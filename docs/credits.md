# Credits and licenses

## Sound

All sound effects ship as OGG Vorbis under `godot/audio/`. They are built by
`tools/audio/build_audio.py` (see `tools/audio/README.md`).

**Synthesised in-house** (no third-party material): all nine player engines
(`engine/*_on.ogg`, `engine/*_off.ogg`), traffic engines (`traffic/eng_*`),
tyre roll dry/wet, air rush, brake scrub, ABS, hot brakes, nitro sustain and
blow-off, slingshot ready, chrono shield, impact sub/knock, road joints,
guard-rail puff, truck buffet, all UI sounds, rewind and the music (rendered at
runtime in `scripts/sfx.gd`).

**Recordings**: every file below is released under
[Creative Commons 0 1.0 (public domain dedication)](https://creativecommons.org/publicdomain/zero/1.0/).
The license was checked on each sound's Freesound page on 2026-11-20 before
download (the page's license link points to `publicdomain/zero/1.0`). CC0 needs
no attribution; the authors are listed as thanks and for traceability. The
files were cut, filtered, loudness-matched and looped; the exact segments are
recorded in `tools/audio/manifest.json`.

| Freesound | Author | Title | Used for |
|---|---|---|---|
| [149932](https://freesound.org/s/149932/) | bryceisbell | Birds From A Balcony At Sunrise In Denton Texas [032912].WAV | `amb/birds` |
| [151624](https://freesound.org/s/151624/) | qubodup | Clank Car Crash Collision | `impact/clank` |
| [167034](https://freesound.org/s/167034/) | soundrecorder7 | Light Rain | `amb/rain_light` |
| [199525](https://freesound.org/s/199525/) | Ermens | abrupt stopping car on wet ground.aif | `brake/skid_wet` |
| [278132](https://freesound.org/s/278132/) | warrenXG | MetalScrape4.wav | `impact/scrape` |
| [321482](https://freesound.org/s/321482/) | dslrguide | Metal Hit 2 | `impact/metal_hit` |
| [340539](https://freesound.org/s/340539/) | mickyman5000 | Car_Door_Hit.wav | `impact/door_hit` |
| [385104](https://freesound.org/s/385104/) | softwalls | XY_City hum_Night_River_ambience.wav | `amb/city_hum` |
| [405422](https://freesound.org/s/405422/) | logancircle2 | Beltway Underpass.mp3 | `amb/underpass` |
| [465397](https://freesound.org/s/465397/) | JPBILLINGSLEYJR | One car passing by | `traffic/pass_dry` |
| [473864](https://freesound.org/s/473864/) | Kragnour | DistantThunder.wav | `amb/thunder_far_0` |
| [487143](https://freesound.org/s/487143/) | craigsmith | R29-28-Large Metal Vehicle Crashes.wav | `impact/crash_metal` |
| [495866](https://freesound.org/s/495866/) | Yakobb1 | City Ambience Distant Stereo.wav | `amb/city_night` |
| [518090](https://freesound.org/s/518090/) | Tim_Verberne | Strong Wind 03.wav | `amb/wind` |
| [540451](https://freesound.org/s/540451/) | Za-Games | Breaking Glass 2 | `impact/glass_0` |
| [563021](https://freesound.org/s/563021/) | cookies+policy | Water Puddle Splash | `road/splash` |
| [592388](https://freesound.org/s/592388/) | magnuswaker | Car Crash (with Glass) | `impact/crash_heavy` |
| [613311](https://freesound.org/s/613311/) | eZZin | Windowcrash.wav | `impact/glass_1` |
| [614627](https://freesound.org/s/614627/) | johnnydekk | screeching tyres / tires | `brake/squeal_dry` |
| [648786](https://freesound.org/s/648786/) | klau78 | Cars and trucks passing by on a wet road | `traffic/pass_wet`, `traffic/pass_wet_heavy` |
| [712914](https://freesound.org/s/712914/) | greyfeather | distant rumbling thunderstorm, ambience | `amb/thunder_far_1` |
| [768870](https://freesound.org/s/768870/) | Gustavo_C | heavy_rain_outside | `amb/rain_heavy` |
| [797835](https://freesound.org/s/797835/) | modusmogulus | Car Antilag (No cleanup, 32float) | `engine/pop_0` … `engine/pop_4` |
| [801435](https://freesound.org/s/801435/) | okpato123 | air brake sound effect | `traffic/air_brake` |
| [812685](https://freesound.org/s/812685/) | AudioPapkin | Sound Design Elements Whoosh SFX 048 | layer in `nitro/ignite` |
| [812689](https://freesound.org/s/812689/) | AudioPapkin | Sound Design Elements Whoosh SFX 052 | layer in `nitro/sling_snap` |
| [840628](https://freesound.org/s/840628/) | loganzsound | Closeup Thunder Strike 01 | `amb/thunder_close` |
| [849916](https://freesound.org/s/849916/) | leocb | Light Rain inside a car, driver seat | `amb/rain_roof` |
| [861757](https://freesound.org/s/861757/) | bassimat | Wind - Low Frequency, Warm and Strong | `amb/storm_low` |

## Fonts

See the font files under `godot/fonts/` (unchanged since earlier releases).
