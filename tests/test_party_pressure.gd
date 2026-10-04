extends SceneTree
## Focused state regressions; no player save is read or modified.

const State = preload("res://scripts/game_state.gd")
var game: Node
var checks: int = 0
var failures: int = 0
var events: Array[Dictionary] = []
var emotions: Array[Dictionary] = []
var missed: Array[int] = []
var fixture_id: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	game = State.new()
	game.save_path = "res://.godot/party-pressure-test-save.json"
	if FileAccess.file_exists(game.save_path): DirAccess.remove_absolute(game.save_path)
	root.add_child(game)
	game.set_process(false)
	game.feedback_event.connect(func(kind: String, value: float): events.append({"kind":kind,"value":value}))
	game.street_reaction.connect(func(id: String, kind: String): emotions.append({"id":id,"kind":kind}))
	game.meeting_reaction.connect(func(id: int, kind: String): emotions.append({"id":id,"kind":kind}))
	game.party_reaction.connect(func(id: String, kind: String): emotions.append({"id":id,"kind":kind}))
	game.meeting_missed.connect(func(id: int, _contact: String): missed.append(id))
	_test_party()
	_test_party_windows()
	_test_party_scheduling()
	_test_pressure()
	_test_reactions()
	_test_save_compatibility()
	game.queue_free()
	if FileAccess.file_exists("res://.godot/party-pressure-test-save.json"): DirAccess.remove_absolute("res://.godot/party-pressure-test-save.json")
	print("PARTY / PRESSURE TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PARTY / PRESSURE CHECK: " + description)

func _fresh() -> void:
	game.restart_game()
	game._rng.seed = 50013
	game.split_flower()
	game.tutorial_sell()
	game.add_tutorial_contact()
	events.clear()
	emotions.clear()
	missed.clear()

func _party_fixture() -> void:
	_fresh()
	game.minute = 1020.0
	game.cash = 100.0
	game.reputation = 5
	game.player_location_id = "home"
	for index: int in range(1, 10): game._add_contact("guest_%d" % index, "Guest %d" % index, 45.0)

func _test_party() -> void:
	_party_fixture()
	var stock: int = game.inventory["dime_bag"]
	var relationship: float = game.contacts[0]["relationship"]
	_check(game.host_party(), "17:00 party opens with supplies")
	_check(game.cash == 75.0 and game.minute == 1020.0 and game.inventory["dime_bag"] == stock and game.reputation == 5, "hosting has no time skip, automatic sales, stock change or reputation award")
	_check(game.party_summary()["active"] and game.party_summary()["end_minute"] == 1200.0, "party remains active for three campaign hours")
	_check(events.size() == 1 and events[0]["kind"] == "purchase" and events[0]["value"] == -25.0, "only a supplies purchase cue fires on hosting")
	_check(not game.invite_party_contact("stranger") and game.invite_party_contact("milo"), "invitations require known contacts")
	_check(not game.invite_party_contact("milo") and not game.mark_party_guest_arrived("milo"), "duplicate invitations and premature arrivals cannot farm relationships")
	_check(not game.sell_party_guest("milo") and not game.chat_party_guest("milo"), "guests must physically arrive before chat or sales")
	for index: int in range(1, 8):
		_check(game.invite_party_contact("guest_%d" % index), "known guest %d can be invited" % index)
	_check(not game.invite_party_contact("guest_8") and game.party_summary()["guest_count"] == 8, "party invitation roster caps at eight")
	var before_cash: float = game.cash
	var arrive: float = game.party_summary()["guests"][0]["arrival_minute"]
	game.advance_time(arrive - game.minute)
	_check(game.cash == before_cash and game.inventory["dime_bag"] == stock, "waiting for guests never sells stock")
	_check(game.mark_party_guest_arrived("milo") and game.contacts[0]["relationship"] == relationship + 2.0, "physical arrival awards relationship once")
	_check(not game.mark_party_guest_arrived("milo") and game.contacts[0]["relationship"] == relationship + 2.0, "repeated arrival cannot award relationship twice")
	game.player_location_id = "market"
	_check(not game.sell_party_guest("milo") and not game.chat_party_guest("milo"), "guest interaction requires the player at home")
	game.player_location_id = "home"
	_check(game.chat_party_guest("milo") and not game.chat_party_guest("milo") and game.contacts[0]["relationship"] == relationship + 5.0, "catching up awards relationship only once per party")
	_check(game.sell_party_guest("milo") and game.cash == before_cash + 24.0 and game.inventory["dime_bag"] == stock - 1, "explicit guest sale transfers one bag for exactly $24")
	_check(not game.sell_party_guest("milo") and not game.party_guest_view("milo")["can_offer"], "one guest purchase cannot duplicate")
	_check(game.contacts[0]["next_request_minute"] >= game.minute + 360.0, "party purchase retains ordinary customer cooldown")
	_check(not game._contact_can_request(game.contacts[1]), "invited guests do not text new errands while attending")
	game.save_game()
	var cash_saved: float = game.cash
	emotions.clear()
	events.clear()
	_check(game.load_game(false) and game.party_summary()["active"], "active party survives save and reload")
	_check(not game.chat_party_guest("milo") and not game.sell_party_guest("milo") and game.cash == cash_saved and emotions.is_empty() and events.is_empty(), "reload cannot replay party awards or transaction cues")
	game.advance_time(float(game.party_summary()["end_minute"]) - game.minute)
	_check(not game.party_summary()["active"] and game.party_summary()["guests"][0]["status"] == "left", "closing resolves invitations and lets world actors depart")
	_check(game.cash == cash_saved and not game.mark_party_guest_arrived("guest_1"), "unserved guests do not buy or grant arrival bonuses after closing")
	_check(not game.host_party(), "one party per night even after first party ends")

