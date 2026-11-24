class_name LTProjects
extends RefCounted
## Public projects through competitive bids. The player never builds directly.
## Outside firms always bid, at a markup, and their money leaves town. Local Sim
## run construction companies bid once they exist. Quality is a lasting property.

const BASE_COST: Dictionary = {
	"road_repair": 9000000, "road_patch": 3500000, "school": 52000000, "school_small": 26000000,
	"clinic": 34000000, "clinic_small": 15000000, "park": 6000000, "apartments": 42000000,
	"house": 22000000, "mayor_house": 30000000, "shop": 15000000, "remodel": 4000000,
}
const BASE_DAYS: Dictionary = {
	"road_repair": 45, "road_patch": 20, "school": 180, "school_small": 120,
	"clinic": 140, "clinic_small": 90, "park": 40, "apartments": 150,
	"house": 90, "mayor_house": 120, "shop": 75, "remodel": 30,
}
const TITLES: Dictionary = {
	"road_repair": "Rebuild %s", "road_patch": "Patch %s", "school": "Build the town school",
	"school_small": "Build a two room schoolhouse", "clinic": "Build the town clinic",
	"clinic_small": "Open a small health office", "park": "Build a park", "apartments": "Build a 4 unit apartment house",
	"house": "A settler's house", "mayor_house": "Build the mayor's house", "shop": "A new business building", "remodel": "A remodel",
}
const BID_DAYS: int = 14
const OUTSIDE: Array = [
	{"name": "Prairie Road Builders", "honesty": 72, "greed": 45, "skill": 0.72, "crew": 8, "roads": true},
	{"name": "Capital Construction Co", "honesty": 60, "greed": 65, "skill": 0.82, "crew": 14, "roads": true},
	{"name": "Riverbend Contractors", "honesty": 25, "greed": 80, "skill": 0.5, "crew": 6, "roads": true},
	{"name": "North Plains Builders", "honesty": 55, "greed": 55, "skill": 0.62, "crew": 10, "roads": false},
]


static func setup_companies(w: LTWorld) -> void:
	for o in OUTSIDE:
		var c: Dictionary = o.duplicate()
		c["id"] = w.companies.size()
		c["workload"] = w.rng.randi_range(0, 2)
		c["quality_hist"] = [clampf(float(o["skill"]) * (0.6 + float(o["honesty"]) / 250.0) + w.rng.randf_range(-0.05, 0.05), 0.2, 1.0)]
		c["overruns"] = 0 if int(o["honesty"]) > 50 else 2
		c["late"] = 1 if float(o["skill"]) < 0.6 else 0
		c["defects"] = 0 if int(o["honesty"]) > 50 else 1
		c["jobs"] = 3
		w.companies.append(c)


static func pipeline_value(w: LTWorld) -> int:
	var t: int = 0
	for p in w.projects:
		if ["bidding", "review"].has(str(p["status"])):
			t += int(p["ceiling"])
	t += LTMoney.dollars(120000.0) if LTPeople.vacancy_count(w) == 0 else 0
	return t


static func is_road(ptype: String) -> bool:
	return ptype == "road_repair" or ptype == "road_patch" or ptype == "road_build"


## A paved two lane town street costs about $1,000 a meter, $10,000 for each 10
## meter survey step (about $100,000 a block); a crew lays about 20 meters a day.
const ROAD_BLOCK_COST: int = 1000000
const ROAD_BLOCK_DAYS: float = 0.5


## A new road the player drew: contractors bid on building its planned blocks.
static func define_road_build(w: LTWorld, street_id: int, segs: Array, draft: bool = false) -> Dictionary:
	var n: int = segs.size()
	# bridges, hillsides and trees to clear cost more than open prairie
	var units: float = 0.0
	var bridge_m: int = 0
	var hill_m: int = 0
	var trees_m: int = 0
	for sid in segs:
		var sg: Dictionary = w.roads[int(sid)]
		var rc: Dictionary = LTTerrain.road_cost(w, LTGeography.node_pos(w, int(sg["a"])), LTGeography.node_pos(w, int(sg["b"])))
		units += float(rc["factor"]) if bool(rc["ok"]) else 1.0
		match str(rc["kind"]):
			"bridge":
				bridge_m += 10
			"hill":
				hill_m += 10
			"forest":
				trees_m += 10
	var p: Dictionary = {
		"id": w.projects.size(), "ptype": "road_build", "title": "Build %s (%d m)" % [w.streets[street_id]["name"], n * 10], "lot": -1, "street": street_id, "ceiling": 0,
		"petition_id": -1, "status": "bidding", "created_day": w.day, "bid_close_day": w.day + BID_DAYS,
		"bids": [], "winner": {}, "winner_name": "", "price": 0, "change_orders": 0, "paid": 0,
		"days_promised": 0, "start_day": -1, "progress": 0.0, "stage": "", "quality": 0.0, "quality_target": 0.0,
		"events": [], "done_day": -1, "warranty_until": -1, "private": false, "developer": {}, "repair_needed_day": -1,
		"kickback": {}, "payment_late": false, "segments": segs.duplicate(),
		"base_cost": int(float(ROAD_BLOCK_COST) * units), "base_days": 15 + int(ROAD_BLOCK_DAYS * units),
		"raw_cost": int(float(ROAD_BLOCK_COST) * units), "raw_days": 15 + int(ROAD_BLOCK_DAYS * units), "spec": default_spec("road_build"),
	}
	_apply_spec(p)
	w.projects.append(p)
	_event(w, p, "Drawn by the mayor: %d meters of new %s." % [n * 10, "alley" if str(w.streets[street_id]["kind"]) == "alley" else "road"])
	var extras: Array = []
	if bridge_m > 0:
		extras.append("a %d meter bridge" % bridge_m)
	if hill_m > 0:
		extras.append("%d meters of hillside" % hill_m)
	if trees_m > 0:
		extras.append("%d meters through trees to clear" % trees_m)
	if not extras.is_empty():
		_event(w, p, "It includes %s, so it costs more than a road on open prairie." % ", ".join(extras))
	if draft:
		_make_draft(p)
		return {"ok": true, "message": "\"%s\" is drawn as a draft. Tap it to write the contract, then press Go live to send it out to bid." % p["title"], "project_id": int(p["id"])}
	_open_bidding(w, p)
	return {"ok": true, "message": "\"%s\" is drawn and out to bid until %s. Award it on the Projects tab." % [p["title"], LTCalendar.short(int(p["bid_close_day"]))], "project_id": int(p["id"])}


