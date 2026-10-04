extends SceneTree
## Absolute appointment slots, new bundle yield and calendar-based police recovery.
const State = preload("res://scripts/game_state.gd")
const Data = preload("res://scripts/game_data.gd")
var game: Node
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	game = State.new()
	game.save_path = "res://.godot/meeting-recovery-test-save.json"
	if FileAccess.file_exists(game.save_path): DirAccess.remove_absolute(game.save_path)
	root.add_child(game)
	game.set_process(false)
	_test_locations()
	_test_slots()
	_test_arrivals_and_packing()
	_test_daily_decay()
	_test_decay_saves()
	game.queue_free()
	if FileAccess.file_exists("res://.godot/meeting-recovery-test-save.json"): DirAccess.remove_absolute("res://.godot/meeting-recovery-test-save.json")
	print("MEETING / RECOVERY TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MEETING / RECOVERY: " + label)

func _fresh() -> void:
	game.restart_game()
	game._rng.seed = 51204
	game.split_flower()
	game.tutorial_sell()
	game.add_tutorial_contact()
	game.advance_time(90.0)

func _request(id: String) -> Dictionary:
	game._add_contact(id, id.capitalize(), 45.0)
	game._create_request(game._find_contact(id))
	return game.inbox.back()

func _has_slot(slots: Array, minute: float) -> bool:
	for slot: Dictionary in slots:
		if is_equal_approx(float(slot["due_minute"]), minute): return true
	return false

func _test_locations() -> void:
	_fresh()
	var locations: Array = game.available_locations()
	_check(locations.size() == 16, "all sixteen named world landmarks appear in client scheduling")
	var seen: Dictionary = {}
	for location: Dictionary in locations:
		_fresh()
		var id: String = location["id"]
		_check(not seen.has(id) and game.schedule_meeting_at(int(game.inbox[0]["id"]), id, game.minute+60.0, 24.0), "unique named location %s accepts a client appointment" % id)
		seen[id] = true
	_check(seen.has("west_overlook") and seen.has("service_lane") and seen.has("east_trail") and seen.has("skate_park") and seen.has("bus_stop"), "outskirts and neighborhood landmarks are no longer hidden")

func _test_slots() -> void:
	_fresh()
	game.minute = 693.25
	_check(game.schedule_meeting_at(int(game.inbox[0]["id"]),"cafe",753.25,24.0), "first appointment can retain an existing fractional/non-grid timestamp")
	game.advance_time(1.4)
	var second: Dictionary = _request("second")
	var slots: Array = game.available_meeting_slots("second")
	_check(_has_slot(slots,783.25) and not _has_slot(slots,780.0), "available slots retain exact thirty-minute adjacency while filtering conflicting grid times")
	var adjacent_label: String = ""
	for slot: Dictionary in slots:
		if is_equal_approx(float(slot["due_minute"]),783.25): adjacent_label = str(slot["label"])
	_check(adjacent_label.contains("30 min after Milo"), "adjacent appointment has a readable relationship to the existing meeting")
	_check(game.schedule_meeting_at(int(second["id"]),"east_trail",783.25,24.0), "changed clock does not drift an absolute second appointment")
	var third: Dictionary = _request("third")
	_check(game.schedule_meeting_at(int(third["id"]),"bus_stop",813.25,24.0), "three appointments can be booked consecutively thirty minutes apart")
	_check(is_equal_approx(float(game.active_meetings()[1]["due_minute"])-float(game.active_meetings()[0]["due_minute"]),30.0), "stored appointments preserve exact promised spacing")
	var fourth: Dictionary = _request("fourth")
	_check(not game.schedule_meeting_at(int(fourth["id"]),"home",843.0,24.0), "a genuine sub-thirty-minute gap stays rejected")
	slots = game.available_meeting_slots("fourth")
	_check(_has_slot(slots,game.minute+480.0), "eight-hour horizon endpoint remains selectable even off the grid")
	_check(not game.schedule_meeting_at(int(fourth["id"]),"home",INF,24.0), "absolute scheduling rejects nonfinite dates")
	_fresh()
	game.minute = 1960.0
	game._class_resolved_through = 1
	slots = game.available_meeting_slots()
	_check(not _has_slot(slots,1980.0) and not _has_slot(slots,2100.0) and _has_slot(slots,2130.0), "morning class and release time stay clear in appointment preview")
	game.minute = 3600.0
	game._class_resolved_through = 2
	slots = game.available_meeting_slots()
	_check(_has_slot(slots,3690.0) and not _has_slot(slots,3720.0) and _has_slot(slots,3870.0), "afternoon timetable uses the same rules in slot preview")
	_fresh()
	game.minute = 1410.0
	_check(str(game.available_meeting_slots()[0]["label"]).begins_with("Day 2"), "next-day appointments display their day at midnight")

