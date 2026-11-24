class_name LTPeople
extends RefCounted
## Sims: generation, needs, daily routine, decisions with plain reasons, life stages,
## family, births, deaths, and moving in and out of town.

const TRAIT_KEYS: Array = ["ambition", "risk", "discipline", "honesty", "sociability", "intelligence", "greed", "kindness"]
const NEED_KEYS: Array = ["hunger", "energy", "shelter", "health", "safety", "money_security", "social", "fun", "respect", "family"]
const SKILL_KEYS: Array = ["cooking", "retail", "farming", "construction", "repair", "medicine", "teaching", "management", "logistics", "finance"]
const FEMALE_FIRST: Array = ["Mary", "Anna", "Beth", "Carol", "Dana", "Emma", "Faith", "Grace", "Hannah", "Irene", "Jane", "Karen", "Laura", "Megan", "Nora", "Paula", "Rosa", "Sara", "Tina", "Vera", "Wendy", "Clara", "Diane", "Elsie", "Florence", "Gladys", "Harriet", "June", "Linda", "Mabel", "Ruth", "Alice", "Lucy", "Joan", "Ida", "Opal"]
const MALE_FIRST: Array = ["James", "John", "Robert", "Michael", "David", "William", "Richard", "Joseph", "Thomas", "Charles", "Daniel", "Matthew", "Anthony", "Mark", "Donald", "Steven", "Paul", "Andrew", "Joshua", "Kenneth", "Kevin", "Brian", "George", "Timothy", "Ronald", "Edward", "Jeffrey", "Ryan", "Jacob", "Gary", "Walt", "Hank", "Leon", "Earl", "Glen", "Roy"]
const LAST_NAMES: Array = ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson", "Thomas", "Taylor", "Moore", "Jackson", "Martin", "Lee", "Perez", "Thompson", "White", "Harris", "Sanchez", "Clark", "Ramirez", "Lewis", "Robinson", "Olson", "Larson", "Nelson", "Hanson", "Peterson", "Berg", "Lund", "Schmidt", "Weber", "Fischer"]
const OUTSIDE_JOBS: Array = [
	{"title": "factory worker", "wage": 168.0, "skill": "repair"},
	{"title": "warehouse worker", "wage": 152.0, "skill": "logistics"},
	{"title": "truck driver", "wage": 216.0, "skill": "logistics"},
	{"title": "office clerk", "wage": 152.0, "skill": "finance"},
	{"title": "farm hand", "wage": 136.0, "skill": "farming"},
	{"title": "construction laborer", "wage": 176.0, "skill": "construction"},
	{"title": "nursing aide", "wage": 144.0, "skill": "medicine"},
	{"title": "store clerk", "wage": 120.0, "skill": "retail"},
	{"title": "line cook", "wage": 128.0, "skill": "cooking"},
]
const COMMUTE_COST_DAILY: int = 700
const FOOD_DAILY_ADULT: int = 900
const FOOD_DAILY_CHILD: int = 550
const PENSION_MONTHLY: int = 190000   # about the average Social Security check in 2026


# ================================================================ generation

static func generate_town(w: LTWorld) -> void:
	var units: Array = []
	var cols: int = int(w.config["lot_cols"])
	var res_lots: Array = []
	for l in w.lots:
		if str(l["zone"]) == "residential":
			res_lots.append(l)
	var house_n: int = int(w.config["house_lots"])
	var apt_n: int = int(w.config["apartment_lots"])
	var apt_units: int = int(w.config["apartment_units"])
	var idx: int = 0
	for l in res_lots:
		if idx < house_n:
			l["use"] = "house"
			l["building"] = "house"
			l["value"] = LTMoney.dollars(w.rng.randf_range(135000.0, 195000.0))
			l["units"] = [-1]
			l["condition"] = w.rng.randf_range(55.0, 92.0)
			l["built_day"] = -w.rng.randi_range(5, 60) * 365
			units.append({"lot": int(l["id"]), "unit": 0, "kind": "house"})
		elif idx < house_n + apt_n:
			l["use"] = "apartment"
			l["building"] = "apartment"
			l["value"] = LTMoney.dollars(w.rng.randf_range(380000.0, 520000.0))
			var u: Array = []
			for k in apt_units:
				u.append(-1)
				units.append({"lot": int(l["id"]), "unit": k, "kind": "apartment"})
			l["units"] = u
			l["unit_rent"] = LTMoney.dollars(w.rng.randf_range(720.0, 940.0))
			l["condition"] = w.rng.randf_range(45.0, 88.0)
			l["built_day"] = -w.rng.randi_range(10, 50) * 365
			l["owner_kind"] = "outside"
			l["owner_id"] = -1
			l["name"] = "Plains Property Group apartments"
		idx += 1
	# households until the target is met or housing runs out
	var target_pop: int = int(w.config["target_population"])
	var target_hh: int = int(w.config["target_households"])
	var unit_i: int = 0
	while unit_i < units.size() and w.households.size() < target_hh and w.alive_count() < target_pop + 4:
		var u: Dictionary = units[unit_i]
		var family_bias: bool = str(u["kind"]) == "house"
		var h: Dictionary = make_household(w, family_bias, false)
		move_household_into(w, h, int(u["lot"]), int(u["unit"]))
		unit_i += 1
	# house owners and their mortgages, renters and their landlords
	for h in w.households:
		var l: Dictionary = w.lot(int(h["lot"]))
		if str(l["use"]) == "house":
			_setup_owner(w, h, l)
			# what the house is: built long ago, roughly for the family living there
			var ad: int = w.household_adults(h).size()
			var kids: int = w.household_members(h).size() - ad
			l["home"] = LTGeography.choose_home(w, maxi(1, ad), kids, LTMoney.dollars(w.rng.randf_range(35000.0, 90000.0)), w.rng.randf_range(20.0, 80.0), w.rng.randf_range(20.0, 80.0), l, LTMoney.dollars(w.rng.randf_range(260000.0, 450000.0)))
		else:
			h["tenure"] = "rent"
			h["rent"] = int(l["unit_rent"])
	# two apartment buildings belong to well off Sims who run them as landlords
	_seed_sim_landlords(w)
	for h in w.households:
		for m in w.household_members(h):
			_seed_finances(w, m)
	# a few couples are already expecting when the game starts
	for c in w.citizens:
		var a: int = w.age_years(c)
		if str(c["sex"]) == "F" and a >= 20 and a <= 40 and int(c["spouse"]) >= 0 and w.rng.randf() < 0.08:
			LTHealth.conceive(w, c, w.cit(int(c["spouse"])), "they wanted another child")
			c["pregnant"]["due"] = w.rng.randi_range(10, 260)


static func _setup_owner(w: LTWorld, h: Dictionary, l: Dictionary) -> void:
	var adults: Array = w.household_adults(h)
	if adults.is_empty():
		return
	adults.sort_custom(func(a, b): return w.age_years(a) > w.age_years(b))
	var head: Dictionary = adults[0]
	l["owner_kind"] = "sim"
	l["owner_id"] = int(head["id"])
	h["tenure"] = "own"
	h["rent"] = 0
	var age: int = w.age_years(head)
	if age < 68 or w.rng.randf() < 0.25:
		var years_paid: float = clampf(float(age - 28) / 30.0, 0.0, 0.85) * w.rng.randf_range(0.5, 1.0)
		var bal: int = int(float(l["value"]) * 0.85 * (1.0 - years_paid))
		if bal > LTMoney.dollars(5000.0):
			var joint: Array = []
			if adults.size() > 1 and int(adults[1]["spouse"]) == int(head["id"]):
				joint = [int(adults[1]["id"])]
			var d: Dictionary = LTFinance.new_debt(w, "p", int(head["id"]), "bank", -1, "mortgage", bal, 0.058, 360, "house", int(l["id"]), joint)
			d["original"] = int(float(l["value"]) * 0.85)
			h["mortgage"] = int(d["id"])
			w.log_sim(head, "Owns the house on %s with a mortgage of %s from Prairie State Bank." % [LTGeography.lot_label(w, int(l["id"])), LTMoney.fmt(bal)], true)
	else:
		w.log_sim(head, "Owns the house on %s outright." % LTGeography.lot_label(w, int(l["id"])), true)


static func _seed_sim_landlords(w: LTWorld) -> void:
	var apts: Array = []
	for l in w.lots:
		if str(l["use"]) == "apartment":
			apts.append(l)
	var candidates: Array = []
	for c in w.citizens:
		var a: int = w.age_years(c)
		if a >= 45 and a <= 75 and str(w.hh(int(c["household"]))["tenure"]) == "own":
			candidates.append(c)
	candidates.sort_custom(func(a, b): return int(a["traits"]["ambition"]) + int(a["traits"]["greed"]) > int(b["traits"]["ambition"]) + int(b["traits"]["greed"]))
	var n: int = mini(2, mini(apts.size(), candidates.size()))
	for i in n:
		var owner: Dictionary = candidates[i]
		var l: Dictionary = apts[i]
		LTEconomy.create_landlord(w, owner, l)


## The wife's age in a married couple, following the age mix of US married women.
static func _married_age(w: LTWorld) -> int:
	var r: float = w.rng.randf()
	if r < 0.17:
		return w.rng.randi_range(23, 34)
	if r < 0.35:
		return w.rng.randi_range(35, 44)
	if r < 0.53:
		return w.rng.randi_range(45, 54)
	if r < 0.74:
		return w.rng.randi_range(55, 64)
	if r < 0.90:
		return w.rng.randi_range(65, 74)
	return w.rng.randi_range(75, 85)


