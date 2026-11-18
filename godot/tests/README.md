# Regression checks

From the repository root with Godot 4 on PATH:

```powershell
godot --headless --path godot --editor --import
godot --headless --path godot res://tests/RaceRegression.tscn
godot --headless --path godot res://tests/RewardsRegression.tscn
```

`RaceRegression` covers touch ownership and cancellation, pause/resume, focus
loss, tutorial timing and hints, traffic appearances, and 2D/3D atlas lifetimes.

`RewardsRegression` covers repeated coin collection and real tutorial rewinds,
equal slipstream scores and particle emission over equal durations at
30/60/120/144 FPS, Back through settings and pause during a lesson, and the
menu version matching project settings. Brake, overheat, slipstream and rain
particles are tested separately with a fixed random seed. The navigation fixture
intercepts persistence so a failed test cannot mark the user's tutorial complete.
Neither suite writes the player's save file.

For a graphical frame-time sample on the current computer:

```powershell
godot --path godot res://tests/RaceRegression.tscn --disable-vsync --fixed-fps 60 -- --benchmark
```

Desktop checks do not substitute for testing performance and input on Android.
