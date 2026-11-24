class_name LTHazards
## Weather and disasters, with rates taken from the real climate of eastern South
## Dakota and from US fire statistics. Every number here is a yearly or monthly
## rate a person can check, kept in one place.
##
## Sources the numbers follow (rounded):
## - Days with rain, thunder and snow by month: NOAA climate normals for Sioux Falls.
## - Severe thunderstorms (damaging wind or hail an inch or larger) reaching one
##   small town: about 1 to 2 a year, mostly May to August (NOAA storm events).
## - A tornado touching a given small town: well under once a century; about 1 in
##   400 a year is used for a town's whole footprint.
## - Blizzards: about 1 to 2 a year in eastern South Dakota, November to April.
## - Home fires: about 1 in 400 homes a year reported to a fire department (NFPA),
##   more in winter. About 1 in 30 home fires injures someone and about 1 in 125
##   kills someone. Most are small kitchen fires; about 1 in 20 destroys the house.
## - Ordinary thunderstorms and snow do not damage sound buildings. Cheap or worn
##   ones (poor condition) lose shingles, siding and gutters.
## - Homeowners insurance costs about 0.6% of the building's value a year and pays
##   claims above a $1,500 deductible.

# days per month with [thunder, rain without thunder, snow], January first
const MONTH_DAYS_WX: Array = [
	[0.0, 1.0, 6.0], [0.1, 1.0, 6.0], [0.6, 2.5, 5.0], [2.5, 5.0, 1.5],
	[5.5, 5.5, 0.0], [8.5, 2.5, 0.0], [8.0, 1.0, 0.0], [7.0, 2.0, 0.0],
	[4.0, 4.0, 0.0], [1.5, 5.0, 0.5], [0.3, 2.2, 3.5], [0.0, 1.0, 6.0],
]
const SEVERE_PER_YEAR: float = 1.5
const SEVERE_MONTH: Array = [0.0, 0.0, 0.01, 0.07, 0.18, 0.30, 0.25, 0.14, 0.05, 0.0, 0.0, 0.0]
const TORNADO_PER_YEAR: float = 0.0025
const BLIZZARD_PER_YEAR: float = 1.5
const BLIZZARD_MONTH: Array = [0.26, 0.22, 0.15, 0.03, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.12, 0.22]
const HOME_FIRE_PER_YEAR: float = 0.0025
const BUSINESS_FIRE_PER_YEAR: float = 0.005
const FIRE_INJURY: float = 1.0 / 30.0
const FIRE_DEATH: float = 1.0 / 125.0
const INSURANCE_RATE: float = 0.006
const DEDUCTIBLE: int = 150000
const DAMAGE_COST_PER_POINT: int = 40000  # $400 of repairs per point of condition lost


## Rolls the day's weather from the month's real odds, then any severe event.
static func roll_weather(w: LTWorld) -> void:
	var m: int = LTCalendar.month_index(w.day)
	var md: float = float(LTCalendar.MONTH_DAYS[m])
	var row: Array = MONTH_DAYS_WX[m]
	var r: float = w.rng.randf() * md
	if r < float(row[0]):
		w.weather = "Storm"
	elif r < float(row[0]) + float(row[1]):
		w.weather = "Rain"
	elif r < float(row[0]) + float(row[1]) + float(row[2]):
		w.weather = "Snow"
	else:
		w.weather = "Clear"
	w.region["event_today"] = ""
	# severe events: a yearly rate spread over the months they happen in
	var sev: float = SEVERE_PER_YEAR * float(SEVERE_MONTH[m]) / md
	var bliz: float = BLIZZARD_PER_YEAR * float(BLIZZARD_MONTH[m]) / md
	var r2: float = w.rng.randf()
	if r2 < sev:
		w.weather = "Storm"
		w.region["event_today"] = "tornado" if w.rng.randf() < TORNADO_PER_YEAR / SEVERE_PER_YEAR else "severe_storm"
	elif r2 < sev + bliz:
		w.weather = "Snow"
		w.region["event_today"] = "blizzard"


