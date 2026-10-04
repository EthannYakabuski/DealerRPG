extends SceneTree
## Social choices, callbacks and night scheduling use isolated deterministic state.

const State = preload("res://scripts/game_state.gd")
var game: Node
var checks: int = 0
var failures: int = 0
var reactions: Array[Dictionary] = []
var tips: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	game = State.new()
	game.save_path = "res://.godot/social-test-save.json"
	if FileAccess.file_exists(game.save_path): DirAccess.remove_absolute(game.save_path)
	root.add_child(game)
	game.set_process(false)
	game.civilian_reaction.connect(func(id: String, reaction: String): reactions.append({"id":id,"reaction":reaction}))
	game.police_tip.connect(func(location: String, severity: float): tips.append({"location":location,"severity":severity}))
	_test_street_choices()
	_test_introductions()
	_test_proactive_texting()
	_test_night_suppliers()
	_test_old_supplier_schedule()
	_test_callbacks()
	_test_long_scheduling()
	_test_optional_save_fields()
	game.queue_free()
	if FileAccess.file_exists("res://.godot/social-test-save.json"): DirAccess.remove_absolute("res://.godot/social-test-save.json")
	print("SOCIAL STATE TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SOCIAL CHECK: " + text)

func _fresh() -> void:
	game.restart_game()
	game._rng.seed = 8213
	game.split_flower()
	game.tutorial_sell()
	game.add_tutorial_contact()
	game.advance_time(90.0)
	reactions.clear()
	tips.clear()

func _street(response: String) -> String:
	for index: int in range(42):
		var id: String = "citizen_%02d" % index
		game.street_conversation(id, "Neighbour %02d" % index)
		if game.street_npcs[id]["response"] == response: return id
	return ""

func _message(contact_id: String = "milo") -> Dictionary:
	for message: Dictionary in game.inbox:
		if message["contact_id"] == contact_id and message["status"] == "new": return message
	return {}

func _test_street_choices() -> void:
	_fresh()
	var buyer: String = _street("sale")
	var refusal: String = _street("refusal")
	var reporter: String = _street("report")
	_check(not buyer.is_empty() and not refusal.is_empty() and not reporter.is_empty(), "seeded neighbourhood has buyers refusals and possible reporters")
	var view: Dictionary = game.street_conversation(buyer)
	_check(view["can_offer"] and not view.has("response") and not view.has("_informant"), "conversation does not reveal private NPC outcomes in advance")
	_check(not game.add_street_contact(buyer), "strangers do not share a number before a successful sale")
	var money: float = game.cash
	var stock: int = game.inventory["dime_bag"]
	_check(game.offer_street_sale(buyer), "interested pedestrian accepts a physical sale")
	_check(game.cash == money+22.0 and game.inventory["dime_bag"] == stock-1, "street sale transfers exactly one bag and quoted payment")
	_check(not game.offer_street_sale(buyer) and game.cash == money+22.0, "repeat button cannot duplicate a street transaction")
	_check(game.street_conversation(buyer)["can_add_contact"] and game.add_street_contact(buyer), "successful buyer can be added to contacts")
	var contact_id: String = game.street_npcs[buyer]["contact_id"]
	_check(not game.add_street_contact(buyer) and game.contacts.size() == 2, "street contacts cannot be added twice")
	_check(_message(contact_id).is_empty() and float(game._find_contact(contact_id)["next_request_minute"]) >= game.minute+360.0, "new street contact respects the fulfilled purchase cooldown")
	money = game.cash
	stock = game.inventory["dime_bag"]
	_check(not game.offer_street_sale(refusal) and game.cash == money and game.inventory["dime_bag"] == stock, "refusal consumes neither stock nor cash")
	_check(reactions.is_empty() and not game.street_conversation(refusal)["can_offer"], "a refusal has a cooldown without a police report")
	var heat_before: float = game.heat
	_check(not game.offer_street_sale(reporter) and reactions.size() == 1 and reactions[0]["reaction"] == "report", "reporting pedestrian asks the world to run to an officer")
	_check(game.heat == heat_before and tips.is_empty() and game.status == "playing", "reporter does not magically alert police or end the run before arriving")
	_check(not game.offer_street_sale(reporter) and reactions.size() == 1, "reporting outcome cannot be triggered repeatedly")
	game.save_game()
	game.load_game(false)
	_check(game.pending_civilian_reports().has(reporter) and game.street_npcs[refusal]["response"] == "refusal", "report journeys and fixed refusal outcomes survive reload")
	_check(game.civilian_report_arrived(reporter) and not game.civilian_report_arrived(reporter), "physical report can be consumed exactly once")
	_check(game.pending_civilian_reports().is_empty() and tips.is_empty(), "report completion leaves spatial police response to the world")

