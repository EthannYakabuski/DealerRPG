# Release verification

## Automated behavior

The build script rejects nonzero exits and Godot script/runtime errors before export. Tests use separate test saves and never write the player's campaign save.

| Suite | Verified behavior |
| --- | --- |
| `test_game_state.gd` | 143 campaign checks: tutorial sequence, meeting windows, quantity and money accounting, relationships, referrals, suppliers, food/capacity, classes, parties, recovery work, cars, corrupt saves, terminal loss/restart, and an earned-money tuition victory. Customer cooldowns persist across saves, old saves migrate, and malformed walking-arrival records are rejected safely. The slower-paced campaign wins after 58 sales and eight supplier pickups on day five. |
| `test_interface.gd` | 48 checks using the actual scene, buttons and interaction dispatcher: start, packing, tutorial handoff, delayed first text, scheduling, Agenda wait, walking arrivals with the clock running, approaching/arrived actor save and resume, punctual relationship rewards, shop/interior interactions, phone pages, cars, class attendance, tuition result, and terminal Escape behavior. |
| `test_population.gd` | 97 checks covering real geometry and patrol sight lines, jurisdiction, pursuit/arrest persistence, escape, movement/collisions, stamina, skateboard, combat, vehicles, walking arrivals/departures and saved actor positions. All twelve moving cars progress over five simulated minutes without gridlock or same-lane overlap. Groups retain shoulder room after sustained walking. The police cruiser witnesses crime. Board/feet grounding and traversal are checked on grass, paving, island tops and edges. |
| `test_feedback.gd` | 50 checks covering the live meeting card, earliest client/supplier priority, game-time countdown, clickable existing directions, completion/cancellation, actual transaction values including cents, success-only sounds, concurrent click/event playback, mute controls, terminal arrest audio and the revised Agenda wait button. |
| `test_world.gd` | Original model availability, twelve accessible landmarks, no road/building or pedestrian/building intersections, traffic lane samples on road surfaces, parking, five enter/exit interior transitions, and Compatibility camera-cutaway restoration. |
| `smoke_test.gd` | 62 full-scene checks covering import/animation, world assembly, movement, board, menus, interiors, navigation and lighting. |
| `test_visuals.gd` | 9 animation cache checks covering clip selection, uninterrupted playback, nonlooping actions, missing clips, replacement players and changed libraries. |

Some tests deliberately isolate their domain: interface testing moves patrols away before its staged handoff; population tests separately verify witnessed sales, pursuit and arrest. Campaign balance is tested using time advancement, while browser checks below exercise actual input and rendering.

Independent real-clock probes placed the player and actual game camera at all six selectable meeting locations. Normal ninety-minute schedules and Agenda skips to thirty minutes before the appointment produced arrivals approximately twelve minutes early. Short-notice thirty-minute schedules arrived 8.5–12 minutes early, within reach, without missed appointments or late penalties. Real JSON save/resume preserved both approaching and waiting actors with zero position change.

## Visual iteration

The original previews and all model packs were audited before curation. Native OpenGL screenshots cover title, campus gameplay, backpack, city map, apartment and dusk; an additional whole-map view checks the reference topology. Iterations corrected asset scale, external palette paths, reflective cyan foliage, overexposed lighting, paving face orientation/elevation, parking overlap, road corner continuity, spawn crowding, nighttime readability, HUD contrast, clipped labels, and player occlusion.

The game uses Compatibility-supported cached alpha-material cutaways instead of the unsupported per-instance transparency property. Original building/tree shadows and collisions remain active while the player can be seen through foreground geometry.

The performance pass caches actor animation lookups, redraws the minimap at ten updates per second, and replaces fifty over-detailed streetlamp bulb spheres with one shared low-detail mesh. The bulbs occupy only a few pixels and no longer cast unnecessary shadows.

On this machine's GeForce GT 1030, a five-second unpaused Chrome campus sample after these changes averaged 33 FPS with a 34 ms 95th-percentile frame interval. An earlier sample at the same player position averaged 24 FPS with a 66 ms interval. The clock and pedestrian positions differed between samples, so this is a useful local observation rather than a controlled benchmark or a performance guarantee. Native Compatibility rendering reached 60 FPS in the campus scene. Other browsers, GPUs, resolutions and busy scenes can differ.

The player-feedback iteration initially regressed to 9–17 FPS, which was caught before publication. Local neighbor lists, cached ground support/visual parts, and camera-based animation culling recovered a final campus sample to 31.3 FPS (49.6 ms 95th percentile), compared with 32.6 FPS (33.5 ms) for the previous public release sampled on the same machine. Offscreen bodies continue moving; only their skeletal animation processing pauses, with a 120-pixel camera margin. Eighty camera-follow checks verified that visible actors stay animated and offscreen patrols continue walking. The final full build passed all 409 counted checks plus world geometry/cutaway validation, and the final exported browser startup, skateboard movement and camera-follow actions produced no console errors, exceptions or failed network requests.

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

The player-feedback iteration was also exercised in the exported browser build: the tutorial displayed a `+$20` receipt, saving Milo left an empty inbox, his first text arrived after the introductory wait, and a new appointment created the live HUD card. Clicking it activated the existing directions without opening a menu. Agenda waiting left thirty game minutes for a visible approach, and the resulting handoff displayed `+$44`, raised cash to `$86`, removed the appointment card and left no immediate repeat request. Saving and reloading preserved the cash, clock, skateboard and active pursuit; the nearby patrol then completed an arrest. The recorded `iteration-web-*` actions produced no console errors, exceptions or failed network requests.

## Hosting

The repository is configured for GitHub Pages through Actions. A dedicated Windows x64 runner builds the game; the deployment job uses GitHub's Pages artifact workflow. The runner is a background process, not an installed Windows service, so it must be started again after shutdown. Existing runner registration for another project was preserved.

The [first release workflow](https://github.com/EthannYakabuski/DealerRPG/actions/runs/36884531478) completed successfully for commit `402c05ac9705ec22b5ff8b65d3765407f446623d` on October 1, 2026. Its fresh Windows checkout passed all 264 counted checks plus world geometry/cutaway verification, exported the game and uploaded the Pages artifact. GitHub's deployment job then published [Night School](https://ethannyakabuski.github.io/DealerRPG/), which returned HTTP 200.

A fresh isolated Chrome profile played the public URL, downloading its real WebAssembly and game pack. Observed public interactions included new story, packing stock, the $20 tutorial sale, saving Milo, scheduling a meeting, waiting through the agenda, and a completed $44 handoff (cash $86; two total sales). A patrol witnessed the handoff. Manual save and full browser reload restored the cash, clock, position and active pursuit; the nearby patrol then completed the arrest, and Escape did not bypass the terminal game-over screen. All recorded public actions and reloads produced zero console errors, exceptions or failed network requests. Reports and screenshots use the ignored `published-*` filenames under `build/`.

Future pushes to `main` repeat import, all behavioral checks and web export before deployment.
