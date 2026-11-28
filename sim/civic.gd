class_name LTCivic
extends RefCounted
## The city: laws, budget, services and city jobs, petitions, published needs,
## zoning, and the theft hook. A law changes numbers inside Sim and business
## scoring. It never sets an outcome directly.

const LAWS: Dictionary = {
	"min_wage": {"label": "Minimum wage (per hour)", "min": 725, "max": 2000, "step": 25, "money": true},
	"property_tax": {"label": "Property tax (yearly, share of value)", "min": 0.004, "max": 0.03, "step": 0.001, "pct": true},
	"sales_tax": {"label": "Sales tax", "min": 0.0, "max": 0.06, "step": 0.005, "pct": true},
	"income_tax": {"label": "City income tax", "min": 0.0, "max": 0.04, "step": 0.005, "pct": true},
	"business_tax": {"label": "Business profit tax", "min": 0.0, "max": 0.2, "step": 0.01, "pct": true},
	"school_funding": {"label": "School funding (1.0 is the state average)", "min": 0.5, "max": 2.0, "step": 0.1},
	"police_funding": {"label": "Police funding (1.0 is the county average)", "min": 0.5, "max": 2.0, "step": 0.1},
	"health_funding": {"label": "Health care support", "min": 0.0, "max": 2.0, "step": 0.1},
	"welfare": {"label": "Unemployment, food and shelter support", "min": 0.0, "max": 2.0, "step": 0.1},
	"fire_funding": {"label": "Fire protection (1.0 is the county average)", "min": 0.5, "max": 2.0, "step": 0.1},
	"license_fee": {"label": "Business license fees (1.0 is standard)", "min": 0.0, "max": 3.0, "step": 0.25},
	"building_code": {"label": "Building code (0 loose, 1 standard, 2 strict)", "min": 0.0, "max": 2.0, "step": 1.0},
	"health_code": {"label": "Health code inspections (0 none, 1 standard, 2 strict)", "min": 0.0, "max": 2.0, "step": 1.0},
	"pollution_rule": {"label": "Pollution rules (0 none, 1 strict)", "min": 0.0, "max": 1.0, "step": 0.25},
	"zoning_density": {"label": "Homes allowed per apartment lot", "min": 4, "max": 8, "step": 2},
	"rent_cap": {"label": "Most a landlord may raise rent each year", "min": 0.0, "max": 0.15, "step": 0.01, "pct": true},
	"late_fee_cap": {"label": "Most a lender may charge as a late fee", "min": 1000, "max": 3500, "step": 500, "money": true},
	"bus_service": {"label": "Bus to the county seat (0 none, 1 weekdays)", "min": 0.0, "max": 1.0, "step": 1.0},
	"bank_charter": {"label": "Charter a local bank (0 no, 1 yes, needs 120 people)", "min": 0.0, "max": 1.0, "step": 1.0},
	"lot_coverage": {"label": "Most of a lot that buildings may cover", "min": 0.25, "max": 0.7, "step": 0.05, "pct": true},
	"transfer_tax": {"label": "Tax on every property sale, paid by the seller", "min": 0.0, "max": 0.03, "step": 0.005, "pct": true},
	"hunting_season": {"label": "Hunting season (0 closed, 1 open in season)", "min": 0.0, "max": 1.0, "step": 1.0},
	"mining": {"label": "Mining (0 banned, 1 quarries only, 2 gold mines too)", "min": 0.0, "max": 2.0, "step": 1.0},
}
const DEFAULT_LAWS: Dictionary = {"min_wage": 1000, "property_tax": 0.015, "sales_tax": 0.02, "income_tax": 0.0, "business_tax": 0.06, "school_funding": 1.0, "police_funding": 1.0, "health_funding": 0.5, "welfare": 0.5, "fire_funding": 1.0, "license_fee": 1.0, "building_code": 1.0, "health_code": 1.0, "pollution_rule": 0.5, "zoning_density": 4, "rent_cap": 0.1, "late_fee_cap": 3500, "bus_service": 0.0, "bank_charter": 0.0, "transfer_tax": 0.005, "lot_coverage": 0.4, "hunting_season": 1.0, "mining": 1.0}
const DENY_REASONS: Array = ["no money in the budget this year", "this is not the city's job", "the need is not as big as the petition says", "maybe next year"]
const PETITION_KINDS: Dictionary = {
	"grocery": {"title": "We need a grocery store in town", "civic": false},
	"school": {"title": "Build a school here so our kids stop riding the bus for an hour", "civic": true},
	"clinic": {"title": "We need a clinic close to home", "civic": true},
	"road": {"title": "Fix the road", "civic": true},
	"housing": {"title": "We need more places to live that people can afford", "civic": false},
	"jobs": {"title": "Bring jobs to town", "civic": false},
	"park": {"title": "Give the kids a park", "civic": true},
}


static func setup_city(w: LTWorld) -> void:
	w.city = {
		"name": "Prairie Hollow",
		"laws": DEFAULT_LAWS.duplicate(),
		"elections": false,
		"term_years": 4,
		"next_election_day": 365 * 4 - 60,
		"mayor_in_office": true,
		"bonds": [],
		"newspapers": [],
		"services": [],
		"jobs": [],
		"income_12m": LTMoney.dollars(60000.0),
		"spend_12m": LTMoney.dollars(55000.0),
		"budget_months": [],
		"month": _blank_month(),
		"thefts_90d": [],
		"sales_tax_month": 0,
		"grants_paid": 0,
		"bad_debt": 0,
		"protests": 0,
		"repair_needs": [],
		"care_outside_90d": [],
	}
	# a single clerk job exists from the start
	w.city["jobs"].append({"id": 0, "title": "city clerk", "skill": "finance", "service": "hall", "wage": LTMoney.dollars(128.0), "holder": -1})


static func _blank_month() -> Dictionary:
	return {"income": {}, "spend": {}}


# ================================================================ law helpers

static func law(w: LTWorld, key: String) -> float:
	return float(w.city["laws"][key])


static func min_daily_wage(w: LTWorld) -> int:
	return int(w.city["laws"]["min_wage"]) * 8


static func sales_tax_rate(w: LTWorld) -> float:
	return law(w, "sales_tax")


static func income_tax_rate(w: LTWorld) -> float:
	return law(w, "income_tax")


static func business_tax_rate(w: LTWorld) -> float:
	return law(w, "business_tax")


static func lot_rent(w: LTWorld, lot_id: int) -> int:
	return int(float(LTGeography.asking_price(w, lot_id)) * 0.008)


static func has_service(w: LTWorld, kind: String) -> bool:
	for s in w.city["services"]:
		if str(s["kind"]) == kind:
			return true
	return false


static func service(w: LTWorld, kind: String) -> Dictionary:
	for s in w.city["services"]:
		if str(s["kind"]) == kind:
			return s
	return {}


static func school_quality(w: LTWorld) -> float:
	var f: float = law(w, "school_funding")
	var q: float = clampf(0.35 + f * 0.35, 0.2, 1.0)
	var s: Dictionary = service(w, "school")
	if not s.is_empty():
		var teachers: int = 0
		var teach_skill: float = 0.0
		for j in w.city["jobs"]:
			if str(j["service"]) == "school" and int(j["holder"]) >= 0:
				teachers += 1
				teach_skill += float(w.cit(int(j["holder"]))["skills"]["teaching"])
		var building: float = float(s["quality"])
		if teachers == 0:
			return q * 0.6
		q = clampf(q * 0.5 + (teach_skill / float(teachers)) / 100.0 * 0.3 + building * 0.2, 0.2, 1.0)
	return q


static func safety_level(w: LTWorld) -> float:
	if int(w.market.get("safety_day", -1)) == w.day:
		return float(w.market["safety"])
	var v: float = _safety_level(w)
	w.market["safety_day"] = w.day
	w.market["safety"] = v
	return v


static func _safety_level(w: LTWorld) -> float:
	var thefts: int = w.city["thefts_90d"].size()
	var unemp: float = 0.0
	if not w.stats_history.is_empty():
		unemp = float(w.stats_history[w.stats_history.size() - 1]["unemployment"])
	var lit: float = LTGeography.amenity_share(w, "lights") * 8.0
	return clampf(45.0 + law(w, "police_funding") * 28.0 - float(thefts) * 3.0 - unemp * 25.0 + lit, 5.0, 100.0)


static func enforcement(w: LTWorld) -> float:
	return clampf(0.25 + law(w, "police_funding") * 0.3, 0.1, 0.85)


static func family_friendliness(w: LTWorld) -> float:
	var f: float = 0.3 + school_quality(w) * 0.4
	if has_service(w, "clinic"):
		f += 0.15
	if has_service(w, "park"):
		f += 0.1
	return clampf(f, 0.0, 1.0)


# ================================================================ daily and monthly

static func daily(w: LTWorld) -> void:
	var cut: int = w.day - 90
	while not w.city["thefts_90d"].is_empty() and int(w.city["thefts_90d"][0]) < cut:
		w.city["thefts_90d"].remove_at(0)
	while not w.city["care_outside_90d"].is_empty() and int(w.city["care_outside_90d"][0]["day"]) < cut:
		w.city["care_outside_90d"].remove_at(0)
	_fill_city_jobs(w)
	if LTCalendar.weekday(w.day) == "Monday":
		_generate_petitions(w)
	_grow_signatures(w)
	_follow_up_petitions(w)
	if LTCalendar.is_month_start(w.day):
		_month_budget(w)
		_track_laws(w)


static func _book(w: LTWorld, side: String, cat: String, cents: int) -> void:
	pass


