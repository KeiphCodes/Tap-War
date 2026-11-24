class_name LTBuildings
extends RefCounted
## Business buildings designed by their owners, room by room.
##
## An owner lays out the building for the business they mean to run: how big, how
## many seats or bays or exam rooms, a drive-through window, a patio, a loading
## dock, parking, apartments upstairs to rent out. Personality and money decide,
## and every choice is written down with the reason. The building's rooms set how
## many customers it can serve; the features bring in more business. When a
## business outgrows its building the owner adds on.

const ROOMS: Dictionary = {
	# key: [[room, label, share of the floor], ...], what sets capacity, per unit
	"grocery": {"rooms": [["sales", "Sales floor", 0.62], ["stock", "Stockroom", 0.16], ["cooler", "Walk in cooler", 0.08], ["office", "Office", 0.05], ["rest", "Restrooms", 0.04], ["break", "Break room", 0.05]], "unit": "sales", "per": 22.0, "serve": 1.0},
	"general_store": {"rooms": [["sales", "Sales floor", 0.68], ["stock", "Stockroom", 0.2], ["office", "Office", 0.07], ["rest", "Restroom", 0.05]], "unit": "sales", "per": 22.0, "serve": 1.0},
	"pharmacy": {"rooms": [["sales", "Sales floor", 0.55], ["rx", "Pharmacy counter", 0.2], ["stock", "Stockroom", 0.15], ["office", "Office", 0.05], ["rest", "Restroom", 0.05]], "unit": "sales", "per": 18.0, "serve": 1.0},
	"outfitter": {"rooms": [["sales", "Sales floor", 0.6], ["rental", "Rental and repair", 0.2], ["stock", "Stockroom", 0.15], ["rest", "Restroom", 0.05]], "unit": "sales", "per": 25.0, "serve": 1.0},
	"cafe": {"rooms": [["dining", "Dining room", 0.55], ["kitchen", "Kitchen", 0.3], ["cooler", "Walk in cooler", 0.05], ["rest", "Restrooms", 0.07], ["office", "Office", 0.03]], "unit": "dining", "per": 15.0, "serve": 3.0, "seat": true},
	"bar": {"rooms": [["dining", "Barroom", 0.6], ["kitchen", "Kitchen", 0.2], ["cooler", "Cooler", 0.07], ["rest", "Restrooms", 0.1], ["office", "Office", 0.03]], "unit": "dining", "per": 15.0, "serve": 3.0, "seat": true},
	"bakery": {"rooms": [["bake", "Bake room", 0.5], ["counter", "Front counter", 0.3], ["stock", "Flour storage", 0.12], ["rest", "Restroom", 0.08]], "unit": "counter", "per": 10.0, "serve": 1.0},
	"clinic": {"rooms": [["wait", "Waiting room", 0.18], ["exam", "Exam rooms", 0.4], ["lab", "Lab", 0.1], ["office", "Offices", 0.14], ["nurse", "Nurse station", 0.08], ["rest", "Restrooms", 0.1]], "unit": "exam", "per": 110.0, "serve": 16.0, "count": true},
	"repair_shop": {"rooms": [["bays", "Service bays", 0.72], ["parts", "Parts room", 0.12], ["office", "Office and counter", 0.1], ["rest", "Restroom", 0.06]], "unit": "bays", "per": 450.0, "serve": 5.0, "count": true},
	"construction": {"rooms": [["shop", "Shop", 0.65], ["office", "Office", 0.15], ["tools", "Tool room", 0.15], ["rest", "Restroom", 0.05]], "unit": "", "per": 0.0},
	"childcare": {"rooms": [["class", "Classrooms", 0.5], ["nap", "Nap room", 0.15], ["kitchen", "Kitchen", 0.12], ["office", "Office", 0.08], ["rest", "Restrooms", 0.15]], "unit": "class", "per": 35.0, "serve": 1.0},
	"private_school": {"rooms": [["class", "Classrooms", 0.6], ["gym", "Gym and lunchroom", 0.2], ["office", "Office", 0.1], ["rest", "Restrooms", 0.1]], "unit": "class", "per": 30.0, "serve": 1.0},
	"law_office": {"rooms": [["offices", "Offices", 0.55], ["reception", "Reception", 0.2], ["conf", "Conference room", 0.17], ["rest", "Restroom", 0.08]], "unit": "", "per": 0.0},
	"real_estate": {"rooms": [["offices", "Offices", 0.55], ["reception", "Reception", 0.3], ["rest", "Restroom", 0.15]], "unit": "", "per": 0.0},
	"bank": {"rooms": [["lobby", "Lobby", 0.35], ["teller", "Teller line", 0.15], ["vault", "Vault", 0.1], ["offices", "Loan offices", 0.3], ["rest", "Restrooms", 0.1]], "unit": "", "per": 0.0},
	"hotel": {"rooms": [["rooms", "Guest rooms", 0.72], ["lobby", "Lobby", 0.12], ["laundry", "Laundry", 0.08], ["office", "Office", 0.08]], "unit": "rooms", "per": 330.0, "serve": 1.0, "count": true},
	"funeral_home": {"rooms": [["chapel", "Chapel", 0.4], ["view", "Viewing room", 0.2], ["prep", "Prep room", 0.15], ["office", "Office", 0.15], ["rest", "Restrooms", 0.1]], "unit": "", "per": 0.0},
}
const FEATURE_PRICE: Dictionary = {
	"drive_thru": 45000, "patio": 15000, "dock": 30000, "parking": 2500, "awning": 6000, "apartments": 95000,
	"hood": 25000, "neon": 4000, "brick_front": 30000, "solar": 40000, "playground": 18000,
}
const FEATURE_LABEL: Dictionary = {
	"drive_thru": "drive-through window", "patio": "outdoor patio seating", "dock": "loading dock", "awning": "awning over the sidewalk",
	"apartments": "apartments upstairs to rent out", "hood": "kitchen hood and fire suppression", "neon": "neon sign",
	"brick_front": "brick front", "solar": "solar panels", "playground": "fenced playground",
}


