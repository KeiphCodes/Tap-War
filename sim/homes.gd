class_name LTHomes
extends RefCounted
## Houses built room by room by the families who live in them.
##
## A family designs its house from its own life: how many people and how old,
## what they earn, their personalities, their skills and hobbies, whether a
## grandparent lives with them. Every room and feature has a real price (South
## Dakota, about 2026), and the bank caps what they can borrow, so they trim the
## wish list until it fits. Each choice is written down with the reason.
##
## The house is placed on its own lot by the family: how far back from the street,
## toward which side, and where the garage goes. Like real houses it always faces
## the road. Later in life families remodel and add on: a bedroom for a new baby,
## a first floor bedroom for an aging parent, a finished basement, a workshop.
## Additions that would break the zoning rules need a variance from the mayor.
##
## Lot coordinates here: x runs along the street front (centered on the lot), d is
## the distance back from the street edge of the lot, both in meters.

const M2: float = 10.764          # square feet in a square meter
const FRONT_SETBACK: float = 7.5   # 25 feet, the usual small town rule
const SIDE_SETBACK: float = 1.5    # 5 feet
const REAR_SETBACK: float = 3.0    # 10 feet
const SHELL_PER_SQFT: float = 125.0

## Square feet for each room.
const ROOM_SQFT: Dictionary = {
	"bed": 140, "suite": 240, "ground_bed": 170, "living": 300, "dining": 160, "family": 280,
	"office": 120, "mudroom": 70, "laundry": 60, "den": 220, "sunroom": 180,
	"kitchen_basic": 150, "kitchen_standard": 200, "kitchen_chef": 280,
	"bath_full": 50, "bath_three": 40, "bath_half": 25, "suite_bath": 90,
}
const ROOM_LABEL: Dictionary = {
	"bed": "Bedroom", "suite": "Main bedroom", "ground_bed": "First floor bedroom", "living": "Living room",
	"dining": "Dining room", "family": "Family room", "office": "Office", "mudroom": "Mudroom", "laundry": "Laundry",
	"den": "Den", "sunroom": "Sunroom", "kitchen_basic": "Kitchen", "kitchen_standard": "Kitchen", "kitchen_chef": "Cook's kitchen",
	"bath_full": "Bath", "bath_three": "Shower bath", "bath_half": "Half bath", "suite_bath": "Main bath",
}
## Extra rooms a family may add, in the order they give them up when money is short.
const EXTRA_ROOMS: Array = ["sunroom", "den", "office", "family", "dining", "mudroom", "laundry"]
## Prices in dollars, on top of the shell.
const PRICE: Dictionary = {
	"kitchen_basic": 0, "kitchen_standard": 15000, "kitchen_chef": 45000, "island": 6000, "pantry": 3000,
	"bath_full": 22000, "bath_three": 16000, "bath_half": 9000, "suite_bath": 30000,
	"stall_attached": 18000, "stall_detached": 24000, "workshop": 22000,
	"basement": 30000, "basement_finished": 28000,
	"porch": 12000, "deck": 15000, "patio": 7000, "fence": 9000, "shed": 5000, "garden": 800,
	"greenhouse": 9000, "shelter": 8000, "pool": 55000,
	"siding_vinyl": 0, "siding_wood": 9000, "siding_brick": 26000, "siding_stone": 40000,
	"roof_shingle": 0, "roof_metal": 12000,
	"heat_furnace": 0, "heat_geothermal": 32000, "heat_wood_stove": 5000,
	"fireplace": 7000, "ac": 7500, "solar": 24000,
}
const STYLES: Dictionary = {
	"ranch": {"label": "Ranch", "cost": 1.0, "aspect": 2.0},
	"two_story": {"label": "Two story", "cost": 0.96, "aspect": 1.35},
	"farmhouse": {"label": "Farmhouse", "cost": 1.04, "aspect": 1.5},
	"craftsman": {"label": "Craftsman", "cost": 1.07, "aspect": 1.25},
	"split_level": {"label": "Split level", "cost": 1.02, "aspect": 1.6},
}
const OUTSIDE_LABEL: Dictionary = {
	"porch": "front porch", "deck": "back deck", "patio": "patio", "fence": "fenced back yard", "shed": "garden shed",
	"garden": "vegetable garden", "greenhouse": "greenhouse", "shelter": "storm shelter", "pool": "swimming pool",
}


# ---------------------------------------------------------------- design

static func _t(ctx: Dictionary, k: String) -> float:
	return float(ctx.get("traits", {}).get(k, 50.0))


