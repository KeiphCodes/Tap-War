class_name LTLand
extends RefCounted
## Property lines that owners redraw: merging lots they own, splitting a lot in two.
##
## As in a real town, combining two lots one owner already holds is paperwork the
## county recorder files (a lot combination). Splitting a lot creates a new
## building lot, so it is a plat that the mayor must approve or deny. Each new lot
## must meet the zoning minimums for width and area, and the building left on the
## old lot must still meet its setbacks.
##
## Who does it, and why:
## - a family buys the empty lot next door for a bigger yard and combines them;
## - a business that has outgrown its lot buys the neighbor's lot to build on;
## - an owner of a wide lot splits off a building lot to sell: investors for the
##   profit, families when money is tight or the kids have grown up and left.

## Smallest lot the zoning allows: [frontage meters, area square meters].
const MINIMUM: Dictionary = {
	"residential": [15.0, 450.0], "mixed": [7.5, 280.0], "commercial": [7.5, 280.0], "civic": [15.0, 450.0],
	"park": [10.0, 300.0], "agricultural": [60.0, 8000.0], "industrial": [20.0, 1200.0],
}


static func minimum(zone: String) -> Array:
	return MINIMUM.get(zone, [15.0, 450.0])


## Two lots side by side on the same street front, sharing a whole side line.
static func adjacent(a: Dictionary, b: Dictionary) -> bool:
	if str(a["front"]) != str(b["front"]) or bool(a.get("removed", false)) or bool(b.get("removed", false)):
		return false
	if ["n", "s"].has(str(a["front"])):
		return absf(float(a["z0"]) - float(b["z0"])) < 0.1 and absf(float(a["z1"]) - float(b["z1"])) < 0.1 and (absf(float(a["x1"]) - float(b["x0"])) < 0.1 or absf(float(b["x1"]) - float(a["x0"])) < 0.1)
	return absf(float(a["x0"]) - float(b["x0"])) < 0.1 and absf(float(a["x1"]) - float(b["x1"])) < 0.1 and (absf(float(a["z1"]) - float(b["z0"])) < 0.1 or absf(float(b["z1"]) - float(a["z0"])) < 0.1)


static func side_neighbors(w: LTWorld, l: Dictionary) -> Array:
	var out: Array = []
	for o in w.lots:
		if int(o["id"]) != int(l["id"]) and adjacent(l, o):
			out.append(o)
	return out


static func same_owner(a: Dictionary, b: Dictionary) -> bool:
	return str(a["owner_kind"]) == str(b["owner_kind"]) and int(a["owner_id"]) == int(b["owner_id"])


# ---------------------------------------------------------------- combining

## Combines empty lot b into lot a. Both must belong to the same owner and zone.
static func merge(w: LTWorld, a_id: int, b_id: int, why: String) -> Dictionary:
	var a: Dictionary = w.lot(a_id)
	var b: Dictionary = w.lot(b_id)
	if a.is_empty() or b.is_empty() or not adjacent(a, b):
		return {"ok": false, "message": "Those lots do not share a side line."}
	if not same_owner(a, b) or str(a["owner_kind"]) == "city":
		return {"ok": false, "message": "Only one private owner holding both lots can combine them."}
	if str(a["zone"]) != str(b["zone"]):
		return {"ok": false, "message": "Lots in different zones cannot be combined."}
	if str(b["use"]) != "empty":
		return {"ok": false, "message": "The lot being added must be empty."}
	for k in ["x0", "z0"]:
		a[k] = minf(float(a[k]), float(b[k]))
	for k in ["x1", "z1"]:
		a[k] = maxf(float(a[k]), float(b[k]))
	a["value"] = int(a["value"]) + int(b["value"])
	a["lakefront"] = bool(a.get("lakefront", false)) or bool(b.get("lakefront", false))
	a["view"] = bool(a.get("view", false)) or bool(b.get("view", false))
	a.erase("for_sale")
	b["removed"] = true
	b["use"] = "removed"
	b["merged_into"] = a_id
	b.erase("for_sale")
	if not a.has("record"):
		a["record"] = []
	a["record"].append({"day": w.day, "text": "Combined with lot %d by the owner. %s" % [b_id, why]})
	w.dist_cache.clear()
	_count(w, "lot_merges")
	return {"ok": true, "message": "Lots %d and %d are now one lot." % [a_id, b_id]}