static func _month_budget(w: LTWorld) -> void:
	var laws: Dictionary = w.city["laws"]
	if not bool(w.city.get("incorporated", true)):
		# an unincorporated settlement: the county taxes and serves it, the town fund only pays its own bills
		var tr0: Dictionary = w.ledger.tracked["city"]
		var m0: Dictionary = {"income": tr0["in"].duplicate(), "spend": tr0["out"].duplicate(), "day": w.day}
		tr0["in"] = {}
		tr0["out"] = {}
		var i0: int = 0
		var s0: int = 0
		for k in m0["income"]:
			i0 += int(m0["income"][k])
		for k in m0["spend"]:
			s0 += int(m0["spend"][k])
		m0["total_income"] = i0
		m0["total_spend"] = s0
		m0["cash_end"] = w.ledger.bal("city")
		w.city["budget_months"].append(m0)
		return
	# property tax from every building: owners pay, outside owned property pays from outside
	for l in w.lots:
		if str(l["use"]) == "empty":
			continue
		var bill: int = int(float(l["value"]) * float(laws["property_tax"]) / 12.0)
		var paid: int = 0
		match str(l["owner_kind"]):
			"sim":
				var o: Dictionary = w.cit(int(l["owner_id"]))
				if w.is_present(o):
					paid = w.household_pay(w.hh(int(o["household"])), "city", bill, "property_tax")
					if paid < bill:
						LTFinance.new_debt(w, "p", int(o["id"]), "city", -1, "tax", bill - paid, 0.08, 12, "", -1, [])
						w.log_sim(o, "Could not pay %s of property tax. The city added a tax debt that bankruptcy cannot erase." % LTMoney.fmt(bill - paid), true)
			"business":
				var b: Dictionary = w.biz(int(l["owner_id"]))
				paid = w.ledger.pay(w.acct_b(b), "city", bill, "property_tax")
				b["month_costs"] = int(b["month_costs"]) + paid
			"outside":
				paid = w.ledger.pay("outside", "city", bill, "property_tax")
			"city":
				paid = 0
		_book(w, "income", "property tax", paid)
	# business lots leased from the city pay property tax inside their lease
	_book(w, "income", "sales tax", int(w.city["sales_tax_month"]))
	w.city["sales_tax_month"] = 0
	var students: int = 0
	for c in w.citizens:
		if w.is_present(c) and w.age_years(c) >= 5 and w.age_years(c) < 18 and str(c["student"]) != "dropout":
			students += 1
	# schools: tuition to the county district until the town has its own school
	# the state pays most of school costs, the city pays a local share
	var school_cost: int = int(float(students) * float(LTMoney.dollars(95.0)) * float(laws["school_funding"]))
	if has_service(w, "school"):
		school_cost = int(float(students) * float(LTMoney.dollars(40.0)) * float(laws["school_funding"]))
	# state aid per resident comes in from outside
	w.ledger.pay("outside", "city", w.alive_count() * LTMoney.dollars(22.0), "state aid")
	_spend(w, "outside", school_cost, "schools")
	_spend(w, "outside", int(float(LTMoney.dollars(1800.0)) * float(laws["police_funding"])), "police (county sheriff contract)")
	_spend(w, "outside", int(float(LTMoney.dollars(800.0)) * float(laws.get("fire_funding", 1.0))), "fire protection")
	if float(laws.get("bus_service", 0.0)) > 0.0:
		_spend(w, "outside", LTMoney.dollars(2400.0), "bus service contract")
	var sheltered: int = int(w.city.get("shelter_nights", 0))
	if sheltered > 0:
		_spend(w, "outside", sheltered * LTMoney.dollars(18.0), "homeless shelter")
		w.city["shelter_nights"] = 0
	if has_service(w, "clinic"):
		_spend(w, "outside", int(float(LTMoney.dollars(1500.0)) * maxf(0.5, float(laws["health_funding"]))), "clinic supplies")
	if has_service(w, "park"):
		_spend(w, "outside", LTMoney.dollars(300.0), "park upkeep")
	_spend(w, "outside", LTMoney.dollars(700.0), "road patching")
	for s in w.roads:
		if bool(s.get("planned", false)) or bool(s.get("removed", false)):
			continue
		s["condition"] = minf(100.0, float(s["condition"]) + 0.15)
	# record the month from the ledger's own record of city money in and out
	var tr: Dictionary = w.ledger.tracked["city"]
	var m: Dictionary = {"income": tr["in"].duplicate(), "spend": tr["out"].duplicate()}
	tr["in"] = {}
	tr["out"] = {}
	var inc: int = 0
	var sp: int = 0
	for k in m["income"]:
		inc += int(m["income"][k])
	for k in m["spend"]:
		sp += int(m["spend"][k])
	m["day"] = w.day
	m["total_income"] = inc
	m["total_spend"] = sp
	m["cash_end"] = w.ledger.bal("city")
	w.city["budget_months"].append(m)
	if w.city["budget_months"].size() > 120:
		w.city["budget_months"].remove_at(0)
	w.city["sales_12m"] = int(float(w.city.get("sales_12m", 0)) * 0.92)
	w.city["income_12m"] = 0
	w.city["spend_12m"] = 0
	var n: int = mini(12, w.city["budget_months"].size())
	for i in n:
		var bm: Dictionary = w.city["budget_months"][w.city["budget_months"].size() - 1 - i]
		w.city["income_12m"] = int(w.city["income_12m"]) + int(bm["total_income"])
		w.city["spend_12m"] = int(w.city["spend_12m"]) + int(bm["total_spend"])
	if n < 12 and n > 0:
		w.city["income_12m"] = int(float(w.city["income_12m"]) * 12.0 / float(n))
		w.city["spend_12m"] = int(float(w.city["spend_12m"]) * 12.0 / float(n))
	w.city["month"] = _blank_month()
	# trust in the city drifts toward how life is going and how services feel
	for c in w.citizens:
		if w.is_present(c) and w.age_years(c) >= 16:
			var target: float = LTPeople.happiness(c) * 0.6 - LTGov.trust_penalty(w) + safety_level(w) * 0.2 + (10.0 if has_service(w, "school") else 0.0) + (6.0 if has_service(w, "clinic") else 0.0)
			c["trust_city"] = float(c["trust_city"]) + (target - float(c["trust_city"])) * 0.08
	if w.ledger.bal("city") < LTMoney.dollars(10000.0):
		w.chronicle_add("City budget crisis: only %s left in the city account." % LTMoney.fmt(w.ledger.bal("city")), "city", true, [])


static func _spend(w: LTWorld, to_acct: String, cents: int, cat: String) -> int:
	var paid: int = w.ledger.pay("city", to_acct, cents, cat)
	if paid < cents:
		w.chronicle_add("The city could not fully pay for %s. Short by %s." % [cat, LTMoney.fmt(cents - paid)], "city", true, [])
	return paid


static func income_note(w: LTWorld, cat: String, cents: int) -> void:
	_book(w, "income", cat, cents)


# ================================================================ city services and city jobs

static func add_service(w: LTWorld, kind: String, lot_id: int, quality: float, size: String) -> void:
	var s: Dictionary = {"kind": kind, "lot": lot_id, "built_day": w.day, "quality": quality, "size": size}
	w.city["services"].append(s)
	var l: Dictionary = w.lot(lot_id)
	l["use"] = "civic"
	l["building"] = kind
	l["name"] = "Prairie Hollow %s" % kind.capitalize()
	l["owner_kind"] = "city"
	l["condition"] = 60.0 + quality * 40.0
	l["built_day"] = w.day
	l["value"] = LTMoney.dollars(150000.0)
	var jid: int = w.city["jobs"].size()
	match kind:
		"school":
			var n: int = 3 if size == "full" else 2
			for i in n:
				w.city["jobs"].append({"id": jid + i, "title": "teacher", "skill": "teaching", "service": "school", "wage": LTMoney.dollars(150.0), "holder": -1})
			for c in w.citizens:
				if w.is_present(c) and str(c["student"]) == "outside school":
					c["student"] = "town school"
		"clinic":
			w.city["jobs"].append({"id": jid, "title": "nurse", "skill": "medicine", "service": "clinic", "wage": LTMoney.dollars(170.0), "holder": -1})
			if size == "full":
				w.city["jobs"].append({"id": jid + 1, "title": "clinic doctor", "skill": "medicine", "service": "clinic", "wage": LTMoney.dollars(320.0), "holder": -1})
		"park":
			w.city["jobs"].append({"id": jid, "title": "park keeper", "skill": "farming", "service": "park", "wage": LTMoney.dollars(112.0), "holder": -1})


static func open_city_jobs(w: LTWorld) -> int:
	var n: int = 0
	for j in w.city["jobs"]:
		if int(j["holder"]) < 0:
			n += 1
	return n


static func best_city_opening(w: LTWorld, c: Dictionary) -> Dictionary:
	for j in w.city["jobs"]:
		if int(j["holder"]) < 0 and float(c["skills"][str(j["skill"])]) >= 35.0:
			return {"employer_kind": "city", "id": int(j["id"]), "name": "the city", "title": j["title"], "wage": maxi(int(j["wage"]), min_daily_wage(w)), "skill": j["skill"]}
	return {}


static func city_would_hire(w: LTWorld, opening: Dictionary, c: Dictionary) -> bool:
	return float(c["skills"][str(opening["skill"])]) >= 35.0 and LTJustice.record_count(c) == 0


