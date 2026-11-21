class_name LTRegion
extends RefCounted
## Tier 3: the county around the town, simulated statistically. Its economy rises
## and falls, its employers hire and fail, its suppliers run short, and its storms
## reach town. Nobody out here is a full Sim, but town Sims feel all of it.

const EMPLOYERS: Array = [
	{"name": "Great Plains Meatpacking", "titles": ["factory worker", "line cook"], "jobs": 900},
	{"name": "Dakota Window Works", "titles": ["factory worker", "construction laborer"], "jobs": 400},
	{"name": "County Medical Center", "titles": ["nursing aide", "office clerk"], "jobs": 600},
	{"name": "Northern Freight Lines", "titles": ["truck driver", "warehouse worker"], "jobs": 350},
	{"name": "Valley Co-op", "titles": ["farm hand", "store clerk", "warehouse worker"], "jobs": 300},
	{"name": "County Seat Offices", "titles": ["office clerk", "store clerk"], "jobs": 500},
]


static func setup(w: LTWorld) -> void:
	var emps: Array = []
	for e in EMPLOYERS:
		var d: Dictionary = e.duplicate(true)
		d["health"] = w.rng.randf_range(0.55, 0.95)
		d["open"] = true
		emps.append(d)
	w.region = {
		"name": "the county", "population": 42000, "index": 1.0, "phase": "steady", "phase_months": 0,
		"unemployment": 0.045, "employers": emps, "shortages": {}, "history": [], "storms": 0,
	}


static func index(w: LTWorld) -> float:
	return float(w.region.get("index", 1.0))


static func layoff_mult(w: LTWorld) -> float:
	return clampf(2.2 - index(w) * 1.2, 0.5, 2.5)


static func hire_mult(w: LTWorld) -> float:
	return clampf(index(w) * 1.3 - 0.3, 0.3, 1.4)


static func employer_for(w: LTWorld, title: String) -> String:
	var options: Array = []
	for e in w.region["employers"]:
		if bool(e["open"]) and e["titles"].has(title):
			options.append(str(e["name"]))
	if options.is_empty():
		return "an employer in the county seat"
	return options[w.rng.randi_range(0, options.size() - 1)]


static func employer_open(w: LTWorld, name: String) -> bool:
	for e in w.region["employers"]:
		if str(e["name"]) == name:
			return bool(e["open"])
	return true


static func shortage(w: LTWorld, btype: String) -> bool:
	return int(w.region["shortages"].get(btype, -1)) >= w.day


static func daily(w: LTWorld) -> void:
	if LTCalendar.is_month_start(w.day):
		_month(w)
	if w.weather == "Storm" and w.rng.randf() < 0.03:
		_storm(w)
	# shortages come more often in winter and in hard times
	if w.rng.randf() < 0.0025 * (1.5 if LTCalendar.season(w.day) == "Winter" else 1.0) * (2.0 - index(w)):
		var kinds: Array = ["grocery", "general_store", "cafe"]
		var k: String = kinds[w.rng.randi_range(0, kinds.size() - 1)]
		if not shortage(w, k):
			var days: int = w.rng.randi_range(8, 20)
			w.region["shortages"][k] = w.day + days
			var what: String = {"grocery": "food", "general_store": "household goods", "cafe": "restaurant supplies"}[k]
			w.chronicle_add("Valley Wholesale is short on %s across the region for about %d days. Local shelves will run thin." % [what, days], "region", true, [])