## Snow on the ground, in inches. Snowfall adds to it, and it melts slowly in deep
## winter and fast in spring, so the prairie stays white through most of a Dakota
## winter, the way it really does.
static func snow_depth(w: LTWorld) -> float:
	return float(w.region.get("snow_depth", 0.0))


static func _snow_cover(w: LTWorld) -> void:
	var d: float = snow_depth(w)
	var m: int = LTCalendar.month_index(w.day)
	if w.weather == "Snow":
		d += w.rng.randf_range(1.0, 5.0) * (3.0 if event_today(w) == "blizzard" else 1.0)
	else:
		var melt: float = [0.25, 0.35, 1.2, 3.0, 6.0, 6.0, 6.0, 6.0, 6.0, 3.0, 1.0, 0.3][m]
		if w.weather == "Rain" or w.weather == "Storm":
			melt += 2.0
		d -= melt
	w.region["snow_depth"] = clampf(d, 0.0, 40.0)


static func event_today(w: LTWorld) -> String:
	return str(w.region.get("event_today", ""))


static func daily(w: LTWorld) -> void:
	_snow_cover(w)
	match event_today(w):
		"severe_storm":
			severe_storm(w)
		"tornado":
			tornado(w)
		"blizzard":
			blizzard(w)
		_:
			if w.weather == "Storm" or w.weather == "Snow":
				_ordinary_weather(w)
	_fires(w)


# ---------------------------------------------------------------- weak buildings

## A building is weak when it is worn down or was built cheaply. Weak buildings
## are the ones ordinary weather can hurt, and they take the worst of a storm.
static func weak(w: LTWorld, l: Dictionary) -> bool:
	if float(l["condition"]) < 45.0:
		return true
	return float(l.get("build_quality", 0.6)) < 0.4


static func _building(l: Dictionary) -> bool:
	return ["house", "apartment", "business", "civic", "mayor_house", "closed"].has(str(l["use"]))


static func _code_factor(w: LTWorld) -> float:
	# a strict building code means stronger roofs and tie downs; a loose one, weaker
	return clampf(1.4 - float(w.city["laws"].get("building_code", 1.0)) * 0.4, 0.6, 1.4)


static func _ordinary_weather(w: LTWorld) -> void:
	# a thunderstorm or snowfall: only weak buildings lose a few shingles or a gutter
	var hit: Array = []
	for l in w.lots:
		if not _building(l) or not weak(w, l):
			continue
		if w.rng.randf() < 0.03 * _code_factor(w):
			damage(w, l, w.rng.randf_range(2.0, 6.0), "storm")
			hit.append(l)
	if hit.size() > 0:
		w.chronicle_add("%s brought down shingles and gutters on %d run down %s." % ["The thunderstorm" if w.weather == "Storm" else "Heavy snow", hit.size(), "building" if hit.size() == 1 else "buildings"], "region", false, [])


static func severe_storm(w: LTWorld) -> void:
	w.region["storms"] = int(w.region.get("storms", 0)) + 1
	_count(w, "severe_storms")
	var hail: bool = w.rng.randf() < 0.6
	var hit: int = 0
	var weak_hit: int = 0
	for l in w.lots:
		if not _building(l):
			continue
		var is_weak: bool = weak(w, l)
		# hail dents most roofs a little; wind mostly takes what is already loose
		var p: float = (0.35 if is_weak else (0.10 if hail else 0.04)) * _code_factor(w)
		if w.rng.randf() >= p:
			continue
		var dmg: float = w.rng.randf_range(8.0, 25.0) if is_weak else w.rng.randf_range(3.0, 10.0)
		damage(w, l, dmg, "storm")
		hit += 1
		if is_weak:
			weak_hit += 1
	for s in w.roads:
		if bool(s.get("planned", false)) or bool(s.get("removed", false)):
			continue
		if w.rng.randf() < 0.1:
			s["condition"] = maxf(0.0, float(s["condition"]) - w.rng.randf_range(1.0, 4.0))
	w.dist_cache.clear()
	var what: String = "hail and damaging wind" if hail else "damaging wind"
	if hit == 0:
		w.chronicle_add("A severe thunderstorm with %s passed over town. No buildings were damaged." % what, "region", true, [])
	else:
		w.chronicle_add("A severe thunderstorm with %s damaged %d %s%s." % [what, hit, "building" if hit == 1 else "buildings", (", %d of them run down or cheaply built" % weak_hit) if weak_hit > 0 else ""], "region", true, [])