static func has_rooms(btype: String) -> bool:
	return ROOMS.has(btype)


## Features a business must have to open: a cook line needs a hood, a daycare a
## fenced playground. The rest are wishes the owner pays for out of spare money.
const REQUIRED: Dictionary = {"cafe": ["hood"], "bar": ["hood"], "childcare": ["playground"]}
## Wishes in the order an owner gives them up when money is short.
const GIVE_UP: Array = ["solar", "apartments", "brick_front", "drive_thru", "neon", "awning", "patio", "dock"]


## The owner's design, from the business and the owner's own traits. `spare` is
## the money left over after the basic building, equipment, stock and reserve.
static func design(w: LTWorld, btype: String, owner: Dictionary, sqft: int, spare: int) -> Dictionary:
	var money: int = spare
	var t: Dictionary = owner.get("traits", {})
	var tr: Callable = func(k: String) -> float: return float(t.get(k, 50.0))
	var why: Array = []
	var feats: Array = []
	var shed: bool = bool(LTEconomy.COSTS.get(btype, {}).get("shed", false))
	var plan: Dictionary = {"type": btype, "sqft": sqft, "stories": 1, "features": feats, "why": why, "color": w.rng.randi_range(0, 5),
		"style": "metal" if shed else ("brick" if tr.call("discipline") > 60.0 else "storefront")}
	if str(plan["style"]) == "brick":
		feats.append("brick_front")
		why.append("a brick front that will look good for fifty years")
	var rich: bool = money > LTMoney.dollars(150000.0)
	match btype:
		"cafe", "bar":
			feats.append("hood")
			if tr.call("sociability") > 50.0:
				feats.append("patio")
				why.append("patio seating for summer evenings")
			if btype == "cafe" and tr.call("ambition") > 60.0 and rich:
				feats.append("drive_thru")
				why.append("a drive-through for coffee on the way to work")
			if btype == "bar":
				feats.append("neon")
		"pharmacy", "bank":
			if tr.call("ambition") > 45.0:
				feats.append("drive_thru")
				why.append("a drive-through so people can stay in the car in winter")
		"grocery", "general_store", "warehouse", "factory", "mill", "sawmill":
			feats.append("dock")
			why.append("a loading dock so the trucks can unload in any weather")
		"childcare":
			feats.append("playground")
	if not shed and tr.call("kindness") > 55.0:
		feats.append("awning")
	if ["grocery", "general_store", "cafe", "bar", "pharmacy", "clinic", "outfitter", "bakery", "repair_shop", "bank", "hotel"].has(btype):
		plan["parking"] = clampi(int(float(sqft) / 300.0), 4, 40)
		why.append("%d parking spaces" % int(plan["parking"]))
	# apartments upstairs: the old Main Street way to make a building pay
	if not shed and ["general_store", "cafe", "bakery", "pharmacy", "law_office", "real_estate", "bar", "outfitter"].has(btype) and tr.call("ambition") + tr.call("greed") > 115.0 and money > LTMoney.dollars(120000.0):
		feats.append("apartments")
		plan["stories"] = 2
		why.append("apartments upstairs to rent out, which pay the mortgage")
	if tr.call("intelligence") > 70.0 and rich:
		feats.append("solar")
	plan["rooms"] = rooms_for(plan)
	# keep only the wishes the spare money covers
	var given: Array = []
	for k in GIVE_UP:
		if extras_cost(plan) <= spare:
			break
		if feats.has(k) and not REQUIRED.get(btype, []).has(k):
			feats.erase(k)
			given.append(str(FEATURE_LABEL[k]))
			if k == "apartments":
				plan["stories"] = 1
	if extras_cost(plan) > spare and int(plan.get("parking", 0)) > 4:
		plan["parking"] = 4
	if not given.is_empty():
		why.append("went without %s to keep the start up affordable" % LTHomes._join(given.slice(0, 3)))
	return plan