func _test_party_windows() -> void:
	_party_fixture()
	game.minute = 1019.0
	_check(not game.host_party() and game.cash == 100.0, "party cannot begin before 17:00")
	game.minute = 1430.0
	game.inventory["dime_bag"] = 0
	_check(game.host_party() and game.party_summary()["end_minute"] == 1560.0, "late-night party caps at 02:00 and does not require product")
	game.minute = 1450.0
	_check(not game.host_party(), "midnight does not reset party night limit")
	_party_fixture()
	game.minute = 1450.0
	_check(game.host_party() and game.party_summary()["end_minute"] == 1560.0, "new party can start after midnight and closes at 02:00")
	game.save_game()
	_check(game.load_game(false) and game.active_party["night_day"] == 1, "after-midnight party night identity persists")
	_party_fixture()
	game.minute = 1560.0
	_check(not game.host_party(), "02:00 is the exclusive party closing boundary")
	game.minute = 1545.0
	_check(not game.host_party() and game.cash == 100.0, "too little time to invite guests does not charge supplies")

func _test_party_scheduling() -> void:
	_party_fixture()
	game._create_request(game._find_contact("guest_1"))
	var message: Dictionary = game.inbox.back()
	game.host_party()
	game.invite_party_contact("guest_1")
	_check(not game.schedule_meeting(int(message["id"]), "cafe", 90.0, 24.0) and game.active_meetings().is_empty() and message["status"] == "new", "an old text cannot duplicate an invited guest at a simultaneous meeting")
	_check(not game.schedule_meeting(int(message["id"]), "cafe", 195.0, 24.0), "meeting needs more than fifteen minutes after party closing for departure")
	_check(game.schedule_meeting(int(message["id"]), "cafe", 420.0, 24.0), "party invitation does not prevent a later next-day appointment")
	game.invite_party_contact("guest_2")
	var count: int = game.inbox.size()
	var guest: Dictionary = game._find_contact("guest_2")
	var outreach_before: float = guest.get("next_outreach_minute", 0.0)
	_check(not game.text_contact("guest_2") and not game._create_request(guest) and game.inbox.size() == count and guest.get("next_outreach_minute", 0.0) == outreach_before, "party guests generate neither outreach nor unsolicited requests, without consuming outreach cooldown")
	_party_fixture()
	game._create_request(game._find_contact("guest_1"))
	message = game.inbox.back()
	game.schedule_meeting(int(message["id"]), "cafe", 190.0, 24.0)
	game.host_party()
	_check(not game.invite_party_contact("guest_1"), "existing appointment in party departure buffer also prevents an invitation")

func _appointment(location_id: String, complete: bool = true) -> Dictionary:
	fixture_id += 1
	var contact_id: String = "appointment_%d" % fixture_id
	game._add_contact(contact_id, "Classmate %d" % fixture_id, 45.0)
	game._create_request(game._find_contact(contact_id))
	var message: Dictionary = game.inbox.back()
	game.schedule_meeting(int(message["id"]), location_id, 35.0, 24.0)
	var meeting: Dictionary = game.active_meetings().back()
	if complete:
		game.inventory["dime_bag"] = 20
		game.advance_time(float(meeting["due_minute"]) - game.minute)
		game.player_location_id = location_id
		_check(game.complete_meeting(int(meeting["id"])), "fixture completes an actual customer appointment")
	return meeting

