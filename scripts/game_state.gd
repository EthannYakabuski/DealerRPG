extends Node
## Authoritative campaign state. World code is responsible for physical proximity
## and police movement; these methods enforce economic and scheduling rules.

signal changed
signal notification(text: String)
signal ended(won: bool, reason: String)
signal crime_committed(severity: float)
signal feedback_event(kind: String, value: float)
signal civilian_reaction(npc_id: String, reaction: String)
signal police_tip(location_id: String, severity: float)
signal street_reaction(npc_id: String, kind: String)
signal meeting_reaction(meeting_id: int, kind: String)
signal party_reaction(contact_id: String, kind: String)
signal meeting_missed(meeting_id: int, contact_id: String)
signal police_pressure_changed

const Data = preload("res://scripts/game_data.gd")
const TIME_SCALE: float = 3.0
const MINUTES_PER_DAY: float = 1440.0
const MEETING_WINDOW: float = 25.0
const MEETING_ARRIVAL_MINUTES: float = 12.0
const CLASS_START: float = 540.0
const CLASS_DEADLINE: float = 600.0
const CLASS_END: float = 660.0
const VEHICLE_PRICE: float = 900.0
const FIRST_FOLLOWUP_MINUTES: float = 90.0
const REORDER_MINUTES: float = 360.0
const REQUEST_RETRY_MINUTES: float = 240.0
const MAX_EXTRA_OFFICERS_PER_AREA: int = 4
const MAX_VISIBLE_EXTRA_OFFICERS: int = 8
const SUPPLIER_COOLDOWN: float = 2880.0

var cash: float = 22.0
var tuition_remaining: float = Data.STARTING_TUITION
var health: float = 100.0
var hunger: float = 85.0
var energy: float = 100.0
var heat: float = 0.0
var reputation: int = 0
var minute: float = 600.0
var tutorial_step: int = 0
var inventory: Dictionary = {}
var contacts: Array[Dictionary] = []
var inbox: Array[Dictionary] = []
var meetings: Array[Dictionary] = []
var introductions: Array[Dictionary] = []
var callbacks: Array[Dictionary] = []
var street_npcs: Dictionary = {}
var active_party: Dictionary = {}
var supplier_progress: Array[Dictionary] = []
var npc_party_invites: Array[Dictionary] = []
var last_party_invite_day: int = 0
var police_pressure: Dictionary = {}
var pursuit_incidents: int = 0
var last_meeting_location: String = ""
var consecutive_location_meetings: int = 0
var status: String = "playing"
var ending_reason: String = ""
var missed_classes: int = 0
var player_location_id: String = "campus_quad"
var paused: bool = false
var vehicle_owned: bool = false
var flower_quality: float = 0.76
var dime_quality: float = 0.76
var total_sales: int = 0
var total_earned: float = 0.0
var classes_attended: int = 1
var parties_hosted: int = 0
var last_party_day: int = 0
var save_path: String = "user://deerfield_save_v2.json"
var last_error: String = ""
var world_state: Dictionary = {"position": [20.0,0.3,50.0], "interior": ""}
var _next_id: int = 1
var _class_resolved_through: int = 1
var _next_message_minute: float = 620.0
var _autosave_seconds: float = 0.0
var _dirty: bool = false
var _low_food_warned: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	restart_game(false)
	if FileAccess.file_exists(save_path):
		load_game(false)

func _process(delta: float) -> void:
	if paused or status != "playing":
		return
	if tutorial_step >= 3:
		advance_time(delta * TIME_SCALE)
	_autosave_seconds += delta
	if _dirty and _autosave_seconds >= 20.0:
		save_game()

func restart_game(delete_save: bool = true) -> void:
	cash = 22.0
	tuition_remaining = Data.STARTING_TUITION
	health = 100.0
	hunger = 85.0
	energy = 100.0
	heat = 0.0
	reputation = 0
	minute = 600.0
	tutorial_step = 0
	inventory = {"flower": 1, "dime_bag": 0, "sandwich": 1, "energy_drink": 1, "skateboard": 1, "pistol": 0, "ammo": 0}
	contacts.clear()
	inbox.clear()
	meetings.clear()
	introductions.clear()
	callbacks.clear()
	street_npcs.clear()
	active_party.clear()
	supplier_progress.clear()
	for tier: int in range(3): supplier_progress.append(_supplier_defaults(tier))
	npc_party_invites.clear()
	last_party_invite_day = 0
	police_pressure.clear()
	pursuit_incidents = 0
	last_meeting_location = ""
	consecutive_location_meetings = 0
	status = "playing"
	ending_reason = ""
	missed_classes = 0
	player_location_id = "campus_quad"
	paused = false
	vehicle_owned = false
	flower_quality = 0.76
	dime_quality = 0.76
	total_sales = 0
	total_earned = 0.0
	classes_attended = 1
	parties_hosted = 0
	last_party_day = 0
	_next_id = 1
	_class_resolved_through = 1
	_next_message_minute = 620.0
	_autosave_seconds = 0.0
	_low_food_warned = false
	last_error = ""
	world_state = {"position": [20.0,0.3,50.0], "interior": ""}
	if delete_save and FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	_mark_changed()

func day_number() -> int:
	return int(floor(minute / MINUTES_PER_DAY)) + 1

func time_text() -> String:
	return format_minute(minute)

func format_minute(value: float) -> String:
	var time_of_day: int = int(floor(value)) % 1440
	return "%02d:%02d" % [time_of_day / 60, time_of_day % 60]

func current_phase() -> String:
	var hour: float = fmod(minute, MINUTES_PER_DAY) / 60.0
	if hour >= 6.0 and hour < 11.0:
		return "Morning"
	if hour >= 11.0 and hour < 17.0:
		return "Afternoon"
	if hour >= 17.0 and hour < 20.0:
		return "Evening"
	if hour >= 20.0 and hour < 22.0:
		return "Dusk"
	return "Night"

func next_class_minute() -> float:
	var unresolved_day: int = maxi(day_number(), _class_resolved_through + 1)
	return float(class_schedule(unresolved_day)["start_minute"])

func class_schedule(day: int = -1) -> Dictionary:
	var target_day: int = day_number() if day < 1 else day
	var start: float = float(target_day - 1) * MINUTES_PER_DAY + (840.0 if target_day % 3 == 0 else CLASS_START)
	return {"day": target_day, "start_minute": start, "latest_arrival_minute": start + 60.0, "end_minute": start + 120.0}

func current_objective() -> String:
	if status == "won":
		return "Tuition paid. A future of your own."
	if status == "lost":
		return ending_reason
	match tutorial_step:
		0: return "Milo is waiting outside class. Open your backpack [I] and split your flower bundle."
		1: return "Walk up to Milo and press [E] to make your first sale."
		2: return "Open your phone [P] and save Milo as a contact."
	if total_sales == 1 and inbox.is_empty():
		return "Milo will text later. Explore campus or grab groceries while you wait."
	return "Read your texts, choose your meetings, and pay off $%d in tuition." % int(ceil(tuition_remaining))

func available_locations() -> Array[Dictionary]:
	var locations: Array[Dictionary] = []
	for location: Dictionary in Data.LOCATIONS:
		if not bool(location.get("supplier_only", false)) and not bool(location.get("party_only", false)): locations.append(location.duplicate(true))
	return locations

func supplier_catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = Data.SUPPLIERS.duplicate(true)
	for entry: Dictionary in result:
		var progress: Dictionary = supplier_progress[int(entry["tier"])]
		entry["unlocked"] = progress["unlocked"]
		entry["next_available_minute"] = progress["next_order_minute"]
		entry["successful_meetings"] = progress["successful_meetings"]
		entry["location_id"] = Data.SUPPLIER_SITES[posmod(int(entry["tier"]) + int(progress.get("orders_placed", 0)), Data.SUPPLIER_SITES.size())]
		entry["next_pickup_minute"] = supplier_pickup_minute(int(entry["tier"]), maxf(minute, float(progress["next_order_minute"])) + 60.0)
		entry["can_order"] = status == "playing" and tutorial_step >= 3 and bool(progress["unlocked"]) and minute >= float(progress["next_order_minute"])
		entry["discovery_hint"] = "Your first connection." if int(entry["tier"]) == 0 else ("Meet Sable at a party or at Freight lane between 22:00 and 02:00." if int(entry["tier"]) == 1 else "Complete three pickups with Sable for a personal introduction at the East trail shelter.")
	return result

func _supplier_defaults(tier: int) -> Dictionary:
	return {"unlocked": tier == 0, "next_order_minute": 0.0, "successful_meetings": 0, "orders_placed": 0, "referral_received": false, "interview_stage": 0, "retry_minute": 0.0}

func pending_supplier_introductions() -> Array[Dictionary]:
	if not bool(supplier_progress[2]["referral_received"]) or bool(supplier_progress[2]["unlocked"]): return []
	return [{"id":"supplier_2", "name":"Sable's referral", "text":"Sable: Three completed pickups earned you an introduction. Meet the Regent at the East trail shelter between 22:00 and 02:00. Say Sable sent you, and remember those three completed pickups. Listen before promising anything.", "location_id":"east_trail"}]

func supplier_encounters() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var hour: float = fmod(minute, MINUTES_PER_DAY)
	if status != "playing" or tutorial_step < 3 or (hour >= 120.0 and hour < 1320.0): return result
	for tier: int in [1, 2]:
		var progress: Dictionary = supplier_progress[tier]
		if bool(progress["unlocked"]) or minute < float(progress["retry_minute"]): continue
		if tier == 2 and not bool(progress["referral_received"]): continue
		if tier == 1 and bool(party_summary()["active"]) and not _party_guest("supplier_1").is_empty(): continue
		result.append({"id": "supplier_%d" % tier, "tier": tier, "name": Data.SUPPLIERS[tier]["name"], "location_id": Data.SUPPLIERS[tier]["location_id"], "active": true, "kind": "introduction" if tier == 1 else "interview"})
	return result

func supplier_encounter_view(encounter_id: String) -> Dictionary:
	if encounter_id not in ["supplier_1", "supplier_2"]: return {}
	var tier: int = 1 if encounter_id == "supplier_1" else 2
	var progress: Dictionary = supplier_progress[tier]
	var view: Dictionary = {"id": encounter_id, "tier": tier, "name": Data.SUPPLIERS[tier]["name"], "location_id": Data.SUPPLIERS[tier]["location_id"], "complete": bool(progress["unlocked"]), "retry_minute": float(progress["retry_minute"]), "choices": [], "text": ""}
	if bool(progress["unlocked"]): view["text"] = "We've exchanged numbers. Call when you need a pickup; I need two days between new orders."
	elif minute < float(progress["retry_minute"]): view["text"] = "Let's talk another night. Come back after day %d, %s." % [int(float(progress["retry_minute"]) / MINUTES_PER_DAY) + 1, format_minute(float(progress["retry_minute"]))]
	elif tier == 1:
		view["text"] = "I'm Sable. I work with people who keep their word. Introduce yourself and we can exchange numbers."
		view["choices"] = [{"id":"introduce","label":"Introduce yourself and exchange numbers"}]
	elif not bool(progress["referral_received"]): view["text"] = "We haven't been introduced. Build trust with Sable first."
	elif int(progress["interview_stage"]) == 0:
		view["text"] = "Before we exchange numbers, tell me who introduced us. Think back to your referral. A wrong answer means trying another night."
		view["choices"] = [{"id":"rae","label":"Rae"},{"id":"sable","label":"Sable"},{"id":"stranger","label":"Someone I met outside class"}]
	else:
		view["text"] = "Sable said you have been dependable. How many completed pickups earned this introduction?"
		view["choices"] = [{"id":"one","label":"One pickup"},{"id":"none","label":"We haven't completed a pickup"},{"id":"three","label":"Three completed pickups"}]
	return view

func supplier_encounter_action(encounter_id: String, action: String) -> bool:
	if not _can_act(): return false
	var encounter: Dictionary = {}
	for candidate: Dictionary in supplier_encounters():
		if candidate["id"] == encounter_id: encounter = candidate
	if encounter.is_empty() or player_location_id != str(encounter["location_id"]): return _fail("Meet them at their late-night hangout to have this conversation.")
	var tier: int = int(encounter["tier"])
	var allowed: bool = false
	for choice: Dictionary in supplier_encounter_view(encounter_id)["choices"]:
		if choice["id"] == action: allowed = true
	if not allowed: return _fail("Choose one of the conversation replies.")
	if tier == 1:
		_unlock_supplier(1)
		return true
	var progress: Dictionary = supplier_progress[2]
	var correct: bool = action == ("sable" if int(progress["interview_stage"]) == 0 else "three")
	if not correct:
		progress["interview_stage"] = 0
		progress["retry_minute"] = minute + MINUTES_PER_DAY
		_notify("The Regent: That doesn't line up. Ask Sable about the referral and come back another night.")
		_mark_changed()
		return false
	progress["interview_stage"] = int(progress["interview_stage"]) + 1
	if int(progress["interview_stage"]) >= 2: _unlock_supplier(2)
	else: _mark_changed()
	return true

func _unlock_supplier(tier: int) -> void:
	if bool(supplier_progress[tier]["unlocked"]): return
	supplier_progress[tier]["unlocked"] = true
	_notify("%s saved as a supplier. You can arrange pickups on your phone. Each new order needs a two-day gap." % Data.SUPPLIERS[tier]["name"])
	feedback_event.emit("text", 0.0)
	_mark_changed()

func inventory_weight() -> float:
	var weight: float = 0.0
	for item: String in Data.ITEMS:
		weight += float(inventory.get(item, 0)) * float(Data.ITEMS[item]["weight"])
	return weight

func capacity_remaining() -> float:
	return maxf(0.0, Data.BACKPACK_CAPACITY - inventory_weight())