## A family's house, designed from its life. ctx keys (all optional): adults, kids,
## income (yearly cents), traits, elder (a parent 70 or older lives with them),
## cook, builder, hunter, works_home, head_age, lot (to place it), budget.
static func design(w: LTWorld, ctx: Dictionary) -> Dictionary:
	var adults: int = int(ctx.get("adults", 2))
	var kids: int = int(ctx.get("kids", 0))
	var income: int = int(ctx.get("income", LTMoney.dollars(80000.0)))
	var head_age: int = int(ctx.get("head_age", 35))
	var why: Array = []
	var reach: float = (_t(ctx, "ambition") - _t(ctx, "discipline")) / 100.0 + w.rng.randf_range(-0.2, 0.2)
	var big_budget: bool = income > LTMoney.dollars(110000.0)
	var spec: Dictionary = {"color": w.rng.randi_range(0, 5), "rooms": ["living"], "outside": [], "why": why}
	# bedrooms: a room for the couple, kids share two to a room until they are older
	var beds: int = clampi(1 + maxi(0, adults - 2) + int(ceil(float(kids) / 1.5)), 1, 6)
	if adults >= 2 and kids == 0 and w.rng.randf() < 0.6:
		beds += 1
		why.append("a spare room for guests or a baby to come")
	if reach > 0.25:
		beds += 1
		why.append("one more bedroom than they need, because they want room to grow")
	spec["beds"] = clampi(beds, 1, 6)
	spec["suite"] = adults >= 2 or income > LTMoney.dollars(70000.0)
	spec["ground_bed"] = bool(ctx.get("elder", false))
	if bool(spec["ground_bed"]):
		why.append("a first floor bedroom so a parent who lives with them never has to climb stairs")
	# style
	var style: String = "ranch"
	if head_age >= 55 or bool(ctx.get("elder", false)):
		style = "ranch"
		why.append("a ranch on one floor, to stay in it into old age")
	elif int(spec["beds"]) >= 4 and w.rng.randf() < 0.6:
		style = "two_story"
		why.append("two stories to fit a big family on the lot")
	elif _t(ctx, "sociability") > 60.0 and w.rng.randf() < 0.5:
		style = "farmhouse"
		why.append("a farmhouse with a wide front porch for visiting with neighbors")
	elif _t(ctx, "intelligence") > 62.0 and _t(ctx, "ambition") > 55.0:
		style = "craftsman"
		why.append("a craftsman, for the woodwork and the look of it")
	elif ctx.has("lot") and LTTerrain.slope(w, _lot_mid(ctx["lot"]).x, _lot_mid(ctx["lot"]).y) > 0.05:
		style = "split_level"
		why.append("a split level to follow the slope of the lot")
	spec["style"] = style
	spec["stories"] = 2 if style == "two_story" or style == "farmhouse" and int(spec["beds"]) >= 4 else 1
	# kitchen
	if bool(ctx.get("cook", false)):
		spec["kitchen"] = "chef"
		why.append("a cook's kitchen because cooking is what they love")
	elif income < LTMoney.dollars(50000.0):
		spec["kitchen"] = "basic"
	else:
		spec["kitchen"] = "standard"
	spec["island"] = str(spec["kitchen"]) != "basic" and _t(ctx, "ambition") > 40.0
	spec["pantry"] = kids >= 2 or str(spec["kitchen"]) == "chef"
	# bathrooms: one for every two bedrooms, a half bath for guests
	spec["full"] = maxi(1, int(ceil(float(spec["beds"]) / 2.5)))
	spec["three"] = 0
	spec["half"] = 1 if int(spec["beds"]) >= 3 else 0
	spec["suite_bath"] = bool(spec["suite"]) and (adults >= 2 or reach > 0.0) and int(spec["beds"]) >= 2
	if bool(spec["suite_bath"]) and int(spec["full"]) > 1:
		spec["full"] = int(spec["full"]) - 1
	if kids >= 3:
		why.append("enough bathrooms that school mornings are not a fight")
	# rooms
	var rooms: Array = spec["rooms"]
	if adults >= 2 and (_t(ctx, "sociability") > 50.0 or kids >= 2):
		rooms.append("dining")
	if kids >= 2:
		rooms.append("family")
		why.append("a family room so the kids have a place of their own")
	if bool(ctx.get("works_home", false)) or _t(ctx, "intelligence") > 68.0:
		rooms.append("office")
		why.append("a home office for the work they do at home")
	if bool(ctx.get("hunter", false)) or kids >= 2 or w.rng.randf() < 0.35:
		rooms.append("mudroom")
		if bool(ctx.get("hunter", false)):
			why.append("a mudroom with a chest freezer for hunting season")
	rooms.append("laundry")
	if _t(ctx, "sociability") > 62.0 or (reach > 0.2 and big_budget):
		rooms.append("den")
	if _t(ctx, "kindness") > 60.0 and big_budget and w.rng.randf() < 0.4:
		rooms.append("sunroom")
		why.append("a sunroom for the long winters")
	# garage, attached on the prairie where winters are long
	spec["garage"] = 2 if adults >= 2 else 1
	if reach > 0.3 and w.rng.randf() < 0.5:
		spec["garage"] = 3
	spec["garage_kind"] = "attached"
	spec["workshop"] = bool(ctx.get("builder", false))
	if bool(spec["workshop"]):
		why.append("a workshop in the garage for building and fixing things")
	# basement: storage, a playroom, and the safest place in a tornado
	spec["basement"] = w.rng.randf() < 0.6 or _t(ctx, "risk") < 35.0
	spec["basement_finished"] = bool(spec["basement"]) and kids >= 2 and big_budget
	if bool(spec["basement_finished"]):
		spec["three"] = 1
	# outside
	var out: Array = spec["outside"]
	if style == "farmhouse" or style == "craftsman" or _t(ctx, "sociability") > 55.0:
		out.append("porch")
	if _t(ctx, "sociability") > 45.0:
		out.append("deck" if income > LTMoney.dollars(60000.0) else "patio")
	if kids > 0 and kids <= 3 or _t(ctx, "sociability") < 35.0:
		out.append("fence")
	if _t(ctx, "discipline") > 50.0 or _t(ctx, "kindness") > 60.0:
		out.append("garden")
	if out.has("garden") and _t(ctx, "discipline") > 68.0 and big_budget:
		out.append("greenhouse")
	if not bool(spec["basement"]) or out.has("garden"):
		out.append("shed")
	if not bool(spec["basement"]) and _t(ctx, "risk") < 45.0:
		out.append("shelter")
		why.append("a storm shelter, because there is no basement to run to")
	if _t(ctx, "greed") + _t(ctx, "ambition") > 140.0 and income > LTMoney.dollars(160000.0):
		out.append("pool")
	# materials and systems
	spec["siding"] = "vinyl"
	if _t(ctx, "discipline") > 65.0 and big_budget:
		spec["siding"] = "brick"
	elif _t(ctx, "ambition") > 70.0 and income > LTMoney.dollars(140000.0):
		spec["siding"] = "stone"
	elif _t(ctx, "kindness") > 60.0 and income > LTMoney.dollars(70000.0):
		spec["siding"] = "wood"
	spec["roof"] = "metal" if _t(ctx, "discipline") > 60.0 else "shingle"
	if str(spec["roof"]) == "metal":
		why.append("a metal roof that stands up to hail")
	spec["heat"] = "furnace"
	if _t(ctx, "intelligence") > 65.0 and _t(ctx, "discipline") > 55.0 and big_budget:
		spec["heat"] = "geothermal"
		why.append("geothermal heat, which costs more now and less every winter after")
	elif bool(ctx.get("hunter", false)) or _t(ctx, "risk") > 65.0:
		spec["heat"] = "wood_stove"
	spec["fireplace"] = _t(ctx, "sociability") > 55.0 and income > LTMoney.dollars(75000.0)
	spec["ac"] = income > LTMoney.dollars(45000.0)
	spec["solar"] = _t(ctx, "intelligence") > 70.0 and big_budget
	_sync(spec)
	# trim to what the bank will lend and the family can put down
	var budget: int = int(ctx.get("budget", maxi(LTMoney.dollars(180000.0), income * 4)))
	_trim(spec, budget)
	if ctx.has("lot"):
		place(w, ctx["lot"], spec, ctx)
	return spec


static func _lot_mid(l: Dictionary) -> Vector2:
	return Vector2((float(l["x0"]) + float(l["x1"])) * 0.5, (float(l["z0"]) + float(l["z1"])) * 0.5)


## Gives up wishes, least needed first, until the house fits the budget.
static func _trim(spec: Dictionary, budget: int) -> void:
	var steps: Array = [
		["pool", "the pool"], ["sunroom", "the sunroom"], ["stone", "stone walls"], ["solar", "solar panels"],
		["geothermal", "geothermal heat"], ["greenhouse", "the greenhouse"], ["chef", "the cook's kitchen"], ["den", "the den"],
		["basement_finished", "finishing the basement"], ["brick", "brick walls"], ["deck", "the deck"], ["metal", "the metal roof"],
		["fireplace", "the fireplace"], ["third_stall", "a third garage stall"], ["wood", "wood siding"], ["office", "the office"],
		["island", "the kitchen island"], ["family", "the family room"], ["dining", "the dining room"], ["suite_bath", "the main bath"],
		["half", "the half bath"], ["porch", "the porch"], ["workshop", "the workshop"], ["basement", "the basement"],
		["stall", "a garage stall"], ["spare_bed", "a bedroom"],
	]
	var given: Array = []
	for s in steps:
		if home_cost(spec) <= budget:
			break
		var k: String = str(s[0])
		var did: bool = true
		match k:
			"pool", "greenhouse", "deck", "porch":
				did = spec["outside"].has(k)
				spec["outside"].erase(k)
				if k == "deck" and did:
					spec["outside"].append("patio")
			"sunroom", "den", "office", "family", "dining":
				did = spec["rooms"].has(k)
				spec["rooms"].erase(k)
			"stone", "brick", "wood":
				did = str(spec["siding"]) == k
				if did:
					spec["siding"] = "vinyl"
			"solar", "fireplace", "island", "suite_bath", "workshop", "basement_finished":
				did = bool(spec[k])
				spec[k] = false
			"geothermal":
				did = str(spec["heat"]) == "geothermal"
				if did:
					spec["heat"] = "furnace"
			"chef":
				did = str(spec["kitchen"]) == "chef"
				if did:
					spec["kitchen"] = "standard"
			"metal":
				did = str(spec["roof"]) == "metal"
				spec["roof"] = "shingle"
			"third_stall":
				did = int(spec["garage"]) >= 3
				if did:
					spec["garage"] = 2
			"stall":
				did = int(spec["garage"]) >= 2
				if did:
					spec["garage"] = int(spec["garage"]) - 1
			"half":
				did = int(spec["half"]) > 0
				spec["half"] = 0
			"basement":
				did = bool(spec["basement"])
				spec["basement"] = false
				spec["basement_finished"] = false
				spec["three"] = 0
			"spare_bed":
				did = int(spec["beds"]) > 1
				if did:
					spec["beds"] = int(spec["beds"]) - 1
		if did:
			given.append(str(s[1]))
		_sync(spec)
	if not given.is_empty():
		spec["why"].append("gave up %s to stay within what the bank would lend" % _join(given.slice(0, 4)))


