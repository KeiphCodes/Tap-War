class_name LTFounder
extends RefCounted
## Founding a town from nothing. The player won the lottery and bought prairie.
## Settlers come on their own when the land is zoned, cheap and within reach of work.
## They buy a lot from the town fund and hire a builder; the bank carries the
## construction loan and it becomes their mortgage. At 25 residents the town
## incorporates: city taxes and services begin, and in elected mode a vote follows.

const INCORPORATE_AT: int = 25
const MILESTONES: Array = [
	["home", "The mayor's house is built"],
	["first_settler", "The first settler family moves in"],
	["first_business", "A Sim opens the first business"],
	["incorporated", "The town incorporates"],
	["pop_50", "50 residents"],
	["grocery", "A grocery opens in town"],
	["pop_100", "100 residents"],
	["school", "The town has a school"],
	["clinic", "The town has a clinic"],
	["paved", "Every street paved and in good shape"],
	["balanced", "A full year with income above spending"],
	["pop_250", "250 residents"],
	["bank", "A local bank opens"],
	["pop_500", "500 residents"],
	["pop_1000", "1,000 residents"],
]


static func setup(w: LTWorld) -> void:
	# empty prairie: unzoned land owned by the town fund, county gravel roads
	for l in w.lots:
		l["zone"] = "none"
		l["use"] = "empty"
		l["value"] = LTGeography.land_value("none")
		l["district"] = "Founders' Plat"
	for s in w.roads:
		s["condition"] = w.rng.randf_range(18.0, 28.0)
		s["quality"] = 0.2
	for d in w.config["districts"]:
		d["name"] = "Founders' Plat"
	w.city["incorporated"] = false
	w.city["next_election_day"] = 99999999
	w.city["name"] = str(w.mode.get("town_name", "New Hope"))
	# the city clerk job waits for a real city
	w.city["jobs"] = []
	w.city["income_12m"] = 0
	w.city["spend_12m"] = 0
	w.ledger.pay("outside", "city", int(w.mode["lottery"]), "founder's lottery money")


static func daily(w: LTWorld) -> void:
	if LTCalendar.day_of_month(w.day) == 5:
		_settlers(w)
	if not bool(w.city.get("incorporated", true)) and w.residents() >= INCORPORATE_AT:
		_incorporate(w)
	if w.day % 7 == 2:
		_milestones(w)


# ---------------------------------------------------------------- settlers

static func settler_pull(w: LTWorld) -> float:
	var pull: float = LTRegion.index(w) * 25.0
	pull += 15.0 if not w.open_businesses("grocery").is_empty() else 0.0
	pull += 10.0 if LTCivic.has_service(w, "school") else 0.0
	pull += 5.0 if LTCivic.has_service(w, "clinic") else 0.0
	pull += float(LTEconomy.open_positions(w)) * 3.0
	pull += LTCivic.safety_level(w) * 0.1
	pull += LTGeography.amenity_share(w, "sidewalks") * 8.0
	# cheap land and a fresh start draw people early on
	pull += clampf(30.0 - float(w.residents()) * 0.1, 5.0, 30.0)
	var paved: float = 0.0
	for st in w.streets:
		paved = maxf(paved, LTGeography.street_condition(w, int(st["id"])))
	if paved < 30.0:
		pull -= 10.0
	if bool(w.city.get("incorporated", false)):
		pull -= float(w.city["laws"]["property_tax"]) * 300.0
	return pull


