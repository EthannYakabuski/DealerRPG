extends SceneTree
## Bounded visual QA: whole map and campus paving, using the actual renderer.

var world: Node3D
var camera: Camera3D
var output_directory: String

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	output_directory = ProjectSettings.globalize_path("res://build/screenshots/world-qa")
	DirAccess.make_dir_recursive_absolute(output_directory)
	world = load("res://scripts/world.gd").new()
	root.add_child(world)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("243638")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c4d8d8")
	environment.ambient_light_energy = 0.35
	environment_node.environment = environment
	root.add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52,-32,0)
	sun.light_energy = 0.72
	sun.light_color = Color("fff0d1")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 450.0
	root.add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 270
	camera.far = 600
	camera.position = Vector3(0,320,0)
	root.add_child(camera)
	camera.look_at(Vector3.ZERO,Vector3.FORWARD)
	camera.current = true
	_remove_distance_culling(world.exterior)
	await _capture("01-whole-map")
	camera.size = 41
	camera.position = Vector3(20,0,50)+Vector3(24,38,28)
	camera.look_at(Vector3(20,0,50))
	sun.directional_shadow_max_distance = 100
	await _capture("02-campus-paving")
	var sites := {"03-west-parking":Vector3(-86,0,46),"04-west-overlook":world.get_landmark("west_overlook"),"05-freight-lane":world.get_landmark("service_lane"),"06-east-trail":world.get_landmark("east_trail"),"07-neighbor-door":world.get_landmark("deerfield_social")}
	for filename: String in sites:
		var at: Vector3 = sites[filename]
		camera.size = 68 if filename=="03-west-parking" else 30
		camera.position = at+Vector3(10,45,26)
		camera.look_at(at)
		world.update_camera_occlusion(camera.position,at)
		await _capture(filename)
	world.enter_interior("deerfield_social")
	camera.size = 26
	camera.position = Vector3(1000,0,0)+Vector3(10,45,26)
	camera.look_at(Vector3(1000,0,0))
	await _capture("08-neighbor-room")
	world.queue_free()
	await process_frame
	print("WORLD QA CAPTURES: ",output_directory)
	quit(0)

func _remove_distance_culling(node: Node) -> void:
	if node is GeometryInstance3D:
		node.visibility_range_end = 0
	if node is Label3D:
		node.visible = false
	for child in node.get_children():
		_remove_distance_culling(child)

func _capture(filename: String) -> void:
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var captured := root.get_texture().get_image()
	var result := captured.save_png(output_directory.path_join(filename+".png"))
	assert(result == OK)
