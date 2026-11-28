class_name LTApartments
extends RefCounted
## Apartment buildings designed by whoever builds them, for the people who need homes.
##
## A builder looks at who is waiting for a place to live (single workers, young
## couples, families with kids, seniors), picks a mix of studios and one, two and
## three bedroom units to fit them, sets a rent for each, and adds what renters ask
## for: a laundry room, parking, storage, a playground, balconies, an elevator.
## Personality decides the rest: the kind build for families and keep rents fair,
## the greedy pack in small units, the orderly build in brick. Every choice is
## written down with the reason, and the zoning law caps how many homes a lot holds.
##
## The building record is lot["apt"]; lot["units"][i] is the household in unit i.

## Unit types: square feet, bedrooms, baths, and the going rent in a small South
## Dakota town in 2026 (dollars a month, before the building's own premium).
const TYPES: Dictionary = {
	"studio": {"label": "Studio", "sqft": 450, "beds": 0, "baths": 1.0, "rent": 650, "short": "Studio"},
	"1br": {"label": "One-bedroom", "sqft": 650, "beds": 1, "baths": 1.0, "rent": 780, "short": "1 BR"},
	"2br": {"label": "Two-bedroom", "sqft": 900, "beds": 2, "baths": 1.5, "rent": 950, "short": "2 BR"},
	"3br": {"label": "Three-bedroom", "sqft": 1150, "beds": 3, "baths": 2.0, "rent": 1150, "short": "3 BR"},
}
const PER_SQFT: float = 150.0          # building cost, walk up apartments
const COMMON_SHARE: float = 0.18       # halls, stairs, walls
const AMENITY_PRICE: Dictionary = {
	"laundry": 25000, "storage": 9000, "playground": 18000, "balconies": 4000, "elevator": 120000,
	"community_room": 30000, "bike_room": 5000, "parking": 3000,
}
const AMENITY_LABEL: Dictionary = {
	"laundry": "laundry room", "storage": "storage lockers", "playground": "playground", "balconies": "balconies",
	"elevator": "elevator", "community_room": "community room", "bike_room": "bike room", "parking": "parking lot",
}
const STYLES: Dictionary = {
	"walkup": "Walk up", "garden": "Garden apartments", "townhouse": "Townhouse row", "senior": "Senior apartments",
}


# ---------------------------------------------------------------- who needs a home

## Who is looking for a rental, and what kind: {"total", "mix" {type: count}, "why"}.
static func demand(w: LTWorld) -> Dictionary:
	var mix: Dictionary = {"studio": 0.0, "1br": 0.0, "2br": 0.0, "3br": 0.0}
	var why: Array = []
	var homeless: int = 0
	for h in w.households:
		var ms: Array = w.household_members(h)
		if ms.is_empty():
			continue
		var adults: int = w.household_adults(h).size()
		var kids: int = ms.size() - adults
		var t: String = unit_for(adults, kids)
		if int(h["lot"]) < 0:
			homeless += 1
			mix[t] += 2.0
		elif str(h.get("tenure", "")) == "rent":
			mix[t] += 0.3
	# grown children still at home who would move out with a place to go
	var at_home: int = 0
	for c in w.citizens:
		if w.is_present(c) and w.age_years(c) >= 19 and w.age_years(c) <= 30 and str(c["job"]["kind"]) != "none":
			var h2: Dictionary = w.hh(int(c["household"]))
			for a in w.household_adults(h2):
				if a["children"].has(int(c["id"])):
					at_home += 1
					break
	mix["studio"] += float(at_home) * 0.5
	mix["1br"] += float(at_home) * 0.5
	if homeless > 0:
		why.append("%d household%s with nowhere to live" % [homeless, "" if homeless == 1 else "s"])
	if at_home > 0:
		why.append("%d grown children working and still living with their parents" % at_home)
	var vac: int = LTPeople.vacancy_count(w)
	if vac == 0:
		why.append("not one apartment free in town")
	var total: float = 0.0
	for k in mix:
		total += float(mix[k])
	return {"total": total, "mix": mix, "why": why, "vacant": vac}


