class_name LTEconomy
extends RefCounted
## Sim owned businesses: market reading, founding, daily operations, supply chains,
## customers, hiring and firing, closing. The player cannot place any of this.

const TYPES: Dictionary = {
	"grocery": {"display": "Grocery", "skill": "retail", "zones": ["commercial", "mixed"], "startup": 3200000, "staff": 1, "wage": 11200, "title": "grocery clerk", "license": 25000},
	"cafe": {"display": "Cafe", "skill": "cooking", "zones": ["commercial", "mixed"], "startup": 1500000, "staff": 1, "wage": 10400, "title": "cafe worker", "license": 20000},
	"general_store": {"display": "General Store", "skill": "management", "zones": ["commercial", "mixed"], "startup": 1800000, "staff": 1, "wage": 10400, "title": "store clerk", "license": 20000},
	"farm": {"display": "Farm", "skill": "farming", "zones": ["agricultural"], "startup": 2400000, "staff": 1, "wage": 10400, "title": "farm hand", "license": 15000},
	"construction": {"display": "Construction", "skill": "construction", "zones": ["commercial", "industrial", "mixed"], "startup": 1600000, "staff": 2, "wage": 14400, "title": "construction worker", "license": 30000},
	"landlord": {"display": "Rentals", "skill": "management", "zones": ["residential"], "startup": 0, "staff": 0, "wage": 0, "title": "", "license": 10000},
}
const FOOD_UNIT_PRICE: int = 800        # one person-day of groceries at the outside supermarket
const IMPORT_UNIT_COST: int = 560       # wholesale from Valley Wholesale
const IMPORT_DELIVERY_FEE: int = 4500
const PRODUCE_UNIT_PRICE: int = 380     # local farm to grocery, one person-day of fresh food
const PRODUCE_EXPORT_PRICE: int = 260   # farm surplus sold to the outside co-op
const MEAL_PRICE: int = 1100
const MEAL_COST: int = 420
const GOODS_PRICE: int = 2600           # household supplies for a week
const GOODS_COST: int = 1650
const OUTSIDE_TRIP_FUEL: int = 900
const SUFFIXES: Dictionary = {"grocery": ["Market", "Grocery", "Foods", "Fresh Market"], "cafe": ["Cafe", "Coffee House", "Diner", "Kitchen"], "general_store": ["General Store", "Supply", "Mercantile", "Hardware and Supply"], "farm": ["Farm", "Acres", "Family Farm", "Gardens"], "construction": ["Construction", "Builders", "Contracting", "and Sons Building"], "landlord": ["Rentals", "Property", "Apartments", "Housing"]}


## One lookup for every business type, the first six here and the rest in LTServices.
static func tcfg(btype) -> Dictionary:
	var k: String = str(btype)
	if TYPES.has(k):
		return TYPES[k]
	return LTServices.TYPES.get(k, {})


static func all_types() -> Array:
	var out: Array = TYPES.keys()
	out.append_array(LTServices.TYPES.keys())
	return out


# ================================================================ market reading

static func analyze_market(w: LTWorld) -> void:
	var m: Dictionary = {}
	var hh_n: int = 0
	var outside_grocery: int = 0
	var trip_minutes: float = 0.0
	var people: int = 0
	var adults: int = 0
	var adult_cash: int = 0
	for h in w.households:
		var ms: Array = w.household_members(h)
		if ms.is_empty() or int(h["lot"]) < 0:
			continue
		hh_n += 1
		people += ms.size()
		for p in ms:
			if w.age_years(p) >= 18:
				adults += 1
				adult_cash += w.cash(p)
		if str(h["last_grocery"]) == "outside" or str(h["last_grocery"]) == "":
			outside_grocery += 1
			trip_minutes += w.minutes_to_outside(int(h["lot"])) * 2.0
	m["households"] = hh_n
	m["people"] = people
	m["adults"] = adults
	m["food_units_day"] = float(people)
	m["grocery_outside_households"] = outside_grocery
	m["grocery_outside_share"] = 0.0 if hh_n == 0 else float(outside_grocery) / float(hh_n)
	m["avg_grocery_trip_minutes"] = 0.0 if outside_grocery == 0 else trip_minutes / float(outside_grocery)
	m["cafe_visits_day"] = float(adults) * 0.22
	m["goods_week"] = float(hh_n)
	var groceries: Array = w.open_businesses("grocery")
	var farms: Array = w.open_businesses("farm")
	m["grocery_count"] = groceries.size()
	m["farm_count"] = farms.size()
	m["cafe_count"] = w.open_businesses("cafe").size()
	m["general_count"] = w.open_businesses("general_store").size()
	m["construction_count"] = w.open_businesses("construction").size()
	var produce_need: float = 0.0
	for g in groceries:
		produce_need += float(people) * 0.35 / float(maxi(1, groceries.size()))
	m["produce_demand_day"] = produce_need
	m["construction_pipeline"] = LTProjects.pipeline_value(w)
	m["avg_adult_cash"] = 0 if adults == 0 else adult_cash / adults
	m["open_positions"] = open_positions(w)
	w.market = m


static func open_positions(w: LTWorld) -> int:
	var n: int = 0
	for b in w.businesses:
		if str(b["status"]) == "open":
			n += maxi(0, int(b["target_staff"]) - b["staff"].size())
	n += LTCivic.open_city_jobs(w)
	return n


# ================================================================ founding

## A Sim's own estimate of whether a business could work. Can be wrong: optimism
## scales with risk tolerance and falls with finance skill.
# ---------------------------------------------------------------- what it really costs to start

## Building size (square feet), equipment and opening stock in dollars, for a small
## town start up bought used where people really do (trucks, kitchen gear, coolers).
## Sheds are metal buildings, cheaper per foot than a storefront.
const COSTS: Dictionary = {
	"grocery": {"sqft": 4000, "equipment": 120000, "stock": 60000, "shed": false},
	"cafe": {"sqft": 1500, "equipment": 70000, "stock": 5000, "shed": false},
	"general_store": {"sqft": 2500, "equipment": 30000, "stock": 40000, "shed": false},
	"farm": {"sqft": 2400, "equipment": 150000, "stock": 30000, "shed": true},
	"construction": {"sqft": 1600, "equipment": 45000, "stock": 5000, "shed": true},
	"clinic": {"sqft": 3000, "equipment": 150000, "stock": 15000, "shed": false},
	"pharmacy": {"sqft": 1500, "equipment": 40000, "stock": 80000, "shed": false},
	"private_school": {"sqft": 4000, "equipment": 40000, "stock": 5000, "shed": false},
	"repair_shop": {"sqft": 2000, "equipment": 50000, "stock": 10000, "shed": true},
	"factory": {"sqft": 10000, "equipment": 400000, "stock": 50000, "shed": true},
	"warehouse": {"sqft": 8000, "equipment": 60000, "stock": 0, "shed": true},
	"trucking": {"sqft": 1500, "equipment": 250000, "stock": 5000, "shed": true},
	"hotel": {"sqft": 6000, "equipment": 120000, "stock": 5000, "shed": false},
	"bar": {"sqft": 1500, "equipment": 50000, "stock": 10000, "shed": false},
	"childcare": {"sqft": 2500, "equipment": 25000, "stock": 3000, "shed": false},
	"funeral_home": {"sqft": 3000, "equipment": 60000, "stock": 15000, "shed": false},
	"law_office": {"sqft": 800, "equipment": 15000, "stock": 0, "shed": false},
	"real_estate": {"sqft": 600, "equipment": 8000, "stock": 0, "shed": false},
	"mill": {"sqft": 3000, "equipment": 200000, "stock": 20000, "shed": true},
	"bakery": {"sqft": 1500, "equipment": 60000, "stock": 3000, "shed": false},
	"bank": {"sqft": 3000, "equipment": 200000, "stock": 0, "shed": false},
	"outfitter": {"sqft": 2000, "equipment": 25000, "stock": 40000, "shed": false},
	"marina": {"sqft": 1200, "equipment": 90000, "stock": 5000, "shed": true},
	"campground": {"sqft": 800, "equipment": 60000, "stock": 2000, "shed": true},
	"guide_service": {"sqft": 600, "equipment": 30000, "stock": 3000, "shed": false},
	"sawmill": {"sqft": 6000, "equipment": 350000, "stock": 10000, "shed": true},
	"quarry": {"sqft": 2000, "equipment": 600000, "stock": 0, "shed": true},
	"gold_mine": {"sqft": 5000, "equipment": 3500000, "stock": 0, "shed": true},
}
## Businesses that live off the land need it close by: [feature, meters, lakefront only]
const NEEDS_LAND: Dictionary = {
	"marina": ["lake", 60.0, true], "campground": ["lake|forest", 300.0, false], "sawmill": ["forest", 450.0, false],
	"quarry": ["mountain", 400.0, false], "gold_mine": ["mountain", 300.0, false],
}
const STOREFRONT_PER_SQFT: float = 165.0
const SHED_PER_SQFT: float = 95.0
## Kinds of business people really start from home: a contractor with a truck and
## tools, a mechanic in the garage, home daycare, a cottage bakery, a lawyer or
## realtor with a home office, an owner operator with a truck in the yard.
const HOME_OK: Dictionary = {
	"construction": {"equipment": 45000, "stock": 3000, "what": "a used truck, a trailer and tools, run from home"},
	"repair_shop": {"equipment": 20000, "stock": 4000, "what": "tools and a lift in the home garage"},
	"childcare": {"equipment": 5000, "stock": 1000, "what": "a licensed home daycare"},
	"bakery": {"equipment": 8000, "stock": 1000, "what": "a cottage bakery from the home kitchen"},
	"law_office": {"equipment": 6000, "stock": 0, "what": "a home office"},
	"real_estate": {"equipment": 3000, "stock": 0, "what": "a home office and a car"},
	"trucking": {"equipment": 120000, "stock": 2000, "what": "one used semi parked in the yard"},
	"guide_service": {"equipment": 15000, "stock": 1000, "what": "a truck, a boat and gear, run from home"},
}


## Every dollar a founder needs before opening day, in cents:
## {building, equipment, stock, reserve, license, total, sqft, home, existing}
## Businesses are sized to the town: a 100 person town gets a corner market, not
## a supermarket. `existing` means moving into an empty building already standing.
static func startup_costs(w: LTWorld, btype: String, home_based: bool, existing: bool = false) -> Dictionary:
	var cfg: Dictionary = tcfg(btype)
	var sheet: Dictionary = COSTS.get(btype, {"sqft": 1500, "equipment": 20000, "stock": 5000, "shed": false})
	var building: int = 0
	var sqft: int = 0
	var equipment: int = LTMoney.dollars(float(sheet["equipment"]))
	var stock: int = LTMoney.dollars(float(sheet["stock"]))
	var scale: float = clampf(float(_town_size(w)) / 1000.0, 0.35, 1.5)
	if home_based and HOME_OK.has(btype):
		equipment = LTMoney.dollars(float(HOME_OK[btype]["equipment"]))
		stock = LTMoney.dollars(float(HOME_OK[btype]["stock"]))
	else:
		sqft = maxi(400, int(float(sheet["sqft"]) * scale / 50.0) * 50)
		equipment = int(float(equipment) * (0.5 + scale * 0.5))
		stock = int(float(stock) * scale)
		if not existing:
			building = LTMoney.dollars(float(sqft) * (SHED_PER_SQFT if bool(sheet["shed"]) else STOREFRONT_PER_SQFT))
	# three months of wages and utilities to get through the slow start
	var staff: int = 0 if home_based else int(cfg["staff"])
	var wage: int = maxi(int(cfg["wage"]), LTCivic.min_daily_wage(w))
	var reserve: int = (staff * wage * 22 + LTMoney.dollars(260.0)) * 3
	var license: int = int(float(cfg["license"]) * LTCivic.law(w, "license_fee"))
	return {"building": building, "equipment": equipment, "stock": stock, "reserve": reserve, "license": license,
		"total": building + equipment + stock + reserve + license, "sqft": sqft, "home": home_based and HOME_OK.has(btype), "existing": existing}


