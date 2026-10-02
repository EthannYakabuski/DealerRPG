extends SceneTree
## Deterministic integration tests. All save files stay under .godot; real saves
## are neither read by these instances nor overwritten by the test campaign.

const State = preload("res://scripts/game_state.gd")
const Data = preload("res://scripts/game_data.gd")
var checks: int = 0
var failures: int = 0
var game: Node
var feedback_events: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	game = State.new()
	game.save_path = "res://.godot/gameplay-test-save.json"
	if FileAccess.file_exists(game.save_path): DirAccess.remove_absolute(game.save_path)
	root.add_child(game)
	game.set_process(false)
	game.feedback_event.connect(func(kind: String, value: float): feedback_events.append({"kind": kind, "value": value}))
	_test_tutorial()
	_test_meetings()
	_test_customer_pacing()
	_test_feedback_events()
	_test_suppliers_inventory()
	_test_calendar_survival()
	_test_party_and_unlocks()
	_test_saves_and_hardcore()
	_test_meeting_walk_saves()
	_test_campaign()
	game.queue_free()
	if FileAccess.file_exists("res://.godot/gameplay-test-save.json"): DirAccess.remove_absolute("res://.godot/gameplay-test-save.json")
	print("GAMEPLAY TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _fresh() -> void:
	game.restart_game()
	game._rng.seed = 73921
	feedback_events.clear()

func _tutorial(wait_for_followup: bool = true) -> void:
	_fresh()
	game.split_flower()
	game.tutorial_sell()
	game.add_tutorial_contact()
	if wait_for_followup: game.advance_time(90.0)

func _test_tutorial() -> void:
	_fresh()
	_check(game.day_number() == 1 and game.time_text() == "10:00", "campaign starts outside class day one at 10:00")
	_check(not game.tutorial_sell(), "tutorial cannot sell before packing")
	_check(not game.add_tutorial_contact(), "tutorial cannot add a contact before first sale")
	game._process(5.0)
	_check(is_equal_approx(game.minute, 600.0), "tutorial clock freezes")
	_check(game.split_flower(), "bundle can be split")
	_check(game.inventory["flower"] == 0 and game.inventory["dime_bag"] == 6, "split converts exactly six abstract bags")
	_check(game.tutorial_step == 1, "tutorial advances after packing")
	_check(not game.split_flower(), "cannot split absent stock")
	_check(game.tutorial_sell(), "first tutorial handoff succeeds")
	_check(game.cash == 42.0 and game.inventory["dime_bag"] == 5, "first handoff transfers one bag and twenty dollars")
	_check(not game.tutorial_sell(), "tutorial sale cannot be duplicated")
	_check(game.add_tutorial_contact(), "Milo contact can be saved")
	_check(game.contacts.size() == 1 and game.inbox.is_empty() and game.tutorial_step == 3, "phone saves initial contact without instantly reordering")
	_check(not game.add_tutorial_contact(), "tutorial contact cannot duplicate")
	game.paused = true
	game._process(10.0)
	_check(game.minute == 600.0, "paused phone freezes time")
	game.paused = false
	game._process(1.0)
	_check(game.minute == 603.0, "clock advances three game minutes each second")
	_check(game.current_objective().contains("Milo will text later"), "post-tutorial objective explains the intentional wait")

func _test_meetings() -> void:
	_tutorial()
	var message_id: int = int(game.inbox[0]["id"])
	_check(not game.schedule_meeting(message_id, "moon", 90.0, 24.0), "invalid location rejected")
	_check(not game.schedule_meeting(message_id, "cafe", 5.0, 24.0), "impossible meeting delay rejected")
	_check(not game.schedule_meeting(message_id, "cafe", 90.0, -2.0), "negative price rejected")
	_check(not game.schedule_meeting(message_id, "cafe", INF, 24.0), "infinite delay rejected")
	_check(game.schedule_meeting(message_id, "cafe", 90.0, 24.0), "client meeting schedules")
	_check(not game.schedule_meeting(message_id, "cafe", 180.0, 24.0), "same request cannot be accepted twice")
	var meeting: Dictionary = game.active_meetings()[0]
	var meeting_id: int = int(meeting["id"])
	_check(not game.complete_meeting(meeting_id), "handoff fails at wrong location")
	game.player_location_id = "cafe"
	_check(not game.complete_meeting(meeting_id), "handoff fails before NPC arrival")
	game.advance_time(90.0)
	_check(game.complete_meeting(meeting_id), "on-time handoff succeeds")
	_check(game.cash == 90.0 and game.inventory["dime_bag"] == 3, "meeting transfers quoted quantity and cash")
	_check(game.reputation == 1 and float(game.contacts[0]["relationship"]) > 55.0, "fair punctual sale increases relationship and reputation")
	_check(not game.complete_meeting(meeting_id), "completed meeting cannot pay twice")
	game.advance_time(float(game.contacts[0]["next_request_minute"]) - game.minute + 61.0)
	var next_message: Dictionary = _new_message()
	_check(not next_message.is_empty(), "contacts create recurring demand")
	if not next_message.is_empty():
		game.schedule_meeting(int(next_message["id"]), "home", 60.0, 40.0)
		var next_meeting: Dictionary = game.active_meetings()[0]
		var relationship: float = float(game.contacts[0]["relationship"])
		game.advance_time(110.0)
		_check(next_meeting["status"] == "missed", "overdue meeting expires")
		_check(float(game.contacts[0]["relationship"]) < relationship, "no-show damages relationship")
	_tutorial()
	game.contacts[0]["relationship"] = 100.0
	game.schedule_meeting(int(game.inbox[0]["id"]), "home", 30.0, 24.0)
	meeting = game.active_meetings()[0]
	game.advance_time(70.0)
	game.player_location_id = "home"
	_check(game.complete_meeting(int(meeting["id"])), "close contacts forgive up to forty-five minutes of lateness")
	_tutorial()
	game.minute = 1440.0 + 450.0
	game.inbox[0]["expires_minute"] = 2500.0
	_check(not game.schedule_meeting(int(game.inbox[0]["id"]), "home", 90.0, 24.0), "meetings cannot overlap unattended class")

func _test_customer_pacing() -> void:
	_tutorial(false)
	game.advance_time(89.0)
	_check(game.inbox.is_empty(), "Milo gives the first purchase at least ninety minutes before texting")
	game.advance_time(1.0)
	_check(game.inbox.size() == 1, "first follow-up arrives after ninety minutes")
	var contact: Dictionary = game.contacts[0]
	game.schedule_meeting(int(game.inbox[0]["id"]), "cafe", 30.0, 24.0)
	var meeting: Dictionary = game.active_meetings()[0]
	game.player_location_id = "cafe"
	game.advance_time(17.0)
	_check(not game.complete_meeting(int(meeting["id"])), "meeting cannot trade thirteen minutes early")
	game.advance_time(1.0)
	_check(game.complete_meeting(int(meeting["id"])), "meeting can trade twelve minutes early once physically present")
	var deadline: float = float(contact["next_request_minute"])
	_check(deadline >= game.minute + 390.0 and deadline <= game.minute + 510.0, "a two-bag order lasts six-and-a-half to eight-and-a-half hours")
	game.advance_time(30.0)
	_check(_new_message().is_empty(), "customer does not text shortly after the handoff")
	_check(not game._create_request(contact), "direct request creation also respects the customer cooldown")
	game.save_game()
	game.restart_game(false)
	feedback_events.clear()
	_check(game.load_game(false), "cooldown save loads successfully")
	_check(is_equal_approx(float(game.contacts[0]["next_request_minute"]), deadline) and feedback_events.is_empty(), "save reload preserves cooldown and replays no transaction sounds")
	game.advance_time(deadline - game.minute - 1.0)
	_check(_new_message().is_empty(), "contact remains quiet throughout the cooldown")
	game.advance_time(62.0)
	_check(not _new_message().is_empty(), "customer can request another purchase after the cooldown")
	game.schedule_meeting(int(_new_message()["id"]), "cafe", 30.0, 24.0)
	game.cancel_meeting(int(game.active_meetings()[0]["id"]))
	var retry_at: float = float(game.contacts[0]["next_request_minute"])
	_check(retry_at >= game.minute + 240.0, "cancellation gives the contact four hours before another request")
	game.advance_time(60.0)
	_check(_new_message().is_empty(), "cancelled meeting does not produce instant replacement texts")
	game.save_game()
	game.load_game(false)
	_check(is_equal_approx(float(game.contacts[0]["next_request_minute"]), retry_at), "cancellation cooldown persists across reload")

	# Previous v2 saves remain readable. Keep accepted commitments, retire only
	# premature unaccepted requests, and derive a stable cooldown from history.
	_tutorial()
	game.schedule_meeting(int(game.inbox[0]["id"]), "cafe", 30.0, 24.0)
	game.advance_time(30.0)
	game.player_location_id = "cafe"
	game.complete_meeting(int(game.active_meetings()[0]["id"]))
	game.save_game()
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(game.save_path))
	legacy["contacts"][0].erase("next_request_minute")
	legacy["contacts"][0].erase("last_order_quantity")
	var premature: Dictionary = legacy["inbox"][0].duplicate(true)
	premature["id"] = 99
	premature["status"] = "new"
	premature["created_minute"] = game.minute + 1.0
	legacy["inbox"].append(premature)
	var accepted: Dictionary = legacy["meetings"][0].duplicate(true)
	accepted["id"] = 100
	accepted["status"] = "scheduled"
	accepted["due_minute"] = game.minute + 90.0
	legacy["meetings"].append(accepted)
	_write_save(legacy)
	_check(game.load_game(false), "existing version-two save migrates without losing the campaign")
	_check(float(game.contacts[0]["next_request_minute"]) >= game.minute + 390.0, "migration derives cooldown from last delivery quantity and time")
	_check(_new_message().is_empty() and game.active_meetings().size() == 1, "migration retires premature texts while preserving accepted meetings")
	game.save_game()
	var migrated_deadline: float = float(game.contacts[0]["next_request_minute"])
	game.load_game(false)
	_check(is_equal_approx(float(game.contacts[0]["next_request_minute"]), migrated_deadline), "migrated cooldown does not change on repeated reload")
	legacy = JSON.parse_string(FileAccess.get_file_as_string(game.save_path))
	legacy["contacts"][0]["next_request_minute"] = "invalid"
	_write_save(legacy)
	_check(not game.load_game(false), "damaged cooldown is rejected before mutating the running campaign")
	_tutorial()
	game._add_contact("new_friend", "New friend", 50.0)
	game._create_request(game.contacts[1])
	game.save_game()
	legacy = JSON.parse_string(FileAccess.get_file_as_string(game.save_path))
	legacy["contacts"][1].erase("next_request_minute")
	legacy["contacts"][1].erase("last_order_quantity")
	legacy["minute"] = game.minute + 10.0
	_write_save(legacy)
	_check(game.load_game(false) and game.inbox.back()["status"] == "new", "migration preserves a legitimate first request from a new contact")
	_tutorial()
	game.save_game()
	legacy = JSON.parse_string(FileAccess.get_file_as_string(game.save_path))
	legacy["contacts"][0].erase("next_request_minute")
	legacy["contacts"][0].erase("last_order_quantity")
	legacy["contacts"][0]["last_sale_minute"] = -1.0
	legacy["contacts"][0]["sales"] = 0
	legacy["inbox"][0]["created_minute"] = 600.0
	legacy["minute"] = 600.0
	legacy["next_message_minute"] = 635.0
	_write_save(legacy)
	_check(game.load_game(false) and _new_message().is_empty(), "migration repairs the original immediate tutorial follow-up")
	_check(float(game.contacts[0]["next_request_minute"]) == 690.0, "old tutorial saves receive the intended ninety-minute introductory cooldown")

