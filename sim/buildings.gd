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
	return LTBizSpecs.SPECS.has(btype)


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
	# how the floor is split: a smart owner sizes the work rooms to the customer
	# rooms; a greedy one squeezes in more seats than the kitchen can keep up with
	var spec: Dictionary = LTBizSpecs.of(btype)
	plan["v"] = 2
	plan["mix"] = 0.0
	if spec.has("flex"):
		var fl: Array = spec["flex"]
		var a_lbl: String = _room_label(btype, str(fl[0])).to_lower()
		var b_lbl: String = _room_label(btype, str(fl[1])).to_lower()
		if tr.call("greed") > 65.0 and tr.call("intelligence") < 55.0:
			plan["mix"] = 0.25
			why.append("a bigger %s to fit more customers in, with a smaller %s" % [a_lbl, b_lbl])
		elif tr.call("intelligence") > 60.0:
			why.append("the %s sized to what the %s can keep up with" % [b_lbl, a_lbl])
	plan["code"] = LTBizSpecs.code_for(w, btype)
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


static func _room_label(btype: String, key: String) -> String:
	for r in LTBizSpecs.of(btype).get("rooms", []):
		if str(r[0]) == key:
			return str(r[1])
	return key


## The rooms and their square feet, from the shares for this kind of business.
static func rooms_for(plan: Dictionary) -> Array:
	var spec: Dictionary = LTBizSpecs.of(str(plan["type"]))
	var rooms: Array = spec.get("rooms", [["main", "Work floor", 0.8, "b"], ["office", "Office", 0.12, "f"], ["rest", "Restroom", 0.08, "b"]])
	# mix: the part of the work room given over to customers (a quarter, for a greedy owner)
	var mix: float = float(plan.get("mix", 0.0))
	var fl: Array = spec.get("flex", ["", ""])
	var moved: float = 0.0
	for r in rooms:
		if str(r[0]) == str(fl[1]):
			moved = float(r[2]) * mix
	var out: Array = []
	for r in rooms:
		var share: float = float(r[2])
		if str(r[0]) == str(fl[0]):
			share += moved
		elif str(r[0]) == str(fl[1]):
			share -= moved
		out.append({"key": str(r[0]), "label": str(r[1]), "sqft": int(float(plan["sqft"]) * share), "zone": str(r[3]) if r.size() > 3 else "b"})
	return out


## The rooms of a plan; plans from before the full room lists get them now.
static func rooms_of(plan: Dictionary) -> Array:
	if int(plan.get("v", 1)) < 2 and LTBizSpecs.SPECS.has(str(plan.get("type", ""))):
		plan["v"] = 2
		plan["rooms"] = rooms_for(plan)
	return plan.get("rooms", [])


static func _room_sqft(plan: Dictionary, key: String) -> float:
	for r in rooms_of(plan):
		if str(r["key"]) == key:
			return float(r["sqft"])
	return 0.0


## Every room that limits how many customers a day: [what, customers a day, units].
## The smallest is the bottleneck.
static func limits(plan: Dictionary) -> Array:
	var cfg: Dictionary = LTBizSpecs.of(str(plan.get("type", "")))
	if cfg.is_empty() or str(cfg.get("unit", "")) == "":
		return []
	var units: float = _room_sqft(plan, str(cfg["unit"])) / float(cfg["per"])
	if bool(cfg.get("count", false)):
		units = floorf(units)
	units = maxf(1.0, units)
	var out: Array = [[str(cfg["unit"]), units * float(cfg.get("serve", 1.0)), units]]
	for lm in cfg.get("limits", []):
		out.append([str(lm[2]), maxf(1.0, _room_sqft(plan, str(lm[0])) / float(lm[1])), 0.0])
	return out


## How many customers a day the building can serve (by its rooms), or -1 for no limit.
static func capacity(plan: Dictionary) -> float:
	var lm: Array = limits(plan)
	if lm.is_empty():
		return -1.0
	var c: float = INF
	for x in lm:
		c = minf(c, float(x[1]))
	return c


## The room that holds the business back, or "" when the main room does.
static func bottleneck(plan: Dictionary) -> String:
	var lm: Array = limits(plan)
	if lm.size() < 2:
		return ""
	var low: Array = lm[0]
	for x in lm:
		if float(x[1]) < float(low[1]) - 0.01:
			low = x
	return "" if low == lm[0] else str(low[0])