## A household of a given shape: one or two adults (a couple if two) and some
## children, for settlers who planned their house around their family.
static func make_family(w: LTWorld, adults: int, kids: int) -> Dictionary:
	var hid: int = w.households.size()
	var h: Dictionary = {"id": hid, "members": [], "lot": -1, "unit": -1, "tenure": "none", "rent": 0, "rent_late": 0, "mortgage": -1, "pantry": 3.0, "car": true, "moved_in": w.day, "last_grocery": "", "shop_habit": -1, "evicted_day": -1}
	w.households.append(h)
	var last_name: String = LAST_NAMES[w.rng.randi_range(0, LAST_NAMES.size() - 1)]
	var wa: int = w.rng.randi_range(24, 46) if kids > 0 else w.rng.randi_range(23, 60)
	var a: Dictionary = make_adult(w, hid, last_name, "F" if adults == 2 or w.rng.randf() < 0.7 else "M", wa)
	var b: Dictionary = {}
	if adults >= 2:
		b = make_adult(w, hid, last_name, "M", clampi(wa + w.rng.randi_range(-3, 5), 21, 80))
		a["spouse"] = int(b["id"])
		b["spouse"] = int(a["id"])
		_relate(a, b, "spouse", 70.0, 75.0)
		_relate(b, a, "spouse", 70.0, 75.0)
	for k in kids:
		var ka: int = clampi(w.rng.randi_range(0, 17), 0, maxi(0, wa - 20))
		make_child(w, hid, last_name, ka, a, b)
	for m in w.household_members(h):
		_seed_finances(w, m)
	return h


## `settler` households are the ones who move to a brand new town to build a house:
## mostly younger couples and families, as on any real frontier.
static func make_household(w: LTWorld, family_bias: bool, immigrant: bool, settler: bool = false) -> Dictionary:
	var hid: int = w.households.size()
	var h: Dictionary = {"id": hid, "members": [], "lot": -1, "unit": -1, "tenure": "none", "rent": 0, "rent_late": 0, "mortgage": -1, "pantry": 3.0, "car": true, "moved_in": w.day, "last_grocery": "", "shop_habit": -1, "evicted_day": -1}
	w.households.append(h)
	var last_name: String = LAST_NAMES[w.rng.randi_range(0, LAST_NAMES.size() - 1)]
	# household types and ages follow the US census mix for a small midwestern town:
	# about 47% married couples (a third with children at home), 9% single parents,
	# 28% living alone (40% of those over 65), the rest unrelated adults sharing a home
	var roll: int = w.rng.randi_range(0, 99)
	if family_bias:
		roll = w.rng.randi_range(0, 71)
	if settler:
		roll = w.rng.randi_range(0, 99)
		roll = 0 if roll < 65 else (50 if roll < 78 else 60)
	if roll < 47:
		var wa: int = _married_age(w) if not settler else w.rng.randi_range(24, 50)
		var ha: int = clampi(wa + w.rng.randi_range(-3, 5), 21, 92)
		var a: Dictionary = make_adult(w, hid, last_name, "F", wa)
		var b: Dictionary = make_adult(w, hid, last_name, "M", ha)
		a["spouse"] = int(b["id"])
		b["spouse"] = int(a["id"])
		_relate(a, b, "spouse", 70.0, 75.0)
		_relate(b, a, "spouse", 70.0, 75.0)
		var p_kids: float = 0.7 if wa < 45 else (0.25 if wa < 55 else 0.0)
		var kids: int = 0
		if w.rng.randf() < p_kids:
			kids = [1, 1, 1, 2, 2, 2, 3, 4][w.rng.randi_range(0, 7)]
		for k in kids:
			var ka: int = w.rng.randi_range(0, 17)
			if wa - ka < 20:
				ka = maxi(0, wa - w.rng.randi_range(20, 30))
			make_child(w, hid, last_name, ka, a, b)
	elif roll < 56:
		var sex: String = "F" if w.rng.randf() < 0.78 else "M"
		var pa: int = w.rng.randi_range(22, 55)
		var p: Dictionary = make_adult(w, hid, last_name, sex, pa)
		for k in w.rng.randi_range(1, 2):
			var ka2: int = w.rng.randi_range(0, 17)
			if pa - ka2 < 19:
				ka2 = maxi(0, pa - w.rng.randi_range(19, 30))
			make_child(w, hid, last_name, ka2, p, {})
	elif roll < 72:
		var sx: String = "F" if w.rng.randf() < 0.5 else "M"
		make_adult(w, hid, last_name, sx, w.rng.randi_range(19, 64))
	elif roll < 84:
		# living alone over 65, more often a widow
		var s3: String = "F" if w.rng.randf() < 0.68 else "M"
		make_adult(w, hid, last_name, s3, w.rng.randi_range(65, 92))
	else:
		# two unrelated adults sharing a home: roommates or an unmarried couple
		var r1: String = "F" if w.rng.randf() < 0.5 else "M"
		var aa: int = w.rng.randi_range(19, 45)
		make_adult(w, hid, last_name, r1, aa)
		var ln2: String = LAST_NAMES[w.rng.randi_range(0, LAST_NAMES.size() - 1)]
		make_adult(w, hid, ln2, "M" if r1 == "F" and w.rng.randf() < 0.6 else r1, clampi(aa + w.rng.randi_range(-5, 5), 19, 60))
	if immigrant:
		for m in w.household_members(h):
			_seed_finances(w, m)
	return h


static func _blank_citizen(w: LTWorld, hid: int, last_name: String, sex: String, age: int) -> Dictionary:
	var first: String
	if sex == "F":
		first = FEMALE_FIRST[w.rng.randi_range(0, FEMALE_FIRST.size() - 1)]
	else:
		first = MALE_FIRST[w.rng.randi_range(0, MALE_FIRST.size() - 1)]
	var c: Dictionary = {
		"id": w.citizens.size(), "first_name": first, "last_name": last_name, "sex": sex,
		"age_days": age * 365 + w.rng.randi_range(0, 364), "alive": true, "left_town": false,
		"death_day": -1, "death_cause": "", "household": hid, "spouse": -1, "mother": -1, "father": -1, "children": [],
		"traits": {}, "needs": {}, "weights": {}, "skills": {}, "education": 0.0,
		"health_cond": "", "sick_days": 0, "chronic": false,
		"job": {"kind": "none", "employer": -1, "title": "", "daily_wage": 0, "since": 0, "skill": ""},
		"student": "none", "retired": false, "homeless": false,
		"credit": {"has_file": false, "months": 0, "on_time": 0, "late": 0, "collections": 0, "chargeoffs": 0, "bankruptcy_day": -99999, "inquiries": [], "score": 0},
		"trust_city": 50.0, "history": [], "memory": [], "rel": {},
		"intent": {}, "owns": [], "bk": {}, "days_unemployed": 0, "signed": [],
		"theft_record": 0, "last_decision": "", "looks": {},
		"moved_in": w.day, "outside_debt_note": "",
	}
	c["looks"] = {"height": w.rng.randf_range(0.92, 1.08), "build": w.rng.randf_range(0.85, 1.2), "skin": w.rng.randi_range(0, 5), "hair": w.rng.randi_range(0, 6)}
	w.citizens.append(c)
	w.hh(hid)["members"].append(int(c["id"]))
	w.ledger.open(w.acct_p(c))
	for k in NEED_KEYS:
		c["needs"][k] = w.rng.randf_range(60.0, 92.0)
		c["weights"][k] = w.rng.randf_range(0.8, 1.2)
	c["weights"]["hunger"] = 1.6
	c["weights"]["shelter"] = 1.4
	c["weights"]["health"] = 1.4
	return c


static func make_adult(w: LTWorld, hid: int, last_name: String, sex: String, age: int) -> Dictionary:
	var c: Dictionary = _blank_citizen(w, hid, last_name, sex, age)
	for k in TRAIT_KEYS:
		c["traits"][k] = clampi(int(round(w.rng.randfn(50.0, 20.0))), 2, 98)
	c["education"] = clampf(w.rng.randfn(55.0, 15.0) + float(c["traits"]["intelligence"] - 50) * 0.3, 15.0, 95.0)
	_roll_skills(w, c, age)
	return c


static func make_child(w: LTWorld, hid: int, last_name: String, age: int, pa: Dictionary, pb: Dictionary) -> Dictionary:
	var sex: String = "F" if w.rng.randf() < 0.5 else "M"
	var c: Dictionary = _blank_citizen(w, hid, last_name, sex, age)
	_unique_first_name(w, c)
	inherit_traits(w, c, pa, pb)
	c["education"] = clampf(float(age) * 3.6 + float(c["traits"]["intelligence"] - 50) * 0.2, 0.0, 70.0)
	_roll_skills(w, c, age)
	if str(pa.get("sex", "F")) == "F":
		c["mother"] = int(pa["id"])
		if not pb.is_empty():
			c["father"] = int(pb["id"])
	else:
		c["father"] = int(pa["id"])
		if not pb.is_empty():
			c["mother"] = int(pb["id"])
	pa["children"].append(int(c["id"]))
	_relate(pa, c, "child", 80.0, 90.0)
	_relate(c, pa, "parent", 75.0, 85.0)
	if not pb.is_empty():
		pb["children"].append(int(c["id"]))
		_relate(pb, c, "child", 80.0, 90.0)
		_relate(c, pb, "parent", 75.0, 85.0)
	return c