## Buys an empty lot next door from whoever sells it, at the asking price.
static func buy_next_door(w: LTWorld, buyer_kind: String, buyer_id: int, pay_acct: String, l: Dictionary, n: Dictionary) -> int:
	var price: int = int(n["for_sale"]) if n.has("for_sale") else LTGeography.asking_price(w, int(n["id"]))
	if w.ledger.bal(pay_acct) < price:
		return -1
	var seller: String = LTCivic.owner_acct(w, n)
	LTCivic.property_sale(w, pay_acct, seller, price, int(n["id"]))
	n["owner_kind"] = buyer_kind
	n["owner_id"] = buyer_id
	n.erase("for_sale")
	n.erase("bought_for")
	return price


## Empty lots next door that can be bought: city lots not held back, or listed.
static func buyable_next_door(w: LTWorld, l: Dictionary) -> Array:
	var out: Array = []
	for n in side_neighbors(w, l):
		if str(n["use"]) != "empty" or str(n["zone"]) != str(l["zone"]):
			continue
		if (str(n["owner_kind"]) == "city" and not bool(n.get("hold", false))) or n.has("for_sale"):
			out.append(n)
	return out


# ---------------------------------------------------------------- splitting

## Where a split would go: [ok, why, cut, keep side] with the cut measured in
## meters from the lot's low edge (x for lots facing north or south, z otherwise).
static func split_plan(w: LTWorld, l: Dictionary, new_width: float) -> Dictionary:
	var fw: float = LTGeography.lot_frontage(l)
	var dp: float = LTGeography.lot_depth(l)
	var mn: Array = minimum(str(l["zone"]))
	if new_width < float(mn[0]) or new_width * dp < float(mn[1]):
		return {"ok": false, "why": "the new lot would be smaller than the %d foot wide, %s square foot minimum" % [int(float(mn[0]) * 3.28), LTGeography._thousands(int(float(mn[1]) * 10.764))]}
	var keep_w: float = fw - new_width
	if keep_w < float(mn[0]) or keep_w * dp < float(mn[1]):
		return {"ok": false, "why": "what is left would be smaller than the zoning minimum"}
	# which side the building is on; the new lot is cut from the other side
	var cut_low: bool = true
	if str(l["use"]) == "house" and l.has("home"):
		var lay: Dictionary = LTHomes.layout(l, l["home"])
		var hx: float = (float(lay["house"][0]) + float(lay["house"][2])) * 0.5
		cut_low = hx > 0.0
		# the house must still fit what is left, with its setbacks
		var trial: Dictionary = l.duplicate(true)
		_apply_cut(trial, new_width, cut_low)
		var lay2: Dictionary = LTHomes.layout(trial, _shifted_home(l, trial))
		if not bool(lay2["fits"]):
			return {"ok": false, "why": "the house would sit too close to the new lot line"}
	elif str(l["use"]) != "empty":
		return {"ok": false, "why": "only empty lots and house lots can be split"}
	return {"ok": true, "why": "", "width": new_width, "low": cut_low}