## Words for the capacity: "36 seats", "4 service bays".
static func capacity_text(plan: Dictionary) -> String:
	var cfg: Dictionary = LTBizSpecs.of(str(plan.get("type", "")))
	var lm: Array = limits(plan)
	if lm.is_empty():
		return ""
	var n: int = int(lm[0][2])
	var t: String
	match str(cfg["unit"]):
		"dining":
			t = "%d seats" % n
		"bays":
			t = "%d service bay%s" % [n, "" if n == 1 else "s"]
		"exam":
			t = "%d exam room%s" % [n, "" if n == 1 else "s"]
		"rooms":
			t = "%d guest rooms" % n
		"class":
			t = "room for %d children" % n
		_:
			t = "%s sq ft of %s" % [LTGeography._thousands(int(_room_sqft(plan, str(cfg["unit"])))), _room_label(str(plan["type"]), str(cfg["unit"])).to_lower()]
	var bn: String = bottleneck(plan)
	if bn != "":
		t += ", but the %s only keeps up with about %d customers a day" % [bn, int(capacity(plan))]
	return t


## The equipment that goes in, priced to the owner's equipment budget.
static func equipment_list(plan: Dictionary) -> Array:
	var cs: Dictionary = LTEconomy.COSTS.get(str(plan.get("type", "")), {})
	return LTBizSpecs.equipment(str(plan.get("type", "")), float(cs.get("equipment", 0)))


## The code rules the building was built to: [rule, authority].
static func code_list(plan: Dictionary) -> Array:
	if plan.has("code"):
		return plan["code"]
	return LTBizSpecs.code_for(null, str(plan.get("type", "")))


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
	var st: int = int(plan.get("stories", 1))
	var parts: Array = ["%s sq ft%s" % [LTGeography._thousands(int(plan["sqft"])), "" if st == 1 else ", %d stories" % st]]
	var ct: String = capacity_text(plan)
	if ct != "":
		parts.append(ct)
	var mk: String = str(LTBizSpecs.of(str(plan["type"])).get("make", ""))
	if mk != "" and ct == "":
		parts.append("%d rooms built for %s" % [rooms_of(plan).size(), mk])
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
	var foot: float = float(plan["sqft"]) / LTHomes.M2 / float(maxi(1, stories - (1 if plan.get("features", []).has("apartments") else 0)))
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


## Rooms inside, for the floor plan: the customer side across the front where
## people come in, the back of house behind it, the way these places are built.
static func floor_plan(l: Dictionary, plan: Dictionary) -> Array:
	var lay: Dictionary = layout(l, plan)
	var W: float = float(lay["W"])
	var D: float = float(lay["D"])
	var front: Array = []
	var back: Array = []
	for r in rooms_of(plan):
		if str(r.get("zone", "b")) == "f":
			front.append(r)
		else:
			back.append(r)
	if front.is_empty() and not back.is_empty():
		front.append(back.pop_front())
	var rows: Array = [front]
	if back.size() > 5:
		rows.append(back.slice(0, int(ceil(back.size() / 2.0))))
		rows.append(back.slice(int(ceil(back.size() / 2.0))))
	elif not back.is_empty():
		rows.append(back)
	var total: float = 0.0
	for row in rows:
		for r in row:
			total += float(r["sqft"])
	var rects: Array = []
	var d: float = 0.0
	for row in rows:
		var rt: float = 0.0
		for r in row:
			rt += float(r["sqft"])
		var rd: float = D * rt / maxf(1.0, total)
		var x: float = 0.0
		for r in row:
			var rw: float = W * float(r["sqft"]) / maxf(1.0, rt)
			rects.append([x, d, x + rw, d + rd, str(r["label"])])
			x += rw
		d += rd
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
		if PRODUCERS.has(str(b["type"])):
			_grow_production(w, b)
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
			l = w.lot(int(b["lot"]))
			lay = layout(l, plan)
	if not bool(lay["fits"]):
		# no more land: build up, as far as the city's height limit allows
		if not _go_up(w, b, plan, l):
			w.log_biz(b, "Wanted to add %d square feet but the lot is full, no land next door is for sale, and the city's height limit is %d stories. Reason: %s." % [add, height_limit(w), why])
			return
		price = int(float(price) * height_premium(int(plan["stories"])))
		why += "; the lot is full, so the addition goes up to %d stories" % int(plan["stories"])
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


const PRODUCERS: Array = ["farm", "factory", "mill", "sawmill", "quarry"]
const ACRE_PRICE: int = 550000          # $5,500 an acre of South Dakota cropland


static func height_limit(w: LTWorld) -> int:
	return int(w.city["laws"].get("height_limit", 3))