## Families rarely reuse a first name inside one household.
static func _unique_first_name(w: LTWorld, c: Dictionary) -> void:
	var taken: Array = []
	for mid in w.hh(int(c["household"]))["members"]:
		if int(mid) != int(c["id"]):
			taken.append(str(w.cit(int(mid))["first_name"]))
	var pool: Array = FEMALE_FIRST if str(c["sex"]) == "F" else MALE_FIRST
	var tries: int = 0
	while taken.has(str(c["first_name"])) and tries < 20:
		c["first_name"] = pool[w.rng.randi_range(0, pool.size() - 1)]
		tries += 1


static func inherit_traits(w: LTWorld, c: Dictionary, pa: Dictionary, pb: Dictionary) -> void:
	for k in TRAIT_KEYS:
		var base: float = float(pa["traits"].get(k, 50))
		if not pb.is_empty():
			base = (base + float(pb["traits"].get(k, 50))) / 2.0
		c["traits"][k] = clampi(int(round(base * 0.5 + w.rng.randfn(50.0, 18.0) * 0.5)), 2, 98)


static func _roll_skills(w: LTWorld, c: Dictionary, age: int) -> void:
	for k in SKILL_KEYS:
		if age < 13:
			c["skills"][k] = w.rng.randf_range(0.0, 6.0)
		elif age < 18:
			c["skills"][k] = w.rng.randf_range(0.0, 20.0)
		else:
			c["skills"][k] = clampf(w.rng.randf_range(0.0, 30.0) + float(c["education"]) * 0.15 + float(mini(age - 18, 25)) * 0.4, 0.0, 85.0)
	if age >= 18:
		var picks: int = 2 if age > 30 else 1
		for i in picks:
			var best: String = SKILL_KEYS[w.rng.randi_range(0, SKILL_KEYS.size() - 1)]
			c["skills"][best] = clampf(float(c["skills"][best]) + w.rng.randf_range(20.0, 45.0), 0.0, 96.0)


static func _seed_finances(w: LTWorld, c: Dictionary) -> void:
	var age: int = w.age_years(c)
	var t: Dictionary = c["traits"]
	if age < 18:
		if age >= 5:
			c["student"] = "outside school"
		return
	var cr: Dictionary = c["credit"]
	cr["has_file"] = age >= 20 or w.rng.randf() < 0.4
	cr["months"] = maxi(0, (age - 19) * 12) if bool(cr["has_file"]) else 0
	cr["on_time"] = int(float(cr["months"]) * (0.6 + float(t["discipline"]) / 250.0))
	cr["late"] = int(float(cr["months"]) * maxf(0.0, (55.0 - float(t["discipline"])) / 400.0))
	if w.rng.randf() < maxf(0.0, (45.0 - float(t["discipline"])) / 150.0):
		cr["collections"] = 1
	var savings: float = w.rng.randf_range(200.0, 1500.0) + float(age - 18) * w.rng.randf_range(80.0, 400.0) * (0.4 + float(t["discipline"]) / 100.0)
	if float(t["discipline"]) < 30 and float(t["risk"]) > 60:
		savings *= 0.3
	if age >= 65:
		savings += w.rng.randf_range(4000.0, 40000.0)
		c["retired"] = true
		w.log_sim(c, "Retired. Lives on a pension and savings.", true)
	w.ledger.pay("outside", w.acct_p(c), LTMoney.dollars(savings), "starting_savings")
	if age < 65:
		var employ_p: float = 0.8 + float(t["discipline"] - 50) / 250.0 + float(c["education"] - 50) / 300.0
		if w.rng.randf() < employ_p:
			var j: Dictionary = pick_outside_job(w, c)
			set_job(w, c, "outside", -1, str(j["title"]), _outside_wage(w, c, j), str(j["skill"]))
			w.log_sim(c, "Works outside town as a %s and drives %d minutes each way. Reason: there are no local jobs yet." % [c["job"]["title"], int(w.minutes_to_outside(int(w.hh(int(c["household"]))["lot"])))], true)
		else:
			c["days_unemployed"] = w.rng.randi_range(5, 120)
			w.log_sim(c, "Starts with no job. Reason: no employer in reach has hired them yet.", true)
	# consumer debts
	var debt_p: float = 0.25 + float(t["risk"]) / 250.0 + float(t["greed"]) / 300.0 - float(t["discipline"]) / 300.0
	if bool(cr["has_file"]) and w.rng.randf() < debt_p:
		var amt: float = w.rng.randf_range(800.0, 7000.0) * (0.6 + float(t["risk"]) / 100.0)
		var d: Dictionary = LTFinance.new_debt(w, "p", int(c["id"]), "bank", -1, "credit_card", LTMoney.dollars(amt), 0.229, 0, "", -1, [])
		d["limit"] = LTMoney.dollars(maxf(amt * 1.3, 3000.0))
	if bool(cr["has_file"]) and age < 70 and w.rng.randf() < 0.35:
		var car: float = w.rng.randf_range(4000.0, 19000.0)
		LTFinance.new_debt(w, "p", int(c["id"]), "bank", -1, "auto_loan", LTMoney.dollars(car), 0.079, 60, "vehicle", -1, [])
	LTFinance.refresh_score(w, c)


static func pick_outside_job(w: LTWorld, c: Dictionary) -> Dictionary:
	var best: Dictionary = OUTSIDE_JOBS[0]
	var best_s: float = -1e9
	for j in OUTSIDE_JOBS:
		if bool(c.get("disability", false)) and LTHealth.RISKY_JOBS.has(str(j["title"])):
			continue
		var s: float = float(c["skills"][str(j["skill"])]) + w.rng.randf_range(0.0, 30.0)
		if s > best_s:
			best_s = s
			best = j
	return best


static func _outside_wage(w: LTWorld, c: Dictionary, j: Dictionary) -> int:
	var sk: float = float(c["skills"][str(j["skill"])])
	# skill pays: a beginner starts at 80% of the going rate, a master earns 30% over it
	return LTMoney.dollars(float(j["wage"]) * (0.8 + sk / 200.0))


static func set_job(w: LTWorld, c: Dictionary, kind: String, employer: int, title: String, daily_wage: int, skill: String) -> void:
	c["job"] = {"kind": kind, "employer": employer, "title": title, "daily_wage": daily_wage, "since": w.day, "skill": skill}
	if kind == "outside":
		c["job"]["employer_name"] = LTRegion.employer_for(w, title)
	c["days_unemployed"] = 0


static func clear_job(w: LTWorld, c: Dictionary) -> void:
	c["job"] = {"kind": "none", "employer": -1, "title": "", "daily_wage": 0, "since": w.day, "skill": ""}


static func _relate(a: Dictionary, b: Dictionary, kind: String, trust: float, affection: float) -> void:
	a["rel"][int(b["id"])] = {"kind": kind, "trust": trust, "affection": affection}


static func relate_event(w: LTWorld, a: Dictionary, b: Dictionary, kind: String, d_trust: float, d_aff: float) -> void:
	var key: int = int(b["id"])
	if not a["rel"].has(key):
		if a["rel"].size() >= 16:
			var weakest: int = -1
			var wv: float = 1e9
			for k in a["rel"]:
				var r: Dictionary = a["rel"][k]
				if ["spouse", "child", "parent"].has(str(r["kind"])):
					continue
				var v: float = absf(float(r["affection"])) + absf(float(r["trust"]))
				if v < wv:
					wv = v
					weakest = int(k)
			if weakest < 0:
				return
			a["rel"].erase(weakest)
		a["rel"][key] = {"kind": kind, "trust": 50.0, "affection": 40.0}
	var rr: Dictionary = a["rel"][key]
	rr["trust"] = clampf(float(rr["trust"]) + d_trust, 0.0, 100.0)
	rr["affection"] = clampf(float(rr["affection"]) + d_aff, 0.0, 100.0)
	if ["acquaintance", "neighbor", "coworker"].has(str(rr["kind"])) and float(rr["affection"]) > 70.0:
		rr["kind"] = "friend"


# ================================================================ daily routine

static func morning(w: LTWorld) -> void:
	var is_school_day: bool = not LTCalendar.is_weekend(w.day) and not _summer_break(w.day)
	for c in w.citizens:
		if not w.is_present(c):
			continue
		var before_age: int = w.age_years(c)
		c["age_days"] = int(c["age_days"]) + 1
		var age: int = w.age_years(c)
		if age != before_age:
			_birthday(w, c, age)
		var n: Dictionary = c["needs"]
		n["hunger"] = float(n["hunger"]) - 30.0
		n["energy"] = float(n["energy"]) - 28.0
		n["social"] = float(n["social"]) - 5.0 * (0.5 + float(c["traits"]["sociability"]) / 100.0)
		n["fun"] = float(n["fun"]) - 5.0
		_illness(w, c, age)
		if age >= 5 and age < 18 and str(c["student"]) != "dropout":
			if is_school_day and int(c["sick_days"]) == 0:
				_school_day(w, c, age)
		if age >= 18 and not bool(c["retired"]):
			_work_day(w, c)
		if LTJustice.in_jail(w, c):
			continue
		if age >= 16 and (int(c["id"]) % 7 == w.day % 7 or bool(c.get("trigger", false))):
			c["trigger"] = false
			decide_weekly(w, c, age)
		_skills_fade(c)


static func _summer_break(day: int) -> bool:
	var m: int = LTCalendar.month_index(day)
	return m == 6 or m == 7


static func _birthday(w: LTWorld, c: Dictionary, age: int) -> void:
	if age == 18:
		c["student"] = "graduated" if str(c["student"]) != "dropout" else "dropout"
		var cr: Dictionary = c["credit"]
		w.log_sim(c, "Turned 18 with an education level of %d. Now an adult in the eyes of employers and lenders, with no credit history yet." % int(c["education"]), true)
		cr["has_file"] = false
		_roll_adult_skills(w, c)
	elif age == 5:
		c["student"] = "town school" if LTCivic.has_service(w, "school") else "outside school"
		w.log_sim(c, "Started school at the %s." % c["student"], true)
	elif age == 65 and not bool(c["retired"]):
		_consider_retirement(w, c)
	elif age > 65 and not bool(c["retired"]) and w.rng.randf() < 0.4:
		_consider_retirement(w, c)