static func costs_text(cs: Dictionary) -> String:
	var parts: Array = []
	if int(cs["building"]) > 0:
		parts.append("a %d square foot building %s" % [int(cs["sqft"]), LTMoney.fmt(int(cs["building"]))])
	elif bool(cs.get("existing", false)):
		parts.append("leasing an empty building already standing")
	parts.append("equipment %s" % LTMoney.fmt(int(cs["equipment"])))
	if int(cs["stock"]) > 0:
		parts.append("opening stock %s" % LTMoney.fmt(int(cs["stock"])))
	parts.append("three months of cash to get started %s" % LTMoney.fmt(int(cs["reserve"])))
	parts.append("license %s" % LTMoney.fmt(int(cs["license"])))
	return "%s in all: %s" % [LTMoney.fmt(int(cs["total"])), ", ".join(parts)]


static func consider_founding(w: LTWorld, c: Dictionary) -> Dictionary:
	var t: Dictionary = c["traits"]
	var n: Dictionary = c["needs"]
	if float(n["hunger"]) < 35.0 or float(n["health"]) < 35.0 or bool(c["homeless"]):
		return {}
	var drive: float = float(t["ambition"]) * 0.45 + float(t["risk"]) * 0.3 + float(t["intelligence"]) * 0.1
	if drive < 38.0:
		return {}
	var best: Dictionary = {}
	for btype in all_types():
		if btype == "landlord" or _recently_opened(w, btype):
			continue
		var plan: Dictionary = _evaluate(w, c, btype)
		if plan.is_empty():
			continue
		# people notice when the last one failed here and grow warier
		var fails: int = recent_failures(w, btype)
		if fails > 0:
			plan["score"] = float(plan["score"]) - 18.0 * float(fails)
			plan["doubt"] = "%d %s closed here in the last three years" % [fails, "of them" if fails > 1 else "like it"]
		if best.is_empty() or float(plan["score"]) > float(best["score"]):
			best = plan
	if best.is_empty():
		return {}
	best["reason"] = plan_reason(w, c, best)
	if float(best["score"]) < 28.0:
		if w.rng.randf() < 0.15:
			w.counters["founding_failed"] = int(w.counters["founding_failed"]) + 1
			w.log_sim(c, "Looked at starting a %s and decided against it. Reason: %s." % [str(tcfg(best["type"])["display"]).to_lower(), best["doubt"]], true)
		return {}
	return best


static func recent_failures(w: LTWorld, btype: String) -> int:
	var n: int = 0
	for b in w.businesses:
		if str(b["type"]) == btype and str(b["status"]) != "open" and int(b["closed_day"]) >= 0 and w.day - int(b["closed_day"]) < 3 * 365 and w.day - int(b["opened_day"]) < 3 * 365:
			n += 1
	return n


## People in town, counted once a day (founders ask often).
static func _town_size(w: LTWorld) -> int:
	if int(w.market.get("pop_day", -1)) != w.day:
		w.market["pop_day"] = w.day
		w.market["pop"] = w.alive_count()
	return int(w.market["pop"])


## The nearest empty building (a business that closed) in one of the zones.
static func _vacant_building(w: LTWorld, zones: Array, near_lot: int) -> int:
	if int(w.market.get("closed_day", -1)) != w.day:
		var closed: Array = []
		for l0 in w.lots:
			if str(l0["use"]) == "closed" and not bool(l0.get("hold", false)):
				closed.append(l0)
		w.market["closed_day"] = w.day
		w.market["closed_lots"] = closed
	var best: int = -1
	var best_d: float = 1e9
	for l in w.market["closed_lots"]:
		if str(l["use"]) != "closed" or not zones.has(str(l["zone"])):
			continue
		var d: float = 0.0
		if near_lot >= 0:
			var a: Dictionary = w.lot(near_lot)
			d = absf(float(a["col"]) - float(l["col"])) + absf(float(a["row"]) - float(l["row"]))
		if d < best_d:
			best_d = d
			best = int(l["id"])
	return best


static func _home_free(w: LTWorld, lot_id: int) -> bool:
	for b in w.businesses:
		if int(b["lot"]) == lot_id and ["open", "building"].has(str(b["status"])):
			return false
	return true


## Founders watch each other: right after one opens, others wait to see how it does.
static func _recently_opened(w: LTWorld, btype: String) -> bool:
	for b in w.businesses:
		if str(b["type"]) == btype and str(b["status"]) == "open" and w.day - int(b["opened_day"]) < 120:
			return true
	return false


static func _evaluate(w: LTWorld, c: Dictionary, btype: String) -> Dictionary:
	var cfg: Dictionary = tcfg(btype)
	var t: Dictionary = c["traits"]
	var skill: float = float(c["skills"][str(cfg["skill"])])
	if skill < float(cfg.get("min_skill", 22)):
		return {}
	if btype == "bank" and not bool(w.city["laws"].get("bank_charter", 0)):
		return {}
	var m: Dictionary = w.market
	var need: Dictionary = LTCivic.open_need_for(w, btype)
	var zones: Array = cfg["zones"]
	var lot_id: int = -1
	if not need.is_empty() and int(need["lot"]) >= 0 and str(w.lot(int(need["lot"]))["use"]) == "empty":
		lot_id = int(need["lot"])
	else:
		var near: Array = [int(w.hh(int(c["household"]))["lot"])]
		lot_id = LTGeography.best_site(w, zones, near)
	# businesses that live off the land go where the land is
	if NEEDS_LAND.has(btype):
		var nl: Array = NEEDS_LAND[btype]
		if LTTerrain.t(w).is_empty():
			return {}
		var best_l: int = -1
		for feat in str(nl[0]).split("|"):
			var cand: int = LTTerrain.site_near(w, zones, feat, float(nl[1]), bool(nl[2]))
			if cand >= 0:
				best_l = cand
				break
		if best_l < 0:
			return {}
		lot_id = best_l
	# an empty building already standing is far cheaper than building new
	var existing: bool = false
	var vacant: int = _vacant_building(w, zones, int(w.hh(int(c["household"]))["lot"]))
	if vacant >= 0 and (lot_id < 0 or need.is_empty() or int(need["lot"]) != lot_id):
		lot_id = vacant
		existing = true
	# a founder who cannot put down 15% on a real building, and whose kind of
	# business can run from home, starts at home instead
	var home_based: bool = false
	var hh_lot: int = int(w.hh(int(c["household"]))["lot"])
	if HOME_OK.has(btype) and hh_lot >= 0 and str(w.lot(hh_lot)["use"]) == "house" and _home_free(w, hh_lot):
		var full: Dictionary = startup_costs(w, btype, false)
		# most small town businesses of these kinds start at home
		if lot_id < 0 or _town_size(w) < 400 or (not existing and w.cash(c) < int(float(full["total"]) * 0.15)):
			home_based = true
			existing = false
			lot_id = hh_lot
	if lot_id < 0:
		return {}
	# expected monthly sales and margin, from the Sim's view of the market
	var monthly_gross: float = 0.0
	var gross_margin: float = 0.0
	var doubt: String = ""
	var service_why: String = ""
	match btype:
		"grocery":
			var share: float = 0.7 / float(int(m["grocery_count"]) + 1)
			if int(m["grocery_count"]) == 0:
				share = 0.75
			monthly_gross = float(m["food_units_day"]) * 30.0 * share * float(FOOD_UNIT_PRICE) * 1.06
			gross_margin = 0.30
			doubt = "not enough shoppers to cover rent and wages" if int(m["grocery_count"]) > 0 else "the start up cost is more than the savings and the bank would lend"
		"cafe":
			var share2: float = 1.0 / float(int(m["cafe_count"]) + 1)
			monthly_gross = float(m["cafe_visits_day"]) * 30.0 * share2 * float(MEAL_PRICE) * clampf(float(m["avg_adult_cash"]) / 800000.0, 0.4, 1.2)
			gross_margin = 0.58
			doubt = "people here do not have much spare money for eating out"
		"general_store":
			var share3: float = 0.6 / float(int(m["general_count"]) + 1)
			monthly_gross = float(m["goods_week"]) * 4.3 * share3 * float(GOODS_PRICE)
			gross_margin = 0.33
			doubt = "the town is too small for a general store to make rent"
		"farm":
			var local: float = float(m["produce_demand_day"]) * 30.0 * float(PRODUCE_UNIT_PRICE) / float(int(m["farm_count"]) + 1)
			monthly_gross = local + 30.0 * 95.0 * float(PRODUCE_EXPORT_PRICE)
			gross_margin = 0.55
			doubt = "farm prices are thin unless a local grocery buys the produce"
		"construction":
			var pipeline: float = float(m["construction_pipeline"]) / float(int(m["construction_count"]) + 1)
			var upkeep_market: float = 0.0
			for l in w.lots:
				if str(l["owner_kind"]) == "business":
					upkeep_market += float(l["units"].size()) * 12000.0
			monthly_gross = pipeline / 8.0 + upkeep_market / float(int(m["construction_count"]) + 1) + 30.0 * 3000.0
			gross_margin = 0.30
			doubt = "not enough building work in town to keep a crew busy"
		_:
			var est_s: Dictionary = LTServices.estimate(w, btype)
			monthly_gross = float(est_s["gross"])
			gross_margin = float(est_s["margin"])
			doubt = str(est_s["doubt"])
			service_why = str(est_s["why"])
	var staff: int = 0 if home_based else int(cfg["staff"])
	var wage: int = maxi(int(cfg["wage"]), LTCivic.min_daily_wage(w))
	var costs: float = float(staff * wage) * 22.0
	var lot_rent: int = LTCivic.lot_rent(w, lot_id)
	if not need.is_empty() and bool(need["incentives"].get("free_lot", false)):
		lot_rent = 0
	if home_based:
		lot_rent = 0
	elif existing:
		lot_rent *= 3   # leasing a building, not just the ground
	costs += float(lot_rent) + 30000.0
	var cs: Dictionary = startup_costs(w, btype, home_based, existing)
	var startup: int = int(cs["total"])
	var loan_need: int = maxi(0, startup - maxi(0, w.cash(c) - LTMoney.dollars(2000.0)))
	var grant: int = int(need["incentives"].get("grant", 0)) if not need.is_empty() else 0
	loan_need = maxi(0, loan_need - grant)
	# the building is a 20 year mortgage, equipment and stock a 7 year loan
	var mort_need: int = mini(loan_need, int(float(cs["building"]) * 0.85))
	costs += float(LTFinance.amortized_payment(mort_need, 0.075, 240)) + float(LTFinance.amortized_payment(loan_need - mort_need, 0.09, 84))
	var tax: float = LTCivic.business_tax_rate(w)
	if not need.is_empty() and int(need["incentives"].get("tax_break_years", 0)) > 0:
		tax = 0.0
	var profit: float = (monthly_gross * gross_margin - costs) * (1.0 - tax)
	var optimism: float = 1.0 + (float(t["risk"]) - 50.0) / 100.0 * 0.7 - float(c["skills"]["finance"]) / 400.0
	var est: float = profit * optimism
	var current_income: float = float(c["job"]["daily_wage"]) * 21.0
	# funding check from the Sim's side, no inquiry yet
	var can_fund: bool = loan_need == 0
	var funding_note: String = "savings"
	if not can_fund:
		var score: int = int(c["credit"]["score"])
		var guarantee: bool = not need.is_empty() and bool(need["incentives"].get("loan_guarantee", false))
		# small business loans (SBA style) need about 10% down, 5% with a city guarantee
		var down_ok: bool = w.cash(c) + grant >= int(float(startup) * (0.05 if guarantee else 0.1))
		var bar: int = LTFinance.bank_min_score(w, "business_loan") - (60 if guarantee else 0)
		can_fund = down_ok and bool(c["credit"]["has_file"]) and score >= bar - int(float(t["risk"]) * 0.3)
		funding_note = "savings and a bank loan" + (" backed by the city guarantee" if guarantee else "")
		if not can_fund:
			var family: int = _family_money(w, c)
			if family + w.cash(c) + grant >= startup:
				can_fund = true
				funding_note = "savings and money borrowed from family"
		if not can_fund and startup >= LTMoney.dollars(40000.0) and float(c["skills"]["finance"]) + float(c["skills"]["management"]) > 90.0 and w.cash(c) >= startup / 10:
			can_fund = true
			funding_note = "savings and outside investors who take a share"
		if not can_fund:
			doubt = "the start up cost of %s is more than savings, family money, and what the bank would lend" % LTMoney.fmt(startup)
	if grant > 0:
		funding_note += " and a city start up grant"
	var score_v: float = float(t["ambition"]) * 0.3 + float(t["risk"]) * 0.2 + skill * 0.25
	score_v += clampf((est - current_income * 0.6) / 100.0 / 50.0, -25.0, 25.0)
	score_v -= LTFinance.debt_stress(w, c) * 25.0
	score_v -= (100.0 - float(c["needs"]["money_security"])) * 0.08
	if not need.is_empty():
		score_v += 8.0 + float(need["incentives"].size()) * 3.0
	if not can_fund:
		score_v -= 40.0
	if est <= 0.0:
		score_v -= 20.0
	return {"type": btype, "lot": lot_id, "score": score_v, "est_monthly": int(est), "startup": startup, "loan_need": loan_need, "grant": grant, "need_id": int(need.get("id", -1)), "funding": funding_note, "reason": "", "doubt": doubt, "skill": skill, "service_why": service_why, "has_need": not need.is_empty(), "home": home_based, "costs": cs}


