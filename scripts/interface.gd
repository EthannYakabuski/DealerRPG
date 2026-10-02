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
var conversation: Dictionary = {}
var postpone_meeting_id := -1
var built_page := ""
var page_scroll: ScrollContainer
var controller_active := false
var quick_actions: Dictionary = {}
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
var feedback_voices: Array[AudioStreamPlayer] = []
var feedback_voice_cursor := 0
var sound_enabled := true
var meeting_card: Button
var meeting_location := ""
var money_feedback: Array[Control] = []
const EVENT_SOUNDS: Array[String] = ["pack", "purchase", "sale", "text", "caught", "detected", "consume", "tuition", "class", "party", "impact"]
var tips := ["WASD move  ·  SHIFT run  ·  SPACE skateboard", "TAB phone  ·  G agenda  ·  B backpack  ·  M map", "E interact / talk / rearrange a meeting in person", "V vehicle  ·  J punch  ·  K kick  ·  L shoot"]

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
	for sound in EVENT_SOUNDS:
		sounds[sound]=load("res://art/audio/feedback/%s.wav"%sound)
	# Separate voices keep a menu click or another text from cutting off a sale.
	for i in range(5):
		var voice:=AudioStreamPlayer.new()
		voice.volume_db=-12
		add_child(voice)
		feedback_voices.append(voice)
	_build_hud()
	_build_title()
	Game.changed.connect(func(): refresh_pending=true)
	Game.notification.connect(show_toast)
	Game.feedback_event.connect(_on_feedback_event)
	_update_hud()

func _theme() -> Theme:
	var theme:=Theme.new()
	theme.default_font_size=16
	theme.set_color("font_color","Label",CREAM)
	theme.set_color("font_color","Button",CREAM)
	theme.set_color("font_hover_color","Button",LIME)
	theme.set_color("font_focus_color","Button",LIME)
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

func _button(text:String,callback:Callable,parent:Node=body,primary:bool=false,focus_key:String="") -> Button:
	var b:=Button.new()
	b.text=text
	b.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	b.focus_mode=Control.FOCUS_ALL
	if focus_key!="": b.set_meta("focus_key",focus_key)
	b.custom_minimum_size.y=42
	b.pressed.connect(func():_play_sound("click-a");callback.call())
	if primary:
		b.add_theme_stylebox_override("normal",_style(LIME,7,12))
		b.add_theme_color_override("font_color",INK)
		b.add_theme_color_override("font_focus_color",INK)
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
	_build_meeting_card()
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
	for entry in [["TAB  Phone","messages"],["G  Agenda","agenda"],["B  Backpack","backpack"],["M  Map","map"],["?  Controls","help"]]:
		var id:String=entry[1]
		var action_button:=_button(entry[0],func():toggle_page(id),actions)
		action_button.focus_mode=Control.FOCUS_NONE
		quick_actions[id]=action_button
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
	labels.title_controls=_label("WASD move   /   E interact   /   TAB phone   /   SPACE skateboard",14,MUTED)
	box.add_child(labels.title_controls)
	box.add_child(_label("A fictional city inspired by Ottawa. All characters are adults.",11,MUTED))
	_focus_first_in.call_deferred(title_screen)

func start_play() -> void:
	title_screen.visible=false
	hud.visible=true
	close_page()
	_update_hud()

func _process(delta:float) -> void:
	toast_timer=maxf(0,toast_timer-delta)
	toast_panel.visible=toast_timer>0
	toast_panel.position.y=20 if page!="" else 115
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
	if controller_active:
		labels.objective.text=labels.objective.text.replace("[I]","[RB]").replace("[P]","[LB]").replace("[E]","[A]")
	labels.interact.text=game_root.interaction_text() if page=="" else ""
	labels.mode.text=game_root.player.travel_mode()+("   ·   X to skate" if controller_active else "   ·   SPACE to skate")
	minimap.destination=game_root.destination
	if game_root.destination!="" and game_root.world.landmarks.has(game_root.destination):
		var data:Dictionary=game_root.world.landmarks[game_root.destination]
		labels.route.text="> %s   ·   %dm"%[data.name,int(game_root.player.position.distance_to(data.position))]
	else:
		labels.route.text=""
	if game_root.population.pursuit:
		labels.objective.text="Patrols are pursuing you. Get out of sight for 10 seconds.\nEscape: %ds / 10"%int(game_root.population.escape_seconds)
	_update_meeting_card()