static func _join(a: Array) -> String:
	if a.size() <= 1:
		return "".join(a)
	return ", ".join(a.slice(0, a.size() - 1)) + " and " + str(a[a.size() - 1])


## Keeps the plain summary keys that the rest of the game reads.
static func _sync(spec: Dictionary) -> void:
	spec["baths"] = float(int(spec.get("full", 1)) + int(spec.get("three", 0)) + (1 if bool(spec.get("suite_bath", false)) else 0)) + 0.5 * float(int(spec.get("half", 0)))


## Turns an older plain spec (beds, baths, stories, garage, basement) into a full one.
static func upgrade(spec: Dictionary) -> Dictionary:
	if spec.has("style"):
		return spec
	var s: Dictionary = spec.duplicate(true)
	var beds: int = int(s.get("beds", 3))
	s["style"] = "two_story" if int(s.get("stories", 1)) == 2 else "ranch"
	s["suite"] = beds >= 2
	s["ground_bed"] = false
	var b: float = float(s.get("baths", 1.0))
	s["half"] = 1 if fmod(b, 1.0) > 0.1 else 0
	s["full"] = maxi(1, int(b))
	s["three"] = 0
	s["suite_bath"] = false
	s["kitchen"] = "standard"
	s["island"] = false
	s["pantry"] = false
	s["rooms"] = ["living", "dining", "laundry"] if beds >= 3 else ["living", "laundry"]
	s["garage"] = int(s.get("garage", 1))
	s["garage_kind"] = "attached"
	s["workshop"] = false
	s["basement"] = bool(s.get("basement", false))
	s["basement_finished"] = false
	s["outside"] = ["porch"] if beds >= 3 else []
	s["siding"] = "vinyl"
	s["roof"] = "shingle"
	s["heat"] = "furnace"
	s["fireplace"] = false
	s["ac"] = true
	s["solar"] = false
	s["color"] = int(s.get("color", 0))
	s["why"] = []
	_sync(s)
	return s


# ---------------------------------------------------------------- rooms, size and price

## The rooms on each floor: [{"name", "rooms": [room keys]}], ground floor first.
static func floors(spec: Dictionary) -> Array:
	var sp: Dictionary = upgrade(spec)
	var ground: Array = ["living", "kitchen_%s" % sp["kitchen"]]
	var upper: Array = []
	var bedrooms: Array = []
	if bool(sp["suite"]):
		bedrooms.append("suite")
		if bool(sp["suite_bath"]):
			bedrooms.append("suite_bath")
	for i in int(sp["beds"]) - (1 if bool(sp["suite"]) else 0) - (1 if bool(sp["ground_bed"]) else 0):
		bedrooms.append("bed")
	for i in int(sp["full"]):
		bedrooms.append("bath_full")
	for r in sp["rooms"]:
		if str(r) != "living":
			ground.append(str(r))
	if bool(sp["ground_bed"]):
		ground.append("ground_bed")
		ground.append("bath_three")
	for i in int(sp["half"]):
		ground.append("bath_half")
	if int(sp["stories"]) == 2 or str(sp["style"]) == "split_level":
		upper = bedrooms
	else:
		ground.append_array(bedrooms)
	var out: Array = [{"name": "Main floor" if upper.is_empty() else "First floor", "rooms": ground}]
	if not upper.is_empty():
		out.append({"name": "Upper level" if str(sp["style"]) == "split_level" else "Second floor", "rooms": upper})
	if bool(sp["basement"]):
		var bas: Array = ["rec_room", "bath_three"] if bool(sp["basement_finished"]) else ["storage"]
		out.append({"name": "Basement (finished)" if bool(sp["basement_finished"]) else "Basement", "rooms": bas, "basement": true})
	return out


static func room_label(k: String) -> String:
	if k == "rec_room":
		return "Rec room"
	if k == "storage":
		return "Storage and furnace"
	return str(ROOM_LABEL.get(k, k.capitalize()))


static func _floor_sqft(rooms: Array) -> int:
	var t: float = 0.0
	for r in rooms:
		t += float(ROOM_SQFT.get(str(r), 0))
	return int(t * 1.15)   # halls, closets, stairs and walls


## Finished square feet above ground, the number on a listing.
static func sqft(spec: Dictionary) -> int:
	var t: int = 0
	for f in floors(spec):
		if not bool(f.get("basement", false)):
			t += _floor_sqft(f["rooms"])
	return t


static func footprint_sqft(spec: Dictionary) -> int:
	var m: int = 0
	for f in floors(spec):
		if not bool(f.get("basement", false)):
			m = maxi(m, _floor_sqft(f["rooms"]))
	return m