## The plain words a Sim gives for a plan, built only for the plan they pick.
static func plan_reason(w: LTWorld, c: Dictionary, plan: Dictionary) -> String:
	var btype: String = str(plan["type"])
	var cfg: Dictionary = tcfg(btype)
	var m: Dictionary = w.market
	var skill: float = float(plan["skill"])
	var est: float = float(plan["est_monthly"])
	var service_why: String = str(plan["service_why"])
	var need: Dictionary = {"x": 1} if bool(plan["has_need"]) else {}
	var why: Array = []
	match btype:
		"grocery":
			if int(m["grocery_count"]) == 0:
				why.append("%d of %d households drive about %d minutes round trip for groceries" % [m["grocery_outside_households"], m["households"], int(m["avg_grocery_trip_minutes"])])
			else:
				why.append("the town has room for another grocery")
		"cafe":
			why.append("there is nowhere in town to sit down and eat")
		"general_store":
			why.append("households drive out of town for basic supplies")
		"farm":
			why.append("the grocery imports fresh food that could be grown here" if int(m["grocery_count"]) > 0 else "there is open farmland and the outside co-op buys produce")
		"construction":
			why.append("the city and landlords hire outside builders for everything")
		_:
			if service_why != "":
				why.append(service_why)
	why.append("%s skill is %d" % [cfg["skill"], int(skill)])
	why.append("expects about %s a month after costs" % LTMoney.fmt(int(est)))
	if not need.is_empty():
		why.append("the city published this need with incentives")
	return ", ".join(why)


static func _family_money(w: LTWorld, c: Dictionary) -> int:
	var t: int = 0
	for k in c["rel"]:
		var r: Dictionary = c["rel"][k]
		if not ["parent", "child", "spouse"].has(str(r["kind"])):
			continue
		var o: Dictionary = w.cit(int(k))
		if w.is_present(o) and int(o["household"]) != int(c["household"]) and float(r["trust"]) > 50.0:
			t += maxi(0, w.cash(o) - LTMoney.dollars(5000.0)) / 2
	return t


static func found_business(w: LTWorld, c: Dictionary, plan: Dictionary) -> void:
	var btype: String = str(plan["type"])
	var cfg: Dictionary = tcfg(btype)
	w.counters["founding_attempts"] = int(w.counters["founding_attempts"]) + 1
	var lot_id: int = int(plan["lot"])
	var home: bool = bool(plan.get("home", false))
	var existing: bool = bool(plan.get("costs", {}).get("existing", false))
	if home:
		if str(w.lot(lot_id)["use"]) != "house" or not _home_free(w, lot_id):
			return
	elif existing:
		if str(w.lot(lot_id)["use"]) != "closed":
			return
	elif str(w.lot(lot_id)["use"]) != "empty":
		return
	var cs: Dictionary = plan.get("costs", startup_costs(w, btype, home))
	var startup: int = int(cs["total"])
	var need: Dictionary = w.city_needs[int(plan["need_id"])] if int(plan["need_id"]) >= 0 else {}
	# legal form: an LLC costs money and paperwork, finance and management skill decide
	var llc_score: float = float(c["skills"]["finance"]) * 0.5 + float(c["skills"]["management"]) * 0.3 + float(c["traits"]["discipline"]) * 0.2
	var legal: String = "llc" if llc_score > 52.0 else "sole"
	var b: Dictionary = _new_business(w, btype, c, lot_id, legal)
	var acct: String = w.acct_b(b)
	var own: int = mini(maxi(0, w.cash(c) - LTMoney.dollars(1500.0)), startup)
	w.ledger.pay(w.acct_p(c), acct, own, "owner_investment")
	var sources: Array = ["%s of savings" % LTMoney.fmt(own)]
	var grant: int = int(plan["grant"])
	if grant > 0:
		var g: int = w.ledger.pay("city", acct, grant, "city_grants")
		sources.append("a %s city grant" % LTMoney.fmt(g))
		b["grant_received"] = g
		w.city["grants_paid"] = int(w.city.get("grants_paid", 0)) + g
	var gap: int = startup - w.biz_cash(b)
	if gap > 0:
		var guarantee: bool = not need.is_empty() and bool(need["incentives"].get("loan_guarantee", false))
		var dec: Dictionary = LTFinance.business_offer(w, c, cs, w.biz_cash(b), int(plan["est_monthly"]))
		if not bool(dec["ok"]) and not guarantee:
			# short on the down payment: family may help, then back to the bank
			var famh: int = _family_help(w, c, b, acct, int(float(startup) * 0.2) - w.biz_cash(b))
			if famh > 0:
				sources.append("%s from family toward the down payment" % LTMoney.fmt(famh))
				dec = LTFinance.business_offer(w, c, cs, w.biz_cash(b), int(plan["est_monthly"]))
				gap = startup - w.biz_cash(b)
		if not bool(dec["ok"]) and guarantee:
			dec = {"ok": true, "rate": LTFinance.bank_rate(w, "business_loan", 680), "reason": "the city guarantee", "program": "bank loan with a city guarantee", "re_years": 20, "years": 7}
		if bool(dec["ok"]) and gap > 0:
			# the building on a long real estate loan, equipment and the rest shorter
			var parts: Array = []
			var mort: int = mini(gap, int(dec.get("re_part", int(float(cs["building"]) * 0.85))))
			var fee: int = int(dec.get("fee", 0))
			if mort > 0:
				parts.append(LTFinance.new_debt(w, "b", int(b["id"]), "bank", -1, "commercial_mortgage", mort, float(dec["rate"]) - 0.01, int(dec.get("re_years", 20)) * 12, "building", lot_id, []))
			if gap - mort + fee > 0:
				parts.append(LTFinance.new_debt(w, "b", int(b["id"]), "bank", -1, "business_loan", gap - mort + fee, float(dec["rate"]), int(dec.get("years", 7)) * 12, "equipment", -1, []))
			if fee > 0:
				w.ledger.pay(acct, "outside", fee, "sba_fees")
			for d in parts:
				if bool(dec.get("sba", false)):
					d["sba"] = true
					LTFinance._dhist(w, d, "Made under the SBA program: the government guarantees 75% if it goes bad.")
				if legal == "llc" and w.day - int(c.get("moved_in", 0)) >= 0:
					d["guarantor"] = int(c["id"])
					w.debt_index_dirty = true
					LTFinance._dhist(w, d, "%s signed a personal guarantee, as the bank requires from new founders." % w.full_name(c))
				if guarantee:
					d["city_guarantee"] = true
					LTFinance._dhist(w, d, "The city guarantees this loan if it defaults.")
				LTFinance.fund_loan(w, d, acct, int(d["balance"]))
			w.bank["lent_12m"] = int(w.bank["lent_12m"]) + gap
			w.counters["loans_made"] = int(w.counters["loans_made"]) + 1
			sources.append("a %s %s at %.1f%%%s" % [LTMoney.fmt(gap), str(dec.get("program", "bank loan")), float(dec["rate"]) * 100.0, " with a personal guarantee" if legal == "llc" else ""])
		else:
			var fam: int = 0
			for k in c["rel"]:
				if fam >= gap:
					break
				var r: Dictionary = c["rel"][k]
				var o: Dictionary = w.cit(int(k))
				if not w.is_present(o) or int(o["household"]) == int(c["household"]) or not ["parent", "child", "spouse"].has(str(r["kind"])):
					continue
				var lend: int = mini(gap - fam, maxi(0, w.cash(o) - LTMoney.dollars(5000.0)) / 2)
				if lend > LTMoney.dollars(500.0) and float(o["traits"]["kindness"]) + float(r["trust"]) > 90.0:
					w.ledger.pay(w.acct_p(o), acct, lend, "family_loans")
					LTFinance.new_debt(w, "p", int(c["id"]), "person", int(o["id"]), "family_loan", lend, 0.02, 60, "", -1, [])
					w.log_sim(o, "Lent %s to %s to start %s. Reason: trust and family." % [LTMoney.fmt(lend), c["first_name"], b["name"]], true)
					fam += lend
			if fam > 0:
				sources.append("%s borrowed from family" % LTMoney.fmt(fam))
			if w.biz_cash(b) < int(float(startup) * 0.8) and startup >= LTMoney.dollars(40000.0) and float(c["skills"]["finance"]) + float(c["skills"]["management"]) > 90.0:
				var inv: int = startup - w.biz_cash(b)
				w.ledger.pay("outside", acct, inv, "outside_investment")
				b["investor_share"] = float(inv) / float(startup)
				sources.append("%s from outside investors for a %d%% share" % [LTMoney.fmt(inv), int(float(b["investor_share"]) * 100.0)])
			if w.biz_cash(b) < int(float(startup) * 0.8):
				var partner: Dictionary = LTFamily.find_partner(w, c, startup - w.biz_cash(b))
				if not partner.is_empty():
					var put: int = w.ledger.pay(w.acct_p(partner), acct, startup - w.biz_cash(b), "partner_investment")
					b["owners"].append(int(partner["id"]))
					partner["owns"].append(int(b["id"]))
					sources.append("%s from a partner, %s" % [LTMoney.fmt(put), w.full_name(partner)])
					w.log_sim(partner, "Became a partner in %s by putting in %s. Reason: trusts %s and liked the plan." % [b["name"], LTMoney.fmt(put), c["first_name"]], true)
			if w.biz_cash(b) < int(float(startup) * 0.8):
				# not enough: unwind, nothing is created or destroyed
				w.counters["loans_denied"] = int(w.counters["loans_denied"]) + 1
				w.counters["founding_failed"] = int(w.counters["founding_failed"]) + 1
				_unwind(w, b, c)
				w.log_sim(c, "Tried to start a %s and could not raise the money. The bank said no: %s. The banker's advice: %s." % [str(cfg["display"]).to_lower(), dec["reason"], dec.get("advice", "come back with more money down")], true)
				c["bank_advice"] = {"day": w.day, "text": str(dec.get("advice", "")), "for": btype}
				w.remember(c, "loan_denied", -1, -15.0)
				return
	# equipment is bought now, mostly used and from out of town; the building, if
	# there is one, is built by a contractor the founder hires, and paid as it rises
	w.ledger.pay(acct, "outside", int(cs["equipment"]), "equipment")
	if not ["grocery", "cafe", "general_store"].has(btype) and int(cs["stock"]) > 0:
		w.ledger.pay(acct, "outside", int(cs["stock"]), "opening_stock")
	# the license: some founders who were told no by the city, or who are short and not too honest, skip it
	var fee: int = int(float(cfg["license"]) * LTCivic.law(w, "license_fee"))
	var t2: Dictionary = c["traits"]
	var skip: float = float(t2["greed"]) * 0.3 - float(t2["honesty"]) * 0.6 + float(fee) / 100.0 / 50.0 + w.memory_weight(c, "petition_denied") * -0.8 - LTCivic.enforcement(w) * 20.0
	if skip > 12.0:
		b["unlicensed"] = true
		w.log_sim(c, "Opened without a business license to save %s. Reason: %s." % [LTMoney.fmt(fee), "the city ignored what the neighborhood asked for" if w.memory_weight(c, "petition_denied") < -1.0 else "the fee felt like one cost too many"], true)
	else:
		w.ledger.pay(acct, "city", fee, "license_fees")
	if legal == "llc":
		w.ledger.pay(acct, "outside", 50000, "llc_filing")
	b["need_id"] = int(plan["need_id"])
	b["plan_reason"] = str(plan["reason"])
	b["costs"] = cs
	c["owns"].append(int(b["id"]))
	var reason: String = "%s. It cost %s. Funded with %s." % [str(plan["reason"]), costs_text(cs), ", ".join(sources)]
	b["start_reason"] = reason
	if bool(cs["home"]):
		b["home_based"] = true
		b["start_reason"] = reason + " Run from home: %s." % HOME_OK[btype]["what"]
		open_business(w, b)
		return
	if bool(cs.get("existing", false)):
		b["bplan"] = LTBuildings.design(w, btype, c, maxi(800, int(cs["sqft"])), LTMoney.dollars(40000.0))
		b["start_reason"] = reason + " Moved into the empty building on %s." % LTGeography.lot_label(w, lot_id)
		b["building_lease"] = true
		open_business(w, b)
		return
	# a real building: the owner designs it, hires a builder through bids, opens when it is finished
	b["status"] = "building"
	var bplan: Dictionary = LTBuildings.design(w, btype, c, int(cs["sqft"]), maxi(0, w.biz_cash(b) + w.cash(c) - int(cs["total"]) - LTMoney.dollars(20000.0)))
	b["bplan"] = bplan
	# the owner puts in their own money for the extras
	var extras: int = LTBuildings.extras_cost(bplan)
	if extras > 0:
		w.ledger.pay(w.acct_p(c), acct, mini(extras, w.cash(c)), "owner_investment")
	var bcost: int = maxi(int(cs["building"]), LTBuildings.cost(bplan))
	var r: Dictionary = LTProjects.define_project(w, "shop", lot_id, int(float(bcost) * 1.3), -1, false,
		{"kind": "business", "id": int(b["id"]), "name": str(b["name"]), "acct": acct}, bcost, int(cs["sqft"]))
	if bool(r.get("ok", false)):
		var pr: Dictionary = w.projects[int(r["project_id"])]
		pr["business_id"] = int(b["id"])
		pr["title"] = "%s: a %d square foot building" % [b["name"], int(cs["sqft"])]
		b["project_id"] = int(pr["id"])
	w.log_sim(c, "Decided to start %s and hired builders for the building. Reason: %s" % [b["name"], reason], true)
	w.log_biz(b, "Planned by %s on %s. Reason: %s" % [w.full_name(c), LTGeography.lot_label(w, lot_id), reason])
	w.chronicle_add("%s is putting up a building on %s for %s." % [w.full_name(c), LTGeography.lot_street(w, lot_id)["name"], b["name"]], "business", false, [c["id"]])


