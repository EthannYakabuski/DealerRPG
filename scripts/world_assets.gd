extends RefCounted
## Pack-aware model loading. GLB roots are recentered at ground level before
## scaling; mixed Kenney packs therefore share an explicit metre-based world.

static var manifest: Dictionary = {}
static var scenes: Dictionary = {}
static var tuned_materials: Dictionary = {}

static func initialize() -> void:
	if manifest.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://art/asset_manifest.json"))
		if parsed is Dictionary:
			manifest = parsed

static func make(key: String, dimensions: Vector3 = Vector3.ZERO, height: float = 0.0) -> Node3D:
	initialize()
	var holder := Node3D.new()
	holder.name = key.replace("/", "_")
	if not manifest.has(key):
		push_warning("Unknown curated model: " + key)
		return holder
	var record: Dictionary = manifest[key]
	if not scenes.has(key):
		scenes[key] = load(record.path)
	if not scenes[key] is PackedScene:
		return holder
	var model: Node3D = scenes[key].instantiate()
	if key.begins_with("Nature/"):
		_tune_foliage(model)
	var low: Array = record.min
	var high: Array = record.max
	var size := Vector3(maxf(high[0] - low[0], 0.001), maxf(high[1] - low[1], 0.001), maxf(high[2] - low[2], 0.001))
	var factor := Vector3.ONE
	if height > 0.0:
		factor = Vector3.ONE * (height / size.y)
	elif dimensions != Vector3.ZERO:
		factor = Vector3(dimensions.x / size.x, dimensions.y / size.y, dimensions.z / size.z)
	model.scale = factor
	model.position = -Vector3((low[0] + high[0]) * 0.5, low[1], (low[2] + high[2]) * 0.5) * factor
	holder.add_child(model)
	set_draw_distance(model, 140.0)
	return holder

static func _tune_foliage(node: Node) -> void:
	# The older Nature GLBs mark bark/leaves metallic=1 and use cyan foliage.
	# Reuse their geometry but give this Ontario autumn district matte leaves.
	var colors := {"leafsGreen":Color("637a4e"),"leafsDark":Color("446b55"),"leafsFall":Color("ba8545"),"woodBirch":Color("b6af95"),"woodBark":Color("78563b"),"woodBarkDark":Color("624a38")}
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var original: Material = node.get_active_material(surface)
			if original is StandardMaterial3D:
				var key := original.get_instance_id()
				if not tuned_materials.has(key):
					var replacement: StandardMaterial3D = original.duplicate()
					replacement.metallic = 0.0
					replacement.roughness = 1.0
					if colors.has(original.resource_name):
						replacement.albedo_color = colors[original.resource_name]
					tuned_materials[key] = replacement
				node.set_surface_override_material(surface,tuned_materials[key])
	for child in node.get_children():
		_tune_foliage(child)

static func set_draw_distance(node: Node, distance: float) -> void:
	if node is GeometryInstance3D:
		node.visibility_range_end = distance
		node.visibility_range_end_margin = 12.0
	for child in node.get_children():
		set_draw_distance(child, distance)