static func hire_city(w: LTWorld, c: Dictionary, opening: Dictionary, reason: String) -> void:
	var j: Dictionary = w.city["jobs"][int(opening["id"])]
	if int(j["holder"]) >= 0:
		return
	if str(c["job"]["kind"]) != "none":
		LTEconomy.leave_job(w, c, "took a city job")
	j["holder"] = int(c["id"])
	LTPeople.set_job(w, c, "city", int(j["id"]), str(j["title"]), maxi(int(j["wage"]), min_daily_wage(w)), str(j["skill"]))
	w.counters["hires"] = int(w.counters["hires"]) + 1
	w.log_sim(c, reason.replace("the city as", "the city as"), true)


static func city_job_left(w: LTWorld, c: Dictionary) -> void:
	var jid: int = int(c["job"]["employer"])
	if jid >= 0 and jid < w.city["jobs"].size():
		w.city["jobs"][jid]["holder"] = -1


static func _fill_city_jobs(w: LTWorld) -> void:
	if w.day % 3 != 0:
		return
	for j in w.city["jobs"]:
		if int(j["holder"]) >= 0:
			continue
		var best: Dictionary = {}
		var best_s: float = 34.0
		for c in w.citizens:
			if not w.is_present(c) or w.age_years(c) < 18 or bool(c["retired"]) or str(c["job"]["kind"]) == "owner" or str(c["job"]["kind"]) == "city":
				continue
			var s: float = float(c["skills"][str(j["skill"])])
			if str(c["job"]["kind"]) == "outside":
				s -= 5.0
			if s > best_s and LTJustice.record_count(c) == 0 and not LTJustice.in_jail(w, c):
				best_s = s
				best = c
		if not best.is_empty():
			var opening: Dictionary = {"employer_kind": "city", "id": int(j["id"]), "name": "the city", "title": j["title"], "wage": maxi(int(j["wage"]), min_daily_wage(w)), "skill": j["skill"]}
			hire_city(w, best, opening, "Hired by the city as a %s. Reason: had the %s skill the job needs, and it is close to home." % [j["title"], j["skill"]])


static func city_payday(w: LTWorld) -> void:
	for j in w.city["jobs"]:
		var c: Dictionary = w.cit(int(j["holder"]))
		if not w.is_present(c):
			j["holder"] = -1
			continue
		var due: int = int(c["job"]["daily_wage"]) * 5
		var paid: int = _spend(w, w.acct_p(c), due, "city staff wages")
		w.ledger.pay(w.acct_p(c), "city", int(float(paid) * income_tax_rate(w)), "income_tax")
	# unemployment support for adults looking for work
	var welfare: float = law(w, "welfare")
	if welfare <= 0.0:
		return
	for c in w.citizens:
		if not w.is_present(c) or w.age_years(c) < 18 or bool(c["retired"]):
			continue
		if str(c["job"]["kind"]) == "none" and int(c["days_unemployed"]) >= 7 and int(c["days_unemployed"]) < 200:
			var amt: int = int(float(LTMoney.dollars(150.0)) * welfare)
			var paid2: int = _spend(w, w.acct_p(c), amt, "unemployment support")
			if paid2 > 0 and int(c["days_unemployed"]) < 14:
				w.log_sim(c, "Started getting %s a week in city unemployment support." % LTMoney.fmt(paid2), false)


static func food_help(w: LTWorld, h: Dictionary) -> void:
	var welfare: float = law(w, "welfare")
	if welfare <= 0.0:
		return
	var members: Array = w.household_members(h)
	var units: float = float(members.size()) * 3.0 * welfare
	var cost: int = int(units * float(LTEconomy.FOOD_UNIT_PRICE))
	var paid: int = _spend(w, "outside", cost, "food support")
	h["pantry"] = float(h["pantry"]) + units * float(paid) / float(maxi(1, cost))


static func seek_care(w: LTWorld, c: Dictionary, serious: bool) -> void:
	var local: bool = has_service(w, "clinic")
	var bill: int = LTMoney.dollars(160.0)
	if serious:
		bill = LTMoney.dollars(2800.0)
	var city_share: float = clampf(law(w, "health_funding") * 0.25, 0.0, 0.6)
	if local and not serious:
		bill = LTMoney.dollars(60.0)
	var city_part: int = int(float(bill) * city_share)
	_spend(w, "outside", city_part, "health care support")
	var own: int = bill - city_part
	var payer: Dictionary = c
	if w.age_years(c) < 18:
		var adults: Array = w.household_adults(w.hh(int(c["household"])))
		if not adults.is_empty():
			payer = adults[0]
	var home: int = int(w.hh(int(payer["household"]))["lot"])
	var paid: int = 0
	if local and not serious:
		paid = w.ledger.pay(w.acct_p(payer), "city", own, "clinic_fees")
	else:
		var private: bool = not w.open_businesses("clinic").is_empty()
		paid = LTServices.spend(w, w.acct_p(payer), "medical", own, home, payer)
		if private and not serious:
			local = true
	LTServices.spend(w, w.acct_p(payer), "pharmacy", LTMoney.dollars(35.0), home, payer)
	if not local:
		w.city["care_outside_90d"].append({"day": w.day, "id": int(c["id"]), "serious": serious})
		w.ledger.pay(w.acct_p(payer), "outside", LTEconomy.OUTSIDE_TRIP_FUEL, "commute_fuel")
	if paid < own and w.age_years(payer) >= 18:
		var d: Dictionary = LTFinance.new_debt(w, "p", int(payer["id"]), "clinic", -1, "medical", own - paid, 0.0, 0, "", -1, [])
		d["payment"] = maxi(LTMoney.dollars(50.0), (own - paid) / 24)
		d["term"] = 24
		w.log_sim(payer, "Owes %s in medical bills to County Medical Center after %s %s." % [LTMoney.fmt(own - paid), "their" if payer == c else c["first_name"] + "'s", "serious illness" if serious else "doctor visit"], true)
	if serious:
		w.log_sim(c, "Got seriously ill and needed care at %s." % ("the town clinic" if local else "County Medical Center, %d minutes away" % int(w.minutes_to_outside(maxi(0, int(w.hh(int(c["household"]))["lot"]))))), true)


static func theft(w: LTWorld, c: Dictionary, reason: String) -> void:
	var victims: Array = w.open_businesses("grocery") + w.open_businesses("general_store")
	var target_name: String = ""
	var amount: int = LTMoney.dollars(w.rng.randf_range(20.0, 90.0))
	if not victims.is_empty():
		var b: Dictionary = victims[w.rng.randi_range(0, victims.size() - 1)]
		var units: float = minf(float(b["stock"]), 6.0)
		b["stock"] = float(b["stock"]) - units
		w.hh(int(c["household"]))["pantry"] = float(w.hh(int(c["household"]))["pantry"]) + units
		target_name = str(b["name"])
		w.log_biz(b, "Shoplifting: about %d units of stock went missing." % int(units))
	else:
		var hs: Array = []
		for h in w.households:
			if int(h["id"]) != int(c["household"]) and int(h["lot"]) >= 0 and w.household_cash(h) > amount:
				hs.append(h)
		if hs.is_empty():
			return
		var vh: Dictionary = hs[w.rng.randi_range(0, hs.size() - 1)]
		var victim: Dictionary = w.household_adults(vh)[0]
		amount = w.ledger.pay(w.acct_p(victim), w.acct_p(c), amount, "theft")
		target_name = "the %s home" % victim["last_name"]
		w.remember(victim, "robbed", int(c["id"]), -20.0)
		w.log_sim(victim, "Someone stole %s from home." % LTMoney.fmt(amount), true)
		victim["needs"]["safety"] = float(victim["needs"]["safety"]) - 20.0
	w.counters["thefts"] = int(w.counters["thefts"]) + 1
	w.city["thefts_90d"].append(w.day)
	var caught: bool = w.rng.randf() < LTJustice.detection(w, "theft") * 0.6
	if caught:
		w.log_sim(c, "Stole from %s and was caught. Reason for stealing: %s." % [target_name, reason], true)
		LTJustice.charge(w, c, "theft", "stole from %s" % target_name, -1, 0)
	else:
		w.log_sim(c, "Stole from %s and was not caught. Reason: %s." % [target_name, reason], true)


# ================================================================ petitions