static func _roll_adult_skills(w: LTWorld, c: Dictionary) -> void:
	var edu: float = float(c["education"])
	for k in SKILL_KEYS:
		c["skills"][k] = clampf(float(c["skills"][k]) + edu * 0.12 + w.rng.randf_range(0.0, 10.0), 0.0, 90.0)


static func _consider_retirement(w: LTWorld, c: Dictionary) -> void:
	var savings: int = w.cash(c)
	var score: float = float(savings) / 100.0 / 1000.0 + 20.0 - float(c["traits"]["ambition"]) * 0.2
	if str(c["job"]["kind"]) == "owner":
		score -= 15.0
	if score > 0.0 or w.age_years(c) >= 70:
		c["retired"] = true
		var title: String = str(c["job"]["title"])
		if str(c["job"]["kind"]) != "none" and str(c["job"]["kind"]) != "owner":
			LTEconomy.leave_job(w, c, "retired")
		w.log_sim(c, "Retired%s. Reason: has %s saved plus a pension, and the work was getting harder." % [" from " + title if title != "" else "", LTMoney.fmt(savings)], true)
	else:
		w.log_sim(c, "Kept working past 65. Reason: only %s saved, not enough to stop yet." % LTMoney.fmt(savings), true)


static func _illness(w: LTWorld, c: Dictionary, age: int) -> void:
	var n: Dictionary = c["needs"]
	if int(c["sick_days"]) > 0:
		c["sick_days"] = int(c["sick_days"]) - 1
		n["health"] = float(n["health"]) - 0.6
		if int(c["sick_days"]) == 0:
			c["health_cond"] = "chronic" if bool(c["chronic"]) else ""
		return
	var p: float = 0.0012
	if LTCalendar.season(w.day) == "Winter":
		p *= 2.2
	if age >= 70:
		p *= 2.0
	if age < 6:
		p *= 1.5
	if float(n["hunger"]) < 25.0:
		p *= 2.0
	if bool(c["homeless"]):
		p *= 3.0
	if float(n["health"]) < 40.0:
		p *= 1.8
	if w.rng.randf() < p:
		var serious: bool = w.rng.randf() < 0.12 + (0.15 if age >= 65 else 0.0)
		c["sick_days"] = w.rng.randi_range(8, 30) if serious else w.rng.randi_range(2, 6)
		c["health_cond"] = "serious illness" if serious else "sick"
		n["health"] = float(n["health"]) - (10.0 if serious else 3.0)
		if age >= 55 and serious and w.rng.randf() < 0.3:
			c["chronic"] = true
		LTCivic.seek_care(w, c, serious)


static func _school_day(w: LTWorld, c: Dictionary, age: int) -> void:
	var gain: float = 0.05
	var local: bool = LTCivic.has_service(w, "school")
	if local:
		if str(c["student"]) == "outside school":
			c["student"] = "town school"
			w.log_sim(c, "Moved to the new town school. No more long bus ride.", true)
		gain = 0.045 + 0.05 * LTCivic.school_quality(w)
	else:
		gain = 0.05 * (0.6 + 0.4 * LTCivic.school_quality(w))
		c["needs"]["energy"] = float(c["needs"]["energy"]) - 4.0
	gain *= 0.6 + float(c["traits"]["discipline"]) / 125.0
	if float(c["needs"]["hunger"]) < 30.0:
		gain *= 0.5
	c["education"] = minf(100.0, float(c["education"]) + gain)
	if w.rng.randf() < 0.004:
		c["traits"]["intelligence"] = clampi(int(c["traits"]["intelligence"]) + (1 if local or w.rng.randf() < 0.5 else 0), 0, 100)
	if age >= 15 and age <= 17 and str(c["student"]) != "dropout":
		var hunger_push: float = maxf(0.0, 40.0 - float(c["needs"]["money_security"])) * 0.02
		var p: float = (0.00008 + hunger_push * 0.0003) * (1.5 - float(c["traits"]["discipline"]) / 100.0)
		if w.rng.randf() < p:
			c["student"] = "dropout"
			w.log_sim(c, "Dropped out of school. Reason: low discipline and the family needs money now.", true)
			w.chronicle_add("%s dropped out of school at %d." % [w.full_name(c), age], "family", w.involves_watched([c["id"]]), [c["id"]])


static func _work_day(w: LTWorld, c: Dictionary) -> void:
	var job: Dictionary = c["job"]
	var kind: String = str(job["kind"])
	if kind == "none":
		c["days_unemployed"] = int(c["days_unemployed"]) + 1
		c["needs"]["respect"] = float(c["needs"]["respect"]) - 0.6
		return
	if LTCalendar.is_weekend(w.day) and kind != "owner":
		return
	if int(c["sick_days"]) > 0 or LTHealth.on_leave(w, c):
		return
	var sk: String = str(job["skill"])
	if sk != "":
		c["skills"][sk] = minf(100.0, float(c["skills"][sk]) + 0.03 * (0.5 + float(c["traits"]["intelligence"]) / 100.0))
	c["needs"]["respect"] = float(c["needs"]["respect"]) + 0.8
	c["needs"]["social"] = float(c["needs"]["social"]) + 5.0
	if kind == "outside":
		var hhl: int = int(w.hh(int(c["household"]))["lot"])
		var mins: float = w.minutes_to_outside(hhl) if hhl >= 0 else 30.0
		var bus: bool = LTCivic.bus_rider(w, c)
		c["needs"]["energy"] = float(c["needs"]["energy"]) - mins * (0.08 if bus else 0.12)
		c["needs"]["fun"] = float(c["needs"]["fun"]) - mins * 0.05
		if bus:
			w.ledger.pay(w.acct_p(c), "city", LTCivic.BUS_FARE, "bus_fares")
		else:
			w.ledger.pay(w.acct_p(c), "outside", COMMUTE_COST_DAILY, "commute_fuel")
		if not LTRegion.employer_open(w, str(job.get("employer_name", ""))):
			clear_job(w, c)
			return
		if w.rng.randf() < 0.00045 * LTRegion.layoff_mult(w):
			w.log_sim(c, "Lost the job as a %s. Reason: the outside employer cut staff." % job["title"], true)
			w.remember(c, "fired", -1, -20.0)
			clear_job(w, c)
			w.counters["layoffs"] = int(w.counters["layoffs"]) + 1
			w.chronicle_add("%s lost an outside job when the employer cut staff." % w.full_name(c), "work", w.involves_watched([c["id"]]), [c["id"]])


static func _skills_fade(c: Dictionary) -> void:
	var used: String = str(c["job"]["skill"])
	for k in SKILL_KEYS:
		if k != used and float(c["skills"][k]) > 30.0:
			c["skills"][k] = float(c["skills"][k]) - 0.002


static func evening(w: LTWorld) -> void:
	for h in w.households:
		var members: Array = w.household_members(h)
		if members.is_empty():
			continue
		var eat_need: float = 0.0
		for m in members:
			eat_need += 1.0
		var pantry: float = float(h["pantry"])
		var fed: float = 1.0
		if pantry >= eat_need:
			h["pantry"] = pantry - eat_need
		else:
			fed = pantry / maxf(eat_need, 1.0)
			h["pantry"] = 0.0
		var housed: bool = int(h["lot"]) >= 0
		var hspec: Dictionary = LTHomes.of(w, h) if housed else {}
		var crowd: float = (float(members.size()) / (LTHomes.capacity(hspec) if not hspec.is_empty() else (4.0 if str(w.lot(int(h["lot"])).get("use", "")) == "house" else 3.0))) if housed else 2.0
		if not hspec.is_empty():
			LTHomes.evening(w, h, members)
		var bills: int = monthly_bills(w, h)
		var cash_total: int = w.household_cash(h)
		for m in members:
			var n: Dictionary = m["needs"]
			n["hunger"] = float(n["hunger"]) + 34.0 * fed + (6.0 if fed >= 1.0 else 0.0)
			# a night's sleep: housed Sims wake rested, rough sleepers do not
			if LTJustice.in_jail(w, m):
				n["energy"] = maxf(float(n["energy"]) + 30.0, 55.0)
			elif housed:
				n["energy"] = maxf(float(n["energy"]) + 40.0, 72.0 if crowd <= 1.2 else 60.0)
				n["shelter"] = float(n["shelter"]) + (4.0 if crowd <= 1.0 else 1.0)
				if bool(h.get("shutoff", false)):
					n["shelter"] = float(n["shelter"]) - (12.0 if LTCalendar.season(w.day) == "Winter" else 5.0)
					n["energy"] = float(n["energy"]) - 8.0
			elif LTCivic.shelter_bed(w, m):
				n["energy"] = maxf(float(n["energy"]) + 32.0, 55.0)
				n["shelter"] = float(n["shelter"]) - 2.0
			else:
				n["energy"] = maxf(float(n["energy"]) + 25.0, 40.0)
				n["shelter"] = float(n["shelter"]) - 9.0
			if members.size() > 1:
				n["social"] = float(n["social"]) + 4.0
			var weekend: bool = LTCalendar.is_weekend(w.day)
			n["fun"] = float(n["fun"]) + 4.0 + (8.0 if weekend else 0.0) + float(m["traits"]["sociability"]) / 50.0
			if weekend and m["rel"].size() > 1:
				n["social"] = float(n["social"]) + 6.0 + float(m["traits"]["sociability"]) / 25.0
			var months_cover: float = float(cash_total) / maxf(float(bills), 1.0)
			var target: float = clampf(25.0 + months_cover * 22.0, 0.0, 100.0)
			if str(m["job"]["kind"]) != "none" or bool(m["retired"]):
				target += 10.0
			target -= LTFinance.debt_stress(w, m) * 30.0
			n["money_security"] = float(n["money_security"]) + clampf(target - float(n["money_security"]), -2.5, 2.5)
			n["safety"] = float(n["safety"]) + clampf(LTCivic.safety_level(w) - float(n["safety"]), -1.0, 1.0)
			_family_need(w, m)
			_health_drift(w, m)
			for k in NEED_KEYS:
				n[k] = clampf(float(n[k]), 0.0, 100.0)
		if LTCalendar.is_month_start(w.day):
			_monthly_household(w, h)