static func price_list(spec: Dictionary) -> Array:
	var sp: Dictionary = upgrade(spec)
	var st: Dictionary = STYLES[str(sp["style"])]
	var lines: Array = [["%s house shell, %d sq ft" % [st["label"], sqft(sp)], int(float(sqft(sp)) * SHELL_PER_SQFT * float(st["cost"]))]]
	var add: Callable = func(label: String, key: String, n: int = 1):
		if n > 0 and int(PRICE[key]) > 0:
			lines.append([label, int(PRICE[key]) * n])
	add.call(room_label("kitchen_%s" % sp["kitchen"]), "kitchen_%s" % sp["kitchen"])
	if bool(sp["island"]):
		add.call("Kitchen island", "island")
	if bool(sp["pantry"]):
		add.call("Walk in pantry", "pantry")
	add.call("Full baths x%d" % int(sp["full"]), "bath_full", int(sp["full"]))
	add.call("Shower baths x%d" % (int(sp["three"]) + (1 if bool(sp["ground_bed"]) else 0)), "bath_three", int(sp["three"]) + (1 if bool(sp["ground_bed"]) else 0))
	add.call("Half baths x%d" % int(sp["half"]), "bath_half", int(sp["half"]))
	if bool(sp["suite_bath"]):
		add.call("Main bath", "suite_bath")
	var gk: String = "stall_%s" % sp["garage_kind"]
	add.call("%s garage, %d stall%s" % [str(sp["garage_kind"]).capitalize(), int(sp["garage"]), "" if int(sp["garage"]) == 1 else "s"], gk, int(sp["garage"]))
	if bool(sp["workshop"]):
		add.call("Workshop", "workshop")
	if bool(sp["basement"]):
		add.call("Basement", "basement")
	if bool(sp["basement_finished"]):
		add.call("Finished basement", "basement_finished")
	for o in sp["outside"]:
		add.call(str(OUTSIDE_LABEL[str(o)]).capitalize(), str(o))
	add.call("%s siding" % str(sp["siding"]).capitalize(), "siding_%s" % sp["siding"])
	add.call("Metal roof", "roof_%s" % sp["roof"])
	add.call({"geothermal": "Geothermal heat", "wood_stove": "Wood stove", "furnace": "Furnace"}[str(sp["heat"])], "heat_%s" % sp["heat"])
	if bool(sp["fireplace"]):
		add.call("Fireplace", "fireplace")
	if bool(sp["ac"]):
		add.call("Central air", "ac")
	if bool(sp["solar"]):
		add.call("Solar panels", "solar")
	return lines


static func home_cost(spec: Dictionary) -> int:
	var t: int = 0
	for ln in price_list(spec):
		t += int(ln[1])
	return LTMoney.dollars(float(t))


## One line a person can read.
static func text(spec: Dictionary) -> String:
	if spec.is_empty():
		return "a house"
	var sp: Dictionary = upgrade(spec)
	var b: float = float(sp["baths"])
	var parts: Array = ["%s, %d bedroom%s" % [STYLES[str(sp["style"])]["label"], int(sp["beds"]), "" if int(sp["beds"]) == 1 else "s"],
		"%s bath%s" % [str(int(b)) if fmod(b, 1.0) < 0.1 else "%.1f" % b, "" if b == 1.0 else "s"],
		"%s sq ft" % LTGeography._thousands(sqft(sp))]
	if int(sp["garage"]) > 0:
		parts.append("%d car %s garage%s" % [int(sp["garage"]), "detached" if str(sp["garage_kind"]) == "detached" else "attached", " with a workshop" if bool(sp["workshop"]) else ""])
	if bool(sp["basement"]):
		parts.append("finished basement" if bool(sp["basement_finished"]) else "basement")
	for k in ["office", "den", "sunroom"]:
		if sp["rooms"].has(k):
			parts.append(str(ROOM_LABEL[k]).to_lower())
	for o in ["porch", "deck", "pool", "shelter", "greenhouse"]:
		if sp["outside"].has(o):
			parts.append(str(OUTSIDE_LABEL[o]))
	return ", ".join(parts)


# ---------------------------------------------------------------- on the lot

## The family decides where on the lot: how far back, toward which side, where the
## garage goes. Private people sit back farther; a lot with an alley behind it gets
## a garage off the alley, as in old towns.
static func place(w: LTWorld, l: Dictionary, spec: Dictionary, ctx: Dictionary = {}) -> void:
	var dp: float = LTGeography.lot_depth(l)
	var setback: float = FRONT_SETBACK
	if dp > 45.0:
		setback += clampf((50.0 - _t(ctx, "sociability")) / 4.0, 0.0, 8.0) + w.rng.randf_range(0.0, 3.0)
	if str(spec.get("style", "")) == "farmhouse" and dp > 50.0:
		setback += 4.0
	var side: String = "right" if w.rng.randf() < 0.5 else "left"
	if alley_behind(w, l):
		spec["garage_kind"] = "detached"
		side = "rear_" + side
		spec["why"].append("a garage out back on the alley, so the front yard is all lawn")
	elif str(spec.get("style", "")) == "farmhouse" and dp > 50.0 and w.rng.randf() < 0.6:
		spec["garage_kind"] = "detached"
		side = "rear_" + side
	spec["place"] = {"setback": setback, "shift": clampf(0.5 + w.rng.randf_range(-0.3, 0.3), 0.0, 1.0), "garage_side": side}
	# fit the lot: a house wider than the lot is redrawn deeper, then smaller
	var guard: int = 0
	while not bool(layout(l, spec)["fits"]) and guard < 8:
		guard += 1
		if str(spec["style"]) == "ranch" and int(spec["beds"]) >= 3:
			spec["style"] = "two_story"
			spec["stories"] = 2
			spec["why"].append("two stories, because a ranch this size would not fit the lot")
		elif int(spec["garage"]) > 1:
			spec["garage"] = int(spec["garage"]) - 1
		elif float(spec["place"]["setback"]) > FRONT_SETBACK:
			spec["place"]["setback"] = FRONT_SETBACK
		elif spec["rooms"].size() > 2:
			spec["rooms"].remove_at(spec["rooms"].size() - 2)
		elif int(spec["beds"]) > 1:
			spec["beds"] = int(spec["beds"]) - 1
		_sync(spec)


static func alley_behind(w: LTWorld, l: Dictionary) -> bool:
	var mid: Vector2 = _lot_mid(l)
	var back: Vector2 = mid
	var dp: float = LTGeography.lot_depth(l)
	match str(l["front"]):
		"s":
			back.y = float(l["z0"]) - 3.0
		"n":
			back.y = float(l["z1"]) + 3.0
		"e":
			back.x = float(l["x0"]) - 3.0
		"w":
			back.x = float(l["x1"]) + 3.0
	if dp <= 0.0:
		return false
	for s in w.roads:
		if str(w.streets[int(s["street"])].get("kind", "")) != "alley":
			continue
		var r: Rect2 = LTGeography.seg_rect(w, s)
		if r.grow(1.0).has_point(back):
			return true
	return false


