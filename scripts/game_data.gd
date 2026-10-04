extends RefCounted
## Small, fictional economy expressed in game units, never real-world quantities.

const SAVE_VERSION: int = 2
const STARTING_TUITION: float = 3500.0
const BACKPACK_CAPACITY: float = 14.0
const BAGS_PER_BUNDLE: int = 7
const ITEMS: Dictionary = {
	"flower": {"name": "Flower bundle", "weight": 0.8, "price": 0, "description": "A fictional game bundle. Split into seven dime bags."},
	"dime_bag": {"name": "Dime bag", "weight": 0.12, "price": 0, "description": "One abstract sale item. Quality carries over from its bundle."},
	"sandwich": {"name": "Sandwich", "weight": 0.45, "price": 8, "description": "Restores 48 hunger and a little health."},
	"energy_drink": {"name": "Energy drink", "weight": 0.35, "price": 6, "description": "Restores 65 energy and 8 hunger."},
	"skateboard": {"name": "Skateboard", "weight": 2.0, "price": 65, "description": "Your everyday ride. Toggle it outside a car."},
	"pistol": {"name": "Handgun", "weight": 1.5, "price": 380, "description": "A dangerous late-game purchase. Gunfire immediately draws police."},
	"ammo": {"name": "Ammunition", "weight": 0.025, "price": 3, "description": "One shot. Violence is risky and never required to graduate."},
}
const SUPPLIERS: Array[Dictionary] = [
	{"tier": 0, "name": "Rae", "title": "The local connection", "reputation_required": 0, "bundle_price": 46, "quality": 0.72, "risk": 0.05, "max_bundles": 4, "location_id": "west_overlook"},
	{"tier": 1, "name": "Sable", "title": "The district connection", "reputation_required": 0, "bundle_price": 40, "quality": 0.87, "risk": 0.12, "max_bundles": 8, "location_id": "service_lane"},
	{"tier": 2, "name": "The Regent", "title": "The city connection", "reputation_required": 0, "bundle_price": 33, "quality": 0.98, "risk": 0.20, "max_bundles": 12, "location_id": "east_trail"},
]
const SUPPLIER_SITES: Array[String] = ["west_overlook", "service_lane", "east_trail"]
const LOCATIONS: Array[Dictionary] = [
	{"id": "campus_quad", "name": "Campus quad", "district": "Campus"},
	{"id": "library", "name": "Library steps", "district": "Campus"},
	{"id": "cafe", "name": "Takeout patio", "district": "Commercial"},
	{"id": "home", "name": "Deerfield apartment", "district": "Residential"},
	{"id": "market", "name": "College Square market", "district": "Commercial"},
	{"id": "car_park", "name": "West parking lot", "district": "Campus"},
	{"id": "classroom", "name": "Lecture hall entrance", "district": "Campus"},
	{"id": "supplier", "name": "Service yard", "district": "Commercial"},
	{"id": "auto_dealer", "name": "Second Hand Motors", "district": "Commercial"},
	{"id": "skate_park", "name": "Deerfield skate spot", "district": "Residential"},
	{"id": "bus_stop", "name": "Baseline transit", "district": "Commercial"},
	{"id": "residence", "name": "Student residence", "district": "Campus"},
	{"id": "west_overlook", "name": "West trail overlook", "district": "Campus"},
	{"id": "service_lane", "name": "Freight lane", "district": "Commercial"},
	{"id": "east_trail", "name": "East trail shelter", "district": "Residential"},
	{"id": "deerfield_social", "name": "Deerfield neighbors", "district": "Residential"},
]
const CONTACT_NAMES: Array[String] = ["Milo", "Jules", "Nia", "Dev", "Avery", "Sam", "Tessa", "Rowan", "Casey", "Morgan", "Lee", "Emery"]
const CONTACT_COURSES: Array[String] = ["architecture", "culinary arts", "animation", "computer science", "photography", "music production", "design", "journalism", "accounting", "film", "engineering", "hospitality"]
const CONTACT_HANGOUTS: Array[String] = ["the library steps", "the takeout patio", "the campus quad", "the west parking lot", "College Square market", "Deerfield apartments"]
const STREET_GREETINGS: Array[String] = ["Hey. Taking a break too?", "Oh, hey. How's your day going?", "Hey there. What's up?", "Hi. Feels like everyone's in a hurry today.", "Hey. Haven't I seen you around campus?", "What's going on?", "Hi. You caught me between things.", "Hey, good to see another familiar face."]
const STREET_SMALLTALK: Array[String] = ["I've got three assignments open and somehow none of them are getting done.", "I came out for coffee and forgot what else I needed.", "The music outside residence was actually pretty good last night.", "My friends are having a very serious argument about where to get lunch.", "I'm trying to make my grocery money last until Friday.", "I keep saying I'll get an early night. It never happens.", "Somebody left an umbrella in every classroom except the one I was in.", "Nice weather for a walk. Better than staring at another screen.", "I'm meeting a friend who measures five minutes very differently than I do.", "Have you tried the takeout patio? The queue looked manageable earlier.", "I finally fixed my bike. Now I've misplaced the lock.", "My playlist has been the same six songs all week."]
const STREET_BUY_REPLIES: Array[String] = ["Yeah, one works. Here you go. We can swap numbers.", "Wasn't on my list, but sure. Just one, thanks. Save my number.", "Okay, one sounds good. Give me your number for next time.", "I've got time. Let's do one. We should keep in touch.", "Thanks, I appreciate it. Save my number if you like.", "One is plenty for now. Here, let's exchange numbers."]
const STREET_REFUSE_REPLIES: Array[String] = ["Not today, thanks. Maybe another time.", "I'm set for now. Appreciate you asking.", "Wrong time for me, sorry.", "I'll pass. I've got somewhere to be.", "I'm watching my spending today. No thanks.", "No, but have a good evening.", "Not what I'm after right now.", "I'm good. Catch you around."]
const STREET_REPORT_REPLIES: Array[String] = ["No. I'm going to speak to an officer about this.", "That makes me uncomfortable. I'm finding a patrol.", "Leave me alone. I'm reporting this.", "I don't want any part of that. An officer should hear about it."]

static func contact_background(contact_name: String) -> Dictionary:
	var index: int = CONTACT_NAMES.find(contact_name)
	if index < 0: index = posmod(contact_name.hash(), CONTACT_COURSES.size())
	var course: String = CONTACT_COURSES[index % CONTACT_COURSES.size()]
	var hangout: String = CONTACT_HANGOUTS[index % CONTACT_HANGOUTS.size()]
	return {"course": course, "hangout": hangout, "bio": "%s studies %s and usually hangs out at %s." % [contact_name, course, hangout]}

static func item_name(item: String) -> String:
	return str(ITEMS.get(item, {}).get("name", item.capitalize()))

static func location_name(location_id: String) -> String:
	for location: Dictionary in LOCATIONS:
		if location["id"] == location_id:
			return str(location["name"])
	return "Unknown location"
