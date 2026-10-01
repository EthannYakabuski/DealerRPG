class_name CityWorld
extends Node3D
## A compact, authored interpretation of the supplied Ottawa aerial reference.
## North is -Z. Campus occupies the south/east, College Square the northwest,
## and the curved Deerfield neighbourhood the northeast.

const Art = preload("res://scripts/world_assets.gd")
const Batch = preload("res://scripts/world_batch.gd")
const GRASS := Color("75846a")
const ASPHALT := Color("343d44")
const WALK := Color("c2bba8")
const CURB := Color("d8d1bc")
const PAINT := Color("e8dfc0")
const YELLOW := Color("d5b56a")
const INK := Color("23383b")
const CAMPUS := Color("87c5b0")
const SHOP := Color("f0bd71")
const HOME := Color("c4aed8")

var landmarks: Dictionary = {}
var spawn_position := Vector3(20.0, 0.2, 50.0)
var obstacle_rects: Array[Rect2] = []
var map_buildings: Array[Rect2] = []
var map_roads: Array[PackedVector3Array] = []
var road_polylines: Array[PackedVector3Array] = []
var road_widths: Array[float] = []
var pedestrian_routes: Array[PackedVector3Array] = []
var traffic_routes: Array[PackedVector3Array] = []
var campus_police_routes: Array[PackedVector3Array] = []
var city_police_routes: Array[PackedVector3Array] = []
var parked_car_spawns: Array[Dictionary] = []
var interior_nodes: Dictionary = {}
var current_interior := ""
var exterior: Node3D
var interior_root: Node3D
var night_material: StandardMaterial3D
var interior_lights: Array[OmniLight3D] = []
var exterior_lights: Array[OmniLight3D] = []
var _batch: RefCounted
var _rng := RandomNumberGenerator.new()
var _labels: Array[Label3D] = []
var _occluders: Array[Dictionary] = []
var _fade_materials: Dictionary = {}

func _ready() -> void:
	_rng.seed = 26813
	Art.initialize()
	_batch = Batch.new()
	exterior = Node3D.new()
	exterior.name = "OttawaInspiredCity"
	add_child(exterior)
	interior_root = Node3D.new()
	interior_root.name = "Interiors"
	add_child(interior_root)
	_create_landmarks()
	_create_ground()
	_create_roads()
	_create_commercial()
	_create_campus()
	_create_residential()
	_create_park()
	_create_streetscape()
	_create_routes()
	_create_interiors()
	_create_markers()
	_batch.flush(exterior)
	road_polylines.assign(map_roads)
	set_night(0.0)

func _create_landmarks() -> void:
	_landmark("campus_quad", "Campus quad", 20, 49, "meet", "Campus")
	_landmark("classroom", "Lecture hall", 32, 39, "class", "Campus", "classroom")
	_landmark("library", "Learning commons", -18, 65, "tuition", "Campus", "library")
	_landmark("cafe", "Night Owl café", -63, -14, "food", "College Square", "cafe")
	_landmark("market", "Corner market", -84, -36, "market", "College Square", "market")
	_landmark("home", "Deerfield apartment", 78, -59, "home", "Deerfield", "home")
	_landmark("car_park", "West campus parking", -82, 47, "meet", "Campus")
	_landmark("supplier", "Service yard", -95, 77, "supplier", "College Square")
	_landmark("auto_dealer", "Second Hand Motors", -109, -4, "vehicle", "College Square")
	_landmark("skate_park", "Deerfield skate spot", 116, 8, "meet", "Deerfield")
	_landmark("bus_stop", "Baseline transit", -30, -82, "meet", "College Square")
	_landmark("residence", "Student residence", 83, 57, "meet", "Campus")

func _landmark(id: String, title: String, x: float, z: float, kind: String, district: String, interior_id: String = "") -> void:
	landmarks[id] = {"name": title, "position": Vector3(x, 0.17, z), "type": kind, "district": district, "interior": interior_id}

func get_landmark(id: String) -> Vector3:
	return landmarks.get(id, {"position": spawn_position}).position

func get_district(at: Vector3) -> String:
	if current_interior != "":
		return str(landmarks.get(current_interior, {"district": "Campus"}).district)
	if at.z < -15.0 and at.x > 31.0:
		return "Deerfield"
	if at.x < -29.0 and at.z < 28.0:
		return "College Square"
	return "Campus"

func nearest_landmark(at: Vector3, radius: float = 5.5) -> String:
	var result := ""
	var distance := radius
	for id in landmarks:
		var separation: float = at.distance_to(landmarks[id].position)
		if separation < distance:
			distance = separation
			result = id
	return result