## Where everything stands on the lot, in lot coordinates (x along the front,
## centered; d back from the street). Rects are [x0, d0, x1, d1].
static func layout(l: Dictionary, spec_in: Dictionary) -> Dictionary:
	var spec: Dictionary = upgrade(spec_in)
	var fw: float = LTGeography.lot_frontage(l)
	var dp: float = LTGeography.lot_depth(l)
	var pl: Dictionary = spec.get("place", {"setback": FRONT_SETBACK, "shift": 0.5, "garage_side": "right"})
	var setback: float = float(pl["setback"])
	var gside: String = str(pl["garage_side"])
	var rear: bool = gside.begins_with("rear") or str(spec["garage_kind"]) == "detached"
	var right: bool = gside.ends_with("right")
	var stalls: int = int(spec["garage"])
	var gw: float = float(stalls) * 3.3 + (3.0 if bool(spec["workshop"]) else 0.0)
	var gd: float = 7.0
	var area: float = float(footprint_sqft(spec)) / M2
	var aspect: float = float(STYLES[str(spec["style"])]["aspect"])
	var avail: float = fw - 2.0 * SIDE_SETBACK - (0.0 if rear else gw)
	var W: float = clampf(sqrt(area * aspect), 6.0, maxf(6.0, avail))
	var D: float = area / W
	var out: Dictionary = {"fits": true, "why": "", "W": W, "D": D, "gw": gw}
	var total: float = W + (0.0 if rear else gw)
	var slack: float = maxf(0.0, fw - 2.0 * SIDE_SETBACK - total)
	var x_left: float = -fw * 0.5 + SIDE_SETBACK + slack * float(pl["shift"])
	var hx0: float = x_left
	var gx0: float = x_left + W
	if not right and not rear:
		gx0 = x_left
		hx0 = x_left + gw
	out["house"] = [hx0, setback, hx0 + W, setback + D]
	if stalls > 0 or bool(spec["workshop"]):
		if rear:
			var gxl: float = (fw * 0.5 - SIDE_SETBACK - gw) if right else (-fw * 0.5 + SIDE_SETBACK)
			out["garage"] = [gxl, dp - REAR_SETBACK * 0.5 - gd, gxl + gw, dp - REAR_SETBACK * 0.5]
			out["garage_rear"] = true
			out["drive"] = [gxl, dp - REAR_SETBACK * 0.5, gxl + gw, dp]
		else:
			out["garage"] = [gx0, setback + 1.0, gx0 + gw, setback + 1.0 + gd]
			out["drive"] = [gx0 + 0.3, 0.0, gx0 + gw - 0.3, setback + 1.0]
	else:
		out["drive"] = [hx0 + W - 3.0, 0.0, hx0 + W, setback + 4.0]
	# door and the walk to the street
	var door_x: float = hx0 + W * (0.5 if rear else (0.35 if right else 0.65))
	out["door_x"] = door_x
	var back: float = setback + D
	var o: Array = spec["outside"]
	if o.has("porch"):
		var pw: float = W if str(spec["style"]) == "farmhouse" else minf(W * 0.6, 7.0)
		var px: float = clampf(door_x - pw * 0.5, hx0, hx0 + W - pw)
		out["porch"] = [px, setback - 2.4, px + pw, setback]
	if o.has("deck"):
		var dw: float = minf(W * 0.6, 7.0)
		out["deck"] = [door_x - dw * 0.5, back, door_x + dw * 0.5, back + 3.6]
	elif o.has("patio"):
		out["patio"] = [door_x - 2.0, back, door_x + 2.0, back + 4.0]
	var yard_far: float = dp - REAR_SETBACK
	var far_x: float = (-fw * 0.5 + SIDE_SETBACK) if right else (fw * 0.5 - SIDE_SETBACK - 3.0)
	if o.has("shed"):
		out["shed"] = [far_x, yard_far - 3.0, far_x + 3.0, yard_far]
	if o.has("garden"):
		out["garden"] = [-3.0, yard_far - 9.0, 3.0, yard_far - 6.0]
	if o.has("greenhouse"):
		out["greenhouse"] = [3.6, yard_far - 9.0, 7.6, yard_far - 6.0]
	if o.has("pool"):
		out["pool"] = [door_x - 4.0, back + 5.0, door_x + 4.0, back + 9.0]
	if o.has("shelter"):
		out["shelter"] = [hx0 + 0.5, back + 0.5, hx0 + 2.5, back + 2.5]
	if o.has("fence"):
		out["fence"] = [-fw * 0.5 + 0.3, back, fw * 0.5 - 0.3, dp - 0.3]
	# zoning: setbacks, the back yard, how much of the lot is covered
	var covered: float = W * D
	for k in ["garage", "shed", "greenhouse"]:
		if out.has(k):
			var r: Array = out[k]
			covered += (float(r[2]) - float(r[0])) * (float(r[3]) - float(r[1]))
	out["coverage"] = covered / maxf(1.0, fw * dp)
	var used_back: float = back
	for k in ["deck", "pool", "garden"]:
		if out.has(k):
			used_back = maxf(used_back, float(out[k][3]))
	if total > fw - 2.0 * SIDE_SETBACK + 0.05:
		out["fits"] = false
		out["why"] = "it would sit closer than %d feet to the side lot line" % int(SIDE_SETBACK * 3.28)
	elif back + REAR_SETBACK > dp or (out.has("garage_rear") and back > float(out["garage"][1]) - 1.0):
		out["fits"] = false
		out["why"] = "it would sit closer than %d feet to the back lot line" % int(REAR_SETBACK * 3.28)
	elif used_back > dp:
		out["fits"] = false
		out["why"] = "the yard is not deep enough"
	return out


static func max_coverage(w: LTWorld) -> float:
	return float(w.city["laws"].get("lot_coverage", 0.4))


## Breaks a rule the city could waive with a variance? Returns "" if it is legal.
static func rule_broken(w: LTWorld, l: Dictionary, spec: Dictionary) -> String:
	var lay: Dictionary = layout(l, spec)
	if not bool(lay["fits"]):
		return str(lay["why"])
	if float(lay["coverage"]) > max_coverage(w) + 0.001:
		return "buildings would cover %d%% of the lot, over the %d%% limit" % [int(float(lay["coverage"]) * 100.0), int(max_coverage(w) * 100.0)]
	return ""


## Rooms laid out inside the house, for the floor plan: per floor, rects
## [x0, d0, x1, d1, room key] in house coordinates (0..W across, 0..D from the front).
static func plan(l: Dictionary, spec: Dictionary) -> Array:
	var lay: Dictionary = layout(l, spec)
	var W: float = float(lay["W"])
	var D: float = float(lay["D"])
	var sp: Dictionary = upgrade(spec)
	var right: bool = str(sp.get("place", {}).get("garage_side", "right")).ends_with("right")
	var out: Array = []
	for f in floors(sp):
		var rooms: Array = f["rooms"]
		# small rooms (baths, laundry, mudroom) stack in a column on the garage side
		var small: Array = []
		var big: Array = []
		for r in rooms:
			if int(ROOM_SQFT.get(str(r), 120)) <= 90 and str(r) != "storage":
				small.append(r)
			else:
				big.append(r)
		var col_w: float = 0.0
		var rects: Array = []
		if not small.is_empty() and big.size() >= 1:
			var sa: float = 0.0
			for r in small:
				sa += float(ROOM_SQFT.get(str(r), 50))
			var ta: float = 0.0
			for r in rooms:
				ta += float(ROOM_SQFT.get(str(r), 120))
			col_w = clampf(W * sa / ta, 2.0, W * 0.35)
			var cx0: float = W - col_w if right else 0.0
			var y: float = 0.0
			for r in small:
				var rh: float = D * float(ROOM_SQFT.get(str(r), 50)) / sa
				rects.append([cx0, y, cx0 + col_w, y + rh, str(r)])
				y += rh
		elif big.is_empty():
			big = small
			small = []
		var bx0: float = 0.0 if right or small.is_empty() else col_w
		var BW: float = W - (col_w if not small.is_empty() else 0.0)
		# public rooms in front, private and work rooms in back
		var front: Array = []
		var rear: Array = []
		for r in big:
			if ["living", "dining", "office", "den", "suite", "bed", "rec_room", "ground_bed"].has(str(r)) and front.size() < 3:
				front.append(r)
			else:
				rear.append(r)
		if rear.is_empty() and front.size() > 1:
			rear.append(front.pop_back())
		var fa: float = 0.0
		var ra: float = 0.0
		for r in front:
			fa += float(ROOM_SQFT.get(str(r), 120))
		for r in rear:
			ra += float(ROOM_SQFT.get(str(r), 120))
		var fd: float = D * fa / maxf(1.0, fa + ra)
		for row in [[front, 0.0, fd, fa], [rear, fd, D, ra]]:
			var x: float = bx0
			for r in row[0]:
				var rw: float = BW * float(ROOM_SQFT.get(str(r), 120)) / maxf(1.0, float(row[3]))
				rects.append([x, float(row[1]), x + rw, float(row[2]), str(r)])
				x += rw
		out.append({"name": f["name"], "rects": rects, "W": W, "D": D})
	return out