## `owner` set means a private job (a settler's house, a developer's apartments):
## the owner picks the builder and it is never one of the mayor's contracts.
## `cost` and `sqft` set a private building's price and size (a family's house, a
## founder's shop) instead of the type's usual cost.
static func define_project(w: LTWorld, ptype: String, target: int, ceiling: int, petition_id: int, draft: bool = false, owner: Dictionary = {}, cost: int = 0, sqft: int = 0) -> Dictionary:
	if not BASE_COST.has(ptype):
		return {"ok": false, "message": "Unknown project type."}
	var p: Dictionary = {
		"id": w.projects.size(), "ptype": ptype, "title": "", "lot": -1, "street": -1, "ceiling": 0,
		"petition_id": petition_id, "status": "bidding", "created_day": w.day, "bid_close_day": w.day + BID_DAYS,
		"bids": [], "winner": {}, "winner_name": "", "price": 0, "change_orders": 0, "paid": 0,
		"days_promised": 0, "start_day": -1, "progress": 0.0, "stage": "", "quality": 0.0, "quality_target": 0.0,
		"events": [], "done_day": -1, "warranty_until": -1, "private": false, "developer": {}, "repair_needed_day": -1,
		"kickback": {}, "payment_late": false,
	}
	if is_road(ptype):
		if target < 0 or target >= w.streets.size():
			return {"ok": false, "message": "Pick a street."}
		for q in w.projects:
			if int(q["street"]) == target and ["draft", "bidding", "review", "building"].has(str(q["status"])):
				return {"ok": false, "message": "%s already has a project." % w.streets[target]["name"]}
		p["street"] = target
		p["title"] = TITLES[ptype] % w.streets[target]["name"]
	elif ptype == "remodel":
		# the family keeps living there while the builders work
		var lr: Dictionary = w.lot(target)
		if lr.is_empty() or str(lr["use"]) != "house":
			return {"ok": false, "message": "There is no house there to remodel."}
		p["lot"] = target
		p["title"] = TITLES[ptype]
	else:
		if target < 0:
			var zones: Array = ["residential", "mixed"] if ptype == "apartments" else (["park", "civic"] if ptype == "park" else ["civic"])
			target = LTGeography.best_site(w, zones, [])
		var l: Dictionary = w.lot(target)
		if l.is_empty() or not ["empty", "closed"].has(str(l["use"])):
			return {"ok": false, "message": "That site is not an empty lot."}
		var allowed: Array = ["civic", "mixed"]
		if ptype == "park":
			allowed = ["park", "civic", "mixed"]
		elif ptype == "apartments" or ptype == "house":
			allowed = ["residential", "mixed"]
		elif ptype == "shop":
			allowed = LTGeography.ZONES.duplicate()
		elif ptype == "mayor_house":
			allowed = LTGeography.ZONES.duplicate()
			if int(w.player.get("home_lot", -1)) >= 0:
				return {"ok": false, "message": "The mayor's house is already built."}
			for q in w.projects:
				if str(q["ptype"]) == "mayor_house" and not ["cancelled", "done"].has(str(q["status"])):
					return {"ok": false, "message": "The mayor's house is already out to bid or being built."}
		if not allowed.has(str(l["zone"])):
			return {"ok": false, "message": "Lot %d is zoned %s. This project needs %s. Rezone it first." % [target, l["zone"], " or ".join(allowed)]}
		p["lot"] = target
		p["title"] = TITLES[ptype]
		l["use"] = "reserved"
		l["ref"] = int(p["id"])
	p["raw_cost"] = cost if cost > 0 else int(BASE_COST[ptype])
	if int(p["lot"]) >= 0 and bool(w.lot(int(p["lot"])).get("wooded", false)):
		# trees to clear and stumps to pull before the foundation goes in
		p["raw_cost"] = int(p["raw_cost"]) + LTTerrain.LOT_CLEARING
	p["raw_days"] = int(BASE_DAYS.get(ptype, 30))
	if sqft > 0:
		# about a month of site work plus a day for every 60 square feet
		p["raw_days"] = 30 + sqft / 60
		p["sqft"] = sqft
	p["spec"] = default_spec(ptype)
	_apply_spec(p)
	if ceiling > 0:
		p["ceiling"] = ceiling
		p["ceiling_set"] = true
	if not owner.is_empty():
		p["private"] = true
		p["developer"] = owner
		draft = false
	w.projects.append(p)
	if draft:
		_event(w, p, "Drafted by the mayor.")
		_make_draft(p)
		return {"ok": true, "message": "\"%s\" is a draft. Open it to write the contract, then press Go live to send it out to bid." % p["title"], "project_id": int(p["id"])}
	_open_bidding(w, p)
	return {"ok": true, "message": "\"%s\" is out to bid until %s." % [p["title"], LTCalendar.short(int(p["bid_close_day"]))], "project_id": int(p["id"])}


## A draft is the mayor's private worksheet: contractors cannot see it yet.
static func _make_draft(p: Dictionary) -> void:
	p["status"] = "draft"
	p["bid_close_day"] = -1


static func _open_bidding(w: LTWorld, p: Dictionary) -> void:
	p["status"] = "bidding"
	p["bid_close_day"] = w.day + BID_DAYS
	if bool(p["private"]):
		_event(w, p, "%s asked builders for bids. This is their own job: they pick the builder, not the mayor." % str(p["developer"].get("name", "The owner")).capitalize())
		return
	var terms: String = spec_text(p) if p.has("spec") else ""
	_event(w, p, "The mayor sent it out to bid for %d days%s. Budget ceiling %s." % [BID_DAYS, (" on these terms: " + terms) if terms != "" else "", LTMoney.fmt(int(p["ceiling"]))])
	if not bool(p["private"]):
		w.chronicle_add("The city put \"%s\" out to bid, budget ceiling %s." % [p["title"], LTMoney.fmt(int(p["ceiling"]))], "project", false, [])


## The mayor publishes a finished draft: contractors can now see it and bid.
static func go_live(w: LTWorld, pid: int) -> Dictionary:
	if pid < 0 or pid >= w.projects.size():
		return {"ok": false, "message": "No such project."}
	var p: Dictionary = w.projects[pid]
	if str(p["status"]) != "draft":
		return {"ok": false, "message": "This contract is already live."}
	_open_bidding(w, p)
	return {"ok": true, "message": "\"%s\" is live. Contractors have until %s to bid." % [p["title"], LTCalendar.short(int(p["bid_close_day"]))]}


# ---------------------------------------------------------------- the contract

