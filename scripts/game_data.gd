extends RefCounted
## Small, fictional economy expressed in game units, never real-world quantities.

const SAVE_VERSION: int = 2
const STARTING_TUITION: float = 3500.0
const BACKPACK_CAPACITY: float = 14.0
const BAGS_PER_BUNDLE: int = 6
const ITEMS: Dictionary = {
	"flower": {"name": "Flower bundle", "weight": 0.8, "price": 0, "description": "A fictional game bundle. Split into six dime bags."},
	"dime_bag": {"name": "Dime bag", "weight": 0.12, "price": 0, "description": "One abstract sale item. Quality carries over from its bundle."},
	"sandwich": {"name": "Sandwich", "weight": 0.45, "price": 8, "description": "Restores 48 hunger and a little health."},
	"energy_drink": {"name": "Energy drink", "weight": 0.35, "price": 6, "description": "Restores 65 energy and 8 hunger."},
	"skateboard": {"name": "Skateboard", "weight": 2.0, "price": 65, "description": "Your everyday ride. Toggle it outside a car."},
	"pistol": {"name": "Handgun", "weight": 1.5, "price": 380, "description": "A dangerous late-game purchase. Gunfire immediately draws police."},
	"ammo": {"name": "Ammunition", "weight": 0.025, "price": 3, "description": "One shot. Violence is risky and never required to graduate."},
}
const SUPPLIERS: Array[Dictionary] = [
	{"tier": 0, "name": "Rae", "title": "The local connection", "reputation_required": 0, "bundle_price": 46, "quality": 0.72, "risk": 0.05, "max_bundles": 4, "location_id": "car_park"},
	{"tier": 1, "name": "Sable", "title": "The district connection", "reputation_required": 8, "bundle_price": 40, "quality": 0.87, "risk": 0.12, "max_bundles": 8, "location_id": "car_park"},
	{"tier": 2, "name": "The Regent", "title": "The city connection", "reputation_required": 22, "bundle_price": 33, "quality": 0.98, "risk": 0.20, "max_bundles": 12, "location_id": "car_park"},
]
const LOCATIONS: Array[Dictionary] = [
	{"id": "campus_quad", "name": "Campus quad", "district": "Campus"},
	{"id": "library", "name": "Library steps", "district": "Campus"},
	{"id": "cafe", "name": "Takeout patio", "district": "Commercial"},
	{"id": "home", "name": "Deerfield apartment", "district": "Residential"},
	{"id": "market", "name": "College Square market", "district": "Commercial"},
	{"id": "car_park", "name": "West parking lot", "district": "Commercial"},
]
const CONTACT_NAMES: Array[String] = ["Milo", "Jules", "Nia", "Dev", "Avery", "Sam", "Tessa", "Rowan", "Casey", "Morgan", "Lee", "Emery"]
const CONTACT_COURSES: Array[String] = ["architecture", "culinary arts", "animation", "computer science", "photography", "music production", "design", "journalism", "accounting", "film", "engineering", "hospitality"]
const CONTACT_HANGOUTS: Array[String] = ["the library steps", "the takeout patio", "the campus quad", "the west parking lot", "College Square market", "Deerfield apartments"]

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
