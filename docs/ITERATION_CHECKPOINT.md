# Living-city iteration checkpoint — 2026-10-03

## Ready to publish: pickup scheduling, vehicles and pursuit escalation (A–L)

All requested game changes are implemented and reviewed. Supplier pickups allow 15 minutes early with the actor present; all sixteen client locations work; absolute half-hour slots and exact adjacent appointments fix clock drift. Bundles contain seven bags. Solid props block traffic, driven cars ignore pedestrian displacement, rotation respects walls, and legacy embedded cars recover a safe pose before exit.

Cruisers use the existing 220-degree / 6 m visibility and wall occlusion, report road skating outside campus, and pursue on the road network at the 20-second tier. Sidewalks, parking lots and marked crossings are exempt. Foot officers aim and shoot at 25 seconds; successful melee stuns them for one second. Daily escalation drops two steps: a final 30-second chase becomes the next day's first 20-second chase. Ongoing pursuits keep their requirement across midnight and save/continue. Fatal damage opens statistics and allows a fresh story. An incidental sixth-interior movement clamp was also corrected.

All source is frozen. Independent state, UI and vehicle/world integration reviews are complete. The full local build passed 1,198 counted checks plus world geometry/cutaway validation with clean logs and a 40.5 MB export. Count only logs corresponding to current tests/test_*.gd plus smoke_test.log; stale agent logs must not be included. The earned campaign wins on day 8 after 67 sales and seven pickups with the full supplier ladder and no missed classes. Native 1280/960 UI and aim/fire/stun captures were reviewed.

Local exported-browser checks passed controller story/backpack/seven-bag packing, the opening sale, saving Milo, all location options, fixed times and booking East trail shelter at 14:00. Every pursuit-local-* report has zero console errors, exceptions and network failures. The unpaused campus sample was 32.2 FPS, p95 frame 34.3 ms, GT 1030/WebGL 2 at 1280×800. QA Chrome and temporary preview PID 91068 / port 8061 were closed. Leave the preexisting port 8060 server and user's Godot editor alone.

Remaining: commit/push the reviewed source, verify exact-SHA CI/Pages with assess_game_workflow, run a fresh public-browser smoke check, then record the release. Prior live game release 5ca374d; prior main documentation 39ce20a. Original untracked Assets/MoreNature, Nature, UI_Dialogs, UI_emotes, UI_input and skybox packs must stay untouched. No reset credit was used. Source ownership: customer_pacing state/data; city_motion population/car trips; hud_audio interface; root world/player/main/integration/release. Completed agents are frozen; assess_game_workflow is waiting for the release SHA.

## Complete: supplier discovery and daily life (A–J)

Current user scope: fix stuck west officer and stray parking-lot sidewalk; widen police view to 220 degrees and close awareness to 6 m; suppliers have two-day contact cooldowns and social unlocks (tier 1 immediately, tier 2 parties/late outskirts, tier 3 after three tier-2 deals and a conversation); 30-minute meeting slots; mixed morning/afternoon classes, one/day; rare NPC-hosted parties; remote supplier locations; purposeful pedestrians with more solo walkers.