## What the owner's choices add beyond the plain building.
static func extras_cost(plan: Dictionary) -> int:
	var t: int = 0
	for f in plan.get("features", []):
		if not REQUIRED.get(str(plan["type"]), []).has(str(f)):
			t += int(FEATURE_PRICE.get(str(f), 0))
	t += maxi(0, int(plan.get("parking", 0)) - 4) * int(FEATURE_PRICE["parking"])
	return LTMoney.dollars(float(t))


## The rooms and their square feet, from the shares for this kind of business.
static func rooms_for(plan: Dictionary) -> Array:
	var cfg: Dictionary = ROOMS.get(str(plan["type"]), {"rooms": [["main", "Work floor", 0.8], ["office", "Office", 0.12], ["rest", "Restroom", 0.08]]})
	var out: Array = []
	for r in cfg["rooms"]:
		out.append({"key": str(r[0]), "label": str(r[1]), "sqft": int(float(plan["sqft"]) * float(r[2]))})
	return out


## How many customers a day the building can serve (by its rooms), or -1 for no limit.
static func capacity(plan: Dictionary) -> float:
	var cfg: Dictionary = ROOMS.get(str(plan.get("type", "")), {})
	if cfg.is_empty() or str(cfg["unit"]) == "":
		return -1.0
	for r in plan.get("rooms", []):
		if str(r["key"]) == str(cfg["unit"]):
			var units: float = float(r["sqft"]) / float(cfg["per"])
			if bool(cfg.get("count", false)):
				units = floorf(units)
			return maxf(1.0, units) * float(cfg.get("serve", 1.0))
	return -1.0


## Words for the capacity: "36 seats", "4 service bays".
static func capacity_text(plan: Dictionary) -> String:
	var cfg: Dictionary = ROOMS.get(str(plan.get("type", "")), {})
	if cfg.is_empty() or str(cfg["unit"]) == "":
		return ""
	for r in plan.get("rooms", []):
		if str(r["key"]) == str(cfg["unit"]):
			var n: int = maxi(1, int(float(r["sqft"]) / float(cfg["per"])))
			match str(cfg["unit"]):
				"dining":
					return "%d seats" % n
				"bays":
					return "%d service bay%s" % [n, "" if n == 1 else "s"]
				"exam":
					return "%d exam room%s" % [n, "" if n == 1 else "s"]
				"rooms":
					return "%d guest rooms" % n
				"class":
					return "room for %d children" % n
				_:
					return "%s sq ft of %s" % [LTGeography._thousands(int(r["sqft"])), str(r["label"]).to_lower()]
	return ""


