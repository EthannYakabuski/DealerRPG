extends CanvasLayer

const CREAM := Color("f1eedf")
const MUTED := Color("a6b3a8")
const INK := Color("16221f")
const PANEL := Color("20302a")
const LIME := Color("d5f276")
const AMBER := Color("efbf77")
const RED := Color("f28f7e")
const Data = preload("res://scripts/game_data.gd")

var game_root: Node3D
var root: Control
var hud: Control
var modal: Control
var title_screen: Control
var body: VBoxContainer
var page := ""
var selected_message: Dictionary = {}
var labels: Dictionary = {}
var bars: Dictionary = {}
var minimap: CityMap
var toast: Label
var toast_panel: PanelContainer
var toast_timer := 0.0
var refresh_pending := false
var refresh_elapsed := 0.0
var sfx: AudioStreamPlayer
var sounds: Dictionary = {}
var tips := ["WASD move  ·  SHIFT run  ·  SPACE skateboard", "TAB phone  ·  B backpack  ·  M city map", "E interact  ·  V enter / exit vehicle", "J punch  ·  K kick  ·  L shoot  ·  ESC pause"]

func _ready() -> void:
	layer=5
	root=Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.theme=_theme()
	sfx=AudioStreamPlayer.new()
	sfx.volume_db=-15
	add_child(sfx)
	for sound in ["click-a","tap-b","switch-a"]:
		sounds[sound]=load("res://art/audio/%s.ogg"%sound)
	_build_hud()
	_build_title()
	Game.changed.connect(func(): refresh_pending=true)
	Game.notification.connect(show_toast)
	_update_hud()

func _theme() -> Theme:
	var theme:=Theme.new()
	theme.default_font_size=16
	theme.set_color("font_color","Label",CREAM)
	theme.set_color("font_color","Button",CREAM)
	theme.set_color("font_hover_color","Button",LIME)
	theme.set_color("font_pressed_color","Button",INK)
	theme.set_stylebox("normal","Button",_style(Color("304238"),7,12))
	theme.set_stylebox("hover","Button",_style(Color("3c5143"),7,12))
	theme.set_stylebox("pressed","Button",_style(LIME,7,12))
	theme.set_stylebox("focus","Button",_outline(LIME))
	theme.set_stylebox("disabled","Button",_style(Color("29322e"),7,12))
	theme.set_color("font_disabled_color","Button",Color("76847b"))
	theme.set_stylebox("panel","PopupMenu",_style(PANEL,7,10))
	theme.set_color("font_color","PopupMenu",CREAM)
	theme.set_stylebox("normal","OptionButton",_style(Color("304238"),7,12))
	theme.set_stylebox("hover","OptionButton",_style(Color("3c5143"),7,12))
	theme.set_stylebox("normal","LineEdit",_style(Color("304238"),7,10))
	theme.set_color("font_color","LineEdit",CREAM)
	theme.set_constant("separation","VBoxContainer",12)
	theme.set_constant("separation","HBoxContainer",12)
	return theme

func _style(color:Color,radius:int=8,padding:int=16) -> StyleBoxFlat:
	var s:=StyleBoxFlat.new()
	s.bg_color=color
	s.set_corner_radius_all(radius)
	s.content_margin_left=padding
	s.content_margin_right=padding
	s.content_margin_top=padding
	s.content_margin_bottom=padding
	return s

func _outline(color:Color) -> StyleBoxFlat:
	var s:=_style(Color(0,0,0,0),7,0)
	s.set_border_width_all(2)
	s.border_color=color
	return s

func _label(text:String,size:int=16,color:Color=CREAM) -> Label:
	var l:=Label.new()
	l.text=text
	l.add_theme_font_size_override("font_size",size)
	l.add_theme_color_override("font_color",color)
	l.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return l

func _paragraph(text:String,parent:Node=body,color:Color=MUTED) -> Label:
	var l:=_label(text,16,color)
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l

func _button(text:String,callback:Callable,parent:Node=body,primary:bool=false) -> Button:
	var b:=Button.new()
	b.text=text
	b.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	b.focus_mode=Control.FOCUS_NONE
	b.custom_minimum_size.y=42
	b.pressed.connect(func():_play_sound("click-a");callback.call())
	if primary:
		b.add_theme_stylebox_override("normal",_style(LIME,7,12))
		b.add_theme_color_override("font_color",INK)
		b.add_theme_color_override("font_hover_color",INK)
		b.add_theme_stylebox_override("hover",_style(Color("e5ffa1"),7,12))
	parent.add_child(b)
	return b

