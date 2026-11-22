# Inuki – The Tale of a Ninja (Godot 4)

Mac/desktop port of the HTML game. Everything is drawn in code: pixel backgrounds are generated at startup, characters are skeletal rigs, sounds are synthesized.

## Run on Mac
1. Install **Godot 4.3+** (standard version) from https://godotengine.org/download/macos
2. Open Godot → **Import** → select `inuki-godot/project.godot`
3. Press **▶ (F5)** to play.

To build a real `.app`: *Project → Export → Add… macOS*, install export templates when asked, then **Export Project**.

## Controls
| Action | Keyboard + mouse | Controller |
|---|---|---|
| Move | A / D (or arrows) | Left stick |
| Aim (slow-mo) | Hold left mouse, point at where to strike | Hold RT / RB, aim with right stick |
| Strike | Release mouse | Release trigger |
| Keyboard-only aim | Hold J or K, steer with WASD, release | – |
| Raijin (lightning, 2x dmg) | E / Space / right mouse | Y |
| Fullscreen | F | – |
