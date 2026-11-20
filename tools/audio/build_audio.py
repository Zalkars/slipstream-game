"""Offline audio build for SLIPSTREAM 0.8.0.

Renders every sound asset the game ships into godot/audio/ as OGG Vorbis:

* synthesised assets (player engines for all nine cars, traffic engines, tyres,
  nitro, UI, impacts' sub layers ...) - built with circular (FFT) processing so
  every loop is sample-exact seamless;
* processed recordings (rain, thunder, birds, city, wind, crash/glass, tyre
  squeal, splash, air brake ...) cut from CC0 Freesound files listed in
  SOURCES below and in docs/credits.md.

Requirements: Python 3.10+, numpy, scipy, soundfile (libsndfile with Vorbis).

    python tools/audio/fs.py get <ids...>            # fetch + verify CC0 sources
    python tools/audio/build_audio.py --src <dir with <id>.ogg files>

The source recordings are not committed (they are large); only the processed
derivatives under godot/audio/ are. Re-running the script is deterministic.
"""
import argparse
import json
import os
import zlib

import numpy as np
import soundfile as sf
from scipy import signal

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "godot", "audio")
SR = 32000          # synthesised assets
SRR = 44100         # processed recordings
SRC = ""

# Freesound CC0 sources: id -> (author, title). Every id was checked on its page
# (license link = creativecommons.org/publicdomain/zero/1.0/) before use.
SOURCES = {
    "167034": ("soundrecorder7", "Light Rain"),
    "768870": ("Gustavo_C", "heavy_rain_outside"),
    "849916": ("leocb", "Light Rain inside a car, driver seat"),
    "840628": ("loganzsound", "Closeup Thunder Strike 01"),
    "473864": ("Kragnour", "DistantThunder.wav"),
    "712914": ("greyfeather", "distant rumbling thunderstorm, ambience"),
    "149932": ("bryceisbell", "Birds From A Balcony At Sunrise In Denton Texas [032912].WAV"),
    "495866": ("Yakobb1", "City Ambience Distant Stereo.wav"),
    "385104": ("softwalls", "XY_City hum_Night_River_ambience.wav"),
    "518090": ("Tim_Verberne", "Strong Wind 03.wav"),
    "861757": ("bassimat", "Wind - Low Frequency, Warm and Strong"),
    "405422": ("logancircle2", "Beltway Underpass.mp3"),
    "614627": ("johnnydekk", "screeching tyres / tires"),
    "199525": ("Ermens", "abrupt stopping car on wet ground.aif"),
    "278132": ("warrenXG", "MetalScrape4.wav"),
    "592388": ("magnuswaker", "Car Crash (with Glass)"),
    "487143": ("craigsmith", "R29-28-Large Metal Vehicle Crashes.wav"),
    "321482": ("dslrguide", "Metal Hit 2"),
    "151624": ("qubodup", "Clank Car Crash Collision"),
    "340539": ("mickyman5000", "Car_Door_Hit.wav"),
    "540451": ("Za-Games", "Breaking Glass 2"),
    "613311": ("eZZin", "Windowcrash.wav"),
    "563021": ("cookies+policy", "Water Puddle Splash"),
    "801435": ("okpato123", "air brake sound effect"),
    "797835": ("modusmogulus", "Car Antilag (No cleanup, 32float)"),
    "465397": ("JPBILLINGSLEYJR", "One car passing by"),
    "648786": ("klau78", "Cars and trucks passing by on a wet road"),
    "812685": ("AudioPapkin", "Sound Design Elements Whoosh SFX 048"),
    "812689": ("AudioPapkin", "Sound Design Elements Whoosh SFX 052"),
}

MANIFEST = {}


# --------------------------------------------------------------------------- io

def write(name, x, sr, quality=0.42, meta=None):
    """Write mono (n,) or stereo (n, 2) float audio as OGG Vorbis."""
    path = os.path.join(OUT, name + ".ogg")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    x = np.asarray(x, dtype=np.float64)
    pk = np.max(np.abs(x)) + 1e-12
    if pk > 0.89:
        # -1 dBFS ceiling: Vorbis overshoots peaks by up to ~1 dB.
        x = x * (0.89 / pk)
    data = x.astype(np.float32)
    # libsndfile's Vorbis encoder overflows the stack on big single writes:
    # feed it in small blocks.
    with sf.SoundFile(path, "w", sr, 1 if x.ndim == 1 else x.shape[1], format="OGG",
                      subtype="VORBIS", compression_level=1.0 - quality) as fh:
        for i in range(0, len(data), 4096):
            fh.write(data[i:i + 4096])
    mono = x if x.ndim == 1 else x.mean(axis=1)
    rms = 20 * np.log10(np.sqrt(np.mean(mono ** 2)) + 1e-12)
    entry = {"len": round(len(x) / sr, 3), "rms_db": round(float(rms), 1),
             "ch": 1 if x.ndim == 1 else 2, "sr": sr}
    if meta:
        entry.update(meta)
    MANIFEST[name] = entry