## Parents, grown children and spouses in other households who trust the founder
## chip in toward the down payment. Returns what they put in.
static func _family_help(w: LTWorld, c: Dictionary, b: Dictionary, acct: String, want: int) -> int:
	if want <= 0:
		return 0
	var got: int = 0
	for k in c["rel"]:
		if got >= want:
			break
		var r: Dictionary = c["rel"][k]
		var o: Dictionary = w.cit(int(k))
		if not w.is_present(o) or int(o["household"]) == int(c["household"]) or not ["parent", "child", "spouse"].has(str(r["kind"])):
			continue
		var give: int = mini(want - got, maxi(0, w.cash(o) - LTMoney.dollars(5000.0)) / 2)
		if give > LTMoney.dollars(500.0) and float(o["traits"]["kindness"]) + float(r["trust"]) > 90.0:
			w.ledger.pay(w.acct_p(o), acct, give, "family_gifts")
			w.log_sim(o, "Gave %s to %s toward the down payment on %s. Reason: family, and the bank wanted more money down." % [LTMoney.fmt(give), c["first_name"], b["name"]], true)
			got += give
	return got


## Opening day: the building is finished (or the business runs from home).
static func open_business(w: LTWorld, b: Dictionary) -> void:
	var btype: String = str(b["type"])
	var cfg: Dictionary = tcfg(btype)
	var c: Dictionary = w.cit(int(b["owners"][0]))
	var lot_id: int = int(b["lot"])
	b["status"] = "open"
	b["opened_day"] = w.day
	var home: bool = bool(b.get("home_based", false))
	var l: Dictionary = w.lot(lot_id)
	if not home:
		l["use"] = "business"
		l["ref"] = int(b["id"])
		l["building"] = btype
		l["built_day"] = w.day
		l["condition"] = 85.0
		l["name"] = str(b["name"])
		if not b.has("bplan"):
			var sq: int = int(b.get("costs", {}).get("sqft", 0))
			if sq <= 0:
				sq = int(COSTS.get(btype, {"sqft": 1500})["sqft"])
			b["bplan"] = LTBuildings.design(w, btype, c, sq, LTMoney.dollars(w.rng.randf_range(0.0, 150000.0)))
		if b.has("bplan") and b["bplan"].get("features", []).has("apartments") and l["units"].is_empty():
			l["units"] = [-1, -1]
			l["unit_rent"] = LTMoney.dollars(750.0)
	else:
		b["free_lot"] = true
	var need: Dictionary = w.city_needs[int(b["need_id"])] if int(b.get("need_id", -1)) >= 0 else {}
	if not need.is_empty():
		need["status"] = "taken"
		need["taken_by"] = int(b["id"])
		need["taken_day"] = w.day
		b["incentives"] = need["incentives"].duplicate()
		if int(need["incentives"].get("tax_break_years", 0)) > 0:
			b["tax_break_until"] = w.day + 365 * int(need["incentives"]["tax_break_years"])
		if bool(need["incentives"].get("free_lot", false)):
			b["free_lot"] = true
	if not w.is_present(c):
		return
	if str(c["job"]["kind"]) != "none":
		leave_job(w, c, "started a business")
	LTPeople.set_job(w, c, "owner", int(b["id"]), "owner of " + str(b["name"]), 0, str(cfg["skill"]))
	w.log_biz(b, "Opened by %s %s. Reason: %s" % [w.full_name(c), "from home on " + LTGeography.lot_label(w, lot_id) if home else "on " + LTGeography.lot_label(w, lot_id), b["start_reason"]])
	w.log_biz(b, "Legal form: %s." % ("an LLC, which keeps business debt separate from the owner's own money unless they guaranteed it" if str(b["legal_form"]) == "llc" else "a sole proprietorship, so the owner and the business are the same legal pocket"))
	w.log_sim(c, "Opened %s. %s" % [b["name"], b["start_reason"]], true)
	w.remember(c, "founded", int(b["id"]), 20.0)
	w.counters["businesses_opened"] = int(w.counters["businesses_opened"]) + 1
	w.chronicle_add("%s opened %s%s. %s said: %s." % [w.full_name(c), b["name"], " from home" if home else " on " + str(LTGeography.lot_street(w, lot_id)["name"]), c["first_name"], b.get("plan_reason", "")], "business", true, [c["id"]])
	order_stock(w, b, true)
	analyze_market(w)


static func _unwind(w: LTWorld, b: Dictionary, c: Dictionary) -> void:
	# return every cent to where it came from, then drop the record
	var acct: String = w.acct_b(b)
	for d in LTFinance.debts_of(w, "b", int(b["id"])):
		w.ledger.pay(acct, LTFinance.creditor_acct(w, d), int(d["balance"]), "unwind")
		d["status"] = "paid"
		d["balance"] = 0
	for d in LTFinance.debts_of(w, "p", int(c["id"])):
		if str(d["type"]) == "family_loan" and int(d["opened_day"]) == w.day:
			w.ledger.pay(acct, LTFinance.creditor_acct(w, d), int(d["balance"]), "unwind")
			d["status"] = "paid"
			d["balance"] = 0
	var grant: int = int(b.get("grant_received", 0))
	if grant > 0:
		w.ledger.pay(acct, "city", grant, "unwind")
		w.city["grants_paid"] = int(w.city.get("grants_paid", 0)) - grant
	w.ledger.pay(acct, w.acct_p(c), w.biz_cash(b), "unwind")
	b["status"] = "never_opened"
	b["closed_day"] = w.day


static func _new_business(w: LTWorld, btype: String, c: Dictionary, lot_id: int, legal: String) -> Dictionary:
	var cfg: Dictionary = tcfg(btype)
	var sfx: Array = SUFFIXES.get(btype, LTServices.SUFFIXES.get(btype, ["Company"]))
	var name: String = "%s %s" % [c["last_name"], sfx[w.rng.randi_range(0, sfx.size() - 1)]]
	if str(sfx[0]) == "and Sons Building":
		name = "%s and Sons Building" % c["last_name"]
	for other in w.businesses:
		if str(other["name"]) == name:
			name = "%s's %s" % [c["first_name"], str(cfg["display"])]
	var t: Dictionary = c["traits"]
	var b: Dictionary = {
		"id": w.businesses.size(), "type": btype, "name": name, "owners": [int(c["id"])], "legal_form": legal,
		"lot": lot_id, "status": "open", "opened_day": w.day, "closed_day": -1, "close_reason": "", "start_reason": "",
		"stock": 0.0, "produce": 0.0, "pending": [], "price_level": 1.04 + float(t["greed"] - 50) / 400.0,
		"wage": maxi(int(cfg["wage"]), LTCivic.min_daily_wage(w)), "staff": [], "target_staff": int(cfg["staff"]),
		"condition": 85.0, "cleanliness": 80.0, "reputation": 55.0, "equipment": 1.0,
		"customers_today": 0, "sales_today": 0, "month_revenue": 0, "month_costs": 0, "month_profit_hist": [],
		"customers_hist": [], "history": [], "loss_months": 0, "incentives": {}, "tax_break_until": -1,
		"free_lot": false, "supplier": "Valley Wholesale", "stockout_days": 0, "unlicensed": false,
		"crew_quality": 0.5, "workload": 0, "contract_revenue": 0, "experience_avg": 60.0, "short_pay_days": 0,
		"lifetime_revenue": 0, "jobs_done": 0, "overruns": 0, "defects": 0,
	}
	w.businesses.append(b)
	w.ledger.open(w.acct_b(b))
	return b


