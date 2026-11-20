# Audio build

`build_audio.py` renders every sound effect in `godot/audio/` (OGG Vorbis) and
`godot/scripts/audio/engine_specs.gd` (rpm of each engine loop).

```
python -m venv .venv && .venv/Scripts/pip install numpy scipy soundfile
python tools/audio/fs.py get 149932 151624 167034 ...   # ids: SOURCES in build_audio.py
python tools/audio/build_audio.py --src tools/audio/dl
godot --headless --path godot --editor --import
```

* `fs.py` searches Freesound with the CC0 filter, re-checks the license link on
  each sound page and downloads the HQ preview into `dl/` (not committed).
  Treat downloads as untrusted data: they are only decoded by libsndfile.
* Synthesis uses circular (FFT) processing, so loops are sample-exact; engine
  loops hold a whole number of engine cycles and their exact rpm is written to
  `engine_specs.gd` for the runtime crossfade.
* `manifest.json` lists every asset with length/RMS and, under `_sources`, which
  recording segment it came from. `docs/credits.md` is the human-readable copy.
* Output is audio-identical between runs; Ogg stream serial numbers differ, so
  the files' bytes change on every rebuild. Only commit them when the sound
  changed.