func _test_feedback_events() -> void:
	_fresh()
	game.tutorial_sell()
	_check(feedback_events.is_empty(), "failed tutorial transaction emits no success feedback")
	game.split_flower()
	_check(_feedback_count("pack", 0.0) == 1, "successful packing emits one pack cue")
	game.split_flower()
	_check(_feedback_count("pack", 0.0) == 1, "failed packing does not replay its sound")
	game.tutorial_sell()
	game.tutorial_sell()
	_check(_feedback_count("sale", 20.0) == 1, "tutorial money feedback reports exactly one successful twenty-dollar sale")
	game.add_tutorial_contact()
	_check(_feedback_count("text", 0.0) == 0, "saving a contact does not sound like receiving a text")
	game.advance_time(90.0)
	_check(_feedback_count("text", 0.0) == 1, "new incoming request emits a single text cue")
	game.schedule_meeting(int(game.inbox[0]["id"]), "cafe", 30.0, 24.0)
	game.advance_time(30.0)
	game.player_location_id = "cafe"
	game.complete_meeting(int(game.active_meetings()[0]["id"]))
	_check(_feedback_count("sale", 48.0) == 1, "client feedback includes the actual quoted sale proceeds")
	game.buy_item("sandwich", 1)
	game.buy_item("sandwich", -1)
	_check(_feedback_count("purchase", -8.0) == 1, "only a successful shop purchase emits the exact cash delta")
	game.consume_item("sandwich")
	_check(_feedback_count("consume", 0.0) == 1, "consumption emits a successful use cue")
	game.supplier_order(0, 1)
	var supplier: Dictionary = _meeting_of_type("supplier")
	game.advance_time(float(supplier["due_minute"]) - game.minute)
	game.player_location_id = "car_park"
	game.complete_meeting(int(supplier["id"]))
	_check(_feedback_count("purchase", -46.0) == 1, "supplier payment emits purchase feedback only on physical pickup")
	game.pay_tuition(10.0)
	game.pay_tuition(9999.0)
	_check(_feedback_count("tuition", -10.0) == 1, "tuition cue carries the successful payment without failed payment feedback")
	game.player_location_id = "home"
	game.sleep_at_home()
	game.advance_time(30.0)
	game.player_location_id = "campus_quad"
	game.attend_class()
	game.attend_class()
	_check(_feedback_count("class", 0.0) == 1, "class cue plays once for completed attendance")
	game.caught_by_police()
	game.caught_by_police()
	_check(_feedback_count("caught", 0.0) == 1, "capture cue plays once, not repeatedly after game over")
	_tutorial()
	game.reputation = 5
	game._maybe_referral(game.contacts[0])
	game.resolve_introduction(int(game.pending_introductions()[0]["id"]), "accept")
	game.inventory["dime_bag"] = 12
	game.minute = 1020.0
	game.player_location_id = "home"
	var cash_before: float = game.cash
	game.host_party()
	_check(_feedback_count("party", game.cash - cash_before) == 1, "party cue includes net proceeds after supplies")

