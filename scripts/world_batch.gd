extends RefCounted
## Repeated paint markings, paving, and trim share instanced primitive meshes.
## This keeps a detailed city practical in WebGL Compatibility rendering.

var groups: Dictionary = {}
var materials: Dictionary = {}
const CHUNK_SIZE := 32.0

func material(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var key := color.to_html() + str(glow)
	if materials.has(key):
		return materials[key]
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.9
	if glow > 0.0:
		result.emission_enabled = true
		result.emission = color
		result.emission_energy_multiplier = glow
	materials[key] = result
	return result

func box(position: Vector3, size: Vector3, color: Color, angle: float = 0.0, glow: float = 0.0) -> void:
	var casts_shadows := size.y > 0.4 or position.y-size.y*0.5 > 0.45
	var key := "box" + color.to_html() + str(glow) + str(casts_shadows)
	if not groups.has(key):
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		mesh.material = material(color, glow)
		groups[key] = {"mesh": mesh, "transforms": [], "casts_shadows": casts_shadows}
	var basis := Basis(Vector3.UP, angle).scaled_local(size)
	groups[key].transforms.append(Transform3D(basis, position))

func cylinder(position: Vector3, radius: float, height: float, color: Color) -> void:
	var casts_shadows := height > 0.4 or position.y-height*0.5 > 0.45
	var key := "cylinder" + color.to_html() + str(casts_shadows)
	if not groups.has(key):
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.5
		mesh.bottom_radius = 0.5
		mesh.height = 1.0
		mesh.radial_segments = 16
		mesh.material = material(color)
		groups[key] = {"mesh": mesh, "transforms": [], "casts_shadows": casts_shadows}
	var basis := Basis.IDENTITY.scaled(Vector3(radius * 2.0, height, radius * 2.0))
	groups[key].transforms.append(Transform3D(basis, position))

func flush(parent: Node3D) -> void:
	for key in groups:
		var entry: Dictionary = groups[key]
		# A citywide MultiMesh has one enormous visibility bound. Small spatial
		# batches allow the renderer to reject offscreen paint, paving and trim.
		var chunks: Dictionary = {}
		for transform: Transform3D in entry.transforms:
			var cell := Vector2i(floori(transform.origin.x/CHUNK_SIZE),floori(transform.origin.z/CHUNK_SIZE))
			if not chunks.has(cell): chunks[cell]=[]
			chunks[cell].append(transform)
		for cell: Vector2i in chunks:
			var transforms: Array=chunks[cell]
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = entry.mesh
			multimesh.instance_count = transforms.size()
			for index in transforms.size():
				multimesh.set_instance_transform(index, transforms[index])
			var instance := MultiMeshInstance3D.new()
			instance.name = "CityDetails_%s_%d_%d" % [key,cell.x,cell.y]
			instance.multimesh = multimesh
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if entry.casts_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(instance)
	groups.clear()