static func _affected_for(w: LTWorld, kind: String) -> Dictionary:
	var m: Dictionary = w.market
	var affected: Array = []
	var why: String = ""
	var strength: float = 0.0
	var data: Dictionary = {}
	match kind:
		"grocery":
			if int(m.get("grocery_count", 0)) > 0 and float(m.get("grocery_outside_share", 0.0)) < 0.5:
				return {}
			for g in w.open_businesses("grocery"):
				if w.day - int(g["opened_day"]) < 150:
					return {}
			for h in w.households:
				if int(h["lot"]) >= 0 and (str(h["last_grocery"]) == "outside" or str(h["last_grocery"]) == ""):
					affected.append_array(w.household_adults(h))
			data = {"households_outside": m.get("grocery_outside_households", 0), "households": m.get("households", 0), "trip_minutes": int(m.get("avg_grocery_trip_minutes", 0.0))}
			why = "%d of %d households drive to the next town for groceries, about %d minutes round trip, and the gas money leaves town." % [data["households_outside"], data["households"], data["trip_minutes"]]
			strength = float(data["households_outside"]) * float(data["trip_minutes"]) / 60.0
		"school":
			if has_service(w, "school"):
				return {}
			var kids: int = 0
			for c in w.citizens:
				if w.is_present(c) and str(c["student"]) == "outside school":
					kids += 1
					for pid in [int(c["mother"]), int(c["father"])]:
						var p: Dictionary = w.cit(pid)
						if w.is_present(p) and not affected.has(p):
							affected.append(p)
			if kids < 8:
				return {}
			var mins: int = int(w.minutes_to_outside(0) + 15.0)
			data = {"students": kids, "bus_minutes": mins}
			why = "%d children ride a bus about %d minutes each way to the county school. They come home tired and learn less." % [kids, mins]
			strength = float(kids) * 2.0
		"clinic":
			if has_service(w, "clinic"):
				return {}
			var trips: Array = w.city["care_outside_90d"]
			var seniors: int = 0
			for c in w.citizens:
				if w.is_present(c) and w.age_years(c) >= 65:
					seniors += 1
					affected.append(c)
			for t in trips:
				var tc: Dictionary = w.cit(int(t["id"]))
				if w.is_present(tc) and w.age_years(tc) >= 18 and not affected.has(tc):
					affected.append(tc)
			if trips.size() < 4 and seniors < 8:
				return {}
			data = {"care_trips_90d": trips.size(), "seniors": seniors, "minutes": int(w.minutes_to_outside(0))}
			why = "%d trips to County Medical Center in the last 90 days, each about %d minutes away. %d seniors live here." % [trips.size(), data["minutes"], seniors]
			strength = float(trips.size()) * 2.0 + float(seniors)
		"road":
			var worst: int = -1
			var worst_c: float = 100.0
			for st in w.streets:
				if str(st["kind"]) != "street":
					continue
				var cond: float = LTGeography.street_condition(w, int(st["id"]))
				if cond < worst_c:
					worst_c = cond
					worst = int(st["id"])
			if worst < 0 or worst_c > 40.0:
				return {}
			for l in w.lots:
				if int(l["street"]) == worst:
					for u in l["units"]:
						if int(u) >= 0:
							affected.append_array(w.household_adults(w.hh(int(u))))
					if str(l["use"]) == "business":
						var b: Dictionary = w.biz(int(l["ref"]))
						for o in b["owners"]:
							if w.is_present(w.cit(int(o))):
								affected.append(w.cit(int(o)))
			var last: int = -1
			for sid in w.streets[worst]["segments"]:
				last = maxi(last, int(w.roads[int(sid)]["last_project"]))
			data = {"street": worst, "condition": int(worst_c), "last_project": last}
			why = "%s is in poor shape, condition %d of 100. Trips are slower and cars take a beating." % [w.streets[worst]["name"], int(worst_c)]
			if last >= 0:
				var p: Dictionary = w.projects[last]
				why += " It was last fixed by %s on day %d, and that job is not holding up." % [p.get("winner_name", "a contractor"), int(p.get("done_day", 0))]
			strength = (40.0 - worst_c) * 1.5 + float(affected.size())
		"housing":
			var homeless: int = 0
			for h in w.households:
				if int(h["lot"]) < 0 and not w.household_members(h).is_empty():
					homeless += 1
					affected.append_array(w.household_adults(h))
			if homeless == 0 and LTPeople.vacancy_count(w) > 0:
				return {}
			data = {"homeless_households": homeless, "vacant_units": LTPeople.vacancy_count(w)}
			why = "%d households have no home and %d apartments are free in town." % [homeless, data["vacant_units"]]
			strength = float(homeless) * 6.0 + (8.0 if LTPeople.vacancy_count(w) == 0 else 0.0)
			if strength < 6.0:
				return {}
		"jobs":
			var un: int = 0
			var adults: int = 0
			for c in w.citizens:
				if w.is_present(c) and w.age_years(c) >= 18 and not bool(c["retired"]):
					adults += 1
					if str(c["job"]["kind"]) == "none" and int(c["days_unemployed"]) > 30:
						un += 1
						affected.append(c)
			if adults == 0 or float(un) / float(adults) < 0.14:
				return {}
			data = {"long_unemployed": un, "adults": adults}
			why = "%d of %d working age adults have been out of work more than a month." % [un, adults]
			strength = float(un) * 2.0
		"park":
			if has_service(w, "park"):
				return {}
			var kids2: int = 0
			for c in w.citizens:
				if w.is_present(c) and w.age_years(c) < 13 and w.age_years(c) >= 3:
					kids2 += 1
					for pid in [int(c["mother"]), int(c["father"])]:
						var p2: Dictionary = w.cit(pid)
						if w.is_present(p2) and not affected.has(p2):
							affected.append(p2)
			if kids2 < 12:
				return {}
			data = {"kids": kids2}
			why = "%d young children and no park anywhere in town." % kids2
			strength = float(kids2) * 0.8
	if affected.is_empty():
		return {}
	return {"affected": affected, "why": why, "strength": strength, "data": data}


static func _generate_petitions(w: LTWorld) -> void:
	# people need a few weeks of living with a problem before someone organizes
	if w.day < 14:
		return
	var started_this_week: bool = false
	for kind in PETITION_KINDS:
		if started_this_week:
			return
		var open: bool = false
		for p in w.petitions:
			if str(p["kind"]) == kind and ["gathering", "submitted", "approved", "approved_moved", "approved_smaller", "published"].has(str(p["status"])):
				open = true
				break
			if str(p["kind"]) == kind and str(p["status"]) == "denied" and w.day - int(p["response_day"]) < 60:
				open = true
				break
			if str(p["kind"]) == kind and str(p["status"]) == "resolved" and w.day - int(p.get("resolved_day", 0)) < 180:
				open = true
				break
		if open:
			continue
		var a: Dictionary = _affected_for(w, kind)
		if a.is_empty():
			continue
		if float(a["strength"]) < 6.0:
			continue
		# the starter is whoever feels it most and organizes people: kindness and sociability
		var starter: Dictionary = {}
		var best: float = -1e9
		for c in a["affected"]:
			var t: Dictionary = c["traits"]
			var s: float = float(t["kindness"]) * 0.4 + float(t["sociability"]) * 0.4 + float(t["ambition"]) * 0.1 + w.rng.randf_range(0.0, 15.0)
			if s > best:
				best = s
				starter = c
		if best < 55.0:
			continue
		_start_petition(w, kind, starter, a)
		started_this_week = true


static func _start_petition(w: LTWorld, kind: String, starter: Dictionary, a: Dictionary) -> void:
	var near: Array = []
	for c in a["affected"]:
		var hl: int = int(w.hh(int(c["household"]))["lot"])
		if hl >= 0:
			near.append(hl)
	var site: int = -1
	var site_text: String = ""
	match kind:
		"grocery", "jobs":
			site = LTGeography.best_site(w, ["commercial", "mixed"], near)
		"school", "clinic", "park":
			site = LTGeography.best_site(w, ["civic", "park"] if kind == "park" else ["civic"], near)
			if site < 0:
				site = LTGeography.best_site(w, ["commercial", "mixed", "park"], near)
		"housing":
			site = LTGeography.best_site(w, ["residential", "mixed"], near)
		"road":
			site = int(a["data"]["street"])
	if kind == "road":
		site_text = str(w.streets[site]["name"])
	elif site >= 0:
		site_text = LTGeography.lot_label(w, site)
	else:
		site_text = "anywhere close"
	var p: Dictionary = {
		"id": w.petitions.size(), "kind": kind, "title": PETITION_KINDS[kind]["title"], "why": a["why"], "data": a["data"],
		"starter": int(starter["id"]), "signers": [int(starter["id"])], "affected": a["affected"].map(func(x): return int(x["id"])),
		"created_day": w.day, "status": "gathering", "site": site, "site_text": site_text, "offers": [],
		"strength": float(a["strength"]), "response": "", "response_day": -1, "response_reason": "", "outcome": [],
		"threshold": maxi(4, int(ceil(float(a["affected"].size()) * 0.3))), "project_id": -1, "need_id": -1,
	}
	if kind == "road":
		p["title"] = "Fix %s" % w.streets[site]["name"]
	_find_offers(w, p)
	w.petitions.append(p)
	w.counters["petitions"] = int(w.counters["petitions"]) + 1
	w.log_sim(starter, "Started a petition: \"%s\". Reason: %s" % [p["title"], a["why"]], true)
	w.remember(starter, "petition_started", int(p["id"]), 10.0)
	w.chronicle_add("%s started a petition: \"%s\". %s Suggested site: %s." % [w.full_name(starter), p["title"], a["why"], site_text], "petition", w.involves_watched([starter["id"]]), [starter["id"]])


static func _find_offers(w: LTWorld, p: Dictionary) -> void:
	var kind: String = str(p["kind"])
	var skill: String = ""
	match kind:
		"grocery":
			skill = "retail"
		"clinic":
			skill = "medicine"
		"school":
			skill = "teaching"
	if skill == "":
		return
	for c in w.citizens:
		if not w.is_present(c) or w.age_years(c) < 21:
			continue
		if float(c["skills"][skill]) > 55.0 and float(c["traits"]["ambition"]) > 45.0:
			var verb: String = "run it if the city helps get it started" if kind == "grocery" else "work there"
			p["offers"].append({"citizen": int(c["id"]), "text": "%s, %s skill %d, offers to %s." % [w.full_name(c), skill, int(c["skills"][skill]), verb]})
			if p["offers"].size() >= 2:
				break
	for c in w.citizens:
		if w.is_present(c) and w.cash(c) > LTMoney.dollars(40000.0) and float(c["traits"]["kindness"]) > 65.0:
			p["offers"].append({"citizen": int(c["id"]), "text": "%s offers to put in %s toward it." % [w.full_name(c), LTMoney.fmt(LTMoney.dollars(2000.0))], "cofund": LTMoney.dollars(2000.0)})
			break