## What the mayor writes into a contract before it goes out to bid. Each choice
## changes what contractors price, how long they take, and what gets built.
const SURFACES: Dictionary = {
	"gravel": {"label": "Gravel", "cost": 0.5, "quality": -0.25, "wear": 2.2, "note": "cheap, dusty, wears out fast"},
	"asphalt": {"label": "Asphalt", "cost": 1.0, "quality": 0.0, "wear": 1.0, "note": "the usual town street"},
	"concrete": {"label": "Concrete", "cost": 1.5, "quality": 0.1, "wear": 0.55, "note": "costly, lasts decades"},
}
const WIDTHS: Dictionary = {
	"lane": {"label": "Narrow lane", "cost": 0.8, "speed": 1.12, "draw": 0.75},
	"street": {"label": "Two lane street", "cost": 1.0, "speed": 1.0, "draw": 1.0},
	"avenue": {"label": "Wide avenue", "cost": 1.4, "speed": 0.82, "draw": 1.45},
	"alley": {"label": "Alley", "cost": 0.4, "speed": 1.4, "draw": 0.55},
}
const GRADES: Dictionary = {
	"budget": {"label": "Budget materials", "cost": 0.8, "quality": -0.12},
	"standard": {"label": "Standard", "cost": 1.0, "quality": 0.0},
	"premium": {"label": "Premium materials", "cost": 1.3, "quality": 0.12},
}
const SIDEWALK_COST: float = 0.14
const LIGHTS_COST: float = 0.09
const RUSH_COST: float = 0.6     # extra price per share of the schedule a deadline cuts
const LATE_PENALTY: float = 0.005  # of the price per day late, when the contract has one


static func default_spec(ptype: String) -> Dictionary:
	if ptype == "road_build":
		return {"surface": "asphalt", "width": "street", "sidewalks": false, "lights": false, "deadline": 0, "penalty": false}
	return {"grade": "standard", "deadline": 0, "penalty": false}


static func spec_editable(p: Dictionary) -> bool:
	return p.has("spec") and not bool(p["private"]) and ["draft", "bidding", "review"].has(str(p["status"]))


static func _apply_spec(p: Dictionary) -> void:
	var sp: Dictionary = p["spec"]
	var mult: float = 1.0
	var dmult: float = 1.0
	if str(p["ptype"]) == "road_build":
		mult = float(SURFACES[str(sp["surface"])]["cost"]) * float(WIDTHS[str(sp["width"])]["cost"])
		if bool(sp["sidewalks"]):
			mult += SIDEWALK_COST
		if bool(sp["lights"]):
			mult += LIGHTS_COST
		dmult = 0.7 + mult * 0.3
	else:
		mult = float(GRADES[str(sp.get("grade", "standard"))]["cost"])
		dmult = 0.85 + mult * 0.15
	p["base_cost"] = int(float(p["raw_cost"]) * mult)
	p["base_days"] = maxi(5, int(float(p["raw_days"]) * dmult))
	if not bool(p.get("ceiling_set", false)):
		p["ceiling"] = int(float(p["base_cost"]) * 1.45)


static func spec_quality(p: Dictionary) -> float:
	if not p.has("spec"):
		return 0.0
	var sp: Dictionary = p["spec"]
	if str(p["ptype"]) == "road_build":
		return float(SURFACES[str(sp["surface"])]["quality"])
	return float(GRADES[str(sp.get("grade", "standard"))]["quality"])


## One line a person can read: what this contract asks for.
static func spec_text(p: Dictionary) -> String:
	if not p.has("spec"):
		return ""
	var sp: Dictionary = p["spec"]
	var parts: Array = []
	if str(p["ptype"]) == "road_build":
		parts.append(str(WIDTHS[str(sp["width"])]["label"]))
		parts.append(str(SURFACES[str(sp["surface"])]["label"]).to_lower())
		if bool(sp["sidewalks"]):
			parts.append("sidewalks")
		if bool(sp["lights"]):
			parts.append("streetlights")
	else:
		parts.append(str(GRADES[str(sp.get("grade", "standard"))]["label"]))
	if int(sp["deadline"]) > 0:
		parts.append("finish within %d days%s" % [int(sp["deadline"]), " or pay a late penalty" if bool(sp["penalty"]) else ""])
	return ", ".join(parts)


## The mayor rewrites a contract that is not signed yet. If bids are already in,
## the change sends it back out to bid, because every price was for the old terms.
static func edit(w: LTWorld, pid: int, changes: Dictionary) -> Dictionary:
	if pid < 0 or pid >= w.projects.size():
		return {"ok": false, "message": "No such project."}
	var p: Dictionary = w.projects[pid]
	if changes.has("name") and str(p["ptype"]) == "road_build":
		var nm: String = str(changes["name"]).strip_edges().left(40)
		if nm != "" and nm != str(w.streets[int(p["street"])]["name"]):
			w.streets[int(p["street"])]["name"] = nm
			var n: int = p.get("segments", []).size()
			p["title"] = "Build %s (%d m)" % [nm, n * 10]
			_event(w, p, "The mayor named the road %s." % nm)
		changes.erase("name")
	if changes.is_empty():
		return {"ok": true, "message": "Saved."}
	if not spec_editable(p):
		return {"ok": false, "message": "The contract is signed. Its terms can no longer change."}
	var sp: Dictionary = p["spec"]
	var before: String = spec_text(p)
	for k in changes:
		match str(k):
			"surface":
				if SURFACES.has(str(changes[k])):
					sp["surface"] = str(changes[k])
			"width":
				if WIDTHS.has(str(changes[k])):
					sp["width"] = str(changes[k])
			"grade":
				if GRADES.has(str(changes[k])):
					sp["grade"] = str(changes[k])
			"sidewalks", "lights", "penalty":
				if sp.has(k):
					sp[k] = bool(changes[k])
			"deadline":
				sp["deadline"] = clampi(int(changes[k]), 0, 720)
			"ceiling":
				var c: int = int(changes[k])
				if c <= 0:
					p["ceiling_set"] = false
				else:
					p["ceiling"] = maxi(c, LTMoney.dollars(1000.0))
					p["ceiling_set"] = true
	_apply_spec(p)
	var msg: String = "Contract updated: %s. Budget ceiling %s." % [spec_text(p), LTMoney.fmt(int(p["ceiling"]))]
	if str(p["status"]) == "draft":
		msg += " Still a draft: press Go live when it is ready."
	if str(p["status"]) == "review":
		# the bids were for the old terms: they are thrown out and the contract goes
		# back to a draft; it only goes out again when the mayor presses Go live
		p["bids"] = []
		_make_draft(p)
		msg += " The bids were for the old terms, so they were set aside and the contract is a draft again. Press Go live to send it back out to bid."
	if spec_text(p) != before or changes.has("ceiling"):
		_event(w, p, "The mayor changed the contract: %s. Budget ceiling %s." % [spec_text(p), LTMoney.fmt(int(p["ceiling"]))])
	return {"ok": true, "message": msg}