static func tornado(w: LTWorld) -> void:
	_count(w, "tornadoes")
	severe_storm(w)
	# a narrow path across town: everything within a block of it is hit hard
	# its path is a straight line across the map, in meters; within 15 meters is the
	# core, within 50 meters the edge of the storm
	var along_rows: bool = w.rng.randf() < 0.5
	var built: Array = []
	for l0 in w.lots:
		if _building(l0):
			built.append(l0)
	if built.is_empty():
		return
	var aim: Dictionary = built[w.rng.randi_range(0, built.size() - 1)]
	var line: float = (float(aim["z0"]) + float(aim["z1"])) * 0.5 if along_rows else (float(aim["x0"]) + float(aim["x1"])) * 0.5
	line += w.rng.randf_range(-60.0, 60.0)
	var hit: int = 0
	var people: Array = []
	for l in w.lots:
		if not _building(l):
			continue
		var c: float = (float(l["z0"]) + float(l["z1"])) * 0.5 if along_rows else (float(l["x0"]) + float(l["x1"])) * 0.5
		var d: int = 0 if absf(c - line) < 15.0 else (1 if absf(c - line) < 50.0 else 2)
		if d > 1:
			continue
		var dmg: float = w.rng.randf_range(40.0, 95.0) if d == 0 else w.rng.randf_range(10.0, 40.0)
		damage(w, l, dmg, "tornado")
		hit += 1
		for u in l["units"]:
			if int(u) >= 0:
				for m in w.household_members(w.hh(int(u))):
					m["needs"]["safety"] = float(m["needs"]["safety"]) - 40.0
					var safe: bool = str(l["use"]) == "house" and LTHomes.has_shelter(LTHomes.upgrade(l.get("home", {}))) if l.has("home") else false
					if d == 0 and w.rng.randf() < (0.01 if safe else 0.05):
						m["sick_days"] = maxi(int(m["sick_days"]), w.rng.randi_range(5, 30))
						m["health_cond"] = "hurt in the tornado"
						people.append(m["id"])
	if hit > 0:
		w.chronicle_add("A tornado cut across town and damaged %d %s.%s" % [hit, "building" if hit == 1 else "buildings", " %d people were hurt." % people.size() if not people.is_empty() else " Nobody was hurt."], "region", true, people)
	else:
		w.chronicle_add("A tornado touched down on the prairie just outside town. It missed every building.", "region", true, [])


static func blizzard(w: LTWorld) -> void:
	_count(w, "blizzards")
	# snow load and wind: only weak roofs fail, roads close for the day
	var hit: int = 0
	for l in w.lots:
		if _building(l) and weak(w, l) and w.rng.randf() < 0.12 * _code_factor(w):
			damage(w, l, w.rng.randf_range(4.0, 14.0), "blizzard")
			hit += 1
	w.chronicle_add("A blizzard closed the roads for the day.%s" % (" The snow load damaged %d run down %s." % [hit, "roof" if hit == 1 else "roofs"] if hit > 0 else ""), "region", true, [])


# ---------------------------------------------------------------- fires

static func _fires(w: LTWorld) -> void:
	var m: int = LTCalendar.month_index(w.day)
	var season: float = 1.35 if m <= 1 or m == 11 else (0.85 if m >= 5 and m <= 8 else 1.0)
	var code: float = float(w.city["laws"].get("building_code", 1.0))
	var prevent: float = clampf(1.25 - code * 0.25, 0.7, 1.2) * clampf(1.1 - float(w.city["laws"].get("fire_funding", 1.0)) * 0.1, 0.85, 1.05)
	for l in w.lots:
		var rate: float = lot_fire_rate(w, l)
		if rate <= 0.0:
			continue
		if w.rng.randf() >= rate * season * prevent / 365.0:
			continue
		_fire(w, l)


