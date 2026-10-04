extends SceneTree
## Bounded visual review using actual world actors, pursuit state and feedback.
var scene: Node
var game: Node
var output := "res://build/screenshots/pursuit-review"

func _initialize() -> void: call_deferred("_run")

func _capture(name: String, delay: float = 0.3) -> void:
	await create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output.path_join(name+".png")))
	print("Captured pursuit-review/"+name)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	game = root.get_node("Game")
	game.save_path = "res://.godot/pursuit-review-save.json"
	game.set_process(false)
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.start_game(false)
	game.tutorial_step = 3
	game.minute = 1030.0
	scene.player.set_physics_process(false)
	scene.population.set_physics_process(false)
	scene.party_guests.set_physics_process(false)
	scene.supplier_encounters.set_physics_process(false)
	scene.player.position = Vector3(-60,0.2,-17)
	scene.player.facing = Vector3(0,0,-1)
	scene.player.visual.rotation.y = PI
	scene.camera.position = scene.player.position+Vector3(24,38,28)
	scene.camera.look_at(scene.player.position)
	var officer: Dictionary = {}
	for candidate: Dictionary in scene.population.police:
		candidate.node.position = Vector3(145,0.2,112)
		if officer.is_empty() and not bool(candidate.campus): officer = candidate
	officer.node.position = scene.player.position+Vector3(0,0,-8)
	officer.node.rotation.y = 0.0
	scene.population._ground_person(officer.node)
	for incident in 5:
		game.register_pursuit("cafe")
		if incident<4: game.end_pursuit()
	scene.population.pursuit = true
	scene.population.crime_position = scene.player.position
	officer.alert = 10.0
	scene._update_location()
	scene.ui.toast_timer = 0.0
	scene.population._update_police_fire(officer,0.4,true,8.0)
	await _capture("01-armed-officer")
	scene.population._update_police_fire(officer,0.41,true,8.0)
	await _capture("02-police-shot",0.02)
	# Move into the actual striking radius and show the real stunned reaction.
	scene.player.position = officer.node.position+Vector3(0,0,1.7)
	scene.player.facing = Vector3.FORWARD
	scene.population.attack("punch")
	await _capture("03-melee-stun")
	scene.player.reset_travel()
	scene.player.position = scene.world.enter_interior("deerfield_social")
	scene.camera.position = scene.player.position+Vector3(24,38,28)
	scene.camera.look_at(scene.player.position)
	scene._update_location()
	game.end_pursuit()
	scene.population.pursuit = false
	scene.ui.toast_timer = 0.0
	await _capture("04-neighbor-room")
	scene._release_audio(scene)
	await create_timer(0.15).timeout
	scene.queue_free()
	await process_frame
	DirAccess.remove_absolute(game.save_path)
	quit(0)
