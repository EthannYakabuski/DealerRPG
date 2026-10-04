extends Node3D
## Introductions have real bodies and use the same walking paths as residents.
var world: Node3D
var player: StudentPlayer
var population: CityPopulation
var party_guests: Node3D
var actors: Dictionary = {}
var conversation_id := ""
var _dirty := true
var _refresh := 0.0

func setup(city: Node3D, student: StudentPlayer, people: CityPopulation) -> void:
	world = city
	player = student
	population = people
	Game.changed.connect(func(): _dirty = true)

func reset() -> void:
	for id: String in actors.keys(): _remove(id)
	conversation_id = ""
	_dirty = true

func _physics_process(delta: float) -> void:
	if not world or Game.status != "playing": return
	_refresh -= delta
	if _dirty or _refresh <= 0.0:
		_dirty = false
		_refresh = 0.25
		_sync()
	if Game.paused: return
	for id: String in actors.keys():
		var record: Dictionary = actors[id]
		var actor: CharacterBody3D = record.node
		population._set_person_visible(actor, world.current_interior == "")
		actor.collision_layer = 4 if actor.visible else 0
		if record.state == "leaving" and population._point_offscreen(actor.position):
			_remove(id)
			continue
		if record.state == "approaching" and population._horizontal_distance(actor.position, record.target) < 0.9:
			record.state = "waiting"
		if record.state == "waiting":
			actor.velocity = Vector3.ZERO
			ActorVisuals.play(actor, "idle")
			if conversation_id == id:
				var toward: Vector3 = player.position - actor.position
				actor.rotation.y = atan2(toward.x, toward.z)
		else:
			population._move_person(record, record.target, 2.3, delta)
		if _refresh >= 0.24: population._set_model_animation_active(actor)

func _sync() -> void:
	var wanted: Dictionary = {}
	for entry: Dictionary in Game.supplier_encounters():
		if not bool(entry.get("active", true)): continue
		var id := str(entry.id)
		# An unintroduced party visitor also needs time to walk home at closing.
		if is_instance_valid(party_guests) and party_guests.guests.has(id): continue
		if not world.landmarks.has(str(entry.location_id)): continue
		wanted[id] = entry
		if not actors.has(id):
			_create(entry)
		else:
			var target: Vector3 = world.get_landmark(str(entry.location_id))
			if actors[id].state == "leaving" or actors[id].target.distance_squared_to(target) > 1.0:
				actors[id].target = target
				actors[id].state = "approaching"
				actors[id].nav_path = PackedVector3Array()
				actors[id].nav_target = Vector3.INF
	for id: String in actors.keys():
		if wanted.has(id) or id == conversation_id or actors[id].state == "leaving": continue
		var record: Dictionary = actors[id]
		var exit_point: Vector3 = population._offscreen_walk_point(record.node.position)
		if not exit_point.is_finite(): continue
		record.state = "leaving"
		record.target = exit_point
		record.nav_path = PackedVector3Array()
		record.nav_target = Vector3.INF

func _create(entry: Dictionary) -> void:
	var target: Vector3 = world.get_landmark(str(entry.location_id))
	var start: Vector3 = population._offscreen_walk_point(target)
	if not start.is_finite(): return
	var actor: CharacterBody3D = population._person("character-female-f" if int(entry.tier) == 1 else "character-male-e", 1.8)
	actor.reparent(self, false)
	actor.position = start
	var label := ActorVisuals.label(str(entry.name).to_upper(), Color("efbf77"), 21)
	label.position.y = 2.4
	actor.add_child(label)
	actors[str(entry.id)] = {"node": actor, "name": str(entry.name), "target": target, "state": "approaching", "nav_path": PackedVector3Array(), "nav_index": 0, "nav_target": Vector3.INF, "nav_timer": 0.0}
	population._ground_person(actor)

func nearest(radius: float = 3.2) -> Dictionary:
	if world.current_interior != "" or player.vehicle or Game.tutorial_step < 3: return {}
	var result: Dictionary = {}
	var best := radius
	for id: String in actors:
		if not in_reach(id, best): continue
		best = player.position.distance_to(actors[id].node.position)
		result = {"id": id, "name": str(actors[id].name), "node": actors[id].node}
	return result

func in_reach(id: String, radius: float = 3.6) -> bool:
	if world.current_interior != "" or player.vehicle or not actors.has(id): return false
	var actor: Node3D = actors[id].node
	return actors[id].state == "waiting" and actor.visible and player.position.distance_to(actor.position) <= radius and population._line_of_sight(player.position, actor.position)

func has_contact_actor(contact_id: String) -> bool:
	return actors.has(contact_id)

func capture() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in actors:
		var record: Dictionary = actors[id]
		if record.state == "leaving": continue
		var at: Vector3 = record.node.position
		result.append({"id": id, "state": str(record.state), "position": [at.x, at.y, at.z]})
	return result

func restore(saved: Array) -> void:
	_sync()
	for entry: Dictionary in saved:
		var id := str(entry.get("id", ""))
		if not actors.has(id): continue
		var coordinates: Array = entry.get("position", [])
		if coordinates.size() != 3: continue
		var at := Vector3(float(coordinates[0]), float(coordinates[1]), float(coordinates[2]))
		if not at.is_finite() or absf(at.x) > 153 or absf(at.z) > 125: continue
		var record: Dictionary = actors[id]
		record.node.position = at
		record.nav_path = PackedVector3Array()
		record.nav_target = Vector3.INF
		if str(entry.get("state", "")) == "waiting" and population._horizontal_distance(at, record.target) < 1.1: record.state = "waiting"
		population._ground_person(record.node)

func _remove(id: String) -> void:
	var actor: Node3D = actors[id].node
	population._grounding_cache.erase(actor.get_instance_id())
	actor.queue_free()
	actors.erase(id)

func release_to_party(id: String) -> CharacterBody3D:
	if not actors.has(id): return null
	var actor: CharacterBody3D = actors[id].node
	actors.erase(id)
	conversation_id = ""
	# The party helper reuses this pedestrian instead of spawning a second Sable.
	return actor