## Chance a year that this building catches fire, before season and prevention.
static func lot_fire_rate(w: LTWorld, l: Dictionary) -> float:
	var use: String = str(l["use"])
	var rate: float = 0.0
	if use == "house" or use == "apartment" or use == "mayor_house":
		rate = HOME_FIRE_PER_YEAR * maxf(1.0, float(l["units"].size()) * 0.7)
	elif use == "business":
		rate = BUSINESS_FIRE_PER_YEAR
	else:
		return 0.0
	if weak(w, l):
		rate *= 1.6
	return rate


## Fires a year the town should expect as it stands today: the model's own rate,
## averaged over the seasons, without the luck of a few years' draws.
static func expected_fires_per_year(w: LTWorld) -> float:
	var code: float = float(w.city["laws"].get("building_code", 1.0))
	var prevent: float = clampf(1.25 - code * 0.25, 0.7, 1.2) * clampf(1.1 - float(w.city["laws"].get("fire_funding", 1.0)) * 0.1, 0.85, 1.05)
	var season_avg: float = (3.0 * 1.35 + 4.0 * 0.85 + 5.0 * 1.0) / 12.0
	var t: float = 0.0
	for l in w.lots:
		t += lot_fire_rate(w, l)
	return t * season_avg * prevent


static func _fire(w: LTWorld, l: Dictionary) -> void:
	w.counters["fires"] = int(w.counters.get("fires", 0)) + 1
	# most fires are small; better fire service reaches the rest sooner
	var funding: float = float(w.city["laws"].get("fire_funding", 1.0))
	# a small town's fire crew is its volunteers: more of them, faster and fuller turnout
	var crew: int = mini(LTChoices.volunteers(w, "fire"), 12)
	funding *= 1.0 + float(crew) * 0.05
	var roll: float = w.rng.randf() - float(crew) * 0.003
	var dmg: float = 0.0
	var size: String = ""
	if roll < 0.55:
		dmg = w.rng.randf_range(2.0, 8.0)
		size = "A small fire"
	elif roll < 0.95:
		dmg = w.rng.randf_range(15.0, 55.0) / funding
		size = "A fire"
	else:
		dmg = w.rng.randf_range(80.0, 100.0)
		size = "A fire destroyed most of"
	damage(w, l, dmg, "fire")
	var people: Array = []
	var hurt: Array = []
	var dead: Array = []
	for u in l["units"]:
		if int(u) < 0:
			continue
		for m in w.household_members(w.hh(int(u))):
			people.append(m["id"])
			m["needs"]["safety"] = float(m["needs"]["safety"]) - 25.0
			w.log_sim(m, "A fire damaged their home on %s." % LTGeography.lot_label(w, int(l["id"])), true)
	if not people.is_empty():
		var r: float = w.rng.randf()
		var who: Dictionary = w.cit(int(people[w.rng.randi_range(0, people.size() - 1)]))
		if r < FIRE_DEATH:
			dead.append(who["id"])
		elif r < FIRE_DEATH + FIRE_INJURY:
			hurt.append(who["id"])
			who["sick_days"] = maxi(int(who["sick_days"]), w.rng.randi_range(3, 21))
			who["health_cond"] = "burns from a house fire"
			who["needs"]["health"] = float(who["needs"]["health"]) - 20.0
	if str(l["use"]) == "business":
		var b: Dictionary = w.biz(int(l["ref"]))
		if not b.is_empty():
			b["stock"] = float(b["stock"]) * (0.9 if dmg < 10.0 else 0.4)
	var what: String = "%s %s." % [size, LTGeography.lot_label(w, int(l["id"]))] if size.ends_with("of") else "%s damaged %s." % [size, LTGeography.lot_label(w, int(l["id"]))]
	if not dead.is_empty():
		what += " %s died." % w.full_name(w.cit(int(dead[0])))
	elif not hurt.is_empty():
		what += " %s was treated for burns." % w.full_name(w.cit(int(hurt[0])))
	elif not people.is_empty():
		what += " Nobody was hurt."
	w.chronicle_add(what, "city", dmg >= 15.0 or not dead.is_empty() or not hurt.is_empty(), people)
	for cid in dead:
		_count(w, "fire_deaths")
		LTPeople.die(w, w.cit(int(cid)), "injuries from a house fire")
	if not hurt.is_empty():
		_count(w, "fire_injuries")


