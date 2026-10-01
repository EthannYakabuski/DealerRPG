# Release verification

## Automated behavior

The build script rejects nonzero exits and Godot script/runtime errors before export. Tests use separate test saves and never write the player's campaign save.

| Suite | Verified behavior |
| --- | --- |
| `test_game_state.gd` | 94 campaign checks: tutorial sequence, meeting windows, quantity and money accounting, fair-price relationships, referrals, supplier reputation gates and risk, food/capacity, class attendance, parties, recovery work, purchased vehicles, corrupt saves, terminal loss/restart, and a complete earned-money tuition victory. The campaign simulation wins after 56 sales and eight supplier pickups on day three. |
| `test_interface.gd` | 36 checks using the actual scene, buttons and interaction dispatcher: start, packing, tutorial handoff, saving a contact, scheduling, client handoff, market purchase/entry/exit, phone pages, dealership purchase, room-position resume, class attendance, tuition result, and terminal Escape behavior. |
| `test_population.gd` | 63 checks: real scene geometry and patrol sight lines, district jurisdiction, arrest persistence, escape, reload preserving pursuit/arrest progress, body movement/collisions, stamina, skateboard, firearm and ammo accounting, combat reactions, car theft/ownership/safe exits, meeting arrival/reach, validated physical save data and sustained simulation. |
| `test_world.gd` | Original model availability, twelve accessible landmarks, no road/building or pedestrian/building intersections, traffic lane samples on road surfaces, parking, five enter/exit interior transitions, and Compatibility camera-cutaway restoration. |
| `smoke_test.gd` | 62 full-scene checks covering import/animation, world assembly, movement, board, menus, interiors, navigation and lighting. |
| `test_visuals.gd` | 9 animation cache checks covering clip selection, uninterrupted playback, nonlooping actions, missing clips, replacement players and changed libraries. |

Some tests deliberately isolate their domain: interface testing moves patrols away before its staged handoff; population tests separately verify witnessed sales, pursuit and arrest. Campaign balance is tested using time advancement, while browser checks below exercise actual input and rendering.

## Visual iteration

The original previews and all model packs were audited before curation. Native OpenGL screenshots cover title, campus gameplay, backpack, city map, apartment and dusk; an additional whole-map view checks the reference topology. Iterations corrected asset scale, external palette paths, reflective cyan foliage, overexposed lighting, paving face orientation/elevation, parking overlap, road corner continuity, spawn crowding, nighttime readability, HUD contrast, clipped labels, and player occlusion.

The game uses Compatibility-supported cached alpha-material cutaways instead of the unsupported per-instance transparency property. Original building/tree shadows and collisions remain active while the player can be seen through foreground geometry.

The performance pass caches actor animation lookups, redraws the minimap at ten updates per second, and replaces fifty over-detailed streetlamp bulb spheres with one shared low-detail mesh. The bulbs occupy only a few pixels and no longer cast unnecessary shadows.

On this machine's GeForce GT 1030, a five-second unpaused Chrome campus sample after these changes averaged 33 FPS with a 34 ms 95th-percentile frame interval. An earlier sample at the same player position averaged 24 FPS with a 66 ms interval. The clock and pedestrian positions differed between samples, so this is a useful local observation rather than a controlled benchmark or a performance guarantee. Native Compatibility rendering reached 60 FPS in the campus scene. Other browsers, GPUs, resolutions and busy scenes can differ.

## Browser execution

An isolated Chrome profile loaded the actual exported `index.wasm` and game pack from the local HTTP server using WebGL 2. Browser console reports Godot 4.5.1 / Compatibility / Emscripten single-threaded; startup, interactions and reload produced no console errors, exceptions or failed network requests.

Observed input sequence:

1. Start a new story from the title screen.
2. Open backpack with B, pack six bags, close it, and press E beside Milo.
3. Open phone with Tab, save Milo, open his request, and submit the meeting form.
4. Wait through the Agenda, complete the handoff with E, and verify cash/stock/reputation change.
5. Equip the skateboard with Space and move using W; the camera follows and the player remains outside the building collision.
6. Open pause, save, reload the browser, select Continue, and verify time, cash, position and skateboard restore.

Browser screenshots and console reports are generated under ignored `build/screenshots/` and `build/logs/`. A browser-only missing arrow glyph was replaced with ASCII in the release source. This verification targets desktop browsers; touch controls and mobile-device performance are not part of this version.

## Hosting

The repository is configured for GitHub Pages through Actions. A dedicated Windows x64 runner builds the game; the deployment job uses GitHub's Pages artifact workflow. The runner is a background process, not an installed Windows service, so it must be started again after shutdown. Existing runner registration for another project was preserved.

The [first release workflow](https://github.com/EthannYakabuski/DealerRPG/actions/runs/36884531478) completed successfully for commit `402c05ac9705ec22b5ff8b65d3765407f446623d` on October 1, 2026. Its fresh Windows checkout passed all 264 counted checks plus world geometry/cutaway verification, exported the game and uploaded the Pages artifact. GitHub's deployment job then published [Night School](https://ethannyakabuski.github.io/DealerRPG/), which returned HTTP 200.

A fresh isolated Chrome profile played the public URL, downloading its real WebAssembly and game pack. Observed public interactions included new story, packing stock, the $20 tutorial sale, saving Milo, scheduling a meeting, waiting through the agenda, and a completed $44 handoff (cash $86; two total sales). A patrol witnessed the handoff. Manual save and full browser reload restored the cash, clock, position and active pursuit; the nearby patrol then completed the arrest, and Escape did not bypass the terminal game-over screen. All recorded public actions and reloads produced zero console errors, exceptions or failed network requests. Reports and screenshots use the ignored `published-*` filenames under `build/`.

Future pushes to `main` repeat import, all behavioral checks and web export before deployment.