def load(sid, sr=SRR, mono=False):
    x, s = sf.read(os.path.join(SRC, sid + ".ogg"), always_2d=True)
    if s != sr:
        g = np.gcd(int(s), int(sr))
        x = signal.resample_poly(x, sr // g, int(s) // g, axis=0)
    if mono:
        return x.mean(axis=1)
    if x.shape[1] == 1:
        x = np.repeat(x, 2, axis=1)
    return x


# ---------------------------------------------------------------- processing

def seg(x, t0, t1, sr=SRR):
    return x[int(t0 * sr):int(t1 * sr)].copy()


def fades(x, fin, fout, sr=SRR):
    x = x.copy()
    a = int(fin * sr)
    b = int(fout * sr)
    if a > 0:
        r = np.sin(np.linspace(0, np.pi / 2, a)) ** 2
        x[:a] = (x[:a].T * r).T
    if b > 0:
        r = np.cos(np.linspace(0, np.pi / 2, b)) ** 2
        x[-b:] = (x[-b:].T * r).T
    return x


def sos_filter(x, kind, fc, sr, order=2):
    sos = signal.butter(order, fc, btype=kind, fs=sr, output="sos")
    return signal.sosfiltfilt(sos, x, axis=0)


def rms_norm(x, target_db):
    m = x if x.ndim == 1 else x.mean(axis=1)
    r = np.sqrt(np.mean(m ** 2)) + 1e-12
    return x * (10 ** (target_db / 20) / r)


def peak_norm(x, target_db=-1.0):
    return x * (10 ** (target_db / 20) / (np.max(np.abs(x)) + 1e-12))


def make_loop(x, xfade, sr=SRR):
    """Equal-power crossfade of the tail into the head: result loops seamlessly."""
    n = int(xfade * sr)
    body = x[:-n].copy()
    tail = x[-n:]
    w = np.linspace(0, 1, n)
    fi = np.sin(w * np.pi / 2)
    fo = np.cos(w * np.pi / 2)
    body[:n] = (body[:n].T * fi).T + (tail.T * fo).T
    return body


def steadiest(x, win, sr=SRR, hop=0.1, lo=None, hi=None):
    """Start time of the window whose short-term loudness varies the least."""
    m = x if x.ndim == 1 else x.mean(axis=1)
    h = int(hop * sr)
    n = len(m) // h
    db = 20 * np.log10(np.sqrt(np.mean(m[:n * h].reshape(n, h) ** 2, axis=1)) + 1e-9)
    w = int(win / hop)
    a = int((lo or 0) / hop)
    b = int((hi or len(m) / sr) / hop) - w
    best, best_s = a, 1e9
    for i in range(a, max(a + 1, b)):
        s = db[i:i + w]
        score = s.std() + max(0.0, s.max() - np.median(s) - 6) * 0.5
        if score < best_s:
            best, best_s = i, score
    return best * hop


def stereoize(m, offset, sr=SRR):
    """Mono loop -> decorrelated stereo by pairing it with a rotated copy."""
    r = np.roll(m, int(offset * sr))
    return np.stack([m, r], axis=1)


# ------------------------------------------------------------------ synthesis

def fft_shape(x, gain_fn, sr=SR):
    n = len(x)
    f = np.fft.rfftfreq(n, 1.0 / sr)
    return np.fft.irfft(np.fft.rfft(x) * gain_fn(np.maximum(f, 1e-3)), n)


def lp(f, fc, order=2):
    return 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))


def hp(f, fc, order=2):
    return 1.0 / np.sqrt(1.0 + (fc / f) ** (2 * order))


def peak(f, f0, q, g):
    return g / (1.0 + ((f / f0 - f0 / f) * q) ** 2)


def comb(f, delay, r, sr=SR):
    return np.abs(1.0 / (1.0 - r * np.exp(-2j * np.pi * f * delay)))


def qfreq(f, n, sr=SR):
    """Quantise a frequency to a whole number of periods in an n-sample loop."""
    cyc = max(1, round(f * n / sr))
    return cyc * sr / n


def periodic_sine(n, f, phase=0.0, sr=SR):
    t = np.arange(n) / sr
    return np.sin(2 * np.pi * qfreq(f, n, sr) * t + phase)


