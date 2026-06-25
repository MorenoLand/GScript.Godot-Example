# GScript.Godot-Example

Godot example project for classic online RPG-style fan tooling: script runtime pieces, level loading, tileset collision, animation playback, body recoloring, player movement, camera, and frame sounds.

## Run

1. Open the project in Godot 4.
2. Open `scenes/Main.tscn`.
3. Run the scene.

## Controls

- Move: WASD or arrows
- Sword: Space
- Grab: E
- Pull: hold E and move backward
- Zoom: Alt+8 / Alt+9

## Layout

- `assets/ganis` stores animation files.
- `assets/images` stores player/body/sprite PNGs.
- `assets/sounds` stores WAV/MP3/OGG files.
- `levels` stores `.nw`/`.gmap` files.
- `tilesets` stores level tilesets like `pics1.png`.
- `scripts/TGani.gd` parses and draws animation files.
- `scripts/TPlayer.gd` handles movement, animation switching, recoloring, camera, and sounds.
- `scripts/TLevel.gd` loads `.nw` levels and `.gmap` grids, draws merged level tiles, and checks tile blocking.
- `scripts/TArrays.gd` provides the classic tile type table.

## License

MIT. Use, modify, redistribute, sell, fork, embed, or strip it down.
