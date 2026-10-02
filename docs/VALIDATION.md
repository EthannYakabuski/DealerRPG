# Release verification

## Automated behavior

The living-city iteration adds live-party state and physical guest tests, supplier controller navigation and emote integration, grass riding checks, outskirts patrols, local pressure expiry, and complete pedestrian/car/parking trips. Parties preserve walking and indoor guest progress through real save/continue, borrow the original street contact actor, require explicit sales, and route departing guests around apartment furniture. Repeated-pursuit hide times and overlapping party/meeting rejection are covered separately.

The complete living-city build passed **773 counted checks** plus world geometry/cutaway audits, with clean engine logs and a40.5 MB web export. New suites comprise party/pressure85, party interface34, physical parties19 and skate surfaces6 checks. Browser Gamepad input completed the opening sale and exercised bundle increase/decrease, Down to Arrange Pickup, Up back to quantity, and confirmation with insufficient funds correctly rejected. A browser-only missing arrow glyph in the help text was replaced with words before publication. Recorded browser actions produced zero console errors, exceptions or failed requests.

The expanded city's unpaused five-second campus sample averaged35.6 FPS (33.6 ms95th-percentile frame interval) on the available GT1030 at1280×800, compared with the prior release's45.4 FPS sample. These short local observations are not hardware guarantees. Native1280×800 and960×600 checks covered party controls, interiors/emotes and supplier navigation; native views also reviewed all five crossings, clear west parking approaches, extra patrols and complete car trips. Ambient commuter parking positions reset on reload; campaign, party and player-vehicle progress persist.

The build script rejects nonzero exits and Godot script/runtime errors before export. Tests use separate test saves and never write the player's campaign save.

| Suite | Verified behavior |
| --- | --- |
| `test_game_state.gd` | 144 campaign checks: tutorial sequence, meeting windows, quantity and money accounting, relationships, referrals, suppliers, food/capacity, classes, parties, recovery work, cars, corrupt saves, terminal loss/restart, and an earned-money tuition victory. The current night-supplier campaign wins after 59 sales and eight supplier pickups on day nine with no missed classes. |
| `test_interface.gd` | 50 checks using the actual scene, buttons and interaction dispatcher: start, packing, tutorial handoff, delayed first text, scheduling, Agenda wait, walking arrivals with the clock running, approaching/arrived actor save and resume, handoff review/confirmation, punctual relationship rewards, shop/interior interactions, phone pages, cars, class attendance, tuition result, and terminal Escape behavior. |
| `test_population.gd` | 145 checks covering geometry, patrol sight lines/jurisdiction, pursuit/arrest persistence, escape, movement, stamina, board, combat, vehicles and walking arrivals. All twelve moving cars progress over five simulated minutes without gridlock; groups retain shoulder room. New checks cover swept traffic impacts, safe crawl/side clearance, physical witness runs, living officer selection, single report arrival, saved runner positions and cross-district investigation. |
| `test_feedback.gd` | 51 checks covering the live meeting card, earliest client/supplier priority, countdown, clickable directions, completion/cancellation, transaction values including cents, success-only sounds, concurrent click/event playback, mute, arrest and impact audio. |
| `test_controls.gd` | 33 real joystick-event checks: title start, menu shortcuts, native focus/refresh, dropdown open/select/cancel, numeric adjustment, analog deadzone/proportional movement, nonzero controller IDs, board, impact damage/knockback/cooldown and paused/owned-car exclusions. |
| `test_social_state.gd` | 81 checks covering persistent street outcomes, all referral decisions and accurate/inaccurate informants, proactive offers/discounts, night windows, eight-hour scheduling, tomorrow/postponement callbacks, no duplicate transactions, saved reporters and legacy daytime supplier migration. |
| `test_social_interface.gd` | 41 actual-button checks for referral questions and profile clues, accept/block, proactive replies, discount cap, eight-hour form, tomorrow, physical postponement, nighttime supplier UI, map directions and numeric focus persistence. |
| `test_social_world.gd` | 13 checks through the real world dispatcher: held conversations, daily-goal small talk, street sales and number exchange, release on close, report departure, real JSON save/continue with no teleport, report completion only at an officer and rejection of remote postponement. |
| `test_world.gd` | Original model availability, twelve accessible landmarks, eight door axes and clear approaches, no road/building or pedestrian/building intersections, traffic lanes, parking, five enter/exit transitions and Compatibility cutaway restoration. |
| `smoke_test.gd` | 62 full-scene checks covering import/animation, world assembly, movement, board, menus, interiors, navigation and lighting. |
| `test_visuals.gd` | 9 animation cache checks covering clip selection, uninterrupted playback, nonlooping actions, missing clips, replacement players and changed libraries. |