func _test_pressure() -> void:
	_fresh()
	var first: Dictionary = _appointment("cafe")
	_check(game.police_pressure_locations().is_empty(), "one completed meeting creates no hotspot")
	_check(not game.complete_meeting(int(first["id"])) and game.consecutive_location_meetings == 1, "duplicate transaction cannot increase location streak")
	_appointment("cafe")
	var area: Dictionary = game.police_pressure_locations()[0]
	_check(area["watch_level"] == 1 and area["strength"] == 1, "second consecutive meeting draws one additional patrol")
	var deadline: float = area["expires_minute"]
	_appointment("cafe")
	area = game.police_pressure_locations()[0]
	_check(area["watch_level"] == 2 and area["strength"] == 2 and area["expires_minute"] == deadline, "third meeting creates heavy watch without resetting quiet-area expiry")
	_appointment("market")
	_check(game.last_meeting_location == "market" and game.consecutive_location_meetings == 1, "using another location breaks consecutive-use streak")
	_appointment("cafe")
	_check(game.consecutive_location_meetings == 1 and game.police_pressure_locations()[0]["watch_level"] == 2, "returning starts a new streak while existing watch remains")
	var durations: Array[float] = [10.0,10.0,15.0,20.0,25.0,30.0,40.0,50.0]
	for expected: float in durations:
		game.register_pursuit("cafe")
		_check(game.escape_duration_seconds() == expected, "new pursuit raises escape requirement to %.0f seconds" % expected)
	_check(game.police_pressure_locations()[0]["strength"] == 4 and game.police_pressure_locations()[0]["incident_count"] == 8, "visible officers cap while incident risk keeps accumulating")
	game.register_pursuit("moon")
	_check(game.pursuit_incidents == 8, "invalid location cannot increase pursuit requirements")
	game.save_game()
	var expires: float = game.police_pressure_locations()[0]["expires_minute"]
	_check(game.load_game(false) and game.pursuit_incidents == 8 and game.escape_duration_seconds() == 50.0 and game.police_pressure_locations()[0]["expires_minute"] == expires, "hotspot and global escape escalation survive reload")
	game.minute = expires - 1.0
	game._expire_police_pressure()
	_check(not game.police_pressure_locations().is_empty(), "local reinforcement lasts the entire quiet day")
	game.register_pursuit("cafe")
	_check(game.police_pressure_locations()[0]["expires_minute"] == game.minute + 1440.0 and game.escape_duration_seconds() == 30.0, "new bust refreshes local deadline and uses the two-step daily recovery")
	game.minute += 1440.0
	game._expire_police_pressure()
	_check(game.police_pressure_locations().is_empty() and game.last_meeting_location == "" and game.escape_duration_seconds() == 30.0, "quiet-day expiry removes local patrols but does not shorten an active pursuit")
	game.end_pursuit()
	_check(game.escape_duration_seconds() == 20.0 and game.pursuit_incidents == 9, "ending pursuit exposes recovered daily tier while lifetime incidents remain recorded")

func _test_reactions() -> void:
	_fresh()
	var meeting: Dictionary = _appointment("cafe", false)
	game.advance_time(float(meeting["due_minute"]) + 50.0 - game.minute)
	_check(missed.size() == 1 and missed[0] == int(meeting["id"]) and emotions.back()["kind"] == "angry", "missed appointment emits one physical departure cue and angry emotion")
	game.advance_time(60.0)
	_check(missed.size() == 1, "missed meeting cue cannot repeat every clock tick")
	_fresh()
	game.street_conversation("citizen_56", "Neighbour")
	var first: String = game.street_smalltalk("citizen_56", "study")
	var second: String = game.street_smalltalk("citizen_56", "study")
	_check(first != second and game.street_conversation("citizen_56")["text"] == second, "smalltalk varies across conversations and remembers the latest reply")
	game.street_npcs["citizen_56"]["talk_count"] = 0
	game.street_npcs["citizen_56"]["response"] = "refusal"
	_check(game.street_smalltalk("citizen_56", "party") == first, "same voice is independent of private purchase outcome and activity stereotype")
	_check(not game.offer_street_sale("citizen_56") and emotions.back()["kind"] == "sad", "refusal supplies a readable emotion without automatic police")
	game.save_game()
	var count: int = game.street_npcs["citizen_56"]["talk_count"]
	_check(game.load_game(false) and game.street_npcs["citizen_56"]["talk_count"] == count, "conversation progression and outcome persist")

func _saved() -> Dictionary:
	game.save_game()
	return JSON.parse_string(FileAccess.get_file_as_string(game.save_path))