static func _settlers(w: LTWorld) -> void:
	var p: float = clampf(settler_pull(w) / 100.0, 0.05, 0.9)
	# a finished house for sale is the quickest way in: a family may buy one outright
	for hl in w.lots:
		if str(hl["use"]) == "house" and hl.has("for_sale") and int(hl["units"][0]) == -1 and w.rng.randf() < p * 0.6:
			_settler_buys_house(w, hl)
	var lots: Array = []
	for l in w.lots:
		if str(l["use"]) != "empty" or bool(l.get("hold", false)) or not ["residential", "mixed"].has(str(l["zone"])) or not LTGeography.connected(w, int(l["id"])):
			continue
		# from the city, or from an investor who listed it
		if str(l["owner_kind"]) == "city" or l.has("for_sale"):
			lots.append(l)
	# families look at the cheapest lots first
	lots.sort_custom(func(a, b): return _lot_price(w, a) < _lot_price(w, b) or (_lot_price(w, a) == _lot_price(w, b) and int(a["id"]) < int(b["id"])))
	if lots.is_empty():
		return
	var bought: int = 0
	while bought < 3 and not lots.is_empty() and w.rng.randf() < p:
		var l: Dictionary = lots.pop_front()
		var price: int = _lot_price(w, l)
		var pct: int = int(float(price) / float(maxi(1, int(l["value"]))) * 100.0)
		if pct > 100 and w.rng.randf() < clampf(float(pct - 100) / 200.0, 0.0, 0.9):
			# too dear: this family keeps looking
			p *= 0.8
			continue
		var seller: String = LTCivic.owner_acct(w, l)
		var sold_by: String = "the city" if seller == "city" else ("%s, who bought it to sell" % w.full_name(w.cit(int(l["owner_id"]))) if str(l["owner_kind"]) == "sim" else "its owner")
		LTCivic.property_sale(w, "outside", seller, price, int(l["id"]))
		if seller != "city" and str(l["owner_kind"]) == "sim":
			var inv: Dictionary = w.cit(int(l["owner_id"]))
			if w.is_present(inv):
				var gain: int = price - int(l.get("bought_for", price))
				w.log_sim(inv, "Sold %s for %s, %s %s on what it cost." % [LTGeography.lot_label(w, int(l["id"])), LTMoney.fmt(price), "a gain of" if gain >= 0 else "a loss of", LTMoney.fmt(absi(gain))], true)
		l.erase("bought_for")
		w.chronicle_add("A settler family bought %s from %s for %s." % [LTGeography.lot_label(w, int(l["id"])), sold_by, LTMoney.fmt(price)], "housing", false, [])
		l["owner_kind"] = "outside"
		var family: String = LTPeople.LAST_NAMES[w.rng.randi_range(0, LTPeople.LAST_NAMES.size() - 1)]
		# who is coming: mostly young couples and families
		var roll: float = w.rng.randf()
		var adults: int = 2 if roll < 0.78 else 1
		var kids: int = 0
		if roll < 0.55:
			kids = [1, 1, 2, 2, 2, 3, 3, 4][w.rng.randi_range(0, 7)]
		elif roll >= 0.78 and roll < 0.9:
			kids = w.rng.randi_range(1, 2)
		var income: int = LTMoney.dollars(w.rng.randf_range(38000.0, 62000.0) * (1.6 if adults == 2 else 1.0))
		var spec: Dictionary = LTGeography.choose_home(w, adults, kids, income, w.rng.randf_range(25.0, 80.0), w.rng.randf_range(25.0, 80.0))
		var cost: int = LTGeography.home_cost(spec)
		var r: Dictionary = LTProjects.define_project(w, "house", int(l["id"]), int(float(cost) * 1.3), -1, false,
			{"kind": "settler", "id": -1, "name": "the %s family" % family, "acct": "bank", "family": family, "adults": adults, "kids": kids, "home": spec},
			cost, LTGeography.home_sqft(spec))
		if not bool(r["ok"]):
			continue
		var pr: Dictionary = w.projects[int(r["project_id"])]
		pr["title"] = "The %s family's house" % family
		pr["home"] = spec
		w.chronicle_add("The %s family bought %s for %s and hired a builder for a %s house (%s). They will move in when it is done." % [family, LTGeography.lot_label(w, int(l["id"])), LTMoney.fmt(price), LTMoney.fmt(cost), LTGeography.home_text(spec)], "move", true, [])
		bought += 1
		p *= 0.6


static func _lot_price(w: LTWorld, l: Dictionary) -> int:
	return int(l["for_sale"]) if l.has("for_sale") else LTGeography.asking_price(w, int(l["id"]))