func _new_introduction() -> Dictionary:
	game.reputation = 2
	game._maybe_referral(game.contacts[0])
	return game.introductions.back()

func _test_introductions() -> void:
	_fresh()
	var introduction: Dictionary = _new_introduction()
	introduction["_informant"] = false
	introduction["_cover_course"] = game.contact_profile("milo")["course"]
	var id: int = int(introduction["id"])
	_check(game.contacts.size() == 1 and game.pending_introductions().size() == 1, "word of mouth produces an introduction instead of an instantly trusted contact")
	var public_intro: Dictionary = game.pending_introductions()[0]
	_check(not public_intro.has("_informant") and not public_intro.has("_cover_course"), "introduction presentation does not reveal hidden informant flags")
	_check(game.ask_introduction(id, "referrer").contains("Milo"), "player can ask who gave out their number")
	var answer: String = game.ask_introduction(id, "connection")
	_check(answer.contains(game.contact_profile("milo")["course"]) and answer.contains(game.contact_profile("milo")["hangout"]), "legitimate introduction gives details comparable to a known contact profile")
	game.save_game()
	game.load_game(false)
	_check(game.ask_introduction(id, "connection") == answer, "question answers and hidden identity remain consistent after reload")
	_check(game.resolve_introduction(id, "accept") and game.contacts.size() == 2, "explicit acceptance adds the introduced contact")
	_check(game.active_meetings().is_empty() and not _message("referral_%d" % id).is_empty(), "acceptance creates an opportunity but never books a meeting automatically")
	_check(not game.resolve_introduction(id, "accept"), "resolved introductions cannot mint duplicate contacts")
	_fresh()
	introduction = _new_introduction()
	introduction["_informant"] = true
	introduction["_cover_course"] = "chemistry"
	id = int(introduction["id"])
	_check(not game.ask_introduction(id, "connection").contains(game.contact_profile("milo")["course"]), "inconsistent cover gives the player a readable discrepancy")
	_check(game.resolve_introduction(id, "block") and game.contacts.size() == 1 and game.pending_introductions().is_empty(), "blocking an unknown number prevents their opportunity without punishment")
	_fresh()
	introduction = _new_introduction()
	_check(game.resolve_introduction(int(introduction["id"]), "decline") and game.contacts.size() == 1, "declining an introduction adds no contact or obligation")
	_fresh()
	introduction = _new_introduction()
	introduction["_informant"] = true
	introduction["_cover_course"] = game.contact_profile("milo")["course"]
	id = int(introduction["id"])
	game.resolve_introduction(id, "accept")
	var request: Dictionary = _message("referral_%d" % id)
	game.schedule_meeting(int(request["id"]), "cafe", 30.0, 22.0)
	var meeting: Dictionary = game.active_meetings()[0]
	game.advance_time(30.0)
	game.player_location_id = "cafe"
	_check(game.complete_meeting(int(meeting["id"])), "a contact with consistent cover still requires a chosen physical handoff")
	_check(tips.size() == 1 and tips[0]["location"] == "cafe" and game.status == "playing", "informant sting sends a location tip for physical police response rather than instant death")
	var money: float = game.cash
	_check(not game.complete_meeting(int(meeting["id"])) and tips.size() == 1 and game.cash == money, "sting handoff cannot duplicate money or police tips")

