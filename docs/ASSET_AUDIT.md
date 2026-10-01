# Supplied asset audit

Audit performed on the original `Assets` directory. `tools/curate_assets.py`
reproduces the numerical audit and curated runtime library. The full inventory,
including per-model source path, bytes, transformed bounds, triangle count,
mesh/material counts, animation names, skins, and external image dependencies,
is in `docs/asset_catalog.json`.

## Inventory and visual assessment

The source contains **1,175 GLB models** plus duplicate FBX/OBJ/DAE/STL formats,
preview images, UI SVGs/PNGs, font files, and six interface sounds. The GLBs are
the appropriate Godot/Web format. Importing every duplicate would waste editor
time and repository/export size. `Assets/.gdignore` deliberately keeps the
original library out of Godot's importer; curated files live in `art/models`.

Every supplied pack's License.txt was checked and explicitly says **CC0**.
Kenney credit is welcomed but optional. A copy of each selected pack's license
travels with its curated models. The game's code license is separate.

| Pack | GLBs | Source GLB MiB | Visual findings and gameplay application |
| --- | ---: | ---: | --- |
| Characters | 26 | 3.26 | Rounded miniature adults, accessories and mobility aids. Twelve human models have the same rich animation vocabulary. Casual students, clientele, officers, and suppliers are supported. |
| Cars | 50 | 5.37 | Stylized modern passenger cars, hatchback, SUV, van, taxi, delivery, emergency vehicles, wheels/debris. Support traffic, parked cars, theft, ownership and police. |
| Commercial_City | 41 | 3.57 | White/grey multi-storey buildings with blue windows, green or gold awnings. Low-rise and wide variants work for campus/shops. Skyscrapers are inappropriate for this reference neighbourhood. |
| Suburban_City | 40 | 2.49 | Detached/semi-detached white houses with vivid green roofs, varied garages and porches, fences, planters, driveway/path pieces. Residential loop and student apartment stand-ins. |
| Industrial_City | 37 | 2.99 | Wide practical low-rise blocks, loading yards, solar arrays, containers and utilities. Useful for academic labs, maintenance yard and supplier meeting point. |
| ModularBuildings | 108 | 0.73 | Tan modular walls, window floors, corner pieces, pitched roofs, awnings and storefront bits. Suitable for future custom building silhouettes; not necessary to import all for the initial district. |
| Furniture | 140 | 1.87 | Domestic, kitchen, bathroom, office and seating furniture. Older pack embeds material colors and uses a different origin/scale convention. Enables five furnished enterable rooms. |
| Market | 20 | 0.74 | Stocked shelves, produce/bread displays, freezers, carts, checkout and animated employee. Actual grocery-store interior rather than empty interaction box. |
| Roads | 95 | 1.50 | Tile grid roads plus slants, broad curves, sidewalks, lamps, signs, traffic lights and dumpsters. Street furniture reused; authored ribbon road geometry better fits the aerial's irregular curves than an imposed tile grid. |
| Skateboard | 20 | 0.54 | Board, rails, half-pipe, low ledges, platforms and skater characters. Primary transport plus a landmark skate plaza. |
| Nature | 329 | 2.89 | Large older collection: trees in green/autumn/dark variants, plants, flowers, rocks, ground/water tiles, cliffs and camping props. Select temperate trees and shrubs; no tropical/cactus biome in Ottawa. |
| MoreNature | 80 | 1.24 | Additional angular autumn/pine trees, wood, rocks, outdoor structures and tools. Selected environmental dressing; farming/crafting items intentionally do not imply production systems. |
| Blasters | 40 | 1.21 | Highly stylized fictional blasters, clips, crates and target props. Suitable for an abstract late-game combat item; no realistic weapon construction/mechanics. |
| Train | 103 | 6.64 | Passenger/freight trains, tram-like stock, rails and crossings. No rail corridor appears within the drawn playable boundary, so omitted instead of adding an implausible line. |
| WaterCraft | 46 | 1.86 | Small boats through enormous ships. The source reference has no navigable water inside the selected boundary, so omitted rather than distorting geography. |
| skybox | 0 | — | Equirectangular day/morning/night/space/alien imagery. Day-cycle lighting can use the project's procedural sky to interpolate continuously; alien/space options do not match this setting. |
| UI_Dialogs | 0 | — | Blue cartoon panels, controls, and six OGG click/switch/tap sounds. Native theme is preferable for coherent Night School typography; sounds available for interactions. |
| UI_emotes | 0 | — | Speech/thought, emotion, warning, food, money and relationship symbols in multiple styles. Good future NPC intent indicators; no need to include all raster variants. |
| UI_input | 0 | — | Extensive platform-specific key, mouse, gamepad and touch glyphs. Keyboard/mouse prompts are the initial desktop-browser target. |