# ---------------------------------------------------------------- daily life

static func of(w: LTWorld, h: Dictionary) -> Dictionary:
	if int(h["lot"]) < 0:
		return {}
	var l: Dictionary = w.lot(int(h["lot"]))
	if str(l.get("use", "")) != "house" or not l.has("home"):
		return {}
	return upgrade(l["home"])


## How many people a house holds without feeling crowded.
static func capacity(spec: Dictionary) -> float:
	return float(int(spec["beds"])) * 1.6 + 0.6


## A household's monthly utility bill changes with the house: its size, central air
## in summer, how it is heated, solar panels.
static func utility_factor(w: LTWorld, spec: Dictionary) -> float:
	if spec.is_empty():
		return 1.0
	var f: float = 0.6 + 0.4 * float(sqft(spec)) / 1800.0
	var season: String = LTCalendar.season(w.day)
	if season == "Winter":
		if str(spec["heat"]) == "geothermal":
			f *= 0.6
		elif str(spec["heat"]) == "wood_stove":
			f *= 0.8
	elif season == "Summer" and not bool(spec["ac"]):
		f *= 0.8
	if bool(spec["solar"]):
		f *= 0.7
	return f


## Somewhere safe below ground when a tornado comes.
static func has_shelter(spec: Dictionary) -> bool:
	return not spec.is_empty() and (bool(spec["basement"]) or spec["outside"].has("shelter"))


## The house's small daily effects on the family, called each evening.
static func evening(w: LTWorld, h: Dictionary, members: Array) -> void:
	var spec: Dictionary = of(w, h)
	if spec.is_empty():
		return
	var people: float = float(members.size())
	var baths: float = maxf(1.0, float(spec["baths"]))
	var summer: bool = LTCalendar.season(w.day) == "Summer"
	for m in members:
		var n: Dictionary = m["needs"]
		# too few bathrooms make for hard mornings
		if people / baths > 3.0:
			n["energy"] = float(n["energy"]) - 2.0
		if summer and not bool(spec["ac"]) and w.weather == "Clear":
			n["energy"] = float(n["energy"]) - 3.0
		if str(spec["kitchen"]) == "chef" and float(m["skills"]["cooking"]) > 50.0:
			n["fun"] = float(n["fun"]) + 2.0
		if spec["rooms"].has("den") or spec["rooms"].has("family") or bool(spec["basement_finished"]):
			n["fun"] = float(n["fun"]) + 1.0
		if spec["outside"].has("porch") or spec["outside"].has("deck"):
			n["social"] = float(n["social"]) + 1.0


# ---------------------------------------------------------------- remodels and additions

## Once a year each owning family looks at its house against its life.
static func monthly(w: LTWorld) -> void:
	var m: int = LTCalendar.month_index(w.day)
	for h in w.households:
		if str(h.get("tenure", "")) != "own" or int(h["lot"]) < 0 or h["members"].is_empty():
			continue
		if (int(h["id"]) * 7 + 3) % 12 != m:
			continue
		var l: Dictionary = w.lot(int(h["lot"]))
		if str(l["use"]) != "house" or not l.has("home") or _busy(w, int(l["id"])):
			continue
		# a big job leaves a family tired of builders for a couple of years
		if w.day - int(h.get("last_remodel_day", -9999)) < 700:
			continue
		_consider(w, h, l)


static func _busy(w: LTWorld, lot_id: int) -> bool:
	for p in w.projects:
		if str(p["ptype"]) == "remodel" and int(p["lot"]) == lot_id and ["bidding", "review", "building"].has(str(p["status"])):
			return true
	for v in w.city.get("variances", []):
		if int(v["lot"]) == lot_id and str(v["status"]) == "pending":
			return true
	return false


## What this family wants changed, most pressing first: [{key, label, why}].
static func wants(w: LTWorld, h: Dictionary, spec: Dictionary) -> Array:
	var members: Array = w.household_members(h)
	var adults: Array = w.household_adults(h)
	var kids: Array = []
	var teens: int = 0
	var elder: bool = false
	for c in members:
		var a: int = w.age_years(c)
		if a < 18:
			kids.append(c)
			if a >= 13:
				teens += 1
		elif a >= 72 and adults.size() >= 2:
			elder = true
	var head: Dictionary = adults[0] if not adults.is_empty() else {}
	var t: Dictionary = head.get("traits", {})
	var out: Array = []
	var need_beds: int = 1 + maxi(0, adults.size() - 2) + teens + int(ceil(float(kids.size() - teens) / 2.0))
	if need_beds > int(spec["beds"]):
		out.append({"key": "bedroom", "label": "add a bedroom", "why": "the kids need room as the family grows"})
	if float(members.size()) / maxf(1.0, float(spec["baths"])) > 2.5:
		out.append({"key": "bath", "label": "add a bathroom", "why": "%d people sharing %s bathroom%s" % [members.size(), str(spec["baths"]).trim_suffix(".0"), "" if float(spec["baths"]) <= 1.0 else "s"]})
	if elder and not bool(spec["ground_bed"]) and int(spec["stories"]) == 2:
		out.append({"key": "ground_bed", "label": "add a first floor bedroom and bath", "why": "a parent living with them cannot manage the stairs"})
	var homebiz: bool = false
	for b in w.businesses:
		if int(b["lot"]) == int(h["lot"]) and str(b["status"]) == "open":
			homebiz = true
	if homebiz and not spec["rooms"].has("office"):
		out.append({"key": "office", "label": "add a home office", "why": "the business they run from home needs a desk and a door"})
	if not head.is_empty() and float(head["skills"]["construction"]) + float(head["skills"]["repair"]) > 110.0 and not bool(spec["workshop"]):
		out.append({"key": "workshop", "label": "add a workshop to the garage", "why": "they build and fix things"})
	if not has_shelter(spec) and int(w.counters.get("tornadoes", 0)) > int(h.get("tornadoes_seen", 0)):
		out.append({"key": "shelter", "label": "put in a storm shelter", "why": "after the tornado, nobody wants to hide in a closet again"})
	h["tornadoes_seen"] = int(w.counters.get("tornadoes", 0))
	if bool(spec["basement"]) and not bool(spec["basement_finished"]) and kids.size() >= 2:
		out.append({"key": "finish_basement", "label": "finish the basement", "why": "a playroom for the kids and a spare bath"})
	if not head.is_empty() and float(head["skills"]["cooking"]) > 55.0 and str(spec["kitchen"]) != "chef":
		out.append({"key": "kitchen", "label": "redo the kitchen", "why": "cooking is what they love"})
	if not t.is_empty() and float(t["sociability"]) > 50.0 and not spec["outside"].has("deck") and not spec["outside"].has("patio"):
		out.append({"key": "deck", "label": "build a back deck", "why": "summer evenings with friends"})
	if not bool(spec["ac"]):
		out.append({"key": "ac", "label": "put in central air", "why": "the summers are hot"})
	if int(spec["garage"]) == 0:
		out.append({"key": "garage", "label": "build a garage", "why": "scraping ice off the car every winter morning"})
	if not t.is_empty() and float(t["ambition"]) > 65.0 and str(spec["siding"]) == "vinyl" and w.rng.randf() < 0.3:
		out.append({"key": "siding", "label": "put brick on the front", "why": "they want the house to look like they have made it"})
	return out