func _card(parent:Node=body,color:Color=PANEL) -> VBoxContainer:
	var panel:=PanelContainer.new()
	panel.add_theme_stylebox_override("panel",_style(color,9,18))
	parent.add_child(panel)
	var box:=VBoxContainer.new()
	panel.add_child(box)
	return box

func _row(parent:Node=body) -> HBoxContainer:
	var row:=HBoxContainer.new()
	parent.add_child(row)
	return row

func _space(parent:Node,height:float) -> void:
	var spacer:=Control.new()
	spacer.custom_minimum_size.y=height
	parent.add_child(spacer)

func _build_hud() -> void:
	hud=Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	var brand:=PanelContainer.new()
	brand.position=Vector2(24,22)
	brand.size=Vector2(272,88)
	brand.add_theme_stylebox_override("panel",_style(Color(0.07,0.12,0.10,0.93),9,16))
	hud.add_child(brand)
	var brand_box:=VBoxContainer.new()
	brand_box.add_theme_constant_override("separation",3)
	brand.add_child(brand_box)
	brand_box.add_child(_label("NIGHT SCHOOL",26,LIME))
	labels.district=_label("DEERFIELD / CAMPUS",12,MUTED)
	brand_box.add_child(labels.district)
	var clock_panel:=PanelContainer.new()
	clock_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	clock_panel.position=Vector2(-125,22)
	clock_panel.size=Vector2(250,65)
	clock_panel.add_theme_stylebox_override("panel",_style(Color(0.07,0.12,0.10,0.93),9,12))
	hud.add_child(clock_panel)
	labels.clock=_label("DAY 01   10:00",20)
	labels.clock.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	clock_panel.add_child(labels.clock)
	var finances:=PanelContainer.new()
	finances.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	finances.position=Vector2(-300,22)
	finances.size=Vector2(276,95)
	finances.add_theme_stylebox_override("panel",_style(Color(0.07,0.12,0.10,0.93),9,15))
	hud.add_child(finances)
	var fv:=VBoxContainer.new()
	finances.add_child(fv)
	labels.money=_label("$22   /   CASH",24,CREAM)
	fv.add_child(labels.money)
	labels.debt=_label("TUITION LEFT    $3,500",13,AMBER)
	fv.add_child(labels.debt)
	var stats_frame:=PanelContainer.new()
	stats_frame.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stats_frame.position=Vector2(-300,126)
	stats_frame.size=Vector2(276,94)
	stats_frame.add_theme_stylebox_override("panel",_style(Color(0.07,0.12,0.10,0.88),8,14))
	hud.add_child(stats_frame)
	var stats:=VBoxContainer.new()
	stats_frame.add_child(stats)
	for stat in ["health","hunger","heat"]:
		var row:=HBoxContainer.new()
		stats.add_child(row)
		var lab:=_label(stat.to_upper(),11,CREAM)
		lab.custom_minimum_size.x=65
		row.add_child(lab)
		var bar:=ProgressBar.new()
		bar.show_percentage=false
		bar.custom_minimum_size=Vector2(172,8)
		bar.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("background",_style(Color(0.05,0.1,0.08,0.65),3,0))
		bar.add_theme_stylebox_override("fill",_style(RED if stat=="heat" else (LIME if stat=="health" else AMBER),3,0))
		row.add_child(bar)
		bars[stat]=bar
	var objective:=PanelContainer.new()
	objective.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	objective.position=Vector2(24,-238)
	objective.size=Vector2(370,138)
	objective.add_theme_stylebox_override("panel",_style(Color(0.07,0.12,0.10,0.93),9,18))
	hud.add_child(objective)
	var ov:=VBoxContainer.new()
	objective.add_child(ov)
	labels.chapter=_label("01  /  AFTER CLASS",12,LIME)
	ov.add_child(labels.chapter)
	labels.objective=_paragraph("",ov,CREAM)
	labels.objective.custom_minimum_size.x=330
	labels.route=_label("",12,AMBER)
	ov.add_child(labels.route)
	var map_frame:=PanelContainer.new()
	map_frame.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	map_frame.position=Vector2(-290,-308)
	map_frame.size=Vector2(266,216)
	map_frame.add_theme_stylebox_override("panel",_style(Color(0.07,0.12,0.10,0.95),8,7))
	hud.add_child(map_frame)
	minimap=CityMap.new()
	minimap.city=game_root.world
	minimap.student=game_root.player
	minimap.population=game_root.population
	minimap.landmark_selected.connect(game_root.navigate)
	map_frame.add_child(minimap)
	labels.interact=_label("",17,CREAM)
	labels.interact.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	labels.interact.position=Vector2(-330,-125)
	labels.interact.size=Vector2(660,32)
	labels.interact.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	labels.interact.add_theme_color_override("font_shadow_color",Color.BLACK)
	labels.interact.add_theme_constant_override("shadow_offset_x",1)
	labels.interact.add_theme_constant_override("shadow_offset_y",2)
	hud.add_child(labels.interact)
	var bottom:=PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left=24
	bottom.offset_right=-24
	bottom.offset_top=-74
	bottom.offset_bottom=-20
	bottom.add_theme_stylebox_override("panel",_style(Color(0.07,0.12,0.10,0.94),8,6))
	hud.add_child(bottom)
	var actions:=HBoxContainer.new()
	bottom.add_child(actions)
	for entry in [["TAB  Phone","messages"],["B  Backpack","backpack"],["M  Map","map"],["?  Controls","help"]]:
		var id:String=entry[1]
		_button(entry[0],func():toggle_page(id),actions)
	var filler:=Control.new()
	filler.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	actions.add_child(filler)
	labels.mode=_label("ON FOOT   ·   SPACE to skate",13,MUTED)
	actions.add_child(labels.mode)
	_space(actions,0)
	toast_panel=PanelContainer.new()
	toast_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_panel.position=Vector2(-320,115)
	toast_panel.size=Vector2(640,62)
	toast_panel.add_theme_stylebox_override("panel",_style(Color(0.11,0.17,0.13,0.97),8,15))
	toast_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_panel)
	toast=_label("",16,CREAM)
	toast.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	toast.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	toast.custom_minimum_size.x=600
	toast_panel.add_child(toast)
	toast_panel.visible=false
	hud.visible=false