Implementation ownership: city_motion handled world/population; customer_pacing handled state/data; hud_audio handled interface and independent review; root handled physical suppliers/parties and integration/release. All game source is committed and deployed at `5ca374d17200956b09923f2300cd18f42732c936` on main. The exact-SHA [CI/Pages run](https://github.com/EthannYakabuski/DealerRPG/actions/runs/37170171986) independently passed all 982 counted checks, world geometry/cutaway validation, and the 40.5 MB export. [Public game](https://ethannyakabuski.github.io/DealerRPG/) verified. Prior deployed game was e3f4dce.

Contracts: Game.supplier_encounters() returns active {id,tier,name,location_id,kind}; Game.supplier_encounter_view(id) exposes {name,text,choices:[{id,label}],complete,retry_minute}; Game.supplier_encounter_action(id,action) handles progression, with root guarding real actor distance. IDs supplier_1/supplier_2. Party supplier uses contact_id supplier_1 + supplier flag; chat unlocks. Party summary includes mode, location_id, host_id/host_name; NPC venue deerfield_social at (86,0,-51), interior index 5 at x=1000. Party roster can have eight contacts plus supplier guest; optional saved supplier_walks stores up to two exterior actors. UI show_supplier_conversation(view) routes choices to root.supplier_conversation_action(action).

Implementation and full local build complete: 982 counted checks plus world geometry/cutaway audits, clean logs, 40.5 MB export. New state72/UI38/physical32 suites pass; population171 and police32 pass. Earned campaign61sales/8pickups/day9, all classes, full supplier ladder. Native1280/960 menus and neighbor/full9party rooms reviewed, plus west parking, 3 remote sites and neighbor door. Read-only QA caught Sable party/pickup duplication: party-aware supplier_pickup_minute + actor-provider ownership now prevent it at booking/approach/departure. Source files frozen.

West freeze root cause was a campus waypoint (-112,26) across jurisdiction; corrected full patrol circuits pass. State keeps supplier intros in the phone, rotates remote pickup sites, migrates legacy supplier access and shifts legacy afternoon-class conflicts once. Local browser Gamepad tutorial, supplier quantity/order focus/discovery, skate/analog movement passed with zero errors/exceptions/network failures; campus32.2FPS p95frame50.2ms GT1030. Reports supplier-local-*. Local QA browser and owned preview PID17580/port8061 were closed. Existing port8060 server PID86420 was left untouched. Original untracked asset packs must remain untouched.

A fresh isolated public-browser session passed startup, controller story/backpack/packing, the $20 opening sale, saving Milo, and supplier order/discovery navigation. Visual review confirmed the two-day order notice, West trail overlook pickup and locked Sable party/Freight lane hint in the deployed build. All supplier-public-* reports have zero console errors, exceptions and network failures. The public QA browser was closed after verification. No required work remains; this final checkpoint is documentation only and the tested game release remains the SHA above.

## Follow-up: police perception and performance

Implementation, verification and deployment complete. Game release: `e3f4dce7eda2c45107a2f93284d03bdfe10dfad8` on main. [CI and Pages deployment](https://github.com/EthannYakabuski/DealerRPG/actions/runs/37065429155) independently passed all 808 counted checks plus world audits and exported 40.5 MB. New police logic in population.gd uses a 110-degree forward cone and a 3 m near-awareness exception, always requiring wall line of sight. It applies to cruisers, handoffs, stolen-car identification and pursuit. Unseen handoffs preserve the last known chase position; reported stings and gunfire dispatch independently. Native batch readback passed four additional transform checks. Final local browser gameplay and three benchmark samples passed without script errors.

world_batch.gd now groups primitive details in 32 m spatial chunks; ActorVisuals ground rings no longer cast shadows. Native controlled profiles show 31.5–36.6% fewer submitted primitives across three exterior districts without reducing population or simulation. Batch tests pass 5 headless/9 native. Profiler is tools/profile_runtime.gd; measurements are build/logs/runtime-profile-{baseline,chunk32,final}.json. Browser baseline was variable (26.9/14.3/27.6 FPS; final 26.8/28.1/28.6), so avoid claiming an FPS percentage gain.

A fresh isolated public-browser session verified startup, controller new story/backpack/splitting stock, and the $20 tutorial sale, with zero console errors, exceptions or network failures. Reports/screenshots use build/logs/police-perf-public-* and build/screenshots/police-perf-public-*. Scene rendering was visually reviewed. The QA browser and local preview server were closed; the user's original Godot editor was left untouched. No required work remains. The final checkpoint is documentation only; the tested game release remains the SHA above. User reset externally; no credit was redeemed by the agent. Earlier iteration history follows.

Completed release: `2931d27880c4051e200e7b88cac5508ffe201c53` on main; https://ethannyakabuski.github.io/DealerRPG/. Prior release: `525c717`.
User requests A–N: varied ambiguous street responses; intuitive controller supplier quantities/confirmation; aligned crossings; additional outskirts walkers and patrols; clear sidewalks; physical apartment parties 17:00–02:00 with optional individual sales; repeat-location police pressure; escalating hide times 10,10,15,20,25,30,+10; extra patrol expiry after a quiet day; NPC parking/car trips; slow skateboarding on grass; supplied NPC emotes.

## Implementation and release verification complete

- Root: main/player, new party actor helper and integration tests, checkpoint, final native/browser QA and publish.
- customer_pacing: game_state/game_data, dialogue variety, live party state, enforcement state/save compatibility, state tests, SYSTEMS_API.
- city_motion: world/population, crossings/sidewalks, 42 existing +15 new outskirts citizens, baseline patrols7→10 plus pressure units, NPC car-trip helper, geometry/population tests.
- hud_audio: interface/controller bundle stepper, party UI, emote helper/assets, UI tests/captures.

The game changes are committed and published. Preserve original untracked Assets/MoreNature, Nature, UI_Dialogs, UI_emotes, UI_input, skybox packs. Do not stage them wholesale.

## Contracts

- `world.is_paved_surface(Vector3)->bool`: highest rendered surface classification, raised grass remains false. Root skateboard speed2.2 on grass vs11.8 paved.
- Game parties: `host_party()` charges25 supplies only, no automatic stock sales/time skip; active up to180 game minutes, capped02:00, up to8 saved contacts. `party_summary()` exposes id/active/start/end/guests; guest contact_id/name/arrival_minute/arrived/chatted/purchased. `mark_party_guest_arrived`, `chat_party_guest`, `sell_party_guest`, `party_guest_view`.
- Root party helper owns separate node, uses population navigation for outside walks, apartment slots inside, root guards physical conversations. Optional `world_state.party_walks` up to8 records contact_id/state/position/slot.
- Police: `Game.register_pursuit(location_id)` called once per new pursuit; `escape_duration_seconds()` returns escalation; `police_pressure_locations()` returns location/expiry/strength/watch/incident counts. Cap4 additional officers/location and8 visible globally; persistent underlying pressure expires after1440 quiet game minutes.
- State cosmetic signals: street_reaction(npc_id,kind), meeting_reaction(meeting_id,kind), party_reaction(contact_id,kind), meeting_missed(id,contact_id). Existing civilian_reaction(report) remains physical runner.
- Party conversations reuse show_conversation with actor_id `party:<contact_id>`, party_guest flag; root conversation_action branches to physical party helper.

## Verification / environment

Godot console: C:/Users/swimr/Downloads/Godot_v4.5.1-stable_win64.exe/Godot_v4.5.1-stable_win64_console.exe
Full build: scripts/build_web.ps1 (imports, every tests/test_*.gd + smoke, exports build/web). Use escalated runs for final clean engine logs; sandbox can emit irrelevant certificate errors. Test saves must be isolated under.godot.
Node: C:/Users/swimr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe
Browser harness: tools/browser_smoke.mjs boot/click/key/pad/capture/benchmark/close. `pad --button` uses standard browser Gamepad indices; `pad --axis 0 --value 1 --hold 700` tests movement. Use fresh isolated profile; never personal browser save.
Last release607 checks passed. This iteration's focused tests passed: state310, population145, party interface34, social interface41, feedback51, party physical integration19, skate surfaces6, plus world geometry. Party tests include borrowed street NPC identity, physical approach, mid-walk and indoor saves, explicit sales and furniture-safe departures. Shared pedestrian navigation now retains its obstacle path until clear to avoid corner oscillation. Native UI reviewed at1280 and960; curated emotes visible above guests.

Full scripts/build_web.ps1 completed successfully2026-10-02:773 counted checks plus world geometry/cutaway audits, clean logs,40.5 MB export. Local browser Gamepad tutorial and supplier quantity/down/up/confirm flow passed with zero browser errors; insufficient cash is correctly rejected. A missing browser-only arrow glyph was replaced with words and re-exported (the only post-suite source change). Local campus benchmark35.6FPS, p95frame33.6ms onGT1030; prior sample45.4FPS. Native UI1280/960 and five crossings/commuter routes visually verified.

Deployment succeeded at https://github.com/EthannYakabuski/DealerRPG/actions/runs/37055354410 for the exact release SHA above. CI independently passed all 773 checks, world geometry and cutaway audits, and the 40.5 MB export. A fresh public-browser session verified the new supplier help text, quantity increment and direct Down-to-pickup focus with zero console errors, exceptions or network failures. Reports/screenshots use build/logs/living-city-* and build/screenshots/living-city-*.

No required implementation or verification remains. Ambient commuter parking resets on reload; player vehicles and campaign/party progress persist. Temporary QA browsers and the local preview server were closed. Original asset packs are the only remaining untracked worktree files. This final checkpoint is documentation only; the tested game release remains the SHA above.

Usage at start:18% weekly remaining. User will apply a reset if needed; do not redeem a credit without explicit confirmation. Keep this file updated at milestones so continuation can resume without repeating work.

Latest checked usage: 6% remaining. No reset requested or redeemed by agent.