static func _month(w: LTWorld) -> void:
	var r: Dictionary = w.region
	r["phase_months"] = int(r["phase_months"]) + 1
	var idx: float = float(r["index"])
	var phase: String = str(r["phase"])
	# a slow business cycle: years of steady growth, now and then a downturn
	if int(r["phase_months"]) > 6:
		var roll: float = w.rng.randf()
		match phase:
			"steady", "growth":
				if roll < 0.04:
					phase = "slowdown"
				elif roll < 0.12:
					phase = "growth"
				else:
					phase = "steady"
			"slowdown":
				phase = "recession" if roll < 0.45 else "steady"
			"recession":
				if roll < 0.3:
					phase = "recovery"
			"recovery":
				if roll < 0.35:
					phase = "growth"
		if phase != str(r["phase"]):
			r["phase_months"] = 0
			w.chronicle_add(_phase_text(phase), "region", phase == "recession", [])
	var drift: float = {"steady": 0.0, "growth": 0.012, "slowdown": -0.012, "recession": -0.025, "recovery": 0.018}[phase]
	idx = clampf(idx + drift + w.rng.randf_range(-0.01, 0.01) + (1.0 - idx) * 0.03, 0.6, 1.3)
	r["index"] = idx
	r["phase"] = phase
	r["unemployment"] = clampf(0.045 + (1.0 - idx) * 0.12, 0.025, 0.14)
	r["history"].append({"day": w.day, "index": idx, "phase": phase})
	if r["history"].size() > 240:
		r["history"].remove_at(0)
	# employers rise and fall with the region; a weak one in a bad year can close
	for e in r["employers"]:
		if not bool(e["open"]):
			if idx > 1.05 and w.rng.randf() < 0.05:
				e["open"] = true
				e["health"] = 0.6
				w.chronicle_add("%s reopened in the county seat and is hiring." % e["name"], "region", true, [])
			continue
		e["health"] = clampf(float(e["health"]) + (idx - 1.0) * 0.08 + w.rng.randf_range(-0.05, 0.05), 0.0, 1.0)
		if float(e["health"]) < 0.15 and w.rng.randf() < 0.35:
			_employer_fails(w, e)


static func _phase_text(phase: String) -> String:
	match phase:
		"growth":
			return "The county economy is growing. Outside employers are hiring."
		"slowdown":
			return "The county economy is slowing down. Fewer outside jobs are opening."
		"recession":
			return "The county is in a recession. Outside employers are laying people off."
		"recovery":
			return "The county economy is starting to recover."
	return "The county economy has settled."


static func _employer_fails(w: LTWorld, e: Dictionary) -> void:
	e["open"] = false
	var hit: Array = []
	for c in w.citizens:
		if w.is_present(c) and str(c["job"]["kind"]) == "outside" and str(c["job"].get("employer_name", "")) == str(e["name"]):
			hit.append(c["id"])
			w.log_sim(c, "Lost the job as a %s when %s shut down. Reason: the company failed in a bad year." % [c["job"]["title"], e["name"]], true)
			w.remember(c, "fired", -1, -30.0)
			LTPeople.clear_job(w, c)
			w.counters["layoffs"] = int(w.counters["layoffs"]) + 1
	w.chronicle_add("%s shut down in the county seat. %d people from town lost their jobs." % [e["name"], hit.size()], "region", true, hit)


static func _storm(w: LTWorld) -> void:
	w.region["storms"] = int(w.region["storms"]) + 1
	var hit: int = 0
	var fire_q: float = float(w.city["laws"].get("fire_funding", 1.0))
	var code: float = float(w.city["laws"].get("building_code", 1.0))
	for l in w.lots:
		if str(l["use"]) == "empty" or w.rng.randf() > 0.25:
			continue
		var dmg: float = w.rng.randf_range(4.0, 18.0) * (1.4 - code * 0.25) * (1.2 - fire_q * 0.15)
		l["condition"] = maxf(0.0, float(l["condition"]) - dmg)
		hit += 1
		# owners pay for repairs, local builders and repair shops get the work if they exist
		var cost: int = int(dmg * float(LTMoney.dollars(90.0)))
		match str(l["owner_kind"]):
			"sim":
				var o: Dictionary = w.cit(int(l["owner_id"]))
				if w.is_present(o):
					var paid: int = LTServices.spend(w, w.acct_p(o), "repairs", cost, int(l["id"]), o)
					w.log_sim(o, "The storm damaged the house. Paid %s for repairs." % LTMoney.fmt(paid), true)
			"business":
				var b: Dictionary = w.biz(int(l["owner_id"]))
				LTServices.spend(w, w.acct_b(b), "repairs", cost, int(l["id"]))
		if str(l["use"]) == "business":
			var b2: Dictionary = w.biz(int(l["ref"]))
			if not b2.is_empty():
				b2["condition"] = maxf(0.0, float(b2["condition"]) - dmg)
	for s in w.roads:
		if bool(s.get("planned", false)) or bool(s.get("removed", false)):
			continue
		if w.rng.randf() < 0.3:
			s["condition"] = maxf(0.0, float(s["condition"]) - w.rng.randf_range(2.0, 8.0))
	w.dist_cache.clear()
	w.chronicle_add("A storm hit town and damaged %d buildings and several roads." % hit, "region", true, [])