## The house after a change, and what it costs (dollars).
static func apply_want(spec_in: Dictionary, key: String) -> Array:
	var spec: Dictionary = upgrade(spec_in).duplicate(true)
	var cost: float = 0.0
	var addition_sqft: int = 0
	match key:
		"bedroom":
			spec["beds"] = int(spec["beds"]) + 1
			addition_sqft = int(ROOM_SQFT["bed"] * 1.15)
		"bath":
			if int(spec["half"]) > 0:
				spec["half"] = int(spec["half"]) - 1
				spec["full"] = int(spec["full"]) + 1
				cost += float(PRICE["bath_full"]) - float(PRICE["bath_half"]) + 6000.0
			else:
				spec["full"] = int(spec["full"]) + 1
				cost += float(PRICE["bath_full"])
				addition_sqft = int(ROOM_SQFT["bath_full"] * 1.15)
		"ground_bed":
			spec["ground_bed"] = true
			spec["beds"] = int(spec["beds"]) + 1
			cost += float(PRICE["bath_three"])
			addition_sqft = int((ROOM_SQFT["ground_bed"] + ROOM_SQFT["bath_three"]) * 1.15)
		"office":
			spec["rooms"].append("office")
			addition_sqft = int(ROOM_SQFT["office"] * 1.15)
		"workshop":
			spec["workshop"] = true
			cost += float(PRICE["workshop"])
		"shelter":
			spec["outside"].append("shelter")
			cost += float(PRICE["shelter"])
		"finish_basement":
			spec["basement_finished"] = true
			spec["three"] = int(spec["three"]) + 1
			cost += float(PRICE["basement_finished"]) + float(PRICE["bath_three"])
		"kitchen":
			cost += float(PRICE["kitchen_chef"]) + 20000.0   # tearing out the old one
			spec["kitchen"] = "chef"
			spec["island"] = true
		"deck":
			spec["outside"].append("deck")
			cost += float(PRICE["deck"])
		"ac":
			spec["ac"] = true
			cost += float(PRICE["ac"])
		"garage":
			spec["garage"] = 2
			cost += float(PRICE["stall_attached"]) * 2.0
		"siding":
			spec["siding"] = "brick"
			cost += float(PRICE["siding_brick"]) * 0.6
	# additions cost more per foot than new building: tearing into a finished house
	cost += float(addition_sqft) * 240.0
	_sync(spec)
	return [spec, LTMoney.dollars(cost)]


static func _consider(w: LTWorld, h: Dictionary, l: Dictionary) -> void:
	var spec: Dictionary = upgrade(l["home"])
	var list: Array = wants(w, h, spec)
	if list.is_empty():
		return
	var head: Dictionary = w.household_adults(h)[0] if not w.household_adults(h).is_empty() else {}
	if head.is_empty():
		return
	var want: Dictionary = list[0]
	var urgent: bool = ["bedroom", "ground_bed", "bath", "shelter"].has(str(want["key"]))
	if not urgent and w.rng.randf() < 0.5:
		return
	var r: Array = apply_want(spec, str(want["key"]))
	var cost: int = int(r[1])
	var cash: int = w.household_cash(h)
	var cushion: int = LTPeople.monthly_bills(w, h) * 3
	var t: Dictionary = head["traits"]
	var funding: String = ""
	if cash - cost > cushion:
		funding = "cash"
	else:
		# a home equity loan against what the house is worth over the mortgage
		var owed: int = 0
		if int(h["mortgage"]) >= 0:
			var d: Dictionary = w.debt(int(h["mortgage"]))
			if LTFinance.is_active(d):
				owed = int(d["balance"])
		var equity: int = int(float(l["value"]) * 0.85) - owed
		var bold: bool = float(t["risk"]) + float(t["ambition"]) - float(t["discipline"]) > 40.0 or ["bedroom", "ground_bed", "shelter"].has(str(want["key"]))
		if equity > cost and bold:
			funding = "loan"
	if funding == "":
		if w.rng.randf() < 0.3:
			w.log_sim(head, "Wanted to %s (%s) but cannot afford %s right now." % [want["label"], want["why"], LTMoney.fmt(cost)], false)
		return
	var broken: String = rule_broken(w, l, r[0])
	if broken != "":
		_file_variance(w, h, l, head, want, r[0], cost, funding, broken)
		return
	start_remodel(w, h, l, head, want, r[0], cost, funding)


## Small jobs a handy owner does on weekends; the rest go out to builders.
static func start_remodel(w: LTWorld, h: Dictionary, l: Dictionary, head: Dictionary, want: Dictionary, spec: Dictionary, cost: int, funding: String) -> void:
	var acct: String = w.acct_p(head)
	h["last_remodel_day"] = w.day
	if funding == "loan":
		var d: Dictionary = LTFinance.new_debt(w, "p", int(head["id"]), "bank", -1, "home_equity", cost, 0.085, 120, "house", int(l["id"]), [])
		LTFinance.fund_loan(w, d, acct, cost)
	var diy: bool = float(head["skills"]["construction"]) > 65.0 and cost < LTMoney.dollars(30000.0)
	if diy:
		var mat: int = w.ledger.pay(acct, "outside", int(float(cost) * 0.5), "home_improvement")
		l["home"] = spec
		l["value"] = int(l["value"]) + int(float(cost) * 0.7)
		_count(w, "remodels")
		w.log_sim(head, "Spent the weekends doing it themselves: %s, %s in materials. Reason: %s." % [want["label"], LTMoney.fmt(mat), want["why"]], true)
		w.chronicle_add("%s %s %s on %s." % [head["first_name"], head["last_name"], _past(str(want["label"])), LTGeography.lot_street(w, int(l["id"]))["name"]], "housing", false, [head["id"]])
		return
	var r: Dictionary = LTProjects.define_project(w, "remodel", int(l["id"]), int(float(cost) * 1.3), -1, false,
		{"kind": "remodel", "id": int(head["id"]), "name": "the %s family" % head["last_name"], "acct": acct, "home": spec, "want": want["label"]}, cost, 0)
	if not bool(r.get("ok", false)):
		return
	var p: Dictionary = w.projects[int(r["project_id"])]
	p["title"] = "The %s family: %s" % [head["last_name"], want["label"]]
	p["home"] = spec
	# the money for the job is set aside so the builder gets paid
	var escrow: String = "escrow:%d" % int(p["id"])
	w.ledger.pay(acct, escrow, int(float(cost) * 1.3), "construction_escrow")
	p["developer"]["acct"] = escrow
	p["developer"]["refund"] = acct
	w.log_sim(head, "Hired builders to %s, about %s%s. Reason: %s." % [want["label"], LTMoney.fmt(cost), " on a home equity loan" if funding == "loan" else "", want["why"]], true)