func split_flower() -> bool:
	if not _can_act(): return false
	if int(inventory.get("flower", 0)) < 1:
		return _fail("You need a flower bundle. Arrange a supplier meeting on your phone.")
	var old_bags: int = int(inventory["dime_bag"])
	dime_quality = (dime_quality * old_bags + flower_quality * Data.BAGS_PER_BUNDLE) / float(old_bags + Data.BAGS_PER_BUNDLE)
	inventory["flower"] = int(inventory["flower"]) - 1
	inventory["dime_bag"] = old_bags + Data.BAGS_PER_BUNDLE
	if tutorial_step == 0:
		tutorial_step = 1
	_notify("Packed six dime bags into your backpack.")
	feedback_event.emit("pack", 0.0)
	_mark_changed()
	return true

func tutorial_sell() -> bool:
	if not _can_act(): return false
	if tutorial_step != 1: return _fail("Finish the current tutorial step first.")
	if int(inventory.get("dime_bag", 0)) < 1: return _fail("Split your flower bundle in your backpack first.")
	inventory["dime_bag"] = int(inventory["dime_bag"]) - 1
	cash += 20.0
	total_earned += 20.0
	total_sales += 1
	tutorial_step = 2
	_notify("Milo: You're a lifesaver. Save my number and I'll text you later.")
	feedback_event.emit("sale", 20.0)
	_mark_changed()
	return true

func add_tutorial_contact() -> bool:
	if not _can_act(): return false
	if tutorial_step != 2: return _fail("Make your first sale to Milo before saving his number.")
	_add_contact("milo", "Milo", 55.0)
	contacts[0]["sales"] = 1
	contacts[0]["last_sale_minute"] = minute
	contacts[0]["next_request_minute"] = minute + FIRST_FOLLOWUP_MINUTES
	tutorial_step = 3
	_next_message_minute = minute + FIRST_FOLLOWUP_MINUTES
	_notify("Milo saved. He'll text in about 90 minutes. Grab lunch or explore while he enjoys his purchase.")
	_mark_changed()
	save_game()
	return true

func schedule_meeting(message_id: int, location_id: String, delay_minutes: float = 90.0, price: float = 22.0) -> bool:
	if not _can_act() or tutorial_step < 3: return false
	if not _valid_location(location_id): return _fail("Choose a real meeting location.")
	if not is_finite(delay_minutes) or delay_minutes < 30.0 or delay_minutes > 480.0:
		return _fail("Meetings must be scheduled 30–480 minutes from now.")
	if not is_finite(price) or price < 12.0 or price > 40.0:
		return _fail("Choose a price from $12 to $40 per bag.")
	if active_meetings().size() >= 5: return _fail("Your agenda is full. Finish or cancel a meeting first.")
	for message: Dictionary in inbox:
		if int(message["id"]) != message_id: continue
		if str(message.get("type", "client")) == "supplier_callback": return _fail("Call the supplier back to arrange the next night pickup.")
		if str(message["status"]) != "new" or minute > float(message["expires_minute"]):
			return _fail("That request has expired or was already answered.")
		if price > float(message.get("max_price", 40.0)): return _fail("They only agreed to the discounted price of $%d or less." % int(message["max_price"]))
		var due: float = minute + delay_minutes
		if bool(party_summary()["active"]) and not _party_guest(str(message["contact_id"])).is_empty() and due <= float(active_party["end_minute"]) + 15.0:
			return _fail("They're coming to your party. Arrange the meeting at least 15 minutes after it ends.")
		for invite: Dictionary in npc_party_invites:
			if invite["status"] == "accepted" and invite["host_id"] == message["contact_id"] and due >= float(invite["start_minute"]) - 45.0 and due <= float(invite["end_minute"]) + 15.0: return _fail("They're hosting the party you've accepted. Choose a time outside the party.")
		if _overlaps_class(due): return _fail("That time conflicts with class. Choose another time.")
		for meeting: Dictionary in meetings:
			if meeting["status"] == "scheduled" and absf(float(meeting["due_minute"]) - due) < 30.0:
				return _fail("Leave at least 30 minutes between meetings.")
		message["status"] = "accepted"
		var quantity: int = int(message["quantity"])
		meetings.append({"id": _new_id(), "type": "client", "contact_id": message["contact_id"], "contact_name": message["contact_name"], "location_id": location_id, "due_minute": due, "quantity": quantity, "price": price, "cost": 0.0, "tier": -1, "quality": 0.0, "status": "scheduled", "created_minute": minute, "message_id": message_id})
		_notify("Meet %s at %s, %s. Bring %d bags." % [message["contact_name"], Data.location_name(location_id), format_minute(due), quantity])
		_mark_changed()
		return true
	return _fail("That text could not be found.")

func active_meetings() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for meeting: Dictionary in meetings:
		if meeting["status"] == "scheduled": result.append(meeting)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["due_minute"]) < float(b["due_minute"]))
	return result

func complete_meeting(meeting_id: int) -> bool:
	if not _can_act(): return false
	for meeting: Dictionary in meetings:
		if int(meeting["id"]) != meeting_id: continue
		if meeting["status"] != "scheduled": return _fail("That meeting is already finished.")
		if player_location_id != str(meeting["location_id"]): return _fail("Head to %s for this meeting." % Data.location_name(str(meeting["location_id"])))
		var lateness: float = minute - float(meeting["due_minute"])
		if lateness < -MEETING_ARRIVAL_MINUTES: return _fail("You're early. They arrive around %s." % format_minute(float(meeting["due_minute"]) - MEETING_ARRIVAL_MINUTES))
		if lateness > _meeting_grace(meeting): return _fail("You missed this meeting. Check your phone for another opportunity.")
		if meeting["type"] == "supplier":
			return _complete_supplier(meeting)
		var quantity: int = int(meeting["quantity"])
		if int(inventory["dime_bag"]) < quantity: return _fail("You need %d packed bags for this meeting." % quantity)
		var contact: Dictionary = _find_contact(str(meeting["contact_id"]))
		if contact.is_empty(): return _fail("The contact is unavailable.")
		var price: float = float(meeting["price"])
		var fair_price: float = 20.0 + dime_quality * 10.0
		var relationship_change: float = 5.0 + (dime_quality - 0.7) * 12.0
		if lateness > 10.0: relationship_change -= 5.0 + (lateness - 10.0) * 0.25
		if price > fair_price: relationship_change -= (price - fair_price) * 1.2
		if price <= fair_price - 3.0: relationship_change += 2.0
		contact["relationship"] = clampf(float(contact["relationship"]) + relationship_change, 0.0, 100.0)
		contact["sales"] = int(contact["sales"]) + 1
		contact["last_sale_minute"] = minute
		contact["last_order_quantity"] = quantity
		contact["next_request_minute"] = minute + _reorder_delay(quantity)
		inventory["dime_bag"] = int(inventory["dime_bag"]) - quantity
		var earnings: float = quantity * price
		cash += earnings
		total_earned += earnings
		total_sales += 1
		reputation += 1 if relationship_change >= 0.0 else 0
		meeting["status"] = "completed"
		_record_meeting_location(str(meeting["location_id"]))
		_notify("Sold %d bags to %s for $%d. Relationship %s." % [quantity, contact["name"], int(earnings), "+%.0f" % relationship_change if relationship_change >= 0.0 else "%.0f" % relationship_change])
		feedback_event.emit("sale", earnings)
		meeting_reaction.emit(meeting_id, "happy" if relationship_change >= 0.0 else "sad")
		report_crime(10.0 + quantity * 2.0)
		if bool(contact.get("_informant", false)) and not bool(contact.get("_sting_triggered", false)):
			contact["_sting_triggered"] = true
			_notify("Your contact steps away and speaks into their sleeve. Police have your meeting location — move!")
			police_tip.emit(str(meeting["location_id"]), 85.0)
		_maybe_referral(contact)
		_mark_changed()
		return true
	return _fail("That meeting could not be found.")

func cancel_meeting(meeting_id: int) -> bool:
	if not _can_act(): return false
	for meeting: Dictionary in meetings:
		if int(meeting["id"]) == meeting_id and meeting["status"] == "scheduled":
			meeting["status"] = "cancelled"
			meeting_reaction.emit(meeting_id, "sad")
			var contact: Dictionary = _find_contact(str(meeting["contact_id"]))
			if not contact.is_empty():
				contact["relationship"] = maxf(0.0, float(contact["relationship"]) - 3.0)
				contact["next_request_minute"] = maxf(float(contact["next_request_minute"]), minute + REQUEST_RETRY_MINUTES)
			_notify("Meeting cancelled. A little notice beats standing someone up.")
			_mark_changed()
			return true
	return false

func supplier_order(tier: int = 0, bundles: int = 1, source_message_id: int = -1) -> bool:
	if not _can_act() or tutorial_step < 3: return false
	if tier < 0 or tier >= Data.SUPPLIERS.size(): return _fail("Unknown supplier.")
	var supplier: Dictionary = Data.SUPPLIERS[tier]
	var progress: Dictionary = supplier_progress[tier]
	if not bool(progress["unlocked"]): return _fail(str(supplier_catalog()[tier]["discovery_hint"]))
	var callback_message: Dictionary = {}
	if source_message_id >= 0:
		for message: Dictionary in inbox:
			if int(message["id"]) == source_message_id and message.get("type", "") == "supplier_callback" and message["status"] == "new" and minute <= float(message["expires_minute"]) and int(message["tier"]) == tier and int(message["bundles"]) == bundles and int(message.get("obligation_id", 0)) > 0: callback_message = message
		if callback_message.is_empty(): return _fail("That callback no longer represents an open pickup.")
	if callback_message.is_empty() and minute < float(progress["next_order_minute"]): return _fail("%s needs two days between new orders. Call again on day %d at %s." % [supplier["name"], int(float(progress["next_order_minute"]) / MINUTES_PER_DAY) + 1, format_minute(float(progress["next_order_minute"]))])
	if bundles < 1 or bundles > int(supplier["max_bundles"]): return _fail("Choose between 1 and %d bundles." % int(supplier["max_bundles"]))
	var cost: float = float(supplier["bundle_price"]) * bundles
	if cash < cost: return _fail("You need $%d for that order." % int(cost))
	if capacity_remaining() + 0.001 < bundles * 0.8: return _fail("Your backpack has no room for that order.")
	if active_meetings().size() >= 5: return _fail("Your agenda is full.")
	for existing: Dictionary in meetings:
		if existing["status"] == "scheduled" and existing["type"] == "supplier": return _fail("Finish your current supplier meeting first.")
	for callback: Dictionary in callbacks:
		if callback["kind"] == "supplier" and callback["status"] == "pending": return _fail("Your supplier will call back later. Wait for their text before ordering again.")
	var due: float = supplier_pickup_minute(tier)
	var meeting_id: int = _new_id()
	var obligation_id: int = meeting_id if callback_message.is_empty() else int(callback_message["obligation_id"])
	var pickup_location: String = str(supplier_catalog()[tier]["location_id"]) if callback_message.is_empty() else str(callback_message.get("location_id", supplier["location_id"]))
	meetings.append({"id": meeting_id, "obligation_id": obligation_id, "type": "supplier", "contact_id": "supplier_%d" % tier, "contact_name": supplier["name"], "location_id": pickup_location, "due_minute": due, "quantity": bundles, "price": supplier["bundle_price"], "cost": cost, "tier": tier, "quality": supplier["quality"], "risk": minf(0.5, float(supplier["risk"]) + maxf(0.0, bundles - 3) * 0.015), "status": "scheduled", "created_minute": minute})
	if callback_message.is_empty():
		progress["next_order_minute"] = minute + SUPPLIER_COOLDOWN
		progress["orders_placed"] = int(progress.get("orders_placed", 0)) + 1
	else: callback_message["status"] = "accepted"
	_notify("%s: Bring $%d to %s on day %d at %s. Pickups run 22:00–02:00; bigger orders attract attention." % [supplier["name"], int(cost), Data.location_name(pickup_location), int(due / MINUTES_PER_DAY) + 1, format_minute(due)])
	_mark_changed()
	return true

func _complete_supplier(meeting: Dictionary) -> bool:
	var time_of_day: float = fmod(minute, MINUTES_PER_DAY)
	if time_of_day >= 120.0 and time_of_day < 1320.0: return _fail("Supplier handoffs only happen between 22:00 and 02:00. Wait for opening or arrange another night.")
	var quantity: int = int(meeting["quantity"])
	var cost: float = float(meeting["cost"])
	if cash < cost: return _fail("You need $%d to close this deal." % int(cost))
	if capacity_remaining() + 0.001 < float(quantity) * 0.8: return _fail("Make room in your backpack before collecting this order.")
	var old_stock: int = int(inventory["flower"])
	flower_quality = (flower_quality * old_stock + float(meeting["quality"]) * quantity) / float(old_stock + quantity)
	inventory["flower"] = old_stock + quantity
	cash -= cost
	meeting["status"] = "completed"
	var progress: Dictionary = supplier_progress[int(meeting["tier"])]
	progress["successful_meetings"] = int(progress["successful_meetings"]) + 1
	if int(meeting["tier"]) == 1 and int(progress["successful_meetings"]) >= 3 and not bool(supplier_progress[2]["referral_received"]):
		supplier_progress[2]["referral_received"] = true
		_notify("Sable: You've been reliable. Meet the Regent at the East trail shelter after 22:00. Say I sent you, and remember: three completed pickups. Listen before promising anything.")
		feedback_event.emit("text", 0.0)
	_record_meeting_location(str(meeting["location_id"]))
	meeting_reaction.emit(int(meeting["id"]), "happy")
	var bust: bool = _rng.randf() < float(meeting.get("risk", 0.05))
	_notify("Collected %d bundles from %s. Split them in your backpack." % [quantity, meeting["contact_name"]])
	feedback_event.emit("purchase", -cost)
	if bust:
		_notify("Something is wrong. A lookout spotted police closing in — move!")
		report_crime(65.0)
		police_tip.emit(str(meeting["location_id"]), 65.0)
	else:
		report_crime(12.0 + quantity * 2.0)
	_mark_changed()
	return true