## The house keeps its place on the ground when the lot shrinks around it: its
## offset along the front is recentered for the smaller lot.
static func _shifted_home(old: Dictionary, nl: Dictionary) -> Dictionary:
	var spec: Dictionary = LTHomes.upgrade(old["home"]).duplicate(true)
	var lay: Dictionary = LTHomes.layout(old, spec)
	var hx_world: float = _front_coord(old) + (float(lay["house"][0]) + float(lay["house"][2])) * 0.5
	var fw2: float = LTGeography.lot_frontage(nl)
	var hx_local: float = hx_world - _front_coord(nl)
	var W: float = float(lay["W"]) + (0.0 if bool(lay.get("garage_rear", false)) or not lay.has("garage") else float(lay["gw"]))
	var slack: float = maxf(0.01, fw2 - 2.0 * LTHomes.SIDE_SETBACK - W)
	var x_left: float = hx_local - float(lay["W"]) * 0.5 + fw2 * 0.5 - LTHomes.SIDE_SETBACK
	var pl: Dictionary = spec.get("place", {"setback": LTHomes.FRONT_SETBACK, "shift": 0.5, "garage_side": "right"}).duplicate()
	pl["shift"] = clampf(x_left / slack, 0.0, 1.0)
	spec["place"] = pl
	return spec


## The lot's center along its front, in map coordinates.
static func _front_coord(l: Dictionary) -> float:
	if ["n", "s"].has(str(l["front"])):
		return (float(l["x0"]) + float(l["x1"])) * 0.5
	return (float(l["z0"]) + float(l["z1"])) * 0.5


static func _apply_cut(l: Dictionary, new_width: float, cut_low: bool) -> void:
	var ax: String = "x" if ["n", "s"].has(str(l["front"])) else "z"
	if cut_low:
		l[ax + "0"] = float(l[ax + "0"]) + new_width
	else:
		l[ax + "1"] = float(l[ax + "1"]) - new_width


## Carries out an approved split: a new lot with the same owner, zone and street.
static func split(w: LTWorld, lot_id: int, new_width: float) -> Dictionary:
	var l: Dictionary = w.lot(lot_id)
	var sp: Dictionary = split_plan(w, l, new_width)
	if not bool(sp["ok"]):
		return {"ok": false, "message": "Cannot split lot %d: %s." % [lot_id, sp["why"]]}
	var ax: String = "x" if ["n", "s"].has(str(l["front"])) else "z"
	var old: Dictionary = l.duplicate(true)
	var r: Array = [float(l["x0"]), float(l["z0"]), float(l["x1"]), float(l["z1"])]
	if bool(sp["low"]):
		if ax == "x":
			r[2] = float(l["x0"]) + new_width
		else:
			r[3] = float(l["z0"]) + new_width
	else:
		if ax == "x":
			r[0] = float(l["x1"]) - new_width
		else:
			r[1] = float(l["z1"]) - new_width
	_apply_cut(l, new_width, bool(sp["low"]))
	if l.has("home"):
		l["home"] = _shifted_home(old, l)
	var nid: int = LTGeography._add_lot(w, r[0], r[1], r[2], r[3], str(l["zone"]), str(l["front"]), str(l.get("district", "Town")))
	if nid < 0:
		# no road found for the new lot: put the old lines back
		for k in ["x0", "z0", "x1", "z1"]:
			l[k] = old[k]
		if old.has("home"):
			l["home"] = old["home"]
		return {"ok": false, "message": "The new lot would not reach a road."}
	var n: Dictionary = w.lot(nid)
	n["owner_kind"] = l["owner_kind"]
	n["owner_id"] = l["owner_id"]
	# land value moves with the land; the building stays with the old lot
	var land_old: int = LTGeography.land_value(str(l["zone"]), LTGeography.lot_area(old))
	var share: float = new_width / LTGeography.lot_frontage(old)
	n["value"] = int(float(land_old) * share)
	l["value"] = maxi(0, int(l["value"]) - int(n["value"]))
	n["record"] = [{"day": w.day, "text": "Split off lot %d by its owner, plat approved by the city." % lot_id}]
	if not l.has("record"):
		l["record"] = []
	l["record"].append({"day": w.day, "text": "Lot %d was split off this lot." % nid})
	w.dist_cache.clear()
	_count(w, "lot_splits")
	return {"ok": true, "message": "Lot %d was split; the new lot is %d." % [lot_id, nid], "new_lot": nid}


# ---------------------------------------------------------------- what owners decide