func _build_meeting_card() -> void:
	meeting_card=Button.new()
	meeting_card.name="UpcomingMeetingCard"
	meeting_card.position=Vector2(24,126)
	meeting_card.size=Vector2(290,206)
	meeting_card.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	meeting_card.focus_mode=Control.FOCUS_NONE
	meeting_card.add_theme_stylebox_override("normal",_style(Color(0.07,0.12,0.10,0.94),9,0))
	meeting_card.add_theme_stylebox_override("hover",_style(Color(0.14,0.22,0.15,0.97),9,0))
	meeting_card.add_theme_stylebox_override("pressed",_style(Color(0.20,0.29,0.17,0.98),9,0))
	meeting_card.pressed.connect(_route_upcoming_meeting)
	hud.add_child(meeting_card)
	var box:=VBoxContainer.new()
	box.mouse_filter=Control.MOUSE_FILTER_IGNORE
	box.position=Vector2(16,14)
	box.size=Vector2(258,178)
	box.add_theme_constant_override("separation",5)
	meeting_card.add_child(box)
	labels.meeting_heading=_label("NEXT MEETING",11,LIME)
	labels.meeting_countdown=_label("",28,CREAM)
	labels.meeting_contact=_label("",18,CREAM)
	labels.meeting_place=_label("",14,MUTED)
	labels.meeting_place.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	labels.meeting_time=_label("",12,MUTED)
	labels.meeting_hint=_label("CLICK FOR DIRECTIONS",11,LIME)
	for field in ["meeting_heading","meeting_countdown","meeting_contact","meeting_place","meeting_time","meeting_hint"]:
		box.add_child(labels[field])

func meeting_countdown(due_minute:float) -> String:
	var remaining:float=due_minute-Game.minute
	if remaining>0:
		var minutes:int=int(ceil(remaining))
		return "IN %dh %02dm"%[int(minutes/60.0),minutes%60] if minutes>=60 else "IN %dm"%minutes
	if remaining>-1:
		return "MEET NOW"
	return "%dm LATE"%int(floor(-remaining))

func _update_meeting_card() -> void:
	var upcoming:Array[Dictionary]=Game.active_meetings()
	meeting_card.visible=Game.tutorial_step>=3 and Game.status=="playing" and not upcoming.is_empty()
	if upcoming.is_empty():
		meeting_location=""
		return
	var meeting:Dictionary=upcoming[0]
	meeting_location=str(meeting.location_id)
	labels.meeting_heading.text="NEXT PICKUP" if meeting.type=="supplier" else "NEXT MEETING"
	labels.meeting_countdown.text=meeting_countdown(float(meeting.due_minute))
	labels.meeting_countdown.add_theme_color_override("font_color",RED if Game.minute>float(meeting.due_minute)+1 else (AMBER if float(meeting.due_minute)-Game.minute<=15 else CREAM))
	labels.meeting_contact.text=str(meeting.contact_name)
	labels.meeting_place.text=Data.location_name(meeting_location)
	labels.meeting_time.text="%s  ·  %d %s"%[_when(float(meeting.due_minute)),int(meeting.quantity),"bundles" if meeting.type=="supplier" else "bags"]
	labels.meeting_hint.text="CLICK FOR DIRECTIONS"+ ("  /  +%d LATER"%(upcoming.size()-1) if upcoming.size()>1 else "")
	meeting_card.tooltip_text="Set directions to "+Data.location_name(meeting_location)+". The clock keeps running."

func _route_upcoming_meeting() -> void:
	_update_meeting_card()
	if meeting_location!="":
		_play_sound("click-a")
		game_root.navigate(meeting_location)

