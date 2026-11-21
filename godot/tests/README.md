# Regression checks

From the repository root with Godot 4 on PATH:

```powershell
godot --headless --path godot --editor --import
godot --headless --path godot res://tests/RaceRegression.tscn
godot --headless --path godot res://tests/RewardsRegression.tscn
godot --headless --path godot res://tests/FeaturesRegression.tscn
godot --headless --path godot res://tests/FixesRegression.tscn
godot --headless --path godot res://tests/AdsRegression.tscn
godot --headless --path godot res://tests/GfxRegression.tscn
godot --headless --path godot res://tests/PhysicsRegression.tscn
godot --headless --path godot res://tests/AudioRegression.tscn
godot --headless --path godot res://tests/RoadRegression.tscn
```

`GfxRegression` (0.8.0) covers the graphics preset table, the Auto benchmark
mapping, the dynamic-resolution state machine and applying every preset to a
live Game. `PhysicsRegression` covers tyre grip by surface (dry / wet /
puddle / aquaplaning), wet vs dry braking, braking at 30/60/120/144 FPS,
same-seed determinism, SLIP1 codes racing with the legacy physics, that the
render systems never consume `run_rng`, and the seeded fog banks.

Visual QA for the renderer (graphical, writes `godot/shots`, git-ignored):

```powershell
godot --path godot --fixed-fps 60 res://tests/GfxShots.tscn -- --presets=0,1,2,3
godot --path godot res://tests/GfxShots.tscn -- --presets=0,1,2,3 --perf=1
```

Car normal-map atlases (`art/race/cars_N_n.png`) are regenerated with
`godot --path godot res://tests/BakeRaceNormals.tscn -- --bake-race-normals`.

`RaceRegression` covers touch ownership and cancellation, pause/resume, focus
loss, tutorial timing and hints, traffic appearances, and 2D/3D atlas lifetimes.

`RewardsRegression` covers repeated coin collection and real tutorial rewinds,
equal slipstream scores and particle emission over equal durations at
30/60/120/144 FPS, Back through settings and pause during a lesson, and the
menu version matching project settings. Brake, overheat, slipstream and rain
particles are tested separately with a fixed random seed. The navigation fixture
intercepts persistence so a failed test cannot mark the user's tutorial complete.
Neither suite writes the player's save file.

`AdsRegression` drives `AdsService` with a fake Yandex plugin: demo units in
debug builds, rewarded preload and retry, the top banner on the menu, garage
and finish screen (UI moved down by its measured height) and during the race
(HUD below the height reserved at race start; a late, failing or taller banner
never moves it mid-race), and the revive offer: 5 s countdown, accept/decline/Back, once per run,
none in duels or the Daily Challenge, none without a loaded ad. The Android
SDK itself is not exercised on desktop.

Use Godot 4.7.2 (the version `build_apk.bat` builds with).

`RoadRegression` covers traffic lane changes (spontaneous rate, an indicator
only for a move checked as safe and then completed or switched off at once,
no lane change into the space ahead of or beside the player with a gap scaled
by closing speed, a 45 s seeded run), the staged road-works zone (sign/arrows/
cones/STOP layout scaled by speed, knocking cones and signs for points, STOP
barrier crash with Chrono-Shield and revive, traffic waiting behind the
closure, same-seed determinism) and the Auto graphics choice (GPU tiers,
vsync-bound frames, the loading spike).
`AudioRegression` checks the bus layout and routing (every game bus follows
the SFX volume/mute), that all baked OGG assets load with loops flagged, engine
data for all nine cars, the rpm/gear model, a driven race through rain, storm,
nitro, braking and a crash with traffic voices assigned, and the volume
settings. It cannot judge how anything sounds.

For a graphical frame-time sample on the current computer:

```powershell
godot --path godot res://tests/RaceRegression.tscn --disable-vsync --fixed-fps 60 -- --benchmark
```

Desktop checks do not substitute for testing performance and input on Android.