static func create_landlord(w: LTWorld, owner: Dictionary, l: Dictionary) -> void:
	var b: Dictionary = _new_business(w, "landlord", owner, int(l["id"]), "llc" if float(owner["skills"]["finance"]) > 45.0 else "sole")
	b["name"] = "%s Rentals" % owner["last_name"]
	b["opened_day"] = -w.rng.randi_range(2, 15) * 365
	b["reputation"] = 50.0 + float(owner["traits"]["kindness"] - 50) * 0.4
	l["owner_kind"] = "business"
	l["owner_id"] = int(b["id"])
	l["name"] = str(b["name"])
	owner["owns"].append(int(b["id"]))
	var val: int = int(l["value"])
	var bal: int = int(float(val) * w.rng.randf_range(0.25, 0.6))
	var d: Dictionary = LTFinance.new_debt(w, "b", int(b["id"]), "bank", -1, "commercial_mortgage", bal, 0.065, 240, "house", int(l["id"]), [])
	d["original"] = int(float(val) * 0.7)
	if str(b["legal_form"]) == "llc":
		d["guarantor"] = int(owner["id"])
		w.debt_index_dirty = true
	w.ledger.pay("outside", w.acct_b(b), LTMoney.dollars(w.rng.randf_range(4000.0, 15000.0)), "starting_savings")
	b["start_reason"] = "Bought the %s years ago as an investment. Rents %d units." % [l["name"], l["units"].size()]
	w.log_biz(b, "Owned by %s. %s" % [w.full_name(owner), b["start_reason"]])
	w.log_sim(owner, "Owns %s, an apartment building on %s, with a commercial mortgage of %s." % [b["name"], LTGeography.lot_label(w, int(l["id"])), LTMoney.fmt(bal)], true)


static func _local_builder(w: LTWorld, exclude: Dictionary) -> Dictionary:
	for b in w.open_businesses("construction"):
		if int(b["id"]) != int(exclude.get("id", -1)) and b["staff"].size() > 0:
			return b
	return {}


# ================================================================ daily operations

static func daily(w: LTWorld) -> void:
	for b in w.businesses:
		if str(b["status"]) != "open":
			continue
		b["customers_avg"] = lerpf(float(b.get("customers_avg", 0.0)), float(b["customers_today"]), 0.05)
		if b.has("bplan") and int(b["sales_today"]) > 0:
			# a drive-through or a summer patio brings in people passing through
			var extra: int = int(float(b["sales_today"]) * (LTBuildings.revenue_factor(w, b["bplan"]) - 1.0))
			if extra > 0:
				w.ledger.pay("outside", w.acct_b(b), extra, "sales")
				b["month_revenue"] = int(b["month_revenue"]) + extra
		b["customers_today"] = 0
		b["sales_today"] = 0
		_receive_deliveries(w, b)
		match str(b["type"]):
			"farm":
				_farm_day(w, b)
	_household_shopping(w)
	_cafe_visits(w)
	LTServices.daily(w)
	for b in w.businesses:
		if str(b["status"]) != "open":
			continue
		_end_of_day(w, b)
	if LTCalendar.weekday(w.day) == "Friday":
		_payday(w)
	if LTCalendar.is_month_start(w.day):
		for b in w.businesses:
			if str(b["status"]) == "open":
				_month_close(w, b)


static func _receive_deliveries(w: LTWorld, b: Dictionary) -> void:
	var keep: Array = []
	for p in b["pending"]:
		if int(p["day"]) <= w.day:
			b["stock"] = float(b["stock"]) + float(p["units"])
		else:
			keep.append(p)
	b["pending"] = keep


## Restock decisions. Local farm produce first if one exists, imports fill the rest.
static func order_stock(w: LTWorld, b: Dictionary, opening: bool = false) -> void:
	var btype: String = str(b["type"])
	if not ["grocery", "cafe", "general_store"].has(btype):
		return
	var m: Dictionary = w.market
	var daily_units: float = 0.0
	var unit_cost: int = IMPORT_UNIT_COST
	match btype:
		"grocery":
			daily_units = float(m.get("food_units_day", 50.0)) * 0.8 / float(maxi(1, int(m.get("grocery_count", 1))))
		"cafe":
			daily_units = float(m.get("cafe_visits_day", 10.0))
			unit_cost = MEAL_COST
		"general_store":
			daily_units = float(m.get("goods_week", 20.0)) / 7.0 * 0.7
			unit_cost = GOODS_COST
	var owner: Dictionary = w.cit(int(b["owners"][0]))
	var mgmt: float = float(owner["skills"]["management"]) if not owner.is_empty() else 40.0
	# poor managers misjudge: they over or under order
	var judgment: float = 1.0 + w.rng.randf_range(-0.4, 0.4) * (1.0 - mgmt / 100.0)
	var target: float = daily_units * 4.0 * judgment
	var on_hand: float = float(b["stock"])
	for p in b["pending"]:
		on_hand += float(p["units"])
	var want: float = target - on_hand
	if want < daily_units * 1.5 and not opening:
		return
	var acct: String = w.acct_b(b)
	# local first
	if btype == "grocery" or btype == "cafe":
		var local_units: float = want * (0.35 if btype == "grocery" else 0.5)
		for f in w.open_businesses("farm"):
			if local_units <= 0.5:
				break
			var take: float = minf(local_units, float(f["produce"]))
			var price: int = PRODUCE_UNIT_PRICE if btype == "grocery" else int(PRODUCE_UNIT_PRICE * 1.1)
			var afford: float = float(w.biz_cash(b)) / float(price)
			take = floorf(minf(take, afford))
			if take >= 1.0:
				var cost: int = int(take) * price
				w.ledger.pay(acct, w.acct_b(f), cost, "local_produce")
				f["produce"] = float(f["produce"]) - take
				f["month_revenue"] = int(f["month_revenue"]) + cost
				f["lifetime_revenue"] = int(f["lifetime_revenue"]) + cost
				f["sales_today"] = int(f["sales_today"]) + cost
				b["month_costs"] = int(b["month_costs"]) + cost
				b["stock"] = float(b["stock"]) + take
				b["supplier"] = "%s and Valley Wholesale" % f["name"]
				want -= take
				local_units -= take
	if btype == "grocery" and want > 0.5:
		var bread: float = LTServices.grocery_buys_bread(w, b, want * 0.15)
		b["stock"] = float(b["stock"]) + bread
		want -= bread
	if btype == "general_store" and want > 0.5:
		var goods: float = LTServices.store_buys_goods(w, b, want)
		b["stock"] = float(b["stock"]) + goods
		want -= goods
	if want <= 0.5:
		return
	var reserve: int = maxi(0, w.biz_cash(b) - LTMoney.dollars(600.0))
	var units: float = floorf(minf(want, float(reserve - IMPORT_DELIVERY_FEE) / float(unit_cost)))
	if units < 1.0:
		if not opening:
			w.log_biz(b, "Could not afford a full stock order from Valley Wholesale.")
		return
	var cost2: int = int(units) * unit_cost
	if LTRegion.shortage(w, btype):
		units = floorf(units * 0.4)
		cost2 = int(units) * unit_cost
		w.log_biz(b, "Valley Wholesale could only fill part of the order. There is a shortage in the region.")
	w.ledger.pay(acct, "outside", cost2, "imports")
	b["month_costs"] = int(b["month_costs"]) + cost2
	LTServices.pay_freight(w, b)
	var delay: int = LTServices.delivery_days(w, b, 2 if w.weather != "Snow" and w.weather != "Storm" else 4)
	if opening:
		b["stock"] = float(b["stock"]) + units
	else:
		b["pending"].append({"day": w.day + delay, "units": units, "source": "Valley Wholesale"})


static func _farm_day(w: LTWorld, b: Dictionary) -> void:
	var season: String = LTCalendar.season(w.day)
	var crew: float = 1.0
	for sid in b["staff"]:
		var s: Dictionary = w.cit(int(sid))
		if w.is_present(s) and int(s["sick_days"]) == 0:
			crew += float(s["skills"]["farming"]) / 60.0
	var owner: Dictionary = w.cit(int(b["owners"][0]))
	if not owner.is_empty():
		crew += float(owner["skills"]["farming"]) / 50.0
	var growth: float = 0.0
	match season:
		"Spring":
			growth = 6.0
		"Summer":
			growth = 22.0
		"Fall":
			growth = 26.0
		"Winter":
			growth = 1.5
	if w.weather == "Storm":
		growth *= 0.3
	elif w.weather == "Rain" and season == "Summer":
		growth *= 1.2
	var seed_cost: int = int(growth * 70.0)
	var paid: int = w.ledger.pay(w.acct_b(b), "outside", seed_cost, "farm_inputs")
	b["month_costs"] = int(b["month_costs"]) + paid
	if paid < seed_cost:
		growth *= float(paid) / float(maxi(1, seed_cost))
	b["produce"] = minf(float(b["produce"]) + growth * crew * float(b["equipment"]), 3000.0)
	# spoilage and surplus sold to the outside co-op
	b["produce"] = float(b["produce"]) * 0.985
	var keep_for_town: float = float(w.market.get("produce_demand_day", 0.0)) * 6.0
	var surplus: float = float(b["produce"]) - keep_for_town
	if surplus > 40.0 and LTCalendar.weekday(w.day) == "Wednesday":
		var sold: int = int(surplus * 0.8)
		var rev: int = sold * PRODUCE_EXPORT_PRICE
		w.ledger.pay("outside", w.acct_b(b), rev, "exports")
		b["produce"] = float(b["produce"]) - float(sold)
		b["month_revenue"] = int(b["month_revenue"]) + rev
		b["lifetime_revenue"] = int(b["lifetime_revenue"]) + rev


static func _service_experience(w: LTWorld, b: Dictionary, customers: int) -> float:
	var staff_n: float = 0.0
	var skill: float = 0.0
	var mood: float = 0.0
	var owner: Dictionary = w.cit(int(b["owners"][0]))
	var cfg: Dictionary = tcfg(str(b["type"]))
	var people: Array = []
	if w.is_present(owner) and int(owner["sick_days"]) == 0:
		people.append(owner)
	for sid in b["staff"]:
		var s: Dictionary = w.cit(int(sid))
		if w.is_present(s) and int(s["sick_days"]) == 0:
			people.append(s)
	for p in people:
		staff_n += 1.0
		skill += float(p["skills"][str(cfg["skill"])])
		mood += LTPeople.happiness(p)
	if staff_n == 0.0:
		return 10.0
	skill /= staff_n
	mood /= staff_n
	var capacity: float = staff_n * 45.0
	if b.has("bplan"):
		var bcap: float = LTBuildings.capacity(b["bplan"])
		if bcap > 0.0:
			capacity = minf(capacity, bcap)
	var wait_penalty: float = clampf((float(customers) - capacity) / capacity, 0.0, 1.0) * 35.0
	var stock_ok: float = 1.0 if float(b["stock"]) > 5.0 else 0.4
	var exp: float = skill * 0.3 + mood * 0.25 + float(b["cleanliness"]) * 0.2 + float(b["condition"]) * 0.1 + 15.0 * stock_ok - wait_penalty
	return clampf(exp, 0.0, 100.0)