static func _deadline_terms(p: Dictionary, price: float, days: int) -> Array:
	# a deadline shorter than the crew's honest schedule costs overtime and extra crews
	var dl: int = int(p.get("spec", {}).get("deadline", 0))
	if dl > 0 and days > dl:
		var cut: float = float(days - dl) / float(days)
		price *= 1.0 + cut * RUSH_COST
		days = dl
	return [price, days]


static func _event(w: LTWorld, p: Dictionary, text: String) -> void:
	p["events"].append({"day": w.day, "text": text})


static func cancel(w: LTWorld, pid: int) -> Dictionary:
	var p: Dictionary = w.projects[pid]
	if not ["draft", "bidding", "review"].has(str(p["status"])):
		return {"ok": false, "message": "Only projects not yet awarded can be cancelled."}
	p["status"] = "cancelled"
	if str(p["ptype"]) == "road_build":
		LTGeography.cancel_planned(w, int(p["street"]))
	if int(p["lot"]) >= 0 and str(p["ptype"]) != "remodel":
		w.lot(int(p["lot"]))["use"] = "empty"
		w.lot(int(p["lot"]))["ref"] = -1
	_event(w, p, "Cancelled by the mayor.")
	return {"ok": true, "message": "Cancelled."}


static func daily(w: LTWorld) -> void:
	LTGeography.wear_roads(w)
	for p in w.projects:
		match str(p["status"]):
			"bidding":
				if w.day >= int(p["bid_close_day"]):
					_collect_bids(w, p)
			"building":
				_build_day(w, p)
			"done":
				_watch_quality(w, p)
	if LTCalendar.day_of_month(w.day) == 10:
		_developers(w)


# ---------------------------------------------------------------- bids

static func _collect_bids(w: LTWorld, p: Dictionary) -> void:
	var ptype: String = str(p["ptype"])
	var bids: Array = []
	for co in w.companies:
		if is_road(ptype) and not bool(co["roads"]):
			continue
		bids.append(_outside_bid(w, p, co))
	for b in w.open_businesses("construction"):
		if b["staff"].size() >= 1:
			bids.append(_local_bid(w, p, b))
	p["bids"] = bids
	p["status"] = "review" if not bool(p["private"]) else "review"
	_event(w, p, "Bidding closed with %d bids." % bids.size())
	if bool(p["private"]):
		_developer_award(w, p)
	else:
		w.chronicle_add("Bids are in for \"%s\": %d companies bid. The mayor must pick one." % [p["title"], bids.size()], "project", true, [])


static func _grade(q: float) -> String:
	if q >= 0.85:
		return "A"
	if q >= 0.7:
		return "B"
	if q >= 0.55:
		return "C"
	if q >= 0.4:
		return "D"
	return "F"


static func _avg(a: Array) -> float:
	if a.is_empty():
		return 0.5
	var t: float = 0.0
	for x in a:
		t += float(x)
	return t / float(a.size())


static func _outside_bid(w: LTWorld, p: Dictionary, co: Dictionary) -> Dictionary:
	var ptype: String = str(p["ptype"])
	var base: float = float(p.get("base_cost", BASE_COST.get(ptype, 0)))
	var skill: float = float(co["skill"])
	var code: float = float(w.city["laws"].get("building_code", 1.0))
	var true_cost: float = base * (1.0 + (1.0 - skill) * 0.25) * (1.0 + float(co["workload"]) * 0.03) * (0.9 + code * 0.1)
	var markup: float = 1.08 + float(co["greed"]) / 500.0 + 0.05  # profit plus travel and lodging for an outside crew
	var price: float = true_cost * markup
	var plans_change_orders: bool = false
	var cuts_materials: bool = false
	if int(co["honesty"]) < 40:
		# low bid now, change orders later
		price = true_cost * w.rng.randf_range(0.82, 0.92)
		plans_change_orders = true
		cuts_materials = w.rng.randf() < 0.7
	price *= w.rng.randf_range(0.96, 1.05)
	var days: int = int(float(p.get("base_days", BASE_DAYS.get(ptype, 30))) * (1.1 - skill * 0.2) * (1.0 + float(co["workload"]) * 0.05) * w.rng.randf_range(0.95, 1.1)) + 4
	var q: float = clampf(skill * (0.75 + float(co["honesty"]) / 400.0) + w.rng.randf_range(-0.05, 0.05), 0.15, 1.0)
	if cuts_materials:
		q *= 0.6
	var dt: Array = _deadline_terms(p, price, days)
	price = float(dt[0])
	days = int(dt[1])
	return {
		"kind": "outside", "company": int(co["id"]), "name": co["name"], "local": false,
		"price": int(price), "days": days, "crew": int(co["crew"]), "warranty_years": 1 if int(co["honesty"]) < 50 else 3,
		"grade": _grade(_avg(co["quality_hist"])), "record": "%d jobs, %d overruns, %d late, %d defects" % [co["jobs"], co["overruns"], co["late"], co["defects"]],
		"hidden_quality": q, "plans_change_orders": plans_change_orders, "money_note": "Outside firm: the money leaves town and the crew is not local.",
	}