static func _grow_signatures(w: LTWorld) -> void:
	for p in w.petitions:
		if str(p["status"]) != "gathering" and str(p["status"]) != "submitted":
			continue
		var starter: Dictionary = w.cit(int(p["starter"]))
		for aid in p["affected"]:
			if p["signers"].has(aid):
				continue
			var c: Dictionary = w.cit(int(aid))
			if not w.is_present(c):
				continue
			var trust_starter: float = 50.0
			if c["rel"].has(int(p["starter"])):
				trust_starter = float(c["rel"][int(p["starter"])]["trust"])
			# word spreads slowly: a neighbor hears about it, thinks it over, signs
			var prob: float = 0.006 + float(c["traits"]["sociability"]) / 8000.0 + trust_starter / 9000.0 + clampf(float(p["strength"]) / 2000.0, 0.0, 0.02)
			if not starter.is_empty():
				prob += float(starter["traits"]["sociability"]) / 10000.0
			if w.rng.randf() < prob:
				p["signers"].append(int(aid))
				c["signed"].append(int(p["id"]))
				if not starter.is_empty():
					LTPeople.relate_event(w, c, starter, "neighbor", 2.0, 2.0)
		if str(p["status"]) == "gathering" and p["signers"].size() >= int(p["threshold"]):
			p["status"] = "submitted"
			p["submitted_day"] = w.day
			w.chronicle_add("Petition \"%s\" reached %d signatures and is on the mayor's desk." % [p["title"], p["signers"].size()], "petition", true, [p["starter"]])


static func petition_cost_estimate(w: LTWorld, p: Dictionary) -> int:
	match str(p["kind"]):
		"school":
			return LTProjects.BASE_COST["school"]
		"clinic":
			return LTProjects.BASE_COST["clinic"]
		"park":
			return LTProjects.BASE_COST["park"]
		"road":
			return LTProjects.BASE_COST["road_repair"]
		"grocery", "jobs", "housing":
			return LTMoney.dollars(10000.0)
	return 0


## Mayor responses. Each changes what happens next, through Sim scoring.
static func respond_petition(w: LTWorld, pid: int, response: String, act: Dictionary) -> Dictionary:
	if pid < 0 or pid >= w.petitions.size():
		return {"ok": false, "message": "No such petition."}
	var p: Dictionary = w.petitions[pid]
	if not ["gathering", "submitted"].has(str(p["status"])):
		return {"ok": false, "message": "That petition has already been answered."}
	var kind: String = str(p["kind"])
	var civic: bool = bool(PETITION_KINDS[kind]["civic"])
	var trust_delta: float = 0.0
	var msg: String = ""
	var site: int = int(p["site"])
	match response:
		"approve", "approve_moved", "approve_smaller":
			if response == "approve_moved":
				site = int(act.get("lot", -1))
				if site < 0:
					return {"ok": false, "message": "Pick a different site first."}
			var smaller: bool = response == "approve_smaller"
			if civic:
				var ptype: String = kind if kind != "road" else "road_repair"
				if smaller:
					ptype = {"school": "school_small", "clinic": "clinic_small", "park": "park", "road": "road_patch"}[kind]
				var r: Dictionary = LTProjects.define_project(w, ptype, site, int(act.get("ceiling", 0)), pid, not bool(act.get("live", false)))
				if not bool(r["ok"]):
					return r
				p["project_id"] = int(r["project_id"])
				msg = "Approved. %s" % r["message"]
			else:
				var btype: String = "grocery" if kind == "grocery" else ("general_store" if kind == "jobs" else "landlord")
				if kind == "housing":
					var hr: Dictionary = LTProjects.define_project(w, "apartments", site, 0, pid, not bool(act.get("live", false)))
					if not bool(hr["ok"]):
						return hr
					p["project_id"] = int(hr["project_id"])
					msg = "Approved. %s" % hr["message"]
				else:
					var inc: Dictionary = {"free_lot": true}
					if not smaller:
						inc["tax_break_years"] = 2
					var nr: Dictionary = publish_need(w, btype, site, inc, pid)
					if not bool(nr["ok"]):
						return nr
					msg = "Approved. " + str(nr["message"])
			trust_delta = 12.0 if response == "approve" else (4.0 if response == "approve_smaller" else 0.0)
			if response == "approve_moved":
				# moving it helps only if the signers can still reach it
				var reach: float = _reach_penalty(w, p, site)
				trust_delta = 8.0 - reach
				p["outcome"].append("Moved to %s. For the people who signed, the trip is about %d minutes longer." % [LTGeography.lot_label(w, site), int(reach)])
			p["status"] = response if response != "approve" else "approved"
		"publish_need":
			var btype2: String = str(act.get("need", "grocery"))
			var nr2: Dictionary = publish_need(w, btype2, site, act.get("incentives", {"free_lot": true}), pid)
			if not bool(nr2["ok"]):
				return nr2
			msg = str(nr2["message"])
			p["status"] = "published"
			trust_delta = 6.0 + float(act.get("incentives", {}).size()) * 1.5
		"deny":
			var reason: String = str(act.get("reason", DENY_REASONS[0]))
			p["status"] = "denied"
			p["response_reason"] = reason
			var anger: float = 8.0 + float(p["strength"]) * 0.15
			if reason == DENY_REASONS[2]:
				anger *= 1.6
			elif reason == DENY_REASONS[3]:
				anger *= 0.6
			trust_delta = -anger
			msg = "Denied. Reason given: %s." % reason
			_after_denial(w, p, reason)
		_:
			return {"ok": false, "message": "Unknown response."}
	p["response"] = response
	p["response_day"] = w.day
	for sid in p["signers"]:
		var c: Dictionary = w.cit(int(sid))
		if w.is_present(c):
			c["trust_city"] = clampf(float(c["trust_city"]) + trust_delta, 0.0, 100.0)
			w.log_sim(c, "The mayor answered the petition \"%s\": %s" % [p["title"], msg], false)
	for aid in p["affected"]:
		if not p["signers"].has(aid):
			var c2: Dictionary = w.cit(int(aid))
			if w.is_present(c2):
				c2["trust_city"] = clampf(float(c2["trust_city"]) + trust_delta * 0.4, 0.0, 100.0)
	p["outcome"].append("Day %d: %s Trust in the city among signers changed by %d." % [w.day, msg, int(trust_delta)])
	w.chronicle_add("The mayor answered \"%s\": %s" % [p["title"], msg], "petition", false, [p["starter"]])
	return {"ok": true, "message": msg}


static func _reach_penalty(w: LTWorld, p: Dictionary, new_site: int) -> float:
	if int(p["site"]) < 0 or new_site < 0 or str(p["kind"]) == "road":
		return 0.0
	var diff: float = 0.0
	var n: int = 0
	for sid in p["signers"]:
		var c: Dictionary = w.cit(int(sid))
		var hl: int = int(w.hh(int(c["household"]))["lot"])
		if hl < 0:
			continue
		diff += w.travel_minutes(hl, new_site) - w.travel_minutes(hl, int(p["site"]))
		n += 1
	return 0.0 if n == 0 else maxf(0.0, diff / float(n)) * 2.0


static func _after_denial(w: LTWorld, p: Dictionary, reason: String) -> void:
	var starter: Dictionary = w.cit(int(p["starter"]))
	if p["signers"].size() >= int(p["threshold"]) * 2 or (reason == DENY_REASONS[2] and float(p["strength"]) > 30.0):
		w.city["protests"] = int(w.city["protests"]) + 1
		p["outcome"].append("Signers protested outside city hall.")
		w.chronicle_add("%d people protested at city hall after the mayor denied \"%s\" saying %s." % [p["signers"].size(), p["title"], reason], "protest", true, [p["starter"]])
	# Sims try to solve it themselves: founders see the gap, some petition again later
	for sid in p["signers"]:
		var c: Dictionary = w.cit(int(sid))
		if w.is_present(c):
			w.remember(c, "petition_denied", int(p["id"]), -15.0)
			c["trigger"] = true


static func _follow_up_petitions(w: LTWorld) -> void:
	if w.day % 7 != 3:
		return
	for p in w.petitions:
		if str(p["status"]) == "resolved" or str(p["status"]) == "denied" or str(p["status"]) == "gathering" or str(p["status"]) == "submitted":
			continue
		var kind: String = str(p["kind"])
		var done: bool = false
		var note: String = ""
		match kind:
			"grocery":
				if not w.open_businesses("grocery").is_empty():
					done = true
					note = "A grocery opened: %s." % w.open_businesses("grocery")[0]["name"]
			"school", "clinic", "park":
				if has_service(w, kind):
					done = true
					note = "The %s opened." % kind
			"road", "housing":
				if int(p["project_id"]) >= 0 and str(w.projects[int(p["project_id"])]["status"]) == "done":
					done = true
					note = "The project is finished."
			"jobs":
				if LTEconomy.open_positions(w) > 0 or w.open_businesses().size() > 3:
					done = true
					note = "New businesses are hiring."
		if done:
			p["status"] = "resolved"
			p["resolved_day"] = w.day
			p["outcome"].append("Day %d: %s" % [w.day, note])
			for sid in p["signers"]:
				var c: Dictionary = w.cit(int(sid))
				if w.is_present(c):
					c["trust_city"] = clampf(float(c["trust_city"]) + 6.0, 0.0, 100.0)


# ================================================================ published needs