static func _household_shopping(w: LTWorld) -> void:
	var groceries: Array = w.open_businesses("grocery")
	var stores: Array = w.open_businesses("general_store")
	var tax: float = LTCivic.sales_tax_rate(w)
	for h in w.households:
		var ms: Array = w.household_members(h)
		if ms.is_empty():
			continue
		var adults: Array = w.household_adults(h)
		if adults.is_empty():
			continue
		var need_units: float = float(ms.size())
		if float(h["pantry"]) >= need_units * 1.5:
			continue
		var want: float = need_units * 7.0 - float(h["pantry"])
		var home: int = int(h["lot"]) if int(h["lot"]) >= 0 else 0
		var shopper: Dictionary = adults[0]
		var t: Dictionary = shopper["traits"]
		# option scores, in dollars of value: cheaper, closer, nicer, habitual wins
		var options: Array = []
		var out_min: float = w.minutes_to_outside(home) * 2.0
		var out_cost: float = want * float(FOOD_UNIT_PRICE) / 100.0 + float(OUTSIDE_TRIP_FUEL) / 100.0
		var out_score: float = -out_cost - out_min * 0.22 - (0.0 if bool(h["car"]) else 25.0)
		if str(h["last_grocery"]) == "outside":
			out_score += 4.0
		options.append({"kind": "outside", "score": out_score})
		for g in groceries:
			var mins: float = w.travel_minutes(home, int(g["lot"])) * 2.0
			var price: float = float(FOOD_UNIT_PRICE) * float(g["price_level"]) * (1.0 + tax)
			var s: float = -want * price / 100.0 - mins * 0.22 + (float(g["reputation"]) - 50.0) * 0.25
			if float(g["stock"]) < want * 0.5:
				s -= 8.0
			s += w.memory_weight(shopper, "good_shop", int(g["id"])) * 0.4 + w.memory_weight(shopper, "bad_shop", int(g["id"])) * 0.6
			if int(h["shop_habit"]) == int(g["id"]):
				s += 5.0
			options.append({"kind": "local", "biz": g, "score": s})
		var choice: Dictionary = LTPeople.choose(w, shopper, options)
		if str(choice["kind"]) == "local":
			var g2: Dictionary = choice["biz"]
			var units: float = minf(want, float(g2["stock"]))
			var unit_price: int = int(float(FOOD_UNIT_PRICE) * float(g2["price_level"]))
			var afford: float = float(w.household_cash(h)) / (float(unit_price) * (1.0 + tax))
			if afford < units:
				var short: int = int((units - afford) * float(unit_price) * (1.0 + tax))
				LTFinance.card_draw(w, shopper, short, "groceries")
				afford = float(w.household_cash(h)) / (float(unit_price) * (1.0 + tax))
			units = floorf(minf(units, afford))
			if units >= 1.0:
				var net: int = int(units) * unit_price
				var tx: int = int(float(net) * tax)
				w.household_pay(h, w.acct_b(g2), net, "retail_sales")
				w.household_pay(h, "city", tx, "sales_tax")
				w.city["sales_tax_month"] = int(w.city.get("sales_tax_month", 0)) + tx
				g2["stock"] = float(g2["stock"]) - units
				g2["customers_today"] = int(g2["customers_today"]) + 1
				g2["sales_today"] = int(g2["sales_today"]) + net
				g2["month_revenue"] = int(g2["month_revenue"]) + net
				g2["lifetime_revenue"] = int(g2["lifetime_revenue"]) + net
				h["pantry"] = float(h["pantry"]) + units
				h["last_grocery"] = str(g2["id"])
				h["shop_habit"] = int(g2["id"])
				var exp: float = _service_experience(w, g2, int(g2["customers_today"]) * 3)
				g2["experience_avg"] = float(g2["experience_avg"]) * 0.97 + exp * 0.03
				if exp > 70.0:
					w.remember(shopper, "good_shop", int(g2["id"]), 3.0)
				elif exp < 40.0:
					w.remember(shopper, "bad_shop", int(g2["id"]), -5.0)
					w.log_sim(shopper, "Had a bad trip to %s: long wait or empty shelves." % g2["name"], false)
				want -= units
			if want > need_units:
				# empty shelves: drive to the next town for the rest
				g2["stockout_days"] = int(g2["stockout_days"]) + 1
				_buy_outside(w, h, shopper, want)
		else:
			_buy_outside(w, h, shopper, want)
		# weekly household goods
		if (int(h["id"]) + w.day) % 7 == 0:
			_buy_goods(w, h, shopper, stores, tax)


static func _buy_outside(w: LTWorld, h: Dictionary, shopper: Dictionary, want: float) -> void:
	var cost_unit: int = FOOD_UNIT_PRICE
	var cash: int = w.household_cash(h)
	if cash < int(want * float(cost_unit)) + OUTSIDE_TRIP_FUEL:
		LTFinance.card_draw(w, shopper, int(want * float(cost_unit)) + OUTSIDE_TRIP_FUEL - cash, "groceries")
		cash = w.household_cash(h)
	var units: float = floorf(minf(want, float(cash - OUTSIDE_TRIP_FUEL) / float(cost_unit)))
	if units < 1.0:
		if int(shopper["id"]) % 3 == w.day % 3:
			w.log_sim(shopper, "Could not afford groceries this week. Went to the food pantry at the church.", true)
		LTCivic.food_help(w, h)
		# the church food pantry, funded by outside donations, keeps people from starving
		if float(h["pantry"]) < float(w.household_members(h).size()):
			var gift: float = float(w.household_members(h).size()) * 2.0
			h["pantry"] = float(h["pantry"]) + gift
			h["charity_days"] = int(h.get("charity_days", 0)) + 1
		return
	w.household_pay(h, "outside", int(units) * cost_unit + OUTSIDE_TRIP_FUEL, "outside_shopping")
	h["pantry"] = float(h["pantry"]) + units
	h["last_grocery"] = "outside"
	for m in w.household_adults(h):
		m["needs"]["fun"] = float(m["needs"]["fun"]) - 3.0
		break


static func _buy_goods(w: LTWorld, h: Dictionary, shopper: Dictionary, stores: Array, tax: float) -> void:
	var home: int = maxi(0, int(h["lot"]))
	var best: Dictionary = {}
	var best_s: float = -float(GOODS_PRICE) / 100.0 - w.minutes_to_outside(home) * 0.3
	for s in stores:
		if float(s["stock"]) < 1.0:
			continue
		var sc: float = -float(GOODS_PRICE) * float(s["price_level"]) / 100.0 - w.travel_minutes(home, int(s["lot"])) * 0.3 + (float(s["reputation"]) - 50.0) * 0.1
		if sc > best_s:
			best_s = sc
			best = s
	if best.is_empty():
		w.household_pay(h, "outside", GOODS_PRICE, "outside_shopping")
		return
	var price: int = int(float(GOODS_PRICE) * float(best["price_level"]))
	var paid: int = w.household_pay(h, w.acct_b(best), price, "retail_sales")
	var tx: int = w.household_pay(h, "city", int(float(paid) * tax), "sales_tax")
	w.city["sales_tax_month"] = int(w.city.get("sales_tax_month", 0)) + tx
	best["stock"] = float(best["stock"]) - 1.0
	best["customers_today"] = int(best["customers_today"]) + 1
	best["sales_today"] = int(best["sales_today"]) + paid
	best["month_revenue"] = int(best["month_revenue"]) + paid
	best["lifetime_revenue"] = int(best["lifetime_revenue"]) + paid


static func _cafe_visits(w: LTWorld) -> void:
	var cafes: Array = w.open_businesses("cafe")
	if cafes.is_empty():
		return
	var tax: float = LTCivic.sales_tax_rate(w)
	for c in w.citizens:
		if not w.is_present(c) or w.age_years(c) < 16:
			continue
		var n: Dictionary = c["needs"]
		var want: float = (100.0 - float(n["fun"])) * 0.004 + (100.0 - float(n["social"])) * 0.003 + float(c["traits"]["sociability"]) * 0.001
		var money_ok: float = clampf(float(w.cash(c)) / float(LTMoney.dollars(400.0)), 0.0, 1.0)
		if w.rng.randf() > want * money_ok * 0.5:
			continue
		var cafe: Dictionary = cafes[w.rng.randi_range(0, cafes.size() - 1)]
		if float(cafe["stock"]) < 1.0:
			continue
		var price: int = int(float(MEAL_PRICE) * float(cafe["price_level"]))
		if w.ledger.pay_full(w.acct_p(c), w.acct_b(cafe), price, "retail_sales"):
			var tx: int = w.ledger.pay(w.acct_p(c), "city", int(float(price) * tax), "sales_tax")
			w.city["sales_tax_month"] = int(w.city.get("sales_tax_month", 0)) + tx
			cafe["stock"] = float(cafe["stock"]) - 1.0
			cafe["customers_today"] = int(cafe["customers_today"]) + 1
			cafe["sales_today"] = int(cafe["sales_today"]) + price
			cafe["month_revenue"] = int(cafe["month_revenue"]) + price
			cafe["lifetime_revenue"] = int(cafe["lifetime_revenue"]) + price
			n["fun"] = float(n["fun"]) + 12.0
			n["social"] = float(n["social"]) + 10.0
			n["hunger"] = float(n["hunger"]) + 8.0
			var exp: float = _service_experience(w, cafe, int(cafe["customers_today"]) * 2)
			cafe["experience_avg"] = float(cafe["experience_avg"]) * 0.97 + exp * 0.03
			# people meet each other at the cafe
			for sid in cafe["staff"]:
				var s: Dictionary = w.cit(int(sid))
				if w.is_present(s) and w.rng.randf() < 0.2:
					LTPeople.relate_event(w, c, s, "acquaintance", 1.0, 2.0)


static func _end_of_day(w: LTWorld, b: Dictionary) -> void:
	var btype: String = str(b["type"])
	if btype == "landlord":
		return
	if ["grocery", "cafe", "general_store"].has(btype):
		var spoil: float = 0.02 if btype == "grocery" else (0.08 if btype == "cafe" else 0.0)
		b["stock"] = float(b["stock"]) * (1.0 - spoil)
		order_stock(w, b)
		# price adjustments, the owner's own call
		var owner: Dictionary = w.cit(int(b["owners"][0]))
		if not owner.is_empty() and int(owner["id"]) % 7 == w.day % 7:
			_adjust_prices(w, b, owner)
		var rep: float = float(b["reputation"])
		rep += (float(b["experience_avg"]) - 55.0) * 0.01
		if float(b["stock"]) < 3.0:
			rep -= 0.3
		if float(b["price_level"]) > 1.25:
			rep -= 0.15
		b["reputation"] = clampf(rep, 0.0, 100.0)
	b["cleanliness"] = clampf(float(b["cleanliness"]) - 0.4 + float(b["staff"].size()) * 0.25, 0.0, 100.0)
	b["condition"] = maxf(0.0, float(b["condition"]) - 0.02)
	_hire_if_needed(w, b)


