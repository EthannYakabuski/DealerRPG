class_name GameControls
extends RefCounted
## Shared keyboard/gamepad bindings. Repeated scene starts never duplicate events.

static func setup() -> void:
	var keys := {"move_up":[KEY_W,KEY_UP],"move_down":[KEY_S,KEY_DOWN],"move_left":[KEY_A,KEY_LEFT],"move_right":[KEY_D,KEY_RIGHT],"sprint":[KEY_SHIFT],"interact":[KEY_E],"phone":[KEY_TAB,KEY_P],"backpack":[KEY_B,KEY_I],"map":[KEY_M],"agenda":[KEY_G],"contacts":[],"skateboard":[KEY_SPACE],"vehicle":[KEY_V],"punch":[KEY_J],"kick":[KEY_K],"shoot":[KEY_L],"pause_game":[KEY_ESCAPE]}
	for action: String in keys:
		if not InputMap.has_action(action): InputMap.add_action(action,0.25)
		for code: int in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = code
			_add(action,event)
	var buttons := {"interact":JOY_BUTTON_A,"skateboard":JOY_BUTTON_X,"vehicle":JOY_BUTTON_Y,"phone":JOY_BUTTON_LEFT_SHOULDER,"backpack":JOY_BUTTON_RIGHT_SHOULDER,"map":JOY_BUTTON_BACK,"pause_game":JOY_BUTTON_START,"agenda":JOY_BUTTON_DPAD_UP,"contacts":JOY_BUTTON_DPAD_RIGHT,"kick":JOY_BUTTON_DPAD_LEFT,"shoot":JOY_BUTTON_DPAD_DOWN,"ui_accept":JOY_BUTTON_A,"ui_cancel":JOY_BUTTON_B,"ui_up":JOY_BUTTON_DPAD_UP,"ui_down":JOY_BUTTON_DPAD_DOWN,"ui_left":JOY_BUTTON_DPAD_LEFT,"ui_right":JOY_BUTTON_DPAD_RIGHT}
	for action: String in buttons:
		var event := InputEventJoypadButton.new()
		event.device = -1
		event.button_index = buttons[action]
		_add(action,event)
	for binding: Array in [["move_left",JOY_AXIS_LEFT_X,-1.0],["move_right",JOY_AXIS_LEFT_X,1.0],["move_up",JOY_AXIS_LEFT_Y,-1.0],["move_down",JOY_AXIS_LEFT_Y,1.0],["sprint",JOY_AXIS_TRIGGER_LEFT,1.0],["punch",JOY_AXIS_TRIGGER_RIGHT,1.0],["ui_left",JOY_AXIS_LEFT_X,-1.0],["ui_right",JOY_AXIS_LEFT_X,1.0],["ui_up",JOY_AXIS_LEFT_Y,-1.0],["ui_down",JOY_AXIS_LEFT_Y,1.0]]:
		var event := InputEventJoypadMotion.new()
		event.device = -1
		event.axis = binding[1]
		event.axis_value = binding[2]
		_add(binding[0],event)
	for action: String in ["move_left","move_right","move_up","move_down"]:
		InputMap.action_set_deadzone(action,0.25)

static func _add(action: String,event: InputEvent) -> void:
	if not InputMap.has_action(action): InputMap.add_action(action)
	if not InputMap.action_has_event(action,event): InputMap.action_add_event(action,event)