func buy_item(item: String, quantity: int = 1) -> bool:
	if not _can_act(): return false
	if not Data.ITEMS.has(item) or item in ["flower", "dime_bag"]: return _fail("That item is not sold here.")
	if quantity < 1 or quantity > 99: return _fail("Choose a valid quantity.")
	if item in ["pistol", "ammo"]:
		if reputation < 8: return _fail("The underground market opens at reputation 8.")
		if player_location_id not in ["car_park", "supplier"]: return _fail("Visit the underground contact at the service yard.")
	elif player_location_id not in ["market", "cafe"]:
		return _fail("Visit the market or takeout patio to shop.")
	if item in ["skateboard", "pistol"] and (int(inventory[item]) > 0 or quantity > 1): return _fail("You only need one of those.")
	var price: float = float(Data.ITEMS[item]["price"]) * quantity
	if cash < price: return _fail("You need $%d for that purchase." % int(price))
	if float(Data.ITEMS[item]["weight"]) * quantity > capacity_remaining() + 0.001: return _fail("Your backpack is full.")
	cash -= price
	inventory[item] = int(inventory.get(item, 0)) + quantity
	_notify("Bought %s ×%d." % [Data.item_name(item), quantity])
	feedback_event.emit("purchase", -price)
	_mark_changed()
	return true

func consume_item(item: String) -> bool:
	if not _can_act(): return false
	if item not in ["sandwich", "energy_drink"]: return _fail("That item cannot be consumed.")
	if int(inventory.get(item, 0)) <= 0: return _fail("You don't have one in your backpack.")
	inventory[item] = int(inventory[item]) - 1
	if item == "sandwich":
		hunger = minf(100.0, hunger + 48.0)
		health = minf(100.0, health + 8.0)
	else:
		energy = minf(100.0, energy + 65.0)
		hunger = minf(100.0, hunger + 8.0)
	_low_food_warned = hunger < 20.0
	_notify("%s used." % Data.item_name(item))
	feedback_event.emit("consume", 0.0)
	_mark_changed()
	return true

func discard_item(item: String, quantity: int = 1) -> bool:
	if not _can_act() or not inventory.has(item) or quantity <= 0: return false
	if int(inventory[item]) < quantity: return false
	inventory[item] = int(inventory[item]) - quantity
	_mark_changed()
	return true

func use_ammo() -> bool:
	if not _can_act() or int(inventory.get("pistol", 0)) <= 0: return _fail("You need a handgun first.")
	if int(inventory.get("ammo", 0)) <= 0: return _fail("You're out of ammunition.")
	inventory["ammo"] = int(inventory["ammo"]) - 1
	report_crime(65.0)
	return true

func use_energy(amount: float) -> bool:
	if not is_finite(amount) or amount < 0.0 or energy < amount: return false
	energy -= amount
	return true

func purchase_vehicle() -> bool:
	if not _can_act(): return false
	if vehicle_owned: return _fail("You already own a car.")
	if player_location_id not in ["car_park", "auto_dealer"]: return _fail("Visit Second Hand Motors to buy a car.")
	if reputation < 22: return _fail("The car seller will meet you at reputation 22.")
	if cash < VEHICLE_PRICE: return _fail("A legitimate car costs $900.")
	cash -= VEHICLE_PRICE
	vehicle_owned = true
	_notify("Your own car. No stolen-vehicle alert when you drive it.")
	feedback_event.emit("purchase", -VEHICLE_PRICE)
	_mark_changed()
	return true

func pay_tuition(amount: float = -1.0) -> bool:
	if not _can_act() or tutorial_step < 3: return false
	if not is_finite(amount): return _fail("Enter a valid payment.")
	if amount < 0.0: amount = minf(cash, tuition_remaining)
	amount = minf(amount, tuition_remaining)
	if amount <= 0.0 or amount > cash: return _fail("You don't have enough cash for that payment.")
	cash -= amount
	tuition_remaining = maxf(0.0, tuition_remaining - amount)
	_notify("Paid $%d toward tuition. $%d left." % [int(amount), int(ceil(tuition_remaining))])
	feedback_event.emit("tuition", -amount)
	_mark_changed()
	if tuition_remaining <= 0.001:
		finish_game(true, "Tuition paid in full. You bought yourself a future.")
	return true

func attend_class() -> bool:
	if not _can_act() or tutorial_step < 3: return false
	if player_location_id not in ["campus_quad", "library", "classroom"]: return _fail("Go to the lecture hall on campus to attend class.")
	var today: int = day_number()
	if _class_resolved_through >= today: return _fail("You've finished class today. Your next class starts at %s." % format_minute(next_class_minute()))
	var schedule: Dictionary = class_schedule(today)
	if minute < float(schedule["start_minute"]) - 20.0: return _fail("Class opens at %s. Arrive before %s." % [format_minute(float(schedule["start_minute"]) - 20.0), format_minute(float(schedule["latest_arrival_minute"]))])
	if minute >= float(schedule["latest_arrival_minute"]): return _fail("Class has already started without you.")
	_class_resolved_through = today
	classes_attended += 1
	_notify("Class attended. A little normal life. You're free at %s." % format_minute(float(schedule["end_minute"])))
	feedback_event.emit("class", 0.0)
	advance_time(float(schedule["end_minute"]) - minute)
	_mark_changed()
	return true

func sleep_at_home() -> bool:
	if not _can_act() or tutorial_step < 3: return false
	if player_location_id != "home": return _fail("Return to your apartment to sleep.")
	if heat > 35.0: return _fail("Lose the police before you lead them home.")
	var time_of_day: float = fmod(minute, MINUTES_PER_DAY)
	var wake: float = 490.0
	var duration: float = wake - time_of_day
	if duration <= 0.0: duration += MINUTES_PER_DAY
	advance_time(duration)
	if status != "playing": return false
	energy = 100.0
	if hunger >= 20.0: health = minf(100.0, health + 30.0)
	_notify("08:10. A new day. Grab breakfast. Today's class starts at %s; arrive before %s." % [format_minute(float(class_schedule()["start_minute"])), format_minute(float(class_schedule()["latest_arrival_minute"]))])
	_mark_changed()
	save_game()
	return true

func work_shift() -> bool:
	if not _can_act() or tutorial_step < 3: return false
	if player_location_id not in ["campus_quad", "library", "classroom"]: return _fail("The campus library always needs an extra pair of hands.")
	if heat > 30.0: return _fail("Lose the police attention before taking a campus shift.")
	var time_of_day: float = fmod(minute, MINUTES_PER_DAY)
	if time_of_day < 11.0 * 60.0 or time_of_day > 19.0 * 60.0: return _fail("Library shifts run between 11:00 and 19:00.")
	advance_time(120.0)
	if status != "playing": return false
	cash += 35.0
	total_earned += 35.0
	_notify("Two hours shelving books. $35 earned honestly. Every little bit helps.")
	_mark_changed()
	return true

func host_party() -> bool:
	if not _can_act() or tutorial_step < 3: return false
	if player_location_id != "home": return _fail("Go home to host a party.")
	if reputation < 5 or contacts.size() < 2: return _fail("Build reputation 5 and meet a second contact before hosting.")
	if bool(party_summary()["active"]): return _fail("Your party is already running. Invite a friend or chat with a guest.")
	if heat > 45.0: return _fail("There's too much police interest to invite people over.")
	var time_of_day: float = fmod(minute, MINUTES_PER_DAY)
	if time_of_day >= 120.0 and time_of_day < 1020.0: return _fail("Parties run between 17:00 and 02:00.")
	var night_day: int = day_number() - (1 if time_of_day < 120.0 else 0)
	if parties_hosted > 0 and last_party_day == night_day: return _fail("One party per night. Give your neighbours a break.")
	if cash < 25.0: return _fail("You need $25 for food and party supplies.")
	var closing: float = float(day_number() - 1) * MINUTES_PER_DAY + (120.0 if time_of_day < 120.0 else 1560.0)
	if closing - minute < 20.0: return _fail("It's nearly 02:00. Save the party for tomorrow evening.")
	for invite: Dictionary in npc_party_invites:
		if invite["status"] == "accepted" and float(invite["start_minute"]) < minf(minute + 180.0, closing) and float(invite["end_minute"]) > minute: return _fail("You've accepted a friend's party during that time. Visit them instead.")
	last_party_day = night_day
	parties_hosted += 1
	cash -= 25.0
	active_party = {"id": _new_id(), "start_minute": minute, "end_minute": minf(minute + 180.0, closing), "night_day": night_day, "status": "active", "guests": [], "mode":"player", "location_id":"home", "host_id":"player", "host_name":"You"}
	_add_party_supplier(_rng.randf() < 0.5)
	_notify("Party supplies are ready. Invite up to eight contacts and greet them at home. The party ends at %s." % format_minute(float(active_party["end_minute"])))
	feedback_event.emit("purchase", -25.0)
	_mark_changed()
	return true

func party_summary() -> Dictionary:
	var live: bool = not active_party.is_empty() and active_party.get("status", "") == "active" and minute >= float(active_party.get("start_minute", 0.0)) and minute < float(active_party.get("end_minute", 0.0)) and status == "playing"
	var guests: Array = active_party.get("guests", []).duplicate(true)
	var contact_count: int = 0
	for guest: Dictionary in guests:
		if not bool(guest.get("supplier", false)): contact_count += 1
	return {"active": live, "id": int(active_party.get("id", 0)), "start_minute": float(active_party.get("start_minute", 0.0)), "end_minute": float(active_party.get("end_minute", 0.0)), "ends_minute": float(active_party.get("end_minute", 0.0)), "guest_count": guests.size(), "contact_guest_count": contact_count, "guests": guests, "mode":str(active_party.get("mode", "player")), "location_id":str(active_party.get("location_id", "home")), "host_id":str(active_party.get("host_id", "player")), "host_name":str(active_party.get("host_name", "You")), "can_invite": live and active_party.get("mode", "player") == "player" and contact_count < 8 and minute + 15.0 < float(active_party.get("end_minute", 0.0))}

func _add_party_supplier(appears: bool) -> void:
	if appears and not _party_contact_available("supplier_1", float(active_party["start_minute"]), float(active_party["end_minute"])):
		appears = false
		_notify("Sable already has a pickup or callback arranged and can't make this party.")
	active_party["supplier_present"] = appears
	if not appears: return
	active_party["guests"].append({"contact_id":"supplier_1", "name":"Sable", "supplier":true, "arrival_minute":minf(float(active_party["start_minute"]) + 30.0, float(active_party["end_minute"]) - 5.0), "status":"invited", "arrived":false, "chatted":false, "purchased":false})

func invite_party_contact(contact_id: String) -> bool:
	if not _can_act() or not bool(party_summary()["can_invite"]): return _fail("Start a party with space and time for another guest first.")
	var contact: Dictionary = _find_contact(contact_id)
	if contact.is_empty() or bool(contact.get("blocked", false)): return _fail("That contact cannot be invited.")
	if not _party_guest(contact_id).is_empty(): return _fail("They already have an invitation to this party.")
	if not _party_contact_available(contact_id, minute, float(active_party["end_minute"])): return _fail("You've already arranged a meeting or callback with them. Keep that appointment first.")
	var arrival: float = minf(minute + 15.0 + active_party["guests"].size() * 4.0 + _rng.randf_range(0.0, 8.0), float(active_party["end_minute"]) - 5.0)
	active_party["guests"].append({"contact_id": contact_id, "name": str(contact["name"]), "arrival_minute": arrival, "status": "invited", "arrived": false, "chatted": false, "purchased": false})
	_notify("%s: I'll come over. See you around %s." % [contact["name"], format_minute(arrival)])
	feedback_event.emit("text", 0.0)
	_mark_changed()
	return true

func _party_guest(contact_id: String) -> Dictionary:
	for guest: Dictionary in active_party.get("guests", []):
		if guest["contact_id"] == contact_id: return guest
	return {}

func mark_party_guest_arrived(contact_id: String) -> bool:
	if not _can_act() or not bool(party_summary()["active"]): return false
	var guest: Dictionary = _party_guest(contact_id)
	if guest.is_empty() or bool(guest["arrived"]) or minute < float(guest["arrival_minute"]): return false
	var contact: Dictionary = _find_contact(contact_id)
	if contact.is_empty() and not bool(guest.get("supplier", false)): return false
	guest["arrived"] = true
	guest["status"] = "inside"
	if not contact.is_empty(): contact["relationship"] = minf(100.0, float(contact["relationship"]) + 2.0)
	party_reaction.emit(contact_id, "wave")
	_mark_changed()
	return true

func party_guest_arrived(contact_id: String) -> bool:
	return mark_party_guest_arrived(contact_id)

func party_guest_view(contact_id: String) -> Dictionary:
	var guest: Dictionary = _party_guest(contact_id)
	if guest.is_empty(): return {}
	var available: bool = bool(party_summary()["active"]) and bool(guest["arrived"]) and player_location_id == str(active_party.get("location_id", "home"))
	if bool(guest.get("supplier", false)):
		return {"contact_id":contact_id,"name":"Sable","supplier":true,"text":"I'm Sable. Introduce yourself and we can exchange numbers." if not bool(supplier_progress[1]["unlocked"]) else "Good to see you. My number's in your supplier list. Enjoy the party.","can_offer":false,"can_chat":available and not bool(guest["chatted"]),"price":0.0,"sold":false}
	var text: String = "Good to see you. Thanks for having me over!"
	if active_party.get("mode", "player") == "npc": text = "Glad you made it! Make yourself at home." if contact_id == active_party.get("host_id", "") else "Hey, you made it too. Nice to see everyone outside class."
	if bool(guest["chatted"]): text = "This was a good idea. Nice to catch up outside class."
	if bool(guest["purchased"]): text = "I'm sorted for tonight, thanks. Let's enjoy the party."
	return {"contact_id": contact_id, "name": str(guest["name"]), "text": text, "can_offer": available and not bool(guest["purchased"]), "can_chat": available and not bool(guest["chatted"]), "price": 24.0, "sold": bool(guest["purchased"])}