func _build_title() -> void:
	title_screen=Control.new()
	title_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(title_screen)
	var shade:=ColorRect.new()
	shade.color=Color(0.025,0.065,0.045,0.73)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_screen.add_child(shade)
	var margin:=MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",90)
	margin.add_theme_constant_override("margin_top",95)
	margin.add_theme_constant_override("margin_right",90)
	margin.add_theme_constant_override("margin_bottom",60)
	title_screen.add_child(margin)
	var box:=VBoxContainer.new()
	margin.add_child(box)
	box.add_child(_label("A DEERFIELD STORY",15,LIME))
	_space(box,20)
	var title:=_label("NIGHT\nSCHOOL",86,CREAM)
	title.add_theme_constant_override("line_spacing",-16)
	box.add_child(title)
	_space(box,12)
	box.add_child(_label("Tuition is due. The city is open.",24,AMBER))
	var copy:=_paragraph("One student. A backpack. A phone full of possibilities.\nBuild your connections, keep up appearances, and buy back your future.",box,CREAM)
	copy.custom_minimum_size.x=640
	_space(box,20)
	var buttons:=HBoxContainer.new()
	box.add_child(buttons)
	var start:=_button("START A NEW STORY    >",func():game_root.start_game(false),buttons,true)
	start.custom_minimum_size.x=260
	if FileAccess.file_exists(Game.save_path) and Game.status=="playing":
		_button("CONTINUE",func():game_root.start_game(true),buttons)
	_space(box,6)
	box.add_child(_label("HARDCORE   •   Arrest or three missed classes ends your story.",13,MUTED))
	var fill:=Control.new()
	fill.size_flags_vertical=Control.SIZE_EXPAND_FILL
	box.add_child(fill)
	box.add_child(_label("WASD move   /   E interact   /   TAB phone   /   SPACE skateboard",14,MUTED))
	box.add_child(_label("A fictional city inspired by Ottawa. All characters are adults.",11,MUTED))

func start_play() -> void:
	title_screen.visible=false
	hud.visible=true
	close_page()
	_update_hud()

func _process(delta:float) -> void:
	toast_timer=maxf(0,toast_timer-delta)
	toast_panel.visible=toast_timer>0
	refresh_elapsed+=delta
	if refresh_elapsed>0.15:
		refresh_elapsed=0
		_update_hud()
	if refresh_pending:
		refresh_pending=false
		if page!="" and page!="schedule" and page!="ending":
			_build_page()

