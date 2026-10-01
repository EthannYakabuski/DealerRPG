# Night School: district layout

## What the supplied aerial actually shows

The black boundary encloses College Square Mall and commercial parking to the
west/northwest; a curving Deerfield Drive residential precinct in the northeast;
and large Algonquin campus blocks, paths, squares, parking and teaching buildings
across the south/east. Baseline Road diagonally bounds the north, Woodroffe forms
the west, and College Avenue the south. Navaho Drive curves through the western
commercial/campus seam and Wabishesh Private is a north/south internal spine.
The experimental-farm water/park features are northwest **outside** the drawn
boundary. No river, marina, docks or rail line is visible within it.

The playable city preserves those spatial relationships while compressing
distance, replacing branded buildings with fictional equivalents, and expanding
walkable social spaces. It is not a rectangular downtown street grid.

## Coordinate system and proportions

- City slab: X -156…156; Z -128…128. North is negative Z.
- Playable boundary: X ±154; Z ±126, with physical containment walls at edges.
- Adult character: approximately 1.7 units high. Typical road: 6.5–11 units
  wide plus sidewalks. Typical house: 11.5 × 9 units footprint, 6.4 high.
- Campus south/east roughly half the inhabited area; commercial northwest and
  residential northeast occupy the remaining quarters. Treed margins soften
  the compressed boundary.
- Camera angle and diagonal roads make the result a legible miniature district.
  The source geography is the guide, not a geospatial coordinate transform.

## Primary anchors

Coordinates are `(X, Z)`; positions use ground Y about 0.17.

| Stable ID | Fictional landmark | Position | Function |
| --- | --- | --- | --- |
| campus_quad | Campus quad | 20, 49 | Tutorial friend and meet location |
| classroom | Lecture hall | 32, 39 | Daily attendance and enterable room |
| library | Learning commons | -18, 65 | Tuition/student services and enterable library |
| cafe | Night Owl café | -63, -14 | Food, social meet and furnished café |
| market | Corner market | -84, -36 | Food/supply shopping and furnished grocery store |
| home | Deerfield apartment | 78, -59 | Rest, parties and furnished student apartment |
| car_park | West campus parking | -82, 47 | Meetings and parked vehicles |
| supplier | Service yard | -95, 77 | Underground supply connection |
| auto_dealer | Second Hand Motors | -109, -4 | Late-game legal car purchase |
| skate_park | Deerfield skate spot | 116, 8 | Skateboard/social landmark |
| bus_stop | Baseline transit | -30, -82 | Additional public meeting site |
| residence | Student residence | 83, 57 | Campus social meeting site |

Initial player spawn is `(20, 0.2, 50)`, just after class beside the quad. It is
on open paving with immediate sight of the lecture building and campus paths.

## Street hierarchy

Baseline is the broad northern diagonal; Woodroffe sweeps down the western edge;
College Avenue curves across the south. Their connected perimeter gives traffic
a sensible circulating route rather than spawning cars on disconnected strips.
Navaho curves northeast from the west edge, connecting the commercial frontage
to the internal spine. Wabishesh runs from Baseline through campus and joins the
southern road. Deerfield branches into a smaller, gently bent residential loop.
A short campus parking access and eastern service road complete the network.

Road ribbons create continuous bends with mitered offsets. Wider paving ribbons
form sidewalks; thin curb ribbons and lane/edge stripes clarify travel lanes.
Crosswalks mark principal pedestrian crossings at the campus/commercial seams.
Parking fields have bordered asphalt, independent aisle space and repeated
striped stalls. Car spawn records are supplied to the population/vehicle system
instead of putting a second decorative car on top of an interactive one.

## Campus and residential fabric

Campus buildings form several large low-rise teaching blocks, a central quad,
learning commons, residence and field house. Wider supplied commercial and
industrial models stand in for institutional massing; solar panels, campus
signage, benches, planting islands and a sculpture make function legible.
Pedestrian paths are distinct from road geometry and connect doors to the quad,
the parking lot and the east residence. Building footprints are physical
obstacles and exposed to the pathfinding layer.

Deerfield consists of varied houses and a larger apartment stand-in around the
loop. A central pedestrian spine links courtyard benches and the home entrance.
Green and autumn foliage suits an Ottawa fall semester. Plantings occur beside
streets and within courtyards, with the main road surface kept clear.