static func _local_bid(w: LTWorld, p: Dictionary, b: Dictionary) -> Dictionary:
	var ptype: String = str(p["ptype"])
	var owner: Dictionary = w.cit(int(b["owners"][0]))
	var t: Dictionary = owner["traits"] if not owner.is_empty() else {"honesty": 50, "greed": 50}
	var skill: float = 0.0
	var crew: int = 0
	for sid in b["staff"]:
		var s: Dictionary = w.cit(int(sid))
		if w.is_present(s):
			skill += float(s["skills"]["construction"])
			crew += 1
	if not owner.is_empty():
		skill += float(owner["skills"]["construction"]) * 1.5
	skill = clampf(skill / (float(crew) + 1.5) / 100.0, 0.2, 0.95)
	b["crew_quality"] = skill
	var base: float = float(p.get("base_cost", BASE_COST.get(ptype, 0)))
	var busy: int = 0
	for q in w.projects:
		if str(q["status"]) == "building" and str(q["winner"].get("kind", "")) == "local" and int(q["winner"]["id"]) == int(b["id"]):
			busy += 1
	var code: float = float(w.city["laws"].get("building_code", 1.0))
	var true_cost: float = base * (1.0 + (1.0 - skill) * 0.3) * (1.0 + float(busy) * 0.15) * (0.9 + code * 0.1)
	var price: float = true_cost * (1.05 + float(t["greed"]) / 500.0)
	var plans: bool = false
	if int(t["honesty"]) < 35 and int(t["greed"]) > 55:
		price = true_cost * 0.88
		plans = true
	var crew_factor: float = clampf(float(crew) / 4.0, 0.4, 1.5)
	var days: int = int(float(p.get("base_days", BASE_DAYS.get(ptype, 30))) * (1.15 - skill * 0.2) / crew_factor * (1.0 + float(busy) * 0.3)) + 2
	var q2: float = clampf(skill * (0.8 + float(t["honesty"]) / 500.0) + w.rng.randf_range(-0.06, 0.06), 0.15, 1.0)
	var dt: Array = _deadline_terms(p, price, days)
	price = float(dt[0])
	days = int(dt[1])
	var hist: String = "first public job" if int(b["jobs_done"]) == 0 else "%d jobs, %d overruns, %d defects" % [b["jobs_done"], b["overruns"], b["defects"]]
	return {
		"kind": "local", "company": int(b["id"]), "name": b["name"], "local": true,
		"price": int(price), "days": days, "crew": crew + 1, "warranty_years": 2,
		"grade": "new" if int(b["jobs_done"]) == 0 else _grade(float(b.get("quality_avg", 0.6))), "record": hist,
		"hidden_quality": q2, "plans_change_orders": plans, "money_note": "Local firm owned by %s: wages and profit stay in town." % w.full_name(owner),
	}


static func award(w: LTWorld, pid: int, bid_index: int) -> Dictionary:
	if pid < 0 or pid >= w.projects.size():
		return {"ok": false, "message": "No such project."}
	var p: Dictionary = w.projects[pid]
	if str(p["status"]) != "review":
		return {"ok": false, "message": "This project is not waiting for a decision."}
	if bid_index < 0 or bid_index >= p["bids"].size():
		return {"ok": false, "message": "No such bid."}
	var bid: Dictionary = p["bids"][bid_index]
	if int(bid["price"]) > int(p["ceiling"]):
		return {"ok": false, "message": "That bid is over the budget ceiling of %s." % LTMoney.fmt(int(p["ceiling"]))}
	if int(bid["price"]) > w.ledger.bal("city") + LTMoney.dollars(5000.0) and not bool(p["private"]):
		return {"ok": false, "message": "The city has %s and the bid is %s. Borrow first or pick a cheaper bid." % [LTMoney.fmt(w.ledger.bal("city")), LTMoney.fmt(int(bid["price"]))]}
	_start(w, p, bid)
	var cheapest: bool = true
	for other in p["bids"]:
		if int(other["price"]) < int(bid["price"]):
			cheapest = false
	_event(w, p, "Awarded to %s for %s, %d days promised. %s" % [bid["name"], LTMoney.fmt(int(bid["price"])), bid["days"], "It was the cheapest bid." if cheapest else "It was not the cheapest bid."])
	w.chronicle_add("The mayor awarded \"%s\" to %s for %s." % [p["title"], bid["name"], LTMoney.fmt(int(bid["price"]))], "project", false, [])
	return {"ok": true, "message": "Awarded to %s." % bid["name"]}


static func _start(w: LTWorld, p: Dictionary, bid: Dictionary) -> void:
	p["winner"] = {"kind": bid["kind"], "id": int(bid["company"])}
	p["winner_name"] = bid["name"]
	p["price"] = int(bid["price"])
	p["days_promised"] = int(bid["days"])
	p["quality_target"] = clampf(float(bid["hidden_quality"]) + spec_quality(p), 0.1, 1.0)
	p["plans_change_orders"] = bool(bid["plans_change_orders"])
	p["warranty_until"] = -1
	p["status"] = "building"
	p["start_day"] = w.day
	p["progress"] = 0.0
	p["warranty_years"] = int(bid["warranty_years"])
	if int(p["lot"]) >= 0 and str(p["ptype"]) != "remodel":
		var l: Dictionary = w.lot(int(p["lot"]))
		l["use"] = "site"
		l["ref"] = int(p["id"])
	if str(bid["kind"]) == "outside":
		w.companies[int(bid["company"])]["workload"] = int(w.companies[int(bid["company"])]["workload"]) + 1


static func _payer(w: LTWorld, p: Dictionary) -> String:
	if bool(p["private"]):
		return str(p["developer"]["acct"])
	return "city"


static func _payee(w: LTWorld, p: Dictionary) -> String:
	if str(p["winner"]["kind"]) == "local":
		return "b:%d" % int(p["winner"]["id"])
	return "outside"


static func _stage_name(ptype: String, prog: float) -> String:
	if is_road(ptype):
		if prog < 0.2:
			return "tearing out old pavement"
		if prog < 0.5:
			return "laying the road base"
		if prog < 0.9:
			return "paving"
		return "striping and cleanup"
	if prog < 0.15:
		return "site work"
	if prog < 0.35:
		return "foundation"
	if prog < 0.65:
		return "framing"
	if prog < 0.85:
		return "closing in the shell"
	return "finishing"