static func _family_need(w: LTWorld, c: Dictionary) -> void:
	var t: float = 70.0
	for kid_id in c["children"]:
		var kid: Dictionary = w.cit(int(kid_id))
		if w.is_present(kid) and w.age_years(kid) < 18:
			t = minf(t, (float(kid["needs"]["hunger"]) + float(kid["needs"]["health"])) / 2.0 + 10.0)
	if int(c["spouse"]) >= 0 and w.is_present(w.cit(int(c["spouse"]))):
		t += 10.0
	c["needs"]["family"] = float(c["needs"]["family"]) + clampf(t - float(c["needs"]["family"]), -2.0, 2.0)


static func _health_drift(w: LTWorld, c: Dictionary) -> void:
	var n: Dictionary = c["needs"]
	var age: int = w.age_years(c)
	var h: float = float(n["health"])
	if float(n["hunger"]) < 15.0:
		h -= 0.8
	elif float(n["hunger"]) < 30.0:
		h -= 0.2
	if float(n["energy"]) < 15.0:
		h -= 0.15
	if age >= 70:
		h -= 0.05 * float(age - 69) / 5.0
	if bool(c["chronic"]):
		h -= 0.04
	if int(c["sick_days"]) == 0 and float(n["hunger"]) > 50.0 and float(n["energy"]) > 40.0:
		h += 0.35
	var cap: float = 100.0 - maxf(0.0, float(age - 50)) * 0.8
	n["health"] = minf(h, cap)


static func monthly_bills(w: LTWorld, h: Dictionary) -> int:
	var members: Array = w.household_members(h)
	var food: int = 0
	for m in members:
		food += (FOOD_DAILY_ADULT if w.age_years(m) >= 18 else FOOD_DAILY_CHILD) * 30
	var util: int = utilities(w, h)
	var housing: int = int(h["rent"])
	if int(h["mortgage"]) >= 0:
		var d: Dictionary = w.debt(int(h["mortgage"]))
		if LTFinance.is_active(d):
			housing = int(d["payment"])
	return food + util + housing


static func utilities(w: LTWorld, h: Dictionary) -> int:
	var base: int = LTMoney.dollars(150.0)
	if LTCalendar.season(w.day) == "Winter":
		base = LTMoney.dollars(260.0)
	elif LTCalendar.season(w.day) == "Summer":
		base = LTMoney.dollars(180.0)
	return int(float(base) * LTHomes.utility_factor(w, LTHomes.of(w, h))) + w.household_members(h).size() * LTMoney.dollars(15.0)


static func _monthly_household(w: LTWorld, h: Dictionary) -> void:
	if int(h["lot"]) < 0:
		return
	# utilities go to the outside power and gas company; two short months and they shut it off
	var util: int = utilities(w, h)
	if bool(h.get("shutoff", false)):
		util += LTMoney.dollars(75.0)
	var paid_u: int = w.household_pay(h, "outside", util, "utilities")
	if paid_u < util:
		h["util_late"] = int(h.get("util_late", 0)) + 1
		for m in w.household_adults(h):
			w.log_sim(m, "Could not pay the full utility bill. Paid %s of %s." % [LTMoney.fmt(paid_u), LTMoney.fmt(util)], false)
			m["needs"]["shelter"] = float(m["needs"]["shelter"]) - 8.0
		if int(h["util_late"]) >= 2 and not bool(h.get("shutoff", false)):
			h["shutoff"] = true
			for m in w.household_members(h):
				w.log_sim(m, "The power company shut off the utilities for unpaid bills. No heat or lights at home.", true)
	else:
		h["util_late"] = 0
		if bool(h.get("shutoff", false)):
			h["shutoff"] = false
			for m in w.household_adults(h):
				w.log_sim(m, "Paid the past due utility bill and the reconnection fee. The lights are back on.", true)
	LTServices.monthly_household(w, h)
	# seniors draw pensions from outside
	for m in w.household_adults(h):
		if bool(m["retired"]) or w.age_years(m) >= 67:
			w.ledger.pay("outside", w.acct_p(m), PENSION_MONTHLY, "pensions")
	if str(h["tenure"]) == "rent":
		if LTCalendar.month_index(w.day) == 0 and w.day > 1:
			_rent_review(w, h)
		_pay_rent(w, h)


## Once a year a landlord sets the rent: tight housing and greed push it up, the city's cap holds it down.
static func _rent_review(w: LTWorld, h: Dictionary) -> void:
	var l: Dictionary = w.lot(int(h["lot"]))
	var vac: int = vacancy_count(w)
	var greed: float = 50.0
	if str(l["owner_kind"]) == "business":
		var o: Dictionary = w.cit(int(w.biz(int(l["owner_id"]))["owners"][0]))
		if not o.is_empty():
			greed = float(o["traits"]["greed"])
	var raise: float = 0.02 + (0.05 if vac == 0 else 0.0) + (greed - 50.0) / 1000.0 - float(vac) * 0.005
	var cap: float = float(w.city["laws"].get("rent_cap", 0.1))
	raise = clampf(raise, -0.03, cap)
	var old: int = int(h["rent"])
	h["rent"] = int(float(old) * (1.0 + raise))
	l["unit_rent"] = maxi(int(l["unit_rent"]), int(h["rent"]))
	if absi(int(h["rent"]) - old) >= 500:
		for m in w.household_adults(h):
			w.log_sim(m, "The landlord %s the rent to %s a month%s." % ["raised" if int(h["rent"]) > old else "lowered", LTMoney.fmt(int(h["rent"])), ", the most the city's rent cap allows" if is_equal_approx(raise, cap) else ""], true)


static func _pay_rent(w: LTWorld, h: Dictionary) -> void:
	var l: Dictionary = w.lot(int(h["lot"]))
	var rent: int = int(h["rent"])
	var to_acct: String = "outside"
	var landlord_biz: Dictionary = {}
	if str(l["use"]) == "business":
		# the apartment over a shop: rent goes to the business downstairs
		landlord_biz = w.biz(int(l["ref"]))
		to_acct = w.acct_b(landlord_biz)
	elif str(l["owner_kind"]) == "business":
		landlord_biz = w.biz(int(l["owner_id"]))
		to_acct = w.acct_b(landlord_biz)
	var paid: int = w.household_pay(h, to_acct, rent, "rent")
	if not landlord_biz.is_empty():
		landlord_biz["month_revenue"] = int(landlord_biz.get("month_revenue", 0)) + paid
	var adults: Array = w.household_adults(h)
	if paid >= rent:
		if int(h["rent_late"]) > 0:
			h["rent_late"] = 0
		for m in adults:
			LTFinance.credit_event(w, m, "on_time_rent")
		return
	h["rent_late"] = int(h["rent_late"]) + 1
	var landlord_name: String = str(landlord_biz.get("name", "Plains Property Group")) if not landlord_biz.is_empty() else "Plains Property Group"
	for m in adults:
		w.log_sim(m, "Paid %s of %s rent to %s. Now %d month(s) behind." % [LTMoney.fmt(paid), LTMoney.fmt(rent), landlord_name, h["rent_late"]], true)
		m["needs"]["shelter"] = float(m["needs"]["shelter"]) - 15.0
	# landlords act in their own interest: a Sim landlord with high kindness waits longer
	var patience: int = 2
	if not landlord_biz.is_empty():
		var owner: Dictionary = w.cit(int(landlord_biz["owners"][0]))
		if not owner.is_empty() and int(owner["traits"]["kindness"]) > 65:
			patience = 3
	if int(h["rent_late"]) > patience:
		evict(w, h, landlord_name)


static func evict(w: LTWorld, h: Dictionary, landlord_name: String) -> void:
	var lot_id: int = int(h["lot"])
	var l: Dictionary = w.lot(lot_id)
	vacate(w, h)
	h["evicted_day"] = w.day
	w.counters["evictions"] = int(w.counters["evictions"]) + 1
	var names: Array = []
	for m in w.household_members(h):
		m["homeless"] = true
		w.remember(m, "evicted", -1, -40.0)
		w.log_sim(m, "Evicted by %s for unpaid rent. Now without a home." % landlord_name, true)
		names.append(str(m["first_name"]))
		LTFinance.credit_event(w, m, "eviction")
	w.chronicle_add("The %s household was evicted from %s by %s." % [_hh_name(w, h), LTGeography.lot_label(w, lot_id), landlord_name], "housing", w.involves_watched(h["members"]), h["members"].duplicate())
	# family may take them in
	_find_shelter(w, h)


static func _hh_name(w: LTWorld, h: Dictionary) -> String:
	var ms: Array = w.household_members(h)
	if ms.is_empty():
		return "empty"
	return str(ms[0]["last_name"])