static func publish_need(w: LTWorld, btype: String, lot_id: int, incentives: Dictionary, petition_id: int) -> Dictionary:
	if LTEconomy.tcfg(btype).is_empty() or btype == "landlord":
		return {"ok": false, "message": "Unknown business type."}
	for n in w.city_needs:
		if str(n["need"]) == btype and str(n["status"]) == "open":
			return {"ok": false, "message": "A %s need is already published." % btype}
	var zones: Array = LTEconomy.tcfg(btype)["zones"]
	if lot_id >= 0:
		var l: Dictionary = w.lot(lot_id)
		if str(l["use"]) != "empty":
			return {"ok": false, "message": "That lot is not empty."}
		if not zones.has(str(l["zone"])):
			return {"ok": false, "message": "That lot is zoned %s. A %s needs %s." % [l["zone"], btype, " or ".join(zones)]}
	else:
		lot_id = LTGeography.best_site(w, zones, [])
	var grant: int = int(incentives.get("grant", 0))
	if grant > w.ledger.bal("city"):
		return {"ok": false, "message": "The city does not have %s for the grant." % LTMoney.fmt(grant)}
	var n2: Dictionary = {"id": w.city_needs.size(), "need": btype, "lot": lot_id, "incentives": incentives.duplicate(), "status": "open", "published_day": w.day, "petition_id": petition_id, "taken_by": -1}
	w.city_needs.append(n2)
	if petition_id >= 0:
		w.petitions[petition_id]["need_id"] = int(n2["id"])
	var parts: Array = []
	if bool(incentives.get("free_lot", false)):
		parts.append("a free lot")
	if int(incentives.get("tax_break_years", 0)) > 0:
		parts.append("no business tax for %d years" % int(incentives["tax_break_years"]))
	if grant > 0:
		parts.append("a %s start up grant" % LTMoney.fmt(grant))
	if bool(incentives.get("loan_guarantee", false)):
		parts.append("a city loan guarantee")
	var inc_text: String = "no incentives" if parts.is_empty() else ", ".join(parts)
	# a published need is a decision point for Sims who could take it
	var skill: String = str(LTEconomy.tcfg(btype)["skill"])
	for c in w.citizens:
		if w.is_present(c) and w.age_years(c) >= 21 and float(c["skills"][skill]) >= 30.0:
			c["trigger"] = true
	w.chronicle_add("The city published a need: this town needs a %s, at %s, with %s." % [str(LTEconomy.tcfg(btype)["display"]).to_lower(), LTGeography.lot_label(w, lot_id), inc_text], "city", true, [])
	return {"ok": true, "message": "Published a need for a %s on %s with %s. A Sim still has to decide to take it." % [str(LTEconomy.tcfg(btype)["display"]).to_lower(), LTGeography.lot_label(w, lot_id), inc_text]}


static func open_need_for(w: LTWorld, btype: String) -> Dictionary:
	for n in w.city_needs:
		if str(n["need"]) == btype and str(n["status"]) == "open":
			return n
	return {}


static func zone_lot(w: LTWorld, lot_id: int, zone: String) -> Dictionary:
	if not LTGeography.ZONES.has(zone):
		return {"ok": false, "message": "Unknown zone."}
	var l: Dictionary = w.lot(lot_id)
	if l.is_empty():
		return {"ok": false, "message": "No such lot."}
	if not ["empty", "closed"].has(str(l["use"])):
		return {"ok": false, "message": "Only empty lots can be rezoned. Something is built there."}
	var old: String = str(l["zone"])
	l["zone"] = zone
	l["value"] = LTGeography.land_value(zone)
	if str(l["use"]) == "closed":
		l["use"] = "empty"
		l["ref"] = -1
		l["building"] = ""
	w.chronicle_add("Lot %d was rezoned from %s to %s." % [lot_id, old, zone], "city", false, [])
	return {"ok": true, "message": "Lot %d is now zoned %s." % [lot_id, zone]}


# ================================================================ laws with estimates

static func law_estimate(w: LTWorld, key: String, value: float) -> Dictionary:
	var laws: Dictionary = w.city["laws"]
	var old: float = float(laws[key])
	var hits: String = ""
	var yearly: int = 0
	match key:
		"min_wage":
			var daily_new: int = int(value) * 8
			var below: int = 0
			var extra: int = 0
			for c in w.citizens:
				if w.is_present(c) and ["business", "city"].has(str(c["job"]["kind"])) and int(c["job"]["daily_wage"]) < daily_new:
					below += 1
					extra += (daily_new - int(c["job"]["daily_wage"])) * 260
			hits = "%d local workers would get a raise, costing their employers about %s a year. Thin margin businesses may cut staff or raise prices. Outside jobs are not affected." % [below, LTMoney.fmt(extra)]
			yearly = 0
		"property_tax":
			var base: int = 0
			for l in w.lots:
				if str(l["use"]) != "empty" and str(l["owner_kind"]) != "city":
					base += int(l["value"])
			yearly = int(float(base) * (value - old))
			hits = "Every home and building owner, and landlords who pass it on to renters. City income changes by about %s a year." % LTMoney.fmt(yearly)
		"sales_tax":
			var sales: int = 0
			for b in w.open_businesses():
				var h: Array = b["customers_hist"]
				if not h.is_empty():
					sales += int(h[h.size() - 1]) * 12
			yearly = int(float(sales) * (value - old))
			hits = "Local shoppers pay it. Higher sales tax pushes some shopping back to the next town. City income changes by about %s a year at today's sales." % LTMoney.fmt(yearly)
		"income_tax":
			var wages: int = 0
			for c in w.citizens:
				if w.is_present(c) and str(c["job"]["kind"]) != "none" and str(c["job"]["kind"]) != "owner":
					wages += int(c["job"]["daily_wage"]) * 260
			yearly = int(float(wages) * (value - old))
			hits = "Everyone with a paycheck. Lowers money security, may push some to move. City income changes by about %s a year." % LTMoney.fmt(yearly)
		"business_tax":
			var profits: int = 0
			for b in w.open_businesses():
				for pr in b["month_profit_hist"]:
					profits += maxi(0, int(pr))
			yearly = int(float(profits) * (value - old))
			hits = "Business owners. Lower tax makes more Sims think a start up is worth it. City income changes by about %s a year at today's profits." % LTMoney.fmt(yearly)
		"school_funding":
			var students: int = 0
			for c in w.citizens:
				if w.is_present(c) and w.age_years(c) >= 5 and w.age_years(c) < 18:
					students += 1
			yearly = -int(float(students) * float(LTMoney.dollars(95.0 if not has_service(w, "school") else 40.0)) * 12.0 * (value - old))
			hits = "%d students. Their education grows %s each school day. The effect shows up years from now when they are adults. Cost changes by about %s a year." % [students, "faster" if value > old else "slower", LTMoney.fmt(-yearly)]
		"police_funding":
			yearly = -int(float(LTMoney.dollars(1800.0)) * 12.0 * (value - old))
			hits = "Everyone's sense of safety, and anyone tempted to steal. Cost changes by about %s a year." % LTMoney.fmt(-yearly)
		"health_funding":
			yearly = -int(float(w.city["care_outside_90d"].size()) * 4.0 * float(LTMoney.dollars(160.0)) * 0.25 * (value - old))
			hits = "People who need a doctor. The city pays a bigger or smaller share of each visit. Cost changes by about %s a year." % LTMoney.fmt(-yearly)
		"welfare":
			var un: int = 0
			for c in w.citizens:
				if w.is_present(c) and w.age_years(c) >= 18 and str(c["job"]["kind"]) == "none" and not bool(c["retired"]):
					un += 1
			yearly = -int(float(un) * float(LTMoney.dollars(150.0)) * 52.0 * (value - old))
			hits = "%d adults out of work, hungry households, and anyone sleeping in the shelter. Cost changes by about %s a year at today's unemployment." % [un, LTMoney.fmt(-yearly)]
		"fire_funding":
			yearly = -int(float(LTMoney.dollars(800.0)) * 12.0 * (value - old))
			hits = "Every building. Better fire service reaches fires sooner, so they do less damage. Cost changes by about %s a year." % LTMoney.fmt(-yearly)
		"license_fee":
			var n_new: int = 0
			for b in w.businesses:
				if w.day - int(b["opened_day"]) < 365:
					n_new += 1
			yearly = int(float(n_new) * float(LTMoney.dollars(250.0)) * (value - old))
			hits = "Anyone starting a business pays %s the fee. High fees push a few founders, the less honest ones, to skip the license. City income changes by about %s a year." % ["more" if value > old else "less", LTMoney.fmt(yearly)]
		"building_code":
			hits = "Builders: a stricter code costs about %d%% more per project but sets a floor on quality and storm damage. A loose code is cheaper now and costs later." % int(absf(value - old) * 12.0)
		"health_code":
			hits = "Food shops, bars, clinics, child care and the motel. Inspectors visit more often; owners spend on cleaning; failing shops lose reputation or face charges."
		"pollution_rule":
			hits = "Factories pay more to run clean. Neighbors' health improves. A strict rule can make a factory not worth starting."
		"zoning_density":
			hits = "New apartment buildings will hold %d homes instead of %d. More homes per lot, more crowding on the street." % [int(value), int(old)]
		"rent_cap":
			var renters: int = 0
			for h in w.households:
				if str(h["tenure"]) == "rent":
					renters += 1
			hits = "%d renting households. A low cap protects them; landlords earn less and build less." % renters
		"late_fee_cap":
			hits = "Borrowers who fall behind pay at most %s per missed payment. Lenders lose a little income." % LTMoney.fmt(int(value))
		"bus_service":
			yearly = -int(float(LTMoney.dollars(2400.0)) * 12.0 * (value - old))
			hits = "Commuters and households without a car. Riders pay a small fare to the city instead of gas money to the outside. Cost about %s a year." % LTMoney.fmt(-yearly)
		"bank_charter":
			hits = "A Sim with finance skill may start a local bank. Its loans keep interest in town, and its losses fall on a local owner."
		"hunting_season":
			hits = "Hunters, guides and outfitters, and the visitors who come for deer and pheasant in the fall. Closing it keeps the wildlife undisturbed and the woods quiet."
		"mining":
			hits = "Quarries and gold mines bring good wages and work for the region, and dust, noise, runoff and injuries with them. A gold mine is a boom: the ore runs out and the price swings."
		"lot_coverage":
			hits = "Families adding on to their houses and businesses expanding. A tight limit keeps yards open and light between houses; more families will need a variance from you to add a bedroom or a garage. A loose one lets them build out."
		"transfer_tax":
			var sold: int = int(w.city.get("sales_12m", 0))
			yearly = int(float(sold) * (value - old))
			hits = "Everyone who sells land or a house, investors and builders most of all. A higher tax brings in more each sale but makes flipping less worth it. About %s of sales in the last year, so this changes city income by about %s a year." % [LTMoney.fmt(sold), LTMoney.fmt(yearly)]
	return {"hits": hits, "yearly": yearly}