static func _build_day(w: LTWorld, p: Dictionary) -> void:
	var ptype: String = str(p["ptype"])
	var rate: float = 1.0 / float(maxi(1, int(p["days_promised"])))
	var wx: float = 1.0
	match w.weather:
		"Snow":
			wx = 0.15
		"Storm":
			wx = 0.25
		"Rain":
			wx = 0.65
	if LTCalendar.season(w.day) == "Winter" and is_road(ptype):
		wx *= 0.6
	var labor: float = 1.0
	if str(p["winner"]["kind"]) == "local":
		var b: Dictionary = w.biz(int(p["winner"]["id"]))
		var present: int = 0
		for sid in b["staff"]:
			if w.is_present(w.cit(int(sid))) and int(w.cit(int(sid))["sick_days"]) == 0:
				present += 1
		labor = clampf(float(present + 1) / 3.0, 0.2, 1.4)
		if str(b["status"]) != "open":
			labor = 0.0
	if bool(p["payment_late"]):
		labor *= 0.2
	# the bid was priced to sell, not to finish on time
	var plan_factor: float = 1.0
	if bool(p.get("plans_change_orders", false)):
		plan_factor = 0.88
	var before: float = float(p["progress"])
	# contractors build to their schedule, which already allows for normal weather
	p["progress"] = minf(1.0, before + rate * (0.55 + 0.45 * wx) * labor * plan_factor * 1.12)
	var old_stage: String = str(p["stage"])
	p["stage"] = _stage_name(ptype, float(p["progress"]))
	if str(p["stage"]) != old_stage:
		_event(w, p, "Stage: %s." % p["stage"])
		_progress_payment(w, p)
	# change orders and kickback offers, with a paper trail
	if bool(p.get("plans_change_orders", false)) and before < 0.5 and float(p["progress"]) >= 0.5:
		var co: int = int(float(p["price"]) * w.rng.randf_range(0.12, 0.25))
		var room: int = int(p["ceiling"]) - int(p["price"]) - int(p["change_orders"])
		if co <= room:
			p["change_orders"] = int(p["change_orders"]) + co
			_event(w, p, "Change order for %s from %s: \"unexpected ground conditions\". It fits under the ceiling and was paid." % [LTMoney.fmt(co), p["winner_name"]])
			w.chronicle_add("%s billed the city %s extra on \"%s\" through a change order." % [p["winner_name"], LTMoney.fmt(co), p["title"]], "project", false, [])
		else:
			p["change_orders"] = int(p["change_orders"]) + maxi(0, room)
			p["days_promised"] = int(p["days_promised"]) + 20
			_event(w, p, "Change order for %s refused, over the ceiling. The contractor slowed down and paid only %s more." % [LTMoney.fmt(co), LTMoney.fmt(maxi(0, room))])
	if before < 0.3 and float(p["progress"]) >= 0.3 and not bool(p["private"]):
		_maybe_kickback(w, p)
	if float(p["progress"]) >= 1.0:
		_finish(w, p)


static func _progress_payment(w: LTWorld, p: Dictionary) -> void:
	var total: int = int(p["price"]) + int(p["change_orders"])
	var due: int = int(float(total) * minf(1.0, float(p["progress"]))) - int(p["paid"])
	if float(p["progress"]) >= 1.0:
		due = total - int(p["paid"])
	if due <= 0:
		return
	var paid: int = w.ledger.pay(_payer(w, p), _payee(w, p), due, "contract_payments" if not bool(p["private"]) else "private_construction")
	p["paid"] = int(p["paid"]) + paid
	if str(p["winner"]["kind"]) == "local":
		var b: Dictionary = w.biz(int(p["winner"]["id"]))
		b["month_revenue"] = int(b["month_revenue"]) + paid
		b["lifetime_revenue"] = int(b["lifetime_revenue"]) + paid
		# materials for the job are bought from outside
		var mat: int = w.ledger.pay(w.acct_b(b), "outside", int(float(paid) * 0.45), "construction_materials")
		b["month_costs"] = int(b["month_costs"]) + mat
	if paid < due:
		p["payment_late"] = true
		_event(w, p, "Payment of %s was late, the payer only had %s. Work slowed down." % [LTMoney.fmt(due), LTMoney.fmt(paid)])
		if not bool(p["private"]):
			w.chronicle_add("The city could not make a %s payment on \"%s\". Work slowed." % [LTMoney.fmt(due - paid), p["title"]], "city", true, [])
	else:
		p["payment_late"] = false


static func _maybe_kickback(w: LTWorld, p: Dictionary) -> void:
	var honesty: int = 50
	if str(p["winner"]["kind"]) == "outside":
		honesty = int(w.companies[int(p["winner"]["id"])]["honesty"])
	else:
		var owner: Dictionary = w.cit(int(w.biz(int(p["winner"]["id"]))["owners"][0]))
		honesty = int(owner["traits"]["honesty"]) if not owner.is_empty() else 50
	if honesty >= 40 or w.rng.randf() > 0.6:
		return
	var clerk: Dictionary = {}
	for j in w.city["jobs"]:
		if str(j["title"]) == "city clerk" and int(j["holder"]) >= 0:
			clerk = w.cit(int(j["holder"]))
	var amount: int = LTMoney.dollars(w.rng.randf_range(1500.0, 4000.0))
	if clerk.is_empty():
		_event(w, p, "%s offered a %s \"thank you\" to whoever signs the inspections. Nobody at city hall to take it." % [p["winner_name"], LTMoney.fmt(amount)])
		return
	var t: Dictionary = clerk["traits"]
	var take: float = float(t["greed"]) * 0.6 - float(t["honesty"]) * 0.7 + (100.0 - float(clerk["needs"]["money_security"])) * 0.2
	if take > 5.0:
		var src: String = "outside" if str(p["winner"]["kind"]) == "outside" else "b:%d" % int(p["winner"]["id"])
		var got: int = w.ledger.pay(src, w.acct_p(clerk), amount, "kickbacks")
		p["kickback"] = {"clerk": int(clerk["id"]), "amount": got}
		p["quality_target"] = float(p["quality_target"]) * 0.85
		_event(w, p, "City clerk %s accepted %s from %s and signed off on inspections without looking closely." % [w.full_name(clerk), LTMoney.fmt(got), p["winner_name"]])
		w.log_sim(clerk, "Took %s from %s to go easy on inspections. Reason: greed beat honesty, and money was tight." % [LTMoney.fmt(got), p["winner_name"]], true)
		w.chronicle_add("Paper trail: city clerk %s took %s from %s during \"%s\"." % [w.full_name(clerk), LTMoney.fmt(got), p["winner_name"], p["title"]], "project", true, [clerk["id"]])
	else:
		_event(w, p, "%s offered city clerk %s a %s \"thank you\". The clerk refused and wrote it down." % [p["winner_name"], w.full_name(clerk), LTMoney.fmt(amount)])
		w.log_sim(clerk, "Refused a %s bribe from %s and reported it. Reason: honesty." % [LTMoney.fmt(amount), p["winner_name"]], true)
		if str(p["winner"]["kind"]) == "outside":
			w.companies[int(p["winner"]["id"])]["defects"] = int(w.companies[int(p["winner"]["id"])]["defects"]) + 1