func _test_proactive_texting() -> void:
	_fresh()
	_check(not game.text_contact("milo"), "proactive text cannot duplicate an unanswered incoming request")
	game.advance_time(211.0)
	var normal_request_deadline: float = game.contacts[0]["next_request_minute"]
	_check(game.text_contact("milo") and game.contact_profile("milo")["last_reply"].contains("good for now"), "recent customer can politely decline a proactive text")
	var deadline: float = game.contacts[0]["next_outreach_minute"]
	_check(not game.text_contact("milo"), "outbound text cooldown prevents repeated spam")
	_check(float(game.contacts[0]["next_request_minute"]) == normal_request_deadline, "ignored outbound offer does not reset the ordinary incoming request cooldown")
	game.save_game()
	game.load_game(false)
	_check(is_equal_approx(float(game.contacts[0]["next_outreach_minute"]), deadline) and not game.text_contact("milo"), "outbound cooldown and reply survive reload")
	var discounted: Dictionary = {}
	for seed_value: int in range(1, 65):
		_fresh()
		game.schedule_meeting(int(_message()["id"]), "cafe", 30.0, 22.0)
		game.advance_time(30.0)
		game.player_location_id = "cafe"
		game.complete_meeting(int(game.active_meetings()[0]["id"]))
		game.advance_time(210.0)
		game._rng.seed = seed_value
		normal_request_deadline = game.contacts[0]["next_request_minute"]
		game.text_contact("milo")
		var candidate: Dictionary = _message()
		if candidate.has("max_price"):
			discounted = candidate
			break
	_check(not discounted.is_empty() and game.active_meetings().is_empty(), "an interested proactive reply can offer a discount without accepting a meeting")
	if discounted.is_empty(): return
	_check(game.minute < normal_request_deadline, "proactive outreach can find interest before the ordinary six-to-eight-hour demand cooldown")
	_check(not game.schedule_meeting(int(discounted["id"]), "cafe", 60.0, 24.0), "discounted customer cannot be charged more than the agreed offer")
	_check(game.schedule_meeting(int(discounted["id"]), "cafe", 60.0, 20.0), "player can explicitly accept and schedule the discounted opportunity")

func _test_night_suppliers() -> void:
	for case: Array in [[600.0,1320.0],[1390.0,1450.0],[1490.0,1550.0],[1501.0,2760.0]]:
		_fresh()
		game.minute = case[0]
		game.cash = 1000.0
		_check(game.supplier_order(0,1) and game.active_meetings()[0]["due_minute"] == case[1], "supplier chooses next legal night slot from minute %.0f" % case[0])
	_fresh()
	game.minute = 840.0
	game.cash = 1000.0
	game.schedule_meeting(int(_message()["id"]), "cafe", 480.0, 22.0)
	game.supplier_order(0,1)
	var supplier: Dictionary
	for meeting: Dictionary in game.active_meetings():
		if meeting["type"] == "supplier": supplier = meeting
	_check(supplier["due_minute"] == 1350.0, "night pickup leaves thirty minutes after an existing appointment")
	_fresh()
	game.cash = 1000.0
	game.supplier_order(0,1)
	supplier = game.active_meetings()[0]
	game.player_location_id = str(supplier["location_id"])
	game.advance_time(float(supplier["due_minute"])-16.0-game.minute)
	_check(not game.complete_meeting(int(supplier["id"])) and game.cash == 1000.0, "supplier handoff remains blocked more than fifteen minutes before its appointment")
	game.advance_time(1.0)
	_check(game.complete_meeting(int(supplier["id"])) and game.cash == 954.0, "present supplier can trade fifteen minutes early even before22:00 opening")