func _on_feedback_event(kind:String,value:float) -> void:
	if not game_root.started:
		return
	_play_feedback_sound(kind)
	if value!=0 and kind in ["sale","purchase","tuition","party"]:
		_show_money_feedback(kind,value)

func _play_feedback_sound(kind:String) -> void:
	if not sound_enabled or not sounds.has(kind):
		return
	var chosen:AudioStreamPlayer=null
	for voice in feedback_voices:
		if not voice.playing:
			chosen=voice
			break
	if chosen==null:
		chosen=feedback_voices[feedback_voice_cursor]
		feedback_voice_cursor=(feedback_voice_cursor+1)%feedback_voices.size()
	chosen.stream=sounds[kind]
	chosen.play()

func _show_money_feedback(kind:String,value:float) -> void:
	# Three bounded, short-lived cards allow rapid purchases without an ever-growing
	# stack. Their tweens run independently of the paused simulation clock.
	while money_feedback.size()>=3:
		var oldest:Control=money_feedback.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	for existing in money_feedback:
		if is_instance_valid(existing):
			existing.position.y+=82
	var panel:=PanelContainer.new()
	panel.name="MoneyFeedback"
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position=Vector2(-300,245)
	panel.size=Vector2(276,70)
	panel.add_theme_stylebox_override("panel",_style(Color(0.06,0.13,0.085,0.96),9,12))
	root.add_child(panel)
	money_feedback.append(panel)
	var box:=VBoxContainer.new()
	box.mouse_filter=Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation",1)
	panel.add_child(box)
	box.add_child(_label(("+$" if value>0 else "-$")+_money(absf(value)),30,LIME if value>0 else AMBER))
	var caption:String={"sale":"SALE COMPLETE","purchase":"PURCHASE COMPLETE","tuition":"TUITION PAYMENT","party":"PARTY EARNINGS"}.get(kind,"TRANSACTION")
	box.add_child(_label(caption,11,MUTED))
	panel.modulate.a=0
	panel.scale=Vector2(0.96,0.96)
	var tween:=create_tween().bind_node(panel)
	tween.set_parallel(true)
	tween.tween_property(panel,"modulate:a",1.0,0.16)
	tween.tween_property(panel,"scale",Vector2.ONE,0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(1.8)
	tween.chain().tween_property(panel,"modulate:a",0.0,0.6)
	tween.chain().tween_callback(func():money_feedback.erase(panel);panel.queue_free())

func set_sound_enabled(enabled:bool) -> void:
	sound_enabled=enabled
	if game_root.ambient:
		game_root.ambient.stream_paused=not enabled
	if not enabled:
		sfx.stop()
		for voice in feedback_voices:
			voice.stop()

func _money(value:float) -> String:
	# Party proceeds and final tuition payments can include cents. The balance
	# and the receipt must agree, without advertising money the player cannot spend.
	var cents:int=int(round(value*100.0))
	var number:=str(int(cents/100.0))
	var result:=""
	for i in range(number.length()):
		if i>0 and (number.length()-i)%3==0:
			result+=","
		result+=number[i]
	return result+(".%02d"%(cents%100) if cents%100!=0 else "")

func show_toast(text:String) -> void:
	toast.text=text
	toast_timer=6.0
	toast_panel.move_to_front()

func _play_sound(id:String) -> void:
	if sound_enabled and sfx and sounds.has(id):
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
	if page=="conversation" and id!="conversation" and game_root.has_method("end_conversation"):
		game_root.end_conversation()
	page=id
	Game.paused=true
	_build_page()

func close_page() -> void:
	if page=="conversation" and game_root.has_method("end_conversation"):
		game_root.end_conversation()
	page=""
	built_page=""
	var focused:=get_viewport().gui_get_focus_owner()
	if focused: focused.release_focus()
	if modal:
		modal.queue_free()
		modal=null
	Game.paused=not game_root.started or Game.status!="playing"

func _build_page() -> void:
	var focus_state:Dictionary=_capture_focus() if built_page==page else {}
	built_page=page
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
	page_scroll=scroll
	scroll.follow_focus=true
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
		"conversation":_conversation_page()
		"postpone":_postpone_page()
		_:_help_page()
	toast_panel.move_to_front()
	for feedback in money_feedback:
		if is_instance_valid(feedback):
			feedback.move_to_front()
	_configure_focus_tree(modal)
	_restore_focus.call_deferred(focus_state)

func _focus_controls(node:Node) -> Array[Control]:
	var result:Array[Control]=[]
	# SpinBox's keyboard entry is an internal LineEdit. Include internal children
	# so rebuilding a live page can restore numeric-field focus as well as buttons.
	for child in node.get_children(true):
		if child is Control and child.focus_mode==Control.FOCUS_ALL and child.is_visible_in_tree():
			if not child is BaseButton or not child.disabled:
				result.append(child)
		result.append_array(_focus_controls(child))
	return result

func _focus_first_in(node:Control) -> void:
	if not is_instance_valid(node) or not node.is_visible_in_tree(): return
	var controls:=_focus_controls(node)
	if not controls.is_empty(): controls[0].grab_focus()

func focus_first_action() -> void:
	if page!="" and is_instance_valid(body):
		_focus_first_in(body)
		if not get_viewport().gui_get_focus_owner(): _focus_first_in(modal)
	elif is_instance_valid(title_screen) and title_screen.visible:
		_focus_first_in(title_screen)

func _configure_focus_tree(node:Node) -> void:
	for child in node.get_children():
		if child is SpinBox:
			child.focus_mode=Control.FOCUS_NONE
			var edit:LineEdit=child.get_line_edit()
			edit.focus_mode=Control.FOCUS_ALL
			edit.add_theme_stylebox_override("focus",_outline(LIME))
		elif child is OptionButton:
			child.focus_mode=Control.FOCUS_ALL
			child.add_theme_stylebox_override("focus",_outline(LIME))
		_configure_focus_tree(child)

func _capture_focus() -> Dictionary:
	var focused:=get_viewport().gui_get_focus_owner()
	if not focused or not is_instance_valid(modal) or not modal.is_ancestor_of(focused): return {}
	var path:Array[int]=[]
	var cursor:Node=focused
	while cursor!=modal:
		path.push_front(cursor.get_index(true))
		cursor=cursor.get_parent()
	return {"key":str(focused.get_meta("focus_key","")),"path":path,"scroll":page_scroll.scroll_vertical if is_instance_valid(page_scroll) else 0}

func _restore_focus(state:Dictionary) -> void:
	# Containers lay out at the end of a frame. Focusing an internal numeric entry
	# before that can scroll to its stale rectangle and hide the page introduction.
	var target_modal:Control=modal
	await get_tree().process_frame
	if not is_instance_valid(target_modal) or modal!=target_modal: return
	if page=="" or not is_instance_valid(modal): return
	if not state.is_empty():
		if is_instance_valid(page_scroll): page_scroll.scroll_vertical=int(state.get("scroll",0))
		var key:String=state.get("key","")
		if key!="":
			for control in _focus_controls(modal):
				if str(control.get_meta("focus_key",""))==key:
					control.grab_focus()
					return
		var candidate:Node=modal
		for index in state.get("path",[]):
			if int(index)>=candidate.get_child_count(true):
				candidate=null
				break
			candidate=candidate.get_child(int(index),true)
		if candidate is Control and candidate.focus_mode==Control.FOCUS_ALL and candidate.is_visible_in_tree():
			if not candidate is BaseButton or not candidate.disabled:
				candidate.grab_focus()
				return
	focus_first_action()

func adjust_focused_value(direction:int) -> bool:
	var focused:=get_viewport().gui_get_focus_owner()
	if not focused or page=="": return false
	var spin:SpinBox=focused if focused is SpinBox else (focused.get_parent() if focused.get_parent() is SpinBox else null)
	if not spin: return false
	spin.value=clampf(spin.value+float(direction)*spin.step,spin.min_value,spin.max_value)
	return true

func _when(minute:float) -> String:
	return "Day %d / %s"%[int(floor(minute/1440.0))+1,Game.format_minute(minute)]

func set_controller_active(active:bool) -> void:
	controller_active=active
	var names:Dictionary={"messages":"LB  Phone","agenda":"D-UP  Agenda","backpack":"RB  Backpack","map":"SELECT  Map","help":"Controls"} if active else {"messages":"TAB  Phone","agenda":"G  Agenda","backpack":"B  Backpack","map":"M  Map","help":"?  Controls"}
	for id:String in quick_actions:
		quick_actions[id].text=names[id]
	labels.title_controls.text="LEFT STICK move   /   A interact   /   LB phone   /   X skateboard" if active else "WASD move   /   E interact   /   TAB phone   /   SPACE skateboard"
	if active and not get_viewport().gui_get_focus_owner(): focus_first_action()
	_update_hud()

func show_conversation(context:Dictionary) -> void:
	conversation=context.duplicate(true)
	show_page("conversation")

func _conversation_page() -> void:
	_heading(str(conversation.get("name","Someone nearby")),str(conversation.get("district","A conversation on the street")))
	var card:=_card()
	var reply:String=str(conversation.get("response",conversation.get("text","You catch their attention. Start with a conversation, or take a chance on an offer.")))
	_paragraph(reply,card,CREAM)
	var actor_id:String=str(conversation.get("actor_id",conversation.get("npc_id","")))
	_button("MAKE SMALL TALK",func():game_root.conversation_action(actor_id,"smalltalk"),card,false,"street_talk")
	if bool(conversation.get("can_offer",true)):
		_button("OFFER A BAG  /  $%s"%_money(float(conversation.get("price",22))),func():game_root.conversation_action(actor_id,"offer"),card,true,"street_offer")
	if bool(conversation.get("can_add_contact",false)):
		_button("SAVE THEIR NUMBER",func():game_root.conversation_action(actor_id,"add_contact"),card,true,"street_save")
	_paragraph("People react differently. Get to know someone before deciding whether to trust them.",card)
	_button("LEAVE",func():game_root.conversation_action(actor_id,"leave"),body,false,"street_leave")

func show_postpone_meeting(meeting_id:int) -> void:
	postpone_meeting_id=meeting_id
	show_page("postpone")

func _postpone_page() -> void:
	var appointment:Dictionary={}
	for entry in Game.active_meetings():
		if int(entry.id)==postpone_meeting_id: appointment=entry
	if appointment.is_empty():
		_heading("This meeting is finished","Check your agenda for your next connection.")
		_button("BACK TO THE CITY",close_page,body,true)
		return
	_heading("Meet "+str(appointment.contact_name),"You are here together. Complete the handoff, or ask for another opportunity later.")
	var card:=_card()
	var supplier:bool=appointment.type=="supplier"
	_paragraph("%s  ·  %s\n%d %s  /  $%s total"%[_when(float(appointment.due_minute)),Data.location_name(str(appointment.location_id)),int(appointment.quantity),"bundles" if supplier else "bags",_money(float(appointment.cost) if supplier else float(appointment.price)*int(appointment.quantity))],card,CREAM)
	var patrols:int=game_root.population.police_presence_count(game_root.player.position)
	if patrols>0:
		_paragraph("You can see %d %s nearby. You can ask for more time if this feels exposed."%[patrols,"patrol" if patrols==1 else "patrols"],card,AMBER)
	var id:int=postpone_meeting_id
	_button("COMPLETE HANDOFF",func():
		if game_root.complete_in_person(id) and Game.status=="playing": close_page(),card,true,"meeting_handoff")
	var later:=_card()
	_paragraph("Need more time? Ask them to text again later. This clears the current appointment without a trust penalty; agree on a new meeting when they reply.",later)
	var delay:=OptionButton.new()
	delay.custom_minimum_size.y=44
	delay.set_meta("focus_key","postpone_delay")
	var delays:Array[int]=[120,180,240]
	for minutes:int in delays:
		delay.add_item("Text again in %d %s"%[int(minutes/60.0),"hour" if minutes==60 else "hours"])
	delay.select(0)
	later.add_child(delay)
	_button("CONFIRM POSTPONEMENT",func():
		if game_root.postpone_in_person(id,delays[delay.selected]) and Game.status=="playing": close_page(),later,false,"meeting_postpone")
	_button("CLOSE WITHOUT CHANGING THE MEETING",close_page)

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
	for introduction:Dictionary in Game.pending_introductions():
		count+=1
		_introduction_card(introduction)
	for message in Game.inbox:
		if message.status!="new":
			continue
		count+=1
		var card:=_card()
		var row:=_row(card)
		var name:=_label(str(message.contact_name).to_upper(),18,LIME)
		name.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var callback:bool=str(message.get("type","client"))=="supplier_callback"
		row.add_child(_label("PICKUP CALLBACK" if callback else "%d BAGS"%int(message.quantity),13,AMBER))
		_paragraph(str(message.get("text","Hey, are you around? Can we meet up today?")),card,CREAM)
		_paragraph("Reply before %s."%_when(float(message.expires_minute)),card)
		var current:Dictionary=message.duplicate(true)
		var message_id:int=int(message.id)
		if callback:
			_paragraph("Pickups run 22:00–02:00. Next available: %s."%_when(Game.next_supplier_minute()),card,AMBER)
			_button("ARRANGE THIS PICKUP",func():
				if Game.accept_supplier_callback(message_id): show_page("agenda"),card,true,"pickup_%d"%message_id)
		else:
			_paragraph("You have %d packed bags."%Game.inventory.dime_bag,card)
			if message.has("max_price"):
				_paragraph("Their offer: up to $%s per bag."%_money(float(message.max_price)),card,AMBER)
			_button("ARRANGE A MEETING   >",func():selected_message=current;show_page("schedule"),card,true,"request_%d"%message_id)
			_button("HIT ME UP TOMORROW",func():Game.request_tomorrow(message_id),card,false,"tomorrow_%d"%message_id)
	if count==0 and Game.tutorial_step>=3:
		_paragraph("All caught up. New texts arrive as time passes. Better relationships bring more introductions.")
		_button("CHECK YOUR AGENDA",func():show_page("agenda"))

func _introduction_card(introduction:Dictionary) -> void:
	var card:=_card()
	var id:int=int(introduction.id)
	card.add_child(_label(str(introduction.name).to_upper()+"  /  NEW NUMBER",18,AMBER))
	_paragraph(str(introduction.text),card,CREAM)
	_paragraph("Ask a little before saving this number. Answers are clues, not proof.",card)
	var questions:=_row(card)
	var who:=_button("WHO REFERRED YOU?",func():Game.ask_introduction(id,"referrer"),questions,false,"intro_%d_who"%id)
	var connection:=_button("HOW DO YOU KNOW THEM?",func():Game.ask_introduction(id,"connection"),questions,false,"intro_%d_connection"%id)
	who.disabled=str(introduction.get("who_answer",""))!=""
	connection.disabled=str(introduction.get("connection_answer",""))!=""
	if who.disabled: _paragraph(str(introduction.who_answer),card,CREAM)
	if connection.disabled: _paragraph(str(introduction.connection_answer),card,CREAM)
	var profile:Dictionary=Game.contact_profile(str(introduction.get("referrer_id","")))
	if not profile.is_empty() and (who.disabled or connection.disabled):
		_paragraph("WHAT YOU KNOW ABOUT %s\nStudies %s. Usually around %s."%[str(profile.get("name",introduction.get("referrer_name","your friend"))).to_upper(),str(profile.get("course","")),str(profile.get("hangout",""))],card,MUTED)
	var decisions:=_row(card)
	_button("SAVE CONTACT",func():Game.resolve_introduction(id,"accept"),decisions,true,"intro_%d_accept"%id)
	_button("DECLINE",func():Game.resolve_introduction(id,"decline"),decisions,false,"intro_%d_decline"%id)
	_button("BLOCK NUMBER",func():Game.resolve_introduction(id,"block"),decisions,false,"intro_%d_block"%id)

func _schedule_page() -> void:
	_heading("Meet "+str(selected_message.get("contact_name","a contact")),"Arrive on time for full trust. Contacts aim to be there about 12 minutes early.")
	var card:=_card()
	card.add_child(_label("MEETING PLACE",12,LIME))
	var location:=OptionButton.new()
	location.set_meta("focus_key","schedule_location")
	location.custom_minimum_size.y=44
	var locations:Array=Game.available_locations()
	for item in locations:
		location.add_item(item.name)
	card.add_child(location)
	card.add_child(_label("TIME FROM NOW",12,LIME))
	var time:=OptionButton.new()
	time.set_meta("focus_key","schedule_time")
	time.custom_minimum_size.y=44
	var delays:=[30,60,90,120,180,240,300,360,420,480]
	for delay in delays:
		time.add_item("%s  ·  in %d minutes"%[_when(Game.minute+delay),delay])
	time.select(2)
	card.add_child(time)
	card.add_child(_label("PRICE PER BAG  /  FAIR PRICES BUILD TRUST",12,LIME))
	var price:=SpinBox.new()
	price.min_value=12
	price.max_value=float(selected_message.get("max_price",40))
	price.value=minf(price.max_value,float(selected_message.get("suggested_price",22)))
	price.get_line_edit().set_meta("focus_key","schedule_price")
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
		var id:String=str(contact.id)
		var profile:Dictionary=Game.contact_profile(id)
		if not profile.is_empty():
			_paragraph(str(profile.get("bio","Studies %s. Usually around %s."%[profile.get("course",""),profile.get("hangout","")])),card)
		var last_reply:String=str(contact.get("last_reply",profile.get("last_reply","")))
		if last_reply!="": _paragraph('Last reply: "%s"'%last_reply,card,CREAM)
		_button("TEXT THEM / CHECK IN",func():Game.text_contact(id),card,false,"contact_%s_text"%id)
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
		card.add_child(_label("%s   /   %s"%[_when(float(meeting.due_minute)),str(meeting.contact_name).to_upper()],20,AMBER))
		_paragraph("%s  ·  %d %s  ·  %s"%[Data.location_name(meeting.location_id),meeting.quantity,"bundles" if meeting.type=="supplier" else "bags","$%d total"%int(meeting.cost) if meeting.type=="supplier" else "$%d per bag"%int(meeting.price)],card,CREAM)
		var row:=_row(card)
		var id:int=meeting.id
		var loc:String=meeting.location_id
		var due:float=meeting.due_minute
		_button("GET DIRECTIONS",func():game_root.navigate(loc);close_page(),row,true)
		_button("Cancel",func():Game.cancel_meeting(id),row)
		if game_root.closest_location==loc:
			var arrival:float=due-Game.MEETING_ARRIVAL_MINUTES
			var walk_in:float=due-30.0
			if Game.minute<walk_in:
				_paragraph("Skip ahead, then watch your contact walk over. They aim to arrive around %s."%Game.format_minute(arrival),card)
				_button("WAIT UNTIL %s"%Game.format_minute(walk_in),func():Game.advance_time(maxf(0,walk_in-Game.minute));close_page(),card)
			elif Game.minute<arrival:
				_paragraph("Your contact should arrive around %s. Close your phone while they make their way here."%Game.format_minute(arrival),card,AMBER)
			else:
				_paragraph("The arrival window is open. Close your phone and meet your contact in person.",card,AMBER)
	if Game.active_meetings().is_empty():
		_paragraph("No meetings scheduled. Check your messages or arrange a supplier pickup.")

func _suppliers_page() -> void:
	_heading("The next connection","Pickups run nightly, 22:00–02:00. Arrange a slot, bring the cash, and meet in person.")
	_paragraph("Next available pickup: %s. Larger connections carry larger risks."%_when(Game.next_supplier_minute()),body,AMBER)
	for supplier in Game.supplier_catalog():
		var card:=_card()
		card.add_child(_label(str(supplier.name).to_upper(),23,LIME))
		_paragraph("%s  ·  Requires %d reputation"%[supplier.title,supplier.reputation_required],card)
		_paragraph("$%d / bundle  ·  %d%% quality  ·  %d%% bust risk\nOne bundle packs into six bags."%[supplier.bundle_price,int(supplier.quality*100),int(supplier.risk*100)],card,CREAM)
		var row:=_row(card)
		var quantity:=SpinBox.new()
		quantity.custom_minimum_size.x=150
		quantity.min_value=1
		quantity.max_value=supplier.max_bundles
		quantity.value=1
		quantity.suffix="bundles"
		quantity.get_line_edit().set_meta("focus_key","supplier_%d_quantity"%int(supplier.tier))
		row.add_child(quantity)
		var tier:int=supplier.tier
		var b:=_button("ARRANGE PICKUP",func():
			if Game.supplier_order(tier,int(quantity.value)):
				show_page("agenda"),row,Game.reputation>=supplier.reputation_required,"supplier_%d_order"%tier)
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
			"dime_bag":_paragraph("Quality: %d%%. Hand off at your scheduled meeting with %s."%[int(Game.dime_quality*100),"A" if controller_active else "E"],card,AMBER)
		if item not in ["skateboard","flower","dime_bag"] or Game.tutorial_step>=3:
			_button("DISCARD ONE  /  FREE UP SPACE",func():Game.discard_item(id,1),card)

func _map_page() -> void:
	_heading("Know your neighbourhood","Choose a destination below or click a landmark. Campus south and east; College Square west; Deerfield northeast.")
	var map:=CityMap.new()
	map.large=true
	map.city=game_root.world
	map.student=game_root.player
	map.population=game_root.population
	map.destination=game_root.destination
	map.custom_minimum_size=Vector2(650,440)
	map.landmark_selected.connect(func(id:String):game_root.navigate(id);map.destination=id)
	var route:=_row()
	var destination:=OptionButton.new()
	destination.custom_minimum_size=Vector2(300,44)
	destination.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	destination.set_meta("focus_key","map_destination")
	for id:String in game_root.world.landmarks:
		var index:int=destination.item_count
		destination.add_item(str(game_root.world.landmarks[id].name))
		destination.set_item_metadata(index,id)
		if id==game_root.destination: destination.select(index)
	route.add_child(destination)
	_button("SET DIRECTIONS",func():
		var id:String=destination.get_selected_metadata()
		game_root.navigate(id)
		map.destination=id,route,true,"map_route")
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
	_button("SOUND: %s"%("ON" if sound_enabled else "OFF"),func():set_sound_enabled(not sound_enabled);_build_page())
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
	_paragraph("CONTROLLER: Left stick move; A interact / confirm; B close; X skateboard; Y vehicle; LT run; RT punch; LB phone; RB backpack; Select map; Start pause. D-pad up agenda, right contacts, left kick, down shoot. In menus, D-pad or stick selects; A confirms; left/right adjusts a focused price or quantity.")
	_paragraph("CONNECTIONS: Talk to people in the city, check in with saved contacts, and decide which introductions to trust. Questions and what you know about a friend can help you judge a new number. You can ask new requests to text tomorrow. At an in-person meetup, E opens the choice to complete the handoff or discuss postponing.")
	_paragraph("Mouse wheel changes camera distance. Click map landmarks for directions. Menus pause the clock. Close a menu with its Close button, Escape, or the same shortcut.")
	_paragraph("MEETINGS: Pack stock in your backpack, answer a text, choose a place/time/price, follow the map, and press E to hand off. If early, Agenda can skip ahead to 30 minutes before the meeting. Close your phone and watch your contact walk over; they aim to arrive 12 minutes early. The clock pauses in menus.")
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
	_paragraph("Day %d  ·  Sales: %d  ·  Contacts: %d\nEarned: $%s  ·  Classes attended: %d"%[Game.day_number(),Game.total_sales,Game.contacts.size(),_money(Game.total_earned),Game.classes_attended],box)
	_space(box,20)
	_button("START A NEW STORY",func():Game.restart_game();get_tree().reload_current_scene(),box,true)
	_focus_first_in.call_deferred(modal)