static func _finish(w: LTWorld, p: Dictionary) -> void:
	_progress_payment(w, p)
	var floor_q: float = 0.1 + float(w.city["laws"].get("building_code", 1.0)) * 0.12
	var q: float = clampf(float(p["quality_target"]) + w.rng.randf_range(-0.04, 0.04), floor_q, 1.0)
	var defect: bool = w.rng.randf() < (0.5 - q * 0.5)
	if defect:
		q *= 0.85
		_event(w, p, "Inspection found defects: %s." % ("cracked base and thin asphalt" if is_road(str(p["ptype"])) else "a leaking roof and uneven floors"))
	p["quality"] = q
	p["status"] = "done"
	if int(p["lot"]) >= 0 and str(p["ptype"]) != "remodel":
		w.lot(int(p["lot"]))["build_quality"] = q
	p["done_day"] = w.day
	p["warranty_until"] = w.day + 365 * int(p["warranty_years"])
	var late: int = (w.day - int(p["start_day"])) - int(p["days_promised"])
	var over: int = int(p["change_orders"])
	_event(w, p, "Finished. Quality %d of 100 (grade %s). %s %s" % [int(q * 100.0), _grade(q), "Finished %d days late." % late if late > 0 else "On time.", "Cost %s over the bid in change orders." % LTMoney.fmt(over) if over > 0 else "No change orders."])
	var sp: Dictionary = p.get("spec", {})
	if late > 0 and bool(sp.get("penalty", false)) and not bool(p["private"]):
		var pen: int = int(float(p["price"]) * minf(0.2, LATE_PENALTY * float(late)))
		var from: String = _payee(w, p)
		if from != "outside":
			pen = mini(pen, maxi(0, w.ledger.bal(from)))
		if pen > 0:
			w.ledger.pay(from, _payer(w, p), pen, "late penalty")
			p["penalty_paid"] = pen
			_event(w, p, "%s paid %s in late penalties under the contract." % [p["winner_name"], LTMoney.fmt(pen)])
	if str(p["winner"]["kind"]) == "outside":
		var co: Dictionary = w.companies[int(p["winner"]["id"])]
		co["quality_hist"].append(q)
		co["jobs"] = int(co["jobs"]) + 1
		co["workload"] = maxi(0, int(co["workload"]) - 1)
		if late > 0:
			co["late"] = int(co["late"]) + 1
		if over > 0:
			co["overruns"] = int(co["overruns"]) + 1
		if defect:
			co["defects"] = int(co["defects"]) + 1
	else:
		var b: Dictionary = w.biz(int(p["winner"]["id"]))
		b["jobs_done"] = int(b["jobs_done"]) + 1
		b["quality_avg"] = (float(b.get("quality_avg", q)) * float(int(b["jobs_done"]) - 1) + q) / float(b["jobs_done"])
		b["reputation"] = clampf(float(b["reputation"]) + (q - 0.6) * 20.0 - (5.0 if late > 0 else 0.0), 0.0, 100.0)
		if late > 0:
			b["overruns"] = int(b["overruns"]) + 1
		if defect:
			b["defects"] = int(b["defects"]) + 1
		w.log_biz(b, "Finished \"%s\" with quality %d." % [p["title"], int(q * 100.0)])
	var ptype: String = str(p["ptype"])
	w.dist_cache.clear()
	if ptype == "road_build":
		var st2: Dictionary = w.streets[int(p["street"])]
		for k in ["surface", "width", "sidewalks", "lights"]:
			if sp.has(k):
				st2[k] = sp[k]
		for sid in p["segments"]:
			LTGeography.open_segment(w, int(sid), q)
			w.roads[int(sid)]["last_project"] = int(p["id"])
			w.roads[int(sid)]["repaired_day"] = w.day
		p["condition_at_finish"] = LTGeography.street_condition(w, int(p["street"]))
		p["expected_repair_days"] = expected_days_to_repair(w, int(p["street"]))
	elif is_road(ptype):
		var st: Dictionary = w.streets[int(p["street"])]
		for sid in st["segments"]:
			var s: Dictionary = w.roads[int(sid)]
			if ptype == "road_patch":
				s["condition"] = minf(100.0, float(s["condition"]) + 30.0 * (0.5 + q * 0.5))
				s["quality"] = (float(s["quality"]) + q) / 2.0
			else:
				s["condition"] = 70.0 + q * 30.0
				s["quality"] = q
			s["last_project"] = int(p["id"])
			s["repaired_day"] = w.day
		p["condition_at_finish"] = LTGeography.street_condition(w, int(p["street"]))
		p["expected_repair_days"] = expected_days_to_repair(w, int(p["street"]))
		_event(w, p, "At this quality the street should need repair again in about %d days." % int(p["expected_repair_days"]))
	elif ptype == "remodel":
		LTHomes.finish_remodel(w, p, w.lot(int(p["lot"])))
	elif ptype == "house":
		var l2: Dictionary = w.lot(int(p["lot"]))
		l2["use"] = "house"
		l2["building"] = "house"
		l2["units"] = [-1]
		l2["condition"] = 60.0 + q * 40.0
		l2["built_day"] = w.day
		l2["value"] = int(p["price"]) + int(p["change_orders"]) + int(l2["value"])
		if p.has("home"):
			l2["home"] = p["home"]
		if str(p["developer"].get("kind", "")) == "spec":
			LTDevelopers.list_spec_house(w, p, l2)
		else:
			LTFounder.settler_moves_in(w, p, l2)
	elif ptype == "shop":
		var sb: Dictionary = w.biz(int(p.get("business_id", -1)))
		if not sb.is_empty() and str(sb["status"]) == "building":
			sb["building_quality"] = q
			LTEconomy.open_business(w, sb)
	elif ptype == "mayor_house":
		var l3: Dictionary = w.lot(int(p["lot"]))
		l3["use"] = "mayor_house"
		l3["building"] = "mayor_house"
		l3["name"] = "The Mayor's House"
		l3["owner_kind"] = "city"
		l3["condition"] = 60.0 + q * 40.0
		l3["built_day"] = w.day
		w.player["home_lot"] = int(p["lot"])
		w.chronicle_add("%s moved out of the camper and into the mayor's house on %s." % [w.player["name"], LTGeography.lot_street(w, int(p["lot"]))["name"]], "city", true, [])
	elif ptype == "apartments":
		var l: Dictionary = w.lot(int(p["lot"]))
		l["use"] = "apartment"
		l["building"] = "apartment"
		var units: Array = []
		for k in int(w.city["laws"].get("zoning_density", 4)):
			units.append(-1)
		l["units"] = units
		l["unit_rent"] = LTMoney.dollars(880.0)
		l["condition"] = 60.0 + q * 40.0
		l["built_day"] = w.day
		l["value"] = int(p["price"]) + int(p["change_orders"])
		var dev: Dictionary = p["developer"]
		if str(dev["kind"]) == "business":
			l["owner_kind"] = "business"
			l["owner_id"] = int(dev["id"])
			l["name"] = str(w.biz(int(dev["id"]))["name"])
		else:
			l["owner_kind"] = "outside"
			l["owner_id"] = -1
			l["name"] = "Plains Property Group apartments"
	else:
		var kind: String = ptype.replace("_small", "")
		LTCivic.add_service(w, kind, int(p["lot"]), q, "small" if ptype.ends_with("_small") else "full")
	w.counters["projects_done"] = int(w.counters["projects_done"]) + 1
	w.chronicle_add("\"%s\" is finished by %s. Quality %d of 100.%s" % [p["title"], p["winner_name"], int(q * 100.0), " %d days late." % late if late > 0 else ""], "project", true, [])