func _feedback_count(kind: String, value: float) -> int:
	var count: int = 0
	for event: Dictionary in feedback_events:
		if event["kind"] == kind and is_equal_approx(float(event["value"]), value): count += 1
	return count

func _write_save(state: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(game.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(state))
	file.close()

func _test_suppliers_inventory() -> void:
	_tutorial()
	_check(not game.supplier_order(0, 1), "supplier rejects unaffordable orders")
	game.cash = 1000.0
	_check(not game.supplier_order(2, 1), "supplier tiers require reputation")
	_check(not game.supplier_order(0, 20), "supplier bundle limit enforced")
	var old_cash: float = game.cash
	_check(game.supplier_order(0, 2), "supplier order creates a physical meeting")
	_check(game.inventory["flower"] == 0 and game.cash == old_cash, "supplier stock and payment wait for handoff")
	_check(not game.supplier_order(0, 1), "duplicate outstanding supplier order rejected")
	var supplier: Dictionary = game.active_meetings()[0]
	game.player_location_id = "car_park"
	game.advance_time(float(supplier["due_minute"]) - game.minute)
	_check(game.complete_meeting(int(supplier["id"])), "supplier handoff succeeds")
	_check(game.inventory["flower"] == 2 and game.cash == old_cash - 92.0, "supplier charges correct price and delivers bundles")
	_check(is_equal_approx(game.flower_quality, 0.72), "supplier sets quality")
	game.split_flower()
	_check(game.dime_quality < 0.76 and game.dime_quality > 0.72, "quality is weighted across mixed stock")
	game.player_location_id = "market"
	_check(not game.buy_item("sandwich", -1), "negative shop quantity rejected")
	_check(not game.buy_item("flower", 1), "flower cannot be bought at normal shop")
	_check(not game.buy_item("skateboard", 1), "duplicate skateboard rejected")
	_check(not game.buy_item("sandwich", 99), "backpack capacity enforced")
	_check(game.buy_item("sandwich", 2), "food purchase works")
	game.hunger = 5.0
	game.health = 70.0
	_check(game.consume_item("sandwich") and game.hunger == 53.0 and game.health == 78.0, "food restores hunger and health")
	game.energy = 1.0
	_check(game.consume_item("energy_drink") and game.energy == 66.0, "drink restores energy")
	_check(not game.consume_item("pistol"), "nonfood cannot be consumed")
	_check(not game.buy_item("pistol", 1), "weapons gated behind underground reputation")
	game.reputation = 8
	game.player_location_id = "car_park"
	_check(game.buy_item("pistol", 1) and game.buy_item("ammo", 2), "underground market works after unlock")
	_check(game.use_ammo() and game.inventory["ammo"] == 1 and game.heat > 0.0, "shots consume ammunition and create heat")
	_check(not game.discard_item("flower", -3), "negative discard cannot mint items")

func _test_calendar_survival() -> void:
	_tutorial()
	_check(not game.attend_class(), "day-one completed class cannot be repeated")
	game.player_location_id = "home"
	_check(game.sleep_at_home(), "sleep advances to morning")
	_check(game.day_number() == 2 and game.time_text() == "08:10", "sleep wakes before class")
	game.player_location_id = "campus_quad"
	_check(not game.attend_class(), "cannot attend class before doors open")
	game.advance_time(30.0)
	_check(game.attend_class(), "class entry opens at 08:40")
	_check(game.time_text() == "11:00" and game.classes_attended == 2 and game.missed_classes == 0, "class skip resolves attendance and time")
	game.advance_time(1440.0)
	_check(game.missed_classes == 1, "missing day-three class adds one warning")
	game.advance_time(1440.0)
	_check(game.missed_classes == 2 and game.status == "playing", "two misses remain survivable")
	game.advance_time(1440.0)
	_check(game.missed_classes == 3 and game.status == "lost", "third miss is hardcore eviction")
	_tutorial()
	game.hunger = 0.0
	game.health = 0.05
	game.advance_time(5.0)
	_check(game.status == "lost", "untreated starvation can end a run")
	_tutorial()
	game.cash = 0.0
	game.minute = 660.0
	game.player_location_id = "library"
	_check(game.work_shift() and game.cash == 35.0, "honest campus shift recovers a bankrupt run")
	_check(game.time_text() == "13:00", "shift spends real campaign time")
	_check(game.current_phase() == "Afternoon", "day phase derives from campaign clock")
	game.minute = 1230.0
	_check(game.current_phase() == "Dusk", "dusk phase is available")

func _test_party_and_unlocks() -> void:
	_tutorial()
	game.player_location_id = "home"
	_check(not game.host_party(), "party requires a social circle")
	game.reputation = 5
	game._maybe_referral(game.contacts[0])
	game.resolve_introduction(int(game.pending_introductions()[0]["id"]), "accept")
	game.inventory["dime_bag"] = 12
	game.minute = 1020.0
	var old_cash: float = game.cash
	_check(game.host_party(), "evening party succeeds with contacts and stock")
	_check(game.cash > old_cash and game.parties_hosted == 1 and game.reputation == 8, "party drives money reputation and social loop")
	_check(not game.host_party(), "parties limited to one per day")
	game.player_location_id = "car_park"
	game.cash = 1500.0
	_check(not game.purchase_vehicle(), "car ownership gated until late game")
	game.reputation = 22
	_check(game.purchase_vehicle() and game.vehicle_owned and game.cash == 600.0, "late-game legitimate car purchase works")
	_check(not game.purchase_vehicle(), "car cannot be purchased twice")

func _test_saves_and_hardcore() -> void:
	_tutorial()
	game.schedule_meeting(int(game.inbox[0]["id"]), "cafe", 90.0, 24.0)
	game.cash = 123.0
	game.minute = 650.0
	_check(game.save_game(), "versioned save writes")
	game.cash = 1.0
	game.minute = 12.0
	_check(game.load_game(false), "valid save restores")
	_check(game.cash == 123.0 and game.minute == 650.0 and game.active_meetings().size() == 1, "save preserves money clock and obligations")
	game.caught_by_police()
	_check(game.status == "lost", "police capture ends run")
	game.status = "playing"
	_check(game.load_game(false) and game.status == "lost", "hardcore death persists in save")
	var old_cash: float = game.cash
	_check(not game.split_flower() and not game.pay_tuition(1.0) and game.cash == old_cash, "terminal state rejects economy actions")
	game.restart_game()
	_check(game.status == "playing" and game.cash == 22.0 and game.tutorial_step == 0, "restart clears failed campaign")
	_check(not FileAccess.file_exists(game.save_path), "restart removes old hardcore save")
	game.save_game()
	var state: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(game.save_path))
	state["inventory"]["dime_bag"] = -1
	var file: FileAccess = FileAccess.open(game.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(state))
	file.close()
	_check(not game.load_game(false) and game.inventory["dime_bag"] == 0, "corrupted inventory rejected without partial mutation")
	_fresh()
	game.save_game()
	state = JSON.parse_string(FileAccess.get_file_as_string(game.save_path))
	state["version"] = -100
	file = FileAccess.open(game.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(state))
	file.close()
	_check(not game.load_game(false), "incompatible save version rejected")
	_tutorial()
	game.cash = 100.0
	_check(not game.pay_tuition(200.0) and game.cash == 100.0, "cannot pay tuition beyond funds")
	_check(game.pay_tuition(75.0) and game.cash == 25.0 and game.tuition_remaining == 3425.0, "partial tuition payments work")
	game.cash = 3425.0
	_check(game.pay_tuition() and game.status == "won" and game.tuition_remaining == 0.0, "full repayment wins campaign")
	_check(game.load_game(false) and game.status == "won", "victory persists in save")

