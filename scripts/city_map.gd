class_name CityMap
extends Control

signal landmark_selected(id: String)
var city: Node3D
var student: Node3D
var population: Node3D
var large := false
var destination := ""
var redraw_elapsed := 0.0
var map_background: StyleBoxFlat

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(250,200)
	tooltip_text = "Click a location to set your destination. M opens the city map."
	map_background = StyleBoxFlat.new()
	map_background.bg_color = Color("304339")
	map_background.set_corner_radius_all(5)

func project(pos: Vector3) -> Vector2:
	return Vector2((pos.x+150)/300.0*size.x,(pos.z+120)/240.0*size.y)

func _process(delta: float) -> void:
	redraw_elapsed += delta
	if is_visible_in_tree() and redraw_elapsed >= 0.1:
		redraw_elapsed = 0.0
		queue_redraw()

func _draw() -> void:
	draw_style_box(map_background,Rect2(Vector2.ZERO,size))
	if not city:
		return
	draw_rect(Rect2(Vector2(size.x*0.55,0),Vector2(size.x*0.45,size.y*0.45)),Color("384b40"))
	draw_rect(Rect2(Vector2(0,size.y*0.1),Vector2(size.x*0.46,size.y*0.54)),Color("4b4b44"))
	draw_rect(Rect2(Vector2(size.x*0.42,size.y*0.47),Vector2(size.x*0.58,size.y*0.53)),Color("435349"))
	var buildings: Array = city.map_buildings
	for rect in buildings:
		var a := project(Vector3(rect.position.x,0,rect.position.y))
		var b := project(Vector3(rect.end.x,0,rect.end.y))
		draw_rect(Rect2(a,b-a),Color("73796b"))
	for road in city.map_roads:
		var points := PackedVector2Array()
		for point in road:
			points.append(project(point))
		if points.size()>1:
			draw_polyline(points,Color("b4b09c"),6 if large else 3,true)
	for id in city.landmarks:
		var data: Dictionary = city.landmarks[id]
		var pos := project(data.position)
		var color := Color("d8d7c4")
		if id==destination:
			color=Color("d5f276")
			draw_arc(pos,9,0,TAU,24,color,2,true)
		draw_circle(pos,4 if large else 2.5,color)
		if large:
			var text_size:Vector2=ThemeDB.fallback_font.get_string_size(str(data.name),HORIZONTAL_ALIGNMENT_LEFT,-1,13)
			var label_pos:=pos+Vector2(8,4)
			label_pos.x=clampf(label_pos.x,6,size.x-text_size.x-6)
			label_pos.y=clampf(label_pos.y,18,size.y-8)
			draw_string(ThemeDB.fallback_font,label_pos,str(data.name),HORIZONTAL_ALIGNMENT_LEFT,-1,13,color)
	if population and population.pursuit:
		for officer in population.police:
			draw_circle(project(officer.node.position),3,Color("ff8870"))
	if student and student.position.x<400:
		var p := project(student.position)
		if destination!="" and city.landmarks.has(destination):
			draw_dashed_line(p,project(city.landmarks[destination].position),Color("d5f276"),1.5,5,true)
		draw_circle(p,7,Color("132b2a"))
		draw_circle(p,4,Color("d5f276"))
	draw_string(ThemeDB.fallback_font,Vector2(size.x-24,22),"N",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("f1eddd"))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and city:
		var nearest := ""
		var distance := 35.0
		for id in city.landmarks:
			var d: float = project(city.landmarks[id].position).distance_to(event.position)
			if d<distance:
				distance=d
				nearest=id
		if nearest!="":
			destination=nearest
			queue_redraw()
			landmark_selected.emit(nearest)