func chat_party_guest(contact_id: String) -> bool:
	var view: Dictionary = party_guest_view(contact_id)
	if not _can_act() or not bool(view.get("can_chat", false)): return false
	var guest: Dictionary = _party_guest(contact_id)
	if bool(guest.get("supplier", false)):
		guest["chatted"] = true
		_unlock_supplier(1)
		party_reaction.emit(contact_id, "happy")
		_mark_changed()
		return true
	var contact: Dictionary = _find_contact(contact_id)
	if contact.is_empty(): return false
	guest["chatted"] = true
	contact["relationship"] = minf(100.0, float(contact["relationship"]) + 3.0)
	party_reaction.emit(contact_id, "happy")
	_notify("You caught up with %s. Relationship +3." % guest["name"])
	_maybe_referral(contact)
	_mark_changed()
	return true

func party_chat(contact_id: String) -> bool:
	return chat_party_guest(contact_id)

func sell_party_guest(contact_id: String) -> bool:
	var view: Dictionary = party_guest_view(contact_id)
	if not _can_act() or not bool(view.get("can_offer", false)): return false
	if int(inventory["dime_bag"]) < 1: return _fail("Pack a bag before offering a sale to your guest.")
	var guest: Dictionary = _party_guest(contact_id)
	var contact: Dictionary = _find_contact(contact_id)
	if contact.is_empty(): return false
	guest["purchased"] = true
	inventory["dime_bag"] = int(inventory["dime_bag"]) - 1
	cash += 24.0
	total_earned += 24.0
	total_sales += 1
	reputation += 1
	contact["sales"] = int(contact["sales"]) + 1
	contact["last_sale_minute"] = minute
	contact["last_order_quantity"] = 1
	contact["next_request_minute"] = minute + _reorder_delay(1)
	for message: Dictionary in inbox:
		if message["contact_id"] == contact_id and message["status"] == "new": message["status"] = "expired"
	_notify("Sold one bag to %s for $24." % guest["name"])
	feedback_event.emit("party", 24.0)
	party_reaction.emit(contact_id, "happy")
	report_crime(12.0)
	if bool(contact.get("_informant", false)) and not bool(contact.get("_sting_triggered", false)):
		contact["_sting_triggered"] = true
		_notify("Your guest slips outside and makes a call. A patrol is checking the apartment — be careful.")
		police_tip.emit(str(active_party.get("location_id", "home")), 85.0)
	_maybe_referral(contact)
	_mark_changed()
	return true

func party_sell(contact_id: String) -> bool:
	return sell_party_guest(contact_id)

func _resolve_party() -> void:
	if active_party.is_empty() or active_party["status"] != "active" or minute < float(active_party["end_minute"]): return
	active_party["status"] = "ended"
	for guest: Dictionary in active_party["guests"]: guest["status"] = "left"
	_notify("The party has wrapped up. Your guests are heading home.")
	for invite: Dictionary in npc_party_invites:
		if int(invite["id"]) == int(active_party["id"]): invite["status"] = "ended"

func party_invitations() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for invite: Dictionary in npc_party_invites:
		if invite["status"] not in ["new", "accepted", "active"] or minute >= float(invite["end_minute"]): continue
		var view: Dictionary = invite.duplicate(true)
		view.erase("supplier_present")
		result.append(view)
	return result

func _create_npc_party_invitation(host: Dictionary) -> Dictionary:
	if host.is_empty() or not _can_act() or float(host.get("relationship", 0.0)) < 65.0 or bool(host.get("blocked", false)): return {}
	var start: float = floorf(minute / MINUTES_PER_DAY) * MINUTES_PER_DAY + 1110.0
	if minute > start - 90.0: start += MINUTES_PER_DAY
	if not _party_contact_available(str(host["id"]), start, start + 180.0): return {}
	var invite: Dictionary = {"id":_new_id(),"host_id":str(host["id"]),"host_name":str(host["name"]),"start_minute":start,"end_minute":start+180.0,"location_id":"deerfield_social","status":"new","supplier_present":_rng.randf()<0.5,"text":"A few of us are getting together at the Deerfield neighbors' apartment on day %d, %s. Want to come?" % [int(start / MINUTES_PER_DAY) + 1, format_minute(start)]}
	npc_party_invites.append(invite)
	last_party_invite_day = day_number()
	while npc_party_invites.size() > 12: npc_party_invites.remove_at(0)
	_notify("Party invite from %s. Check your phone to accept or decline." % host["name"])
	feedback_event.emit("text", 0.0)
	_mark_changed()
	return invite

func _party_contact_available(contact_id: String, start: float, end: float) -> bool:
	for meeting: Dictionary in active_meetings():
		if meeting["contact_id"] == contact_id and float(meeting["due_minute"]) <= end + 15.0 and float(meeting["due_minute"]) + _meeting_grace(meeting) >= start - 15.0: return false
	for callback: Dictionary in callbacks:
		if callback["contact_id"] == contact_id and callback["status"] == "pending" and float(callback["due_minute"]) >= start - 15.0 and float(callback["due_minute"]) <= end + 15.0: return false
	return true

func _maybe_npc_party_invitation() -> void:
	if last_party_invite_day >= day_number() or bool(party_summary()["active"]): return
	for invite: Dictionary in party_invitations():
		if invite["status"] in ["new", "accepted", "active"]: return
	var candidates: Array[Dictionary] = []
	for contact: Dictionary in contacts:
		if float(contact["relationship"]) >= 65.0 and not bool(contact.get("blocked", false)): candidates.append(contact)
	if candidates.is_empty(): return
	last_party_invite_day = day_number()
	if _rng.randf() < 0.16: _create_npc_party_invitation(candidates[_rng.randi_range(0, candidates.size()-1)])

func accept_party_invitation(invitation_id: int) -> bool:
	if not _can_act(): return false
	for invite: Dictionary in npc_party_invites:
		if int(invite["id"]) != invitation_id: continue
		if invite["status"] != "new" or minute > float(invite["start_minute"]) + 30.0: return _fail("That party invitation is no longer available.")
		if not _party_contact_available(str(invite["host_id"]), float(invite["start_minute"]), float(invite["end_minute"])): return _fail("You've arranged other business with the host during the party. Resolve that first.")
		if bool(party_summary()["active"]) and float(active_party["end_minute"]) > float(invite["start_minute"]): return _fail("You already have a party planned during that time.")
		for other: Dictionary in npc_party_invites:
			if other["status"] == "accepted" and float(other["start_minute"]) < float(invite["end_minute"]) and float(other["end_minute"]) > float(invite["start_minute"]): return _fail("Another accepted party overlaps this one.")
		invite["status"] = "accepted"
		_notify("You're on %s's guest list. Visit the Deerfield neighbors on day %d at %s." % [invite["host_name"], int(float(invite["start_minute"]) / MINUTES_PER_DAY) + 1, format_minute(float(invite["start_minute"]))])
		_resolve_party_invitations()
		_mark_changed()
		return true
	return _fail("That invitation could not be found.")

func decline_party_invitation(invitation_id: int) -> bool:
	if not _can_act(): return false
	for invite: Dictionary in npc_party_invites:
		if int(invite["id"]) == invitation_id and invite["status"] == "new":
			invite["status"] = "declined"
			_notify("You declined the party invitation. No hard feelings.")
			_mark_changed()
			return true
	return false

func _resolve_party_invitations() -> void:
	for invite: Dictionary in npc_party_invites:
		if invite["status"] == "new" and minute > float(invite["start_minute"]) + 30.0: invite["status"] = "expired"
		if invite["status"] != "accepted" or minute < float(invite["start_minute"]): continue
		if minute >= float(invite["end_minute"]):
			invite["status"] = "expired"
			continue
		if bool(party_summary()["active"]): continue
		invite["status"] = "active"
		active_party = {"id":int(invite["id"]),"start_minute":float(invite["start_minute"]),"end_minute":float(invite["end_minute"]),"night_day":int(float(invite["start_minute"])/MINUTES_PER_DAY)+1,"status":"active","mode":"npc","host_id":str(invite["host_id"]),"host_name":str(invite["host_name"]),"location_id":"deerfield_social","guests":[]}
		var selected: Array[String] = [str(invite["host_id"])]
		for contact: Dictionary in contacts:
			if selected.size() < 4 and not selected.has(str(contact["id"])) and not bool(contact.get("blocked",false)) and _party_contact_available(str(contact["id"]), float(invite["start_minute"]), float(invite["end_minute"])): selected.append(str(contact["id"]))
		for contact_id: String in selected:
			var contact: Dictionary = _find_contact(contact_id)
			if contact.is_empty(): continue
			active_party["guests"].append({"contact_id":contact_id,"name":str(contact["name"]),"arrival_minute":float(invite["start_minute"])+active_party["guests"].size()*5.0,"status":"invited","arrived":false,"chatted":false,"purchased":false})
		_add_party_supplier(bool(invite["supplier_present"]))
		_notify("%s's party is starting at the Deerfield neighbors. Drop in when you're ready." % invite["host_name"])

func advance_time(minutes: float) -> void:
	if status != "playing" or not is_finite(minutes) or minutes <= 0.0: return
	# Small slices preserve ordering when sleeping, attending class, or advancing tests.
	var remaining: float = minf(minutes, MINUTES_PER_DAY * 30.0)
	while remaining > 0.0 and status == "playing":
		var step: float = minf(remaining, 5.0)
		minute += step
		remaining -= step
		hunger = maxf(0.0, hunger - step * 0.025)
		energy = minf(100.0, energy + step * (0.09 if hunger > 20.0 else 0.025))
		heat = maxf(0.0, heat - step * 0.10)
		if hunger <= 0.0:
			health = maxf(0.0, health - step * 0.035)
			if health <= 0.0:
				finish_game(false, "You collapsed from hunger and exhaustion. Your run is over.")
				break
		_resolve_classes()
		if status != "playing": break
		_resolve_meetings()
		_resolve_party()
		_resolve_party_invitations()
		_expire_police_pressure()
		if tutorial_step >= 3:
			_process_callbacks()
			_generate_messages()
	if hunger < 20.0 and not _low_food_warned and status == "playing":
		_low_food_warned = true
		_notify("You're running on empty. Eat a sandwich or stop at the market.")
	_mark_changed()

func set_heat(value: float) -> void:
	if not is_finite(value) or status != "playing": return
	heat = clampf(value, 0.0, 100.0)
	_mark_changed()

func _pressure_area(location_id: String) -> Dictionary:
	if not police_pressure.has(location_id):
		police_pressure[location_id] = {"watch_level": 0, "incident_count": 0, "last_bust_minute": -1.0, "expires_minute": 0.0}
	return police_pressure[location_id]

func _record_meeting_location(location_id: String) -> void:
	if not _valid_location(location_id): return
	_expire_police_pressure()
	consecutive_location_meetings = consecutive_location_meetings + 1 if last_meeting_location == location_id else 1
	last_meeting_location = location_id
	var level: int = 2 if consecutive_location_meetings >= 3 else (1 if consecutive_location_meetings == 2 else 0)
	if level == 0: return
	var area: Dictionary = _pressure_area(location_id)
	if int(area["watch_level"]) >= level: return
	area["watch_level"] = level
	if float(area["expires_minute"]) <= minute: area["expires_minute"] = minute + MINUTES_PER_DAY
	_notify("%s is %s after repeated meetings. Consider another spot." % [Data.location_name(location_id), "under heavy police watch" if level == 2 else "drawing police attention"])
	police_pressure_changed.emit()

func register_pursuit(location_id: String) -> void:
	# World calls this only when a new pursuit starts, never every witness tick.
	if not _can_act() or not _valid_location(location_id): return
	_expire_police_pressure()
	pursuit_incidents += 1
	var area: Dictionary = _pressure_area(location_id)
	area["incident_count"] = int(area["incident_count"]) + 1
	area["last_bust_minute"] = minute
	area["expires_minute"] = minute + MINUTES_PER_DAY
	police_pressure_changed.emit()
	_mark_changed()

func escape_duration_seconds() -> float:
	if pursuit_incidents <= 2: return 10.0
	if pursuit_incidents <= 6: return 10.0 + float(pursuit_incidents - 2) * 5.0
	return 30.0 + float(pursuit_incidents - 6) * 10.0

func police_pressure_locations() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for location_id: String in police_pressure:
		var area: Dictionary = police_pressure[location_id]
		if float(area["expires_minute"]) <= minute: continue
		var strength: int = mini(MAX_EXTRA_OFFICERS_PER_AREA, int(area["watch_level"]) + int(area["incident_count"]))
		if strength <= 0: continue
		result.append({"location_id": location_id, "expires_minute": float(area["expires_minute"]), "strength": strength, "watch_level": int(area["watch_level"]), "incident_count": int(area["incident_count"])})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["strength"]) > int(b["strength"]))
	return result

func _expire_police_pressure(emit_signal: bool = true) -> bool:
	var removed: bool = false
	for location_id: String in police_pressure.keys():
		if float(police_pressure[location_id]["expires_minute"]) > minute: continue
		police_pressure.erase(location_id)
		if last_meeting_location == location_id:
			last_meeting_location = ""
			consecutive_location_meetings = 0
		removed = true
	if removed and emit_signal: police_pressure_changed.emit()
	return removed

func report_crime(severity: float) -> void:
	if not _can_act() or not is_finite(severity) or severity <= 0.0: return
	# World witnesses decide whether a crime becomes a pursuit. General heat still
	# reflects neighbourhood attention even if nobody had direct line of sight.
	heat = clampf(heat + severity * 0.14, 0.0, 100.0)
	crime_committed.emit(severity)
	_mark_changed()

func take_damage(amount: float) -> void:
	if not _can_act() or not is_finite(amount) or amount <= 0.0: return
	health = maxf(0.0, health - amount)
	_mark_changed()
	if health <= 0.0: finish_game(false, "Your injuries ended the run. Every choice had a cost.")