static func _adjust_prices(w: LTWorld, b: Dictionary, owner: Dictionary) -> void:
	var t: Dictionary = owner["traits"]
	var p: float = float(b["price_level"])
	var rivals: int = w.open_businesses(str(b["type"])).size() - 1
	var target: float = 1.04 + float(t["greed"] - 50) / 300.0
	if rivals == 0 and int(t["greed"]) > 65 and int(t["honesty"]) < 40:
		target += 0.12
	if int(b["loss_months"]) > 0:
		target += 0.04
	if float(b["stock"]) > float(w.market.get("food_units_day", 50.0)) * 6.0:
		target -= 0.06
	var old: float = p
	p += clampf(target - p, -0.03, 0.03)
	b["price_level"] = clampf(p, 0.85, 1.45)
	if absf(p - old) > 0.025:
		w.log_biz(b, "%s %s prices to %d%% of the outside supermarket. Reason: %s." % [owner["first_name"], "raised" if p > old else "cut", int(p * 100.0), "no competition and wants more margin" if p > old and rivals == 0 else ("losing money" if p > old else "too much stock sitting on the shelves")])


static func _hire_if_needed(w: LTWorld, b: Dictionary) -> void:
	if b["staff"].size() >= int(b["target_staff"]):
		return
	if w.biz_cash(b) < int(b["wage"]) * 10:
		return
	var cfg: Dictionary = tcfg(str(b["type"]))
	var best: Dictionary = {}
	var best_s: float = 25.0
	for c in _seekers(w):
		if not w.is_present(c) or str(c["job"]["kind"]) != "none":
			continue
		var s: float = applicant_score(w, b, c)
		if s > best_s:
			best_s = s
			best = c
	if best.is_empty():
		return
	var opening: Dictionary = {"employer_kind": "business", "id": int(b["id"]), "name": b["name"], "title": cfg["title"], "wage": int(b["wage"]), "skill": cfg["skill"]}
	hire(w, best, opening, "Hired at %s as a %s. Reason: needed work, and %s picked them from the people looking." % [b["name"], cfg["title"], w.cit(int(b["owners"][0])).get("first_name", "the owner")])


static func _seekers(w: LTWorld) -> Array:
	if int(w.market.get("seekers_day", -1)) != w.day:
		var out: Array = []
		for c in w.citizens:
			if w.is_present(c) and w.age_years(c) >= 16 and not bool(c["retired"]) and str(c["job"]["kind"]) == "none" and not LTJustice.in_jail(w, c):
				out.append(c)
		w.market["seekers"] = out
		w.market["seekers_day"] = w.day
	return w.market["seekers"]


static func applicant_score(w: LTWorld, b: Dictionary, c: Dictionary) -> float:
	var cfg: Dictionary = tcfg(str(b["type"]))
	var s: float = float(c["skills"][str(cfg["skill"])]) * 0.5 + float(c["traits"]["discipline"]) * 0.2 + float(c["education"]) * 0.1
	s -= float(LTJustice.record_count(c)) * 25.0
	if LTJustice.in_jail(w, c) or (bool(c.get("disability", false)) and LTHealth.RISKY_JOBS.has(str(cfg["title"]))):
		s -= 100.0
	var owner: Dictionary = w.cit(int(b["owners"][0]))
	if not owner.is_empty() and owner["rel"].has(int(c["id"])):
		s += float(owner["rel"][int(c["id"])]["trust"] - 50.0) * 0.3
	var hl: int = int(w.hh(int(c["household"]))["lot"])
	if hl >= 0:
		s -= w.travel_minutes(hl, int(b["lot"])) * 0.3
	if w.age_years(c) < 18:
		s -= 8.0
	return s


