extends SceneTree
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("SKATE SURFACE: "+message)
func _run() -> void:
	var game: Node=root.get_node("Game")
	game.save_path="res://.godot/skate-surface-test-save.json"
	game.set_process(false)
	var scene: Node=load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.start_game(false)
	scene.player.set_physics_process(false)
	scene.population.set_physics_process(false)
	scene.player.camera=null
	var paved: Vector3=scene.world.get_landmark("campus_quad")
	var grass:=Vector3(43,0.3,63)
	_check(scene.world.is_paved_surface(paved),"Campus walkway is classified as paved")
	_check(not scene.world.is_paved_surface(grass),"Open grass is classified as soft ground")
	Input.action_press("move_right")
	scene.player.skateboarding=true
	scene.player.position=grass
	for tick in 45:
		scene.player.position=grass
		scene.player._physics_process(1.0/60.0)
		await physics_frame
	_check(scene.player.board_on_grass and Vector2(scene.player.velocity.x,scene.player.velocity.z).length()<3.0,"Board crawls on grass slower than walking")
	scene.player.position=paved+Vector3(0,0.2,0)
	scene.player.velocity=Vector3.ZERO
	for tick in 50:
		scene.player.position=paved+Vector3(0,0.2,0)
		scene.player._physics_process(1.0/60.0)
		await physics_frame
	_check(not scene.player.board_on_grass and scene.player.velocity.x>10.5,"Pavement preserves original riding speed")
	scene.player.position=grass
	for tick in 25:
		scene.player.position=grass
		scene.player._physics_process(1.0/60.0)
		await physics_frame
	_check(scene.player.velocity.x<3.0,"Grass brakes existing pavement momentum promptly")
	scene.player.skateboarding=false
	scene.player.velocity=Vector3.ZERO
	for tick in 35:
		scene.player.position=grass
		scene.player._physics_process(1.0/60.0)
		await physics_frame
	_check(scene.player.velocity.x>4.5,"Walking on grass remains normal speed")
	Input.action_release("move_right")
	print("SKATE SURFACE TESTS: %d checks, %d failures"%[checks,failures])
	scene._release_audio(scene)
	await create_timer(0.15).timeout
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
