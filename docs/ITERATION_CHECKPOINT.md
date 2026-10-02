# Living-city iteration checkpoint — 2026-10-02

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