def soft(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


def onepole_env(n, attack, decay, sr=SR):
    t = np.arange(n) / sr
    return (1 - np.exp(-t / max(attack, 1e-4))) * np.exp(-t / decay)


def noise(n, rng):
    return rng.standard_normal(n)


# --- engines -------------------------------------------------------------------

V8_CROSS = [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875]
ENGINES = {
    # silhouette: character
    "hatch": dict(cyl=4, firing=[0, .25, .5, .75], bank=[0, 0, 0, 0], amp=[1, .94, .98, .9],
                  idle=850, redline=6900, shift=6300, refs=[1700, 3500, 6100], tau=0.55,
                  form=[(190, 2.0, 1.0), (560, 2.5, .8), (1500, 3, .55)], lpf=3600, pipe=0.0042,
                  roar=.30, clatter=0, valve=.05, turbo=0, turbo_hz=0, crackle=0, jitter=.05, drive=1.8,
                  sub=.25, pops=0.0, vol=-1.0),
    "van": dict(cyl=4, firing=[0, .25, .5, .75], bank=[0, 0, 0, 0], amp=[1, .9, .96, .86],
                idle=760, redline=4700, shift=4200, refs=[1300, 2500, 4100], tau=0.75,
                form=[(120, 1.8, 1.0), (380, 2.0, .7), (1100, 2.5, .35)], lpf=2600, pipe=0.006,
                roar=.18, clatter=.55, valve=.02, turbo=.05, turbo_hz=3900, crackle=0, jitter=.07, drive=1.6,
                sub=.4, pops=0.0, vol=0.0),
    "sedan": dict(cyl=6, firing=[0, 1 / 6, 2 / 6, .5, 4 / 6, 5 / 6], bank=[0] * 6, amp=[1, .97, .99, .96, 1, .95],
                  idle=720, redline=7000, shift=6500, refs=[1800, 3800, 6300], tau=0.45,
                  form=[(150, 1.8, 1.0), (460, 2.2, .7), (1150, 2.8, .5)], lpf=4200, pipe=0.0048,
                  roar=.22, clatter=0, valve=.03, turbo=.035, turbo_hz=5200, crackle=0, jitter=.03, drive=1.5,
                  sub=.3, pops=0.0, vol=-0.5),
    "offroad": dict(cyl=6, firing=[0, 1 / 6, 2 / 6, .5, 4 / 6, 5 / 6], bank=[0, 1, 0, 1, 0, 1],
                    amp=[1, .86, .95, .82, .98, .84],
                    idle=760, redline=6200, shift=5600, refs=[1600, 3200, 5500], tau=0.6,
                    form=[(115, 1.6, 1.0), (340, 2.0, .9), (900, 2.4, .5)], lpf=3200, pipe=0.0056,
                    roar=.32, clatter=.08, valve=.03, turbo=0, turbo_hz=0, crackle=.05, jitter=.08, drive=2.0,
                    sub=.45, pops=0.0, vol=0.0),
    "muscle": dict(cyl=8, firing=V8_CROSS, bank=[0, 1, 1, 0, 1, 0, 0, 1], amp=[1, .72, .9, .66, 1, .78, .86, .7],
                   idle=760, redline=6600, shift=6000, refs=[1500, 3200, 5800], tau=0.65,
                   form=[(72, 1.4, 1.0), (230, 1.8, .95), (620, 2.2, .45)], lpf=2800, pipe=0.0068,
                   roar=.30, clatter=0, valve=.02, turbo=0, turbo_hz=0, crackle=.35, jitter=.10, drive=2.4,
                   sub=.7, pops=0.55, vol=1.0),
    "pickup": dict(cyl=8, firing=V8_CROSS, bank=[0, 1, 1, 0, 1, 0, 0, 1], amp=[1, .85, .94, .8, 1, .86, .9, .82],
                   idle=700, redline=5600, shift=5000, refs=[1400, 2800, 4900], tau=0.75,
                   form=[(62, 1.4, 1.0), (190, 1.8, .9), (500, 2.0, .4)], lpf=2400, pipe=0.0075,
                   roar=.26, clatter=.05, valve=.02, turbo=0, turbo_hz=0, crackle=.12, jitter=.08, drive=2.0,
                   sub=.75, pops=0.15, vol=0.5),
    "sport": dict(cyl=4, firing=[0, .25, .5, .75], bank=[0, 0, 0, 0], amp=[1, .97, .99, .95],
                  idle=950, redline=8300, shift=7800, refs=[2200, 4600, 7700], tau=0.38,
                  form=[(260, 2.4, 1.0), (820, 2.6, .9), (2300, 3.0, .6)], lpf=5600, pipe=0.0034,
                  roar=.42, clatter=0, valve=.05, turbo=.11, turbo_hz=6200, crackle=.45, jitter=.04, drive=2.6,
                  sub=.25, pops=0.85, vol=0.0),
    "hyper": dict(cyl=10, firing=[i / 10 for i in range(10)], bank=[0, 1] * 5,
                  amp=[1, .95, .98, .93, 1, .96, .97, .94, .99, .95],
                  idle=1050, redline=9300, shift=8900, refs=[2600, 5400, 8800], tau=0.28,
                  form=[(320, 2.6, .9), (950, 3.0, 1.0), (2700, 3.2, .8)], lpf=7200, pipe=0.0029,
                  roar=.40, clatter=0, valve=.06, turbo=0, turbo_hz=0, crackle=.4, jitter=.03, drive=2.8,
                  sub=.2, pops=1.0, vol=0.5),
}
EV = dict(refs=[3000, 7200, 13500], redline=15000, idle=0, orders=[(8, .55), (16, .32), (24, .16), (36, .08)],
          inverter=[(1340, .07), (2680, .035)], vol=-2.0)


def pulse_shape(t, tau):
    """Exhaust pressure pulse: fast rise, slower decay, then a rarefaction dip."""
    t = np.maximum(t, 0.0)
    a = (t / tau) * np.exp(1.0 - t / tau)
    b = (t / (3.2 * tau)) * np.exp(1.0 - t / (3.2 * tau))
    return a - 0.42 * b


def engine_loop(p, rpm, load, seed, seconds=1.7):
    rng = np.random.default_rng(seed)
    f_cycle = rpm / 120.0
    k = max(2, int(round(seconds * f_cycle)))
    n = int(round(k * SR / f_cycle))
    rpm_act = 120.0 * SR * k / n
    f_cycle = rpm_act / 120.0
    cyl = p["cyl"]
    # Pulses get shorter as revs climb (less time per stroke).
    tau = p["tau"] / 1000.0 * (0.55 + 0.45 * (2500.0 / max(rpm, 900.0)) ** 0.5)
    L = int(SR * tau * 14)
    banks = [np.zeros(n), np.zeros(n)]
    env_train = np.zeros(n)
    la = 0.42 + 0.58 * load
    for c in range(k):
        for i in range(cyl):
            t0 = (c + p["firing"][i]) / f_cycle
            s = t0 * SR
            idx = int(np.floor(s))
            frac = s - idx
            tt = (np.arange(L) - frac) / SR
            a = p["amp"][i] * la * (1.0 + rng.normal(0.0, p["jitter"]))
            pos = (idx + np.arange(L)) % n
            np.add.at(banks[p["bank"][i]], pos, a * pulse_shape(tt, tau))
            np.add.at(env_train, pos[:min(L, 4)], a)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    f = np.maximum(f, 1e-3)
    form = sum(peak(f, f0 * (0.9 + 0.2 * load), q, g) for f0, q, g in p["form"])
    lpf = p["lpf"] * (0.62 + 0.38 * load)
    base = (0.35 + form) * lp(f, lpf, 2) * hp(f, 28.0, 2)
    out = np.zeros(n)
    for b, delay in enumerate([p["pipe"], p["pipe"] * 1.37]):
        if not banks[b].any():
            continue
        H = base * comb(f, delay, 0.42)
        out += np.fft.irfft(np.fft.rfft(banks[b]) * H, n)
    out /= np.sqrt(np.mean(out ** 2)) + 1e-9
    # Combustion roar: noise modulated by the firing envelope.
    menv = np.fft.irfft(np.fft.rfft(env_train) * lp(f, f_cycle * cyl * 1.6, 1), n)
    menv = np.maximum(menv, 0)
    menv /= menv.max() + 1e-9
    roar = fft_shape(noise(n, rng), lambda ff: peak(ff, 900 + rpm * 0.25, 0.8, 1.0) * lp(ff, 5000, 2))
    roar *= (0.35 + 0.65 * menv)
    roar /= np.sqrt(np.mean(roar ** 2)) + 1e-9
    out += roar * p["roar"] * (0.45 + 0.55 * load)
    if p["clatter"] > 0:
        cl = fft_shape(noise(n, rng), lambda ff: peak(ff, 3200, 1.2, 1.0))
        sharp = np.fft.irfft(np.fft.rfft(env_train) * lp(f, 900, 1), n)
        sharp = np.maximum(sharp, 0) ** 2
        sharp /= sharp.max() + 1e-9
        cl *= sharp
        cl /= np.sqrt(np.mean(cl ** 2)) + 1e-9
        out += cl * p["clatter"] * (0.6 + 0.4 * load)
    if p["valve"] > 0:
        ticks = np.zeros(n)
        cam = f_cycle * cyl
        for j in range(int(cam * n / SR)):
            ticks[int(j * SR / cam + 0.37 * SR / cam) % n] = 1.0
        tk = np.fft.irfft(np.fft.rfft(ticks) * peak(f, 5200, 1.5, 1.0), n)
        tk /= np.sqrt(np.mean(tk ** 2)) + 1e-9
        out += tk * p["valve"]
    if p["turbo"] > 0 and load > 0.5:
        ft = p["turbo_hz"] * (rpm / p["redline"]) ** 0.6
        wh = periodic_sine(n, ft) * (1 + 0.04 * periodic_sine(n, 6.0)) + 0.3 * periodic_sine(n, ft * 2.01)
        out += wh * p["turbo"] * 3.0 * (rpm / p["redline"])
    if p["sub"] > 0:
        out += periodic_sine(n, f_cycle * cyl / 2.0) * p["sub"] * 0.5 * (0.5 + 0.5 * load)
    if p["crackle"] > 0 and load < 0.5:
        # Overrun burble: sparse, irregular little pops in the exhaust.
        cr = np.zeros(n)
        rate = 9.0 * p["crackle"] * (1.2 - rpm / p["redline"])
        for _ in range(int(rate * n / SR)):
            t0 = rng.integers(0, n)
            ln = int(SR * rng.uniform(0.004, 0.012))
            burst = rng.standard_normal(ln) * np.exp(-np.arange(ln) / (ln * 0.3)) * rng.uniform(0.4, 1.0)
            cr[(t0 + np.arange(ln)) % n] += burst
        cr = fft_shape(cr, lambda ff: peak(ff, 700, 0.7, 1.0) + peak(ff, 2200, 1.0, .5))
        cr /= np.sqrt(np.mean(cr ** 2)) + 1e-9
        out += cr * p["crackle"] * 0.9
    out /= np.sqrt(np.mean(out ** 2)) + 1e-9
    out = soft(out * 0.30, p["drive"] * (0.75 + 0.5 * load))
    # Presence: phone speakers start around 300 Hz, so the rpm-tracking
    # harmonics in 0.4-3 kHz carry the engine; keep the lows but lift these.
    out = fft_shape(out, lambda ff: lp(ff, min(13000, lpf * 2.4), 3) * hp(ff, 30, 2)
                    * (0.8 + peak(ff, 1300, 0.33, p.get("presence", 2.4))))
    return rms_norm(out, -17.0), rpm_act


def ev_loop(rpm, load, seed, seconds=1.6):
    rng = np.random.default_rng(seed)
    n = int(SR * seconds)
    fr = rpm / 60.0
    out = np.zeros(n)
    for order, a in EV["orders"]:
        g = a * (0.5 + 0.5 * load) if order > 10 else a
        out += periodic_sine(n, fr * order, rng.uniform(0, 6.28)) * g
        out += periodic_sine(n, fr * order * 1.012, rng.uniform(0, 6.28)) * g * 0.15
    # Gear mesh with sidebands, and the fixed inverter whine.
    gm = periodic_sine(n, fr * 23) * (1 + 0.3 * periodic_sine(n, fr))
    out += gm * (0.10 if load > 0.5 else 0.05)
    for fi, a in EV["inverter"]:
        out += periodic_sine(n, fi) * a * (1.0 if load > 0.5 else 0.6)
    air = fft_shape(noise(n, rng), lambda ff: peak(ff, 1800, 0.6, 1.0) * lp(ff, 6000, 2))
    air /= np.sqrt(np.mean(air ** 2)) + 1e-9
    out += air * 0.08
    hum = periodic_sine(n, 100.0) * 0.05 + periodic_sine(n, 50.0) * 0.06
    out += hum
    if load < 0.5:
        # Regen: a lower, softer second whine family.
        out += periodic_sine(n, fr * 6) * 0.25 + periodic_sine(n, fr * 12) * 0.08
    out = fft_shape(out, lambda ff: lp(ff, 11000, 2) * hp(ff, 35, 2))
    return rms_norm(out, -17.0), float(rpm)


def build_engines():
    meta = {}
    for name, p in ENGINES.items():
        refs = []
        for i, r in enumerate(p["refs"]):
            for load, tag in [(1.0, "on"), (0.15, "off")]:
                x, ract = engine_loop(p, r, load, seed=zlib.crc32(("%s%d%s" % (name, i, tag)).encode()))
                write("engine/%s_%d_%s" % (name, i, tag), x, SR, 0.40)
            refs.append(round(ract, 2))
        meta[name] = {k: p[k] for k in ["idle", "redline", "shift", "pops", "vol"]}
        meta[name]["refs"] = refs
        meta[name]["turbo"] = p["turbo"] > 0
        meta[name]["ev"] = False
    refs = []
    for i, r in enumerate(EV["refs"]):
        for load, tag in [(1.0, "on"), (0.15, "off")]:
            x, ract = ev_loop(r, load, seed=700 + i * 2 + (tag == "off"))
            write("engine/ev_%d_%s" % (i, tag), x, SR, 0.40)
        refs.append(ract)
    meta["ev"] = {"idle": 0, "redline": EV["redline"], "shift": EV["redline"], "pops": 0.0,
                  "vol": EV["vol"], "refs": refs, "turbo": False, "ev": True}
    # Runtime data goes into a GDScript constant: plain .json files are not
    # packed into the APK by the current export filter.
    gd = os.path.join(ROOT, "godot", "scripts", "audio", "engine_specs.gd")
    with open(gd, "w", encoding="utf8", newline="\n") as fh:
        fh.write("extends RefCounted\n\n# Generated by tools/audio/build_audio.py - do not edit by hand.\n"
                 "# refs: exact rpm each engine/<name>_<i>_{on,off}.ogg loop was rendered at.\n\n")
        fh.write("const SPECS := %s\n" % json.dumps(meta, indent="\t"))


TRAFFIC = {
    "car": (dict(ENGINES["hatch"], lpf=2200, roar=.2, valve=0), 2600, .55),
    "suv": (dict(ENGINES["offroad"], lpf=2000, crackle=0), 2300, .6),
    "truck": (dict(ENGINES["van"], cyl=6, firing=[0, 1 / 6, 2 / 6, .5, 4 / 6, 5 / 6], bank=[0] * 6,
                   amp=[1, .9, .95, .88, .97, .9], lpf=1500, clatter=.7, turbo=.06, turbo_hz=3000,
                   form=[(80, 1.4, 1), (260, 1.8, .7), (700, 2, .3)], sub=.6), 1500, .75),
    "van": (dict(ENGINES["van"], lpf=1900), 2100, .6),
    "bus": (dict(ENGINES["van"], cyl=6, firing=[0, 1 / 6, 2 / 6, .5, 4 / 6, 5 / 6], bank=[0] * 6,
                 amp=[1, .93, .96, .9, .98, .92], lpf=1400, clatter=.45, turbo=.12, turbo_hz=2600,
                 form=[(70, 1.4, 1), (230, 1.8, .7), (620, 2, .3)], sub=.6), 1400, .7),
    "sport": (dict(ENGINES["sport"], lpf=3800, crackle=0, turbo=0), 4200, .7),
}


def build_traffic():
    for name, (p, rpm, load) in TRAFFIC.items():
        x, _ = engine_loop(p, rpm, load, seed=zlib.crc32(("traffic" + name).encode()), seconds=1.4)
        write("traffic/eng_%s" % name, x, SR, 0.35)


# --- tyres, air, nitro -----------------------------------------------------------

def build_tyres_air():
    rng = np.random.default_rng(11)
    n = SR * 2
    # Dry tyre roar: rough asphalt, pink-ish with a cavity resonance.
    x = fft_shape(noise(n, rng), lambda f: (f / 200.0) ** -0.45 * hp(f, 60, 2) * lp(f, 2600, 2)
                  * (1 + peak(f, 850, 1.2, 1.4) + peak(f, 140, 1.0, .9)))
    write("tyre/roll_dry", rms_norm(x, -18), SR, 0.35)
    # Wet hiss/spray: bright hiss with surges and droplet grains.
    x = fft_shape(noise(n, rng), lambda f: hp(f, 900, 2) * (1 + peak(f, 3800, .8, 1.2)) * lp(f, 9000, 2))
    surge = 0.75 + 0.18 * periodic_sine(n, 1.5) + 0.07 * periodic_sine(n, 4.5, 1.0)
    x *= surge
    grains = np.zeros(n)
    for _ in range(260):
        t0 = rng.integers(0, n)
        ln = int(SR * rng.uniform(0.003, 0.02))
        grains[(t0 + np.arange(ln)) % n] += rng.standard_normal(ln) * np.exp(-np.arange(ln) / (ln * .3)) * rng.uniform(.3, 1)
    grains = fft_shape(grains, lambda f: peak(f, 2600, .7, 1.0))
    x = x / np.sqrt(np.mean(x ** 2)) + grains / (np.sqrt(np.mean(grains ** 2)) + 1e-9) * 0.45
    write("tyre/roll_wet", rms_norm(x, -18), SR, 0.38)
    # Aerodynamic rush (own car at speed).
    x = fft_shape(noise(n, rng), lambda f: peak(f, 700, .45, 1.0) * lp(f, 4500, 2) * hp(f, 120, 2))
    x *= 0.85 + 0.1 * periodic_sine(n, 0.5) + 0.05 * periodic_sine(n, 3.0)
    write("air/rush", rms_norm(x, -18), SR, 0.35)
    # Brake pad scrub (low friction rumble under braking, no squeal).
    x = fft_shape(noise(n, rng), lambda f: peak(f, 480, 1.6, 1.0) + peak(f, 1400, 2.4, .5) + peak(f, 95, 1.2, .6))
    x *= 0.85 + 0.15 * periodic_sine(n, 11.0)
    write("brake/scrub", rms_norm(x, -18), SR, 0.35)
    # ABS chatter: 14 Hz pulses of pad noise and a low buzz.
    n1 = SR
    env = np.zeros(n1)
    per = n1 // 14
    for j in range(14):
        ln = int(per * 0.55)
        env[j * per:j * per + ln] = np.sin(np.linspace(0, np.pi, ln)) ** 1.5
    a = fft_shape(noise(n1, rng), lambda f: peak(f, 1100, 1.2, 1.0) + peak(f, 2600, 2, .4)) * env
    b = periodic_sine(n1, 72.0) * env * 2.2
    write("brake/abs", rms_norm(a + b * 0.2, -18), SR, 0.35)
    # Hot brakes: hiss with metal stress pings and a soft warning pip.
    n2 = int(SR * 1.2)
    x = fft_shape(noise(n2, rng), lambda f: hp(f, 2500, 2) * lp(f, 9000, 2))
    t = np.arange(n2) / SR
    pings = np.zeros(n2)
    for j in range(6):
        t0 = j / 6.0 * 1.2 + rng.uniform(0, .05)
        tt = t - t0
        pings += np.where(tt > 0, np.sin(2 * np.pi * rng.uniform(2200, 3100) * tt) * np.exp(-np.maximum(tt, 0) * 45), 0)
    pip = periodic_sine(n2, 880.0) * (np.mod(t * 2.5, 1.0) < 0.12)
    x = x / np.sqrt(np.mean(x ** 2)) * 0.6 + pings * 0.5 + pip * 0.12
    write("brake/overheat", rms_norm(x, -19), SR, 0.35)
    # Nitro sustain: jet roar + turbine tone + flutter.
    x = fft_shape(noise(n, rng), lambda f: (peak(f, 320, .6, 1.0) + peak(f, 1600, .9, .5)) * lp(f, 5000, 2))
    x /= np.sqrt(np.mean(x ** 2))
    tone = periodic_sine(n, 2300.0) * 0.16 + periodic_sine(n, 4600.0) * 0.05
    flutter = 0.84 + 0.16 * periodic_sine(n, 34.0)
    rumble = periodic_sine(n, 55.0) * 0.35 + periodic_sine(n, 110.0) * 0.12
    x = soft((x * 0.6 + tone + rumble) * flutter * 0.6, 1.6)
    write("nitro/sustain", rms_norm(x, -17), SR, 0.40)


def chirp(n, f0, f1, curve=1.0, sr=SR):
    k = np.linspace(0, 1, n) ** curve
    fr = f0 + (f1 - f0) * k
    return np.sin(2 * np.pi * np.cumsum(fr) / sr)


def env_ad(n, a, d, sr=SR):
    t = np.arange(n) / sr
    return np.minimum(1.0, t / max(a, 1e-4)) * np.exp(-np.maximum(t - a, 0) / d)


def filt_noise(n, rng, fn):
    return fft_shape(noise(n, rng), fn)


def to_sr(x, src, dst):
    g = np.gcd(src, dst)
    return signal.resample_poly(x, dst // g, src // g)


def build_nitro_specials():
    rng = np.random.default_rng(21)
    # Ignition: valve click, whump (recorded whoosh) and a rising turbine whistle.
    n = int(SR * 1.3)
    click = filt_noise(n, rng, lambda f: peak(f, 3500, 1.5, 1)) * env_ad(n, 0.0005, 0.004)
    whistle = chirp(n, 900, 3400, 0.6) * env_ad(n, 0.25, 0.45) * 0.22
    rush = filt_noise(n, rng, lambda f: peak(f, 1200, .5, 1) * lp(f, 6000, 2)) * env_ad(n, 0.18, 0.5)
    rush /= np.abs(rush).max()
    who = load("812685", SR, mono=True)[:n]
    who = np.pad(who, (0, n - len(who)))
    who /= np.abs(who).max() + 1e-9
    thump = np.sin(2 * np.pi * np.cumsum(np.linspace(85, 38, n)) / SR) * env_ad(n, 0.004, 0.16)
    x = click * 0.6 + whistle + rush * 0.45 + who * 0.55 + thump * 0.7
    write("nitro/ignite", peak_norm(soft(x, 1.3), -1.5), SR, 0.42)
    # Blow-off: pressure dump with valve flutter.
    n = int(SR * 0.8)
    t = np.arange(n) / SR
    x = filt_noise(n, rng, lambda f: hp(f, 1400, 2) * (1 + peak(f, 4200, .8, 1.5)) * lp(f, 11000, 2))
    x /= np.abs(x).max()
    fl = 0.55 + 0.45 * np.sign(np.sin(2 * np.pi * (24 - 10 * t) * t)) * np.exp(-t * 4)
    x = x * env_ad(n, 0.008, 0.22) * fl + chirp(n, 2600, 700) * env_ad(n, 0.01, 0.12) * 0.12
    write("nitro/blowoff", peak_norm(x, -2), SR, 0.42)
    # Slingshot ready: latch click + short pressure hiss + turbine double chirp.
    n = int(SR * 0.42)
    x = filt_noise(n, rng, lambda f: peak(f, 2800, 1.4, 1)) * env_ad(n, 0.0005, 0.006) * 0.9
    x += filt_noise(n, rng, lambda f: hp(f, 2000, 2) * lp(f, 8000, 2)) * env_ad(n, 0.05, 0.08) * 0.25
    x += chirp(n, 1800, 2500, 0.5) * env_ad(n, 0.01, 0.10) * 0.28
    t = np.arange(n) / SR
    x += np.where(t > 0.11, chirp(n, 2400, 3200, 0.5) * env_ad(n, 0.01, 0.12) * 0.30, 0)
    write("nitro/sling_ready", peak_norm(x, -3), SR, 0.42)
    # Slingshot snap: whip crack, recorded whoosh, sub punch and turbine surge.
    n = int(SR * 0.95)
    crack = filt_noise(n, rng, lambda f: peak(f, 4200, 1.0, 1) * hp(f, 1500, 2)) * env_ad(n, 0.0004, 0.012)
    who = load("812689", SR, mono=True)[:n]
    who = np.pad(who, (0, n - len(who)))
    who /= np.abs(who).max() + 1e-9
    punch = np.sin(2 * np.pi * np.cumsum(np.linspace(110, 42, n)) / SR) * env_ad(n, 0.003, 0.11)
    surge = chirp(n, 700, 2800, 0.5) * env_ad(n, 0.06, 0.3) * 0.18
    write("nitro/sling_snap", peak_norm(soft(crack * 0.8 + who * 0.6 + punch * 0.8 + surge, 1.4), -1.5), SR, 0.42)
    # Chrono shield: reverse swell into a glass bell with a time-warp fall.
    n = int(SR * 1.25)
    t = np.arange(n) / SR
    sw_n = int(SR * 0.32)
    sw = filt_noise(sw_n, rng, lambda f: peak(f, 2500, .6, 1)) * np.linspace(0, 1, sw_n) ** 3
    swell = np.zeros(n)
    swell[:sw_n] = sw / (np.abs(sw).max() + 1e-9)
    tb = np.maximum(t - 0.32, 0)
    on = (t >= 0.32)
    bell = sum(np.sin(2 * np.pi * 520 * r * tb) * np.exp(-tb * d) * g
               for r, d, g in [(1, 3.5, .5), (2.76, 5.5, .3), (5.4, 8, .16), (8.93, 12, .08)]) * on
    warp = chirp(n, 1500, 300, 0.7) * env_ad(n, 0.3, 0.35) * 0.15
    sub = np.sin(2 * np.pi * 62 * tb) * np.exp(-tb * 6) * on * 0.6
    write("nitro/shield", peak_norm(swell * 0.5 + bell + warp + sub, -1.5), SR, 0.42)


# --- impacts, road, ui -----------------------------------------------------------

def build_synth_oneshots():
    rng = np.random.default_rng(31)
    # Sub thump that sits under recorded crashes.
    n = int(SR * 0.7)
    x = np.sin(2 * np.pi * np.cumsum(np.linspace(62, 30, n)) / SR) * env_ad(n, 0.003, 0.18)
    x += np.sin(2 * np.pi * 24 * np.arange(n) / SR) * env_ad(n, 0.01, 0.25) * 0.4
    write("impact/sub", peak_norm(x, -1), SR, 0.4)
    # Bumper knock (light rear tap).
    n = int(SR * 0.3)
    fr = np.linspace(80, 40, n)
    x = np.sin(2 * np.pi * np.cumsum(fr) / SR) * env_ad(n, 0.002, 0.07)
    x += filt_noise(n, rng, lambda f: peak(f, 600, .8, 1)) * env_ad(n, 0.001, 0.03) * 0.35
    x += np.sin(2 * np.pi * 190 * np.arange(n) / SR) * env_ad(n, 0.002, 0.04) * 0.2
    write("impact/knock", peak_norm(x, -1), SR, 0.4)
    # Expansion joint, one axle: dull tyre thump plus a little slap.
    for v, (f0, d) in enumerate([(78, 0.05), (66, 0.06)]):
        n = int(SR * 0.22)
        x = np.sin(2 * np.pi * np.cumsum(np.linspace(f0, f0 * 0.6, n)) / SR) * env_ad(n, 0.002, d)
        x += filt_noise(n, rng, lambda f: peak(f, 900, .7, 1) * lp(f, 3000, 2)) * env_ad(n, 0.001, 0.015) * 0.5
        write("road/joint_%d" % v, peak_norm(x, -1), SR, 0.4)
    # Guard-rail post rushing by: a short airy puff.
    n = int(SR * 0.12)
    x = filt_noise(n, rng, lambda f: peak(f, 1600, .7, 1) * hp(f, 400, 2)) * np.sin(np.linspace(0, np.pi, n)) ** 2
    write("road/rail_puff", peak_norm(x, -1), SR, 0.4)
    # Truck/bus wind buffet for close passes.
    n = int(SR * 0.9)
    x = filt_noise(n, rng, lambda f: lp(f, 500, 2) * hp(f, 35, 2)) * np.sin(np.linspace(0, np.pi, n)) ** 2.5
    write("traffic/buffet", peak_norm(x, -1), SR, 0.4)
    # Cut-in "shing" with a reward ping.
    n = int(SR * 0.42)
    k = np.linspace(0, 1, n)
    sh = np.zeros(n)
    for i in range(0, n, 256):
        ln = min(512, n - i)
        fc = 3400 - 2450 * k[i]
        blk = filt_noise(ln, rng, lambda f, fc=fc: peak(f, fc, 2.0, 1))
        sh[i:i + ln] += blk * np.hanning(ln)
    sh *= np.sin(np.pi * k) * (1 - k * 0.25)
    sh /= np.abs(sh).max()
    t = np.arange(n) / SR
    ping = np.sin(2 * np.pi * 1318.5 * t) * np.exp(-12 * t) * .5 + np.sin(2 * np.pi * 2637 * t) * np.exp(-18 * t) * .25
    write("ui/cutin", peak_norm(sh * 0.8 + ping, -2), SR, 0.42)
    # Rewind: tape-spin warble rising.
    n = int(SR * 1.5)
    k = np.linspace(0, 1, n)
    t = np.arange(n) / SR
    tape = np.zeros(n)
    for i in range(0, n, 512):
        ln = min(1024, n - i)
        fc = 380 + 2800 * k[i] ** 2
        tape[i:i + ln] += filt_noise(ln, rng, lambda f, fc=fc: peak(f, fc, 1.6, 1)) * np.hanning(ln)
    tape /= np.abs(tape).max()
    ph = 2 * np.pi * np.cumsum(160 + 580 * k) / SR
    warble = np.sin(ph + np.sin(2 * np.pi * 8 * t) * 0.9) * 0.3
    env = np.sin(np.pi * k) ** 2
    write("ui/rewind", peak_norm((tape * 0.8 + warble) * env, -2), SR, 0.42)


def ui_tail(x, rng, wet=0.14, length=0.35):
    """Shared short 'glass room' tail so every UI sound sits in the same space."""
    n = int(SR * length)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / (SR * length * 0.25))
    ir = fft_shape(ir, lambda f: lp(f, 6000, 1) * hp(f, 300, 1))
    ir /= np.sqrt(np.sum(ir ** 2))
    y = np.convolve(x, ir)
    out = np.pad(x, (0, len(y) - len(x))) + y * wet
    return out


def tone(n, f, decay, partials=((1, 1.0), (2, .25), (3, .08)), attack=0.002):
    t = np.arange(n) / SR
    env = np.minimum(1, t / attack) * np.exp(-t / decay)
    return sum(np.sin(2 * np.pi * f * r * t) * g * np.exp(-t * (r - 1) * 2.5) for r, g in partials) * env


def build_ui():
    rng = np.random.default_rng(41)
    # Click: soft, short, warm tick.
    n = int(SR * 0.05)
    x = tone(n, 1250, 0.010, ((1, .7), (1.8, .25))) + tone(n, 160, 0.012, ((1, .5),))
    write("ui/click", peak_norm(ui_tail(x, rng, 0.08, 0.15), -3), SR, 0.42)
    # Record / confirm: A major arpeggio.
    n = int(SR * 1.1)
    x = np.zeros(n)
    for j, fr in enumerate([880.0, 1108.73, 1318.51, 1760.0]):
        s = int(j * 0.085 * SR)
        x[s:] += tone(n - s, fr, 0.30)[: n - s] * 0.5
    write("ui/record", peak_norm(ui_tail(x, rng, 0.18, 0.5), -2), SR, 0.42)
    # Coin: bright two-note ping (E6 -> A6).
    n = int(SR * 0.32)
    x = tone(n, 1318.5, 0.06) * 0.6
    s = int(0.05 * SR)
    x[s:] += tone(n - s, 1760.0, 0.09)[: n - s] * 0.8
    write("ui/coin", peak_norm(ui_tail(x, rng, 0.12, 0.25), -3), SR, 0.42)
    # Nitro pickup: rising sparkle into the turbine colour of the nitro sounds.
    n = int(SR * 0.5)
    k = np.linspace(0, 1, n)
    x = chirp(n, 440, 1760, 2.0) * np.sin(np.pi * k) ** 2 * 0.6
    x += chirp(n, 880, 3520, 2.0) * np.sin(np.pi * k) ** 2 * 0.15
    x += filt_noise(n, rng, lambda f: hp(f, 3000, 2)) * np.sin(np.pi * k) ** 4 * 0.05
    write("ui/pickup", peak_norm(ui_tail(x, rng, 0.15, 0.3), -3), SR, 0.42)
    # Radar passed: two-tone confirm in the same voice as record.
    n = int(SR * 0.4)
    x = tone(n, 1568.0, 0.07) * 0.6
    s = int(0.08 * SR)
    x[s:] += tone(n - s, 2093.0, 0.1)[: n - s] * 0.7
    write("ui/radar", peak_norm(ui_tail(x, rng, 0.15, 0.3), -3), SR, 0.42)


# --- recordings ------------------------------------------------------------------

def soft_limit(x, knee=0.35):
    """Tame isolated spikes (rain drops, bird chirps) so beds can sit at a useful
    RMS without the encoder peak-normalising them into near silence."""
    a = np.abs(x)
    over = a > knee
    y = x.copy()
    y[over] = np.sign(x[over]) * (knee + (1.0 - knee) * np.tanh((a[over] - knee) / (1.0 - knee)))
    return y


def loop_from(sid, length, xfade, lo=None, hi=None, mono=False, hpf=None, lpf=None, target=-20.0, start=None):
    x = load(sid, SRR, mono=mono)
    if hpf:
        x = sos_filter(x, "highpass", hpf, SRR)
    if lpf:
        x = sos_filter(x, "lowpass", lpf, SRR)
    t0 = start if start is not None else steadiest(x, length + xfade, lo=lo, hi=hi)
    s = seg(x, t0, t0 + length + xfade)
    y = rms_norm(make_loop(s, xfade), target)
    for _ in range(3):
        if np.max(np.abs(y)) <= 0.98:
            break
        y = rms_norm(soft_limit(y / np.max(np.abs(y)) * 0.98), target)
    return y, t0


def oneshot(sid, t0, t1, fin=0.005, fout=0.1, mono=True, hpf=None, lpf=None, target=-1.0):
    x = load(sid, SRR, mono=mono)
    if hpf:
        x = sos_filter(x, "highpass", hpf, SRR)
    if lpf:
        x = sos_filter(x, "lowpass", lpf, SRR)
    return peak_norm(fades(seg(x, t0, t1), fin, fout), target)


def build_recordings():
    used = {}

    def rec(name, sid, info):
        used.setdefault(sid, []).append("%s (%s)" % (name, info))

    # Rain beds (stereo).
    x, t0 = loop_from("167034", 12.0, 1.5, hpf=140)
    write("amb/rain_light", x, SRR, 0.36); rec("amb/rain_light", "167034", "%.1fs loop" % t0)
    m, t0 = loop_from("768870", 12.0, 1.5, mono=True, hpf=120)
    write("amb/rain_heavy", stereoize(m, 5.3), SRR, 0.36); rec("amb/rain_heavy", "768870", "%.1fs loop" % t0)
    m, t0 = loop_from("849916", 10.0, 1.5, mono=True, hpf=90)
    write("amb/rain_roof", stereoize(m, 4.1), SRR, 0.36); rec("amb/rain_roof", "849916", "%.1fs loop" % t0)
    # Thunder.
    x = oneshot("840628", 0.45, 10.5, 0.002, 2.5, mono=False)
    write("amb/thunder_close", x, SRR, 0.40); rec("amb/thunder_close", "840628", "0.45-10.5s")
    x = oneshot("473864", 13.4, 26.0, 0.6, 3.0, mono=False, lpf=2500)
    write("amb/thunder_far_0", x, SRR, 0.38); rec("amb/thunder_far_0", "473864", "13.4-26.0s")
    x = oneshot("712914", 0.0, 6.3, 0.3, 1.8, mono=False, lpf=2500)
    write("amb/thunder_far_1", x, SRR, 0.38); rec("amb/thunder_far_1", "712914", "0-6.3s")
    # Ambience beds (stereo).
    x, t0 = loop_from("149932", 20.0, 2.0, hpf=350)
    write("amb/birds", x, SRR, 0.36); rec("amb/birds", "149932", "%.1fs loop" % t0)
    x, t0 = loop_from("495866", 20.0, 2.0, hpf=40)
    write("amb/city_night", x, SRR, 0.34); rec("amb/city_night", "495866", "%.1fs loop" % t0)
    x, t0 = loop_from("385104", 16.0, 2.0, hpf=35)
    write("amb/city_hum", x, SRR, 0.34); rec("amb/city_hum", "385104", "%.1fs loop" % t0)
    x, t0 = loop_from("518090", 16.0, 2.0, hpf=60)
    write("amb/wind", x, SRR, 0.34); rec("amb/wind", "518090", "%.1fs loop" % t0)
    x, t0 = loop_from("861757", 14.0, 2.0, hpf=25, lpf=1200)
    write("amb/storm_low", x, SRR, 0.34); rec("amb/storm_low", "861757", "%.1fs loop" % t0)
    x, t0 = loop_from("405422", 12.0, 1.5, hpf=40)
    write("amb/underpass", x, SRR, 0.34); rec("amb/underpass", "405422", "%.1fs loop" % t0)
    # Tyres and contact loops (mono).
    x, t0 = loop_from("614627", 1.8, 0.35, lo=15, hi=40, mono=True, hpf=300)
    write("brake/squeal_dry", x, SRR, 0.40); rec("brake/squeal_dry", "614627", "%.1fs loop" % t0)
    x, t0 = loop_from("199525", 3.0, 0.5, mono=True, hpf=150, start=1.9)
    write("brake/skid_wet", x, SRR, 0.40); rec("brake/skid_wet", "199525", "1.9s loop")
    x, t0 = loop_from("278132", 2.4, 0.4, mono=True, hpf=200, start=6.9)
    write("impact/scrape", x, SRR, 0.40); rec("impact/scrape", "278132", "6.9s loop")
    # Impacts (mono so they pan cleanly).
    for name, sid, a, b, fo in [("impact/crash_heavy", "592388", 0.0, 2.2, 0.4),
                                ("impact/crash_metal", "487143", 7.6, 11.3, 0.8),
                                ("impact/metal_hit", "321482", 0.05, 1.4, 0.3),
                                ("impact/clank", "151624", 0.0, 0.54, 0.1),
                                ("impact/door_hit", "340539", 0.0, 0.44, 0.08),
                                ("impact/glass_0", "540451", 0.0, 1.16, 0.15),
                                ("impact/glass_1", "613311", 0.0, 2.05, 0.6),
                                ("road/splash", "563021", 0.3, 3.8, 1.2),
                                ("traffic/air_brake", "801435", 0.9, 2.3, 0.3)]:
        write(name, oneshot(sid, a, b, 0.002, fo, hpf=30), SRR, 0.40)
        rec(name, sid, "%.2f-%.2fs" % (a, b))
    # Exhaust pops: pick the strongest separate transients from the antilag take.
    x = load("797835", SRR, mono=True)
    x = sos_filter(x, "highpass", 80, SRR)
    e = np.abs(x)
    h = int(0.01 * SRR)
    nb = len(e) // h
    blk = e[: nb * h].reshape(nb, h).max(axis=1)
    order = np.argsort(blk)[::-1]
    picks = []
    for i in order:
        if all(abs(i - j) > 15 for j in picks):
            picks.append(i)
        if len(picks) == 5:
            break
    for k, i in enumerate(sorted(picks)):
        t0 = max(0.0, i * 0.01 - 0.01)
        write("engine/pop_%d" % k, peak_norm(fades(seg(x, t0, t0 + 0.16), 0.001, 0.07), -1), SRR, 0.40)
        rec("engine/pop_%d" % k, "797835", "%.2fs" % t0)
    # Pass-bys: dry car pass (peak 0.8 s into the clip), wet pass and a heavy wet pass.
    write("traffic/pass_dry", oneshot("465397", 4.4, 6.7, 0.25, 0.6, hpf=60), SRR, 0.40)
    rec("traffic/pass_dry", "465397", "4.4-6.7s")
    w = load("648786", SRR, mono=True)
    m = w[int(24 * SRR):int(31 * SRR)]
    pk = 24 + np.argmax(np.convolve(m ** 2, np.ones(4410), "same")) / SRR
    write("traffic/pass_wet", oneshot("648786", pk - 0.9, pk + 1.5, 0.3, 0.7, hpf=60), SRR, 0.40)
    rec("traffic/pass_wet", "648786", "%.2f-%.2fs" % (pk - 0.9, pk + 1.5))
    write("traffic/pass_wet_heavy", oneshot("648786", 83.2, 87.2, 0.5, 1.0, hpf=40), SRR, 0.40)
    rec("traffic/pass_wet_heavy", "648786", "83.2-87.2s")
    MANIFEST["_sources"] = {sid: {"author": SOURCES[sid][0], "title": SOURCES[sid][1],
                                  "url": "https://freesound.org/s/%s/" % sid, "license": "CC0 1.0",
                                  "used_for": v} for sid, v in sorted(used.items(), key=lambda kv: int(kv[0]))}
    MANIFEST["_sources"]["812685"] = {"author": "AudioPapkin", "title": SOURCES["812685"][1],
                                      "url": "https://freesound.org/s/812685/", "license": "CC0 1.0",
                                      "used_for": ["nitro/ignite (layer)"]}
    MANIFEST["_sources"]["812689"] = {"author": "AudioPapkin", "title": SOURCES["812689"][1],
                                      "url": "https://freesound.org/s/812689/", "license": "CC0 1.0",
                                      "used_for": ["nitro/sling_snap (layer)"]}


def main():
    global SRC
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="directory holding <freesound id>.ogg source files")
    a = ap.parse_args()
    SRC = a.src
    build_engines()
    build_traffic()
    build_tyres_air()
    build_nitro_specials()
    build_synth_oneshots()
    build_ui()
    build_recordings()
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "manifest.json"), "w",
              encoding="utf8", newline="\n") as fh:
        json.dump(MANIFEST, fh, indent=1, ensure_ascii=False, sort_keys=True)
    total = sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fs in os.walk(OUT) for f in fs if f.endswith(".ogg"))
    print("wrote %d assets, %.2f MB" % (len([k for k in MANIFEST if not k.startswith("_")]), total / 1e6))


if __name__ == "__main__":
    main()