## The unit a household fits: kids share a room two to a room.
static func unit_for(adults: int, kids: int) -> String:
	var beds: int = (1 if adults >= 1 else 0) + maxi(0, adults - 2) + int(ceil(float(kids) / 2.0))
	if adults == 1 and kids == 0:
		return "1br"
	return ["1br", "1br", "2br", "3br"][clampi(beds, 0, 3)]


# ---------------------------------------------------------------- design

## A builder's design. ctx: traits (dict), name, budget (cents, 0 for none),
## units (a fixed count for buildings already standing, else 0), senior (bool).
static func design(w: LTWorld, l: Dictionary, ctx: Dictionary) -> Dictionary:
	var t: Dictionary = ctx.get("traits", {})
	var tr: Callable = func(k: String) -> float: return float(t.get(k, 50.0))
	var dm: Dictionary = demand(w)
	var why: Array = []
	var spec: Dictionary = {"color": w.rng.randi_range(0, 4), "units": [], "amenities": [], "why": why, "builder": str(ctx.get("name", "a builder"))}
	# how many homes: the zoning law, the lot, the market, the money
	var cap: int = int(w.city["laws"].get("zoning_density", 4))
	var fixed: int = int(ctx.get("units", 0))
	var n: int = fixed if fixed > 0 else clampi(int(round(float(dm["total"]) * 0.8)) + 2, 4, cap)
	n = mini(n, cap) if fixed == 0 else n
	if fixed == 0 and tr.call("ambition") > 65.0:
		n = cap
		why.append("as many homes as the zoning allows, %d" % cap)
	# the mix: what people are waiting for, bent by the builder's own leaning
	var weights: Dictionary = dm["mix"].duplicate()
	for k in weights:
		weights[k] = float(weights[k]) + 0.6
	if tr.call("kindness") > 60.0:
		weights["2br"] = float(weights["2br"]) + 1.5
		weights["3br"] = float(weights["3br"]) + 1.0
		why.append("family sized units, because families in town need room")
	if tr.call("greed") > 62.0:
		weights["studio"] = float(weights["studio"]) + 2.0
		weights["1br"] = float(weights["1br"]) + 1.0
		why.append("small units, which rent for more per square foot")
	if bool(ctx.get("senior", false)):
		weights = {"studio": 0.5, "1br": 3.0, "2br": 1.0, "3br": 0.0}
		why.append("one floor living for older residents")
	var wt: float = 0.0
	for k in weights:
		wt += float(weights[k])
	var counts: Dictionary = {}
	var assigned: int = 0
	for k in ["studio", "1br", "2br", "3br"]:
		counts[k] = int(floor(float(n) * float(weights[k]) / maxf(0.01, wt)))
		assigned += int(counts[k])
	var order: Array = ["2br", "1br", "3br", "studio"]
	var oi: int = 0
	while assigned < n:
		counts[order[oi % 4]] = int(counts[order[oi % 4]]) + 1
		assigned += 1
		oi += 1
	# the building
	var stories: int = clampi(int(ceil(float(n) / 4.0)), 1, 4)
	var style: String = "walkup"
	if bool(ctx.get("senior", false)):
		style = "senior"
		stories = mini(stories, 2)
	elif n <= 6 and LTGeography.lot_frontage(l) >= 30.0:
		style = "townhouse"
		stories = 2
		why.append("townhouses side by side, each with its own door")
	elif LTGeography.lot_area(l) > 1600.0 and stories > 2:
		style = "garden"
		stories = 2
	spec["style"] = style
	spec["stories"] = stories
	var quality: float = 1.0 + (0.08 if tr.call("discipline") > 60.0 else 0.0) + (0.05 if fixed == 0 else -0.1)
	for k in ["studio", "1br", "2br", "3br"]:
		for i in int(counts[k]):
			var ty: Dictionary = TYPES[k]
			var rent: float = float(ty["rent"]) * quality * (1.0 + (tr.call("greed") - tr.call("kindness")) / 400.0)
			spec["units"].append({"type": k, "sqft": int(ty["sqft"]), "beds": int(ty["beds"]), "baths": float(ty["baths"]), "rent": LTMoney.dollars(round(rent / 5.0) * 5.0)})
	# amenities renters ask for
	var am: Array = spec["amenities"]
	am.append("parking")
	spec["parking"] = n + int(ceil(float(n) * 0.5))
	if n >= 4:
		am.append("laundry")
	if int(counts["2br"]) + int(counts["3br"]) >= 2 and tr.call("kindness") > 45.0:
		am.append("playground")
		why.append("a playground for the kids who will live there")
	if tr.call("discipline") > 55.0:
		am.append("storage")
	if tr.call("sociability") > 60.0 and n >= 6:
		am.append("community_room")
	if tr.call("ambition") > 55.0 and style != "townhouse" and stories > 1:
		am.append("balconies")
	if stories >= 3 or style == "senior":
		am.append("elevator")
		why.append("an elevator, so nobody is stuck on the stairs")
	spec["siding"] = "brick" if tr.call("discipline") > 62.0 else ("wood" if tr.call("kindness") > 60.0 else "vinyl")
	# fair housing: ground floor units in buildings of four or more are built accessible
	spec["accessible"] = n >= 4
	if bool(spec["accessible"]):
		why.append("accessible ground floor units, as fair housing rules require")
	# trim to the money
	var budget: int = int(ctx.get("budget", 0))
	if budget > 0:
		for k in ["community_room", "balconies", "storage", "playground"]:
			if cost(spec) <= budget:
				break
			if am.has(k):
				am.erase(k)
				why.append("went without the %s to stay within the loan" % AMENITY_LABEL[k])
		while cost(spec) > budget and spec["units"].size() > 4:
			spec["units"].pop_back()
	return spec