## A sale between owners: the buyer pays the seller, then the seller pays the
## city's transfer tax. A sale by the city itself pays no tax to itself.
static func property_sale(w: LTWorld, buyer_acct: String, seller_acct: String, price: int, lot_id: int) -> int:
	var paid: int = w.ledger.pay(buyer_acct, seller_acct, price, "property_sales")
	return transfer_tax(w, seller_acct, paid, lot_id)


## The seller's share to the city on a sale that already changed hands.
static func transfer_tax(w: LTWorld, seller_acct: String, paid: int, lot_id: int) -> int:
	w.city["sales_12m"] = int(w.city.get("sales_12m", 0)) + paid
	var tax: int = 0
	if seller_acct != "city":
		var rate: float = float(w.city["laws"].get("transfer_tax", 0.005))
		tax = w.ledger.pay(seller_acct, "city", int(float(paid) * rate), "transfer_tax")
	var l: Dictionary = w.lot(lot_id)
	if not l.is_empty():
		l["last_sale"] = paid
		l["last_sale_day"] = w.day
		l.erase("for_sale")
	return tax


## The account of whoever owns a lot right now.
static func owner_acct(w: LTWorld, l: Dictionary) -> String:
	match str(l["owner_kind"]):
		"city":
			return "city"
		"sim":
			var o: Dictionary = w.cit(int(l["owner_id"]))
			return w.acct_p(o) if not o.is_empty() else "outside"
		"business":
			var b: Dictionary = w.biz(int(l["owner_id"]))
			return w.acct_b(b) if not b.is_empty() else "outside"
	return "outside"


static func set_law(w: LTWorld, key: String, value) -> Dictionary:
	if not LAWS.has(key):
		return {"ok": false, "message": "Unknown law."}
	if key == "bank_charter" and float(value) > 0.0 and w.alive_count() < 120:
		return {"ok": false, "message": "The state will not charter a bank for a town under 120 people. The town has %d." % w.alive_count()}
	var cfg: Dictionary = LAWS[key]
	var v: float = clampf(float(value), float(cfg["min"]), float(cfg["max"]))
	var old: float = float(w.city["laws"][key])
	if is_equal_approx(v, old):
		return {"ok": false, "message": "No change."}
	var est: Dictionary = law_estimate(w, key, v)
	if key == "min_wage":
		w.city["laws"][key] = int(v)
		# existing local wages below the new floor go up, the owner pays it
		for c in w.citizens:
			if w.is_present(c) and ["business", "city"].has(str(c["job"]["kind"])) and int(c["job"]["daily_wage"]) < int(v) * 8:
				c["job"]["daily_wage"] = int(v) * 8
				w.log_sim(c, "Got a raise to %s a day because the city raised the minimum wage." % LTMoney.fmt(int(v) * 8), true)
		for b in w.businesses:
			if str(b["status"]) == "open" and int(b["wage"]) < int(v) * 8:
				b["wage"] = int(v) * 8
	else:
		w.city["laws"][key] = v
	var entry: Dictionary = {"day": w.day, "law": key, "label": cfg["label"], "old": old, "new": v, "estimate": est, "baseline": _law_baseline(w, key), "tracked": []}
	w.laws_log.append(entry)
	w.chronicle_add("The mayor changed %s from %s to %s. Expected: %s" % [str(cfg["label"]).to_lower(), law_text(key, old), law_text(key, v), est["hits"]], "law", true, [])
	return {"ok": true, "message": "Passed. %s" % est["hits"]}


static func law_text(key: String, v: float) -> String:
	var cfg: Dictionary = LAWS[key]
	if cfg.get("money", false):
		return LTMoney.fmt_exact(int(v))
	if cfg.get("pct", false):
		return "%.1f%%" % (v * 100.0)
	return "%.1f" % v


static func _law_baseline(w: LTWorld, key: String) -> Dictionary:
	var s: Dictionary = w.snapshot()
	return {"income_12m": int(w.city["income_12m"]), "spend_12m": int(w.city["spend_12m"]), "unemployment": s["unemployment"], "businesses": s["businesses_open"], "happiness": s["happiness"], "local_jobs": s["local_jobs"]}


static func _track_laws(w: LTWorld) -> void:
	var s: Dictionary = w.snapshot()
	for e in w.laws_log:
		var months: int = (w.day - int(e["day"])) / 30
		if months < 1 or months > 24:
			continue
		var b: Dictionary = e["baseline"]
		var t: String = "After %d month(s): city income %s a year (was %s), unemployment %d%% (was %d%%), %d businesses open (was %d), %d local jobs (was %d)." % [months, LTMoney.fmt(int(w.city["income_12m"])), LTMoney.fmt(int(b["income_12m"])), int(float(s["unemployment"]) * 100.0), int(float(b["unemployment"]) * 100.0), s["businesses_open"], b["businesses"], s["local_jobs"], b["local_jobs"]]
		e["tracked"].append(t)
		if e["tracked"].size() > 6:
			e["tracked"].remove_at(0)


static func approval(w: LTWorld) -> float:
	var t: float = 0.0
	var n: int = 0
	for c in w.citizens:
		if w.is_present(c) and w.age_years(c) >= 18:
			t += float(c["trust_city"]) * 0.6 + LTPeople.happiness(c) * 0.4
			n += 1
	return 0.0 if n == 0 else t / float(n)


# ================================================================ bus, shelter, fires

const BUS_FARE: int = 250


static func bus_available(w: LTWorld) -> bool:
	return float(w.city["laws"].get("bus_service", 0.0)) > 0.0


## Riders: anyone without a car, and others when the fare beats gas and the drive is long.
static func bus_rider(w: LTWorld, c: Dictionary) -> bool:
	if not bus_available(w):
		return false
	var h: Dictionary = w.hh(int(c["household"]))
	if not bool(h["car"]):
		return true
	return float(c["traits"]["discipline"]) > 55.0 or w.cash(c) < LTMoney.dollars(300.0)


## The welfare law funds shelter beds; a kind Sim may also open their church hall.
static func shelter_bed(w: LTWorld, c: Dictionary) -> bool:
	if law(w, "welfare") >= 0.5:
		w.city["shelter_nights"] = int(w.city.get("shelter_nights", 0)) + 1
		return true
	return w.city.get("charity_shelter", -1) >= 0


# ================================================================ city bonds

static func issue_bond(w: LTWorld, amount: int, purpose: String) -> Dictionary:
	if amount < LTMoney.dollars(50000.0):
		return {"ok": false, "message": "Bonds start at $50,000."}
	var rating: String = LTFinance.city_credit_rating(w)
	if rating == "C":
		return {"ok": false, "message": "Investors will not buy bonds from a city rated C."}
	var rate: float = 0.038 + (0.0 if rating == "A" else 0.012) + (1.0 - LTRegion.index(w)) * 0.02 - (LTGov.factor(w, "finance_officer") - 1.0) * 0.05
	var d: Dictionary = LTFinance.new_debt(w, "city", 0, "bondholders", -1, "city_bond", amount, rate, 240, "", -1, [])
	w.ledger.pay("outside", "city", amount, "bond_sales")
	w.city["bonds"].append(int(d["id"]))
	w.chronicle_add("The city sold %s in 20 year bonds at %.1f%% for %s. Payments are %s a month to bondholders outside town." % [LTMoney.fmt(amount), rate * 100.0, purpose, LTMoney.fmt(int(d["payment"]))], "city", true, [])
	return {"ok": true, "message": "Sold %s in bonds at %.1f%%. %s a month for 20 years." % [LTMoney.fmt(amount), rate * 100.0, LTMoney.fmt(int(d["payment"]))]}


# ================================================================ the weekly paper