## More business from the building's features: a drive-through, summer patio.
static func revenue_factor(w: LTWorld, plan: Dictionary) -> float:
	var f: float = 1.0
	var feats: Array = plan.get("features", [])
	if feats.has("drive_thru"):
		f += 0.08 if LTCalendar.season(w.day) != "Winter" else 0.12
	if feats.has("patio") and LTCalendar.season(w.day) == "Summer" and w.weather == "Clear":
		f += 0.12
	if feats.has("awning") or feats.has("brick_front"):
		f += 0.02
	return f


static func price_list(plan: Dictionary) -> Array:
	var shed: bool = str(plan.get("style", "")) == "metal"
	var per: float = LTEconomy.SHED_PER_SQFT if shed else LTEconomy.STOREFRONT_PER_SQFT
	var lines: Array = [["%s building, %s sq ft" % ["Metal" if shed else "Storefront", LTGeography._thousands(int(plan["sqft"]))], int(float(plan["sqft"]) * per)]]
	for f in plan.get("features", []):
		lines.append([str(FEATURE_LABEL.get(str(f), str(f))).capitalize(), int(FEATURE_PRICE.get(str(f), 0))])
	if int(plan.get("parking", 0)) > 0:
		lines.append(["Parking lot, %d spaces" % int(plan["parking"]), int(plan["parking"]) * int(FEATURE_PRICE["parking"])])
	return lines


static func cost(plan: Dictionary) -> int:
	var t: int = 0
	for ln in price_list(plan):
		t += int(ln[1])
	return LTMoney.dollars(float(t))


static func text(plan: Dictionary) -> String:
	if plan.is_empty():
		return ""
	var parts: Array = ["%s sq ft%s" % [LTGeography._thousands(int(plan["sqft"])), ", two stories" if int(plan.get("stories", 1)) == 2 else ""]]
	var ct: String = capacity_text(plan)
	if ct != "":
		parts.append(ct)
	for f in plan.get("features", []):
		if ["drive_thru", "patio", "dock", "apartments", "playground"].has(str(f)):
			parts.append(str(FEATURE_LABEL[str(f)]))
	if int(plan.get("parking", 0)) > 0:
		parts.append("%d parking spaces" % int(plan["parking"]))
	return ", ".join(parts)


# ---------------------------------------------------------------- on the lot