static func vacate(w: LTWorld, h: Dictionary) -> void:
	var lot_id: int = int(h["lot"])
	if lot_id >= 0:
		var l: Dictionary = w.lot(lot_id)
		var units: Array = l["units"]
		for i in units.size():
			if int(units[i]) == int(h["id"]):
				units[i] = -1
	h["lot"] = -1
	h["unit"] = -1
	h["tenure"] = "none"
	h["rent"] = 0
	h["rent_late"] = 0


static func move_household_into(w: LTWorld, h: Dictionary, lot_id: int, unit: int) -> void:
	var l: Dictionary = w.lot(lot_id)
	l["units"][unit] = int(h["id"])
	h["lot"] = lot_id
	h["unit"] = unit
	h["moved_in"] = w.day
	for m in w.household_members(h):
		m["homeless"] = false


static func free_unit(w: LTWorld) -> Dictionary:
	for l in w.lots:
		var units: Array = l["units"]
		for i in units.size():
			if int(units[i]) == -1 and (str(l["use"]) == "apartment" or str(l["use"]) == "house" or str(l["use"]) == "business"):
				if str(l["use"]) == "house" and str(l["owner_kind"]) == "sim":
					continue
				return {"lot": int(l["id"]), "unit": i}
	return {}


static func vacancy_count(w: LTWorld) -> int:
	var n: int = 0
	for l in w.lots:
		if str(l["use"]) == "apartment" or str(l["use"]) == "business":
			for u in l["units"]:
				if int(u) == -1:
					n += 1
	return n


static func _find_shelter(w: LTWorld, h: Dictionary) -> void:
	# relatives in town with room take them in
	for m in w.household_members(h):
		for k in m["rel"]:
			var r: Dictionary = m["rel"][k]
			if not ["parent", "child"].has(str(r["kind"])):
				continue
			var rel_c: Dictionary = w.cit(int(k))
			if not w.is_present(rel_c) or int(rel_c["household"]) == int(h["id"]):
				continue
			var rh: Dictionary = w.hh(int(rel_c["household"]))
			if int(rh["lot"]) < 0:
				continue
			var kindness: float = float(rel_c["traits"]["kindness"])
			if kindness + float(r["affection"]) * 0.5 > 70.0 and w.household_members(rh).size() + w.household_members(h).size() <= 7:
				merge_household(w, h, rh)
				w.log_sim(rel_c, "Took in %s's household after the eviction. Reason: family, and kindness won over the crowding." % m["first_name"], true)
				return
	# otherwise a free unit if they can pay first month
	var u: Dictionary = free_unit(w)
	if not u.is_empty():
		var l: Dictionary = w.lot(int(u["lot"]))
		if w.household_cash(h) > int(l["unit_rent"]) * 2 and LTFinance.rental_approved(w, h):
			move_household_into(w, h, int(u["lot"]), int(u["unit"]))
			h["tenure"] = "rent"
			h["rent"] = int(l["unit_rent"])
			for m in w.household_members(h):
				w.log_sim(m, "Found a new apartment on %s." % LTGeography.lot_label(w, int(u["lot"])), true)


static func merge_household(w: LTWorld, from_h: Dictionary, into_h: Dictionary) -> void:
	vacate(w, from_h)
	for mid in from_h["members"].duplicate():
		var m: Dictionary = w.cit(int(mid))
		if w.is_present(m):
			m["household"] = int(into_h["id"])
			into_h["members"].append(int(mid))
			m["homeless"] = false
	from_h["members"] = []


# ================================================================ decisions

## Utility choice with a small random term scaled by risk tolerance.
static func choose(w: LTWorld, c: Dictionary, options: Array) -> Dictionary:
	if options.is_empty():
		return {}
	var noise: float = 3.0 + float(c["traits"]["risk"]) * 0.12
	var best: Dictionary = {}
	var best_s: float = -1e9
	for o in options:
		var s: float = float(o["score"]) + w.rng.randf_range(-noise, noise)
		if s > best_s:
			best_s = s
			best = o
	return best


static func decide_weekly(w: LTWorld, c: Dictionary, age: int) -> void:
	var t: Dictionary = c["traits"]
	var n: Dictionary = c["needs"]
	var kind: String = str(c["job"]["kind"])
	var options: Array = []
	options.append({"key": "stay", "score": 10.0 + float(t["discipline"]) * 0.05, "reason": "things are steady enough"})
	if age >= 18 and not bool(c["retired"]) and kind != "owner":
		if kind == "none":
			var urgency: float = 30.0 + (100.0 - float(n["money_security"])) * 0.4 + float(t["discipline"]) * 0.1
			options.append({"key": "job_search", "score": urgency, "reason": "no paycheck and the bills keep coming"})
		elif kind == "outside":
			var better: Dictionary = LTEconomy.best_local_opening(w, c)
			if not better.is_empty():
				var gain: float = (float(better["wage"]) - float(c["job"]["daily_wage"]) + COMMUTE_COST_DAILY) / 100.0
				options.append({"key": "switch_local", "score": 15.0 + gain * 0.8 + 12.0, "reason": "a job in town pays about the same without the long drive", "opening": better})
	if age >= 16 and age < 18 and kind == "none" and str(c["student"]) != "graduated":
		var need_money: float = (100.0 - float(n["money_security"])) * 0.2 + float(t["ambition"]) * 0.15
		var opening: Dictionary = LTEconomy.best_local_opening(w, c)
		if not opening.is_empty():
			options.append({"key": "teen_job", "score": need_money, "reason": "wants spending money and the household is tight", "opening": opening})
	# starting a business is a big decision people come back to now and then (about
	# three times a year), sooner when the city has asked for one; after a failure, it
	# takes a couple of years to try again
	var open_need: bool = false
	for nd in w.city_needs:
		if str(nd["status"]) == "open":
			open_need = true
			break
	var founding_turn: bool = open_need or (int(c["id"]) + w.day / 7) % 17 == 0
	if w.memory_weight(c, "business_failed") < -10.0 and w.day - int(c.get("last_failure_day", -9999)) < 730:
		founding_turn = false
	if founding_turn and age >= 21 and age < 70 and kind != "owner" and c["owns"].is_empty():
		var plan: Dictionary = LTEconomy.consider_founding(w, c)
		if not plan.is_empty():
			options.append({"key": "found", "score": float(plan["score"]), "reason": str(plan["reason"]), "plan": plan})
	if age >= 18:
		var crunch: bool = w.cash(c) < monthly_bills(w, w.hh(int(c["household"]))) / 3
		if crunch and LTFinance.open_card_room(w, c) <= 0 and float(n["money_security"]) < 35.0:
			options.append({"key": "borrow", "score": 20.0 + float(t["risk"]) * 0.2 - float(t["discipline"]) * 0.1, "reason": "cash ran short before the next paycheck"})
		var desperation: float = (100.0 - float(n["hunger"])) * 0.4 + (100.0 - float(n["money_security"])) * 0.3 + float(t["greed"]) * 0.15
		var restraint: float = float(t["honesty"]) * 0.6 + LTCivic.enforcement(w) * 40.0 + float(c["theft_record"]) * 5.0
		pass
	var choice: Dictionary = choose(w, c, options)
	match str(choice.get("key", "stay")):
		"job_search":
			_job_search(w, c)
		"switch_local":
			LTEconomy.hire(w, c, choice["opening"], "Took a job in town at %s. Reason: %s." % [choice["opening"]["name"], choice["reason"]])
		"teen_job":
			LTEconomy.hire(w, c, choice["opening"], "Took a part time job at %s. Reason: %s." % [choice["opening"]["name"], choice["reason"]])
		"found":
			var plan: Dictionary = choice["plan"]
			var intent: Dictionary = c["intent"]
			if str(intent.get("type", "")) == str(plan["type"]):
				intent["weeks"] = int(intent["weeks"]) + 1
				if int(intent["weeks"]) >= 3 or (int(plan["need_id"]) >= 0 and int(intent["weeks"]) >= 2):
					c["intent"] = {}
					LTEconomy.found_business(w, c, plan)
			else:
				c["intent"] = {"type": plan["type"], "since": w.day, "weeks": 1}
				w.log_sim(c, "Started planning to open a %s. Reason: %s. Will look at the numbers again for a few weeks before deciding." % [str(LTEconomy.tcfg(plan["type"])["display"]).to_lower(), plan["reason"]], true)
		"borrow":
			LTFinance.personal_loan(w, c, str(choice["reason"]))
		"steal":
			LTCivic.theft(w, c, str(choice["reason"]))


static func _job_search(w: LTWorld, c: Dictionary) -> void:
	var local: Dictionary = LTEconomy.best_local_opening(w, c)
	if not local.is_empty() and LTEconomy.would_hire(w, local, c):
		LTEconomy.hire(w, c, local, "Hired at %s as a %s. Reason: kept looking and the owner picked them from the applicants." % [local["name"], local["title"]])
		return
	var p: float = 0.025 + float(c["education"]) * 0.0006 + float(c["traits"]["discipline"]) * 0.0004 - float(c["credit"]["collections"]) * 0.01
	if LTJustice.record_count(c) > 0:
		p *= 0.5
	p *= LTRegion.hire_mult(w)
	if not bool(w.hh(int(c["household"]))["car"]) and not LTCivic.bus_available(w):
		p *= 0.3
	if w.rng.randf() < p:
		var j: Dictionary = pick_outside_job(w, c)
		var looked: int = int(c["days_unemployed"])
		set_job(w, c, "outside", -1, str(j["title"]), _outside_wage(w, c, j), str(j["skill"]))
		w.log_sim(c, "Found work outside town as a %s after %d days of looking. Reason: no local opening fit, so took the commute." % [j["title"], looked], true)
		w.remember(c, "hired", -1, 10.0)
	elif int(c["days_unemployed"]) % 28 < 7:
		w.log_sim(c, "Applied for work again with no luck. Unemployed for %d days." % c["days_unemployed"], false)


