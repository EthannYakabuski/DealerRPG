class_name StudentPlayer
extends CharacterBody3D

signal attacked(kind: String)
signal mode_changed

const SKATEBOARD_LENGTH := 1.4
const SKATEBOARD_WIDTH := 0.48
const SKATEBOARD_HEIGHT := 0.19
const SKATEBOARD_DECK_HEIGHT := 0.17
const SKATEBOARD_GRASS_SPEED := 2.2

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
var city_world: Node3D
var body_shape: CollisionShape3D
var car_shape: CollisionShape3D
var weapon: Node3D
var exhausted := false
var last_safe_position := Vector3(20,0.3,50)
var last_position := Vector3(20,0.3,50)
var was_driving := false
var last_attack_kind := ""
var _grounded_position := Vector3.INF
var _grounded_heading := INF
var _grounded_board := false
var board_on_grass := false
var impact_cooldown := 0.0
var impact_velocity := Vector3.ZERO
var police_hit_cooldown := 0.0
var last_safe_vehicle_position := Vector3.INF
var last_safe_vehicle_heading := 0.0

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
	# Size a flat prop by its deck length, not its very small vertical extent.
	# Keep it beside the character model so the riding pose cannot shrink it.
	board = ActorVisuals.model("Skateboard", "skateboard", 1.0)
	var board_bounds := ActorVisuals.bounds_of(board)
	board.scale = Vector3(SKATEBOARD_WIDTH, SKATEBOARD_HEIGHT, SKATEBOARD_LENGTH) / board_bounds.size
	board.position.y = 0.015
	board.visible = false
	add_child(board)
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
		_update_grounding()
		return
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	impact_cooldown = maxf(0.0, impact_cooldown - delta)
	police_hit_cooldown = maxf(0.0, police_hit_cooldown - delta)
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
		# People cannot displace a car during the physics overlap recovery pass.
		collision_mask = 1 | 8 if driving else 1 | 4 | 8
		last_safe_vehicle_position = Vector3.INF
		if driving: car_shape.rotation.y = vehicle.rotation.y
		was_driving = driving
	if driving:
		recover_vehicle_if_blocked()
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction := Vector3(input.x, 0, input.y)
	if camera:
		var right := camera.global_basis.x
		var forward := camera.global_basis.z
		right.y = 0
		forward.y = 0
		direction = (right.normalized() * input.x + forward.normalized() * input.y).limit_length()
	if driving and direction.length_squared()>0.0064:
		_turn_vehicle_safely(lerp_angle(car_shape.rotation.y,atan2(direction.x,direction.z),minf(1.0,delta*7.0)))
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
		board_on_grass = city_world!=null and not city_world.is_paved_surface(global_position)
		speed = SKATEBOARD_GRASS_SPEED if board_on_grass else 11.8
	else:
		board_on_grass = false
	if vehicle:
		speed = 20.0
	if Game.hunger < 15:
		speed *= 0.75
	var acceleration := 24.0 if not skateboarding else 14.0
	if skateboarding and board_on_grass: acceleration=32.0
	if vehicle:
		acceleration = 10.0 if direction.length_squared() > 0.01 else 16.0
	velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
	if impact_velocity.length_squared() > 0.01:
		velocity.x = impact_velocity.x
		velocity.z = impact_velocity.z
		impact_velocity = impact_velocity.move_toward(Vector3.ZERO,delta*18.0)
	if not is_on_floor():
		velocity.y -= 20 * delta
	else:
		velocity.y = -0.5
	move_and_slide()
	if driving: recover_vehicle_if_blocked()
	if indoors:
		var room_count: int = city_world.interior_nodes.size() if city_world else 6
		var room_center := 600.0 + clampf(roundf((position.x-600.0)/80.0),0.0,float(room_count-1))*80.0
		position.x = clampf(position.x,room_center-9.4,room_center+9.4)
		position.z = clampf(position.z,-7.4,7.4)
	else:
		position.x = clampf(position.x,-153.0,153.0)
		position.z = clampf(position.z,-125.0,125.0)
	last_position = position
	if direction.length() > 0.08:
		facing = direction.normalized()
		walk_time += delta
		if attack_cooldown <= 0.25:
			ActorVisuals.play(visual, "crouch" if skateboarding else ("sprint" if sprinting else "walk"))
	elif attack_cooldown <= 0.25:
		ActorVisuals.play(visual, "crouch" if skateboarding else "idle")
	var travel_heading := atan2(facing.x, facing.z)
	# A sideways stance puts both feet along the deck while its nose follows travel.
	if driving:
		visual.rotation.y = car_shape.rotation.y
	else:
		visual.rotation.y = lerp_angle(visual.rotation.y, travel_heading + (PI * 0.5 if skateboarding else 0.0), minf(1.0, delta * 12))
	board.rotation.y = lerp_angle(board.rotation.y, travel_heading, minf(1.0, delta * 12))
	_update_grounding()
	if vehicle:
		vehicle.global_position = global_position
		vehicle.rotation.y = car_shape.rotation.y
		visual.visible = false
	else:
		visual.visible = true
	board.visible = skateboarding and not vehicle
	weapon.visible = last_attack_kind == "shoot" and int(Game.inventory.get("pistol",0)) > 0 and attack_cooldown > 0.15 and not skateboarding and not vehicle