static func sqft(spec: Dictionary) -> int:
	var t: float = 0.0
	for u in spec.get("units", []):
		t += float(u["sqft"])
	return int(t * (1.0 + COMMON_SHARE))


static func price_list(spec: Dictionary) -> Array:
	var lines: Array = [["%s, %d homes, %s sq ft" % [STYLES.get(str(spec.get("style", "walkup")), "Apartments"), spec["units"].size(), LTGeography._thousands(sqft(spec))], int(float(sqft(spec)) * PER_SQFT * (1.1 if str(spec.get("siding", "")) == "brick" else 1.0))]]
	for a in spec.get("amenities", []):
		var n: int = int(spec.get("parking", 0)) if str(a) == "parking" else (spec["units"].size() if str(a) == "balconies" else 1)
		lines.append([("%s, %d spaces" % [AMENITY_LABEL[a].capitalize(), n]) if str(a) == "parking" else str(AMENITY_LABEL[a]).capitalize(), int(AMENITY_PRICE[a]) * n])
	if bool(spec.get("accessible", false)):
		lines.append(["Accessible ground floor units", 6000 * mini(spec["units"].size(), int(ceil(float(spec["units"].size()) / float(maxi(1, int(spec["stories"])))))) ])
	return lines


static func cost(spec: Dictionary) -> int:
	var t: int = 0
	for ln in price_list(spec):
		t += int(ln[1])
	return LTMoney.dollars(float(t))