static func newspaper(w: LTWorld) -> void:
	var week: Array = []
	for i in range(w.chronicle.size() - 1, -1, -1):
		var e: Dictionary = w.chronicle[i]
		if int(e["day"]) <= w.day - 7:
			break
		week.append(e)
	if week.is_empty():
		return
	week.sort_custom(func(a, b): return _news_weight(a) > _news_weight(b))
	var editor: Dictionary = {}
	var best: float = -1.0
	for c in w.citizens:
		if w.is_present(c) and w.age_years(c) >= 25:
			var sc: float = float(c["skills"]["teaching"]) + float(c["traits"]["sociability"]) * 0.5 + float(c["traits"]["honesty"]) * 0.3
			if sc > best:
				best = sc
				editor = c
	var lead: Dictionary = week[0]
	var stories: Array = []
	for e in week.slice(0, 7):
		stories.append({"day": int(e["day"]), "text": str(e["text"]), "kind": str(e["kind"]), "refs": e["refs"]})
	var s: Dictionary = w.snapshot()
	var editorial: String = _editorial(w, s)
	var edition: Dictionary = {"day": w.day, "number": w.city["newspapers"].size() + 1, "headline": _headline(lead), "stories": stories, "editor": int(editor.get("id", -1)), "editorial": editorial, "approval": int(approval(w))}
	w.city["newspapers"].append(edition)
	if w.city["newspapers"].size() > 120:
		w.city["newspapers"].remove_at(0)


static func _news_weight(e: Dictionary) -> int:
	return {"bankruptcy": 9, "business": 8, "death": 7, "crime": 7, "protest": 8, "region": 6, "project": 6, "law": 6, "petition": 5, "estate": 5, "election": 10, "birth": 3, "family": 4, "health": 4, "housing": 4, "city": 5}.get(str(e["kind"]), 2) + (3 if bool(e["important"]) else 0)


static func _headline(e: Dictionary) -> String:
	var t: String = str(e["text"])
	var cut: int = t.find(".")
	if cut > 10:
		t = t.substr(0, cut)
	return t


static func _editorial(w: LTWorld, s: Dictionary) -> String:
	var worst: Dictionary = {}
	for p in w.petitions:
		if ["gathering", "submitted"].has(str(p["status"])) and (worst.is_empty() or float(p["strength"]) > float(worst["strength"])):
			worst = p
	var line: String = "Unemployment stands at %d%% and the city has %s in the bank." % [int(float(s["unemployment"]) * 100.0), LTMoney.fmt(int(s["city_cash"]))]
	if not worst.is_empty():
		line += " Readers keep asking about one thing: %s. %d neighbors have signed." % [str(worst["title"]).to_lower(), worst["signers"].size()]
	var cuts: Array = []
	for e in w.laws_log:
		if w.day - int(e["day"]) > 365 * 3 and str(e["law"]) == "school_funding" and float(e["new"]) < float(e["old"]):
			cuts.append(e)
	if not cuts.is_empty():
		line += " Teachers say the school cuts from years ago show in this year's graduates."
	return line


# ================================================================ elections (optional mode)

static func elections_daily(w: LTWorld) -> void:
	if not bool(w.city.get("elections", false)) or not bool(w.city.get("mayor_in_office", true)) or not bool(w.city.get("incorporated", true)):
		return
	var eday: int = int(w.city["next_election_day"])
	LTGov.sim_mayor_plans(w)
	if w.day == eday - 60:
		LTGov.before_election(w)
		if not bool(w.city.get("elections", false)):
			return
		_find_challenger(w)
	elif w.day == eday:
		_hold_election(w)
	# a recall if approval stays very low
	if LTCalendar.is_month_start(w.day):
		var a: float = approval(w)
		w.city["low_months"] = int(w.city.get("low_months", 0)) + 1 if a < 30.0 else 0
		if int(w.city["low_months"]) >= 6:
			w.city["low_months"] = 0
			w.chronicle_add("Citizens gathered enough signatures for a recall election. It will be held in 30 days.", "election", true, [])
			w.city["next_election_day"] = w.day + 30
			_find_challenger(w)


static func _find_challenger(w: LTWorld) -> void:
	var best: Dictionary = {}
	var bs: float = -1.0
	var open: bool = not LTGov.can_run(w)
	w.city["open_seat"] = open
	w.city.erase("second")
	var second: Dictionary = {}
	var ss: float = -1.0
	for c in w.citizens:
		if int(c["id"]) == LTGov.mayor_citizen(w):
			continue
		if open and w.is_present(c) and w.age_years(c) >= 25:
			# with nobody to run against, the race draws the town's natural leaders
			var sc2: float = float(c["traits"]["ambition"]) * 0.5 + float(c["traits"]["sociability"]) * 0.4 + float(c["rel"].size()) * 1.2 + w.rng.randf_range(0.0, 20.0)
			if sc2 > bs:
				second = best
				ss = bs
				bs = sc2
				best = c
			elif sc2 > ss:
				ss = sc2
				second = c
			continue
		if w.is_present(c) and w.age_years(c) >= 30:
			var sc: float = float(c["traits"]["ambition"]) * 0.5 + float(c["traits"]["sociability"]) * 0.4 + float(c["reputation"] if c.has("reputation") else 50) * 0.1 + (100.0 - float(c["trust_city"])) * 0.4
			if sc > bs:
				bs = sc
				best = c
	if best.is_empty():
		return
	var platform: String = "lower taxes and less waste"
	for p in w.petitions:
		if str(p["status"]) == "denied":
			platform = "doing what the city refused: %s" % str(p["title"]).to_lower()
	w.city["challenger"] = int(best["id"])
	w.city["platform"] = platform
	if open and not second.is_empty():
		w.city["second"] = int(second["id"])
		w.chronicle_add("Two run for the open mayor's seat: %s and %s. The election is in 60 days." % [w.full_name(best), w.full_name(second)], "election", true, [best["id"], second["id"]])
		return
	w.log_sim(best, "Announced a run for mayor on a platform of %s. Reason: ambition and frustration with city hall." % platform, true)
	w.chronicle_add("%s is running for mayor, promising %s. The election is in 60 days." % [w.full_name(best), platform], "election", true, [best["id"]])


static func _open_race(w: LTWorld) -> void:
	var a: Dictionary = w.cit(int(w.city.get("challenger", -1)))
	var b: Dictionary = w.cit(int(w.city.get("second", -1)))
	w.city["next_election_day"] = w.day + 365 * int(w.city["term_years"])
	w.city["open_seat"] = false
	if a.is_empty() or not w.is_present(a):
		a = b
		b = {}
	if a.is_empty() or not w.is_present(a):
		w.chronicle_add("Nobody ran for mayor. %s stays on until someone does." % w.player["name"], "election", true, [])
		return
	var va: int = 0
	var vb: int = 0
	for c in w.citizens:
		if not w.is_present(c) or w.age_years(c) < 18 or w.rng.randf() < 0.35:
			continue
		var sa: float = w.rng.randf_range(0.0, 30.0) + float(a["traits"]["sociability"]) * 0.2
		var sb: float = w.rng.randf_range(0.0, 30.0) + (float(b["traits"]["sociability"]) * 0.2 if not b.is_empty() else -999.0)
		if c["rel"].has(int(a["id"])):
			sa += float(c["rel"][int(a["id"])]["affection"]) * 0.4
		if not b.is_empty() and c["rel"].has(int(b["id"])):
			sb += float(c["rel"][int(b["id"])]["affection"]) * 0.4
		if sa >= sb:
			va += 1
		else:
			vb += 1
	var win: Dictionary = a if va >= vb else b
	var lose: Dictionary = b if va >= vb else a
	var total: int = maxi(1, va + vb)
	w.city["held_election"] = true
	w.chronicle_add("%s won the open race for mayor with %d%% of the vote%s." % [w.full_name(win), maxi(va, vb) * 100 / total, " against %s" % w.full_name(lose) if not lose.is_empty() else ""], "election", true, [win["id"]])
	LTGov.new_mayor(w, win, "won the open seat after %s reached the two term limit" % w.player["name"])


static func _hold_election(w: LTWorld) -> void:
	if bool(w.city.get("open_seat", false)):
		_open_race(w)
		return
	var yes: int = 0
	var no: int = 0
	var ch: Dictionary = w.cit(int(w.city.get("challenger", -1)))
	for c in w.citizens:
		if not w.is_present(c) or w.age_years(c) < 18:
			continue
		# voters weigh their trust in the city, their own life, and the challenger
		var v: float = float(c["trust_city"]) * 0.6 + LTPeople.happiness(c) * 0.3
		if not ch.is_empty() and c["rel"].has(int(ch["id"])):
			v -= float(c["rel"][int(ch["id"])]["affection"]) * 0.2
		v += w.rng.randf_range(-12.0, 12.0)
		if w.rng.randf() < 0.35:
			continue
		if v >= 45.0:
			yes += 1
		else:
			no += 1
	var total: int = maxi(1, yes + no)
	w.city["next_election_day"] = w.day + 365 * int(w.city["term_years"])
	var who: String = w.full_name(ch) if not ch.is_empty() else "the challenger"
	var first: bool = not bool(w.city.get("held_election", false))
	w.city["held_election"] = true
	if yes >= no:
		LTGov.g(w)["mayor_terms"] = int(LTGov.g(w)["mayor_terms"]) + 1
		w.chronicle_add("%s won %s with %d%% of the vote against %s." % [w.player.get("name", "The mayor"), "the town's first election" if first else "reelection", yes * 100 / total, who], "election", true, [])
	else:
		var was_player: bool = not LTMayorAI.is_on(w)
		w.chronicle_add("%s lost the election to %s, %d%% to %d%%.%s" % [w.player.get("name", "The mayor"), who, no * 100 / total, yes * 100 / total, " The town goes on with a new mayor, and you still live here." if was_player else ""], "election", true, [])
		if not ch.is_empty() and w.is_present(ch):
			LTGov.new_mayor(w, ch, "won the election on a platform of %s" % str(w.city.get("platform", "change")))
		else:
			w.city["mayor_in_office"] = false