func _test_arrivals_and_packing() -> void:
	_fresh()
	_check(Data.BAGS_PER_BUNDLE == 7 and game.inventory["dime_bag"] == 6, "one seven-bag bundle leaves six bags after tutorial sale")
	game.inventory["flower"] = 1
	game.flower_quality = 0.98
	var old_quality: float = game.dime_quality
	_check(game.split_flower() and game.inventory["dime_bag"] == 13 and is_equal_approx(game.dime_quality,(old_quality*6.0+0.98*7.0)/13.0), "seven new bags retain correct weighted quality")
	for item: String in Data.ITEMS: game.inventory[item] = 0
	game.inventory["flower"] = 1
	game.inventory["dime_bag"] = 110
	_check(not game.split_flower() and game.inventory["flower"] == 1 and game.inventory["dime_bag"] == 110, "packing's small added weight cannot exceed the backpack limit or partially consume stock")
	_fresh()
	game.cash = 1000.0
	game.supplier_order(0,1)
	var supplier: Dictionary = game.active_meetings()[0]
	_check(game.meeting_arrival_minutes(supplier) == 15.0 and game.meeting_arrival_minutes({"type":"client"}) == 12.0, "supplier early handoff window differs from client arrival window")
	game.minute = float(supplier["due_minute"])-15.0
	game.player_location_id = "cafe"
	_check(not game.complete_meeting(int(supplier["id"])) and game.cash == 1000.0, "early supplier handoff still requires the correct physical location")
	game.player_location_id = str(supplier["location_id"])
	_check(game.complete_meeting(int(supplier["id"])) and game.minute == 1305.0, "booked22:00supplier can be handed off at21:45 when physical caller confirms presence")
	_check(not game.complete_meeting(int(supplier["id"])) and game.cash == 954.0, "early handoff cannot be paid twice")
	_fresh()
	game.schedule_meeting_at(int(game.inbox[0]["id"]),"cafe",750.0,24.0)
	var client: Dictionary = game.active_meetings()[0]
	game.minute = 735.0
	game.player_location_id = "cafe"
	_check(not game.complete_meeting(int(client["id"])), "client window remains twelve minutes rather than silently widening")

func _six_incidents(leave_active: bool = false) -> void:
	for index: int in range(6):
		game.register_pursuit("cafe")
		if not leave_active or index < 5: game.end_pursuit()