static func text(spec: Dictionary) -> String:
	if spec.is_empty():
		return ""
	var c: Dictionary = {}
	for u in spec["units"]:
		c[u["type"]] = int(c.get(u["type"], 0)) + 1
	var parts: Array = []
	for k in ["studio", "1br", "2br", "3br"]:
		if c.has(k):
			parts.append("%d %s%s" % [int(c[k]), str(TYPES[k]["label"]).to_lower(), "s" if int(c[k]) > 1 else ""])
	var am: Array = []
	for a in spec.get("amenities", []):
		if str(a) != "parking":
			am.append(str(AMENITY_LABEL[a]))
	return "%s, %d stor%s: %s%s" % [STYLES.get(str(spec.get("style", "walkup")), "Apartments"), int(spec["stories"]), "y" if int(spec["stories"]) == 1 else "ies", ", ".join(parts), (". With " + LTHomes._join(am)) if not am.is_empty() else ""]


static func rent_range(spec: Dictionary) -> String:
	var lo: int = 1 << 30
	var hi: int = 0
	for u in spec.get("units", []):
		lo = mini(lo, int(u["rent"]))
		hi = maxi(hi, int(u["rent"]))
	if hi == 0:
		return ""
	return LTMoney.fmt(lo) if lo == hi else "%s to %s" % [LTMoney.fmt(lo), LTMoney.fmt(hi)]


## The rent for one unit of a lot (apartments, or the old flat rent).
static func rent_for(w: LTWorld, l: Dictionary, unit: int) -> int:
	var spec: Dictionary = l.get("apt", {})
	if not spec.is_empty() and unit >= 0 and unit < spec["units"].size():
		return int(spec["units"][unit]["rent"])
	return int(l.get("unit_rent", 0))


static func unit_label(spec: Dictionary, i: int) -> String:
	if spec.is_empty() or i >= spec["units"].size():
		return "Unit %d" % (i + 1)
	var u: Dictionary = spec["units"][i]
	return "Apt %d, %s" % [i + 1, str(TYPES[str(u["type"])]["label"]).to_lower()]


## Puts the design on the lot: one home per unit.
static func apply(w: LTWorld, l: Dictionary, spec: Dictionary) -> void:
	l["apt"] = spec
	var units: Array = []
	for i in spec["units"].size():
		units.append(-1)
	l["units"] = units
	var tot: int = 0
	for u in spec["units"]:
		tot += int(u["rent"])
	l["unit_rent"] = tot / maxi(1, spec["units"].size())


# ---------------------------------------------------------------- finding a unit

## The empty unit that suits this household best: enough bedrooms, a rent they
## can carry, the smallest that fits. Any empty home if nothing fits.
static func best_unit(w: LTWorld, h: Dictionary) -> Dictionary:
	var ms: Array = w.household_members(h)
	var adults: int = w.household_adults(h).size()
	var need_beds: int = int(TYPES[unit_for(maxi(1, adults), ms.size() - adults)]["beds"])
	var income: int = 0
	for a in w.household_adults(h):
		income += LTFinance.monthly_income(w, a)
	var best: Dictionary = {}
	var best_s: float = -1e9
	var fallback: Dictionary = {}
	for l in w.lots:
		var use: String = str(l["use"])
		if not ["apartment", "house", "business"].has(use):
			continue
		if use == "house" and str(l["owner_kind"]) == "sim":
			continue
		var units: Array = l["units"]
		for i in units.size():
			if int(units[i]) != -1:
				continue
			var spot: Dictionary = {"lot": int(l["id"]), "unit": i}
			if fallback.is_empty():
				fallback = spot
			var beds: int = 2
			if l.has("apt") and i < l["apt"]["units"].size():
				beds = int(l["apt"]["units"][i]["beds"])
			elif use == "house":
				beds = 3
			var rent: int = rent_for(w, l, i)
			var s: float = -absf(float(beds - need_beds)) * 10.0 - (30.0 if beds < need_beds else 0.0)
			if income > 0 and float(rent) > float(income) * 0.35:
				s -= 25.0
			s -= float(rent) / 10000.0
			if s > best_s:
				best_s = s
				best = spot
	return best if not best.is_empty() else fallback


# ---------------------------------------------------------------- on the lot

