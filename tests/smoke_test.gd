extends SceneTree
## Assembles the real game and checks imported actors, movement, UI, and interiors.
## Test saves are isolated from the player's browser/native campaign.

var checks: int = 0
var failures: int = 0
var scene: Node3D
var state: Node

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("SCENE SMOKE: " + description)

func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D or node is AudioStreamPlayer2D:
		node.stop()
		node.stream = null
	for child in node.get_children():
		_stop_audio(child)

func _run() -> void:
	state = root.get_node("Game")
	state.save_path = "res://.godot/scene-smoke-save.json"
	state.set_process(false)
	state.restart_game()
	var packed: PackedScene = load("res://main.tscn")
	_check(packed != null, "main scene loads")
	if packed == null:
		quit(1)
		return
	scene = packed.instantiate()
	root.add_child(scene)
	await process_frame
	_check(scene.player is CharacterBody3D, "player is a physics character")
	_check(scene.camera != null and scene.camera.current, "game camera is current")
	_check(scene.ui != null and scene.ui.title_screen.visible, "title screen is visible on boot")
	_check(state.paused and not scene.started, "title screen pauses the campaign")
	_check(scene.world.exterior.get_child_count() > 50, "authored world contains rendered geometry")
	for id: String in ["campus_quad", "classroom", "library", "cafe", "market", "home", "supplier", "auto_dealer", "skate_park"]:
		_check(scene.world.landmarks.has(id), "landmark exists: " + id)
	_check(not scene.world.pedestrian_routes.is_empty(), "pedestrian routes exist")
	_check(not scene.world.traffic_routes.is_empty(), "traffic routes exist")
	_check(scene.population.citizens.size() >= 20, "city has ambient citizens")
	_check(scene.population.police.size() >= 2, "campus and city patrols exist")
	_check(scene.population.vehicles.size() >= 5, "traffic and parked vehicles exist")
	_check(scene.population.friend != null, "tutorial contact has a world actor")
	var animation: AnimationPlayer = ActorVisuals.animator(scene.player.visual)
	_check(animation != null, "player uses the imported character rig")
	if animation:
		_check(animation.get_animation_list().size() >= 5, "player has imported animation clips")
		ActorVisuals.play(scene.player.visual, "walk")
		_check(String(animation.current_animation).ends_with("walk"), "walk animation resolves")
		ActorVisuals.play(scene.player.visual, "idle")
		_check(String(animation.current_animation).ends_with("idle"), "idle animation resolves")
	_check(ActorVisuals.animator(scene.population.friend) != null, "tutorial contact uses an animated rig")
	scene.start_game(false)
	await process_frame
	_check(scene.started and not state.paused, "starting a story enables gameplay")
	_check(scene.ui.hud.visible and not scene.ui.title_screen.visible, "gameplay HUD replaces title")
	var initial_position: Vector3 = scene.player.position
	Input.action_press("move_down")
	for frame in range(30):
		await physics_frame
	Input.action_release("move_down")
	_check(scene.player.position.distance_to(initial_position) > 0.25, "keyboard movement changes player position")
	scene.player.toggle_skateboard()
	_check(scene.player.skateboarding, "starting skateboard can be equipped")
	scene.player.toggle_skateboard()
	for page: String in ["messages", "contacts", "agenda", "suppliers", "backpack", "map", "tuition", "home", "help", "pause"]:
		scene.ui.show_page(page)
		await process_frame
		_check(scene.ui.modal != null and state.paused, "menu opens and pauses gameplay: " + page)
		scene.ui.close_page()
		await process_frame
	for id: String in ["home", "market", "cafe", "classroom", "library"]:
		scene.enter_building(id)
		await process_frame
		_check(scene.world.current_interior == id, "interior enters: " + id)
		_check(not scene.world.exterior.visible and scene.world.interior_nodes[id].visible, "interior visibility swaps: " + id)
		_check(scene.player.position.x > 400.0, "player moves into interior space: " + id)
		scene.interact()
		_check(scene.world.current_interior == "" and scene.world.exterior.visible, "interior exits: " + id)
	scene.navigate("cafe")
	_check(scene.destination == "cafe" and scene.navigation_marker != null, "map destination creates world marker")
	state.minute = 22.0 * 60.0
	scene._update_lighting()
	_check(scene.sun.light_energy < 0.3, "late evening changes world lighting")
	state.paused = true
	_stop_audio(scene)
	# Let the audio mixer release playback resources before the process exits.
	await create_timer(0.15).timeout
	scene.queue_free()
	await process_frame
	if FileAccess.file_exists(state.save_path):
		DirAccess.remove_absolute(state.save_path)
	print("SCENE SMOKE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