func _test_meeting_walk_saves() -> void:
	_tutorial()
	var walks: Array[Dictionary] = []
	for index: int in range(3):
		walks.append({"id":11+index,"position":[18.0+index,0.2,47.0],"state":["approaching","waiting","departing"][index],"start_minute":650.0,"due":780.0,"target":[22.0,0.2,52.0]})
	game.world_state = {"position":[20.0,0.3,50.0],"interior":"","meeting_walks":walks}
	_check(game.save_game(), "meeting approaches can be written with campaign progress")
	game.world_state = {}
	_check(game.load_game(false) and game.world_state["meeting_walks"].size() == 3, "save reload preserves approaching waiting and departing clients")
	var restored: Array = game.world_state["meeting_walks"]
	_check(restored[0]["position"] == walks[0]["position"] and restored[0]["target"] == walks[0]["target"] and restored[0]["start_minute"] == 650.0 and restored[0]["due"] == 780.0, "meeting walk roundtrip preserves physical position route target and timing")
	_check(restored[0]["id"] is int and restored[2]["state"] == "departing", "meeting identities and departure state retain their expected types")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(game.save_path))
	var malformed: Array = ["not an actor"]
	var bad_fields: Dictionary = {"id":2.5,"position":[9999.0,0.2,50.0],"state":"teleporting","start_minute":800.0,"due":"tomorrow","target":[20.0,"infinite",50.0]}
	for field: String in bad_fields:
		var bad: Dictionary = walks[1].duplicate(true)
		bad[field] = bad_fields[field]
		malformed.append(bad)
	malformed.append(walks[0].duplicate(true))
	malformed.push_front(walks[0].duplicate(true))
	saved["world_state"]["meeting_walks"] = malformed
	_write_save(saved)
	_check(game.load_game(false) and game.world_state["meeting_walks"].size() == 1, "malformed walk records and duplicate actors are skipped without discarding valid neighbors")
	_check(game.cash == 42.0 and game.world_state["position"] == [20.0,0.3,50.0], "damaged optional actor data does not reset player progress or position")
	saved["world_state"].erase("meeting_walks")
	_write_save(saved)
	_check(game.load_game(false) and game.world_state["meeting_walks"].is_empty(), "older saves without meeting walks restore an empty compatible actor list")
	saved["world_state"]["meeting_walks"] = {"wrong":"container"}
	_write_save(saved)
	_check(game.load_game(false) and game.world_state["meeting_walks"].is_empty(), "invalid actor container is safely ignored")
	var too_many: Array[Dictionary] = []
	for index: int in range(11):
		var extra: Dictionary = walks[0].duplicate(true)
		extra["id"] = index+1
		too_many.append(extra)
	saved["world_state"]["meeting_walks"] = too_many
	_write_save(saved)
	_check(game.load_game(false) and game.world_state["meeting_walks"].is_empty(), "oversized optional actor payload is rejected at the ten-record limit")
	var early: Dictionary = walks[0].duplicate(true)
	early["start_minute"] = -120.0
	_check(game._sanitize_meeting_walks([early]).size() == 1, "finite early start for a long day-one walking route remains valid")
	early["position"] = [20.0,INF,50.0]
	_check(game._sanitize_meeting_walks([early]).is_empty(), "non-finite actor position is rejected before save serialization")