## The building, parking and yard on the lot, like a house plan.
static func layout(l: Dictionary, spec: Dictionary) -> Dictionary:
	var fw: float = LTGeography.lot_frontage(l)
	var dp: float = LTGeography.lot_depth(l)
	var stories: int = maxi(1, int(spec.get("stories", 2)))
	var foot: float = float(sqft(spec)) / LTHomes.M2 / float(stories)
	var W: float = clampf(sqrt(foot * 2.2), 8.0, maxf(8.0, fw - 3.0))
	var D: float = foot / W
	var front: float = 6.0
	var x0: float = -W * 0.5
	var out: Dictionary = {"W": W, "D": D, "building": [x0, front, x0 + W, front + D]}
	var back: float = front + D
	var park_n: int = int(spec.get("parking", 0))
	if park_n > 0:
		var rows: int = maxi(1, int(ceil(float(park_n) / maxf(1.0, floor((fw - 2.0) / 2.7)))))
		out["parking"] = [-fw * 0.5 + 1.0, back + 2.0, fw * 0.5 - 1.0, minf(dp - 0.5, back + 2.0 + 5.5 * float(rows))]
	if spec.get("amenities", []).has("playground"):
		# a 7 by 7 meter play yard beside the building if there is room, else out back
		if fw * 0.5 - W * 0.5 >= 9.0:
			out["playground"] = [fw * 0.5 - 8.5, front, fw * 0.5 - 1.5, front + 7.0]
		else:
			var py: float = float(out["parking"][3]) + 1.0 if out.has("parking") else back + 1.0
			out["playground"] = [-3.5, minf(py, dp - 8.0), 3.5, minf(py, dp - 8.0) + 7.0]
	return out


## Units laid out by floor for the drawing: each floor a row of units.
static func floor_plan(l: Dictionary, spec: Dictionary) -> Array:
	var lay: Dictionary = layout(l, spec)
	var W: float = float(lay["W"])
	var D: float = float(lay["D"])
	var stories: int = maxi(1, int(spec.get("stories", 1)))
	var units: Array = spec.get("units", [])
	var per: int = int(ceil(float(units.size()) / float(stories)))
	var out: Array = []
	var u0: int = 0
	for f in stories:
		var fl: Array = units.slice(u0, mini(units.size(), u0 + per))
		var total: float = 0.0
		for u in fl:
			total += float(u["sqft"])
		var hall: float = D * 0.16
		var rects: Array = [[0.0, D * 0.5 - hall * 0.5, W, D * 0.5 + hall * 0.5, "Hall and stairs" if f > 0 or stories > 1 else "Hall"]]
		# half the units on the street side, half on the back
		var front_u: Array = fl.slice(0, int(ceil(float(fl.size()) / 2.0)))
		var back_u: Array = fl.slice(front_u.size())
		for side in [[front_u, 0.0, D * 0.5 - hall * 0.5, 0], [back_u, D * 0.5 + hall * 0.5, D, front_u.size()]]:
			var row: Array = side[0]
			var rt: float = 0.0
			for u in row:
				rt += float(u["sqft"])
			var x: float = 0.0
			for k in row.size():
				var uw: float = W * float(row[k]["sqft"]) / maxf(1.0, rt)
				rects.append([x, float(side[1]), x + uw, float(side[2]), "Apt %d  %s" % [u0 + int(side[3]) + k + 1, str(TYPES[str(row[k]["type"])]["short"])]])
				x += uw
		out.append({"name": "Ground floor" if f == 0 else "Floor %d" % (f + 1), "rects": rects, "W": W, "D": D, "labels": true})
		u0 += fl.size()
	return out


static func site_parts(l: Dictionary, spec: Dictionary) -> Array:
	var lay: Dictionary = layout(l, spec)
	var out: Array = []
	for k in ["parking", "playground", "building"]:
		if lay.has(k):
			out.append([k, lay[k], {"parking": "parking", "playground": "play", "building": "apartments"}[k]])
	return out


# ---------------------------------------------------------------- builders