College Square uses broad low-rise retail blocks, several small storefronts,
an outdoor café terrace, grocery carts, generous parking and a transit shelter.
A modest maintenance yard near the western campus edge provides a plausible
semi-private supplier location without inventing a giant industrial district.

## Walkers, traffic and police integration

`pedestrian_routes` contains five closed waypoint circuits: quad/library,
commercial storefronts, Deerfield courtyards, east campus/skate spot and west
campus. These are authored around buildings. Population systems can assign
different speeds, offsets and destination/idle behavior to make groups and
daily patterns readable. Meeting clients should use an obstacle-aware route
between circuits/landmarks rather than travel through building solids.

Four `traffic_routes` circulate along the broad perimeter, campus spine/parking,
commercial/Navaho circuit and Deerfield loop. They follow the road centerline
with directional lane offsets. `campus_police_routes` and `city_police_routes`
are exposed separately; root owns jurisdiction, vision, pursuit and arrest.

## Enterable spaces

Five furnished, open-top interiors support top-down visibility: student
apartment, market, café, classroom and learning commons. They are independent
rooms at X offsets starting at 600, hidden until entry. This avoids roof
occlusion and ensures outdoor collision does not intersect interior furniture.
Entry hides the exterior and reveals only the selected room. Exit returns the
player to the same outdoor entrance. The room floor, perimeter and doorway
threshold are physical/visible; the persistent threshold says `EXIT / E`.

Every room uses relevant supplied furniture. Market has stocked shelves,
freezers, produce, bread, checkout and employee. Classroom contains desks,
seating, instructor desk and board. Home contains bed, work desk, laptop, sofa,
kitchen fixtures and skateboard. Library has shelves, reading tables and
computers. Café has tables, chairs, counter and coffee equipment.

## World API

`scripts/world.gd` extends `Node3D`, `class_name CityWorld`; `_ready()` builds the
city once. Parent node is at origin.

| Member | Contract |
| --- | --- |
| `landmarks` | Dictionary of records: name, position:Vector3, type, district, interior |
| `spawn_position` | Safe initial outdoor player position |
| `get_landmark(id)` | Landmark position, falling back to player spawn |
| `get_district(position)` | Campus, College Square, or Deerfield; current room uses its outdoor district |
| `nearest_landmark(position, radius)` | ID of closest outdoor interaction within range |
| `map_roads`, `road_polylines` | Array[PackedVector3Array] centerlines for maps/debugging |
| `road_widths` | Parallel array of asphalt widths |
| `map_buildings` | Array[Rect2] building visual footprints for minimap |
| `obstacle_rects` | Array[Rect2] simplified building collision/pathfinding footprints |
| `pedestrian_routes`, `traffic_routes` | Closed waypoint loops |
| `campus_police_routes`, `city_police_routes` | Jurisdiction-specific walking routes |
| `parked_car_spawns` | Records with position, rotation, model basename for vehicle system |
| `current_interior` | Empty string outside, otherwise one of five room IDs |
| `enter_interior(id)` | Shows room/hides exterior, returns player spawn Vector3 |
| `exit_interior()` | Restores exterior, returns outdoor doorway Vector3 |
| `get_interior_exit()` | Current threshold position, or Vector3.INF outside |
| `set_night(amount)` | Adjusts streetlamp emission; root owns sun/sky/day cycle |
| `update_camera_occlusion(camera_position, player_position)` | At about 5 Hz, fades obstructing building/tree/parasol visuals and updates nearby landmark labels |

The map does not create a directional light or WorldEnvironment. The game's
time-of-day presentation owns those resources. No screen-space GI, volumetric
fog or advanced renderer-only features are required.

Camera cutaways use cached alpha-material duplicate visuals, with the original
geometry set to cast shadows only while obstructing the player. Collision stays
intact and opaque rendering is restored when the camera ray clears. This works
in Compatibility; `GeometryInstance3D.transparency` alone does not. Nine small,
shadowless landmark lights and one light per visible interior warm key social
spaces after sunset without putting a dynamic shadow on every streetlamp.

`tests/test_world.gd` checks every landmark for obstacle clearance, all road
footprints against buildings, complete pedestrian circuit segments against
buildings, every traffic circuit sample against road pavement, five interior
enter/exit transitions, and Compatibility cutaway/restore behavior. Native
render captures were inspected for paving winding, asset palette fidelity,
foliage/ground color and furnished-room readability.