func _test_campaign() -> void:
	# Reach the actual tuition target using only legal API transactions from the
	# tutorial's starting resources, not injected money, reputation, or inventory.
	_tutorial()
	var iterations: int = 0
	var supplier_transactions: int = 0
	while game.status == "playing" and game.cash < game.tuition_remaining and iterations < 450:
		iterations += 1
		for introduction: Dictionary in game.pending_introductions():
			var profile: Dictionary = game.contact_profile(str(introduction["referrer_id"]))
			game.ask_introduction(int(introduction["id"]), "referrer")
			var answer: String = game.ask_introduction(int(introduction["id"]), "connection")
			game.resolve_introduction(int(introduction["id"]), "accept" if answer.contains(str(profile["course"])) and answer.contains(str(profile["hangout"])) else "block")
		if game.hunger < 38.0:
			game.player_location_id = "market"
			if int(game.inventory["sandwich"]) == 0: game.buy_item("sandwich", 1)
			game.consume_item("sandwich")
		if int(game.inventory["dime_bag"]) < 6:
			if int(game.inventory["flower"]) > 0:
				game.split_flower()
			elif game.cash >= 46.0:
				var tier: int = 2 if game.reputation >= 22 else (1 if game.reputation >= 8 else 0)
				var bundles: int = mini(4, int(game.cash / float(Data.SUPPLIERS[tier]["bundle_price"])))
				if game.supplier_order(tier, bundles):
					var supplier: Dictionary = _meeting_of_type("supplier")
					_advance_campaign_to(float(supplier["due_minute"]))
					game.player_location_id = str(supplier["location_id"])
					if game.complete_meeting(int(supplier["id"])): supplier_transactions += 1
					game.split_flower()
		var message: Dictionary = _new_message()
		if message.is_empty():
			_advance_campaign_to(game.minute + 60.0)
			continue
		if int(message["quantity"]) > int(game.inventory["dime_bag"]):
			if int(game.inventory["flower"]) > 0: game.split_flower()
			else:
				_advance_campaign_to(game.minute + 60.0)
				continue
		if game.schedule_meeting(int(message["id"]), "cafe", 45.0, 27.0):
			var meeting: Dictionary = _meeting_of_type("client")
			_advance_campaign_to(float(meeting["due_minute"]))
			game.player_location_id = "cafe"
			game.complete_meeting(int(meeting["id"]))
		else:
			_advance_campaign_to(game.minute + 40.0)
	_check(game.status == "playing", "full campaign survives food and attendance obligations")
	_check(game.missed_classes == 0, "slower customer demand still permits daily class attendance throughout the earned campaign")
	_check(game.cash >= game.tuition_remaining, "economy can earn full tuition from genuine starting resources")
	_check(game.reputation >= 22 and game.contacts.size() >= 5 and supplier_transactions > 3, "campaign reaches supplier ladder and word-of-mouth growth")
	_check(game.pay_tuition() and game.status == "won", "earned campaign finishes with tuition victory")
	print("CAMPAIGN: %d iterations, %d sales, %d supplier meets, day %d, rep %d, %d contacts" % [iterations, game.total_sales, supplier_transactions, game.day_number(), game.reputation, game.contacts.size()])

func _advance_campaign_to(target: float) -> void:
	while game.minute < target and game.status == "playing":
		if game.hunger < 38.0:
			game.player_location_id = "market"
			if int(game.inventory["sandwich"]) == 0: game.buy_item("sandwich", 1)
			game.consume_item("sandwich")
		var next_class: float = game.next_class_minute()
		if game.minute >= next_class - 10.0:
			game.player_location_id = "campus_quad"
			game.attend_class()
			continue
		game.advance_time(minf(minf(target, next_class - 10.0) - game.minute, 60.0))

func _new_message() -> Dictionary:
	for message: Dictionary in game.inbox:
		if message["status"] == "new": return message
	return {}

func _meeting_of_type(kind: String) -> Dictionary:
	for meeting: Dictionary in game.active_meetings():
		if meeting["type"] == kind: return meeting
	return {}
