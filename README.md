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
| V | Enter or exit a nearby vehicle |
| J / K / L | Punch / kick / shoot |
| Mouse wheel | Zoom |
| Escape | Close menu / pause |

Menus pause the clock. Clients walk to meetings about twelve game minutes early; close friends wait longer if you are late. Click the upcoming meeting card on the main HUD for directions. At a meeting location, the Agenda can skip ahead to thirty minutes before the appointment, leaving time to watch your contact walk in. Supplier pickups are physical meetings, not instant deliveries.

Milo's first follow-up arrives about ninety game minutes after saving his number. After later sales, customers wait six to eight game hours, plus extra time for larger orders, before requesting more. Other contacts can still text during that interval.

## Systems

- A guided opening sale, then an open phone-driven network of up to twelve contacts.
- Relationships affected by punctuality, price, quality, cancellation and no-shows.
- Three suppliers with different reputation gates, prices, stock quality and bust risk.
- A finite backpack, food, energy, skateboard, late-game firearm/ammunition and owned car.
- Campus security and city police with visibility-based detection, pursuit, escape and hardcore arrest.
- Animated pedestrians, spaced social groups, daily destination changes, flowing road traffic, a roaming police cruiser and parked vehicles.
- Live meeting countdowns, clickable directions, transaction pop-ups and original sounds for packing, sales, purchases, texts and police events.
- Vehicle theft, recognizable stolen cars, on-foot melee and ranged combat reactions.
- Classes, paid campus shifts, sleep, evening parties, and incremental tuition payments.
- Morning, afternoon, evening, dusk and night lighting; warm shop and interior lights.
- Furnished apartment, market, cafe, lecture hall and learning commons interiors.
- Automatic and manual saves, resume, explicit restart, and terminal victory/loss screens.

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
