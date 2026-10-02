# Living-city iteration checkpoint — 2026-10-02

Base release: `525c717` on main; https://ethannyakabuski.github.io/DealerRPG/.
User requests A–N: varied ambiguous street responses; intuitive controller supplier quantities/confirmation; aligned crossings; additional outskirts walkers and patrols; clear sidewalks; physical apartment parties 17:00–02:00 with optional individual sales; repeat-location police pressure; escalating hide times 10,10,15,20,25,30,+10; extra patrol expiry after a quiet day; NPC parking/car trips; slow skateboarding on grass; supplied NPC emotes.

## Ownership and implementation complete; release verification underway

- Root: main/player, new party actor helper and integration tests, checkpoint, final native/browser QA and publish.
- customer_pacing: game_state/game_data, dialogue variety, live party state, enforcement state/save compatibility, state tests, SYSTEMS_API.
- city_motion: world/population, crossings/sidewalks, 42 existing +15 new outskirts citizens, baseline patrols7→10 plus pressure units, NPC car-trip helper, geometry/population tests.
- hud_audio: interface/controller bundle stepper, party UI, emote helper/assets, UI tests/captures.

No commits for this iteration yet. Preserve original untracked Assets/MoreNature, Nature, UI_Dialogs, UI_emotes, UI_input, skybox packs. Do not stage them wholesale.

## Contracts

- `world.is_paved_surface(Vector3)->bool`: highest rendered surface classification, raised grass remains false. Root skateboard speed2.2 on grass vs11.8 paved.
- Game parties: `host_party()` charges25 supplies only, no automatic stock sales/time skip; active up to180 game minutes, capped02:00, up to8 saved contacts. `party_summary()` exposes id/active/start/end/guests; guest contact_id/name/arrival_minute/arrived/chatted/purchased. `mark_party_guest_arrived`, `chat_party_guest`, `sell_party_guest`, `party_guest_view`.
- Root party helper owns separate node, uses population navigation for outside walks, apartment slots inside, root guards physical conversations. Optional `world_state.party_walks` up to8 records contact_id/state/position/slot.
- Police: `Game.register_pursuit(location_id)` called once per new pursuit; `escape_duration_seconds()` returns escalation; `police_pressure_locations()` returns location/expiry/strength/watch/incident counts. Cap4 additional officers/location and8 visible globally; persistent underlying pressure expires after1440 quiet game minutes.
- State cosmetic signals: street_reaction(npc_id,kind), meeting_reaction(meeting_id,kind), party_reaction(contact_id,kind), meeting_missed(id,contact_id). Existing civilian_reaction(report) remains physical runner.
- UI proposed party conversations reuse show_conversation with actor_id `party:<contact_id>`, party_guest flag; root conversation_action branches to physical party helper.

## Verification / environment

Godot console: C:/Users/swimr/Downloads/Godot_v4.5.1-stable_win64.exe/Godot_v4.5.1-stable_win64_console.exe
Full build: scripts/build_web.ps1 (imports, every tests/test_*.gd + smoke, exports build/web). Use escalated runs for final clean engine logs; sandbox can emit irrelevant certificate errors. Test saves must be isolated under.godot.
Node: C:/Users/swimr/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe
Browser harness: tools/browser_smoke.mjs boot/click/key/pad/capture/benchmark/close. `pad --button` uses standard browser Gamepad indices; `pad --axis 0 --value 1 --hold 700` tests movement. Use fresh isolated profile; never personal browser save.
Last release607 checks passed. This iteration's focused tests passed: state310, population145, party interface34, social interface41, feedback51, party physical integration19, skate surfaces6, plus world geometry. Party tests include borrowed street NPC identity, physical approach, mid-walk and indoor saves, explicit sales and furniture-safe departures. Shared pedestrian navigation now retains its obstacle path until clear to avoid corner oscillation. Native UI reviewed at1280 and960; curated emotes visible above guests.

Full scripts/build_web.ps1 completed successfully2026-10-02:773 counted checks plus world geometry/cutaway audits, clean logs,40.5 MB export. Local browser Gamepad tutorial and supplier quantity/down/up/confirm flow passed with zero browser errors; insufficient cash is correctly rejected. A missing browser-only arrow glyph was replaced with words and re-exported (the only post-suite source change). Local campus benchmark35.6FPS, p95frame33.6ms onGT1030; prior sample45.4FPS. Native UI1280/960 and five crossings/commuter routes visually verified.

Final local reload and commit/push pending. Publishing already authorized; assess_game_workflow agent confirmed runneronline/idle, authenticatedGitHub access and Pages healthy, awaiting releaseSHA. Preserve generated screenshots/logs only under ignored build/. Own temporary preview serverPID90080; QA ChromePID65336, both should be closed when releaseverification finishes. Do not stop unrelated processes.

Usage at start:18% weekly remaining. User will apply a reset if needed; do not redeem a credit without explicit confirmation. Keep this file updated at milestones so continuation can resume without repeating work.

Latest reported usage7% remaining; user informed. No reset requested or redeemed byagent.