All fifteen 3D-pack overview previews were visually inspected, along with the
skybox/UI previews and individual male character previews. The source map image
was inspected directly. This audit distinguishes visual evidence from model
names rather than assuming filenames are sufficient.

## Scale, origin, animation, and palette findings

Units are **not consistent across packs**. Buildings are tabletop-scale,
characters about 0.7 source units tall, cars a few units long, and furniture has
different dimensions/origins. Placing raw scenes side-by-side produces a giant
car next to a tiny building. The world uses explicit metre-like target dimensions
and ground-centres each model using transformed scene bounds.

| Source model | Source bounds X × Y × Z | Runtime interpretation |
| --- | --- | --- |
| Characters/character-male-f | 0.767 × 0.671 × 0.340 | Green hoodie protagonist; target adult height about 1.7 |
| Characters/character-male-c | 0.767 × 0.793 × 0.461 | Police uniform and cap; target adult height about 1.7 |
| Cars/sedan | 1.50 × 1.30 × 2.55 | Around 1.7 uniform scale gives readable stylized car length 4.34 |
| Commercial_City/building-a | 0.884 × 1.293 × 0.940 | Multistorey building; target roughly 8 × 10.5 × 11 |
| Suburban_City/building-type-a | 1.30 × 0.834 × 1.028 | House target roughly 11.5 × 6.4 × 9 |
| Furniture/bedSingle | 0.571 × 0.375 × 1.125 | Interior furnishings sized explicitly for walkable dollhouse rooms |
| Skateboard/skateboard | 0.30 × 0.137 × 0.70 | Board about 1.1 units long |

The character GLBs are animated, not static statues. They contain `static`,
`idle`, `walk`, `sprint`, `jump`, `fall`, `crouch`, `sit`, `drive`, `die`,
`pick-up`, yes/no emotes, holding poses, shoot poses, right/left melee and kick,
interact animations, and wheelchair-specific poses/motion. Prefer these clips
for animation before synthesizing limb movements. The full list is recorded in
the manifest. Male-c is the police model; male-f wears a green hoodie. Male-a
also wears green/orange casual clothing; male-d wears a smart student jacket;
male-e wears glasses and a white top. Visual police roles should not be assigned
by alphabetical guesswork.

Newer GLBs reference **external `Textures/colormap.png` files**. Each pack has
its own palette despite the identical filename. Flattening the selected assets
into one folder would silently recolor models. Curated assets preserve a
subdirectory per pack and copy every referenced image. Furniture/Nature use
embedded material colors in the inspected files. The script checks image URIs
for all models, rather than assuming all GLBs are self-contained.

## Runtime curation

Initial selection: **148 models, 11.50 MiB raw GLBs**, excluding texture and
Godot import overhead. `art/asset_manifest.json` records every selected model and
the exact `res://` path. `world_assets.gd` caches imported PackedScenes and
normalizes their origins and size. The original 1,175 files remain untouched.

Selection is deliberately broader than the first authored scene, so characters,
vehicles, furnishings and combat visuals can be implemented without repeatedly
pulling from ignored source packs. Future assets must be added through
`SELECTION` in the curation script, with their pack license and image references.

## Rendering and coherent use

- The visual direction is a miniature modern district with muted sage lawns,
  warm concrete, charcoal roads, dark signage, mint campus markers, amber shops
  and lavender residential markers. Existing colored roofs/awnings preserve the
  supplied identity without saturating the whole ground plane.
- A small procedural grass shader supplies subtle irregular color and mowing
  variation. It uses basic Compatibility-supported spatial shader operations,
  no external generated texture and no Forward+ dependency.
- Older Nature models were found to declare metallic foliage/bark and strongly
  cyan leaf colors. Runtime material overrides set their metallic value to zero
  and use sage, pine, ochre and natural bark colors. The original files stay
  intact. This was confirmed through actual rendered gameplay inspection.
- Repeated pavement markings, parking stripes, planter bases, trim and small
  structures use MultiMesh batches grouped by material. Model resources are
  cached; distant props/buildings have bounded draw distances.
- Road widths, sidewalk offsets, parking stalls and door approaches are authored
  at human scale. Building collisions use simplified footprints, avoiding
  expensive concave imported-mesh collision in the browser.
- Railways, boats, agricultural crops, giant factories and downtown towers are
  intentionally excluded from this compact campus-adjacent map because the
  supplied reference does not justify their placement. Availability is a design
  resource, not a requirement to put every object into one neighbourhood.

## Attribution and reference handling

Kenney assets are CC0 and their selected licenses are retained. The supplied
Google Maps screenshot is **reference only**: it is not a runtime texture and
must not be exported with the playable game. The authored district is a
compressed interpretation with fictional institution and business names, not a
survey-accurate recreation or an implication that real residents/businesses are
connected to the game's fictional criminal events.