func caught_by_police() -> void:
	if status != "playing": return
	feedback_event.emit("caught", 0.0)
	finish_game(false, "Caught by the police. Hardcore rules: this run is over.")

func finish_game(won: bool, reason: String) -> void:
	if status != "playing": return
	status = "won" if won else "lost"
	ending_reason = reason
	paused = false
	_mark_changed()
	save_game()
	ended.emit(won, reason)

func _resolve_classes() -> void:
	var today: int = day_number()
	while _class_resolved_through < today:
		var target_day: int = _class_resolved_through + 1
		var deadline: float = float(class_schedule(target_day)["latest_arrival_minute"])
		if minute < deadline: break
		_class_resolved_through = target_day
		missed_classes += 1
		_notify("Missed class. Academic housing warning %d/3." % missed_classes)
		if missed_classes >= 3:
			finish_game(false, "Three missed classes cost you your student housing. Evicted. Your run is over.")
			return

func _resolve_meetings() -> void:
	for meeting: Dictionary in meetings:
		if meeting["status"] != "scheduled": continue
		if minute <= float(meeting["due_minute"]) + _meeting_grace(meeting): continue
		meeting["status"] = "missed"
		meeting_reaction.emit(int(meeting["id"]), "angry")
		meeting_missed.emit(int(meeting["id"]), str(meeting["contact_id"]))
		var contact: Dictionary = _find_contact(str(meeting["contact_id"]))
		if not contact.is_empty():
			contact["relationship"] = maxf(0.0, float(contact["relationship"]) - 12.0)
			contact["next_request_minute"] = maxf(float(contact["next_request_minute"]), minute + REQUEST_RETRY_MINUTES)
		_notify("You missed %s at %s. They've headed home." % [meeting["contact_name"], Data.location_name(str(meeting["location_id"]))])
	for message: Dictionary in inbox:
		if message["status"] == "new" and minute > float(message["expires_minute"]): message["status"] = "expired"
	# Bound the save/UI without discarding active obligations.
	while meetings.size() > 40:
		var remove_index: int = -1
		for index: int in range(meetings.size()):
			if meetings[index]["status"] != "scheduled":
				remove_index = index
				break
		if remove_index == -1: break
		meetings.remove_at(remove_index)
	while inbox.size() > 16:
		inbox.remove_at(0)

func _meeting_grace(meeting: Dictionary) -> float:
	var contact: Dictionary = _find_contact(str(meeting["contact_id"]))
	var bonus: float = 0.0 if contact.is_empty() else maxf(0.0, (float(contact["relationship"]) - 50.0) * 0.4)
	return MEETING_WINDOW + bonus

func _overlaps_class(value: float) -> bool:
	var target_day: int = int(floor(value / MINUTES_PER_DAY)) + 1
	if target_day <= _class_resolved_through: return false
	var schedule: Dictionary = class_schedule(target_day)
	return value >= float(schedule["start_minute"]) - 20.0 and value <= float(schedule["end_minute"])

func _generate_messages() -> void:
	if minute < _next_message_minute or contacts.is_empty(): return
	_next_message_minute = minute + _rng.randf_range(35.0, 60.0)
	var time_of_day: float = fmod(minute, MINUTES_PER_DAY)
	if time_of_day < 7.0 * 60.0 or time_of_day > 23.0 * 60.0: return
	_maybe_npc_party_invitation()
	var candidates: Array[Dictionary] = []
	for contact: Dictionary in contacts:
		if _contact_can_request(contact): candidates.append(contact)
	if not candidates.is_empty():
		_create_request(candidates[_rng.randi_range(0, candidates.size() - 1)])

func _contact_can_request(contact: Dictionary) -> bool:
	if bool(contact.get("blocked", false)): return false
	if bool(party_summary()["active"]) and not _party_guest(str(contact["id"])).is_empty(): return false
	if minute < float(contact.get("next_request_minute", minute)): return false
	for callback: Dictionary in callbacks:
		if callback["status"] == "pending" and callback["contact_id"] == contact["id"]: return false
	for message: Dictionary in inbox:
		if message["contact_id"] == contact["id"] and message["status"] == "new": return false
	for meeting: Dictionary in meetings:
		if meeting["contact_id"] == contact["id"] and meeting["status"] == "scheduled": return false
	return true

func _reorder_delay(quantity: int) -> float:
	# Customers need time to use a purchase. Bigger orders last longer, while a
	# little variation keeps the whole contact list from texting simultaneously.
	return REORDER_MINUTES + _rng.randf_range(0.0, 120.0) + maxf(0.0, quantity - 1) * 30.0

func _create_request(contact: Dictionary, proactive: bool = false) -> bool:
	if proactive:
		if not _can_proactive_request(contact) or _contact_has_business(str(contact["id"])): return false
	elif not _contact_can_request(contact): return false
	var maximum: int = mini(6, 2 + reputation / 6)
	var quantity: int = _rng.randi_range(1, maximum)
	if reputation == 0: quantity = 2
	inbox.append({"id": _new_id(), "contact_id": contact["id"], "contact_name": contact["name"], "quantity": quantity, "text": "Hey, can I grab %d bags? Pick a place and time that works for you." % quantity, "status": "new", "created_minute": minute, "expires_minute": minute + 210.0, "suggested_price": 24.0})
	contact["next_request_minute"] = maxf(float(contact["next_request_minute"]), minute + REQUEST_RETRY_MINUTES)
	_notify("New text from %s." % contact["name"])
	feedback_event.emit("text", 0.0)
	return true

func _maybe_referral(contact: Dictionary) -> void:
	var target_count: int = mini(Data.CONTACT_NAMES.size(), 1 + reputation / 2)
	var pending: int = 0
	for entry: Dictionary in introductions:
		if entry["status"] == "pending": pending += 1
	if contacts.size() + pending >= target_count or float(contact["relationship"]) < 40.0: return
	var contact_name: String = ""
	for candidate: String in Data.CONTACT_NAMES:
		var used: bool = false
		for known: Dictionary in contacts:
			if known["name"] == candidate: used = true
		for entry: Dictionary in introductions:
			if entry["name"] == candidate: used = true
		if not used:
			contact_name = candidate
			break
	if contact_name.is_empty(): return
	var informant: bool = _rng.randf() < minf(0.26, 0.12 + heat * 0.0014)
	var accurate_cover: bool = not informant or _rng.randf() < 0.35
	var background: Dictionary = Data.contact_background(str(contact["name"]))
	var claimed_course: String = str(background["course"]) if accurate_cover else ("chemistry" if background["course"] != "chemistry" else "history")
	introductions.append({"id": _new_id(), "name": contact_name, "referrer_id": str(contact["id"]), "referrer_name": str(contact["name"]), "status": "pending", "created_minute": minute, "text": "Hey, %s said you might know where to get a couple of bags. Are you around?" % contact["name"], "who_answer": "", "connection_answer": "", "_informant": informant, "_cover_course": claimed_course, "_cover_hangout": background["hangout"]})
	_notify("Unknown number: %s says they know %s. Ask a few questions before saving the number." % [contact_name, contact["name"]])
	feedback_event.emit("text", 0.0)

func _add_contact(contact_id: String, contact_name: String, relationship: float) -> void:
	contacts.append({"id": contact_id, "name": contact_name, "relationship": relationship, "sales": 0, "last_sale_minute": -1.0, "last_order_quantity": 1, "next_request_minute": minute, "next_outreach_minute": 0.0, "last_text_minute": -1.0, "last_reply": "", "blocked": false})

func _find_contact(contact_id: String) -> Dictionary:
	for contact: Dictionary in contacts:
		if str(contact["id"]) == contact_id: return contact
	return {}

func contact_profile(contact_id: String) -> Dictionary:
	var contact: Dictionary = _find_contact(contact_id)
	if contact.is_empty(): return {}
	var result: Dictionary = Data.contact_background(str(contact["name"]))
	result.merge({"id": contact_id, "name": str(contact["name"]), "last_reply": str(contact.get("last_reply", "")), "last_text_minute": float(contact.get("last_text_minute", -1.0)), "next_outreach_minute": float(contact.get("next_outreach_minute", 0.0))})
	return result

func pending_introductions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in introductions:
		if entry["status"] != "pending": continue
		var public_entry: Dictionary = {}
		for key: String in ["id", "name", "text", "referrer_name", "referrer_id", "who_answer", "connection_answer", "status"]: public_entry[key] = entry[key]
		result.append(public_entry)
	return result

func ask_introduction(introduction_id: int, question: String) -> String:
	if not _can_act() or question not in ["referrer", "connection"]: return ""
	for entry: Dictionary in introductions:
		if int(entry["id"]) != introduction_id or entry["status"] != "pending": continue
		var answer: String
		if question == "referrer":
			answer = "%s gave me your number. Said you might be able to help." % entry["referrer_name"]
			entry["who_answer"] = answer
		else:
			answer = "We know each other from %s. Usually see them at %s." % [entry["_cover_course"], entry["_cover_hangout"]]
			entry["connection_answer"] = answer
		_mark_changed()
		return answer
	return ""

func resolve_introduction(introduction_id: int, decision: String) -> bool:
	if not _can_act() or decision not in ["accept", "decline", "block"]: return false
	for entry: Dictionary in introductions:
		if int(entry["id"]) != introduction_id or entry["status"] != "pending": continue
		entry["status"] = {"accept": "accepted", "decline": "declined", "block": "blocked"}[decision]
		if decision == "accept":
			var contact_id: String = "referral_%d" % introduction_id
			_add_contact(contact_id, str(entry["name"]), 42.0)
			var contact: Dictionary = contacts.back()
			contact["_informant"] = bool(entry["_informant"])
			contact["_sting_triggered"] = false
			contact["referrer_id"] = entry["referrer_id"]
			_create_request(contact)
			_notify("%s saved. An introduction is a starting point, not a guarantee. Choose any meeting yourself." % entry["name"])
		else:
			_notify("Number blocked." if decision == "block" else "You passed on the introduction. No meeting was arranged.")
		_mark_changed()
		return true
	return _fail("That introduction has already been handled.")

func text_contact(contact_id: String) -> bool:
	if not _can_act() or tutorial_step < 3: return false
	var contact: Dictionary = _find_contact(contact_id)
	if contact.is_empty() or bool(contact.get("blocked", false)): return _fail("That contact is unavailable.")
	if minute < float(contact.get("next_outreach_minute", 0.0)): return _fail("Give them a few hours before texting again.")
	if _contact_has_business(contact_id): return _fail("You already have a request, callback or meeting with them.")
	contact["next_outreach_minute"] = minute + REQUEST_RETRY_MINUTES
	contact["last_text_minute"] = minute
	var interested: bool = _can_proactive_request(contact) and _rng.randf() < 0.20 + float(contact["relationship"]) * 0.001
	if interested and _create_request(contact, true):
		var message: Dictionary = inbox.back()
		var discounted: bool = _rng.randf() < 0.7
		message["quantity"] = 1
		if discounted:
			message["suggested_price"] = 20.0
			message["max_price"] = 20.0
			message["text"] = "Wasn't planning on it, but I could grab one for $20. Pick a place and time if that works."
		else:
			message["text"] = "Good timing. I could use one. Where and when?"
		contact["last_reply"] = message["text"]
	else:
		contact["last_reply"] = "I'm good for now, thanks. Try me another time."
		feedback_event.emit("text", 0.0)
	_notify("%s: %s" % [contact["name"], contact["last_reply"]])
	_mark_changed()
	return true

func _can_proactive_request(contact: Dictionary) -> bool:
	if bool(contact.get("blocked", false)): return false
	var last_sale: float = float(contact["last_sale_minute"])
	var gap: float = 180.0 + maxf(0.0, float(contact.get("last_order_quantity", 1)) - 1.0) * 30.0
	return last_sale < 0.0 or minute >= last_sale + gap

func _contact_has_business(contact_id: String) -> bool:
	if bool(party_summary()["active"]) and not _party_guest(contact_id).is_empty(): return true
	for message: Dictionary in inbox:
		if message["contact_id"] == contact_id and message["status"] == "new": return true
	for meeting: Dictionary in meetings:
		if meeting["contact_id"] == contact_id and meeting["status"] == "scheduled": return true
	for callback: Dictionary in callbacks:
		if callback["contact_id"] == contact_id and callback["status"] == "pending": return true
	return false

func street_conversation(npc_id: String, npc_name: String = "Neighbour") -> Dictionary:
	if npc_id.is_empty() or npc_id.length() > 80 or not _can_act(): return {}
	if not street_npcs.has(npc_id):
		if street_npcs.size() >= 128: return {}
		var roll: float = _rng.randf()
		# A separate draw gives every hidden outcome the same pool of voices.
		var dialogue_seed: int = _rng.randi_range(0, 1000000)
		street_npcs[npc_id] = {"name": npc_name.left(60), "response": "sale" if roll < 0.60 else ("refusal" if roll < 0.91 else "report"), "status": "idle", "next_offer_minute": 0.0, "last_sale_minute": -1.0, "sales": 0, "contact_id": "", "text": Data.STREET_GREETINGS[dialogue_seed % Data.STREET_GREETINGS.size()], "dialogue_seed": dialogue_seed, "talk_count": 0}
	var npc: Dictionary = street_npcs[npc_id]
	var contact: Dictionary = _find_contact(str(npc["contact_id"]))
	var ready: bool = minute >= float(npc["next_offer_minute"]) and (contact.is_empty() or (minute >= float(contact["next_request_minute"]) and not _contact_has_business(str(contact["id"]))))
	return {"npc_id": npc_id, "name": str(npc["name"]), "text": str(npc["text"]), "can_offer": tutorial_step >= 3 and ready and npc["status"] not in ["reporting", "reported"], "can_add_contact": int(npc["sales"]) > 0 and str(npc["contact_id"]).is_empty(), "sold": int(npc["sales"]) > 0, "price": 22.0, "contact_id": str(npc["contact_id"])}

