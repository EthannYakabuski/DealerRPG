# Night School — development contract

## Intent
Create a fully playable browser-first 3D top-down student-life crime sandbox using Godot 4.5.1 Compatibility and the supplied Kenney assets. The protagonist is an adult college student; all trading uses fictional abstract inventory units. The city loosely follows the supplied Ottawa/Algonquin/College Square reference, not a claim of geographic accuracy.

## Design pillars
- A convincing connected neighbourhood: campus south/east, College Square west, Deerfield residential northeast, with continuous roads and sidewalks.
- The phone is the opportunity board: incoming texts, contacts, meeting choices, agenda, suppliers, and tuition payments.
- Consequences are legible: relationships, hunger, attendance, heat, and time influence decisions; arrest and eviction end the run.
- A complete affordable campaign: start after class, package one unit, meet a friend, build contacts, source better stock, and pay tuition.
- Browser performance and input clarity take priority over sheer object count.

## Ownership
- Coordinator: project scaffolding, player controls, NPC/traffic/police simulation, presentation, integration and end-to-end verification.
- World developer: asset audit and curated runtime assets, map, roads, props, interiors, environment.
- Systems developer: economy, contacts, agenda, tutorial, suppliers, save/load, endings and state tests.
- Build/QA developer: Windows self-hosted GitHub Actions, web export, Pages deployment, build documentation.

## Milestones
1. Inspect all asset packs, map, tooling and licenses; save audit and spatial plan.
2. Playable city, responsive movement, cameras, collision, traffic, pedestrians, day-night environment.
3. Tutorial, phone, inventory, meetings, shops, suppliers, classes and tuition win.
4. Campus/city police, pursuits/arrest, combat reactions, skateboarding, vehicle theft/ownership, parties/interiors.
5. Save/resume, onboarding, HUD/map/navigation, sound, polish and performance.
6. Headless behavioral tests; rendered visual and browser interaction checks; real web export.
7. Validate CI and publish via requested GitHub Pages workflow when account/repo access permits.

## Verification policy
Use real execution evidence. Keep test hooks separate from normal play. Each action must be reachable from the interface, and both victory and hardcore loss must be reproducible. Check the served WebAssembly build in a browser. Preserve original assets and existing changes. Document remaining external blockers accurately.

## Current status
Milestones 1–7 are implemented and verified. The source now contains the complete campaign, authored city, five interiors, animated population, patrols, vehicles, day/night lighting, phone/backpack interfaces and persistence. The suite includes 94 campaign, 36 interface, 63 population, 62 scene and 9 animation checks, plus world geometry/cutaway checks. Native renders and real single-threaded WebAssembly browser sessions were inspected; the local browser completed the tutorial, scheduling, customer sale, skateboarding and save/resume without console errors.

GitHub Pages is configured for Actions, the dedicated `night-school-desktop` Windows runner is online, and the engine variable is set. [Release run 36884531478](https://github.com/EthannYakabuski/DealerRPG/actions/runs/36884531478) passed from a fresh checkout and published [the playable game](https://ethannyakabuski.github.io/DealerRPG/). Public browser input verified the tutorial, contacts, scheduling, a completed sale, police detection, and saved pursuit continuing into a hardcore arrest after reload. Original user-supplied untracked source packs remain untouched; curated runtime assets are sufficient for CI.
