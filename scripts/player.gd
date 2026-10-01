class_name StudentPlayer
extends CharacterBody3D

signal attacked(kind: String)
signal mode_changed

var visual: Node3D
var board: Node3D
var marker: MeshInstance3D
var facing := Vector3(0, 0, 1)
var skateboarding := false
var vehicle: Node3D
var blocked := false
var attack_cooldown := 0.0
var walk_time := 0.0
var camera: Camera3D
var body_shape: CollisionShape3D
var car_shape: CollisionShape3D
var weapon: Node3D
var exhausted := false
var last_safe_position := Vector3(20,0.3,50)
var last_position := Vector3(20,0.3,50)
var was_driving := false
var last_attack_kind := ""

func _ready() -> void:
	name = "Player"
	collision_layer = 2
	collision_mask = 1 | 4 | 8
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.86
	add_child(shape)
	body_shape = shape
	car_shape = CollisionShape3D.new()
	var car_box := BoxShape3D.new()
	car_box.size = Vector3(1.9,1.5,3.9)
	car_shape.shape = car_box
	car_shape.position.y = 0.77
	car_shape.disabled = true
	add_child(car_shape)
	visual = ActorVisuals.model("Characters", "character-male-f", 1.85)
	add_child(visual)
	board = ActorVisuals.model("Skateboard", "skateboard", 0.16)
	board.position.y = 0.02
	board.visible = false
	visual.add_child(board)
	weapon = ActorVisuals.model("Blasters", "blaster-a", 0.22)
	weapon.position = Vector3(0.36,1.03,0.38)
	weapon.visible = false
	visual.add_child(weapon)
	marker = ActorVisuals.ground_ring(Color("d5f276"), 0.68)
	add_child(marker)
	ActorVisuals.play(visual, "idle")

func _physics_process(delta: float) -> void:
	if blocked or Game.paused or Game.status != "playing":
		velocity = Vector3.ZERO
		return
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	if position.distance_squared_to(last_position) > 1600.0:
		velocity = Vector3.ZERO
		last_safe_position = position
	if position.y < -5.0:
		position = last_safe_position + Vector3.UP * 0.3
		velocity = Vector3.ZERO
	if is_on_floor():
		last_safe_position = position
	var indoors := position.x > 400.0
	if indoors:
		skateboarding = false
	if skateboarding and int(Game.inventory.get("skateboard",0)) == 0:
		skateboarding = false
	var driving := is_instance_valid(vehicle)
	if driving != was_driving:
		body_shape.disabled = driving
		car_shape.disabled = not driving
		was_driving = driving
	if driving:
		car_shape.rotation.y = visual.rotation.y
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction := Vector3(input.x, 0, input.y)
	if camera:
		var right := camera.global_basis.x
		var forward := camera.global_basis.z
		right.y = 0
		forward.y = 0
		direction = (right.normalized() * input.x + forward.normalized() * input.y).limit_length()
	var speed := 5.0
	if Game.energy <= 4.0:
		exhausted = true
	elif Game.energy >= 18.0:
		exhausted = false
	var sprinting := Input.is_action_pressed("sprint") and direction.length_squared() > 0.01 and not exhausted and not skateboarding and not driving
	if sprinting and Game.use_energy(delta * 6.0):
		speed = 7.7
	elif direction.length_squared() < 0.01 and not driving:
		Game.energy = minf(100.0,Game.energy + delta * 5.0)
	else:
		Game.energy = minf(100.0,Game.energy + delta * 1.5)
	if skateboarding:
		speed = 11.8
	if vehicle:
		speed = 20.0
	if Game.hunger < 15:
		speed *= 0.75
	var acceleration := 24.0 if not skateboarding else 14.0
	if vehicle:
		acceleration = 10.0 if direction.length_squared() > 0.01 else 16.0
	velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
	if not is_on_floor():
		velocity.y -= 20 * delta
	else:
		velocity.y = -0.5
	move_and_slide()
	if indoors:
		var room_center := 600.0 + clampf(roundf((position.x-600.0)/80.0),0.0,4.0)*80.0
		position.x = clampf(position.x,room_center-9.4,room_center+9.4)
		position.z = clampf(position.z,-7.4,7.4)
	else:
		position.x = clampf(position.x,-153.0,153.0)
		position.z = clampf(position.z,-125.0,125.0)
	last_position = position
	if direction.length() > 0.08:
		facing = direction.normalized()
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(facing.x, facing.z), delta * 12)
		walk_time += delta
		if attack_cooldown <= 0.25:
			ActorVisuals.play(visual, "crouch" if skateboarding else ("sprint" if sprinting else "walk"))
	elif attack_cooldown <= 0.25:
		ActorVisuals.play(visual, "idle")
	if skateboarding:
		visual.position.y = 0.14
	else:
		visual.position.y = 0.0
	if vehicle:
		vehicle.global_position = global_position
		vehicle.rotation.y = lerp_angle(vehicle.rotation.y, visual.rotation.y, delta * 7)
		visual.visible = false
	else:
		visual.visible = true
	board.visible = skateboarding and not vehicle
	weapon.visible = last_attack_kind == "shoot" and int(Game.inventory.get("pistol",0)) > 0 and attack_cooldown > 0.15 and not skateboarding and not vehicle

func toggle_skateboard() -> void:
	if vehicle or blocked or Game.paused or Game.status != "playing":
		return
	if position.x > 400.0:
		Game.notification.emit("Carry your board indoors. There is more room to ride outside.")
		return
	if int(Game.inventory.get("skateboard", 0)) <= 0:
		Game.notification.emit("Your skateboard is not in your backpack.")
		return
	skateboarding = not skateboarding
	mode_changed.emit()
	Game.notification.emit("Skateboard equipped. Hold a direction to build speed." if skateboarding else "Back on foot.")

func attack(kind: String) -> void:
	if blocked or Game.paused or attack_cooldown > 0 or Game.status != "playing" or vehicle:
		return
	if kind not in ["shoot","punch","kick"]:
		return
	if kind == "shoot":
		if not Game.use_ammo():
			return
	elif not Game.use_energy(8.0 if kind == "kick" else 5.0):
		Game.notification.emit("Catch your breath before striking again.")
		return
	skateboarding = false
	last_attack_kind = kind
	attack_cooldown = 0.65 if kind != "kick" else 0.85
	ActorVisuals.play(visual, "holding-right-shoot" if kind == "shoot" else ("attack-kick-right" if kind == "kick" else "attack-melee-right"), false)
	attacked.emit(kind)

func reset_travel() -> void:
	vehicle = null
	skateboarding = false
	exhausted = false
	attack_cooldown = 0.0
	last_attack_kind = ""
	velocity = Vector3.ZERO
	blocked = false
	was_driving = false
	if body_shape:
		body_shape.disabled = false
	if car_shape:
		car_shape.disabled = true
	if visual:
		visual.visible = true
		visual.position.y = 0.0
	if board:
		board.visible = false
	if weapon:
		weapon.visible = false
	mode_changed.emit()

func travel_mode() -> String:
	if vehicle:
		return "DRIVING"
	return "SKATEBOARD" if skateboarding else "ON FOOT"
