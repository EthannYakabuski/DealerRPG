extends HBoxContainer
## A quantity choice that behaves like a button, never a keyboard text field.

signal value_changed(value: int)

var value := 1
var maximum := 1
var choice: Button
var minus: Button
var plus: Button
var continue_button: Button

func setup(initial: int, limit: int, enabled: bool, focus_key: String) -> void:
	maximum = maxi(1, limit)
	value = clampi(initial, 1, maximum)
	add_theme_constant_override("separation", 6)
	minus = Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(48, 48)
	minus.focus_mode = Control.FOCUS_NONE
	minus.pressed.connect(func(): adjust(-1))
	add_child(minus)
	choice = Button.new()
	choice.custom_minimum_size = Vector2(170, 48)
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.disabled = not enabled
	choice.set_meta("focus_key", focus_key)
	choice.set_meta("bundle_stepper", self)
	choice.tooltip_text = "Left / right changes bundles. Down continues to Arrange Pickup."
	choice.gui_input.connect(_choice_input)
	choice.pressed.connect(func():
		if is_instance_valid(continue_button): continue_button.grab_focus())
	add_child(choice)
	plus = Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(48, 48)
	plus.focus_mode = Control.FOCUS_NONE
	plus.pressed.connect(func(): adjust(1))
	add_child(plus)
	_refresh()

func connect_continue(button: Button) -> void:
	continue_button = button
	choice.focus_neighbor_bottom = choice.get_path_to(button)
	choice.focus_next = choice.get_path_to(button)
	button.focus_neighbor_top = button.get_path_to(choice)
	button.focus_previous = button.get_path_to(choice)
	# Horizontal input belongs to this one quantity, not adjacent navigation.
	choice.focus_neighbor_left = NodePath(".")
	choice.focus_neighbor_right = NodePath(".")

func adjust(direction: int) -> void:
	if choice.disabled: return
	var previous := value
	value = clampi(value + direction, 1, maximum)
	_refresh()
	if previous != value: value_changed.emit(value)

func _choice_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		adjust(-1 if event.is_action_pressed("ui_left") else 1)
		choice.accept_event()

func _refresh() -> void:
	choice.text = "%d %s" % [value, "BUNDLE" if value == 1 else "BUNDLES"]
	minus.disabled = choice.disabled or value <= 1
	plus.disabled = choice.disabled or value >= maximum
