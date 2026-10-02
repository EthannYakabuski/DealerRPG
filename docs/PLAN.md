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
Milestones 1–7 are implemented and verified. The source contains the complete campaign, authored city, five interiors, animated population, patrols, vehicles, day/night lighting, phone/backpack interfaces and persistence. Campaign, interface, population, feedback, scene, animation and world geometry checks are documented in [release verification](VALIDATION.md). Native renders and real single-threaded WebAssembly browser sessions were inspected; the local browser completed the tutorial, scheduling, customer sale, skateboarding and save/resume without console errors.

The first player-feedback iteration adds a correctly sized and grounded skateboard, persistent per-contact purchase cooldowns, a clickable upcoming-meeting card, offscreen walking client arrivals, lane-aware traffic, wider pedestrian formations, a roaming police cruiser, transaction receipts and ten original action sounds. Visual grounding follows the rendered paving and islands while retaining a flat, unobstructed traversal plane. Real-clock meeting probes cover both natural arrivals and Agenda time skips; save/resume keeps approaching actors in place.

The social-interaction iteration audits asset-native door fronts and moves entrance markers onto accessible approaches. Ambient pedestrians have stable identities and daily-goal conversations, can buy and exchange numbers, or physically run to the correct patrol to report an offer. Referral conversations provide questions and known-contact background clues without revealing hidden informant status. Clients support proactive offers, discounts, next-day callbacks and appointments up to eight hours ahead. Supplier handoffs take place between 22:00 and 02:00; physical meetings offer a choice to proceed or postpone without a trust penalty. Moving traffic causes injury and knockback. The Agenda has a direct G shortcut, and standard controllers support movement, actions, all menus, dropdowns, numeric fields and map directions.

GitHub Pages is configured for Actions, the dedicated `night-school-desktop` Windows runner is online, and the engine variable is set. [Release run 36884531478](https://github.com/EthannYakabuski/DealerRPG/actions/runs/36884531478) passed from a fresh checkout and published [the playable game](https://ethannyakabuski.github.io/DealerRPG/). Public browser input verified the tutorial, contacts, scheduling, a completed sale, police detection, and saved pursuit continuing into a hardcore arrest after reload. Original user-supplied untracked source packs remain untouched; curated runtime assets are sufficient for CI.