func _update_hud() -> void:
	if not game_root.player:
		return
	labels.district.text=game_root.district_name()
	labels.clock.text="DAY %02d   %s  /  %s"%[Game.day_number(),Game.time_text(),Game.current_phase().to_upper()]
	labels.money.text="$%s   /   CASH"%_money(Game.cash)
	labels.debt.text="TUITION LEFT    $%s"%_money(Game.tuition_remaining)
	bars.health.value=Game.health
	bars.hunger.value=Game.hunger
	bars.heat.value=Game.heat
	labels.chapter.text="01  /  AFTER CLASS" if Game.tutorial_step<3 else ("PURSUIT  /  BREAK LINE OF SIGHT" if game_root.population.pursuit else "YOUR STORY  /  REP %d"%Game.reputation)
	labels.chapter.add_theme_color_override("font_color",RED if game_root.population.pursuit else LIME)
	labels.objective.text=Game.current_objective()
	labels.interact.text=game_root.interaction_text() if page=="" else ""
	labels.mode.text=game_root.player.travel_mode()+"   ·   SPACE to skate"
	minimap.destination=game_root.destination
	if game_root.destination!="" and game_root.world.landmarks.has(game_root.destination):
		var data:Dictionary=game_root.world.landmarks[game_root.destination]
		labels.route.text="> %s   ·   %dm"%[data.name,int(game_root.player.position.distance_to(data.position))]
	else:
		labels.route.text=""
	if game_root.population.pursuit:
		labels.objective.text="Patrols are pursuing you. Get out of sight for 10 seconds.\nEscape: %ds / 10"%int(game_root.population.escape_seconds)

func _money(value:float) -> String:
	var number:=str(int(ceil(value)))
	var result:=""
	for i in range(number.length()):
		if i>0 and (number.length()-i)%3==0:
			result+=","
		result+=number[i]
	return result

func show_toast(text:String) -> void:
	toast.text=text
	toast_timer=6.0
	toast_panel.move_to_front()
	if game_root.started:
		_play_sound("tap-b")

func _play_sound(id:String) -> void:
	if sfx and sounds.has(id):
		sfx.stream=sounds[id]
		sfx.play()

func transition() -> void:
	var fade:=ColorRect.new()
	fade.color=Color(0.04,0.075,0.055,1)
	fade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(fade)
	var tween:=create_tween()
	tween.tween_property(fade,"color:a",0.0,0.45)
	tween.tween_callback(fade.queue_free)

func toggle_page(id:String) -> void:
	if page!="":
		close_page()
	else:
		show_page(id)

func show_page(id:String) -> void:
	page=id
	Game.paused=true
	_build_page()

func close_page() -> void:
	page=""
	if modal:
		modal.queue_free()
		modal=null
	Game.paused=not game_root.started or Game.status!="playing"

func _build_page() -> void:
	if modal:
		modal.queue_free()
	modal=Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(modal)
	var shade:=ColorRect.new()
	shade.color=Color(0.025,0.055,0.04,0.68)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(shade)
	var shell:=PanelContainer.new()
	shell.set_anchors_preset(Control.PRESET_CENTER)
	shell.position=Vector2(-500,-335)
	shell.size=Vector2(1000,670)
	shell.add_theme_stylebox_override("panel",_style(INK,16,22))
	modal.add_child(shell)
	var outer:=VBoxContainer.new()
	shell.add_child(outer)
	var header:=HBoxContainer.new()
	outer.add_child(header)
	var title:=_label("N / S     PERSONAL NETWORK",18,LIME)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_label("%s  ·  TIME PAUSED"%Game.time_text(),13,MUTED))
	_button("CLOSE  ×",close_page,header)
	var rule:=HSeparator.new()
	outer.add_child(rule)
	var columns:=HBoxContainer.new()
	columns.size_flags_vertical=Control.SIZE_EXPAND_FILL
	outer.add_child(columns)
	var nav:=VBoxContainer.new()
	nav.custom_minimum_size.x=175
	columns.add_child(nav)
	var nav_items:=[ ["Messages","messages"],["Contacts","contacts"],["Agenda","agenda"],["Suppliers","suppliers"],["Backpack","backpack"],["City map","map"],["Tuition","tuition"],["Controls","help"] ]
	for entry in nav_items:
		var id:String=entry[1]
		var b:=_button(entry[0],func():show_page(id),nav,page==id)
		b.alignment=HORIZONTAL_ALIGNMENT_LEFT
	var navfill:=Control.new()
	navfill.size_flags_vertical=Control.SIZE_EXPAND_FILL
	nav.add_child(navfill)
	nav.add_child(_label("CASH  $%s"%_money(Game.cash),15,CREAM))
	nav.add_child(_label("REPUTATION  %d"%Game.reputation,12,MUTED))
	var scroll:=ScrollContainer.new()
	scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(scroll)
	body=VBoxContainer.new()
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",14)
	scroll.add_child(body)
	match page:
		"messages":_messages_page()
		"schedule":_schedule_page()
		"contacts":_contacts_page()
		"agenda":_agenda_page()
		"suppliers":_suppliers_page()
		"backpack":_backpack_page()
		"map":_map_page()
		"tuition":_tuition_page()
		"shop":_shop_page()
		"home":_home_page()
		"campus":_campus_page()
		"pause":_pause_page()
		"confirm_restart":_restart_page()
		_:_help_page()
	toast_panel.move_to_front()

