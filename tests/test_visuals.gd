extends SceneTree
## Regression coverage for cached animation lookups and actor lifetime safety.

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("VISUAL CHECK: "+description)

func _player() -> AnimationPlayer:
	var player := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	for name: String in ["walk","idle","attack"]:
		var animation := Animation.new()
		animation.length = 1.0
		library.add_animation(name,animation)
	player.add_animation_library("motion",library)
	return player

func _run() -> void:
	var actor := Node3D.new()
	var container := Node3D.new()
	var animation_player := _player()
	actor.add_child(container)
	container.add_child(animation_player)
	root.add_child(actor)
	_check(ActorVisuals.animator(actor)==animation_player,"nested AnimationPlayer resolves")
	_check(actor.get_meta("_actor_animation_player") is WeakRef,"actor stores a weak reference rather than a global owner")
	ActorVisuals.play(actor,"walk")
	_check(animation_player.current_animation=="motion/walk","hint resolves imported library clip")
	_check(animation_player.get_meta("_actor_animation_hints").get("walk")==&"motion/walk","clip hint is cached on its AnimationPlayer")
	animation_player.advance(0.3)
	var position: float = animation_player.current_animation_position
	for iteration in range(1000): ActorVisuals.play(actor,"walk")
	_check(is_equal_approx(animation_player.current_animation_position,position),"repeated steady-state calls do not restart playback")
	ActorVisuals.play(actor,"attack",false)
	_check(animation_player.current_animation=="motion/attack" and animation_player.get_animation("motion/attack").loop_mode==Animation.LOOP_NONE,"nonlooping action remains supported")
	ActorVisuals.play(actor,"missing")
	_check(animation_player.current_animation=="motion/attack","unknown animation leaves current playback intact")
	container.remove_child(animation_player)
	animation_player.free()
	var replacement := _player()
	container.add_child(replacement)
	ActorVisuals.play(actor,"idle")
	_check(ActorVisuals.animator(actor)==replacement and replacement.current_animation=="motion/idle","freed cached player safely resolves a replacement")
	var library: AnimationLibrary = replacement.get_animation_library("motion")
	ActorVisuals.play(actor,"walk")
	library.remove_animation("walk")
	var changed := Animation.new()
	library.add_animation("new-walk",changed)
	ActorVisuals.play(actor,"walk")
	_check(replacement.current_animation=="motion/new-walk","removed cached clip re-resolves an updated library")
	actor.queue_free()
	await process_frame
	print("VISUAL TESTS: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