static func expected_days_to_repair(w: LTWorld, street_id: int) -> float:
	var cond: float = LTGeography.street_condition(w, street_id)
	var q: float = LTGeography.street_quality(w, street_id)
	var rate: float = (0.02 + (1.0 - q) * (1.0 - q) * 0.22) * 1.35 - 0.005
	return maxf(0.0, (cond - 40.0) / maxf(rate, 0.001))


static func _watch_quality(w: LTWorld, p: Dictionary) -> void:
	if not is_road(str(p["ptype"])) or int(p["repair_needed_day"]) >= 0:
		return
	var st: int = int(p["street"])
	var mine: bool = false
	for sid in w.streets[st]["segments"]:
		if int(w.roads[int(sid)]["last_project"]) == int(p["id"]):
			mine = true
	if not mine:
		return
	if LTGeography.street_condition(w, st) < 40.0:
		p["repair_needed_day"] = w.day
		if int(p.get("first_repair_day", -1)) < 0:
			p["first_repair_day"] = w.day
		var days: int = w.day - int(p["done_day"])
		var note: String = "%s needs repair again, %d days after %s finished it at quality %d." % [w.streets[st]["name"], days, p["winner_name"], int(float(p["quality"]) * 100.0)]
		if w.day <= int(p["warranty_until"]):
			note += " It is still under warranty, so %s must fix it at its own cost." % p["winner_name"]
		_event(w, p, note)
		w.city["repair_needs"].append({"day": w.day, "street": st, "project": int(p["id"]), "text": note})
		w.chronicle_add(note, "project", true, [])
		if w.day <= int(p["warranty_until"]):
			_warranty_fix(w, p)


static func _warranty_fix(w: LTWorld, p: Dictionary) -> void:
	for sid in w.streets[int(p["street"])]["segments"]:
		var s: Dictionary = w.roads[int(sid)]
		s["condition"] = minf(100.0, float(s["condition"]) + 25.0)
	_event(w, p, "Warranty repair done by %s at its own cost." % p["winner_name"])
	p["warranty_repairs"] = int(p.get("warranty_repairs", 0)) + 1
	p["repair_needed_day"] = -1
	if str(p["winner"]["kind"]) == "local":
		var b: Dictionary = w.biz(int(p["winner"]["id"]))
		w.ledger.pay(w.acct_b(b), "outside", int(float(p["price"]) * 0.08), "warranty_repairs")


# ---------------------------------------------------------------- private building

static func _developers(w: LTWorld) -> void:
	var homeless: int = 0
	for h in w.households:
		if int(h["lot"]) < 0 and not w.household_members(h).is_empty():
			homeless += 1
	var pressure: float = float(homeless) * 10.0 + (20.0 if LTPeople.vacancy_count(w) == 0 else 0.0) + LTPeople.town_pull(w) * 0.3
	if pressure < 25.0:
		return
	for p in w.projects:
		if str(p["ptype"]) == "apartments" and ["draft", "bidding", "review", "building"].has(str(p["status"])):
			return
	var lots: Array = LTGeography.vacant_lots(w, ["residential", "mixed"])
	if lots.is_empty():
		return
	# a Sim landlord with money and credit may build, otherwise the outside property group does
	var dev: Dictionary = {"kind": "outside", "id": -1, "name": "Plains Property Group", "acct": "outside"}
	for b in w.open_businesses("landlord"):
		var owner: Dictionary = w.cit(int(b["owners"][0]))
		if not w.is_present(owner):
			continue
		var t: Dictionary = owner["traits"]
		if float(t["ambition"]) + float(t["risk"]) < 100.0:
			continue
		var need: int = BASE_COST["apartments"]
		var dec: Dictionary = LTFinance.bank_decision(w, owner, "mortgage", int(float(need) * 0.8), LTFinance.monthly_income(w, owner) + LTMoney.dollars(3000.0))
		if bool(dec["ok"]) and w.biz_cash(b) >= int(float(need) * 0.05):
			var loan: int = int(float(need) * 1.1)
			var d: Dictionary = LTFinance.new_debt(w, "b", int(b["id"]), "bank", -1, "construction_loan", loan, float(dec["rate"]), 300, "house", int(lots[0]["id"]), [])
			if str(b["legal_form"]) == "llc":
				d["guarantor"] = int(owner["id"])
				w.debt_index_dirty = true
			LTFinance.fund_loan(w, d, w.acct_b(b), loan)
			w.bank["lent_12m"] = int(w.bank["lent_12m"]) + loan
			dev = {"kind": "business", "id": int(b["id"]), "name": b["name"], "acct": w.acct_b(b)}
			w.log_sim(owner, "Decided to build a 4 unit apartment house. Reason: no vacancies in town and a %s construction loan came through." % LTMoney.fmt(loan), true)
			break
	var r: Dictionary = define_project(w, "apartments", int(lots[0]["id"]), int(float(BASE_COST["apartments"]) * 1.3), -1, false, dev)
	if bool(r["ok"]):
		var p2: Dictionary = w.projects[int(r["project_id"])]
		p2["title"] = "%s: 4 unit apartment house" % dev["name"]
		_event(w, p2, "Private project by %s. They pick the builder, not the mayor." % dev["name"])


static func _developer_award(w: LTWorld, p: Dictionary) -> void:
	var best: int = -1
	var best_s: float = -1e18
	for i in p["bids"].size():
		var b: Dictionary = p["bids"][i]
		var s: float = -float(b["price"]) / 100.0 + (float(b["hidden_quality"]) * 0.5 + 0.5) * 50000.0 * (0.6 if str(b["grade"]) == "new" else 1.0)
		if bool(b["local"]):
			s += 8000.0
		if s > best_s:
			best_s = s
			best = i
	if best >= 0:
		_start(w, p, p["bids"][best])
		_event(w, p, "%s picked %s for %s." % [p["developer"]["name"], p["bids"][best]["name"], LTMoney.fmt(int(p["bids"][best]["price"]))])