func _heading(title:String,subtitle:String="") -> void:
	body.add_child(_label(title,30,CREAM))
	if subtitle!="":
		_paragraph(subtitle)

func _messages_page() -> void:
	_heading("Your conversations","Choose the opportunity. Set the place and time. Keep your word.")
	if Game.tutorial_step==2:
		var card:=_card()
		card.add_child(_label("MILO  /  NEW CONNECTION",14,LIME))
		_paragraph("That helped a lot. Save my number — I know a few people who might want to meet you.",card,CREAM)
		_button("SAVE MILO TO CONTACTS",func():Game.add_tutorial_contact(),card,true)
	if Game.tutorial_step<2:
		_paragraph("Your phone is quiet. Milo is waiting outside class. Start with your backpack.")
	var count:=0
	for message in Game.inbox:
		if message.status!="new":
			continue
		count+=1
		var card:=_card()
		var row:=_row(card)
		var name:=_label(str(message.contact_name).to_upper(),18,LIME)
		name.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(name)
		row.add_child(_label("%d BAGS"%int(message.quantity),13,AMBER))
		_paragraph(str(message.get("text","Hey, are you around? Can we meet up today?")),card,CREAM)
		_paragraph("Reply before %s. You have %d packed bags."%[Game.format_minute(message.expires_minute),Game.inventory.dime_bag],card)
		var current:Dictionary=message.duplicate(true)
		_button("ARRANGE A MEETING   >",func():selected_message=current;show_page("schedule"),card,true)
	if count==0 and Game.tutorial_step>=3:
		_paragraph("All caught up. New texts arrive as time passes. Better relationships bring more introductions.")
		_button("CHECK YOUR AGENDA",func():show_page("agenda"))

func _schedule_page() -> void:
	_heading("Meet "+str(selected_message.get("contact_name","a contact")),"Your choices affect trust. Aim to arrive within 25 minutes of the agreed time.")
	var card:=_card()
	card.add_child(_label("MEETING PLACE",12,LIME))
	var location:=OptionButton.new()
	location.custom_minimum_size.y=44
	var locations:Array=Game.available_locations()
	for item in locations:
		location.add_item(item.name)
	card.add_child(location)
	card.add_child(_label("TIME FROM NOW",12,LIME))
	var time:=OptionButton.new()
	time.custom_minimum_size.y=44
	var delays:=[30,60,90,120,180,240]
	for delay in delays:
		time.add_item("%s  ·  in %d minutes"%[Game.format_minute(Game.minute+delay),delay])
	time.select(2)
	card.add_child(time)
	card.add_child(_label("PRICE PER BAG  /  FAIR PRICES BUILD TRUST",12,LIME))
	var price:=SpinBox.new()
	price.min_value=12
	price.max_value=40
	price.value=22
	price.prefix="$"
	price.step=1
	card.add_child(price)
	_paragraph("Quantity requested: %d. Available in backpack: %d. Quality: %d%%."%[int(selected_message.get("quantity",1)),Game.inventory.dime_bag,int(Game.dime_quality*100)],card)
	_button("CONFIRM MEETING",func():
		if Game.schedule_meeting(int(selected_message.id),locations[location.selected].id,delays[time.selected],price.value):
			game_root.navigate(locations[location.selected].id)
			show_page("agenda"),card,true)
	_button("Back to conversations",func():show_page("messages"))