func street_smalltalk(npc_id: String, _goal: String = "") -> String:
	if not _can_act() or not street_npcs.has(npc_id): return ""
	var npc: Dictionary = street_npcs[npc_id]
	if npc["status"] in ["reporting", "reported"]: return str(npc["text"])
	var seed_value: int = int(npc.get("dialogue_seed", posmod(npc_id.hash(), 1000000)))
	var count: int = int(npc.get("talk_count", 0))
	var reply: String = Data.STREET_SMALLTALK[(seed_value + count) % Data.STREET_SMALLTALK.size()]
	npc["talk_count"] = count + 1
	npc["text"] = reply
	street_reaction.emit(npc_id, "question" if count % 3 == 1 else "wave")
	_mark_changed()
	return reply

func offer_street_sale(npc_id: String) -> bool:
	if not _can_act() or tutorial_step < 3 or not street_npcs.has(npc_id): return false
	var view: Dictionary = street_conversation(npc_id)
	if not bool(view.get("can_offer", false)): return _fail("They aren't looking for another offer right now.")
	if int(inventory["dime_bag"]) < 1: return _fail("Pack a dime bag before offering a sale.")
	var npc: Dictionary = street_npcs[npc_id]
	var reply_index: int = int(npc.get("dialogue_seed", posmod(npc_id.hash(), 1000000)))
	npc["next_offer_minute"] = minute + REQUEST_RETRY_MINUTES
	if npc["response"] == "refusal":
		npc["text"] = Data.STREET_REFUSE_REPLIES[reply_index % Data.STREET_REFUSE_REPLIES.size()]
		street_reaction.emit(npc_id, "sad")
		_notify("%s: %s" % [npc["name"], npc["text"]])
		_mark_changed()
		return false
	if npc["response"] == "report":
		npc["status"] = "reporting"
		npc["text"] = Data.STREET_REPORT_REPLIES[reply_index % Data.STREET_REPORT_REPLIES.size()]
		street_reaction.emit(npc_id, "angry")
		_notify("%s backs away and starts looking for a police officer." % npc["name"])
		civilian_reaction.emit(npc_id, "report")
		_mark_changed()
		return false
	inventory["dime_bag"] = int(inventory["dime_bag"]) - 1
	cash += 22.0
	total_earned += 22.0
	total_sales += 1
	reputation += 1
	npc["sales"] = int(npc["sales"]) + 1
	npc["status"] = "sold"
	npc["last_sale_minute"] = minute
	npc["next_offer_minute"] = minute + _reorder_delay(1)
	npc["text"] = Data.STREET_BUY_REPLIES[reply_index % Data.STREET_BUY_REPLIES.size()]
	var contact: Dictionary = _find_contact(str(npc["contact_id"]))
	if not contact.is_empty():
		contact["sales"] = int(contact["sales"]) + 1
		contact["last_sale_minute"] = minute
		contact["last_order_quantity"] = 1
		contact["next_request_minute"] = npc["next_offer_minute"]
		contact["relationship"] = minf(100.0, float(contact["relationship"]) + 3.0)
		_maybe_referral(contact)
	_notify("Sold one bag to %s for $22." % npc["name"])
	feedback_event.emit("sale", 22.0)
	street_reaction.emit(npc_id, "happy")
	report_crime(12.0)
	_mark_changed()
	return true

func add_street_contact(npc_id: String) -> bool:
	if not _can_act() or not street_npcs.has(npc_id): return false
	var npc: Dictionary = street_npcs[npc_id]
	if int(npc["sales"]) < 1 or not str(npc["contact_id"]).is_empty(): return _fail("Make a sale before exchanging numbers, or check your saved contacts.")
	var contact_id: String = "street_" + npc_id
	_add_contact(contact_id, str(npc["name"]), 45.0)
	var contact: Dictionary = contacts.back()
	contact["sales"] = npc["sales"]
	contact["last_sale_minute"] = npc["last_sale_minute"]
	contact["next_request_minute"] = npc["next_offer_minute"]
	npc["contact_id"] = contact_id
	npc["text"] = "Number saved. I'll text when I'm looking again."
	_notify("%s added to your contacts." % npc["name"])
	_mark_changed()
	return true

func pending_civilian_reports() -> Array[String]:
	var result: Array[String] = []
	for npc_id: String in street_npcs:
		if street_npcs[npc_id]["status"] == "reporting": result.append(npc_id)
	return result

func civilian_report_arrived(npc_id: String) -> bool:
	if not _can_act() or not street_npcs.has(npc_id) or street_npcs[npc_id]["status"] != "reporting": return false
	street_npcs[npc_id]["status"] = "reported"
	_mark_changed()
	return true

func supplier_pickup_minute(tier: int, earliest: float = -1.0) -> float:
	var ready: float = earliest
	if bool(party_summary()["active"]) and not _party_guest("supplier_%d" % tier).is_empty(): ready = maxf(ready, float(active_party["end_minute"]) + 30.0)
	return next_supplier_minute(ready)

func next_supplier_minute(earliest: float = -1.0) -> float:
	var due: float = maxf(minute + 60.0, earliest if is_finite(earliest) else minute + 60.0)
	for attempt: int in range(40):
		var time_of_day: float = fmod(due, MINUTES_PER_DAY)
		if time_of_day >= 120.0 and time_of_day < 1320.0: due += 1320.0 - time_of_day
		var conflict: bool = false
		for existing: Dictionary in active_meetings():
			if absf(float(existing["due_minute"]) - due) < 30.0:
				due = float(existing["due_minute"]) + 30.0
				conflict = true
				break
		if not conflict: return due
	return due

func accept_supplier_callback(message_id: int) -> bool:
	if not _can_act(): return false
	for message: Dictionary in inbox:
		if int(message["id"]) != message_id: continue
		if message.get("type", "") != "supplier_callback" or message["status"] != "new" or minute > float(message["expires_minute"]): return _fail("That supplier callback is no longer available.")
		return supplier_order(int(message["tier"]), int(message["bundles"]), message_id)
	return _fail("That supplier callback could not be found.")

func _next_business_minute(earliest: float) -> float:
	var time_of_day: float = fmod(earliest, MINUTES_PER_DAY)
	if time_of_day < 420.0: return earliest + 420.0 - time_of_day
	if time_of_day > 1380.0: return earliest + MINUTES_PER_DAY - time_of_day + 420.0
	return earliest

func request_tomorrow(message_id: int) -> bool:
	if not _can_act(): return false
	for message: Dictionary in inbox:
		if int(message["id"]) != message_id: continue
		if message["status"] != "new" or minute > float(message["expires_minute"]): return _fail("That request is no longer available.")
		if message.get("type", "client") == "supplier_callback": return _fail("Use the supplier callback to arrange a night pickup.")
		var contact: Dictionary = _find_contact(str(message["contact_id"]))
		if contact.is_empty(): return false
		var due: float = _next_business_minute(maxf(float(day_number()) * MINUTES_PER_DAY + 540.0, float(contact["next_request_minute"])))
		message["status"] = "postponed"
		contact["next_request_minute"] = due
		_queue_callback("client", str(contact["id"]), str(contact["name"]), due)
		_notify("%s: Sure, I'll hit you up tomorrow. No meeting booked yet." % contact["name"])
		_mark_changed()
		return true
	return _fail("That text could not be found.")

func postpone_meeting(meeting_id: int, delay_minutes: float = 120.0) -> bool:
	if not _can_act() or not is_finite(delay_minutes) or delay_minutes < 120.0 or delay_minutes > 480.0: return false
	for meeting: Dictionary in meetings:
		if int(meeting["id"]) != meeting_id or meeting["status"] != "scheduled": continue
		if player_location_id != str(meeting["location_id"]): return _fail("Speak to them at the meeting to postpone without a penalty.")
		if minute < float(meeting["due_minute"]) - MEETING_ARRIVAL_MINUTES or minute > float(meeting["due_minute"]) + _meeting_grace(meeting): return _fail("They aren't available at the meeting yet.")
		meeting["status"] = "postponed"
		var kind: String = str(meeting["type"])
		var due: float = _next_business_minute(minute + delay_minutes) if kind == "client" else next_supplier_minute(minute + delay_minutes)
		var contact: Dictionary = _find_contact(str(meeting["contact_id"]))
		if not contact.is_empty(): contact["next_request_minute"] = due
		_queue_callback(kind, str(meeting["contact_id"]), str(meeting["contact_name"]), due, int(meeting["tier"]), int(meeting["quantity"]))
		if kind == "supplier":
			for callback: Dictionary in callbacks:
				if callback["contact_id"] == meeting["contact_id"] and callback["status"] == "pending":
					callback["obligation_id"] = int(meeting.get("obligation_id", meeting["id"]))
					callback["location_id"] = str(meeting["location_id"])
		_notify("%s: No problem. I'll text again on day %d at about %s. We'll agree on a new meeting then." % [meeting["contact_name"], int(due / MINUTES_PER_DAY) + 1, format_minute(due)])
		_mark_changed()
		return true
	return _fail("That meeting is already finished.")

func _queue_callback(kind: String, contact_id: String, contact_name: String, due: float, tier: int = -1, bundles: int = 1) -> void:
	for callback: Dictionary in callbacks:
		if callback["contact_id"] == contact_id and callback["status"] == "pending": return
	callbacks.append({"id": _new_id(), "kind": kind, "contact_id": contact_id, "contact_name": contact_name, "due_minute": due, "tier": tier, "bundles": bundles, "status": "pending"})
	while callbacks.size() > 80:
		var removed: bool = false
		for index: int in range(callbacks.size()):
			if callbacks[index]["status"] != "pending":
				callbacks.remove_at(index)
				removed = true
				break
		if not removed: break

func _process_callbacks() -> void:
	for callback: Dictionary in callbacks:
		if callback["status"] != "pending" or minute < float(callback["due_minute"]): continue
		if callback["kind"] == "supplier":
			callback["status"] = "delivered"
			inbox.append({"id": _new_id(), "type": "supplier_callback", "obligation_id": int(callback.get("obligation_id", callback["id"])), "contact_id": callback["contact_id"], "contact_name": callback["contact_name"], "quantity": callback["bundles"], "bundles": callback["bundles"], "tier": callback["tier"], "text": "Ready to try again? Call me back and we'll agree on a new pickup between 22:00 and 02:00.", "status": "new", "created_minute": minute, "expires_minute": minute + 240.0, "suggested_price": 0.0})
			inbox.back()["location_id"] = str(callback.get("location_id", Data.SUPPLIERS[int(callback["tier"])]["location_id"]))
			_notify("Supplier callback from %s. A new pickup still needs your confirmation." % callback["contact_name"])
			feedback_event.emit("text", 0.0)
		else:
			var contact: Dictionary = _find_contact(str(callback["contact_id"]))
			if contact.is_empty() or bool(contact.get("blocked", false)):
				callback["status"] = "cancelled"
				continue
			if minute < _next_business_minute(minute): continue
			callback["status"] = "delivered"
			if not _create_request(contact): callback["status"] = "pending"

func _valid_location(location_id: String) -> bool:
	for location: Dictionary in Data.LOCATIONS:
		if location["id"] == location_id: return true
	return false

func _new_id() -> int:
	var value: int = _next_id
	_next_id += 1
	return value

func _can_act() -> bool:
	return status == "playing"

func _fail(message: String) -> bool:
	last_error = message
	_notify(message)
	return false

func _notify(message: String) -> void:
	notification.emit(message)

func _mark_changed() -> void:
	_dirty = true
	changed.emit()

func save_game() -> bool:
	var state: Dictionary = {
		"version": Data.SAVE_VERSION, "calendar_version": 1, "cash": cash, "tuition_remaining": tuition_remaining,
		"health": health, "hunger": hunger, "energy": energy, "heat": heat,
		"reputation": reputation, "minute": minute, "tutorial_step": tutorial_step,
		"inventory": inventory, "contacts": contacts, "inbox": inbox, "meetings": meetings,
		"introductions": introductions, "callbacks": callbacks, "street_npcs": street_npcs,
		"status": status, "ending_reason": ending_reason, "missed_classes": missed_classes,
		"vehicle_owned": vehicle_owned, "flower_quality": flower_quality, "dime_quality": dime_quality,
		"total_sales": total_sales, "total_earned": total_earned, "classes_attended": classes_attended,
		"parties_hosted": parties_hosted, "last_party_day": last_party_day,
		"active_party": active_party, "police_pressure": police_pressure,
		"supplier_progress": supplier_progress, "npc_party_invites": npc_party_invites, "last_party_invite_day": last_party_invite_day,
		"pursuit_incidents": pursuit_incidents, "last_meeting_location": last_meeting_location,
		"consecutive_location_meetings": consecutive_location_meetings,
		"next_id": _next_id, "class_resolved_through": _class_resolved_through,
		"next_message_minute": _next_message_minute, "player_location_id": player_location_id,
		"world_state": _sanitize_world_state(world_state),
	}
	var file: FileAccess = FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if file == null: return _fail("Progress could not be saved on this device.")
	file.store_string(JSON.stringify(state))
	file.close()
	var result: Error = DirAccess.rename_absolute(save_path + ".tmp", save_path)
	if result != OK: return _fail("Progress could not be saved on this device.")
	_dirty = false
	_autosave_seconds = 0.0
	return true