static func best_local_opening(w: LTWorld, c: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_v: float = -1e9
	for b in w.businesses:
		if str(b["status"]) != "open" or b["staff"].size() >= int(b["target_staff"]) or b["owners"].has(int(c["id"])):
			continue
		var cfg: Dictionary = tcfg(str(b["type"]))
		var v: float = float(b["wage"]) / 100.0 + float(c["skills"][str(cfg["skill"])]) * 0.3 + (float(b["reputation"]) - 50.0) * 0.2
		if v > best_v:
			best_v = v
			best = {"employer_kind": "business", "id": int(b["id"]), "name": b["name"], "title": cfg["title"], "wage": int(b["wage"]), "skill": cfg["skill"]}
	var city_job: Dictionary = LTCivic.best_city_opening(w, c)
	if not city_job.is_empty() and float(city_job["wage"]) / 100.0 + 5.0 > best_v:
		best = city_job
	return best


static func would_hire(w: LTWorld, opening: Dictionary, c: Dictionary) -> bool:
	if str(opening["employer_kind"]) == "city":
		return LTCivic.city_would_hire(w, opening, c)
	var b: Dictionary = w.biz(int(opening["id"]))
	return applicant_score(w, b, c) > 20.0


static func hire(w: LTWorld, c: Dictionary, opening: Dictionary, reason: String) -> void:
	if str(opening["employer_kind"]) == "city":
		LTCivic.hire_city(w, c, opening, reason)
		return
	var b: Dictionary = w.biz(int(opening["id"]))
	if b.is_empty() or b["staff"].size() >= int(b["target_staff"]):
		return
	if str(c["job"]["kind"]) != "none":
		leave_job(w, c, "took a job at %s" % b["name"])
	b["staff"].append(int(c["id"]))
	var wage: int = maxi(int(b["wage"]), LTCivic.min_daily_wage(w))
	LTPeople.set_job(w, c, "business", int(b["id"]), str(opening["title"]), wage, str(opening["skill"]))
	w.counters["hires"] = int(w.counters["hires"]) + 1
	w.log_sim(c, reason, true)
	w.log_biz(b, "Hired %s as a %s at %s a day." % [w.full_name(c), opening["title"], LTMoney.fmt(wage)])
	var owner: Dictionary = w.cit(int(b["owners"][0]))
	if not owner.is_empty():
		LTPeople.relate_event(w, c, owner, "employer", 5.0, 2.0)
		LTPeople.relate_event(w, owner, c, "employee", 5.0, 2.0)
	w.remember(c, "hired", int(b["id"]), 10.0)


static func leave_job(w: LTWorld, c: Dictionary, why: String) -> void:
	var job: Dictionary = c["job"]
	match str(job["kind"]):
		"business":
			var b: Dictionary = w.biz(int(job["employer"]))
			if not b.is_empty():
				b["staff"].erase(int(c["id"]))
				w.log_biz(b, "%s left. Reason: %s." % [w.full_name(c), why])
		"city":
			LTCivic.city_job_left(w, c)
	if why != "died" and why != "moved away" and str(job["kind"]) != "none":
		w.log_sim(c, "Left the job as %s. Reason: %s." % [job["title"], why], true)
		w.counters["quits"] = int(w.counters["quits"]) + 1
	LTPeople.clear_job(w, c)


static func lay_off(w: LTWorld, b: Dictionary, c: Dictionary, why: String) -> void:
	b["staff"].erase(int(c["id"]))
	LTPeople.clear_job(w, c)
	w.counters["layoffs"] = int(w.counters["layoffs"]) + 1
	w.remember(c, "fired", int(b["id"]), -25.0)
	w.log_sim(c, "Laid off from %s. Reason given: %s." % [b["name"], why], true)
	w.log_biz(b, "Laid off %s. Reason: %s." % [w.full_name(c), why])
	var owner: Dictionary = w.cit(int(b["owners"][0]))
	if not owner.is_empty():
		LTPeople.relate_event(w, c, owner, "employer", -20.0, -15.0)


static func _payday(w: LTWorld) -> void:
	# outside employers pay outside jobs, businesses pay staff, the city pays its staff
	for c in w.citizens:
		if not w.is_present(c):
			continue
		var job: Dictionary = c["job"]
		if str(job["kind"]) == "outside":
			var days: int = 5
			var gross: int = int(job["daily_wage"]) * days
			var income_tax: int = int(float(gross) * LTCivic.income_tax_rate(w))
			w.ledger.pay("outside", w.acct_p(c), gross, "outside_wages")
			w.ledger.pay(w.acct_p(c), "city", income_tax, "income_tax")
	for b in w.businesses:
		if str(b["status"]) != "open":
			continue
		var acct: String = w.acct_b(b)
		for sid in b["staff"].duplicate():
			var s: Dictionary = w.cit(int(sid))
			if not w.is_present(s):
				b["staff"].erase(sid)
				continue
			var due: int = int(s["job"]["daily_wage"]) * 5
			var paid: int = w.ledger.pay(acct, w.acct_p(s), due, "local_wages")
			b["month_costs"] = int(b["month_costs"]) + paid
			var it: int = w.ledger.pay(w.acct_p(s), "city", int(float(paid) * LTCivic.income_tax_rate(w)), "income_tax")
			if paid < due:
				b["short_pay_days"] = int(b["short_pay_days"]) + 1
				w.log_sim(s, "Paycheck from %s came up short: %s of %s." % [b["name"], LTMoney.fmt(paid), LTMoney.fmt(due)], true)
				LTPeople.relate_event(w, s, w.cit(int(b["owners"][0])), "employer", -10.0, -5.0)
				w.remember(s, "cheated", int(b["id"]), -15.0)
				if float(s["traits"]["discipline"]) < 70.0 or int(b["short_pay_days"]) > 2:
					leave_job(w, s, "the paychecks stopped coming in full")
		# owner draw: what is left over above a cushion
		var cushion: int = LTMoney.dollars(3000.0) + int(b["wage"]) * 5 * b["staff"].size()
		var extra: int = w.biz_cash(b) - cushion
		var owner: Dictionary = w.cit(int(b["owners"][0]))
		if extra > 0 and w.is_present(owner):
			var t: Dictionary = owner["traits"]
			var share: float = 0.35 + float(t["greed"]) / 300.0 - float(t["discipline"]) / 400.0
			var draw: int = int(float(extra) * clampf(share, 0.15, 0.7))
			var inv_cut: int = int(float(draw) * float(b.get("investor_share", 0.0)))
			if inv_cut > 0:
				w.ledger.pay(acct, "outside", inv_cut, "investor_dividends")
			var partners: Array = b["owners"]
			var each: int = (draw - inv_cut) / maxi(1, partners.size())
			for pid in partners:
				var po: Dictionary = w.cit(int(pid))
				if w.is_present(po):
					w.ledger.pay(acct, w.acct_p(po), each, "owner_draws")
		elif w.is_present(owner) and str(b["type"]) != "landlord" and w.cash(owner) < LTMoney.dollars(150.0):
			# a broke owner still has to eat: takes a small draw even when the business cannot spare it
			w.ledger.pay(acct, w.acct_p(owner), LTMoney.dollars(200.0), "owner_draws")
	LTCivic.city_payday(w)


static func _month_close(w: LTWorld, b: Dictionary) -> void:
	var acct: String = w.acct_b(b)
	var btype: String = str(b["type"])
	var owner: Dictionary = w.cit(int(b["owners"][0]))
	# fixed monthly costs
	if btype != "landlord":
		if not bool(b["free_lot"]):
			var rent: int = LTCivic.lot_rent(w, int(b["lot"])) * (3 if bool(b.get("building_lease", false)) else 1)
			var pr: int = w.ledger.pay(acct, "city", rent, "lot_leases")
			b["month_costs"] = int(b["month_costs"]) + pr
		var util: int = LTMoney.dollars(260.0 if btype != "farm" else 180.0)
		b["month_costs"] = int(b["month_costs"]) + w.ledger.pay(acct, "outside", util, "business_utilities")
	else:
		var l: Dictionary = w.lot(int(b["lot"]))
		var t: Dictionary = owner["traits"] if not owner.is_empty() else {"greed": 50, "kindness": 50}
		var upkeep_will: float = 1.0 - float(t["greed"]) / 150.0 + float(t["kindness"]) / 300.0
		var upkeep: int = int(float(LTMoney.dollars(120.0)) * float(l["units"].size()) * upkeep_will)
		var builder: Dictionary = _local_builder(w, {})
		var paid: int = 0
		if not builder.is_empty():
			paid = w.ledger.pay(acct, w.acct_b(builder), upkeep, "repairs_local")
			builder["month_revenue"] = int(builder["month_revenue"]) + paid
		else:
			paid = w.ledger.pay(acct, "outside", upkeep, "repairs_outside")
		b["month_costs"] = int(b["month_costs"]) + paid
		l["condition"] = clampf(float(l["condition"]) - 1.2 + float(paid) / float(maxi(1, LTMoney.dollars(120.0) * l["units"].size())) * 1.3, 0.0, 100.0)
	var profit: int = int(b["month_revenue"]) - int(b["month_costs"])
	if profit > 0 and w.day >= int(b["tax_break_until"]):
		var bt: int = w.ledger.pay(acct, "city", int(float(profit) * LTCivic.business_tax_rate(w)), "business_tax")
		profit -= bt
	b["month_profit_hist"].append(profit)
	if b["month_profit_hist"].size() > 36:
		b["month_profit_hist"].remove_at(0)
	b["customers_hist"].append(int(b["month_revenue"]))
	if b["customers_hist"].size() > 36:
		b["customers_hist"].remove_at(0)
	b["month_revenue"] = 0
	b["month_costs"] = 0
	if btype == "landlord":
		return
	if profit < 0:
		b["loss_months"] = int(b["loss_months"]) + 1
	else:
		b["loss_months"] = maxi(0, int(b["loss_months"]) - 1)
	if w.is_present(owner):
		_owner_monthly_decision(w, b, owner, profit)


static func _owner_monthly_decision(w: LTWorld, b: Dictionary, owner: Dictionary, profit: int) -> void:
	var t: Dictionary = owner["traits"]
	var cash: int = w.biz_cash(b)
	var losses: int = int(b["loss_months"])
	var age_days: int = w.day - int(b["opened_day"])
	# cut losses: discipline and honesty push to stop early, risk and pride keep going
	# owners ride out a bad season and close when the savings run low or after most
	# of a year of losses, not after two bad months
	var quit_score: float = float(losses) * 6.0 + (25.0 if cash < LTMoney.dollars(500.0) else 0.0) + float(t["discipline"]) * 0.15 - float(t["risk"]) * 0.2 - float(t["ambition"]) * 0.1
	if age_days < 180:
		quit_score -= 20.0
	if quit_score > 35.0:
		close_business(w, b, "%s decided to cut losses after %d losing months" % [owner["first_name"], losses])
		w.log_sim(owner, "Closed %s. Reason: %d months of losses and only %s left in the account." % [b["name"], losses, LTMoney.fmt(cash)], true)
		return
	if losses >= 2 and b["staff"].size() > 0:
		var worst: Dictionary = {}
		var worst_s: float = 1e9
		for sid in b["staff"]:
			var s: Dictionary = w.cit(int(sid))
			var sc: float = applicant_score(w, b, s)
			if sc < worst_s:
				worst_s = sc
				worst = s
		if not worst.is_empty():
			lay_off(w, b, worst, "the business lost money %d months running" % losses)
			b["target_staff"] = maxi(0, int(b["target_staff"]) - 1)
	elif profit > LTMoney.dollars(2500.0) and b["staff"].size() >= int(b["target_staff"]) and int(b["stockout_days"]) > 4:
		b["target_staff"] = int(b["target_staff"]) + 1
		w.log_biz(b, "%s decided to hire one more person. Reason: customers were waiting and shelves ran empty." % owner["first_name"])
	b["stockout_days"] = 0
	if profit < 0 and cash < LTMoney.dollars(1500.0) and int(t["risk"]) > 45 and w.day - int(owner["credit"].get("last_biz_loan_day", -999)) > 120:
		owner["credit"]["last_biz_loan_day"] = w.day
		var amt: int = LTMoney.dollars(5000.0)
		var dec: Dictionary = LTFinance.bank_decision(w, owner, "business_loan", amt, maxi(1, LTFinance.monthly_income(w, owner) + LTMoney.dollars(1500.0)))
		if bool(dec["ok"]):
			var d: Dictionary = LTFinance.new_debt(w, "b", int(b["id"]), "bank", -1, "business_loan", amt, float(dec["rate"]), 36, "", -1, [])
			if str(b["legal_form"]) == "llc":
				d["guarantor"] = int(owner["id"])
				w.debt_index_dirty = true
			LTFinance.fund_loan(w, d, w.acct_b(b), amt)
			w.bank["lent_12m"] = int(w.bank["lent_12m"]) + amt
			w.counters["loans_made"] = int(w.counters["loans_made"]) + 1
			w.log_sim(owner, "Borrowed %s more to keep %s going. Reason: sure it will turn around." % [LTMoney.fmt(amt), b["name"]], true)
			w.log_biz(b, "Took a %s working capital loan." % LTMoney.fmt(amt))
		else:
			w.log_sim(owner, "Asked for a loan to keep %s afloat and was refused: %s." % [b["name"], dec["reason"]], true)


## Wind down: stock sold off, staff laid off, creditors paid in order, owner left with the result.
static func close_business(w: LTWorld, b: Dictionary, reason: String) -> void:
	if str(b["status"]) != "open":
		return
	var acct: String = w.acct_b(b)
	var leftover_stock: float = float(b["stock"]) + float(b["produce"])
	if leftover_stock > 0.0:
		var unit: int = IMPORT_UNIT_COST if str(b["type"]) == "grocery" else 200
		w.ledger.pay("outside", acct, int(leftover_stock * float(unit) * 0.3), "liquidation_sales")
	b["stock"] = 0.0
	b["produce"] = 0.0
	b["pending"] = []
	for sid in b["staff"].duplicate():
		var s: Dictionary = w.cit(int(sid))
		if w.is_present(s):
			lay_off(w, b, s, "%s closed" % b["name"])
	b["staff"] = []
	# creditors in order: secured first, then unsecured
	var ds: Array = LTFinance.debts_of(w, "b", int(b["id"]))
	ds.sort_custom(func(x, y): return str(x["secured_by"]) != "" and str(y["secured_by"]) == "")
	var owner: Dictionary = w.cit(int(b["owners"][0]))
	var leftover_debt: int = 0
	for d in ds:
		var pay: int = w.ledger.pay(acct, LTFinance.creditor_acct(w, d), int(d["balance"]), "wind_down_payments")
		d["balance"] = int(d["balance"]) - pay
		if int(d["balance"]) <= 0:
			d["status"] = "paid"
			d["balance"] = 0
			LTFinance._dhist(w, d, "Paid in the wind down.")
			continue
		leftover_debt += int(d["balance"])
		if str(b["legal_form"]) == "sole" and not owner.is_empty():
			d["debtor_kind"] = "p"
			d["debtor_id"] = int(owner["id"])
			w.debt_index_dirty = true
			LTFinance._dhist(w, d, "The business closed. As a sole proprietor, %s owes the remaining %s personally." % [w.full_name(owner), LTMoney.fmt(int(d["balance"]))])
		elif int(d["guarantor"]) >= 0 and w.is_present(w.cit(int(d["guarantor"]))):
			var g: Dictionary = w.cit(int(d["guarantor"]))
			d["debtor_kind"] = "p"
			d["debtor_id"] = int(g["id"])
			w.debt_index_dirty = true
			LTFinance._dhist(w, d, "The LLC closed. %s signed a personal guarantee and now owes %s." % [w.full_name(g), LTMoney.fmt(int(d["balance"]))])
		elif bool(d.get("city_guarantee", false)):
			var cp: int = w.ledger.pay("city", LTFinance.creditor_acct(w, d), int(d["balance"]), "city_guarantee_payouts")
			LTFinance._dhist(w, d, "The city paid %s under its loan guarantee." % LTMoney.fmt(cp))
			w.chronicle_add("The city paid %s to %s under the loan guarantee it gave %s." % [LTMoney.fmt(cp), LTFinance.BANK_NAME, b["name"]], "city", true, [])
			d["balance"] = int(d["balance"]) - cp
			if int(d["balance"]) <= 0:
				d["status"] = "paid"
				d["balance"] = 0
			else:
				LTFinance._charge_off(w, d, [], "the LLC closed with no guarantee left")
		else:
			LTFinance._charge_off(w, d, [], "the LLC closed and nobody else owes it")
	# what is left goes to the owner
	if not owner.is_empty():
		w.ledger.pay(acct, w.acct_p(owner) if w.is_present(owner) else "outside", w.biz_cash(b), "wind_down_to_owner")
		owner["owns"].erase(int(b["id"]))
		if str(owner["job"]["kind"]) == "owner" and int(owner["job"]["employer"]) == int(b["id"]):
			LTPeople.clear_job(w, owner)
		w.remember(owner, "business_failed", int(b["id"]), -40.0)
		var personal_note: String = ""
		if leftover_debt > 0:
			personal_note = " %s of business debt is still owed%s." % [LTMoney.fmt(leftover_debt), " personally, since a sole proprietor and the business are one pocket" if str(b["legal_form"]) == "sole" else " by whoever guaranteed it"]
		w.log_sim(owner, "%s closed. Reason: %s.%s" % [b["name"], reason, personal_note], true)
	else:
		w.ledger.pay(acct, "outside", w.biz_cash(b), "wind_down_to_owner")
	b["status"] = "closed"
	b["closed_day"] = w.day
	b["close_reason"] = reason
	var l: Dictionary = w.lot(int(b["lot"]))
	if not bool(b.get("home_based", false)):
		l["use"] = "closed"
	w.counters["businesses_closed"] = int(w.counters["businesses_closed"]) + 1
	w.log_biz(b, "Closed. Reason: %s." % reason)
	w.chronicle_add("%s closed. Reason: %s." % [b["name"], reason], "business", true, b["owners"].duplicate())


static func heir_keeps_business(w: LTWorld, heir: Dictionary, b: Dictionary) -> bool:
	var cfg: Dictionary = tcfg(str(b["type"]))
	var s: float = float(heir["traits"]["ambition"]) * 0.3 + float(heir["skills"][str(cfg["skill"])]) * 0.4 + float(heir["traits"]["kindness"]) * 0.1
	if str(b["type"]) == "landlord":
		s += 25.0
	var profits: Array = b["month_profit_hist"]
	if not profits.is_empty() and int(profits[profits.size() - 1]) > 0:
		s += 15.0
	return s > 35.0 and w.age_years(heir) < 75


static func transfer_business(w: LTWorld, b: Dictionary, from: Dictionary, to: Dictionary) -> void:
	b["owners"].erase(int(from["id"]))
	b["owners"].insert(0, int(to["id"]))
	w.debt_index_dirty = true
	to["owns"].append(int(b["id"]))
	for d in LTFinance.debts_of(w, "b", int(b["id"])):
		if int(d["guarantor"]) == int(from["id"]):
			d["guarantor"] = -1
			w.debt_index_dirty = true
			LTFinance._dhist(w, d, "The guarantor died. The debt stays with the business.")
	if str(b["type"]) != "landlord" and str(to["job"]["kind"]) != "owner":
		if str(to["job"]["kind"]) != "none":
			leave_job(w, to, "took over the family business")
		LTPeople.set_job(w, to, "owner", int(b["id"]), "owner of " + str(b["name"]), 0, str(tcfg(str(b["type"]))["skill"]))
	w.log_biz(b, "Passed to %s after %s died. The business keeps its own debts." % [w.full_name(to), w.full_name(from)])
	w.log_sim(to, "Took over %s after %s died, along with the business debts that come with it." % [b["name"], from["first_name"]], true)