func _test_old_supplier_schedule() -> void:
	_fresh()
	game.cash = 1000.0
	game.supplier_order(0,1)
	var supplier_id: int = int(game.active_meetings()[0]["id"])
	game.save_game()
	var old_save: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(game.save_path))
	old_save["meetings"][0]["due_minute"] = 900.0
	old_save["world_state"]["meeting_walks"] = [{"id":supplier_id,"position":[20.0,0.2,50.0],"target":[22.0,0.2,52.0],"state":"approaching","start_minute":800.0,"due":900.0},{"id":999,"position":[21.0,0.2,50.0],"target":[22.0,0.2,52.0],"state":"approaching","start_minute":800.0,"due":950.0}]
	_write_save(old_save)
	_check(game.load_game(false) and game.active_meetings()[0]["due_minute"] == 1320.0, "legacy daytime supplier appointment migrates to the next legal night")
	_check(game.cash == 1000.0 and game.inventory["flower"] == 0 and game.inventory["dime_bag"] == 6, "supplier migration preserves all cash and stock")
	_check(game.world_state["meeting_walks"].size() == 1 and int(game.world_state["meeting_walks"][0]["id"]) == 999, "supplier migration removes only the rescheduled actor's stale walk")
	game.save_game()
	game.load_game(false)
	_check(game.active_meetings()[0]["due_minute"] == 1320.0, "migrated night appointment stays stable on repeated reload")
	old_save = JSON.parse_string(FileAccess.get_file_as_string(game.save_path))
	old_save["minute"] = 1450.0
	_write_save(old_save)
	_check(game.load_game(false) and game.meetings[0]["due_minute"] == 1320.0, "overdue valid night appointment is not given a free migration retry")
	game.advance_time(1.0)
	_check(game.meetings[0]["status"] == "missed", "overdue restored night appointment expires by ordinary rules")

func _test_callbacks() -> void:
	_fresh()
	game.schedule_meeting(int(_message()["id"]), "cafe", 30.0, 22.0)
	var meeting: Dictionary = game.active_meetings()[0]
	_check(not game.postpone_meeting(int(meeting["id"])), "phone cannot invoke in-person postponement before arriving")
	game.player_location_id = "cafe"
	game.advance_time(30.0)
	var relationship: float = game.contacts[0]["relationship"]
	var cash_before: float = game.cash
	_check(game.postpone_meeting(int(meeting["id"])), "in-person meeting can be postponed")
	_check(game.active_meetings().is_empty() and game.contacts[0]["relationship"] == relationship and game.cash == cash_before, "polite postponement removes the obligation without loss or a transaction")
	_check(not game.postpone_meeting(int(meeting["id"])) and game.callbacks.size() == 1, "repeated postponement cannot duplicate callbacks")
	game.advance_time(119.0)
	_check(_message().is_empty(), "postponed customer waits the promised couple of hours")
	game.save_game()
	game.load_game(false)
	game.advance_time(1.0)
	_check(not _message().is_empty() and game.active_meetings().is_empty(), "persisted callback becomes a new opportunity rather than an automatic appointment")
	_fresh()
	var request: Dictionary = _message()
	_check(game.request_tomorrow(int(request["id"])) and game.callbacks[0]["due_minute"] == 1980.0, "hit-me-up-tomorrow schedules next-day09:00 business-hours callback")
	_check(not game.request_tomorrow(int(request["id"])), "tomorrow request cannot be duplicated")
	game.save_game()
	game.load_game(false)
	game.advance_time(1979.0-game.minute)
	_check(_message().is_empty(), "deferred customer does not send another same-day request")
	game.advance_time(1.0)
	_check(not _message().is_empty() and game.callbacks[0]["status"] == "delivered", "tomorrow callback fires once after save/reload")
	_fresh()
	game.minute = 1440.0
	game.cash = 1000.0
	game.supplier_order(0,1)
	meeting = game.active_meetings()[0]
	game.advance_time(60.0)
	game.player_location_id = str(meeting["location_id"])
	_check(game.postpone_meeting(int(meeting["id"])) and game.callbacks[0]["due_minute"] == 2760.0, "late supplier postponement waits for the next night window")
	_check(not game.supplier_order(0,1), "pending supplier callback prevents duplicate simultaneous orders")
	game.save_game()
	game.load_game(false)
	_check(game.callbacks[0]["due_minute"] == 2760.0 and game.active_meetings().is_empty(), "midnight supplier postponement keeps its next-night callback across reload")
	game.advance_time(2760.0-game.minute)
	request = _message("supplier_0")
	_check(not request.is_empty() and request["type"] == "supplier_callback" and game.active_meetings().is_empty(), "supplier callback invites explicit confirmation")
	game.save_game()
	game.load_game(false)
	_check(_message("supplier_0").get("type") == "supplier_callback", "delivered supplier opportunity also survives JSON validation and reload")
	_check(game.accept_supplier_callback(int(request["id"])) and game.active_meetings()[0]["due_minute"] == 2820.0, "accepting supplier callback chooses a fresh legal night appointment")
	_check(not game.accept_supplier_callback(int(request["id"])), "supplier callback can only be accepted once")

