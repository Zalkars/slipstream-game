# Race sprite atlases

`cars_*.png` and `sprites.gd` are generated, committed game resources. They cover
all nine player cars and every traffic body/paint/stripe/trailer/bus-accent
combination. `traffic_palette.gd` is shared with the spawner.

The catalogue has 672 traffic appearances across 11 silhouettes and 24 body
colours, plus the nine player cars: 681 sprites in six atlas pages. Passenger
cars have plain, contrasting-stripe and accent-stripe options; utility vehicles
have plain and striped paint. Trucks and buses use two curated colour pairs per
body colour, drawn from 10 cargo colours and eight bus accents. Both front and
rear traffic spawning use the same `variants()` catalogue as the baker.

Regenerate after changing `car_model.gd`, `traffic_model.gd`, `cars.gd`, the
palette, or race camera/framing. From the repository root (Godot on PATH):

```powershell
godot --path godot --script res://scripts/bake_race_art.gd -- --bake-race-art
godot --headless --path godot --editor --import
godot --headless --path godot res://tests/RaceRegression.tscn
```

The baker needs a graphical Compatibility renderer; headless rendering cannot
read back the car sprites. Gameplay never calls the baker. An unknown appearance
uses the existing 2D drawing until the atlases are regenerated.

The generated manifest stores texture paths, not preloaded textures. `RaceArt`
loads the atlases only when 3D is enabled (before the race or from paused
settings) and releases them when returning to 2D. Appearance descriptors and
rewind snapshots store page indices and rectangles, so they cannot retain GPU
textures. The saved display preference is applied before Game enters the tree,
which avoids even a temporary atlas load when launching in 2D.

Keep the PNG import settings: mipmaps enabled with limit 2. Four pixels of
transparent padding separate sprites to prevent filtering into adjacent cars.
The final atlas is cropped to a power-of-two height to avoid unused GPU memory.

For a desktop frame-time sample (not an Android device benchmark):

```powershell
godot --path godot res://tests/RaceRegression.tscn --disable-vsync --fixed-fps 60 -- --benchmark
```

The tests check steering/braking, touch ownership and cancellation, pause/resume,
focus loss, tutorial timing and hints, atlas unloading/reloading, the
player roster, every catalogue appearance, all 11 silhouettes appearing in
8000 traffic spawn attempts, atlas bounds and absence of runtime
3D bakery nodes. They do not read or write the player's save file.