func _contacts_page() -> void:
	_heading("People, not transactions","Trust grows with punctuality, quality, and fair prices. Friends introduce friends.")
	if Game.tutorial_step==2:
		_button("SAVE MILO",func():Game.add_tutorial_contact(),body,true)
	for contact in Game.contacts:
		var card:=_card()
		card.add_child(_label(str(contact.name),22,LIME))
		var trust:float=float(contact.get("relationship",contact.get("trust",50)))
		_paragraph("Relationship: %d / 100   ·   Completed deals: %d"%[int(trust),int(contact.get("sales",contact.get("deals",0)))],card,CREAM)
		_paragraph("Reliable regular" if trust>=65 else "Getting to know you",card)
	if Game.contacts.is_empty():
		_paragraph("Your network begins with Milo. Finish your first handoff outside class.")
	if not Game.contacts.is_empty():
		var card:=_card()
		card.add_child(_label("GET EVERYONE TOGETHER",16,AMBER))
		_paragraph("Host an evening gathering at your Deerfield apartment. Bring stock, food, and a little cash. Parties grow your network and attract attention.",card)
		_button("FIND YOUR APARTMENT",func():game_root.navigate("home");close_page(),card)

func _agenda_page() -> void:
	_heading("Today, on your terms","Class is your one fixed commitment. Everything else is a choice.")
	var class_card:=_card()
	class_card.add_child(_label("DAILY  /  CAMPUS CLASS",14,LIME))
	_paragraph("Next class: day %d, %s–10:00. Press E at the classroom entrance; class advances the clock. Missed classes: %d / 3."%[int(Game.next_class_minute()/1440)+1,Game.format_minute(Game.next_class_minute()),Game.missed_classes],class_card,CREAM)
	_button("DIRECTIONS TO CLASS",func():game_root.navigate("classroom");close_page(),class_card)
	for meeting in Game.active_meetings():
		var card:=_card()
		card.add_child(_label("%s   /   %s"%[Game.format_minute(meeting.due_minute),str(meeting.contact_name).to_upper()],20,AMBER))
		_paragraph("%s  ·  %d %s  ·  %s"%[Data.location_name(meeting.location_id),meeting.quantity,"bundles" if meeting.type=="supplier" else "bags","$%d total"%int(meeting.cost) if meeting.type=="supplier" else "$%d per bag"%int(meeting.price)],card,CREAM)
		var row:=_row(card)
		var id:int=meeting.id
		var loc:String=meeting.location_id
		var due:float=meeting.due_minute
		_button("GET DIRECTIONS",func():game_root.navigate(loc);close_page(),row,true)
		_button("Cancel",func():Game.cancel_meeting(id),row)
		if game_root.closest_location==loc and due>Game.minute:
			_button("WAIT HERE UNTIL %s"%Game.format_minute(due),func():Game.advance_time(maxf(0,due-Game.minute));close_page(),card)
	if Game.active_meetings().is_empty():
		_paragraph("No meetings scheduled. Check your messages or arrange a supplier pickup.")

func _suppliers_page() -> void:
	_heading("The next connection","Arrange a pickup, bring the cash, and get there yourself. Larger connections carry larger risks.")
	for supplier in Game.supplier_catalog():
		var card:=_card()
		card.add_child(_label(str(supplier.name).to_upper(),23,LIME))
		_paragraph("%s  ·  Requires %d reputation"%[supplier.title,supplier.reputation_required],card)
		_paragraph("$%d / bundle  ·  %d%% quality  ·  %d%% bust risk\nOne bundle packs into six bags."%[supplier.bundle_price,int(supplier.quality*100),int(supplier.risk*100)],card,CREAM)
		var row:=_row(card)
		var quantity:=SpinBox.new()
		quantity.min_value=1
		quantity.max_value=supplier.max_bundles
		quantity.value=1
		quantity.suffix="bundles"
		row.add_child(quantity)
		var tier:int=supplier.tier
		var b:=_button("ARRANGE PICKUP",func():
			if Game.supplier_order(tier,int(quantity.value)):
				show_page("agenda"),row,Game.reputation>=supplier.reputation_required)
		b.disabled=Game.reputation<supplier.reputation_required