## Where the building, parking and the rest stand, in the same lot coordinates as
## houses (x along the front, d back from the street). Storefronts come up to the
## sidewalk; metal shops sit back with a yard.
static func layout(l: Dictionary, plan: Dictionary) -> Dictionary:
	var fw: float = LTGeography.lot_frontage(l)
	var dp: float = LTGeography.lot_depth(l)
	var stories: int = int(plan.get("stories", 1))
	var foot: float = float(plan["sqft"]) / LTHomes.M2 / float(stories if stories == 2 and not plan.get("features", []).has("apartments") else 1)
	var feats: Array = plan.get("features", [])
	var shed: bool = str(plan.get("style", "")) == "metal"
	var park_n: int = int(plan.get("parking", 0))
	var park_w: float = 0.0
	if park_n > 0:
		park_w = minf(fw * 0.4, 2.7 * ceil(float(park_n) / maxf(1.0, floor((dp - 6.0) / 5.5))))
	var lane: float = 3.5 if feats.has("drive_thru") else 0.0
	var avail: float = maxf(6.0, fw - 1.0 - park_w - lane)
	var W: float = clampf(sqrt(foot * 1.3), 6.0, avail)
	var D: float = foot / W
	var front: float = 6.0 if shed else 1.5
	if D + front > dp - 2.0:
		D = maxf(5.0, dp - 2.0 - front)
	var x0: float = -fw * 0.5 + 0.5
	var out: Dictionary = {"W": W, "D": D, "fits": foot <= (fw - 1.0) * (dp - 2.0), "building": [x0, front, x0 + W, front + D], "door_x": x0 + W * 0.5}
	if park_n > 0:
		out["parking"] = [x0 + W + lane, 0.5, x0 + W + lane + park_w, minf(dp - 1.0, 0.5 + ceil(float(park_n) / maxf(1.0, floor(park_w / 2.7))) * 5.5)]
	if lane > 0.0:
		out["drive_thru"] = [x0 + W, front, x0 + W + lane, front + D]
	if feats.has("patio"):
		out["patio"] = [x0 + 0.5, 0.0, x0 + minf(W, 7.0), front if front > 1.0 else 0.0]
		if front <= 1.6:
			out["patio"] = [x0 + W * 0.55, front + D, x0 + W, minf(dp, front + D + 5.0)]
	if feats.has("dock"):
		out["dock"] = [x0 + W * 0.3, front + D, x0 + W * 0.7, minf(dp, front + D + 3.0)]
	if feats.has("playground"):
		out["playground"] = [x0, front + D + 1.0, x0 + minf(W, 10.0), minf(dp - 0.5, front + D + 9.0)]
	if shed:
		out["yard"] = [x0, front + D, fw * 0.5 - 0.5, dp - 0.5]
	return out


## Rooms inside, for the floor plan: one floor of rect rows like a house plan.
static func floor_plan(l: Dictionary, plan: Dictionary) -> Array:
	var lay: Dictionary = layout(l, plan)
	var W: float = float(lay["W"])
	var D: float = float(lay["D"])
	var rooms: Array = plan.get("rooms", [])
	var total: float = 0.0
	for r in rooms:
		total += float(r["sqft"])
	# the biggest room across the front, the rest in a row behind it
	var big: Dictionary = rooms[0] if not rooms.is_empty() else {}
	for r in rooms:
		if float(r["sqft"]) > float(big.get("sqft", 0)):
			big = r
	var fd: float = D * float(big.get("sqft", 0)) / maxf(1.0, total)
	var rects: Array = [[0.0, 0.0, W, fd, str(big.get("label", ""))]]
	var rest_t: float = total - float(big.get("sqft", 0))
	var x: float = 0.0
	for r in rooms:
		if r == big:
			continue
		var rw: float = W * float(r["sqft"]) / maxf(1.0, rest_t)
		rects.append([x, fd, x + rw, D, str(r["label"])])
		x += rw
	var out: Array = [{"name": "Ground floor", "rects": rects, "W": W, "D": D, "labels": true}]
	if plan.get("features", []).has("apartments"):
		out.append({"name": "Upstairs apartments", "rects": [[0.0, 0.0, W * 0.5, D, "Apartment 1"], [W * 0.5, 0.0, W, D, "Apartment 2"]], "W": W, "D": D, "labels": true})
	return out


## Site parts for the permit drawing: [[key, rect, label]].
static func site_parts(l: Dictionary, plan: Dictionary) -> Array:
	var lay: Dictionary = layout(l, plan)
	var out: Array = []
	for k in ["yard", "parking", "drive_thru", "patio", "dock", "playground", "building"]:
		if lay.has(k):
			out.append([k, lay[k], {"yard": "yard", "parking": "parking", "drive_thru": "drive-thru", "patio": "patio", "dock": "dock", "playground": "play", "building": str(plan["type"]).replace("_", " ")}[k]])
	return out


# ---------------------------------------------------------------- growing

## A busy, profitable business that has outgrown its building adds on.
static func monthly(w: LTWorld) -> void:
	for b in w.businesses:
		if str(b["status"]) != "open" or bool(b.get("home_based", false)) or not b.has("bplan"):
			continue
		if int(b["loss_months"]) > 0 or w.day - int(b.get("opened_day", 0)) < 365 or w.day - int(b.get("expanded_day", -9999)) < 730:
			continue
		var cap: float = capacity(b["bplan"])
		if cap < 0.0 or float(b.get("customers_avg", 0.0)) < cap * 0.9:
			continue
		_expand(w, b)