func load_game(show_message: bool = true) -> bool:
	if not FileAccess.file_exists(save_path): return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not parsed is Dictionary: return _fail("The saved game is damaged. Start a new run to continue.")
	var state: Dictionary = parsed
	if not _validate_save(state): return _fail("The saved game is incompatible or damaged. Start a new run to continue.")
	cash = float(state["cash"])
	tuition_remaining = float(state["tuition_remaining"])
	health = float(state["health"])
	hunger = float(state["hunger"])
	energy = float(state["energy"])
	heat = float(state["heat"])
	reputation = int(state["reputation"])
	minute = float(state["minute"])
	tutorial_step = int(state["tutorial_step"])
	inventory = state["inventory"].duplicate(true)
	contacts.assign(state["contacts"])
	inbox.assign(state["inbox"])
	meetings.assign(state["meetings"])
	introductions.assign(state.get("introductions", []))
	callbacks.assign(state.get("callbacks", []))
	street_npcs = state.get("street_npcs", {}).duplicate(true)
	status = str(state["status"])
	ending_reason = str(state.get("ending_reason", ""))
	missed_classes = int(state["missed_classes"])
	vehicle_owned = bool(state.get("vehicle_owned", false))
	flower_quality = float(state["flower_quality"])
	dime_quality = float(state["dime_quality"])
	total_sales = int(state["total_sales"])
	total_earned = float(state["total_earned"])
	classes_attended = int(state["classes_attended"])
	parties_hosted = int(state["parties_hosted"])
	last_party_day = int(state["last_party_day"])
	active_party = state.get("active_party", {}).duplicate(true)
	supplier_progress.clear()
	if state.has("supplier_progress"): supplier_progress.assign(state["supplier_progress"])
	else: _migrate_supplier_progress()
	npc_party_invites.assign(state.get("npc_party_invites", []))
	last_party_invite_day = int(state.get("last_party_invite_day", 0))
	police_pressure = state.get("police_pressure", {}).duplicate(true)
	pursuit_incidents = int(state.get("pursuit_incidents", 0))
	last_meeting_location = str(state.get("last_meeting_location", ""))
	consecutive_location_meetings = int(state.get("consecutive_location_meetings", 0))
	_next_id = int(state["next_id"])
	_class_resolved_through = int(state["class_resolved_through"])
	_next_message_minute = float(state["next_message_minute"])
	player_location_id = str(state.get("player_location_id", "campus_quad"))
	world_state = _sanitize_world_state(state.get("world_state", {}))
	_migrate_contact_timing()
	var moved_suppliers: int = _migrate_supplier_schedule()
	var moved_classes: int = _migrate_class_meetings() if not state.has("calendar_version") else 0
	_migrate_supplier_callbacks()
	var expired_pressure: bool = _expire_police_pressure(false)
	if not active_party.is_empty() and minute >= float(active_party["end_minute"]):
		active_party["status"] = "ended"
		for guest: Dictionary in active_party["guests"]: guest["status"] = "left"
	for invite: Dictionary in npc_party_invites:
		if minute >= float(invite["end_minute"]): invite["status"] = "ended" if invite["status"] == "active" else "expired"
	paused = false
	_low_food_warned = hunger < 20.0
	_dirty = moved_suppliers > 0 or moved_classes > 0 or expired_pressure
	if show_message: _notify("Progress restored. Day %d, %s." % [day_number(), time_text()])
	if show_message and moved_suppliers > 0: _notify("Your supplier moved the daytime pickup to the next night window. Check the updated day and time in your agenda.")
	if show_message and moved_classes > 0: _notify("Your class timetable changed. Conflicting appointments moved after class; check your agenda for their new times.")
	changed.emit()
	return true

func _migrate_supplier_progress() -> void:
	for tier: int in range(3): supplier_progress.append(_supplier_defaults(tier))
	for meeting: Dictionary in meetings:
		if meeting["type"] != "supplier": continue
		var tier: int = int(meeting["tier"])
		if tier < 0 or tier > 2: continue
		var progress: Dictionary = supplier_progress[tier]
		progress["unlocked"] = true
		progress["orders_placed"] = int(progress["orders_placed"]) + 1
		progress["next_order_minute"] = maxf(float(progress["next_order_minute"]), float(meeting["created_minute"]) + SUPPLIER_COOLDOWN)
		if meeting["status"] == "completed": progress["successful_meetings"] = int(progress["successful_meetings"]) + 1
	if int(supplier_progress[1]["successful_meetings"]) >= 3: supplier_progress[2]["referral_received"] = true

func _migrate_supplier_callbacks() -> void:
	for callback: Dictionary in callbacks:
		if callback["kind"] == "supplier" and not callback.has("obligation_id"): callback["obligation_id"] = int(callback["id"])
	for message: Dictionary in inbox:
		if message.get("type", "") == "supplier_callback" and not message.has("obligation_id"): message["obligation_id"] = int(message["id"])

func _migrate_class_meetings() -> int:
	var moved: Array[int] = []
	for meeting: Dictionary in meetings:
		if meeting["status"] != "scheduled" or meeting["type"] != "client": continue
		var due: float = float(meeting["due_minute"])
		if minute > due + _meeting_grace(meeting) or not _overlaps_class(due): continue
		meeting["status"] = "migrating"
		due = float(class_schedule(int(due / MINUTES_PER_DAY) + 1)["end_minute"]) + 30.0
		for attempt: int in range(meetings.size()+1):
			var conflict: bool = false
			for other: Dictionary in active_meetings():
				if absf(float(other["due_minute"]) - due) < 30.0:
					due = float(other["due_minute"]) + 30.0
					conflict = true
					break
			if not conflict: break
		meeting["due_minute"] = due
		meeting["status"] = "scheduled"
		moved.append(int(meeting["id"]))
	if not moved.is_empty():
		var retained: Array[Dictionary] = []
		for actor: Dictionary in world_state.get("meeting_walks", []):
			if not moved.has(int(actor["id"])): retained.append(actor)
		world_state["meeting_walks"] = retained
	return moved.size()

func _migrate_supplier_schedule() -> int:
	var moved_ids: Array[int] = []
	for meeting: Dictionary in meetings:
		if meeting["status"] != "scheduled" or meeting["type"] != "supplier": continue
		var old_due: float = float(meeting["due_minute"])
		var time_of_day: float = fmod(old_due, MINUTES_PER_DAY)
		if time_of_day < 120.0 or time_of_day >= 1320.0: continue
		# Expired commitments still expire normally; migration is not a free retry.
		if minute > old_due + _meeting_grace(meeting): continue
		meeting["status"] = "migrating"
		meeting["due_minute"] = next_supplier_minute(maxf(old_due, minute + 60.0))
		meeting["status"] = "scheduled"
		moved_ids.append(int(meeting["id"]))
	if not moved_ids.is_empty():
		var retained: Array[Dictionary] = []
		for actor: Dictionary in world_state.get("meeting_walks", []):
			if not moved_ids.has(int(actor["id"])): retained.append(actor)
		world_state["meeting_walks"] = retained
	return moved_ids.size()

func _migrate_contact_timing() -> void:
	# Save v2 remains compatible: new saves persist the deadline, and older
	# saves derive one once from their last successful handoff without rerolling.
	for contact: Dictionary in contacts:
		if contact.has("next_request_minute"): continue
		var last_sale: float = float(contact["last_sale_minute"])
		var quantity: int = 1
		for meeting: Dictionary in meetings:
			if meeting["contact_id"] == contact["id"] and meeting["status"] == "completed" and meeting["type"] == "client":
				quantity = int(meeting["quantity"])
		contact["last_order_quantity"] = quantity
		var retry_at: float = 0.0
		if last_sale >= 0.0:
			retry_at = last_sale + REORDER_MINUTES + maxf(0.0, quantity - 1) * 30.0
		elif contact["id"] == "milo" and tutorial_step >= 3:
			contact["last_sale_minute"] = 600.0
			retry_at = 600.0 + FIRST_FOLLOWUP_MINUTES
		for message: Dictionary in inbox:
			if message["contact_id"] != contact["id"]: continue
			if message["status"] == "new" and float(message["created_minute"]) < retry_at:
				message["status"] = "expired"
			else:
				retry_at = maxf(retry_at, float(message["created_minute"]) + REQUEST_RETRY_MINUTES)
		contact["next_request_minute"] = retry_at

func _validate_save(state: Dictionary) -> bool:
	if int(state.get("version", -1)) != Data.SAVE_VERSION: return false
	if state.has("calendar_version") and not _integer_range(state["calendar_version"], 1, 1): return false
	for key: String in ["cash", "tuition_remaining", "health", "hunger", "energy", "heat", "reputation", "minute", "tutorial_step", "missed_classes", "flower_quality", "dime_quality", "total_sales", "total_earned", "classes_attended", "parties_hosted", "last_party_day", "next_id", "class_resolved_through", "next_message_minute"]:
		if not state.has(key) or not (state[key] is float or state[key] is int): return false
		if not is_finite(float(state[key])) or float(state[key]) < 0.0: return false
	if str(state.get("status", "")) not in ["playing", "won", "lost"]: return false
	if int(state["tutorial_step"]) > 3 or float(state["minute"]) > 144000000.0: return false
	if float(state["tuition_remaining"]) > Data.STARTING_TUITION: return false
	for key: String in ["health", "hunger", "energy", "heat"]:
		if float(state[key]) > 100.0: return false
	if float(state["flower_quality"]) > 1.0 or float(state["dime_quality"]) > 1.0: return false
	if not state.get("inventory") is Dictionary: return false
	for item: String in Data.ITEMS:
		var count: Variant = state["inventory"].get(item)
		if not (count is float or count is int) or float(count) < 0.0 or float(count) > 10000.0 or fmod(float(count), 1.0) != 0.0: return false
	for key: String in ["contacts", "inbox", "meetings"]:
		if not state.get(key) is Array or state[key].size() > 1000: return false
		for entry: Variant in state[key]:
			if not entry is Dictionary: return false
	for contact: Dictionary in state["contacts"]:
		if not _has_keys(contact, ["id", "name", "relationship", "sales", "last_sale_minute"]): return false
		if not _numeric_range(contact["relationship"], 0.0, 100.0): return false
		if not _numeric_range(contact["sales"], 0.0, 10000000.0) or not _numeric_range(contact["last_sale_minute"], -1.0, 144000000.0): return false
		if contact.has("next_request_minute") and not _numeric_range(contact["next_request_minute"], 0.0, 144000000.0): return false
		if contact.has("last_order_quantity") and not _numeric_range(contact["last_order_quantity"], 1.0, 99.0): return false
		for field: String in ["next_outreach_minute", "last_text_minute"]:
			if contact.has(field) and not _numeric_range(contact[field], -1.0 if field == "last_text_minute" else 0.0, 144000000.0): return false
		for field: String in ["blocked", "_informant", "_sting_triggered"]:
			if contact.has(field) and not contact[field] is bool: return false
		if contact.has("last_reply") and not contact["last_reply"] is String: return false
	for message: Dictionary in state["inbox"]:
		if not _has_keys(message, ["id", "contact_id", "contact_name", "quantity", "text", "status", "created_minute", "expires_minute", "suggested_price"]): return false
		if not _numeric_range(message["quantity"], 1.0, 99.0) or not _numeric_range(message["expires_minute"], 0.0, 144000000.0): return false
		if message.has("max_price") and not _numeric_range(message["max_price"], 12.0, 40.0): return false
		if message.has("type") and str(message["type"]) not in ["client", "supplier_callback"]: return false
		if message.get("type", "") == "supplier_callback":
			if not _numeric_range(message.get("tier"), 0.0, 2.0) or not _numeric_range(message.get("bundles"), 1.0, 12.0): return false
			if message.has("obligation_id") and not _integer_range(message["obligation_id"], 1, 100000000): return false
			if message.has("location_id") and not _valid_location(str(message["location_id"])): return false
	for meeting: Dictionary in state["meetings"]:
		if not _has_keys(meeting, ["id", "type", "contact_id", "contact_name", "location_id", "due_minute", "quantity", "price", "cost", "tier", "quality", "status", "created_minute"]): return false
		if str(meeting["type"]) not in ["client", "supplier"] or not _valid_location(str(meeting["location_id"])): return false
		if not _numeric_range(meeting["quantity"], 1.0, 99.0) or not _numeric_range(meeting["due_minute"], 0.0, 144000000.0): return false
		if not _numeric_range(meeting["price"], 0.0, 1000.0) or not _numeric_range(meeting["cost"], 0.0, 100000.0): return false
		if meeting["type"] == "supplier" and not _integer_range(meeting["tier"], 0, 2): return false
		if meeting.has("obligation_id") and not _integer_range(meeting["obligation_id"], 1, 100000000): return false
	return _validate_social_save(state) and _validate_party_pressure_save(state) and _validate_supplier_party_save(state)

func _validate_supplier_party_save(state: Dictionary) -> bool:
	if state.has("supplier_progress"):
		if not state["supplier_progress"] is Array or state["supplier_progress"].size() != 3: return false
		for entry: Variant in state["supplier_progress"]:
			if not entry is Dictionary or not entry.get("unlocked") is bool or not entry.get("referral_received") is bool: return false
			if not _numeric_range(entry.get("next_order_minute"), 0.0, 144002880.0) or not _numeric_range(entry.get("retry_minute"), 0.0, 144001440.0): return false
			if not _integer_range(entry.get("successful_meetings"), 0, 10000000) or not _integer_range(entry.get("interview_stage"), 0, 2): return false
			if not _integer_range(entry.get("orders_placed", 0), 0, 10000000): return false
		if not bool(state["supplier_progress"][0]["unlocked"]): return false
	if not _integer_range(state.get("last_party_invite_day", 0), 0, 100000): return false
	var invitations: Variant = state.get("npc_party_invites", [])
	if not invitations is Array or invitations.size() > 12: return false
	var ids: Dictionary = {}
	var known: Dictionary = {}
	for contact: Dictionary in state["contacts"]: known[str(contact["id"])] = true
	for invite: Variant in invitations:
		if not invite is Dictionary or not _integer_range(invite.get("id"), 1, 100000000): return false
		if ids.has(int(invite["id"])): return false
		ids[int(invite["id"])] = true
		if not invite.get("host_id") is String or not known.has(invite["host_id"]): return false
		if not invite.get("host_name") is String or not invite.get("text") is String or not invite.get("supplier_present") is bool: return false
		if invite.get("location_id") != "deerfield_social" or invite.get("status") not in ["new", "accepted", "active", "ended", "expired", "declined"]: return false
		if not _numeric_range(invite.get("start_minute"), 0.0, 144002880.0) or not _numeric_range(invite.get("end_minute"), 0.0, 144003060.0): return false
		if float(invite["end_minute"]) - float(invite["start_minute"]) != 180.0 or fmod(float(invite["start_minute"]), MINUTES_PER_DAY) != 1110.0: return false
	return true