## Once a month a Sim with money looks at a town short of rentals and may build.
static func monthly(w: LTWorld) -> void:
	var dm: Dictionary = demand(w)
	if int(dm["vacant"]) > 1 or float(dm["total"]) < 3.0:
		return
	for p in w.projects:
		if str(p["ptype"]) == "apartments" and ["bidding", "review", "building"].has(str(p["status"])):
			return
	# a lot zoned for it
	var lot: Dictionary = {}
	for l in w.lots:
		if str(l["use"]) == "empty" and ["residential", "mixed"].has(str(l["zone"])) and not bool(l.get("removed", false)) and not bool(l.get("hold", false)) and LTGeography.lot_area(l) >= 700.0:
			if str(l["owner_kind"]) == "city" or l.has("for_sale"):
				lot = l
				break
	if lot.is_empty():
		return
	# who: someone with money, business sense and the nerve for it
	var best: Dictionary = {}
	var best_s: float = -1e9
	for c in w.citizens:
		if not w.is_present(c) or w.age_years(c) < 28 or w.age_years(c) > 72:
			continue
		var tt: Dictionary = c["traits"]
		var s: float = float(tt["ambition"]) * 0.4 + float(tt["greed"]) * 0.2 + float(c["skills"]["finance"]) * 0.3 + float(w.cash(c)) / 1000000.0
		if w.cash(c) < LTMoney.dollars(60000.0):
			continue
		# at small town rents new apartments only pay under rent capped rural loans,
		# which the greediest will not take
		if float(tt["greed"]) > 72.0:
			continue
		if s > best_s:
			best_s = s
			best = c
	if best.is_empty() or best_s < 45.0 or w.rng.randf() > 0.5:
		return
	var budget: int = w.cash(best) * 4
	var spec: Dictionary = design(w, lot, {"traits": best["traits"], "name": w.full_name(best), "budget": budget})
	var land: int = int(lot["for_sale"]) if lot.has("for_sale") else LTGeography.asking_price(w, int(lot["id"]))
	var price: int = cost(spec)
	var score: int = int(best["credit"]["score"]) if bool(best["credit"]["has_file"]) else 0
	if score < LTFinance.bank_min_score(w, "business_loan") - 40:
		w.log_sim(best, "Wanted to build apartments and the bank said no: credit %d is too low." % score, false)
		return
	# a regular bank mortgage: 25% down, 25 years, the rents left after vacancy, taxes
	# and upkeep (about 60% of the rent roll) covering the payment 1.2 times
	var program: String = "a bank mortgage"
	var down_share: float = 0.25
	var rate: float = LTFinance.bank_rate(w, "business_loan", maxi(score, 600)) - 0.01
	var months: int = 300
	var cover: float = float(_rent_roll(spec)) * 0.6 / maxf(1.0, float(LTFinance.amortized_payment(int(float(price + land) * 0.75), rate, months)))
	if cover < 1.2:
		# new apartments rarely pay at small town rents; what gets them built is USDA
		# Rural Development's rural rental housing loan: about 1% over up to 50 years,
		# 5% down, in return for keeping the rents affordable. The greediest pass.
		if float(best["traits"]["greed"]) > 72.0:
			w.log_sim(best, "Looked at building apartments: at these rents a bank mortgage does not pay, and a rural housing loan would cap the rents. Passed.", false)
			return
		program = "a USDA Rural Development rental housing loan at about 1%, in return for affordable rents"
		down_share = 0.05
		rate = 0.012
		months = 480
		for u in spec["units"]:
			u["rent"] = mini(int(u["rent"]), LTMoney.dollars(float(TYPES[str(u["type"])]["rent"])))
		spec["why"].append("rents kept affordable under a USDA rural rental housing loan")
		cover = float(_rent_roll(spec)) * 0.6 / maxf(1.0, float(LTFinance.amortized_payment(int(float(price + land) * 0.95), rate, months)))
		if cover < 1.1:
			w.log_sim(best, "Looked at building apartments: even with a rural housing loan the rents would not cover the payments.", false)
			return
	var down: int = int(float(price + land) * down_share)
	if w.cash(best) < down + land:
		return
	var dec: Dictionary = {"ok": true, "rate": rate}
	var acct: String = w.acct_p(best)
	LTCivic.property_sale(w, acct, LTCivic.owner_acct(w, lot), land, int(lot["id"]))
	lot["owner_kind"] = "sim"
	lot["owner_id"] = int(best["id"])
	lot.erase("for_sale")
	var r: Dictionary = LTProjects.define_project(w, "apartments", int(lot["id"]), int(float(price) * 1.3), -1, false,
		{"kind": "apt_dev", "id": int(best["id"]), "name": w.full_name(best), "acct": acct}, price, sqft(spec))
	if not bool(r.get("ok", false)):
		return
	var p: Dictionary = w.projects[int(r["project_id"])]
	p["title"] = "%s's apartments: %d homes" % [best["last_name"], spec["units"].size()]
	p["apt"] = spec
	var escrow: String = "escrow:%d" % int(p["id"])
	var need: int = int(float(price) * 1.3)
	var own: int = mini(w.cash(best), maxi(int(float(need) * down_share), down - land))
	w.ledger.pay(acct, escrow, own, "construction_escrow")
	var d: Dictionary = LTFinance.new_debt(w, "p", int(best["id"]), "bank", -1, "commercial_mortgage", need - own, float(dec["rate"]), months, "building", int(lot["id"]), [])
	LTFinance._dhist(w, d, "Financed with %s." % program)
	LTFinance.fund_loan(w, d, escrow, need - own)
	p["developer"]["acct"] = escrow
	p["developer"]["refund"] = acct
	var why: String = "; ".join(dm["why"].slice(0, 2)) if not dm["why"].is_empty() else "the town needs rentals"
	w.log_sim(best, "Started building %d apartments on %s (%s), financed with %s. Reason: %s." % [spec["units"].size(), LTGeography.lot_label(w, int(lot["id"])), text(spec), program, why], true)
	w.chronicle_add("%s is building %d apartments on %s: %s. Rents %s." % [w.full_name(best), spec["units"].size(), LTGeography.lot_street(w, int(lot["id"]))["name"], text(spec), rent_range(spec)], "housing", true, [best["id"]])