# ================================================================ life events

static func life_events(w: LTWorld) -> void:
	var newborns: Array = []
	for c in w.citizens:
		if not w.is_present(c):
			continue
		if _dies_today(w, c):
			die(w, c, _death_cause(w, c))
			continue
		var baby: Dictionary = _maybe_birth(w, c)
		if not baby.is_empty():
			newborns.append(baby)
	if LTCalendar.day_of_month(w.day) == 15:
		_monthly_migration(w)
		_monthly_partners(w)
		_young_adults_move_out(w)


static func _dies_today(w: LTWorld, c: Dictionary) -> bool:
	var age: int = w.age_years(c)
	var health: float = float(c["needs"]["health"])
	var annual: float = 0.0006
	if age >= 90:
		annual = 0.25
	elif age >= 80:
		annual = 0.09
	elif age >= 70:
		annual = 0.036
	elif age >= 60:
		annual = 0.013
	elif age >= 40:
		annual = 0.003
	elif age < 1:
		annual = 0.005
	if health <= 10.0:
		annual += 0.6
	elif health <= 25.0:
		annual += 0.12
	if str(c["health_cond"]) == "serious illness":
		annual *= 2.5
	if bool(c["homeless"]):
		annual *= 2.0
	return w.rng.randf() < annual / 365.0


static func _death_cause(w: LTWorld, c: Dictionary) -> String:
	if str(c["health_cond"]) == "serious illness":
		return "a serious illness"
	if float(c["needs"]["health"]) < 25.0:
		return "poor health"
	if w.age_years(c) >= 70:
		return "old age"
	return "an accident"


static func die(w: LTWorld, c: Dictionary, cause: String) -> void:
	c["alive"] = false
	c["death_day"] = w.day
	c["death_cause"] = cause
	w.counters["deaths"] = int(w.counters["deaths"]) + 1
	w.log_sim(c, "Died at age %d of %s." % [w.age_years(c), cause], true)
	var refs: Array = [c["id"]]
	for k in c["rel"]:
		var r: Dictionary = c["rel"][k]
		var other: Dictionary = w.cit(int(k))
		if not w.is_present(other):
			continue
		if ["spouse", "child", "parent"].has(str(r["kind"])):
			other["needs"]["family"] = float(other["needs"]["family"]) - 35.0
			other["needs"]["fun"] = float(other["needs"]["fun"]) - 30.0
			w.remember(other, "death_in_family", int(c["id"]), -50.0)
			w.log_sim(other, "Lost %s %s, who died of %s. Grieving." % [_rel_word(str(r["kind"])), w.full_name(c), cause], true)
			refs.append(other["id"])
		elif float(r["affection"]) > 60.0:
			other["needs"]["social"] = float(other["needs"]["social"]) - 10.0
			w.log_sim(other, "A friend, %s, died." % w.full_name(c), false)
	if int(c["spouse"]) >= 0:
		var sp: Dictionary = w.cit(int(c["spouse"]))
		if not sp.is_empty():
			sp["spouse"] = -1
	if str(c["job"]["kind"]) != "none" and str(c["job"]["kind"]) != "owner":
		LTEconomy.leave_job(w, c, "died")
	var h: Dictionary = w.hh(int(c["household"]))
	w.chronicle_add("%s died at %d of %s." % [w.full_name(c), w.age_years(c), cause], "death", true if w.involves_watched(refs) else false, refs)
	LTFinance.settle_estate(w, c)
	if w.household_members(h).is_empty():
		vacate(w, h)


static func _rel_word(kind: String) -> String:
	match kind:
		"spouse":
			return "their spouse"
		"child":
			return "their child"
		"parent":
			return "their parent"
	return ""


static func _maybe_birth(w: LTWorld, m: Dictionary) -> Dictionary:
	if str(m["sex"]) != "F":
		return {}
	var age: int = w.age_years(m)
	if age < 19 or age > 43:
		return {}
	var sp: Dictionary = w.cit(int(m["spouse"]))
	if not w.is_present(sp) or str(sp["sex"]) != "M":
		return {}
	var h: Dictionary = w.hh(int(m["household"]))
	if int(h["lot"]) < 0 or not m.get("pregnant", {}).is_empty():
		return {}
	var kids: int = 0
	for kid in m["children"]:
		if w.is_present(w.cit(int(kid))) and w.age_years(w.cit(int(kid))) < 18:
			kids += 1
	var n: Dictionary = m["needs"]
	# couples decide on housing, money security, age, health, personality and the town
	var score: float = 1.0
	score *= clampf(float(n["money_security"]) / 55.0, 0.2, 1.4)
	score *= clampf(float(n["shelter"]) / 60.0, 0.2, 1.2)
	score *= 1.0 if age < 35 else 0.5
	score *= [1.3, 1.1, 0.7, 0.35, 0.15, 0.05][mini(kids, 5)]
	score *= 0.6 + float(m["traits"]["kindness"] + sp["traits"]["kindness"]) / 250.0
	score *= 0.8 + LTCivic.family_friendliness(w) * 0.4
	# couples here have about as many children as couples in South Dakota do
	if w.rng.randf() >= 0.0006 * score:
		return {}
	var reason: String = "the couple had a home and enough money security to feel ready"
	if float(n["money_security"]) < 45.0:
		reason = "they wanted a child even though money was tight"
	LTHealth.conceive(w, m, sp, reason)
	return {}


static func give_birth(w: LTWorld, m: Dictionary, sp: Dictionary) -> Dictionary:
	var h: Dictionary = w.hh(int(m["household"]))
	var last: String = str(sp["last_name"]) if not sp.is_empty() else str(m["last_name"])
	var baby: Dictionary = _blank_citizen(w, int(h["id"]), last, "F" if w.rng.randf() < 0.5 else "M", 0)
	_unique_first_name(w, baby)
	baby["age_days"] = 0
	inherit_traits(w, baby, m, sp)
	_roll_skills(w, baby, 0)
	baby["mother"] = int(m["id"])
	m["children"].append(int(baby["id"]))
	_relate(m, baby, "child", 85.0, 95.0)
	_relate(baby, m, "parent", 80.0, 90.0)
	if not sp.is_empty():
		baby["father"] = int(sp["id"])
		sp["children"].append(int(baby["id"]))
		_relate(sp, baby, "child", 85.0, 95.0)
		_relate(baby, sp, "parent", 80.0, 90.0)
	w.counters["births"] = int(w.counters["births"]) + 1
	w.log_sim(m, "Had a baby, %s." % baby["first_name"], true)
	if not sp.is_empty() and w.is_present(sp):
		w.log_sim(sp, "Had a baby, %s." % baby["first_name"], true)
	w.log_sim(baby, "Born to %s%s." % [w.full_name(m), " and " + w.full_name(sp) if not sp.is_empty() else ""], true)
	w.chronicle_add("%s was born to %s%s." % [w.full_name(baby), w.full_name(m), " and " + w.full_name(sp) if not sp.is_empty() else ""], "birth", w.involves_watched([m["id"], int(sp.get("id", -1))]), [baby["id"], m["id"]])
	return baby


## About 6 marriages a year per 1,000 people (US and South Dakota): each single
## adult has a small monthly chance of settling down, higher when sociable, and
## marries the compatible single they like best.
const MARRY_MONTHLY: float = 0.0024


static func _monthly_partners(w: LTWorld) -> void:
	var singles: Array = []
	for c in w.citizens:
		if w.is_present(c) and int(c["spouse"]) < 0 and w.age_years(c) >= 20 and w.age_years(c) <= 70:
			singles.append(c)
	for a in singles:
		if int(a["spouse"]) >= 0:
			continue
		var age: int = w.age_years(a)
		var p: float = MARRY_MONTHLY * (0.5 + float(a["traits"]["sociability"]) / 100.0) * (1.4 if age < 35 else (1.0 if age < 50 else 0.45))
		if w.rng.randf() >= p:
			continue
		var best: Dictionary = {}
		var best_s: float = -1.0
		for b in singles:
			if int(b["id"]) == int(a["id"]) or int(b["spouse"]) >= 0 or int(b["household"]) == int(a["household"]):
				continue
			if str(a["sex"]) == str(b["sex"]) and w.rng.randf() < 0.95:
				continue
			if absi(age - w.age_years(b)) > 10:
				continue
			var sc: float = w.rng.randf() * 30.0 + float(b["traits"]["sociability"]) * 0.2
			if a["rel"].has(int(b["id"])):
				sc += float(a["rel"][int(b["id"])]["affection"])
			if sc > best_s:
				best_s = sc
				best = b
		if not best.is_empty():
			_marry(w, a, best)


