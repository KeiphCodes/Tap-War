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
	var lots: Array = []
	for l in w.lots:
		if str(l["use"]) == "empty" and str(l["owner_kind"]) == "city" and ["residential", "mixed"].has(str(l["zone"])) and LTGeography.connected(w, int(l["id"])):
			lots.append(l)
	if lots.is_empty():
		return
	var p: float = clampf(settler_pull(w) / 100.0, 0.05, 0.9)
	var bought: int = 0
	while bought < 3 and not lots.is_empty() and w.rng.randf() < p:
		var l: Dictionary = lots.pop_front()
		var price: int = int(l["value"])
		w.ledger.pay("outside", "city", price, "lot sales")
		l["owner_kind"] = "outside"
		var r: Dictionary = LTProjects.define_project(w, "house", int(l["id"]), int(float(LTProjects.BASE_COST["house"]) * 1.4), -1)
		if not bool(r["ok"]):
			continue
		var pr: Dictionary = w.projects[int(r["project_id"])]
		var family: String = LTPeople.LAST_NAMES[w.rng.randi_range(0, LTPeople.LAST_NAMES.size() - 1)]
		pr["private"] = true
		pr["developer"] = {"kind": "settler", "id": -1, "name": "the %s family" % family, "acct": "bank", "family": family}
		pr["title"] = "The %s family's house" % family
		w.chronicle_add("The %s family bought %s for %s and hired a builder. They will move in when the house is done." % [family, LTGeography.lot_label(w, int(l["id"])), LTMoney.fmt(price)], "move", true, [])
		bought += 1
		p *= 0.6


## Called when a settler's house is finished: the family arrives and owns it.
static func settler_moves_in(w: LTWorld, p: Dictionary, l: Dictionary) -> void:
	var h: Dictionary = LTPeople.make_household(w, true, true)
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


static func _all_paved(w: LTWorld) -> bool:
	for st in w.streets:
		if LTGeography.street_condition(w, int(st["id"])) < 60.0:
			return false
	return true