Some tests deliberately isolate their domain: interface testing moves patrols away before its staged handoff; population tests separately verify witnessed sales, pursuit and arrest. Campaign balance is tested using time advancement, while browser checks below exercise actual input and rendering.

The social/controller release passed **607 counted checks** plus world geometry/cutaway validation in a complete clean-error build and produced the 40.4 MB web export. Eight native rendered entrance views were reviewed against the supplied models; the conversation, referral, contacts, night supplier and handoff screens were reviewed at 1280×800 and 960×600. Controller checks use synthetic Godot joystick events and browser Gamepad API input; no physical controller model has been certified.

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

The social iteration also runs through the browser's standard Gamepad API using an isolated virtual pad: A starts the story, RB opens the backpack, A splits stock, B closes, A makes the tutorial sale, and LB opens the phone to save Milo. The first delayed text exposes the tomorrow reply. Controller navigation opens the native time dropdown, selects 480 minutes, adjusts the price and books an eight-hour appointment visible on the HUD. An uninterrupted second journey schedules a normal appointment, waits on site for the walking actor and opens the handoff dialog three minutes before its due time. It reports one visible patrol nearby. Choosing a two-hour postponement removes the appointment without changing the $42 cash balance and promises a callback at 15:04. The callback arrives as promised; selecting “hit me up tomorrow” clears it and confirms that no new meeting has been booked. Generated screenshots/reports use `social-web-*` and `social-browser-*`; these checks produced no console errors, exceptions or network failures. A five-second unpaused campus sample averaged 45.4 FPS with a 33.4 ms 95th-percentile frame interval on the same GT 1030; this remains a local observation, not a hardware guarantee.

## Hosting

The repository is configured for GitHub Pages through Actions. A dedicated Windows x64 runner builds the game; the deployment job uses GitHub's Pages artifact workflow. The runner is a background process, not an installed Windows service, so it must be started again after shutdown. Existing runner registration for another project was preserved.

The [first release workflow](https://github.com/EthannYakabuski/DealerRPG/actions/runs/36884531478) completed successfully for commit `402c05ac9705ec22b5ff8b65d3765407f446623d` on October 1, 2026. Its fresh Windows checkout passed all 264 counted checks plus world geometry/cutaway verification, exported the game and uploaded the Pages artifact. GitHub's deployment job then published [Night School](https://ethannyakabuski.github.io/DealerRPG/), which returned HTTP 200.

A fresh isolated Chrome profile played the public URL, downloading its real WebAssembly and game pack. Observed public interactions included new story, packing stock, the $20 tutorial sale, saving Milo, scheduling a meeting, waiting through the agenda, and a completed $44 handoff (cash $86; two total sales). A patrol witnessed the handoff. Manual save and full browser reload restored the cash, clock, position and active pursuit; the nearby patrol then completed the arrest, and Escape did not bypass the terminal game-over screen. All recorded public actions and reloads produced zero console errors, exceptions or failed network requests. Reports and screenshots use the ignored `published-*` filenames under `build/`.

Future pushes to `main` repeat import, all behavioral checks and web export before deployment.
