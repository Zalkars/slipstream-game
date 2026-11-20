"""Freesound CC0 helper: search (CC0 filter), verify license on the sound page, download HQ preview.

usage:
  python -I fs.py search "query words" [pages]
  python -I fs.py get <id> [<id> ...]
Downloads go to ../dl/<id>.ogg and metadata to ../dl/meta.json.
"""
import html, json, os, re, sys, time, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
DL = os.path.join(os.path.dirname(HERE), "dl")
UA = {"User-Agent": "Mozilla/5.0 (asset-license-check)"}


def fetch(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def search(q, pages=1):
    out = []
    for p in range(1, pages + 1):
        url = "https://freesound.org/search/?" + urllib.parse.urlencode({
            "q": q, "f": 'license:"Creative Commons 0"', "s": "Rating (highest first)", "page": p})
        s = fetch(url).decode("utf8", "replace")
        for m in re.finditer(r'class="bw-player"(.*?)tabindex', s, re.S):
            blk = m.group(1)
            g = lambda k: (re.search(k + r'="([^"]*)"', blk) or [None, ""])[1]
            out.append((g("data-sound-id"), g("data-username"), html.unescape(g("data-title")),
                        g("data-duration"), g("data-num-downloads"), g("data-samplerate")))
    for o in out:
        print("%-8s %-22s dur=%-6s dl=%-6s sr=%-7s %s" % (o[0], o[1][:22], o[3], o[4], o[5], o[2][:70]))


def get(sid):
    os.makedirs(DL, exist_ok=True)
    meta_p = os.path.join(DL, "meta.json")
    meta = json.load(open(meta_p)) if os.path.exists(meta_p) else {}
    # The canonical sound URL redirects to /people/<user>/sounds/<id>/.
    req = urllib.request.Request("https://freesound.org/s/%s/" % sid, headers=UA)
    with urllib.request.urlopen(req, timeout=60) as r:
        page_url = r.geturl()
        s = r.read().decode("utf8", "replace")
    lic = re.findall(r'title="Go to the full license text" href="([^"]+)"', s)
    if not lic or "publicdomain/zero" not in lic[0]:
        print(sid, "NOT CC0:", lic)
        return
    title = html.unescape((re.search(r'<meta property="og:title" content="([^"]*)"', s) or [None, ""])[1])
    user = (re.search(r'/people/([^/]+)/sounds/', page_url) or [None, ""])[1]
    m = re.search(r'https://cdn\.freesound\.org/previews/\d+/%s_\d+-lq\.ogg' % sid, s)
    if not m:
        print(sid, "no preview found")
        return
    hq = m.group(0).replace("-lq.ogg", "-hq.ogg")
    data = fetch(hq)
    if data[:4] != b"OggS":
        print(sid, "not an ogg file!")
        return
    fn = os.path.join(DL, "%s.ogg" % sid)
    open(fn, "wb").write(data)
    meta[str(sid)] = {"title": title, "user": user, "page": page_url, "license": lic[0], "file": hq,
                      "bytes": len(data), "fetched": time.strftime("%Y-%m-%d")}
    json.dump(meta, open(meta_p, "w"), indent=1, ensure_ascii=False)
    print(sid, "OK CC0", user, "|", title, "|", len(data), "bytes")


if __name__ == "__main__":
    if sys.argv[1] == "search":
        search(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 1)
    else:
        for a in sys.argv[2:]:
            get(a)