func _create_ground() -> void:
	# Slight soil variation is generated in a cheap spatial shader; no neon lawn
	# tile atlas, large texture download, or Forward+ feature is needed.
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode diffuse_burley, specular_disabled;
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void fragment() {
  vec2 p = world_pos.xz * 0.32;
  vec2 i = floor(p); vec2 f = fract(p); f=f*f*(3.0-2.0*f);
  float n = mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
  float stripes = 0.5+0.5*sin(world_pos.x*0.18+world_pos.z*0.06);
  ALBEDO = mix(vec3(0.35,0.43,0.29),vec3(0.44,0.51,0.35),n*0.55+stripes*0.14);
  ROUGHNESS = 1.0;
}"""
	var material := ShaderMaterial.new()
	material.shader = shader
	var ground := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(312, 2, 256)
	ground.mesh = mesh
	ground.material_override = material
	# Terrain receives city shadows but has nothing above grade to cast itself.
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.position.y = -1.0
	exterior.add_child(ground)
	_collision(exterior, Vector3(0, -1.0, 0), Vector3(312, 2, 256))
	# Invisible boundary walls keep cars and players on the playable district.
	_collision(exterior, Vector3(-155, 3, 0), Vector3(1, 8, 256))
	_collision(exterior, Vector3(155, 3, 0), Vector3(1, 8, 256))
	_collision(exterior, Vector3(0, 3, -127), Vector3(312, 8, 1))
	_collision(exterior, Vector3(0, 3, 127), Vector3(312, 8, 1))
	_batch.box(Vector3(0, -2.7, 0), Vector3(313, 3.0, 257), Color("594f41"))

func _create_roads() -> void:
	_road([Vector2(-141,-49),Vector2(-97,-72),Vector2(-45,-95),Vector2(20,-116),Vector2(80,-119),Vector2(139,-112)], 11.0)
	_road([Vector2(-141,-49),Vector2(-135,-8),Vector2(-122,43),Vector2(-103,90),Vector2(-83,118)], 10.5)
	_road([Vector2(-83,118),Vector2(-17,108),Vector2(49,96),Vector2(97,78),Vector2(140,41)], 9.0)
	_road([Vector2(140,41),Vector2(143,-3),Vector2(139,-56),Vector2(139,-112)], 8.0)
	_road([Vector2(-135,-8),Vector2(-109,12),Vector2(-83,23),Vector2(-59,18),Vector2(-43,1),Vector2(-33,-22),Vector2(-10,-39),Vector2(18,-43)], 8.0)
	_road([Vector2(10,-113),Vector2(12,-78),Vector2(16,-49),Vector2(28,-13),Vector2(42,23),Vector2(57,53),Vector2(74,87)], 8.0)
	_road([Vector2(12,-90),Vector2(39,-94),Vector2(70,-104),Vector2(102,-98),Vector2(120,-79),Vector2(126,-51),Vector2(114,-28),Vector2(92,-21),Vector2(70,-27),Vector2(54,-49),Vector2(44,-74),Vector2(39,-94)], 6.5)
	_road([Vector2(-83,23),Vector2(-64,48),Vector2(-48,72),Vector2(-35,112)], 6.5)
	_road([Vector2(42,23),Vector2(71,18),Vector2(103,24),Vector2(141,31)], 6.0)
	# Pedestrian campus malls, with a small grass quad in their centre.
	_path([Vector2(-52,44),Vector2(1,48),Vector2(36,49),Vector2(76,55),Vector2(122,58)],5.5)
	_path([Vector2(-13,18),Vector2(-9,44),Vector2(-4,74),Vector2(2,101)],4.8)
	_path([Vector2(-27,72),Vector2(16,69),Vector2(40,50)],3.6)
	_path([Vector2(20,22),Vector2(20,85)],3.2)
	_path([Vector2(75,-91),Vector2(78,-59),Vector2(82,-37)],3.0)
	_path([Vector2(58,-58),Vector2(109,-57)],2.4)
	_crosswalk(Vector3(21,0,-29), 0.32, 8)
	_crosswalk(Vector3(36,0,8), 0.38, 8)
	_crosswalk(Vector3(-61,0,21),-0.52,8)
	_crosswalk(Vector3(99,0,23), PI/2, 6)
	_crosswalk(Vector3(-27,0,-27),-0.7,8)
	_ground_text("BASELINE ROAD", Vector3(-46,0.18,-98),-0.36,0.10)
	_ground_text("NAVAHO DRIVE", Vector3(-88,0.18,20),0.20,0.08)
	_ground_text("DEERFIELD",Vector3(89,0.18,-23),0.0,0.07)
	_ground_text("COLLEGE AVENUE",Vector3(20,0.18,102),-0.18,0.08)

func _road(points: Array, width: float) -> void:
	var path := _points(points,0.0)
	map_roads.append(path)
	road_widths.append(width)
	_ribbon(path,width+4.7,0.04,WALK)
	_ribbon(path,width+0.55,0.075,CURB)
	_ribbon(path,width,0.095,ASPHALT)
	# Shared endpoints need a paved corner fill: two squared ribbons alone leave
	# the outer quadrant of a turning junction looking disconnected from above.
	for endpoint in [path[0],path[path.size()-1]]:
		_batch.cylinder(endpoint+Vector3.UP*0.042,width*0.5+2.35,0.01,WALK)
		_batch.cylinder(endpoint+Vector3.UP*0.079,width*0.5+0.275,0.01,CURB)
		_batch.cylinder(endpoint+Vector3.UP*0.104,width*0.5,0.012,ASPHALT)
	for i in path.size()-1:
		var from: Vector3 = path[i]
		var toward: Vector3 = path[i+1]
		var distance := from.distance_to(toward)
		var direction := (toward-from).normalized()
		var angle := atan2(direction.x,direction.z)
		var offset := Vector3(direction.z,0,-direction.x)
		for step in range(4,int(distance)-2,7):
			_batch.box(from+direction*step+Vector3.UP*0.13,Vector3(0.13,0.018,2.7),YELLOW,angle)
		for side in [-1,1]:
			var middle: Vector3 = (from+toward)*0.5+offset*(width*0.5-0.35)*side
			_batch.box(middle+Vector3.UP*0.13,Vector3(0.10,0.018,distance),PAINT,angle)

func _path(points: Array, width: float) -> void:
	var path := _points(points,0.0)
	_ribbon(path,width+0.25,0.045,Color("a49d87"))
	_ribbon(path,width,0.065,WALK)
	for i in path.size()-1:
		var from := path[i]
		var toward := path[i+1]
		var direction := (toward-from).normalized()
		for step in range(2,int(from.distance_to(toward)),3):
			_batch.box(from+direction*step+Vector3.UP*0.075,Vector3(width,0.01,0.035),Color("a9a18d"),atan2(direction.x,direction.z))

func _ribbon(points: PackedVector3Array, width: float, height: float, color: Color) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var edges: Array[Vector3] = []
	for i in points.size():
		var before: Vector3 = (points[i]-points[maxi(i-1,0)]).normalized()
		var after: Vector3 = (points[mini(i+1,points.size()-1)]-points[i]).normalized()
		var tangent := (before+after).normalized()
		var side := Vector3(tangent.z,0,-tangent.x)
		var corrected := width*0.5/maxf(0.6,side.dot(Vector3(after.z,0,-after.x)) if i < points.size()-1 else 1.0)
		edges.append(side*corrected)
	for i in points.size()-1:
		var a := points[i]+edges[i]+Vector3.UP*height
		var b := points[i]-edges[i]+Vector3.UP*height
		var c := points[i+1]+edges[i+1]+Vector3.UP*height
		var d := points[i+1]-edges[i+1]+Vector3.UP*height
		vertices.append_array(PackedVector3Array([a,c,b,b,c,d]))
		for _n in 6:
			normals.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material: StandardMaterial3D = _batch.material(color)
	material.cull_mode = BaseMaterial3D.CULL_BACK
	mesh.surface_set_material(0,material)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	exterior.add_child(instance)

func _create_commercial() -> void:
	# The aerial's broad low-rise retail/parking blocks stay in the northwest.
	_parking(Vector3(-90.5,0,-54),Vector2(31,22),0.0,4)
	_building("Commercial_City/building-e",Vector3(-90,0,-27),Vector3(26,9.4,14),PI,"COLLEGE SQUARE / MARKET",SHOP)
	_building("Commercial_City/building-k",Vector3(-62,0,-56),Vector3(20,12.5,12),0.0,"SQUARE WEST",SHOP)
	_building("Industrial_City/building-a",Vector3(-33,0,-60),Vector3(22,11,18),0.0,"HARDWARE & HOME",Color("dc9866"))
	_building("Commercial_City/building-c",Vector3(-64,0,-6),Vector3(16,8.5,13),PI,"NIGHT OWL",SHOP)
	_building("Commercial_City/building-b",Vector3(-111,0,-15),Vector3(10,11,12),0.0,"MOTORS",SHOP)
	_building("Commercial_City/building-a",Vector3(-112,0,-40),Vector3(8.0,10.5,11),0.0,"NORTHSIDE",SHOP)
	_building("Industrial_City/building-g",Vector3(-87,0,86),Vector3(13,7,13),0.0,"MAINTENANCE",Color("959d98"))
	_asset("Industrial_City/shipping-container-a",Vector3(-98.5,0,75),Vector3(3.0,3.0,6.3))
	_asset("Roads/dumpster",Vector3(-80,0,77),Vector3(2.4,1.8,1.4))
	_asset("Blasters/crate-medium",Vector3(-97,0,80),Vector3(1.3,1.1,1.0))
	_path([Vector2(-96,70),Vector2(-84,53)],2.4)
	# Outdoor café terrace and familiar social meeting corner.
	_batch.box(Vector3(-56,0.035,-18),Vector3(17,0.07,9),Color("a49c88"))
	for x in [-62,-56,-50]:
		_asset("Furniture/tableRound",Vector3(x,0.10,-20),Vector3(1.7,0.9,1.7))
		_asset("Commercial_City/detail-parasol-a",Vector3(x,0.10,-20),Vector3(3.3,3.5,3.3))
		_asset("Furniture/chair",Vector3(x-1.2,0.10,-20),Vector3(0.7,1.15,0.7),PI/2)
		_asset("Furniture/chair",Vector3(x+1.2,0.10,-20),Vector3(0.7,1.15,0.7),-PI/2)
	for pos in [Vector3(-103,0,-55),Vector3(-87,0,-55),Vector3(-71,0,-55)]:
		_asset("Market/shopping-cart",pos,Vector3(0.7,1.1,1.0))
	_parking(Vector3(-114,0,3),Vector2(10,12),PI/2,1)
	# A transit shelter borrows the same architectural palette as campus.
	_batch.box(Vector3(-30,1.75,-88),Vector3(10,0.18,3),INK)
	for x in [-34,-26]:
		_batch.box(Vector3(x,0.9,-88),Vector3(0.14,1.8,0.14),INK)
	_asset("Furniture/bench",Vector3(-30,0.10,-88),Vector3(4,1.0,0.8))
	_sign("BASELINE / 88",Vector3(-36,0,-86),CAMPUS)

func _create_campus() -> void:
	# Low connected teaching blocks echo the aerial's large south/east campus.
	_building("Commercial_City/building-j",Vector3(19,0,27),Vector3(26,12.2,17),0,"NORTH HALL",CAMPUS)
	_building("Commercial_City/building-k",Vector3(-20,0,77),Vector3(26,11.3,17),PI,"LEARNING COMMONS",CAMPUS)
	_building("Industrial_City/building-b",Vector3(-38,0,31),Vector3(25,11,16),0,"DESIGN + TECHNOLOGY",CAMPUS)
	_building("Commercial_City/building-j",Vector3(12,0,86),Vector3(24,11,13),PI,"STUDENT SERVICES",CAMPUS)
	_building("Commercial_City/building-e",Vector3(79,0,41),Vector3(26,9.5,15),0,"RESIDENCE / EAST",CAMPUS)
	_building("Commercial_City/building-i",Vector3(106,0,44),Vector3(17,13,16),PI,"ATHLETICS",CAMPUS)
	_building("Industrial_City/building-c",Vector3(112,0,-1),Vector3(24,8.5,16),0,"FIELD HOUSE",CAMPUS)
	_building("Commercial_City/building-j",Vector3(-69,0,88),Vector3(20,10,15),PI,"INNOVATION LAB",CAMPUS)
	# Quad paths surround planted islands; direct routes remain walkable.
	_batch.box(Vector3(17,0.065,56),Vector3(39,0.10,20),WALK)
	_batch.box(Vector3(12,0.14,57),Vector3(15,0.18,9),Color("64785a"))
	_batch.box(Vector3(32,0.14,58),Vector3(7,0.18,9),Color("64785a"))
	_tree(Vector3(9,0,56),6.0,0)
	_tree(Vector3(16,0,58),5.6,1)
	_tree(Vector3(33,0,57),6.2,0)
	for p in [Vector3(2,0,51),Vector3(2,0,63),Vector3(25,0,63),Vector3(26,0,51)]:
		_asset("Furniture/bench",p,Vector3(3.1,1.15,0.85))
	_asset("Furniture/trashcan",Vector3(0,0,51),Vector3(0.65,1.0,0.65))
	# Campus sculpture is a local visual anchor, visible from several paths.
	_batch.cylinder(Vector3(9,0.3,64),1.6,0.6,Color("928a77"))
	_batch.box(Vector3(9,2.1,64),Vector3(0.6,3.0,0.6),Color("b78c53"),0.4)
	_batch.box(Vector3(9,3.0,64),Vector3(2.8,0.55,0.55),Color("b78c53"),-0.3)
	_parking(Vector3(-85,0,45),Vector2(37,26),0.0,4)
	_parking(Vector3(76,0,69),Vector2(23,14),0.0,3)
	for pos in [Vector3(-40,11,29),Vector3(16,11.1,86),Vector3(19,12.3,27)]:
		_asset("Industrial_City/solar-panel-landscape-group",pos,Vector3(7,1.2,4))
	_sign("NORTHBRIDGE COLLEGE",Vector3(-2,0,44),CAMPUS)
	_sign("WEST CAMPUS / P2",Vector3(-64,0,36),CAMPUS)
	# Playing field establishes a campus edge without covering it in buildings.
	_batch.box(Vector3(119,0.025,-22),Vector3(24,0.05,15),Color("657e5a"))
	for x in [108,130]:
		_batch.box(Vector3(x,0.08,-22),Vector3(0.12,0.025,13),PAINT)
	for z in [-28,-16]:
		_batch.box(Vector3(119,0.08,z),Vector3(22,0.025,0.12),PAINT)

func _create_residential() -> void:
	var houses := [
		[Vector3(62,0,-85),"b",PI], [Vector3(83,0,-88),"d",PI],
		[Vector3(106,0,-73),"f",-PI/2], [Vector3(108,0,-43),"h",-PI/2],
		[Vector3(86,0,-43),"e",0.0], [Vector3(72,0,-41),"c",0.0],
		[Vector3(66,0,-64),"a",PI/2], [Vector3(89,0,-68),"n",0.0],
		[Vector3(28,0,-69),"g",PI/2], [Vector3(27,0,-54),"i",PI/2],
		[Vector3(40,0,-20),"l",0.0], [Vector3(78,0,-9),"j",0.0]
	]
	for i in houses.size():
		var item: Array = houses[i]
		var size := Vector3(11.5,6.4,9.0)
		if i == 7:
			size = Vector3(15.5,8.1,11)
		elif i == 5:
			size = Vector3(9,6.0,7)
		_building("Suburban_City/building-type-"+item[1],item[0],size,item[2],"",HOME)
		var front := Vector3(sin(item[2]),0,cos(item[2]))
		var doorstep: Vector3 = item[0]+front*6.0
		_batch.box(doorstep+Vector3.UP*0.065,Vector3(2.3,0.10,5.0),WALK,item[2])
		_asset("Suburban_City/planter",doorstep+Vector3(2.5,0,0),Vector3(1.7,0.8,1.1),item[2])
	# Apartment front entrance reaches the central pedestrian spine directly.
	_path([Vector2(89,-59),Vector2(78,-59)],2.6)
	_sign("DEERFIELD / RESIDENCES",Vector3(52,0,-83),HOME)
	# Shared courtyard with picnic/social areas, hedges, and autumn street trees.
	for pos in [Vector3(81,0,-79),Vector3(77,0,-45),Vector3(98,0,-84),Vector3(38,0,-51),Vector3(110,0,-97)]:
		_tree(pos,_rng.randf_range(5.0,7.0),1)
	for pos in [Vector3(74,0,-69),Vector3(79,0,-70),Vector3(84,0,-53)]:
		_asset("Furniture/bench",pos,Vector3(2.6,1.0,0.8),PI/2)
	# Planted residential perimeter; all props stay outside the road clearance.
	for i in 14:
		var z := -102.0+i*5.4
		_tree(Vector3(134,0,z),_rng.randf_range(4.0,5.5),i%3)

func _create_park() -> void:
	_batch.box(Vector3(118,0.07,10),Vector3(22,0.14,15),Color("aaa99b"))
	_asset("Skateboard/half-pipe",Vector3(124,0.14,9),Vector3(7.5,2.2,6.0),PI/2)
	_asset("Skateboard/rail-low",Vector3(115,0.14,10),Vector3(0.2,0.7,5.0),0.25)
	_asset("Skateboard/obstacle-box",Vector3(110,0.14,10),Vector3(2.3,0.7,3.2))
	_asset("Furniture/bench",Vector3(113,0.13,17),Vector3(3,1.0,0.9))
	_sign("DEERFIELD / SKATE",Vector3(105,0,13),HOME)
	for pos in [Vector3(101,0,10),Vector3(136,0,15),Vector3(133,0,4)]:
		_tree(pos,5.0,1)
	# Retain the aerial's treed edge outside the principal built parcels.
	for i in 23:
		var x := -139.0+i*12.4
		var z := 121.0 if i%2 == 0 else 119.0
		if x > -65 and x < 95:
			_tree(Vector3(x,0,z),_rng.randf_range(4.8,7.0),i%3)
	for i in 20:
		_tree(Vector3(-149,0,-105+i*10.8),_rng.randf_range(5.5,8),i%3)

func _create_streetscape() -> void:
	night_material = StandardMaterial3D.new()
	night_material.albedo_color = Color("f2d9a4")
	night_material.emission_enabled = true
	night_material.emission = Color("ffd39c")
	# A bulb occupies only a few pixels. Share a small mesh instead of giving
	# every streetlamp the default 4,224-triangle sphere and a shadow pass.
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.18
	bulb_mesh.height = 0.16
	bulb_mesh.radial_segments = 8
	bulb_mesh.rings = 4
	for r in map_roads.size():
		var path: PackedVector3Array = map_roads[r]
		for i in path.size()-1:
			var delta := path[i+1]-path[i]
			var side := Vector3(delta.z,0,-delta.x).normalized()
			var spacing := 25.0
			var count := int(delta.length()/spacing)
			for j in count:
				var pos := path[i]+delta.normalized()*(j*spacing+11)+side*(road_widths[r]*0.5+1.6)
				if pos.x < 151 and pos.z > -122:
					_asset("Roads/light-curved",pos,Vector3(1.7,5.1,0.45),atan2(delta.x,delta.z)-PI/2)
					var glow := MeshInstance3D.new()
					glow.mesh = bulb_mesh
					glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					glow.material_override = night_material
					glow.position = pos+Vector3.UP*4.8
					exterior.add_child(glow)
				if r < 6 and j%2 == 0:
					_tree(pos+side*3.3,5.0+(r%3),r%3)
	for p in [Vector3(-130,0,-1),Vector3(-51,0,15),Vector3(34,0,14),Vector3(18,0,-83),Vector3(99,0,16)]:
		_asset("Roads/road-sign-stop",p,Vector3(0.75,2.7,0.15),0.5)
	for p in [Vector3(-127,0,-45),Vector3(-126,0,-26),Vector3(-47,0,-84),Vector3(21,0,-96)]:
		_asset("Roads/traffic-light",p,Vector3(0.6,3.7,0.65))
	for p in [Vector3(-100,0,-17),Vector3(-34,0,-43),Vector3(97,0,33)]:
		_asset("Roads/dumpster",p,Vector3(2.0,1.6,1.3))

func _create_routes() -> void:
	# Intentional sidewalk/plaza waypoints, not direct lines through buildings.
	pedestrian_routes.append(_points([Vector2(20,49),Vector2(1,48),Vector2(-12,48),Vector2(-18,64),Vector2(0,66),Vector2(25,67),Vector2(38,49)]))
	pedestrian_routes.append(_points([Vector2(-60,-17),Vector2(-79,-16),Vector2(-105.5,-16),Vector2(-105.5,-38),Vector2(-84,-37),Vector2(-54,-38),Vector2(-43,-28),Vector2(-50,-17)]))
	pedestrian_routes.append(_points([Vector2(77,-59),Vector2(77,-78),Vector2(91,-81),Vector2(98,-81),Vector2(98,-56),Vector2(108,-54),Vector2(94,-54),Vector2(80,-54)]))
	pedestrian_routes.append(_points([Vector2(76,55),Vector2(94,53),Vector2(95,48),Vector2(95,29),Vector2(106,19),Vector2(117,18),Vector2(98,20),Vector2(62,26),Vector2(62,51)]))
	pedestrian_routes.append(_points([Vector2(-63,38),Vector2(-56,46),Vector2(-48,48),Vector2(-14,48),Vector2(-13,60),Vector2(-36,65),Vector2(-50,58)]))
	traffic_routes.append(_lane_route([Vector2(-141,-49),Vector2(-97,-72),Vector2(-45,-95),Vector2(20,-116),Vector2(80,-119),Vector2(139,-112),Vector2(139,-56),Vector2(143,-3),Vector2(140,41),Vector2(97,78),Vector2(49,96),Vector2(-17,108),Vector2(-83,118),Vector2(-103,90),Vector2(-122,43),Vector2(-135,-8)],2.0))
	traffic_routes.append(_lane_route([Vector2(-141,-49),Vector2(-135,-8),Vector2(-109,12),Vector2(-83,23),Vector2(-59,18),Vector2(-43,1),Vector2(-33,-22),Vector2(-10,-39),Vector2(18,-43),Vector2(16,-49),Vector2(12,-78),Vector2(10,-113),Vector2(-45,-95),Vector2(-97,-72)],1.7))
	traffic_routes.append(_lane_route([Vector2(39,-94),Vector2(70,-104),Vector2(102,-98),Vector2(120,-79),Vector2(126,-51),Vector2(114,-28),Vector2(92,-21),Vector2(70,-27),Vector2(54,-49),Vector2(44,-74)],1.35))
	traffic_routes.append(_lane_route([Vector2(18,-43),Vector2(28,-13),Vector2(42,23),Vector2(57,53),Vector2(74,87),Vector2(49,96),Vector2(-17,108),Vector2(-35,111),Vector2(-48,72),Vector2(-64,48),Vector2(-83,23),Vector2(-59,18),Vector2(-43,1),Vector2(-33,-22),Vector2(-10,-39)],1.4))
	campus_police_routes.append(pedestrian_routes[0])
	campus_police_routes.append(pedestrian_routes[3])
	campus_police_routes.append(pedestrian_routes[4])
	city_police_routes.append(pedestrian_routes[1])
	city_police_routes.append(pedestrian_routes[2])

func _lane_route(points: Array, lane_offset: float) -> PackedVector3Array:
	var center := _points(points)
	var lane := PackedVector3Array()
	for i in center.size():
		var incoming := (center[i]-center[posmod(i-1,center.size())]).normalized()
		var outgoing := (center[(i+1)%center.size()]-center[i]).normalized()
		var tangent := (incoming+outgoing).normalized()
		var right := Vector3(-tangent.z,0,tangent.x)
		var correction := lane_offset/maxf(0.6,right.dot(Vector3(-outgoing.z,0,outgoing.x)))
		lane.append(center[i]+right*correction)
	return lane

func _building(key: String, pos: Vector3, size: Vector3, angle: float, title: String, accent: Color) -> void:
	var visual := _asset(key,pos,size,angle)
	var footprint := Vector2(size.x,size.z)
	if absf(sin(angle)) > 0.5:
		footprint = Vector2(size.z,size.x)
	var rect := Rect2(Vector2(pos.x,pos.z)-footprint*0.46,footprint*0.92)
	map_buildings.append(Rect2(Vector2(pos.x,pos.z)-footprint*0.5,footprint))
	obstacle_rects.append(rect)
	_register_occluder(visual,AABB(pos-Vector3(footprint.x*0.5,0,footprint.y*0.5),Vector3(footprint.x,size.y,footprint.y)))
	_collision(exterior,pos+Vector3.UP*size.y*0.5,Vector3(footprint.x*0.90,size.y,footprint.y*0.90))
	_batch.box(pos+Vector3.UP*0.045,Vector3(footprint.x+1.1,0.09,footprint.y+1.1),Color("9c9b8e"))
	if title != "":
		var front := Vector3(sin(angle),0,cos(angle))
		var sign_pos := pos+front*(size.z*0.5+0.12)+Vector3.UP*3.3
		_batch.box(sign_pos,Vector3(minf(size.x*0.76,15.0),1.15,0.12),INK,angle)
		var label := Label3D.new()
		label.text = title
		label.font_size = 42
		label.pixel_size = 0.016
		label.modulate = accent
		label.outline_size = 0
		label.position = sign_pos+front*0.09
		label.rotation.y = angle
		label.no_depth_test = false
		label.visibility_range_end = 90
		exterior.add_child(label)

func _asset(key: String, at: Vector3, dimensions: Vector3, angle: float = 0.0, parent: Node3D = null) -> Node3D:
	var node: Node3D = Art.make(key,dimensions)
	node.position = at
	node.rotation.y = angle
	(parent if parent != null else exterior).add_child(node)
	if key == "Commercial_City/detail-parasol-a" and parent == null:
		_register_occluder(node,AABB(at-Vector3(dimensions.x*0.5,0,dimensions.z*0.5),dimensions))
	if parent != null and at.y < 0.1 and dimensions.y > 0.6 and not key.ends_with("chair"):
		var footprint := Vector3(dimensions.x*0.78,minf(dimensions.y,1.8),dimensions.z*0.78)
		if absf(sin(angle)) > 0.5:
			footprint = Vector3(footprint.z,footprint.y,footprint.x)
		_collision(parent,at+Vector3.UP*footprint.y*0.5,footprint)
	return node

func _tree(at: Vector3, height: float, variant: int = 0) -> void:
	var keys := ["Nature/tree_oak","Nature/tree_default_fall","Nature/tree_pineRoundA"]
	var tree: Node3D = Art.make(keys[posmod(variant,keys.size())],Vector3.ZERO,height)
	tree.position = at
	tree.rotation.y = _rng.randf()*TAU
	exterior.add_child(tree)
	_register_occluder(tree,AABB(at-Vector3(height*0.42,0,height*0.42),Vector3(height*0.84,height,height*0.84)))
	# A small soil ring makes the lawn/tree transition deliberate.
	_batch.cylinder(at+Vector3.UP*0.035,height*0.11,0.07,Color("716a50"))

func _parking(center: Vector3, size: Vector2, angle: float, parked_count: int) -> void:
	_batch.box(center+Vector3.UP*0.025,Vector3(size.x+1.4,0.05,size.y+1.4),CURB,angle)
	_batch.box(center+Vector3.UP*0.04,Vector3(size.x,0.03,size.y),Color("454c4c"),angle)
	var rotate := Basis(Vector3.UP,angle)
	var stalls := int(size.x/3.3)-1
	for row in [-1,1]:
		for i in stalls+1:
			var local := Vector3(-size.x*0.5+2+i*3.3,0.075,row*(size.y*0.5-3.4))
			_batch.box(center+rotate*local,Vector3(0.10,0.02,5.4),PAINT,angle)
		for i in mini(parked_count,stalls):
			var local := Vector3(-size.x*0.5+3.5+i*6.6,0.13,row*(size.y*0.5-3.4))
			if local.x < size.x*0.5-2:
				var pos := center+rotate*local
				var model: String = ["sedan","hatchback-sports","suv","van"][posmod(i+row+1,4)]
				if i == 0 and row == -1 and center.x < -70 and absf(center.z) > 30:
					model = "police"
				parked_car_spawns.append({"position":pos,"rotation":angle+(PI if row == 1 else 0.0),"model":model})

func _crosswalk(at: Vector3, angle: float, width: float) -> void:
	var rotate := Basis(Vector3.UP,angle)
	for i in 7:
		_batch.box(at+rotate*Vector3(0,0.14,(i-3)*0.85),Vector3(width,0.025,0.4),PAINT,angle)

func _sign(text: String, at: Vector3, accent: Color) -> void:
	_batch.box(at+Vector3.UP*1.7,Vector3(0.12,3.4,0.12),INK)
	_batch.box(at+Vector3.UP*2.9,Vector3(4.5,1.0,0.14),INK)
	var label := Label3D.new()
	label.text = text
	label.font_size = 30
	label.pixel_size = 0.006
	label.modulate = accent
	label.outline_size = 0
	label.position = at+Vector3(0,2.9,0.09)
	label.visibility_range_end = 60
	exterior.add_child(label)

func _ground_text(text: String, at: Vector3, angle: float, scale_factor: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 32
	label.pixel_size = scale_factor*0.15
	label.modulate = Color("a9aea5")
	label.outline_size = 0
	label.position = at
	label.rotation = Vector3(-PI/2,angle,0)
	exterior.add_child(label)

func _create_markers() -> void:
	for id in landmarks:
		var record: Dictionary = landmarks[id]
		var pos: Vector3 = record.position
		var tint := CAMPUS if record.district == "Campus" else (HOME if record.district == "Deerfield" else SHOP)
		# A restrained paving medallion doubles as a visible interaction target.
		_batch.cylinder(pos+Vector3.UP*0.025,1.55,0.035,INK)
		_batch.cylinder(pos+Vector3.UP*0.05,1.35,0.035,tint)
		_batch.cylinder(pos+Vector3.UP*0.07,1.07,0.035,INK)
		var label := Label3D.new()
		label.name = "Landmark_"+id
		label.text = str(record.name).to_upper()
		label.font_size = 34
		label.pixel_size = 0.024
		label.position = pos+Vector3.UP*3.2
		label.modulate = tint
		label.outline_modulate = Color("15272a")
		label.outline_size = 8
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.visibility_range_end = 76.0
		label.visibility_range_end_margin = 6.0
		exterior.add_child(label)
		_labels.append(label)
		if id in ["campus_quad","classroom","library","cafe","market","home","supplier","skate_park","bus_stop"]:
			var lamp := OmniLight3D.new()
			lamp.position = pos+Vector3(0,4.8,0)
			lamp.omni_range = 12.0
			lamp.omni_attenuation = 0.65
			lamp.light_color = Color("ffdc9c")
			lamp.shadow_enabled = false
			exterior.add_child(lamp)
			exterior_lights.append(lamp)

func set_night(amount: float) -> void:
	if night_material != null:
		night_material.emission_energy_multiplier = 0.1+clampf(amount,0.0,1.0)*2.0
	for lamp in interior_lights:
		lamp.light_energy = 0.08+clampf(amount,0.0,1.0)*0.72
	for lamp in exterior_lights:
		lamp.light_energy = clampf(amount*1.4-0.5,0.0,1.0)*1.15

func _register_occluder(node: Node3D, bounds: AABB) -> void:
	_occluders.append({"node":node,"bounds":bounds,"faded":false,"parts":[]})

func update_camera_occlusion(camera_position: Vector3, player_position: Vector3) -> void:
	# GeometryInstance3D.transparency is Forward+ only. Material alpha works on
	# Compatibility; shadow-only originals retain their physical shadow shape.
	var target := player_position+Vector3.UP*0.85
	for record in _occluders:
		var bounds: AABB = record.bounds
		var blocked := false
		if current_interior == "" and bounds.get_center().distance_to(player_position) < 48.0:
			blocked = bounds.grow(0.25).intersects_segment(camera_position,target) != null
		if blocked != bool(record.faded):
			if blocked and record.parts.is_empty():
				_prepare_ghosts(record.node,record.parts)
			for part in record.parts:
				part.mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if blocked else part.shadow
				part.ghost.visible = blocked
			record.faded = blocked
	# Label visibility must use player distance, not high camera altitude.
	for label in _labels:
		label.visible = current_interior == "" and label.global_position.distance_to(player_position) < 24.0

func _prepare_ghosts(node: Node, parts: Array) -> void:
	var original_children := node.get_children()
	if node is MeshInstance3D and node.mesh != null:
		var ghost := MeshInstance3D.new()
		ghost.name = "CameraCutaway"
		ghost.mesh = node.mesh
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in node.mesh.get_surface_count():
			var original: Material = node.get_active_material(surface)
			if original is StandardMaterial3D:
				var key := original.get_instance_id()
				if not _fade_materials.has(key):
					var faded: StandardMaterial3D = original.duplicate()
					faded.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					faded.albedo_color.a = 0.17
					faded.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
					_fade_materials[key] = faded
				ghost.set_surface_override_material(surface,_fade_materials[key])
		ghost.visible = false
		node.add_child(ghost)
		parts.append({"mesh":node,"ghost":ghost,"shadow":node.cast_shadow})
	for child in original_children:
		_prepare_ghosts(child,parts)

func _points(points: Array, height: float = 0.16) -> PackedVector3Array:
	var result := PackedVector3Array()
	for point in points:
		result.append(Vector3(point.x,height,point.y))
	return result

func _collision(parent: Node3D, position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.position = position
	body.add_child(collider)
	parent.add_child(body)
	return body

func _create_interiors() -> void:
	# Each room is an open-top dollhouse, with furniture from the original packs.
	# Independent offsets ensure collision is harmless while a room is hidden.
	var ids := ["home","market","cafe","classroom","library"]
	for i in ids.size():
		var room := Node3D.new()
		room.name = "Interior_"+ids[i]
		room.position = Vector3(600+i*80,0,0)
		interior_root.add_child(room)
		interior_nodes[ids[i]] = room
		_furnish_room(room,ids[i])
		room.visible = false

func _room_box(room: Node3D, at: Vector3, dimensions: Vector3, color: Color, solid: bool = false) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _batch.material(color)
	instance.position = at
	room.add_child(instance)
	if solid:
		_collision(room,at,dimensions)

func _furnish_room(room: Node3D, id: String) -> void:
	var width := 20.0
	var depth := 16.0
	# A matte backdrop keeps the dollhouse legible against the outdoor sky.
	_room_box(room,Vector3(0,-0.75,0),Vector3(100,0.18,90),Color("26383a"))
	_room_box(room,Vector3(0,-0.4,0),Vector3(width+0.4,0.3,depth+0.4),Color("514a3b"))
	_room_box(room,Vector3(0,-0.18,0),Vector3(width,0.35,depth),Color("b4a58b"),true)
	_room_box(room,Vector3(0,1.45,-depth/2),Vector3(width,2.9,0.25),Color("d8ceb9"),true)
	_room_box(room,Vector3(-width/2,1.2,0),Vector3(0.25,2.4,depth),Color("bdb7a5"),true)
	_room_box(room,Vector3(width/2,1.2,0),Vector3(0.25,2.4,depth),Color("bdb7a5"),true)
	_room_box(room,Vector3(0,0.3,depth/2),Vector3(width,0.6,0.25),Color("bdb7a5"),true)
	# Painted threshold is the persistent, discoverable way back outside.
	_room_box(room,Vector3(0,0.02,5.8),Vector3(3,0.025,2.1),CAMPUS)
	var exit_label := Label3D.new()
	exit_label.text = "EXIT / E"
	exit_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	exit_label.position = Vector3(0,1.6,6.4)
	exit_label.font_size = 40
	exit_label.pixel_size = 0.022
	room.add_child(exit_label)
	var title := Label3D.new()
	title.text = str(landmarks[id].name).to_upper()
	title.font_size = 46
	title.pixel_size = 0.018
	title.position = Vector3(0,2.3,-7.8)
	title.modulate = INK
	title.outline_size = 0
	room.add_child(title)
	match id:
		"home":
			_room_box(room,Vector3(-6.5,1.8,-7.8),Vector3(3.8,1.8,0.12),Color("688b93"))
			_room_box(room,Vector3(-6.5,1.8,-7.7),Vector3(0.12,1.8,0.13),Color("e0d8c4"))
			_room_box(room,Vector3(-6.5,1.8,-7.7),Vector3(3.8,0.12,0.13),Color("e0d8c4"))
			_room_box(room,Vector3(3.8,1.8,-7.8),Vector3(1.6,1.8,0.12),Color("344d49"))
			_room_box(room,Vector3(3.8,1.8,-7.7),Vector3(1.3,1.5,0.13),Color("b68c53"))
			_asset("Furniture/bedSingle",Vector3(-6.8,0,-4.5),Vector3(2.8,1.1,4.3),0,room)
			_asset("Furniture/cabinetBed",Vector3(-4.6,0,-6),Vector3(1.2,1.0,1.0),0,room)
			_asset("Furniture/desk",Vector3(5.7,0,-6),Vector3(4.5,1.6,2.0),0,room)
			_asset("Furniture/laptop",Vector3(5.7,1.6,-6),Vector3(1.0,0.6,0.8),0,room)
			_asset("Furniture/chairDesk",Vector3(5.5,0,-4),Vector3(1,1.8,1),PI,room)
			_asset("Furniture/loungeSofa",Vector3(-5,0,1),Vector3(4.3,1.7,2.0),PI/2,room)
			_asset("Furniture/tableCoffee",Vector3(-1.8,0,1),Vector3(2,0.8,2.0),0,room)
			_asset("Furniture/rugRectangle",Vector3(-2,0.04,1),Vector3(5,0.03,4.5),0,room)
			_asset("Furniture/kitchenFridge",Vector3(8,0,0),Vector3(1.6,2.6,1.5),-PI/2,room)
			_asset("Furniture/kitchenSink",Vector3(8,0,2),Vector3(1.6,1.4,1.5),-PI/2,room)
			_asset("Furniture/bookcaseOpen",Vector3(-1,0,-7),Vector3(3,2.6,0.8),0,room)
			_asset("Furniture/books",Vector3(-2.0,0.83,1),Vector3(0.8,0.32,0.6),0.3,room)
			_asset("Furniture/plantSmall1",Vector3(-4.6,1.01,-6),Vector3(0.45,0.6,0.45),0,room)
			_asset("Furniture/speaker",Vector3(-6,0,5),Vector3(0.8,1.3,0.8),0,room)
			_asset("Skateboard/skateboard",Vector3(3.5,0,5),Vector3(0.5,0.22,1.2),0.5,room)
		"market":
			_room_box(room,Vector3(0,0.02,0),Vector3(19.5,0.025,15.5),Color("d0cec0"))
			for x in [-5.0,0.0,5.0]:
				for z in [-3.6,0.0]:
					_asset("Market/shelf-bags" if x < 0 else "Market/shelf-boxes",Vector3(x,0,z),Vector3(2.4,2.0,1.0),0,room)
			for x in [-6.0,-2.0,2.0]:
				_asset("Market/freezers-standing",Vector3(x,0,-6.9),Vector3(3.3,2.5,1),0,room)
			_asset("Market/display-fruit",Vector3(7.5,0,-3),Vector3(2.6,1.3,2.3),0,room)
			_asset("Market/display-bread",Vector3(7.5,0,1),Vector3(2.6,1.4,2.0),0,room)
			_asset("Market/cash-register",Vector3(-6.5,0,5.3),Vector3(3.0,1.5,2),PI,room)
			_asset("Market/character-employee",Vector3(-6.7,0,6.7),Vector3.ZERO,PI,room).scale = Vector3.ONE*2.3
		"cafe":
			for x in [-5.7,0.0,5.7]:
				for z in [-1.0,3.0]:
					_asset("Furniture/tableRound",Vector3(x,0,z),Vector3(2,1.2,2),0,room)
					_asset("Furniture/chair",Vector3(x-1.5,0,z),Vector3(0.9,1.5,0.9),PI/2,room)
					_asset("Furniture/chair",Vector3(x+1.5,0,z),Vector3(0.9,1.5,0.9),-PI/2,room)
			for x in [-5,-2,1,4]:
				_asset("Furniture/kitchenCabinet",Vector3(x,0,-6),Vector3(2.9,1.5,1.5),0,room)
			_asset("Furniture/kitchenCoffeeMachine",Vector3(-3,1.5,-6),Vector3(1.0,1,0.8),0,room)
			_asset("Market/display-bread",Vector3(7,0,-5),Vector3(2,1.4,2),0,room)
		"classroom":
			_room_box(room,Vector3(0,1.7,-7.7),Vector3(8,1.5,0.1),Color("304b43"))
			for x in [-5.0,0.0,5.0]:
				for z in [-3.0,0.5,3.9]:
					if x == 0.0 and z > 3.0:
						continue
					_asset("Furniture/desk",Vector3(x,0,z),Vector3(2.8,1.2,1.6),0,room)
					_asset("Furniture/chair",Vector3(x,0,z+1.3),Vector3(0.9,1.4,0.9),PI,room)
			_asset("Furniture/desk",Vector3(-5,0,-6),Vector3(4.0,1.4,1.6),0,room)
			_asset("Furniture/computerScreen",Vector3(-5,1.4,-6),Vector3(1.1,0.85,0.5),0,room)
		"library":
			for x in [-7.0,-3.5,3.5,7.0]:
				_asset("Furniture/bookcaseOpen",Vector3(x,0,-6.8),Vector3(3.0,2.8,0.8),0,room)
			for x in [-6,6]:
				_asset("Furniture/table",Vector3(x,0,0),Vector3(3,1.3,5.5),0,room)
				for z in [-1.5,1.5]:
					_asset("Furniture/laptop",Vector3(x,1.3,z),Vector3(0.9,0.5,0.8),0,room)
					_asset("Furniture/chair",Vector3(x+2,0,z),Vector3(0.8,1.4,0.8),-PI/2,room)
			_asset("Furniture/desk",Vector3(0,0,-4),Vector3(3.5,1.5,1.5),0,room)
			_asset("Furniture/computerScreen",Vector3(0,1.5,-4),Vector3(1.2,0.9,0.6),0,room)
	_asset("Furniture/pottedPlant",Vector3(-8.7,0,6),Vector3(1.2,2.0,1.2),0,room)
	_asset("Furniture/lampRoundFloor",Vector3(8.5,0,-6.8),Vector3(0.8,2.5,0.8),0,room)
	var room_light := OmniLight3D.new()
	room_light.position = Vector3(0,5,0)
	room_light.omni_range = 18.0
	room_light.omni_attenuation = 0.7
	room_light.light_color = Color("ffe1b0")
	room_light.shadow_enabled = false
	room.add_child(room_light)
	interior_lights.append(room_light)

func enter_interior(id: String) -> Vector3:
	if not interior_nodes.has(id):
		return get_landmark(id)
	if current_interior != "":
		interior_nodes[current_interior].visible = false
	current_interior = id
	exterior.visible = false
	interior_nodes[id].visible = true
	return interior_nodes[id].global_position+Vector3(0,0.2,4.5)

func exit_interior() -> Vector3:
	var id := current_interior
	if interior_nodes.has(id):
		interior_nodes[id].visible = false
	current_interior = ""
	exterior.visible = true
	return get_landmark(id)+Vector3(0,0.1,2.0)

func get_interior_exit() -> Vector3:
	if current_interior == "":
		return Vector3.INF
	return interior_nodes[current_interior].global_position+Vector3(0,0.2,5.8)