# ---------------------------------------------------------------- damage and insurance

## Damages a building and sends the repair bill: the owner pays the deductible
## (or everything, if uninsured) and the insurer pays the rest.
static func damage(w: LTWorld, l: Dictionary, points: float, cause: String) -> void:
	points = minf(points, float(l["condition"]))
	if points <= 0.0:
		return
	l["condition"] = float(l["condition"]) - points
	_count(w, "damaged_buildings")
	if str(l["use"]) == "business":
		var b: Dictionary = w.biz(int(l["ref"]))
		if not b.is_empty():
			b["condition"] = maxf(0.0, float(b["condition"]) - points)
	var cost: int = int(points * float(DAMAGE_COST_PER_POINT))
	var acct: String = ""
	var who: Dictionary = {}
	match str(l["owner_kind"]):
		"sim":
			who = w.cit(int(l["owner_id"]))
			if w.is_present(who):
				acct = w.acct_p(who)
		"business":
			var ob: Dictionary = w.biz(int(l["owner_id"]))
			if not ob.is_empty():
				acct = w.acct_b(ob)
		"city":
			acct = "city"
	if acct == "":
		return
	var insured: bool = bool(l.get("insured", true)) and str(l["owner_kind"]) != "city"
	var own_share: int = mini(cost, DEDUCTIBLE) if insured else cost
	if insured and cost > DEDUCTIBLE:
		# the insurer pays the contractor for everything above the deductible
		w.ledger.pay("outside", acct, cost - DEDUCTIBLE, "insurance claim")
		_count(w, "insurance_claims")
	var paid: int = LTServices.spend(w, acct, "repairs", cost, int(l["id"]), who)
	if not who.is_empty():
		var note: String = "The %s damaged the %s. Repairs cost %s" % [cause, "house" if str(l["use"]) != "business" else "building", LTMoney.fmt(cost)]
		if insured and cost > DEDUCTIBLE:
			note += "; insurance paid all but the %s deductible." % LTMoney.fmt(DEDUCTIBLE)
		elif insured:
			note += ", under the deductible, so they paid it all."
		else:
			note += " and there was no insurance, so they paid %s." % LTMoney.fmt(paid)
		w.log_sim(who, note, own_share >= LTMoney.dollars(1000.0))


## Monthly premiums. A household that cannot pay lets the policy lapse; a lender
## requires one, so a lapse on a mortgaged home is noted in its history.
static func monthly_insurance(w: LTWorld) -> void:
	for l in w.lots:
		if not ["house", "apartment", "business", "closed"].has(str(l["use"])):
			continue
		var kind: String = str(l["owner_kind"])
		if kind != "sim" and kind != "business":
			continue
		var premium: int = int(float(l["value"]) * INSURANCE_RATE / 12.0)
		if premium <= 0:
			continue
		var got: int = 0
		if kind == "sim":
			var o: Dictionary = w.cit(int(l["owner_id"]))
			if not w.is_present(o):
				continue
			got = w.household_pay(w.hh(int(o["household"])), "outside", premium, "insurance")
			if got < premium and bool(l.get("insured", true)):
				w.log_sim(o, "Could not pay the home insurance. The policy lapsed: any damage now is theirs to pay in full.", true)
			elif got >= premium and not bool(l.get("insured", true)):
				w.log_sim(o, "Paid the home insurance again. The house is covered.", false)
		else:
			var b: Dictionary = w.biz(int(l["owner_id"]))
			if b.is_empty():
				continue
			got = w.ledger.pay(w.acct_b(b), "outside", premium, "insurance")
		l["insured"] = got >= premium


static func _count(w: LTWorld, key: String) -> void:
	w.counters[key] = int(w.counters.get(key, 0)) + 1
