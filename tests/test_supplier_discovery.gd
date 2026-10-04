extends SceneTree
## Supplier discovery, rotating pickup contracts, social invitations and class days.
const State = preload("res://scripts/game_state.gd")
var game: Node
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	game = State.new()
	game.save_path = "res://.godot/supplier-discovery-test-save.json"
	if FileAccess.file_exists(game.save_path): DirAccess.remove_absolute(game.save_path)
	root.add_child(game)
	game.set_process(false)
	_test_request_cooldown()
	_test_callback_contract()
	_test_discovery()
	_test_party_supplier()
	_test_supplier_party_conflicts()
	_test_npc_party()
	_test_classes_and_spacing()
	_test_migration()
	game.queue_free()
	if FileAccess.file_exists("res://.godot/supplier-discovery-test-save.json"): DirAccess.remove_absolute("res://.godot/supplier-discovery-test-save.json")
	print("SUPPLIER / CALENDAR TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SUPPLIER / CALENDAR: " + description)

func _fresh() -> void:
	game.restart_game()
	game._rng.seed = 5513
	game.split_flower()
	game.tutorial_sell()
	game.add_tutorial_contact()
	game.advance_time(90.0)

func _write(state: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(game.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(state))
	file.close()

func _snapshot() -> Dictionary:
	game.save_game()
	return JSON.parse_string(FileAccess.get_file_as_string(game.save_path))

func _supplier() -> Dictionary:
	for meeting: Dictionary in game.active_meetings():
		if meeting["type"] == "supplier": return meeting
	return {}

func _test_request_cooldown() -> void:
	_fresh()
	game.cash = 1000.0
	game.reputation = 100
	_check(game.supplier_catalog()[0]["unlocked"] and not game.supplier_catalog()[1]["unlocked"] and not game.supplier_order(2,1), "only Rae is initially accessible even with high reputation")
	var requested: float = game.minute
	_check(game.supplier_order(0,1) and _supplier()["location_id"] == "west_overlook", "first Rae order chooses the west overlook")
	_check(game.cash == 1000.0 and game.supplier_progress[0]["next_order_minute"] == requested + 2880.0, "two-day request cooldown begins without charging pickup cash")
	game.cancel_meeting(int(_supplier()["id"]))
	_check(not game.supplier_order(0,1), "cancelling an order cannot bypass its request cooldown")
	game.save_game()
	_check(game.load_game(false) and not game.supplier_catalog()[0]["can_order"], "supplier restock deadline survives save and reload")
	game.minute = requested + 2879.0
	_check(not game.supplier_order(0,1), "cooldown lasts the full two campaign days")
	game.minute += 1.0
	_check(game.supplier_order(0,1) and _supplier()["location_id"] == "service_lane", "next new request opens exactly at deadline and rotates pickup site")
	game.cancel_meeting(int(_supplier()["id"]))
	game.minute += 2880.0
	_check(game.supplier_order(0,1) and _supplier()["location_id"] == "east_trail", "third new request uses a third remote location")

func _test_callback_contract() -> void:
	_fresh()
	game.minute = 1320.0
	game.cash = 1000.0
	game.supplier_order(0,1)
	var meeting: Dictionary = _supplier()
	var original_id: int = meeting["obligation_id"]
	var original_deadline: float = game.supplier_progress[0]["next_order_minute"]
	game.minute = meeting["due_minute"]
	game.player_location_id = str(meeting["location_id"])
	_check(game.postpone_meeting(int(meeting["id"])), "supplier can postpone a physical pickup without creating a second order")
	game.advance_time(120.0)
	var callback: Dictionary = {}
	for message: Dictionary in game.inbox:
		if message.get("type", "") == "supplier_callback" and message["status"] == "new": callback = message
	_check(not callback.is_empty() and callback["obligation_id"] == original_id, "delivered callback preserves original pickup identity")
	game.save_game()
	game.load_game(false)
	_check(game.accept_supplier_callback(int(callback["id"])), "legitimate callback can rebook before two-day cooldown expires")
	meeting = _supplier()
	_check(meeting["location_id"] == "west_overlook" and meeting["obligation_id"] == original_id and game.supplier_progress[0]["next_order_minute"] == original_deadline and game.supplier_progress[0]["orders_placed"] == 1, "callback retains site and neither resets nor consumes new-order cadence")
	_check(not game.accept_supplier_callback(int(callback["id"])), "same callback cannot create repeated exemptions")
	game.minute = meeting["due_minute"]
	game.player_location_id = str(meeting["location_id"])
	_check(game.complete_meeting(int(meeting["id"])) and game.supplier_progress[0]["successful_meetings"] == 1, "rebooked pickup counts as exactly one completed supplier meeting")
	_check(not game.supplier_order(0,1), "completing callback does not permit a new request before original cooldown")

func _test_discovery() -> void:
	_fresh()
	game.minute = 1200.0
	game.player_location_id = "service_lane"
	_check(game.supplier_encounters().is_empty() and not game.supplier_encounter_action("supplier_1","introduce"), "remote supplier introduction requires the late-night window")
	game.minute = 1320.0
	game.player_location_id = "cafe"
	_check(not game.supplier_encounter_action("supplier_1","introduce"), "supplier introduction requires correct physical landmark")
	game.player_location_id = "service_lane"
	_check(game.supplier_encounter_view("supplier_1")["choices"][0]["id"] == "introduce" and game.supplier_encounter_action("supplier_1","introduce"), "meeting Sable exchanges numbers permanently")
	_check(game.supplier_catalog()[1]["unlocked"] and not game.supplier_encounter_action("supplier_1","introduce"), "repeat introduction cannot duplicate supplier access")
	game.cash = 2000.0
	for count: int in range(3):
		game.minute = maxf(game.minute, float(game.supplier_progress[1]["next_order_minute"]))
		_check(game.supplier_order(1,1), "earned Sable pickup %d respects request cadence" % (count+1))
		var meeting: Dictionary = _supplier()
		game.minute = meeting["due_minute"]
		game.player_location_id = str(meeting["location_id"])
		_check(game.complete_meeting(int(meeting["id"])), "Sable pickup %d physically completes" % (count+1))
		_check(game.pending_supplier_introductions().size() == (1 if count == 2 else 0), "Regent referral requires all three completed pickups")
	_check(game.pending_supplier_introductions()[0]["text"].contains("Sable") and game.pending_supplier_introductions()[0]["text"].contains("three"), "persistent referral supplies the introduction clues")
	game.player_location_id = "east_trail"
	_check(not game.supplier_encounter_action("supplier_2","rae") and not game.supplier_catalog()[2]["unlocked"], "incorrect Regent answer delays introduction without unlocking")
	var retry: float = game.supplier_progress[2]["retry_minute"]
	game.save_game()
	_check(game.load_game(false) and game.supplier_progress[2]["retry_minute"] == retry and game.pending_supplier_introductions().size() == 1, "failed interview retry and readable referral survive reload")
	_check(not game.supplier_encounter_action("supplier_2","sable"), "reopening conversation cannot bypass interview retry")
	game.minute = retry
	game.player_location_id = "east_trail"
	_check(game.supplier_encounter_action("supplier_2","sable"), "correct referrer answer advances the interview")
	game.save_game()
	_check(game.load_game(false) and game.supplier_progress[2]["interview_stage"] == 1, "partly completed interview persists")
	_check(game.supplier_encounter_action("supplier_2","three") and game.supplier_catalog()[2]["unlocked"] and game.pending_supplier_introductions().is_empty(), "correct track-record answer grants permanent Regent access")
	game.save_game()
	_check(game.load_game(false) and game.supplier_catalog()[2]["unlocked"], "supplier access does not expire on save/reload")

func _test_party_supplier() -> void:
	var appearances: int = 0
	for seed_value: int in range(1,21):
		_fresh()
		game._rng.seed = seed_value
		game.reputation = 5
		game.cash = 100.0
		game.minute = 1020.0
		game.player_location_id = "home"
		game._add_contact("party_friend","Jules",50.0)
		game.host_party()
		if not game._party_guest("supplier_1").is_empty(): appearances += 1
	_check(appearances > 3 and appearances < 17, "seeded party sample includes both outcomes of the fifty-percent supplier visit roll")
	if game._party_guest("supplier_1").is_empty(): game._add_party_supplier(true)
	var saved_presence: bool = game.active_party["supplier_present"]
	game.save_game()
	_check(game.load_game(false) and game.active_party["supplier_present"] == saved_presence, "saving party does not reroll the supplier guest")
	game.minute = float(game._party_guest("supplier_1")["arrival_minute"])
	_check(game.mark_party_guest_arrived("supplier_1") and game.party_guest_view("supplier_1")["supplier"] and not game.party_guest_view("supplier_1")["can_offer"], "supplier arrives as a social contact rather than a retail buyer")
	_check(game.chat_party_guest("supplier_1") and game.supplier_catalog()[1]["unlocked"] and not game.chat_party_guest("supplier_1"), "party introduction unlocks Sable once without requiring reputation eight")

func _test_supplier_party_conflicts() -> void:
	_fresh()
	game.reputation = 5
	game.cash = 1000.0
	game.minute = 1320.0
	game.player_location_id = "home"
	game._add_contact("party_friend", "Jules", 50.0)
	game.host_party()
	if game._party_guest("supplier_1").is_empty(): game._add_party_supplier(true)
	game.minute = 1350.0
	game.mark_party_guest_arrived("supplier_1")
	game.chat_party_guest("supplier_1")
	_check(game.supplier_pickup_minute(1) == 1530.0 and game.supplier_catalog()[1]["next_pickup_minute"] == 1530.0, "late party supplier preview leaves thirty minutes to depart after01:00closing")
	_check(game.supplier_order(1,1) and _supplier()["due_minute"] == 1530.0, "booking party guest Sable uses same nonconflicting time as preview")
	_fresh()
	game.reputation = 5
	game.cash = 1000.0
	game.minute = 1320.0
	game.player_location_id = "service_lane"
	game.supplier_encounter_action("supplier_1", "introduce")
	game.supplier_order(1,1)
	game._add_contact("party_friend", "Jules", 50.0)
	game.player_location_id = "home"
	game.host_party()
	game._add_party_supplier(true)
	_check(game._party_guest("supplier_1").is_empty() and not game.active_party["supplier_present"], "existing supplier pickup prevents a simultaneous Sable party appearance")
	game.minute = float(_supplier()["due_minute"])
	game.player_location_id = str(_supplier()["location_id"])
	game.postpone_meeting(int(_supplier()["id"]))
	game._add_party_supplier(true)
	_check(game._party_guest("supplier_1").is_empty(), "pending supplier callback during the party also prevents a duplicate guest")

func _test_npc_party() -> void:
	_fresh()
	var host: Dictionary = game.contacts[0]
	_check(game._create_npc_party_invitation(host).is_empty(), "weak relationship cannot generate a friend's invitation")
	host["relationship"] = 70.0
	var invite: Dictionary = game._create_npc_party_invitation(host)
	var original_cash: float = game.cash
	var original_stock: int = game.inventory["dime_bag"]
	_check(not invite.is_empty() and invite["status"] == "new" and not game.party_summary()["active"], "strong friend's invitation is an opportunity until explicitly accepted")
	game._add_contact("busy_friend","Busy friend",70.0)
	game._create_request(game._find_contact("busy_friend"))
	var busy_message: Dictionary = game.inbox.back()
	game.schedule_meeting(int(busy_message["id"]),"cafe",480.0,24.0)
	_check(game.accept_party_invitation(int(invite["id"])) and not game.accept_party_invitation(int(invite["id"])), "invitation is accepted once with an explicit party time")
	_check(not game.schedule_meeting(int(game.inbox[0]["id"]),"cafe",420.0,24.0), "accepted party host cannot also schedule a conflicting meetup")
	game.save_game()
	_check(game.load_game(false) and game.party_invitations()[0]["status"] == "accepted" and not game.party_summary()["active"], "future accepted invitation persists without starting early")
	game.advance_time(float(invite["start_minute"]) - game.minute)
	var summary: Dictionary = game.party_summary()
	_check(summary["active"] and summary["mode"] == "npc" and summary["location_id"] == "deerfield_social" and summary["host_id"] == "milo", "clock opens accepted party at the actual neighbor apartment")
	_check(game._party_guest("busy_friend").is_empty(), "busy contact is not duplicated as a party guest")
	_check(game.cash == original_cash and game.inventory["dime_bag"] == original_stock and not summary["can_invite"], "visiting friend's party costs no hosting supplies and grants no passive sales")
	game.mark_party_guest_arrived("milo")
	game.player_location_id = "home"
	_check(not game.chat_party_guest("milo"), "neighbor party requires visiting its own venue")
	game.player_location_id = "deerfield_social"
	_check(game.party_guest_view("milo")["text"].contains("Glad you made it") and game.chat_party_guest("milo"), "NPC host welcomes the player as a guest")
	game.world_state = {"position":[1000.0,0.3,0.0],"interior":"deerfield_social","party_walks":[{"contact_id":"milo","state":"inside","position":[1001.0,0.3,2.0],"slot":8}],"supplier_walks":[{"id":"supplier_2","state":"approaching","position":[128.0,0.3,-106.0]}]}
	game.save_game()
	_check(game.load_game(false) and game.world_state["interior"] == "deerfield_social" and game.world_state["party_walks"].size() == 1 and game.world_state["supplier_walks"].size() == 1, "neighbor room, ninth guest slot and physical supplier approach persist")
	game.advance_time(float(summary["end_minute"]) - game.minute)
	_check(not game.party_summary()["active"] and game.party_invitations().is_empty(), "NPC party ends at its advertised time")

func _test_classes_and_spacing() -> void:
	_fresh()
	_check(game.class_schedule(2)["start_minute"] == 1980.0 and game.class_schedule(3)["start_minute"] == 3720.0, "daily schedule includes both morning and afternoon classes")
	game.minute = 3540.0
	game._class_resolved_through = 2
	game._resolve_classes()
	_check(game.missed_classes == 0 and game.next_class_minute() == 3720.0, "afternoon class does not count missed at the old morning deadline")
	game.player_location_id = "classroom"
	_check(not game.attend_class(), "afternoon doors do not open in the morning")
	game.minute = 3700.0
	_check(game.attend_class() and game.minute == 3840.0 and game.classes_attended == 2, "afternoon attendance starts at13:40 and releases at16:00")
	_check(not game.attend_class(), "only one daily class can be attended")
	game.minute = 5160.0
	game._resolve_classes()
	_check(game.missed_classes == 1, "following morning class resolves its own deadline")
	_fresh()
	game._add_contact("second","Second",50.0)
	game._create_request(game._find_contact("second"))
	_check(game.schedule_meeting(int(game.inbox[0]["id"]),"cafe",30.0,24.0) and game.schedule_meeting(int(game.inbox[1]["id"]),"market",60.0,24.0), "consecutive client appointments can be exactly thirty minutes apart")
	game._add_contact("third","Third",50.0)
	game._create_request(game._find_contact("third"))
	_check(not game.schedule_meeting(int(game.inbox.back()["id"]),"home",89.0,24.0), "twenty-nine-minute appointment gap remains rejected")
	_fresh()
	game.minute = 3400.0
	game._class_resolved_through = 2
	game.inbox[0]["expires_minute"] = 3900.0
	_check(not game.schedule_meeting(int(game.inbox[0]["id"]),"cafe",320.0,24.0), "meeting conflict follows actual afternoon class window")

func _test_migration() -> void:
	_fresh()
	game.cash = 1000.0
	game.minute = 1320.0
	game.player_location_id = "service_lane"
	game.supplier_encounter_action("supplier_1","introduce")
	game.supplier_order(1,1)
	var legacy: Dictionary = _snapshot()
	legacy.erase("supplier_progress")
	legacy.erase("npc_party_invites")
	legacy.erase("last_party_invite_day")
	_write(legacy)
	_check(game.load_game(false) and game.supplier_catalog()[1]["unlocked"] and game.supplier_progress[1]["next_order_minute"] == 4200.0, "legacy used supplier access and latest request cooldown migrate from accepted history")
	var old_deadline: float = game.supplier_progress[1]["next_order_minute"]
	game.save_game()
	_check(game.load_game(false) and game.supplier_progress[1]["next_order_minute"] == old_deadline, "migrated request cadence does not reroll on reload")
	var corrupt: Dictionary = _snapshot()
	corrupt["supplier_progress"][1]["successful_meetings"] = -1
	_write(corrupt)
	_check(not game.load_game(false), "damaged supplier progress is rejected before applying state")
	corrupt = legacy.duplicate(true)
	corrupt["npc_party_invites"] = [{"id":999,"host_id":"missing"}]
	_write(corrupt)
	_check(not game.load_game(false), "malformed party invitation is rejected")
	_fresh()
	game.schedule_meeting(int(game.inbox[0]["id"]),"cafe",60.0,24.0)
	legacy = _snapshot()
	legacy.erase("calendar_version")
	legacy["minute"] = 3400.0
	legacy["class_resolved_through"] = 2
	legacy["meetings"][0]["due_minute"] = 3740.0
	legacy["world_state"]["meeting_walks"] = [{"id":legacy["meetings"][0]["id"],"state":"approaching","position":[20.0,0.3,30.0],"target":[-67.0,0.3,-11.0],"start_minute":3680.0,"due":3740.0}]
	_write(legacy)
	_check(game.load_game(false) and game.active_meetings()[0]["due_minute"] == 3870.0 and game.world_state["meeting_walks"].is_empty(), "old accepted afternoon appointment moves after new class and drops only its stale actor walk")
	game.save_game()
	_check(game.load_game(false) and game.active_meetings()[0]["due_minute"] == 3870.0, "class schedule migration happens once without moving accepted appointment again")
	game.restart_game()
	_check(game.supplier_catalog()[0]["unlocked"] and not game.supplier_catalog()[1]["unlocked"] and game.npc_party_invites.is_empty(), "hardcore restart clears discovered access and invitations")