static func _expand(w: LTWorld, b: Dictionary) -> void:
	var owner: Dictionary = w.cit(int(b["owners"][0]))
	if owner.is_empty():
		return
	var plan: Dictionary = b["bplan"].duplicate(true)
	var add: int = maxi(400, int(float(plan["sqft"]) * 0.4))
	plan["sqft"] = int(plan["sqft"]) + add
	plan["rooms"] = rooms_for(plan)
	if int(plan.get("parking", 0)) > 0:
		plan["parking"] = int(plan["parking"]) + int(add / 300)
	var price: int = LTMoney.dollars(float(add) * 190.0)
	var acct: String = w.acct_b(b)
	if w.biz_cash(b) < int(float(price) * 0.3):
		return
	var l: Dictionary = w.lot(int(b["lot"]))
	var lay: Dictionary = layout(l, plan)
	var why: String = "turning customers away: the building serves about %d a day and more than that come" % int(capacity(b["bplan"]))
	if not bool(lay["fits"]):
		if LTLand.assemble_for(w, b):
			lay = layout(w.lot(int(b["lot"])), plan)
	if not bool(lay["fits"]):
		w.log_biz(b, "Wanted to add %d square feet but the lot is too small and no land next door is for sale. Reason: %s." % [add, why])
		return
	var r: Dictionary = LTProjects.define_project(w, "expansion", int(l["id"]), int(float(price) * 1.3), -1, false,
		{"kind": "business", "id": int(b["id"]), "name": str(b["name"]), "acct": acct}, price, add)
	if not bool(r.get("ok", false)):
		return
	var p: Dictionary = w.projects[int(r["project_id"])]
	p["title"] = "%s: a %d square foot addition" % [b["name"], add]
	p["bplan"] = plan
	p["business_id"] = int(b["id"])
	b["expanded_day"] = w.day
	# a construction loan for most of it, held in escrow so the builder gets paid
	var need: int = int(float(price) * 1.3)
	var down: int = mini(w.biz_cash(b), int(float(need) * 0.25))
	var escrow: String = "escrow:%d" % int(p["id"])
	w.ledger.pay(acct, escrow, down, "construction_escrow")
	var d: Dictionary = LTFinance.new_debt(w, "b", int(b["id"]), "bank", -1, "business_loan", need - down, 0.08, 120, "building", int(l["id"]), [])
	LTFinance.fund_loan(w, d, escrow, need - down)
	p["developer"]["acct"] = escrow
	p["developer"]["refund"] = acct
	w.log_biz(b, "Hired builders for a %d square foot addition, about %s. Reason: %s." % [add, LTMoney.fmt(price), why])
	w.log_sim(owner, "Decided to add on to %s. Reason: %s." % [b["name"], why], true)
	w.chronicle_add("%s is adding on: %d more square feet." % [b["name"], add], "business", false, [owner["id"]])


static func finish_expansion(w: LTWorld, p: Dictionary) -> void:
	var b: Dictionary = w.biz(int(p.get("business_id", -1)))
	if b.is_empty():
		return
	b["bplan"] = p["bplan"]
	_close_escrow(w, p)
	var l: Dictionary = w.lot(int(b["lot"]))
	l["value"] = int(l["value"]) + int(float(int(p["price"])) * 0.8)
	w.log_biz(b, "The addition is finished: %s." % text(b["bplan"]))
	w.chronicle_add("%s finished its addition." % b["name"], "business", false, [])


## What is left in a job's escrow goes back to the owner.
static func _close_escrow(w: LTWorld, p: Dictionary) -> void:
	var acct: String = str(p["developer"].get("acct", ""))
	if acct.begins_with("escrow:") and p["developer"].has("refund"):
		w.ledger.pay(acct, str(p["developer"]["refund"]), w.ledger.bal(acct), "construction_escrow")
