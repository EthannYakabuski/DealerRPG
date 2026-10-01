# Final world and visual QA

Verified with Godot 4.5.1 Compatibility / native OpenGL 3.3 on the available
NVIDIA GT 1030. `tools/world_review_capture.gd` produces an unobstructed overhead
map and a close campus view in `build/screenshots/world-qa/`. These generated
images are review artifacts, not game assets.

## Findings corrected

1. **Jagged diagonal paving outlines were real rendering artifacts.** Road and
   path geometry reused walking-route points with Y = 0.16, then added its own
   surface height. This lifted ribbons above the quad slab, so their edges cast
   unexpected diagonal/triangular shadows across it. Geometry now starts at
   ground Y = 0; actor route heights remain separate. Flat pavement, markings,
   and soil/marker disks no longer cast shadows. Trees, buildings, furniture,
   sculpture, and other raised structures retain shadows. The repeated thin
   lines across regular sidewalk slabs are intentional expansion joints.
2. **Outer road corner silhouettes looked disconnected from directly above.**
   Shared ribbon endpoints now receive matched asphalt, curb, and sidewalk
   corner fills. The road centerlines and traffic circuits are unchanged.
3. **The commercial parking rectangle extended under its neighbouring shop.**
   Its footprint was trimmed and shifted within the same commercial parcel.
   Parking paint now stays below road asphalt at driveway overlaps instead of
   drawing stall lines across the road. No building or landmark moved.
4. **Two existing parking slots now use the supplied police vehicle model.**
   One is in the western campus lot and one in the College Square lot. The
   number of parked vehicles remains 24; no overlapping duplicate cars were
   added to the decorative world.

## Whole-map inspection

The overhead render confirms the supplied reference's broad topology: diagonal
Baseline along the north, sweeping west/south perimeter roads, a connected
Navaho/internal-campus spine, College Square retail and parking to the west,
Deerfield's residential loop in the northeast, and teaching/residence buildings
around southern/eastern campus paths. Pavement is continuous at junctions.
There are no missing imported building meshes, terrain holes, detached map
chunks, or unexpected giant assets. Open grass within campus parcels and the
outer tree margin is intentional. This is a compressed fictional district,
not a lot-by-lot or survey-accurate reconstruction.

The close-up confirms coherent cream paving, muted green lawns, green/ochre
foliage, appropriately grounded street furniture, readable building massing,
and intact building/tree shadows without the false floating-path shadows.
Earlier rendered checks also verified furnished interior scale, warm nighttime
lighting, and camera cutaways that expose a player behind a café umbrella.

## Automated verification

`tests/test_world.gd` passes after these corrections:

- 27 building footprints and all 12 landmark access points checked.
- No building conflicts with authored roads or pedestrian circuits.
- Every sampled point on all four traffic circuits remains within road space.
- All five furnished rooms enter and exit at their intended positions.
- Camera cutaway reveals an obstructing café parasol, preserves original
  shadows, and restores opaque rendering after the camera moves away.
- 24 parked vehicle records remain available to the population system.

The native renderer logs the host's existing certificate-store/shader-cache
write warnings. The captures complete successfully; no GDScript or world
geometry errors were reported during these runs.