static func monthly(w: LTWorld) -> void:
	_bigger_yards(w)
	_splits(w)
	_lapse(w)


static func _count(w: LTWorld, key: String) -> void:
	w.counters[key] = int(w.counters.get(key, 0)) + 1


## A family with money to spare buys the empty lot beside the house.
static func _bigger_yards(w: LTWorld) -> void:
	var m: int = LTCalendar.month_index(w.day)
	for h in w.households:
		if str(h.get("tenure", "")) != "own" or int(h["lot"]) < 0 or (int(h["id"]) * 5 + 1) % 12 != m:
			continue
		var l: Dictionary = w.lot(int(h["lot"]))
		if str(l["use"]) != "house" or str(l["owner_kind"]) != "sim":
			continue
		var head: Dictionary = w.cit(int(l["owner_id"]))
		if head.is_empty() or int(head["household"]) != int(h["id"]):
			continue
		var t: Dictionary = head["traits"]
		var kids: int = w.household_members(h).size() - w.household_adults(h).size()
		var wish: float = (50.0 - float(t["sociability"])) * 0.6 + float(kids) * 6.0 + (float(t["greed"]) - 50.0) * 0.3 + w.rng.randf_range(-20.0, 20.0)
		if wish < 20.0:
			continue
		for n in buyable_next_door(w, l):
			var price: int = int(n["for_sale"]) if n.has("for_sale") else LTGeography.asking_price(w, int(n["id"]))
			var cushion: int = LTPeople.monthly_bills(w, h) * 3
			var how: String = "cash"
			if w.cash(head) < price + cushion:
				# borrow against the house: what it is worth over what is owed
				var owed: int = 0
				if int(h["mortgage"]) >= 0 and LTFinance.is_active(w.debt(int(h["mortgage"]))):
					owed = int(w.debt(int(h["mortgage"]))["balance"])
				var equity: int = int(float(l["value"]) * 0.85) - owed
				if equity < price or float(t["discipline"]) > 70.0:
					continue
				var dec: Dictionary = LTFinance.bank_decision(w, head, "personal_loan", price, maxi(1, LTFinance.monthly_income(w, head)))
				if not bool(dec["ok"]):
					continue
				var d: Dictionary = LTFinance.new_debt(w, "p", int(head["id"]), "bank", -1, "home_equity", price, float(dec["rate"]) - 0.03, 120, "house", int(l["id"]), [])
				LTLoans.attach(w, d, "Home equity loan, 10-year fixed", "equity")
				LTFinance.fund_loan(w, d, w.acct_p(head), price)
				how = "a home equity loan"
			var paid: int = buy_next_door(w, "sim", int(head["id"]), w.acct_p(head), l, n)
			if paid < 0:
				continue
			var why: String = "privacy, room for the kids to play and a bigger garden" if kids > 0 else ("privacy and nobody building right next door" if float(t["sociability"]) < 45.0 else "a bigger yard and land that will be worth more")
			merge(w, int(l["id"]), int(n["id"]), "Reason: %s." % why)
			w.log_sim(head, "Bought the empty lot next door for %s with %s and combined it with the house lot. Reason: %s." % [LTMoney.fmt(paid), how, why], true)
			w.chronicle_add("The %s family bought the lot next door on %s and made it part of their yard." % [head["last_name"], LTGeography.lot_street(w, int(l["id"]))["name"]], "housing", false, [head["id"]])
			break


