extends SceneTree
## Native visual review of the meeting card and short transaction feedback.

var scene: Node
var state: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	state=root.get_node("Game")
	state.save_path="res://.godot/feedback-capture-save.json"
	state.set_process(false)
	scene=load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.start_game(false)
	state.paused=true
	state.split_flower()
	state.tutorial_sell()
	state.add_tutorial_contact()
	state.advance_time(90)
	state.schedule_meeting(int(state.inbox[0].id),"library",90,22)
	state.minute=float(state.active_meetings()[0].due_minute)-12
	scene.ui.toast_timer=0
	scene.ui._update_hud()
	await create_timer(3).timeout
	await _capture("meeting-card")
	# A presentation fixture; actual transaction values are covered by test_feedback.
	state.feedback_event.emit("sale",44)
	await create_timer(0.35).timeout
	await _capture("transaction-feedback")
	state.minute=float(state.active_meetings()[0].due_minute)+7
	scene.ui._update_hud()
	await create_timer(2.8).timeout
	await _capture("meeting-late")
	scene._release_audio(scene)
	await create_timer(0.15).timeout
	scene.queue_free()
	await process_frame
	DirAccess.remove_absolute(state.save_path)
	quit()

func _capture(file:String) -> void:
	await RenderingServer.frame_post_draw
	var dir:String=ProjectSettings.globalize_path("res://build/screenshots/feedback")
	DirAccess.make_dir_recursive_absolute(dir)
	var captured:Image=root.get_texture().get_image()
	captured.save_png(dir.path_join(file+".png"))
	print("Captured feedback/"+file)