static func _marry(w: LTWorld, a: Dictionary, b: Dictionary) -> void:
	a["spouse"] = int(b["id"])
	b["spouse"] = int(a["id"])
	_relate(a, b, "spouse", 75.0, 85.0)
	_relate(b, a, "spouse", 75.0, 85.0)
	var ha: Dictionary = w.hh(int(a["household"]))
	var hb: Dictionary = w.hh(int(b["household"]))
	# the smaller household moves into the one with more room or a house
	var mover: Dictionary = hb
	var stay: Dictionary = ha
	var a_house: bool = int(ha["lot"]) >= 0 and str(w.lot(int(ha["lot"]))["use"]) == "house"
	if not a_house and (int(hb["lot"]) >= 0 and (str(w.lot(int(hb["lot"]))["use"]) == "house" or int(ha["lot"]) < 0)):
		mover = ha
		stay = hb
	if int(stay["lot"]) < 0:
		mover = stay
		stay = ha if mover == hb else hb
	var moving: Dictionary = a if int(a["household"]) == int(mover["id"]) else b
	if w.household_members(mover).size() == 1:
		merge_household(w, mover, stay)
	else:
		mover["members"].erase(int(moving["id"]))
		moving["household"] = int(stay["id"])
		stay["members"].append(int(moving["id"]))
	w.counters["marriages"] = int(w.counters["marriages"]) + 1
	w.log_sim(a, "Married %s." % w.full_name(b), true)
	w.log_sim(b, "Married %s." % w.full_name(a), true)
	w.chronicle_add("%s and %s got married." % [w.full_name(a), w.full_name(b)], "family", w.involves_watched([a["id"], b["id"]]), [a["id"], b["id"]])


static func _young_adults_move_out(w: LTWorld) -> void:
	for c in w.citizens:
		if not w.is_present(c):
			continue
		var age: int = w.age_years(c)
		if age < 19 or age > 34 or int(c["spouse"]) >= 0 or str(c["job"]["kind"]) == "none":
			continue
		var h: Dictionary = w.hh(int(c["household"]))
		if w.household_members(h).size() <= 2:
			continue
		var is_child: bool = false
		for m in w.household_adults(h):
			if m["children"].has(int(c["id"])):
				is_child = true
		if not is_child:
			continue
		var u: Dictionary = free_unit(w)
		if u.is_empty():
			continue
		var rent: int = int(w.lot(int(u["lot"]))["unit_rent"])
		if w.cash(c) < rent * 2 or float(c["job"]["daily_wage"]) * 21.0 < float(rent) * 2.5:
			continue
		if w.rng.randf() > 0.25 + float(c["traits"]["ambition"]) / 300.0:
			continue
		var nh: Dictionary = {"id": w.households.size(), "members": [], "lot": -1, "unit": -1, "tenure": "none", "rent": 0, "rent_late": 0, "mortgage": -1, "pantry": 2.0, "car": true, "moved_in": w.day, "last_grocery": "", "shop_habit": -1, "evicted_day": -1}
		w.households.append(nh)
		h["members"].erase(int(c["id"]))
		nh["members"].append(int(c["id"]))
		c["household"] = int(nh["id"])
		move_household_into(w, nh, int(u["lot"]), int(u["unit"]))
		nh["tenure"] = "rent"
		nh["rent"] = rent
		if not LTFinance.rental_approved(w, nh):
			w.log_sim(c, "Got an apartment with a parent as co-signer on the lease, since they have little credit history.", true)
		w.log_sim(c, "Moved out of the family home into an apartment on %s. Reason: has a job and wanted their own place." % LTGeography.lot_label(w, int(u["lot"])), true)


static func town_pull(w: LTWorld) -> float:
	# what an outsider sees: housing, jobs, business chances, safety, services
	var pull: float = 0.0
	pull += clampf(float(vacancy_count(w)) * 4.0, 0.0, 20.0)
	pull += clampf(float(LTEconomy.open_positions(w)) * 6.0, 0.0, 30.0)
	pull += LTCivic.safety_level(w) * 0.15
	pull += (8.0 if LTCivic.has_service(w, "school") else 0.0) + (6.0 if LTCivic.has_service(w, "clinic") else 0.0)
	pull += (6.0 if not w.open_businesses("grocery").is_empty() else -4.0)
	pull -= float(w.city["laws"]["property_tax"]) * 400.0
	return pull


static func _monthly_migration(w: LTWorld) -> void:
	# arrivals
	var pull: float = town_pull(w)
	if vacancy_count(w) > 0:
		var arrivals: int = 0
		var p: float = clampf(pull / 100.0, 0.0, 0.9)
		while arrivals < 3 and w.rng.randf() < p and vacancy_count(w) > 0:
			var u: Dictionary = free_unit(w)
			if u.is_empty():
				break
			var h: Dictionary = make_household(w, false, true)
			move_household_into(w, h, int(u["lot"]), int(u["unit"]))
			h["tenure"] = "rent"
			h["rent"] = int(w.lot(int(u["lot"]))["unit_rent"])
			var reason: String = _arrival_reason(w)
			for m in w.household_members(h):
				m["moved_in"] = w.day
				w.log_sim(m, "Moved to town. Reason: %s." % reason, true)
				w.counters["moved_in"] = int(w.counters["moved_in"]) + 1
			w.chronicle_add("The %s household moved to town. They said %s." % [_hh_name(w, h), reason], "move", false, h["members"].duplicate())
			arrivals += 1
			p *= 0.5
	# departures, scored per household
	for h in w.households:
		var adults: Array = w.household_adults(h)
		if adults.is_empty():
			continue
		var push: float = 0.0
		var ties: float = 0.0
		for m in adults:
			push += (60.0 - happiness(m)) * 0.6
			push += (40.0 - float(m["needs"]["money_security"])) * 0.4
			push += maxf(0.0, 40.0 - float(m["trust_city"])) * 0.3
			if str(m["job"]["kind"]) == "none":
				push += 8.0
			if bool(m["homeless"]):
				push += 25.0
				for kid in m["children"]:
					var kc: Dictionary = w.cit(int(kid))
					if w.is_present(kc) and w.age_years(kc) < 18 and int(kc["household"]) == int(h["id"]):
						push += 30.0
						break
			ties += float(w.day - int(m["moved_in"])) / 365.0 * 1.5 + float(m["rel"].size()) * 1.2
			if not m["owns"].is_empty():
				ties += 30.0
			if str(h["tenure"]) == "own":
				ties += 20.0
		push /= float(adults.size())
		ties /= float(adults.size())
		var score: float = push - ties - pull * 0.2
		if score > 18.0 and w.rng.randf() < clampf(score / 120.0, 0.0, 0.5):
			_household_leaves(w, h, score)


static func _arrival_reason(w: LTWorld) -> String:
	if LTEconomy.open_positions(w) > 0:
		return "there were jobs open in town and an apartment was free"
	if not w.open_businesses("grocery").is_empty():
		return "rent was fair and the town has its own grocery now"
	return "rent was cheaper than in the city"


static func _household_leaves(w: LTWorld, h: Dictionary, score: float) -> void:
	var adults: Array = w.household_adults(h)
	var why: String = "no money security and no reason to stay"
	var m0: Dictionary = adults[0]
	if bool(m0["homeless"]):
		why = "they lost their home and saw no way back here"
	elif str(m0["job"]["kind"]) == "none":
		why = "no work in town and no luck finding any nearby"
	elif float(m0["trust_city"]) < 30.0:
		why = "they gave up on the city ever listening"
	var lot_id: int = int(h["lot"])
	if str(h["tenure"]) == "own" and lot_id >= 0:
		LTFinance.sell_house(w, h, "moving away")
	for m in w.household_members(h):
		for bid in m["owns"].duplicate():
			var ob: Dictionary = w.biz(int(bid))
			if not ob.is_empty() and str(ob["status"]) == "open":
				if ob["owners"].size() > 1:
					ob["owners"].erase(int(m["id"]))
					m["owns"].erase(int(bid))
				elif not LTEconomy.sell_business(w, ob, m, "moving away"):
					LTEconomy.close_business(w, ob, "the owner moved away")
		if str(m["job"]["kind"]) != "none" and str(m["job"]["kind"]) != "owner":
			LTEconomy.leave_job(w, m, "moved away")
		m["left_town"] = true
		m["left_day"] = w.day
		w.log_sim(m, "Left town. Reason: %s." % why, true)
		w.counters["moved_out"] = int(w.counters["moved_out"]) + 1
		# they take their money with them, their debts follow them out of town
		w.ledger.pay(w.acct_p(m), "outside", w.cash(m), "moved_away_cash")
		LTFinance.debtor_left_town(w, m)
	vacate(w, h)
	w.chronicle_add("The %s household left town. Reason: %s." % [_hh_name(w, h), why], "move", w.involves_watched(h["members"]), h["members"].duplicate())


static func happiness(c: Dictionary) -> float:
	var n: Dictionary = c["needs"]
	var wsum: float = 0.0
	var t: float = 0.0
	for k in NEED_KEYS:
		var wt: float = float(c["weights"].get(k, 1.0))
		t += float(n[k]) * wt
		wsum += wt
	var base: float = t / wsum
	# the lowest need drags happiness down, urgent needs dominate
	var low: float = 100.0
	for k in NEED_KEYS:
		low = minf(low, float(n[k]))
	return base * 0.7 + low * 0.3


static func life_stage(w: LTWorld, c: Dictionary) -> String:
	var a: int = w.age_years(c)
	if a < 13:
		return "Child" if a >= 2 else "Baby"
	if a < 18:
		return "Teen"
	if a < 65:
		return "Adult"
	return "Senior"


static func archetype(c: Dictionary) -> String:
	var t: Dictionary = c["traits"]
	if int(t["greed"]) > 65 and int(t["honesty"]) < 35:
		return "grifter"
	if int(t["risk"]) > 65 and int(t["discipline"]) < 35:
		return "gambler"
	if int(t["ambition"]) > 62 and int(t["risk"]) > 55:
		return "founder"
	if int(t["kindness"]) > 65 and int(t["sociability"]) > 60:
		return "pillar"
	if int(t["discipline"]) > 60 and int(t["risk"]) < 45:
		return "steady worker"
	if int(t["discipline"]) < 35 and int(t["ambition"]) < 35:
		return "drifter"
	return "ordinary"