func _backpack_page() -> void:
	_heading("Everything you carry","%.1f / 14.0 carry capacity. Travel light; leave room for your next pickup."%Game.inventory_weight())
	for item in Data.ITEMS:
		var quantity:int=Game.inventory.get(item,0)
		if quantity<=0:
			continue
		var data:Dictionary=Data.ITEMS[item]
		var card:=_card()
		var row:=_row(card)
		var name:=_label(str(data.name),21,CREAM)
		name.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(name)
		row.add_child(_label("× %d"%quantity,21,LIME))
		_paragraph(data.description,card)
		var id:String=item
		match item:
			"flower":_button("SPLIT INTO SIX DIME BAGS",func():Game.split_flower(),card,true)
			"sandwich","energy_drink":_button("CONSUME",func():Game.consume_item(id),card,true)
			"skateboard":_button("EQUIP / STOW",func():close_page();game_root.player.toggle_skateboard(),card)
			"dime_bag":_paragraph("Quality: %d%%. Hand off at your scheduled meeting with E."%int(Game.dime_quality*100),card,AMBER)
		if item not in ["skateboard","flower","dime_bag"] or Game.tutorial_step>=3:
			_button("DISCARD ONE  /  FREE UP SPACE",func():Game.discard_item(id,1),card)

func _map_page() -> void:
	_heading("Know your neighbourhood","Click a landmark to set directions. Campus south and east; College Square west; Deerfield northeast.")
	var map:=CityMap.new()
	map.large=true
	map.city=game_root.world
	map.student=game_root.player
	map.population=game_root.population
	map.destination=game_root.destination
	map.custom_minimum_size=Vector2(650,440)
	map.landmark_selected.connect(func(id:String):game_root.navigate(id);map.destination=id)
	body.add_child(map)
	_paragraph("Blue patrols belong to campus security. City police cover commercial and residential streets. Both can pursue you after witnessing a crime.")

func _tuition_page() -> void:
	_heading("A future of your own","Pay your student loan in any increments. When the balance reaches zero, you've won.")
	var card:=_card()
	card.add_child(_label("$%s"%_money(Game.tuition_remaining),56,AMBER))
	card.add_child(_label("REMAINING STUDENT LOAN",13,MUTED))
	_paragraph("Available cash: $%s. Keep enough for food and your next pickup."%_money(Game.cash),card,CREAM)
	var amount:=SpinBox.new()
	amount.min_value=1
	amount.max_value=maxf(1,minf(Game.cash,Game.tuition_remaining))
	amount.value=minf(100,amount.max_value)
	amount.prefix="$"
	card.add_child(amount)
	_button("MAKE A PAYMENT",func():Game.pay_tuition(amount.value),card,true)
	var stat:=_card()
	_paragraph("Sales completed: %d\nLifetime earnings: $%s\nClasses attended: %d\nFriends in your network: %d"%[Game.total_sales,_money(Game.total_earned),Game.classes_attended,Game.contacts.size()],stat,CREAM)

func _shop_page() -> void:
	var location:String=game_root.closest_location
	_heading("College Square" if location=="market" else ("Navaho Takeout" if location=="cafe" else ("Deerfield Motors" if location=="auto_dealer" else "After-hours market")),"A few essentials to keep your day moving.")
	if location=="auto_dealer":
		_paragraph("Your own car costs $900 and requires 22 reputation. It will be waiting just outside the dealership.")
		_button("PURCHASE VEHICLE  /  $900",func():
			if Game.purchase_vehicle():
				game_root.population.spawn_owned_vehicle(),body,true)
		return
	var items:Array=["sandwich","energy_drink"]
	if location=="market":
		items.append("skateboard")
	if location=="supplier":
		items=["pistol","ammo"]
	for item in items:
		var data:Dictionary=Data.ITEMS[item]
		var card:=_card()
		card.add_child(_label("%s   /   $%d"%[data.name,data.price],22,CREAM))
		_paragraph(data.description,card)
		var id:String=item
		_button("BUY ONE",func():Game.buy_item(id,1),card,true)
	if location in ["market","cafe"]:
		_button("STEP INSIDE",func():game_root.enter_building(location))

func _home_page() -> void:
	_heading("Your place on Deerfield","A small apartment. A little breathing room. Tomorrow is another chance.")
	if game_root.world.current_interior=="":
		_button("ENTER APARTMENT",func():game_root.enter_building("home"),body,true)
	var sleep:=_card()
	_paragraph("Sleep until 08:10 tomorrow. Restores energy and some health. Unfinished meetings may be missed while you sleep.",sleep)
	_button("SLEEP UNTIL MORNING",func():Game.sleep_at_home();close_page(),sleep)
	var party:=_card()
	_paragraph("Host an evening party between 17:00 and 23:00. Bring at least six bags and $25 for supplies. Requires reputation 5 and two contacts.",party)
	_button("HOST A PARTY",func():Game.host_party();close_page(),party,true)