## Owners of wide lots ask the city to split off a lot to sell.
static func _splits(w: LTWorld) -> void:
	var m: int = LTCalendar.month_index(w.day)
	for l in w.lots:
		if bool(l.get("removed", false)) or str(l["owner_kind"]) != "sim" or (int(l["id"]) * 7 + 2) % 12 != m:
			continue
		if not ["empty", "house"].has(str(l["use"])) or _pending_for(w, int(l["id"])):
			continue
		var owner: Dictionary = w.cit(int(l["owner_id"]))
		if not w.is_present(owner):
			continue
		var mn: Array = minimum(str(l["zone"]))
		var fw: float = LTGeography.lot_frontage(l)
		if fw < float(mn[0]) * 2.0:
			continue
		var t: Dictionary = owner["traits"]
		var why: String = ""
		if str(l["use"]) == "empty" and float(t["greed"]) > 50.0:
			why = "two lots sell for more than one big one"
		elif str(l["use"]) == "house":
			var h: Dictionary = w.hh(int(owner["household"]))
			var tight: bool = float(owner["needs"]["money_security"]) < 35.0
			var empty_nest: bool = w.age_years(owner) >= 55 and w.household_members(h).size() <= 2
			if tight and w.rng.randf() < 0.5:
				why = "money is tight, and the side yard is worth more as a lot to sell"
			elif empty_nest and w.rng.randf() < 0.25:
				why = "the kids are grown and gone, and the big yard is more work than it is worth"
		if why == "":
			continue
		var width: float = maxf(float(mn[0]), floorf(fw * 0.5 * 2.0) / 2.0)
		if str(l["use"]) == "house":
			width = float(mn[0]) + 0.5
		var sp: Dictionary = split_plan(w, l, width)
		if not bool(sp["ok"]):
			continue
		_file_plat(w, l, owner, width, why)


static func _pending_for(w: LTWorld, lot_id: int) -> bool:
	for p in w.city.get("plats", []):
		if int(p["lot"]) == lot_id and str(p["status"]) == "pending":
			return true
	return false


static func _file_plat(w: LTWorld, l: Dictionary, owner: Dictionary, width: float, why: String) -> void:
	if not w.city.has("plats"):
		w.city["plats"] = []
	var for_n: int = 0
	var against_n: int = 0
	var voices: Array = []
	for nl in side_neighbors(w, l):
		if str(nl["use"]) != "house" or nl["units"].is_empty() or int(nl["units"][0]) < 0:
			continue
		var na: Array = w.household_adults(w.hh(int(nl["units"][0])))
		if na.is_empty():
			continue
		var n: Dictionary = na[0]
		if float(n["traits"]["kindness"]) - (50.0 - float(n["traits"]["sociability"])) * 0.5 + w.rng.randf_range(-20.0, 20.0) > 35.0:
			for_n += 1
			voices.append("%s does not mind" % w.full_name(n))
		else:
			against_n += 1
			voices.append("%s is against it: %s" % [w.full_name(n), ["a house would go up right beside theirs", "it will crowd the block", "they liked the open space"][w.rng.randi_range(0, 2)]])
	var fw: float = LTGeography.lot_frontage(l)
	var dp: float = LTGeography.lot_depth(l)
	var p: Dictionary = {"id": w.city["plats"].size(), "lot": int(l["id"]), "cid": int(owner["id"]), "width": width, "why": why,
		"day": w.day, "status": "pending", "for": for_n, "against": against_n, "voices": voices,
		"text": "Split lot %d (%d by %d feet) into a %d foot wide lot to sell and a %d foot wide lot that keeps %s." % [int(l["id"]), int(fw * 3.28), int(dp * 3.28), int(width * 3.28), int((fw - width) * 3.28), "the house" if str(l["use"]) == "house" else "the rest"]}
	w.city["plats"].append(p)
	w.log_sim(owner, "Asked the city to approve splitting %s into two lots. Reason: %s." % [LTGeography.lot_label(w, int(l["id"])), why], true)
	w.chronicle_add("Plat request: %s wants to split %s to sell a new building lot. Neighbors: %d for, %d against. The mayor decides." % [w.full_name(owner), LTGeography.lot_label(w, int(l["id"])), for_n, against_n], "city", true, [owner["id"]])


static func pending_plats(w: LTWorld) -> Array:
	var out: Array = []
	for p in w.city.get("plats", []):
		if str(p["status"]) == "pending":
			out.append(p)
	return out