func _validate_party_pressure_save(state: Dictionary) -> bool:
	for field: String in ["pursuit_incidents", "consecutive_location_meetings"]:
		if not _integer_range(state.get(field, 0), 0, 10000000): return false
	var last_location: Variant = state.get("last_meeting_location", "")
	if not last_location is String or (last_location != "" and not _valid_location(last_location)): return false
	var areas: Variant = state.get("police_pressure", {})
	if not areas is Dictionary or areas.size() > Data.LOCATIONS.size(): return false
	for location_id: Variant in areas:
		if not location_id is String or not _valid_location(location_id): return false
		var area: Variant = areas[location_id]
		if not area is Dictionary: return false
		if not _integer_range(area.get("watch_level"), 0, 2) or not _integer_range(area.get("incident_count"), 0, 10000000): return false
		if not _numeric_range(area.get("last_bust_minute"), -1.0, 144000000.0) or not _numeric_range(area.get("expires_minute"), 0.0, 144001440.0): return false
	var party: Variant = state.get("active_party", {})
	if not party is Dictionary: return false
	if party.is_empty(): return true
	if party.get("mode", "player") not in ["player", "npc"] or party.get("location_id", "home") not in ["home", "deerfield_social"]: return false
	if party.has("supplier_present") and not party["supplier_present"] is bool: return false
	if not _integer_range(party.get("id"), 1, 100000000) or not _integer_range(party.get("night_day"), 0, 100000): return false
	if not _numeric_range(party.get("start_minute"), 0.0, 144000000.0) or not _numeric_range(party.get("end_minute"), 0.0, 144000180.0): return false
	var start: float = float(party["start_minute"])
	var end: float = float(party["end_minute"])
	if end <= start or end - start > 180.0: return false
	var start_hour: float = fmod(start, MINUTES_PER_DAY)
	if start_hour >= 120.0 and start_hour < 1020.0: return false
	var closes: float = floorf(start / MINUTES_PER_DAY) * MINUTES_PER_DAY + (120.0 if start_hour < 120.0 else 1560.0)
	if end > closes or party.get("status") not in ["active", "ended"]: return false
	if not party.get("guests") is Array or party["guests"].size() > 9: return false
	var known: Dictionary = {}
	for contact: Dictionary in state["contacts"]: known[str(contact["id"])] = true
	var seen: Dictionary = {}
	var contact_guests: int = 0
	for guest: Variant in party["guests"]:
		if not guest is Dictionary or not guest.get("contact_id") is String or not guest.get("name") is String: return false
		var contact_id: String = guest["contact_id"]
		if guest.has("supplier") and not guest["supplier"] is bool: return false
		if bool(guest.get("supplier", false)):
			if contact_id != "supplier_1" or guest.get("purchased", true): return false
		else:
			if not known.has(contact_id): return false
			contact_guests += 1
		if contact_guests > 8 or seen.has(contact_id) or guest["name"].length() > 1000: return false
		seen[contact_id] = true
		if not _numeric_range(guest.get("arrival_minute"), start, end): return false
		if guest.get("status") not in ["invited", "inside", "left"]: return false
		for flag: String in ["arrived", "chatted", "purchased"]:
			if not guest.get(flag) is bool: return false
		if (guest["chatted"] or guest["purchased"] or guest["status"] == "inside") and not guest["arrived"]: return false
	return true

func _validate_social_save(state: Dictionary) -> bool:
	var intro_data: Variant = state.get("introductions", [])
	var callback_data: Variant = state.get("callbacks", [])
	var street_data: Variant = state.get("street_npcs", {})
	if not intro_data is Array or intro_data.size() > 128: return false
	if not callback_data is Array or callback_data.size() > 80: return false
	if not street_data is Dictionary or street_data.size() > 128: return false
	for entry: Variant in intro_data:
		if not entry is Dictionary or not _has_keys(entry, ["id", "name", "referrer_id", "referrer_name", "status", "created_minute", "text", "who_answer", "connection_answer", "_informant", "_cover_course", "_cover_hangout"]): return false
		if not _numeric_range(entry["id"], 1.0, 100000000.0) or not _numeric_range(entry["created_minute"], 0.0, 144000000.0): return false
		if entry["status"] not in ["pending", "accepted", "declined", "blocked"] or not entry["_informant"] is bool: return false
		for field: String in ["name", "referrer_id", "referrer_name", "text", "who_answer", "connection_answer", "_cover_course", "_cover_hangout"]:
			if not entry[field] is String or entry[field].length() > 1000: return false
	for callback: Variant in callback_data:
		if not callback is Dictionary or not _has_keys(callback, ["id", "kind", "contact_id", "contact_name", "due_minute", "tier", "bundles", "status"]): return false
		if callback["kind"] not in ["client", "supplier"] or callback["status"] not in ["pending", "delivered", "cancelled"]: return false
		if not callback["contact_id"] is String or not callback["contact_name"] is String: return false
		if not _numeric_range(callback["id"], 1.0, 100000000.0) or not _numeric_range(callback["due_minute"], 0.0, 144000000.0): return false
		if not _numeric_range(callback["tier"], -1.0, 2.0) or not _numeric_range(callback["bundles"], 1.0, 99.0): return false
		if callback["kind"] == "supplier" and int(callback["tier"]) < 0: return false
		if callback.has("obligation_id") and not _integer_range(callback["obligation_id"], 1, 100000000): return false
		if callback.has("location_id") and not _valid_location(str(callback["location_id"])): return false
	for npc_id: Variant in street_data:
		if not npc_id is String or npc_id.is_empty() or npc_id.length() > 80: return false
		var npc: Variant = street_data[npc_id]
		if not npc is Dictionary or not _has_keys(npc, ["name", "response", "status", "next_offer_minute", "last_sale_minute", "sales", "contact_id", "text"]): return false
		if npc["response"] not in ["sale", "refusal", "report"] or npc["status"] not in ["idle", "sold", "reporting", "reported"]: return false
		if not npc["name"] is String or not npc["contact_id"] is String or not npc["text"] is String: return false
		if not _numeric_range(npc["next_offer_minute"], 0.0, 144000000.0) or not _numeric_range(npc["last_sale_minute"], -1.0, 144000000.0): return false
		if not _numeric_range(npc["sales"], 0.0, 1000000.0): return false
		for field: String in ["dialogue_seed", "talk_count"]:
			if npc.has(field) and not _integer_range(npc[field], 0, 1000000000): return false
	return true

func _has_keys(value: Dictionary, keys: Array) -> bool:
	for key: String in keys:
		if not value.has(key): return false
	return true

func _numeric_range(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

func _integer_range(value: Variant, minimum: int, maximum: int) -> bool:
	return _numeric_range(value, float(minimum), float(maximum)) and fmod(float(value), 1.0) == 0.0

func _sanitize_world_state(value: Variant) -> Dictionary:
	var fallback: Dictionary = {"position": [20.0,0.3,50.0], "interior": ""}
	if not value is Dictionary: return fallback
	var result: Dictionary = fallback.duplicate(true)
	var interior: String = str(value.get("interior", ""))
	var rooms: Array[String] = ["home","market","cafe","classroom","library","deerfield_social"]
	if interior != "" and not rooms.has(interior): return fallback
	var position_data: Variant = value.get("position", [])
	if not _valid_saved_position(position_data,interior): return fallback
	result["position"] = position_data.duplicate()
	result["interior"] = interior
	for key: String in ["driving","stolen_vehicle","pursuit","skateboarding"]:
		result[key] = bool(value.get(key,false)) if value.get(key,false) is bool else false
	if interior != "":
		result["driving"] = false
		result["skateboarding"] = false
	if _valid_saved_position(value.get("vehicle_owned_pos",[]),""):
		result["vehicle_owned_pos"] = value["vehicle_owned_pos"].duplicate()
	if _numeric_range(value.get("car_rotation",0.0),-10000.0,10000.0): result["car_rotation"] = float(value.get("car_rotation",0.0))
	result["pursuit_state"] = _sanitize_pursuit_state(value.get("pursuit_state",{}))
	result["meeting_walks"] = _sanitize_meeting_walks(value.get("meeting_walks",[]))
	result["informant_runs"] = _sanitize_informant_runs(value.get("informant_runs",[]))
	result["party_walks"] = _sanitize_party_walks(value.get("party_walks",[]))
	result["supplier_walks"] = _sanitize_supplier_walks(value.get("supplier_walks",[]))
	return result

func _sanitize_supplier_walks(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array or value.size() > 2: return result
	var seen: Dictionary = {}
	for entry: Variant in value:
		if not entry is Dictionary or entry.get("id") not in ["supplier_1", "supplier_2"] or entry.get("state") not in ["approaching", "waiting"]: continue
		if seen.has(entry["id"]) or not _valid_saved_position(entry.get("position", []), ""): continue
		seen[entry["id"]] = true
		result.append({"id":entry["id"],"state":entry["state"],"position":entry["position"].duplicate()})
	return result

func _sanitize_party_walks(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array or value.size() > 9: return result
	var seen: Dictionary = {}
	for entry: Variant in value:
		if not entry is Dictionary or not entry.get("contact_id") is String: continue
		var contact_id: String = entry["contact_id"]
		if contact_id.is_empty() or contact_id.length() > 80 or seen.has(contact_id): continue
		var phase: Variant = entry.get("state")
		if phase not in ["approaching", "inside", "leaving"] or not _integer_range(entry.get("slot"), 0, 8): continue
		var position_ok: bool = _valid_saved_position(entry.get("position", []), "home" if phase == "inside" else "")
		if phase in ["inside", "leaving"]: position_ok = position_ok or _valid_saved_position(entry.get("position", []), "deerfield_social")
		if phase == "leaving": position_ok = position_ok or _valid_saved_position(entry.get("position", []), "home")
		if not position_ok: continue
		seen[contact_id] = true
		result.append({"contact_id": contact_id, "state": phase, "position": entry["position"].duplicate(), "slot": int(entry["slot"])})
	return result

func _sanitize_informant_runs(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array or value.size() > 57: return result
	var seen: Dictionary = {}
	for entry: Variant in value:
		if not entry is Dictionary or not entry.get("id") is String: continue
		var npc_id: String = entry["id"]
		if npc_id.length() != 10 or not npc_id.begins_with("citizen_") or not npc_id.substr(8).is_valid_int(): continue
		var number: int = npc_id.substr(8).to_int()
		if number < 0 or number >= 57 or npc_id != "citizen_%02d" % number or seen.has(npc_id): continue
		if not _valid_saved_position(entry.get("position", []), "") or not _valid_saved_position(entry.get("report_position", []), ""): continue
		if not entry.get("campus") is bool: continue
		seen[npc_id] = true
		result.append({"id": npc_id, "position": entry["position"].duplicate(), "report_position": entry["report_position"].duplicate(), "campus": entry["campus"]})
	return result

func _sanitize_meeting_walks(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array or value.size() > 10: return result
	var seen_ids: Dictionary = {}
	for entry: Variant in value:
		if not entry is Dictionary: continue
		if not _numeric_range(entry.get("id"),1.0,100000000.0) or fmod(float(entry["id"]),1.0) != 0.0: continue
		var meeting_id: int = int(entry["id"])
		if seen_ids.has(meeting_id): continue
		if not _valid_saved_position(entry.get("position",[]),"") or not _valid_saved_position(entry.get("target",[]),""): continue
		if not entry.get("state") is String or entry["state"] not in ["approaching","waiting","departing"]: continue
		if not _numeric_range(entry.get("due"),0.0,144000000.0): continue
		# Very long routes can begin before the day-one clock origin.
		if not _numeric_range(entry.get("start_minute"),-1440.0,float(entry["due"])): continue
		seen_ids[meeting_id] = true
		result.append({"id":meeting_id,"position":entry["position"].duplicate(),"state":str(entry["state"]),"start_minute":float(entry["start_minute"]),"due":float(entry["due"]),"target":entry["target"].duplicate()})
	return result

func _sanitize_pursuit_state(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("officers") is Array: return {}
	if value["officers"].size() not in [7, 10]: return {}
	for officer: Variant in value["officers"]:
		if not officer is Dictionary or not _valid_saved_position(officer.get("position",[]),""): return {}
		if not _numeric_range(officer.get("hp"),0.0,150.0): return {}
		if not _numeric_range(officer.get("alert"),0.0,60.0) or not _numeric_range(officer.get("stun"),0.0,60.0): return {}
		if not _numeric_range(officer.get("index"),0.0,1000.0): return {}
	if not _numeric_range(value.get("arrest_seconds"),0.0,10.0): return {}
	if not _numeric_range(value.get("escape_seconds"),0.0,100000000.0): return {}
	if not _numeric_range(value.get("crime_age"),0.0,10000000.0): return {}
	if not _valid_saved_position(value.get("crime_position",[]),""): return {}
	return value.duplicate(true)

func _valid_saved_position(value: Variant, interior: String) -> bool:
	if not value is Array or value.size() != 3: return false
	for coordinate: Variant in value:
		if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)): return false
	if float(value[1]) < -1.0 or float(value[1]) > 15.0: return false
	if interior == "": return absf(float(value[0])) <= 153.5 and absf(float(value[2])) <= 125.5
	var rooms: Array[String] = ["home","market","cafe","classroom","library","deerfield_social"]
	var center: float = 600.0+float(rooms.find(interior))*80.0
	return absf(float(value[0])-center) <= 10.0 and absf(float(value[2])) <= 8.0