func _update_grounding() -> void:
	if not visual or not city_world: return
	if global_position.distance_squared_to(_grounded_position)<0.000001 and absf(board.rotation.y-_grounded_heading)<0.001 and skateboarding==_grounded_board: return
	_grounded_position = global_position
	_grounded_heading = board.rotation.y
	_grounded_board = skateboarding
	var support: float = city_world.walkable_surface_height(global_position)
	if skateboarding and not vehicle:
		# Support the whole wheelbase as it straddles a curb or planted island edge.
		for x: float in [-SKATEBOARD_WIDTH*0.5,0.0,SKATEBOARD_WIDTH*0.5]:
			for z: float in [-SKATEBOARD_LENGTH*0.5,0.0,SKATEBOARD_LENGTH*0.5]:
				var sample := global_position+board.basis.orthonormalized()*Vector3(x,0,z)
				support = maxf(support,city_world.walkable_surface_height(sample))
	else:
		for offset: Vector3 in [Vector3(0.25,0,0),Vector3(-0.25,0,0),Vector3(0,0,0.25),Vector3(0,0,-0.25)]:
			support = maxf(support,city_world.walkable_surface_height(global_position+offset))
	var grounded_offset := support-global_position.y
	visual.position.y = grounded_offset+(SKATEBOARD_DECK_HEIGHT if skateboarding else 0.0)
	board.position.y = grounded_offset+0.015
	var ring_support := support
	for index in 8:
		var angle := TAU*float(index)/8.0
		ring_support = maxf(ring_support,city_world.walkable_surface_height(global_position+Vector3(cos(angle),0,sin(angle))*0.68))
	marker.position.y = ring_support-global_position.y+0.04

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
	_grounded_position = Vector3.INF
	vehicle = null
	skateboarding = false
	exhausted = false
	board_on_grass = false
	attack_cooldown = 0.0
	impact_cooldown = 0.0
	impact_velocity = Vector3.ZERO
	police_hit_cooldown = 0.0
	last_safe_vehicle_position = Vector3.INF
	collision_mask = 1 | 4 | 8
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

func receive_vehicle_impact(car_velocity: Vector3, source: Node3D) -> bool:
	if blocked or Game.paused or Game.status != "playing" or impact_cooldown > 0.0:
		return false
	if not is_instance_valid(source) or source == vehicle or position.x > 400.0:
		return false
	var speed := Vector2(car_velocity.x,car_velocity.z).length()
	if not is_finite(speed) or speed < 2.0: return false
	impact_cooldown = 1.6
	var driving := is_instance_valid(vehicle)
	var damage := clampf(speed*2.6,8.0,44.0)*(0.35 if driving else 1.0)
	skateboarding = false
	impact_velocity = Vector3(car_velocity.x,0,car_velocity.z).normalized()*clampf(speed*0.7,3.0,9.0)
	if driving: impact_velocity *= 0.35
	velocity += impact_velocity
	Game.take_damage(damage)
	Game.feedback_event.emit("impact",damage)
	Game.notification.emit("Traffic collision! -%d health. Watch the road." % int(ceil(damage)))
	mode_changed.emit()
	return true

func _turn_vehicle_safely(target_heading: float) -> void:
	if not city_world: return
	var change := angle_difference(car_shape.rotation.y,target_heading)
	var steps := maxi(1,ceili(absf(change)/0.06))
	var start := car_shape.rotation.y
	for step in range(1,steps+1):
		var angle := start+change*float(step)/float(steps)
		if not city_world.vehicle_pose_clear(global_position,angle): break
		car_shape.rotation.y = angle

func recover_vehicle_if_blocked() -> bool:
	if not is_instance_valid(vehicle) or not city_world: return false
	var heading := car_shape.rotation.y if was_driving else vehicle.rotation.y
	if city_world.vehicle_pose_clear(global_position,heading):
		last_safe_vehicle_position = global_position
		last_safe_vehicle_heading = heading
		return false
	# A valid previous pose prevents recovery from pushing the vehicle through a
	# wall. A bounded nearby search also repairs an embedded car from an old save.
	var safe := Vector3.INF
	if last_safe_vehicle_position.is_finite() and global_position.distance_squared_to(last_safe_vehicle_position)<144.0 and city_world.vehicle_pose_clear(last_safe_vehicle_position,last_safe_vehicle_heading):
		safe = last_safe_vehicle_position
		heading = last_safe_vehicle_heading
	else:
		for radius in range(1,49):
			for index in 24:
				var angle := TAU*float(index)/24.0
				var candidate := global_position+Vector3(cos(angle),0,sin(angle))*float(radius)*0.5
				if absf(candidate.x)>152.0 or absf(candidate.z)>124.0: continue
				if city_world.vehicle_pose_clear(candidate,heading):
					safe = candidate
					break
			if safe.is_finite(): break
	if not safe.is_finite(): return false
	global_position = safe
	car_shape.rotation.y = heading
	visual.rotation.y = heading
	vehicle.global_position = safe
	vehicle.rotation.y = heading
	velocity = Vector3.ZERO
	impact_velocity = Vector3.ZERO
	last_safe_vehicle_position = safe
	last_safe_vehicle_heading = heading
	return true

func receive_police_shot(damage: float, source: Node3D) -> bool:
	if blocked or Game.paused or Game.status!="playing" or police_hit_cooldown>0.0: return false
	if not is_instance_valid(source) or not is_finite(damage) or damage<=0.0 or position.x>400.0: return false
	police_hit_cooldown = 0.65
	skateboarding = false
	Game.take_damage(damage)
	Game.feedback_event.emit("impact",damage)
	Game.notification.emit("Hit by police fire! -%d health. Find cover."%int(ceil(damage)))
	mode_changed.emit()
	return true

func travel_mode() -> String:
	if vehicle:
		return "DRIVING"
	return ("SKATEBOARD / GRASS" if board_on_grass else "SKATEBOARD") if skateboarding else "ON FOOT"