## The mayor's answer to a plat.
static func decide(w: LTWorld, pid: int, approve: bool) -> Dictionary:
	var ps: Array = w.city.get("plats", [])
	if pid < 0 or pid >= ps.size():
		return {"ok": false, "message": "No such plat request."}
	var p: Dictionary = ps[pid]
	if str(p["status"]) != "pending":
		return {"ok": false, "message": "That request has already been decided."}
	var owner: Dictionary = w.cit(int(p["cid"]))
	var l: Dictionary = w.lot(int(p["lot"]))
	p["decided_day"] = w.day
	if not approve:
		p["status"] = "denied"
		if not owner.is_empty():
			owner["trust_city"] = clampf(float(owner.get("trust_city", 50.0)) - 6.0, 0.0, 100.0)
			w.log_sim(owner, "The city denied the request to split %s." % LTGeography.lot_label(w, int(p["lot"])), true)
		return {"ok": true, "message": "Plat denied. Lot %d stays one lot." % int(p["lot"])}
	if str(l["owner_kind"]) != "sim" or int(l["owner_id"]) != int(p["cid"]):
		p["status"] = "void"
		return {"ok": true, "message": "The owner sold the lot before the decision; the request is void."}
	var r: Dictionary = split(w, int(p["lot"]), float(p["width"]))
	if not bool(r["ok"]):
		p["status"] = "void"
		return r
	p["status"] = "approved"
	p["new_lot"] = int(r["new_lot"])
	var n: Dictionary = w.lot(int(r["new_lot"]))
	# the owner lists the new lot at about what land like it sells for
	n["for_sale"] = int(float(n["value"]) * w.rng.randf_range(1.05, 1.25))
	n["bought_for"] = int(n["value"])
	n["listed_day"] = w.day
	if not owner.is_empty():
		owner["trust_city"] = clampf(float(owner.get("trust_city", 50.0)) + 4.0, 0.0, 100.0)
		w.log_sim(owner, "The city approved the split. Listed the new %s for sale at %s." % [LTGeography.lot_label(w, int(r["new_lot"])), LTMoney.fmt(int(n["for_sale"]))], true)
	w.chronicle_add("A new building lot on %s is for sale: %s." % [LTGeography.lot_street(w, int(r["new_lot"]))["name"], LTMoney.fmt(int(n["for_sale"]))], "housing", false, [])
	return {"ok": true, "message": "Plat approved. %s" % r["message"]}


static func _lapse(w: LTWorld) -> void:
	for p in w.city.get("plats", []):
		if str(p["status"]) == "pending" and w.day - int(p["day"]) > 60:
			p["status"] = "lapsed"
			var o: Dictionary = w.cit(int(p["cid"]))
			if not o.is_empty():
				o["trust_city"] = clampf(float(o.get("trust_city", 50.0)) - 8.0, 0.0, 100.0)
				w.log_sim(o, "The city never answered the request to split the lot.", true)


## A business that has outgrown its lot buys the empty lot next door and
## combines them. Returns true if it now has more land.
static func assemble_for(w: LTWorld, b: Dictionary) -> bool:
	var l: Dictionary = w.lot(int(b["lot"]))
	var acct: String = w.acct_b(b)
	for n in buyable_next_door(w, l):
		# the business must own its lot to combine; a leased lot cannot be added to
		if str(l["owner_kind"]) != "business" or int(l["owner_id"]) != int(b["id"]):
			if str(l["owner_kind"]) == "city" and not bool(l.get("hold", false)):
				if buy_next_door(w, "business", int(b["id"]), acct, l, l) < 0:
					return false
			else:
				return false
		var paid: int = buy_next_door(w, "business", int(b["id"]), acct, l, n)
		if paid < 0:
			return false
		merge(w, int(l["id"]), int(n["id"]), "Reason: %s needed room to grow." % b["name"])
		w.log_biz(b, "Bought the empty lot next door for %s and combined it with ours, to build on." % LTMoney.fmt(paid))
		return true
	return false