func _campus_page() -> void:
	_heading("Campus life","The life you're trying to keep. A daily class and honest work when you need it.")
	var class_card:=_card()
	_paragraph("Arrive from 08:40 until 10:00. Class finishes at 11:00. Three missed classes ends your scholarship and your run.",class_card,CREAM)
	_button("ATTEND CLASS",func():
		if Game.attend_class():
			close_page();transition(),class_card,true)
	var job:=_card()
	_paragraph("The library needs help between 11:00 and 19:00. A two-hour shift pays $35. Useful when you need food or seed money.",job)
	_button("WORK A SHIFT  /  $35",func():
		if Game.work_shift():
			close_page();transition(),job)
	if game_root.world.current_interior=="":
		_button("ENTER THE LECTURE HALL",func():game_root.enter_building("classroom"))

func _pause_page() -> void:
	_heading("Take a breath","Your story is saved automatically. The clock pauses while any menu is open.")
	_button("RESUME",close_page,body,true)
	_button("SAVE STORY",func():Game.save_game();show_toast("Story saved in this browser."))
	_button("SOUND ON / OFF",func():game_root.ambient.stream_paused=not game_root.ambient.stream_paused)
	_button("CONTROLS",func():show_page("help"))
	_button("START OVER",func():show_page("confirm_restart"))

func _restart_page() -> void:
	_heading("Start a new story?","This erases your current campaign. Cash, contacts, and tuition progress will be reset.")
	_button("KEEP PLAYING",close_page,body,true)
	_button("ERASE RUN AND RESTART",func():Game.restart_game();get_tree().reload_current_scene())

func _help_page() -> void:
	_heading("A city at your fingertips","Keep your phone close. Keep your schedule closer.")
	for tip in tips:
		var card:=_card()
		card.add_child(_label(tip,18,CREAM))
	_paragraph("Mouse wheel changes camera distance. Click map landmarks for directions. Menus pause the clock. Close a menu with its Close button, Escape, or the same shortcut.")
	_paragraph("MEETINGS: Pack stock in your backpack, answer a text, choose a place/time/price, follow the map, and press E to hand off. If early, open Agenda at the meeting spot and wait.")
	_paragraph("SURVIVAL: Eat sandwiches, attend class daily between 09:00 and 10:00, and sleep at home. Three missed classes means eviction. Campus shifts can help recover seed money.")
	_paragraph("POLICE: Visible crimes and identified stolen cars trigger pursuit. Break line of sight for 10 seconds. A patrol close enough for 2.3 seconds arrests you and ends the run.")
	_paragraph("PROGRESSION: On-time sales and good value grow relationships. Contacts introduce friends. Reputation unlocks better suppliers and a car. Pay tuition from the phone to win.")
	if game_root.closest_location in ["campus_quad","classroom"]:
		_button("WORK CAMPUS SHIFT  /  $35 · 2 HOURS",func():Game.work_shift();close_page())

func show_ending(won:bool,reason:String) -> void:
	close_page()
	page="ending"
	Game.paused=true
	modal=Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(modal)
	var shade:=ColorRect.new()
	shade.color=Color(0.03,0.07,0.05,0.94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(shade)
	var panel:=PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position=Vector2(-350,-235)
	panel.size=Vector2(700,470)
	panel.add_theme_stylebox_override("panel",_style(INK,12,35))
	modal.add_child(panel)
	var box:=VBoxContainer.new()
	panel.add_child(box)
	box.add_child(_label("A FUTURE OF YOUR OWN" if won else "THE STORY ENDS HERE",14,LIME if won else RED))
	box.add_child(_label("TUITION PAID." if won else "GAME OVER.",48,CREAM))
	_paragraph(reason,box,CREAM)
	_paragraph("%d days  ·  %d sales  ·  %d contacts\n$%s earned  ·  %d classes attended"%[Game.day_number(),Game.total_sales,Game.contacts.size(),_money(Game.total_earned),Game.classes_attended],box)
	_space(box,20)
	_button("START A NEW STORY",func():Game.restart_game();get_tree().reload_current_scene(),box,true)