## Taller costs more per square foot: an elevator from three stories, a steel or
## concrete frame from five, high rise fire code (sprinklers, standpipes, a fire
## command room) from eight.
static func height_premium(stories: int) -> float:
	if stories >= 8:
		return 1.7
	if stories >= 5:
		return 1.4
	if stories >= 3:
		return 1.2
	return 1.0


## Add a story on the same footprint, if the code and the height limit allow.
static func _go_up(w: LTWorld, b: Dictionary, plan: Dictionary, l: Dictionary) -> bool:
	if str(plan.get("style", "")) == "metal":
		return false
	var apt: int = 1 if plan.get("features", []).has("apartments") else 0
	var floors_now: int = maxi(1, int(b["bplan"].get("stories", 1)) - apt)
	var need: int = int(ceil(float(plan["sqft"]) / (float(b["bplan"]["sqft"]) / float(floors_now))))
	if need + apt > height_limit(w):
		return false
	plan["stories"] = need + apt
	return bool(layout(l, plan)["fits"])


## A producer that keeps making money grows: more floor, more machines, more
## crew, and a farm buys the next quarter section of land.
static func _grow_production(w: LTWorld, b: Dictionary) -> void:
	var hist: Array = b.get("month_profit_hist", [])
	if hist.size() < 12:
		return
	var tot: float = 0.0
	for i in range(hist.size() - 12, hist.size()):
		if int(hist[i]) <= 0:
			return
		tot += float(hist[i])
	var avg: float = tot / 12.0
	var owner: Dictionary = w.cit(int(b["owners"][0]))
	if owner.is_empty() or float(owner["traits"]["ambition"]) < 45.0:
		return
	var btype: String = str(b["type"])
	var cs: Dictionary = LTEconomy.COSTS.get(btype, {})
	var plan: Dictionary = b["bplan"].duplicate(true)
	var add: int = maxi(800, int(float(plan["sqft"]) * 0.4))
	plan["sqft"] = int(plan["sqft"]) + add
	plan["rooms"] = rooms_for(plan)
	var price: int = LTMoney.dollars(float(add) * LTEconomy.SHED_PER_SQFT + float(cs.get("equipment", 0)) * 0.35)
	var acres: int = 0
	if btype == "farm":
		acres = 160
		price += acres * ACRE_PRICE
	# a careful owner wants it paid back within about eight years
	var payback: float = float(price) / maxf(1.0, avg * 12.0 * 0.35)
	if payback > 6.0 + float(owner["traits"]["risk"]) / 25.0:
		w.log_biz(b, "Thought about growing. Reason it waits: %s would take %.0f years to pay back at today's profits." % [LTMoney.fmt(price), payback])
		b["expanded_day"] = w.day - 365
		return
	var acct: String = w.acct_b(b)
	if w.biz_cash(b) < int(float(price) * 0.25):
		return
	var l: Dictionary = w.lot(int(b["lot"]))
	if not bool(layout(l, plan)["fits"]) and acres == 0:
		if not LTLand.assemble_for(w, b):
			w.log_biz(b, "Wanted to grow by %d square feet but the lot is full and no land next door is for sale." % add)
			b["expanded_day"] = w.day - 365
			return
		l = w.lot(int(b["lot"]))
	var down: int = mini(w.biz_cash(b) - LTMoney.dollars(20000.0), int(float(price) * 0.3))
	w.ledger.pay(acct, "outside", down, "expansion")
	var d: Dictionary = LTFinance.new_debt(w, "b", int(b["id"]), "bank", -1, "business_loan", price - down, 0.075 if acres == 0 else 0.068, 120 if acres == 0 else 300, "expansion" if acres == 0 else "farmland", int(l["id"]), [])
	LTFinance.fund_loan(w, d, "outside", price - down)
	b["bplan"] = plan
	b["equipment"] = float(b.get("equipment", 1.0)) + 0.35
	b["target_staff"] = int(b["target_staff"]) + 2
	b["expanded_day"] = w.day
	if acres > 0:
		b["acres"] = int(b.get("acres", 160)) + acres
	var why: String = "a year of steady profit, about %s a month, and it pays back in about %.0f years" % [LTMoney.fmt(int(avg)), payback]
	var what: String = ("bought another %d acres (now %d) and a bigger machine shed" % [acres, int(b["acres"])]) if acres > 0 else ("added %s square feet and new equipment" % LTGeography._thousands(add))
	w.log_biz(b, "Grew: %s, %s, and is hiring two more. Reason: %s." % [what, LTMoney.fmt(price), why])
	w.log_sim(owner, "Decided to grow %s. Reason: %s." % [b["name"], why], true)
	w.chronicle_add("%s is growing: %s and two more jobs." % [b["name"], what], "business", true, [owner["id"]])


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