static func _past(label: String) -> String:
	var v: String = label.get_slice(" ", 0)
	var rest: String = label.substr(v.length())
	var p: String = {"add": "added", "put": "put", "build": "built", "finish": "finished", "redo": "redid"}.get(v, v + "ed")
	return p + rest


## The builders finished.
static func finish_remodel(w: LTWorld, p: Dictionary, l: Dictionary) -> void:
	LTBuildings._close_escrow(w, p)
	if not p.has("home") or str(l["use"]) != "house":
		return
	l["home"] = p["home"]
	var cost: int = int(p["price"]) + int(p["change_orders"])
	l["value"] = int(l["value"]) + int(float(cost) * 0.75)
	_count(w, "remodels")
	var head: Dictionary = w.cit(int(p["developer"]["id"]))
	if not head.is_empty():
		w.log_sim(head, "The builders finished: %s. It cost %s." % [p["developer"].get("want", "the remodel"), LTMoney.fmt(cost)], true)
	w.chronicle_add("%s on %s is done." % [p["title"], LTGeography.lot_street(w, int(l["id"]))["name"]], "housing", false, [])


static func _count(w: LTWorld, key: String) -> void:
	w.counters[key] = int(w.counters.get(key, 0)) + 1


# ---------------------------------------------------------------- variances

## The family asks the city to waive a zoning rule. Neighbors say their piece, as
## at a real hearing, and the mayor decides.
static func _file_variance(w: LTWorld, h: Dictionary, l: Dictionary, head: Dictionary, want: Dictionary, spec: Dictionary, cost: int, funding: String, broken: String) -> void:
	if not w.city.has("variances"):
		w.city["variances"] = []
	var t: Dictionary = head["traits"]
	# most people trim the plan to fit; the determined ones ask
	if float(t["ambition"]) + float(t["risk"]) < 100.0 and w.rng.randf() < 0.6:
		w.log_sim(head, "Gave up on a plan to %s: %s, and they would not ask the city for an exception." % [want["label"], broken], false)
		return
	var for_n: int = 0
	var against_n: int = 0
	var voices: Array = []
	for nl in neighbors(w, l):
		var nh: Dictionary = w.hh(int(nl["units"][0])) if not nl["units"].is_empty() and int(nl["units"][0]) >= 0 else {}
		if nh.is_empty():
			continue
		var na: Array = w.household_adults(nh)
		if na.is_empty():
			continue
		var n: Dictionary = na[0]
		var rel: float = 0.0
		var rr = n["rel"].get(int(head["id"]), n["rel"].get(str(head["id"]), {}))
		if rr is Dictionary:
			rel = float(rr.get("affection", 0.0))
		var support: float = float(n["traits"]["kindness"]) * 0.5 + rel * 0.5 - 25.0 + w.rng.randf_range(-15.0, 15.0)
		if support >= 0.0:
			for_n += 1
			voices.append("%s supports it" % w.full_name(n))
		else:
			against_n += 1
			voices.append("%s is against it: %s" % [w.full_name(n), ["it will block the light", "it is too close to the property line", "rules are rules", "it will hurt the look of the street"][w.rng.randi_range(0, 3)]])
	var v: Dictionary = {"id": w.city["variances"].size(), "lot": int(l["id"]), "hh": int(h["id"]), "cid": int(head["id"]),
		"family": str(head["last_name"]), "want": want, "home": spec, "cost": cost, "funding": funding, "rule": broken,
		"day": w.day, "status": "pending", "for": for_n, "against": against_n, "voices": voices}
	w.city["variances"].append(v)
	w.log_sim(head, "Asked the city for a variance to %s: %s. Reason: %s." % [want["label"], broken, want["why"]], true)
	w.chronicle_add("Variance request: the %s family wants to %s on %s, but %s. Neighbors: %d for, %d against. The mayor decides." % [head["last_name"], want["label"], LTGeography.lot_street(w, int(l["id"]))["name"], broken, for_n, against_n], "city", true, [head["id"]])


static func neighbors(w: LTWorld, l: Dictionary) -> Array:
	var out: Array = []
	var r: Rect2 = Rect2(float(l["x0"]), float(l["z0"]), float(l["x1"]) - float(l["x0"]), float(l["z1"]) - float(l["z0"])).grow(2.0)
	for o in w.lots:
		if int(o["id"]) == int(l["id"]) or str(o["use"]) != "house":
			continue
		if r.intersects(Rect2(float(o["x0"]), float(o["z0"]), float(o["x1"]) - float(o["x0"]), float(o["z1"]) - float(o["z0"]))):
			out.append(o)
	return out


static func pending_variances(w: LTWorld) -> Array:
	var out: Array = []
	for v in w.city.get("variances", []):
		if str(v["status"]) == "pending":
			out.append(v)
	return out


## The mayor's answer.
static func decide(w: LTWorld, vid: int, approve: bool) -> Dictionary:
	var vs: Array = w.city.get("variances", [])
	if vid < 0 or vid >= vs.size():
		return {"ok": false, "message": "No such variance request."}
	var v: Dictionary = vs[vid]
	if str(v["status"]) != "pending":
		return {"ok": false, "message": "That request has already been decided."}
	var head: Dictionary = w.cit(int(v["cid"]))
	var h: Dictionary = w.hh(int(v["hh"]))
	var l: Dictionary = w.lot(int(v["lot"]))
	v["status"] = "approved" if approve else "denied"
	v["decided_day"] = w.day
	if head.is_empty() or h.is_empty() or int(h["lot"]) != int(v["lot"]):
		return {"ok": true, "message": "Decided. The family no longer lives there."}
	head["trust_city"] = clampf(float(head.get("trust_city", 50.0)) + (6.0 if approve else -8.0), 0.0, 100.0)
	for nl in neighbors(w, l):
		for u in nl["units"]:
			if int(u) >= 0:
				for m in w.household_adults(w.hh(int(u))):
					m["trust_city"] = clampf(float(m.get("trust_city", 50.0)) + (-2.0 if approve and int(v["against"]) > 0 else 1.0), 0.0, 100.0)
	if approve:
		start_remodel(w, h, l, head, v["want"], v["home"], int(v["cost"]), str(v["funding"]))
		w.log_sim(head, "The city granted the variance to %s." % v["want"]["label"], true)
		return {"ok": true, "message": "Variance granted. The %s family can %s." % [v["family"], v["want"]["label"]]}
	w.log_sim(head, "The city denied the variance to %s. Disappointed, and it will not be forgotten at election time." % v["want"]["label"], true)
	return {"ok": true, "message": "Variance denied. The %s family keeps the house as it is." % v["family"]}


## Requests nobody answers lapse after two months.
static func lapse(w: LTWorld) -> void:
	for v in w.city.get("variances", []):
		if str(v["status"]) == "pending" and w.day - int(v["day"]) > 60:
			v["status"] = "lapsed"
			var head: Dictionary = w.cit(int(v["cid"]))
			if not head.is_empty():
				head["trust_city"] = clampf(float(head.get("trust_city", 50.0)) - 10.0, 0.0, 100.0)
				w.log_sim(head, "The city never answered the variance request. They dropped the plan to %s." % v["want"]["label"], true)