func _write(state: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(game.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(state))
	file.close()

func _test_save_compatibility() -> void:
	_party_fixture()
	game.host_party()
	game.invite_party_contact("milo")
	game.world_state = {"position":[600.0,0.3,0.0],"interior":"home","party_walks":[
		{"contact_id":"milo","state":"inside","position":[601.0,0.3,2.0],"slot":0},
		{"contact_id":"guest_1","state":"approaching","position":[-22.0,0.3,30.0],"slot":1},
		{"contact_id":"guest_2","state":"inside","position":[800.0,0.3,0.0],"slot":2},
		{"contact_id":"guest_3","state":"approaching","position":[600.0,0.3,0.0],"slot":3},
		{"contact_id":"milo","state":"inside","position":[600.0,0.3,0.0],"slot":4}
	],"informant_runs":[{"id":"citizen_56","position":[0.0,0.3,0.0],"report_position":[20.0,0.3,10.0],"campus":true}]}
	var valid: Dictionary = _saved()
	_check(game.load_game(false) and game.world_state["party_walks"].size() == 2, "party actor sanitizer retains valid room/exterior actors and skips wrong-room duplicates")
	_check(game.world_state["informant_runs"].size() == 1, "new civilian fifty-seven retains a pending physical report across reload")
	var pursuit: Dictionary = {"officers":[],"arrest_seconds":0.5,"escape_seconds":90.0,"crime_age":2.0,"crime_position":[10.0,0.3,20.0]}
	for index: int in range(10): pursuit["officers"].append({"position":[float(index),0.3,0.0],"hp":100.0,"alert":8.0,"stun":0.0,"index":index})
	_check(game._sanitize_pursuit_state(pursuit).get("officers", []).size() == 10, "expanded base patrol roster and longer escape progress can be restored")
	pursuit["officers"].resize(7)
	_check(game._sanitize_pursuit_state(pursuit).get("officers", []).size() == 7, "legacy seven-officer saves remain readable")
	pursuit["officers"].resize(6)
	_check(game._sanitize_pursuit_state(pursuit).is_empty(), "partial malformed base patrol roster is not restored")
	var corrupt: Dictionary = valid.duplicate(true)
	corrupt["active_party"]["guests"].append(corrupt["active_party"]["guests"][0].duplicate(true))
	_write(corrupt)
	var cash_before: float = game.cash
	_check(not game.load_game(false) and game.cash == cash_before, "duplicate guest save is rejected before changing the running campaign")
	corrupt = valid.duplicate(true)
	corrupt["active_party"]["end_minute"] = 2000.0
	_write(corrupt)
	_check(not game.load_game(false), "invalid party duration or overnight closing cannot load")
	corrupt = valid.duplicate(true)
	corrupt["police_pressure"] = {"cafe":{"watch_level":2,"incident_count":1.5,"last_bust_minute":game.minute,"expires_minute":game.minute+1440.0}}
	_write(corrupt)
	_check(not game.load_game(false), "fractional incident counts are rejected")
	corrupt = valid.duplicate(true)
	corrupt["pursuit_incidents"] = "many"
	_write(corrupt)
	_check(not game.load_game(false), "invalid global incident counter is rejected")
	var expired: Dictionary = valid.duplicate(true)
	expired["minute"] = expired["active_party"]["end_minute"]
	expired["police_pressure"] = {"home":{"watch_level":2,"incident_count":1,"last_bust_minute":600.0,"expires_minute":1100.0}}
	expired["pursuit_incidents"] = 3
	for field: String in ["pursuit_step","pursuit_decay_day","pursuit_decay_pending","active_pursuit_escape_seconds"]: expired.erase(field)
	_write(expired)
	events.clear()
	emotions.clear()
	_check(game.load_game(false) and not game.party_summary()["active"] and game.party_summary()["guests"][0]["status"] == "left" and game.police_pressure_locations().is_empty(), "resume cleans already-expired party and patrol state")
	_check(game.escape_duration_seconds() == 15.0 and events.is_empty() and emotions.is_empty(), "expiry migration preserves global risk and replays no sounds or awards")
	var legacy: Dictionary = valid.duplicate(true)
	for field: String in ["active_party","police_pressure","pursuit_incidents","last_meeting_location","consecutive_location_meetings"]: legacy.erase(field)
	_write(legacy)
	_check(game.load_game(false) and not game.party_summary()["active"] and game.police_pressure_locations().is_empty() and game.escape_duration_seconds() == 10.0, "older saves initialize optional live-party and enforcement state safely")
	game.register_pursuit("home")
	game.restart_game()
	_check(game.pursuit_incidents == 0 and game.active_party.is_empty() and game.police_pressure.is_empty(), "hardcore restart clears party and enforcement history")
