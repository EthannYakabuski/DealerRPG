# NIGHT SCHOOL

**Tuition is due. The city is open.**

A browser-first, single-player 3D crime and student-life sandbox built with Godot 4.5.1's Compatibility renderer. Walk, run, skate, or drive through a compact modern neighbourhood inspired by the supplied Algonquin College / College Square / Deerfield aerial reference.

The game begins after class. Your friend Milo wants a favour, your backpack holds a little stock, and your student loan is still $3,500. Package stock, build a phone network, schedule meetings, keep your commitments, and climb through three supplier tiers. Stay fed, attend class, and watch the patrols. Paying the loan wins; arrest, fatal injuries, or three missed classes ends the run.

## Play

[Play Night School on GitHub Pages](https://ethannyakabuski.github.io/DealerRPG/). Pushes to `main` test, build and publish updates automatically.

Use a desktop browser with WebGL 2 and WebAssembly support. The game uses a single-threaded export, so it does not require cross-origin isolation headers. Saves stay in the browser/device you used; clearing site storage clears that save.

| Control | Action |
| --- | --- |
| WASD / arrows | Move relative to the camera |
| Shift | Run; consumes energy |
| Space | Equip or stow the skateboard |
| E | Talk, hand off, attend class, shop, or enter/exit |
| Tab / P | Phone |
| B / I | Backpack |
| M | City map; click a landmark for directions |
| G | Agenda and upcoming appointments |
| V | Enter or exit a nearby vehicle |
| J / K / L | Punch / kick / shoot |
| Mouse wheel | Zoom |
| Escape | Close menu / pause |

Menus pause the clock. Clients walk to meetings about twelve game minutes early; close friends wait longer if you are late. Click the upcoming meeting card on the main HUD for directions. At a meeting location, the Agenda can skip ahead to thirty minutes before the appointment, leaving time to watch your contact walk in. Talk to the contact beside you to review the handoff or postpone it and receive a later callback. Supplier pickups are physical meetings between 10 p.m. and 2 a.m. Client appointments can be scheduled up to eight hours ahead; “hit me up tomorrow” defers the request to the following day.

Controllers use standard Xbox-style button names (equivalent positions on other pads). Connect a controller and press a button after focusing the browser game.

| Controller | Action |
| --- | --- |
| Left stick | Move; navigate menus |
| A / B | Interact or confirm / close menu |
| X / Y | Skateboard / enter or exit vehicle |
| LT / RT | Sprint / punch |
| LB / RB | Phone / backpack |
| Select / Start | Map / pause |
| D-pad up / right | Agenda / contacts |
| D-pad left / down | Kick / shoot |
| D-pad in menus | Move focus; adjust a selected numeric value with left/right |

The phone supports controller selection, scrolling and scheduling. A opens a dropdown, directions select an option, and A confirms; B backs out. Menus display the control hints for the most recently used input device.

On the supplier screen, focus the bundle quantity and use left/right to adjust it. Down moves directly to that supplier's **Arrange pickup** button; A confirms.

Milo's first follow-up arrives about ninety game minutes after saving his number. After later sales, customers wait six to eight game hours, plus extra time for larger orders, before requesting more. Other contacts can still text during that interval.

## Systems

- A guided opening sale, street conversations and an expanding phone network.
- Ambient customers can buy and exchange numbers, refuse, or run to a nearby officer to report an offer.
- Referral texts let you ask about the referrer and their shared history before accepting a new contact. Compare replies with known contact profiles; a coherent answer is a clue, never a guarantee.
- Proactive offers to saved contacts, occasional requests for a discount, tomorrow replies and in-person postponements.
- Relationships affected by punctuality, price, quality, cancellation and no-shows.
- Three suppliers with different reputation gates, prices, stock quality and bust risk.
- A finite backpack, food, energy, skateboard, late-game firearm/ammunition and owned car.
- Campus security and city police with a forward view cone, close-range awareness, pursuit, escape and hardcore arrest. Ordinary handoffs must be visible: patrols see within a 110-degree cone, or within three metres from any direction, and walls always block their view. Informant reports and planned stings can still dispatch police.
- Animated pedestrians, spaced social groups, daily destination changes, flowing road traffic, a roaming police cruiser and parked vehicles. Moving traffic can injure you and knock you off your board.
- Live meeting countdowns, clickable directions, transaction pop-ups and original sounds for packing, sales, purchases, texts and police events.
- Vehicle theft, recognizable stolen cars, on-foot melee and ranged combat reactions.
- Classes, paid campus shifts, sleep, evening parties, and incremental tuition payments.
- Morning, afternoon, evening, dusk and night lighting; warm shop and interior lights.
- Furnished apartment, market, cafe, lecture hall and learning commons interiors.
- Automatic and manual saves, resume, explicit restart, and terminal victory/loss screens.

Parties can start at the apartment between 17:00 and 02:00 after reputation 5 and two contacts. Pay $25 for supplies, then invite up to eight contacts from the guest list. Guests walk to your door and gather inside for up to three hours, ending by 02:00. Catching up builds relationships; selling is a separate conversation choice and never consumes stock automatically.

Two consecutive completed meetings at one location attract extra attention; three bring heavier patrols. New pursuits add local officers and increase the time you must remain unseen: 10, 10, 15, 20, 25, 30 seconds, then another 10 per pursuit. Extra local patrols leave after a full game day without another bust there. The outskirts now have their own walkers and patrol routes, and some residents walk to parked cars, drive a circuit and return to a vacant space.

Skateboards retain normal speed on pavement but crawl on grass. NPC emotes accompany conversations, sales, missed meetings and police alerts; a casual greeting alone does not reveal whether someone will buy.

## Develop locally

1. Open `project.godot` with **Godot 4.5.1 stable**. The project uses GDScript and Compatibility rendering.
2. Let the curated `art/` assets import, then run the main scene.
3. Install the matching official export templates for a web build.

```powershell
./scripts/build_web.ps1 -GodotExe 'C:\path\to\Godot_v4.5.1-stable_win64_console.exe'
python ./tools/serve_web.py --port 8060
```

Open `http://127.0.0.1:8060/`. Opening the HTML directly from disk will not run the WebAssembly game correctly.

The build script imports resources, runs all `tests/test_*.gd` plus the scene smoke test, exports to `build/web`, and checks the generated files. Build logs and screenshots are generated artifacts and stay out of Git.

## Deployment

Pushes to `main` run `.github/workflows/web.yml`: a **self-hosted Windows x64 runner** imports/tests/exports, then GitHub's Pages deployment job publishes the artifact. The `GODOT_EXE` repository variable selects the installed engine. See [build and deployment details](docs/BUILD_AND_DEPLOY.md) for runner startup, prerequisites and troubleshooting.

## Project notes

- [Asset audit](docs/ASSET_AUDIT.md): all supplied packs, licenses, scales, palettes, animation and runtime selection.
- [Map design](docs/MAP_DESIGN.md): spatial interpretation, roads, district layout and interiors.
- [Systems API](docs/SYSTEMS_API.md): campaign state and integration contract.
- [Development plan](docs/PLAN.md): scope, milestones and verification policy.

Original source assets remain under `Assets/`, ignored by Godot's importer. The runtime uses a curated subset in `art/`; `tools/curate_assets.py` reproduces the model inventory and selection. Kenney asset licenses are retained alongside those assets. The supplied map screenshot is design reference, not a shipped game texture. Code is licensed under the repository's Apache 2.0 license.