func _test_daily_decay() -> void:
	_fresh()
	game.minute = 1439.0
	_six_incidents()
	_check(game.escape_duration_seconds() == 30.0 and game.pursuit_incidents == 6, "six incidents finish the day at thirty-second recovery")
	game.advance_time(1.0)
	_check(game.escape_duration_seconds() == 20.0 and game.pursuit_incidents == 6 and game.pursuit_step == 4, "new day reduces two effective steps without erasing lifetime incidents")
	game.save_game()
	game.load_game(false)
	game.register_pursuit("market")
	_check(game.escape_duration_seconds() == 20.0 and game.pursuit_incidents == 7, "exact example: last thirty-second chase becomes next-day first twenty-second chase, including reload")
	game.end_pursuit()
	game.register_pursuit("market")
	_check(game.escape_duration_seconds() == 25.0, "next same-day incident resumes ordinary escalation after recovered first incident")
	game.end_pursuit()
	game.minute += 3.0*1440.0
	_check(game.escape_duration_seconds() == 10.0 and game.pursuit_step == 0, "multiple quiet days accumulate recovery with a ten-second floor")
	game.register_pursuit("market")
	_check(game.escape_duration_seconds() == 10.0 and game.pursuit_step == 1, "first pursuit after full recovery restarts at the initial tier")
	_fresh()
	game.minute = 1439.0
	_six_incidents(true)
	game.advance_time(1.0)
	_check(game.escape_duration_seconds() == 30.0 and game.pursuit_step == 4, "midnight never shortens the duration of a pursuit already in progress")
	game.save_game()
	_check(game.load_game(false) and game.escape_duration_seconds() == 30.0, "ongoing pursuit duration is frozen across save and resume")
	game.end_pursuit()
	game.register_pursuit("market")
	_check(game.escape_duration_seconds() == 20.0, "after ending the midnight pursuit the next incident uses recovered pressure")
	_fresh()
	game.minute = 1420.0
	_six_incidents()
	game.player_location_id = "home"
	_check(game.sleep_at_home() and game.day_number() == 2 and game.escape_duration_seconds() == 20.0, "sleeping across midnight applies exactly one day of recovery")
	var step: int = game.pursuit_step
	for reload_index: int in range(3):
		game.save_game()
		game.load_game(false)
	_check(game.pursuit_step == step, "repeated same-day loads cannot farm daily decay")

func _write(state: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(game.save_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(state))
	file.close()

func _test_decay_saves() -> void:
	_fresh()
	_six_incidents()
	game.save_game()
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(game.save_path))
	var legacy: Dictionary = saved.duplicate(true)
	for key: String in ["pursuit_step","pursuit_decay_day","pursuit_decay_pending","active_pursuit_escape_seconds"]: legacy.erase(key)
	_write(legacy)
	_check(game.load_game(false) and game.escape_duration_seconds() == 30.0, "legacy pressure history initializes current tier without inventing elapsed days")
	legacy["minute"] = 1439.0
	legacy["world_state"]["pursuit"] = true
	_write(legacy)
	game.load_game(false)
	game.advance_time(1.0)
	_check(game.escape_duration_seconds() == 30.0 and game.pursuit_step == 4, "legacy saved active pursuit gains a frozen duration before midnight recovery")
	var stale: Dictionary = saved.duplicate(true)
	stale["active_pursuit_escape_seconds"] = 30.0
	stale["world_state"]["pursuit"] = false
	stale["pursuit_step"] = 4
	_write(stale)
	_check(game.load_game(false) and game.active_pursuit_escape_seconds == 0.0 and game.escape_duration_seconds() == 20.0, "explicitly inactive world save clears stale pursuit duration")
	stale["world_state"] = {"position":[600.0,0.3,0.0],"interior":"home","pursuit":true}
	_write(stale)
	_check(game.load_game(false) and not game.world_state["pursuit"] and game.active_pursuit_escape_seconds == 0.0, "indoor save cannot restore a frozen outdoor pursuit")
	var corrupt: Dictionary = saved.duplicate(true)
	corrupt["pursuit_decay_day"] = 99
	_write(corrupt)
	_check(not game.load_game(false), "future decay anchor is rejected before applying a save")
	corrupt = saved.duplicate(true)
	corrupt["pursuit_decay_pending"] = "yes"
	_write(corrupt)
	_check(not game.load_game(false), "malformed decay state cannot load")
	corrupt = saved.duplicate(true)
	corrupt["active_pursuit_escape_seconds"] = 9.0
	_write(corrupt)
	_check(not game.load_game(false), "corrupt below-floor active chase requirement is rejected")
	game.restart_game()
	_check(game.pursuit_incidents == 0 and game.pursuit_step == 0 and game.active_pursuit_escape_seconds == 0.0, "new campaign clears effective and lifetime pursuit state")