static func _rent_roll(spec: Dictionary) -> int:
	var t: int = 0
	for u in spec.get("units", []):
		t += int(u["rent"])
	return t


## A finished building opens for renters under its builder's own rental business.
static func open_rentals(w: LTWorld, owner: Dictionary, l: Dictionary) -> void:
	if owner.is_empty():
		l["owner_kind"] = "outside"
		l["owner_id"] = -1
		return
	var b: Dictionary = LTEconomy._new_business(w, "landlord", owner, int(l["id"]), "llc" if float(owner["skills"]["finance"]) > 45.0 else "sole")
	b["name"] = "%s Apartments" % owner["last_name"]
	b["status"] = "open"
	b["opened_day"] = w.day
	b["reputation"] = 50.0 + float(owner["traits"]["kindness"] - 50) * 0.4
	l["owner_kind"] = "business"
	l["owner_id"] = int(b["id"])
	l["name"] = str(b["name"])
	owner["owns"].append(int(b["id"]))
	b["start_reason"] = "Built new: %s. Rents %s." % [text(l["apt"]), rent_range(l["apt"])]
	w.log_biz(b, "Opened by %s. %s" % [w.full_name(owner), b["start_reason"]])
	w.log_sim(owner, "The apartments on %s are finished and open for renters." % LTGeography.lot_label(w, int(l["id"])), true)
	w.chronicle_add("%s opened on %s: %d new homes for rent." % [b["name"], LTGeography.lot_street(w, int(l["id"]))["name"], l["units"].size()], "housing", true, [owner["id"]])
