extends SceneTree
## Run with a real graphics driver, not --headless. Output is ignored build art.

var scene: Node3D
var state: Node
var output_directory: String

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	output_directory = ProjectSettings.globalize_path("res://build/screenshots")
	DirAccess.make_dir_recursive_absolute(output_directory)
	state = root.get_node("Game")
	state.save_path = "res://.godot/render-capture-save.json"
	state.set_process(false)
	state.restart_game()
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await _capture("01-title")
	scene.start_game(false)
	state.paused = true
	scene.ui.toast_timer = 0.0
	await _capture("02-campus-gameplay")
	scene.ui.show_page("backpack")
	await _capture("03-backpack")
	scene.ui.show_page("map")
	await _capture("04-city-map")
	scene.ui.close_page()
	scene.enter_building("home")
	state.paused = true
	_center_camera()
	await _capture("05-apartment")
	scene.player.position = scene.world.exit_interior() + Vector3(0, 0.3, 0)
	scene.player.position = Vector3(-62, 0.3, -22)
	state.minute = 20.0 * 60.0
	scene._update_lighting()
	_center_camera()
	await _capture("06-evening")
	_stop_audio(scene)
	await create_timer(0.15).timeout
	scene.queue_free()
	await process_frame
	if FileAccess.file_exists(state.save_path):
		DirAccess.remove_absolute(state.save_path)
	print("RENDER CAPTURES: " + output_directory)
	quit(0)

func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D or node is AudioStreamPlayer2D:
		node.stop()
		node.stream = null
	for child in node.get_children():
		_stop_audio(child)

func _center_camera() -> void:
	scene.camera.position = scene.player.position + Vector3(24, 38, 28)
	scene.camera.look_at(scene.player.position)

func _capture(filename: String) -> void:
	await create_timer(0.65).timeout
	await RenderingServer.frame_post_draw
	var captured: Image = root.get_texture().get_image()
	var result: Error = captured.save_png(output_directory.path_join(filename + ".png"))
	if result != OK:
		push_error("Could not save render capture: " + filename)
		quit(1)
	print("Captured " + filename)
