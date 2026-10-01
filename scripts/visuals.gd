class_name ActorVisuals
extends RefCounted

static var cache: Dictionary = {}

static func model(pack: String, asset: String, height: float = 1.8) -> Node3D:
	var root := Node3D.new()
	var path := "res://art/models/%s/%s.glb" % [pack, asset]
	if not ResourceLoader.exists(path):
		var fallback := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.height = height
		capsule.radius = height * 0.18
		fallback.mesh = capsule
		fallback.position.y = height * 0.5
		root.add_child(fallback)
		return root
	if not cache.has(path):
		cache[path] = load(path)
	var scene: Node3D = cache[path].instantiate()
	root.add_child(scene)
	var bounds: AABB = bounds_of(scene)
	var factor: float = height / maxf(bounds.size.y, 0.01)
	scene.scale = Vector3.ONE * factor
	scene.position = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z) * factor
	return root

static func bounds_of(node: Node3D, transform_acc: Transform3D = Transform3D.IDENTITY) -> AABB:
	var result := AABB()
	var first := true
	var combined: Transform3D = transform_acc * node.transform
	if node is MeshInstance3D and node.mesh:
		result = combined * node.get_aabb()
		first = false
	for child in node.get_children():
		if child is Node3D:
			var b: AABB = bounds_of(child, combined)
			if b.size.length_squared() > 0.00001:
				result = b if first else result.merge(b)
				first = false
	return result

static func animator(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	# Every actor asks for the same animation thousands of times. Keep a weak
	# reference on that actor, never a global reference that outlives its scene.
	var cached: Variant = node.get_meta("_actor_animation_player",false)
	if cached is WeakRef:
		var existing: Variant = cached.get_ref()
		if is_instance_valid(existing) and existing is AnimationPlayer and node.is_ancestor_of(existing):
			return existing
	var found: AnimationPlayer = _find_animator(node)
	if found:
		node.set_meta("_actor_animation_player",weakref(found))
	return found

static func _find_animator(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found: AnimationPlayer = _find_animator(child)
		if found:
			return found
	return null

static func play(node: Node, name_hint: String, loop: bool = true) -> void:
	var anim: AnimationPlayer = animator(node)
	if not anim:
		return
	var clips: Dictionary = anim.get_meta("_actor_animation_hints",{})
	var animation_name: StringName = clips.get(name_hint,&"")
	if animation_name==&"" or not anim.has_animation(animation_name):
		for candidate: StringName in anim.get_animation_list():
			if String(candidate).get_file()==name_hint or String(candidate).ends_with(name_hint):
				animation_name = candidate
				clips[name_hint] = candidate
				anim.set_meta("_actor_animation_hints",clips)
				break
	if animation_name==&"" or not anim.has_animation(animation_name):
		return
	if anim.current_animation==animation_name and anim.is_playing():
		return
	anim.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	anim.play(animation_name,0.15)

static func material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

static func ground_ring(color: Color, radius: float = 0.8) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius * 0.86
	mesh.outer_radius = radius
	mesh.rings = 24
	mesh.ring_segments = 6
	node.mesh = mesh
	node.material_override = material(color, true)
	node.scale.y = 0.09
	node.position.y = 0.09
	return node

static func label(text: String, color: Color = Color.WHITE, size: int = 32) -> Label3D:
	var node := Label3D.new()
	node.text = text
	node.font_size = size
	node.pixel_size = 0.015
	node.modulate = color
	node.outline_size = 5
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.no_depth_test = false
	return node