func _test_long_scheduling() -> void:
	_fresh()
	_check(not game.schedule_meeting(int(_message()["id"]), "cafe", 481.0, 22.0), "client horizon cannot exceed eight hours")
	_check(game.schedule_meeting(int(_message()["id"]), "cafe", 480.0, 22.0), "client accepts an eight-hour planning horizon")
	_fresh()
	game.minute = 1200.0
	game.inbox[0]["expires_minute"] = 1600.0
	_check(game.schedule_meeting(int(_message()["id"]), "cafe", 480.0, 22.0) and game.active_meetings()[0]["due_minute"] == 1680.0, "long client meeting keeps the correct absolute time across midnight")
	_fresh()
	game.minute = 1500.0
	game.inbox[0]["expires_minute"] = 1900.0
	_check(not game.schedule_meeting(int(_message()["id"]), "cafe", 480.0, 22.0), "eight-hour scheduling still rejects next-day class conflict")

func _write_save(state: Dictionary) -> void:
	var file := FileAccess.open(game.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(state))
	file.close()

func _test_optional_save_fields() -> void:
	_fresh()
	_new_introduction()
	var reporter: String = _street("report")
	game.offer_street_sale(reporter)
	game.request_tomorrow(int(_message()["id"]))
	game.world_state["informant_runs"] = [{"id":reporter,"position":[20.0,0.2,50.0],"report_position":[18.0,0.3,49.0],"campus":true}]
	game.save_game()
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(game.save_path))
	_check(game.load_game(false) and game.pending_introductions().size() == 1 and game.callbacks.size() == 1 and game.pending_civilian_reports().has(reporter), "new social state restores consistently in the existing save version")
	_check(game.world_state["informant_runs"].size() == 1, "pending physical report position persists alongside the campaign")
	var damaged: Dictionary = saved.duplicate(true)
	damaged["introductions"][0]["_informant"] = "yes"
	_write_save(damaged)
	_check(not game.load_game(false), "malformed introduction identity is rejected before applying save")
	damaged = saved.duplicate(true)
	damaged["callbacks"][0]["due_minute"] = -20.0
	_write_save(damaged)
	_check(not game.load_game(false), "malformed callback timing is rejected")
	damaged = saved.duplicate(true)
	damaged["street_npcs"][reporter]["response"] = "unknown"
	_write_save(damaged)
	_check(not game.load_game(false), "malformed pedestrian outcome is rejected")
	damaged = saved.duplicate(true)
	var invalid_run: Dictionary = damaged["world_state"]["informant_runs"][0].duplicate(true)
	invalid_run["id"] = "citizen_99"
	damaged["world_state"]["informant_runs"].append(invalid_run)
	_write_save(damaged)
	_check(game.load_game(false) and game.world_state["informant_runs"].size() == 1, "invalid optional reporter is skipped while preserving the valid route")
	for field: String in ["introductions", "callbacks", "street_npcs"]: saved.erase(field)
	saved["world_state"].erase("informant_runs")
	_write_save(saved)
	_check(game.load_game(false) and game.introductions.is_empty() and game.callbacks.is_empty() and game.street_npcs.is_empty(), "older saves remain compatible without new optional social fields")