## A settler family buys a finished house for sale and moves straight in, with a
## bank mortgage for most of it.
static func _settler_buys_house(w: LTWorld, l: Dictionary) -> void:
	var price: int = int(l["for_sale"])
	var seller: String = LTCivic.owner_acct(w, l)
	var roll: float = w.rng.randf()
	var adults: int = 2 if roll < 0.78 else 1
	var kids: int = [0, 1, 2, 2, 3][w.rng.randi_range(0, 4)] if adults == 2 else w.rng.randi_range(0, 2)
	var h: Dictionary = LTPeople.make_family(w, adults, kids)
	var head: Dictionary = w.household_adults(h)[0]
	var down: int = int(float(price) * 0.1)
	w.ledger.pay("outside", seller, down, "house_purchases")
	var d: Dictionary = LTFinance.new_debt(w, "p", int(head["id"]), "bank", -1, "mortgage", price - down, 0.064, 360, "house", int(l["id"]), [])
	LTFinance.fund_loan(w, d, seller, price - down)
	LTCivic.transfer_tax(w, seller, price, int(l["id"]))
	var b: Dictionary = w.biz(int(l["owner_id"])) if str(l["owner_kind"]) == "business" else {}
	if not b.is_empty():
		w.log_biz(b, "Sold the house on %s for %s, %s over what it cost to build." % [LTGeography.lot_label(w, int(l["id"])), LTMoney.fmt(price), LTMoney.fmt(price - int(l.get("bought_for", price)))])
	l.erase("bought_for")
	LTPeople.move_household_into(w, h, int(l["id"]), 0)
	h["tenure"] = "own"
	h["rent"] = 0
	h["mortgage"] = int(d["id"])
	l["owner_kind"] = "sim"
	l["owner_id"] = int(head["id"])
	for m in w.household_members(h):
		m["moved_in"] = w.day
		w.counters["moved_in"] = int(w.counters["moved_in"]) + 1
		w.log_sim(m, "Moved to %s into a newly built house on %s, bought for %s." % [w.city["name"], LTGeography.lot_label(w, int(l["id"])), LTMoney.fmt(price)], true)
	w.chronicle_add("The %s family bought the new house on %s and moved in. %s now has %d residents." % [head["last_name"], LTGeography.lot_street(w, int(l["id"]))["name"], w.city["name"], w.residents()], "move", true, h["members"].duplicate())


## Called when a settler's house is finished: the family arrives and owns it.
static func settler_moves_in(w: LTWorld, p: Dictionary, l: Dictionary) -> void:
	var dev: Dictionary = p["developer"]
	var h: Dictionary = LTPeople.make_household(w, true, true, true) if not dev.has("adults") else LTPeople.make_family(w, int(dev["adults"]), int(dev["kids"]))
	if p.has("home"):
		l["home"] = p["home"]
	var fam: String = str(p["developer"].get("family", ""))
	if fam != "":
		for m in w.household_members(h):
			m["last_name"] = fam
	LTPeople.move_household_into(w, h, int(l["id"]), 0)
	h["tenure"] = "own"
	h["rent"] = 0
	var adults: Array = w.household_adults(h)
	if adults.is_empty():
		return
	var head: Dictionary = adults[0]
	l["owner_kind"] = "sim"
	l["owner_id"] = int(head["id"])
	var price: int = int(p["price"]) + int(p["change_orders"])
	var d: Dictionary = LTFinance.new_debt(w, "p", int(head["id"]), "bank", -1, "mortgage", price, 0.062, 360, "house", int(l["id"]), [])
	h["mortgage"] = int(d["id"])
	LTFinance._dhist(w, d, "The bank's construction loan became the mortgage when the family moved in.")
	for m in w.household_members(h):
		m["moved_in"] = w.day
		w.counters["moved_in"] = int(w.counters["moved_in"]) + 1
		w.log_sim(m, "Moved to %s into a new house on %s. Reason: cheap land, a fresh start, and work within driving distance." % [w.city["name"], LTGeography.lot_label(w, int(l["id"]))], true)
	w.chronicle_add("The %s family moved into their new house. %s now has %d residents." % [head["last_name"], w.city["name"], w.residents()], "move", true, h["members"].duplicate())


# ---------------------------------------------------------------- incorporation

static func _incorporate(w: LTWorld) -> void:
	w.city["incorporated"] = true
	w.city["incorporated_day"] = w.day
	w.city["jobs"].append({"id": w.city["jobs"].size(), "title": "city clerk", "skill": "finance", "service": "hall", "wage": LTMoney.dollars(128.0), "holder": -1})
	var text: String = "%s incorporated as a town with %d residents. City taxes and services begin, and petitions now go to a real city hall." % [w.city["name"], w.residents()]
	if bool(w.city.get("elections", false)):
		w.city["next_election_day"] = w.day + 90
		text += " The first election for mayor is in 90 days."
	else:
		text += " %s stays mayor." % w.player["name"]
	w.player["title"] = "mayor"
	w.chronicle_add(text, "election" if bool(w.city.get("elections", false)) else "city", true, [])


# ---------------------------------------------------------------- milestones

static func _milestones(w: LTWorld) -> void:
	if not w.city.has("milestones"):
		w.city["milestones"] = {}
	var got: Dictionary = w.city["milestones"]
	var pop: int = w.residents()
	var checks: Dictionary = {
		"home": int(w.player.get("home_lot", -1)) >= 0,
		"first_settler": str(w.mode.get("start", "")) == "founder" and w.alive_count() > 0,
		"first_business": int(w.counters["businesses_opened"]) > 0,
		"incorporated": bool(w.city.get("incorporated", false)) and str(w.mode.get("start", "")) == "founder",
		"pop_50": pop >= 50, "pop_100": pop >= 100, "pop_250": pop >= 250, "pop_500": pop >= 500, "pop_1000": pop >= 1000,
		"grocery": not w.open_businesses("grocery").is_empty(),
		"school": LTCivic.has_service(w, "school") or not w.open_businesses("private_school").is_empty(),
		"clinic": LTCivic.has_service(w, "clinic") or not w.open_businesses("clinic").is_empty(),
		"bank": not w.open_businesses("bank").is_empty(),
		"paved": _all_paved(w),
		"balanced": w.day > 365 and int(w.city["income_12m"]) > int(w.city["spend_12m"]),
	}
	for m in MILESTONES:
		var id: String = m[0]
		if not got.has(id) and bool(checks.get(id, false)):
			got[id] = w.day
			w.chronicle_add("Milestone: %s." % m[1], "milestone", true, [])


## The next things to do, worked out from the town as it is right now: the first
## steps of a new town, then the milestones still ahead. [{text, done}]
static func next_steps(w: LTWorld) -> Array:
	var out: Array = []
	var founder: bool = str(w.mode.get("start", "")) == "founder"
	if founder:
		var drawn: bool = false
		var live: bool = false
		var awarded: bool = false
		var built_road: bool = false
		var house_live: bool = false
		for p in w.projects:
			if str(p["ptype"]) == "road_build" and str(p["status"]) != "cancelled":
				drawn = true
				if str(p["status"]) != "draft":
					live = true
				if ["building", "done"].has(str(p["status"])):
					awarded = true
				if str(p["status"]) == "done":
					built_road = true
			if str(p["ptype"]) == "mayor_house" and not ["draft", "cancelled"].has(str(p["status"])):
				house_live = true
		var homes: bool = false
		for l in w.lots:
			if not bool(l.get("removed", false)) and ["residential", "mixed"].has(str(l["zone"])):
				homes = true
				break
		var steps: Array = [
			["Draw your first road off the county road (Draw road, right side)", drawn],
			["Tap the road, write its contract, and press Go live", live],
			["When bids arrive, award one on the Projects tab", awarded],
			["Plot house lots beside your road (Plot lots; pick a lot width to cut a strip into several)", homes],
			["Draft the mayor's house on the Projects tab and send it live", house_live or int(w.player.get("home_lot", -1)) >= 0],
			["Wait for a contractor to finish your first road", built_road],
			["Welcome your first settler family", w.alive_count() > 0],
			["Reach %d residents so the town incorporates" % INCORPORATE_AT, bool(w.city.get("incorporated", false))],
		]
		for st in steps:
			out.append({"text": st[0], "done": bool(st[1])})
	var got: Dictionary = w.city.get("milestones", {})
	for m in MILESTONES:
		if founder and ["home", "first_settler", "incorporated"].has(str(m[0])):
			continue
		if not founder and ["home", "first_settler", "incorporated"].has(str(m[0])):
			continue
		out.append({"text": str(m[1]), "done": got.has(str(m[0]))})
	return out


static func _all_paved(w: LTWorld) -> bool:
	for st in w.streets:
		if LTGeography.street_condition(w, int(st["id"])) < 60.0:
			return false
	return true
