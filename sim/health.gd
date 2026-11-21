class_name LTHealth
extends RefCounted
## Pregnancy, work injuries, mental health and addiction. All of it comes from the
## same needs and scoring as everything else. Nothing here is graphic: it shows up
## in lives, money, panels and outcomes.

const RISKY_JOBS: Dictionary = {"construction worker": 3.0, "construction laborer": 3.0, "farm hand": 2.0, "factory worker": 2.5, "truck driver": 2.0, "mill hand": 2.0, "warehouse worker": 1.5, "mechanic": 1.5}


static func daily(w: LTWorld) -> void:
	for c in w.citizens:
		if not w.is_present(c):
			continue
		if not c.get("pregnant", {}).is_empty():
			_pregnancy_day(w, c)
		if int(c.get("leave_until", -1)) == w.day:
			w.log_sim(c, "Back at work after leave.", false)
		var age: int = w.age_years(c)
		if age >= 16 and str(c["job"]["kind"]) != "none" and not LTCalendar.is_weekend(w.day):
			_injury_check(w, c)
		if age >= 14:
			_mental(w, c)
			if int(c["id"]) % 7 == (w.day + 3) % 7:
				_coping(w, c)
			_addiction_effects(w, c)


# ---------------------------------------------------------------- pregnancy

static func conceive(w: LTWorld, m: Dictionary, father: Dictionary, reason: String) -> void:
	m["pregnant"] = {"due": w.day + w.rng.randi_range(262, 280), "father": int(father["id"]), "since": w.day}
	w.log_sim(m, "Expecting a baby with %s. Reason: %s." % [w.full_name(father), reason], true)
	w.log_sim(father, "%s is expecting their baby." % m["first_name"], true)
	w.chronicle_add("%s and %s are expecting a baby." % [w.full_name(m), w.full_name(father)], "family", w.involves_watched([m["id"], father["id"]]), [m["id"], father["id"]])


static func _pregnancy_day(w: LTWorld, m: Dictionary) -> void:
	var p: Dictionary = m["pregnant"]
	var home: int = int(w.hh(int(m["household"]))["lot"])
	if (w.day - int(p["since"])) % 30 == 15:
		# prenatal checkups
		LTServices.spend(w, w.acct_p(m), "medical", LTMoney.dollars(90.0), home, m)
	m["needs"]["energy"] = float(m["needs"]["energy"]) - 3.0
	if w.day >= int(p["due"]):
		var father: Dictionary = w.cit(int(p["father"]))
		m["pregnant"] = {}
		LTServices.spend(w, w.acct_p(m), "medical", LTMoney.dollars(2400.0), home, m)
		LTPeople.give_birth(w, m, father)
		# six weeks of leave; an outside job may not hold the place
		m["leave_until"] = w.day + 42
		if str(m["job"]["kind"]) == "outside" and w.rng.randf() < 0.25:
			w.log_sim(m, "The outside employer did not hold the job during maternity leave.", true)
			LTPeople.clear_job(w, m)


static func on_leave(w: LTWorld, c: Dictionary) -> bool:
	return int(c.get("leave_until", -1)) > w.day or int(c.get("jail_until", -1)) > w.day or int(c.get("treatment_until", -1)) > w.day


# ---------------------------------------------------------------- injuries at work

static func _injury_check(w: LTWorld, c: Dictionary) -> void:
	if on_leave(w, c) or int(c["sick_days"]) > 0:
		return
	var title: String = str(c["job"]["title"])
	var risk: float = float(RISKY_JOBS.get(title, 0.4))
	var sk: String = str(c["job"]["skill"])
	var skill: float = float(c["skills"].get(sk, 40.0)) if sk != "" else 40.0
	var p: float = 0.00006 * risk * (1.6 - skill / 100.0)
	if float(c.get("addiction", {}).get("alcohol", 0.0)) > 50.0 or float(c.get("addiction", {}).get("drugs", 0.0)) > 40.0:
		p *= 2.0
	if w.rng.randf() >= p:
		return
	var severe: bool = w.rng.randf() < 0.2
	c["sick_days"] = w.rng.randi_range(20, 60) if severe else w.rng.randi_range(4, 14)
	c["health_cond"] = "work injury"
	c["needs"]["health"] = float(c["needs"]["health"]) - (25.0 if severe else 8.0)
	var bill: int = LTMoney.dollars(4500.0 if severe else 600.0)
	var where: String = "on the job as a %s" % title
	# workers compensation: a local employer's insurance pays, an outside employer's insurer pays
	var job: Dictionary = c["job"]
	if str(job["kind"]) == "business":
		var b: Dictionary = w.biz(int(job["employer"]))
		var paid: int = LTServices.spend(w, w.acct_b(b), "medical", bill, int(b["lot"]))
		b["month_costs"] = int(b["month_costs"]) + paid
		w.log_biz(b, "%s was hurt at work. The business paid %s in medical costs." % [w.full_name(c), LTMoney.fmt(paid)])
	elif str(job["kind"]) == "outside":
		w.ledger.pay("outside", w.acct_p(c), 0, "none")
	if severe and w.rng.randf() < 0.3:
		c["disability"] = true
		w.log_sim(c, "Was badly hurt %s and now has a lasting disability. Heavy work is no longer possible." % where, true)
		w.chronicle_add("%s was badly hurt at work." % w.full_name(c), "health", true, [c["id"]])
		if RISKY_JOBS.has(title):
			LTEconomy.leave_job(w, c, "a disability from the injury")
	else:
		w.log_sim(c, "Was hurt %s. Off work for %d days." % [where, c["sick_days"]], true)


# ---------------------------------------------------------------- mental health

static func _mental(w: LTWorld, c: Dictionary) -> void:
	var hap: float = LTPeople.happiness(c)
	var stress: int = int(c.get("stress_days", 0))
	if hap < 38.0 or float(c["needs"]["money_security"]) < 15.0:
		stress += 1
	else:
		stress = maxi(0, stress - 2)
	c["stress_days"] = stress
	if not bool(c.get("depressed", false)) and stress > 60 and w.rng.randf() < 0.02 * (1.4 - float(c["traits"]["discipline"]) / 100.0):
		c["depressed"] = true
		w.log_sim(c, "Fell into depression after months of pressure. Low energy, hard to keep going.", true)
	if bool(c.get("depressed", false)):
		c["needs"]["energy"] = float(c["needs"]["energy"]) - 4.0
		c["needs"]["fun"] = float(c["needs"]["fun"]) - 3.0
		# getting help is a choice too: kindness of family, the clinic, city support
		if int(c["id"]) % 30 == w.day % 30:
			var help: float = float(c["traits"]["discipline"]) * 0.3 + _family_push(w, c) + float(w.city["laws"].get("health_funding", 0.5)) * 15.0
			if help > 30.0:
				var paid: int = LTServices.spend(w, w.acct_p(c), "medical", LTMoney.dollars(160.0), int(w.hh(int(c["household"]))["lot"]), c)
				if paid > 0:
					c["therapy_months"] = int(c.get("therapy_months", 0)) + 1
					w.log_sim(c, "Saw a counselor for depression.", false)
		if stress == 0 or (int(c.get("therapy_months", 0)) >= 3 and hap > 45.0):
			c["depressed"] = false
			c["therapy_months"] = 0
			w.log_sim(c, "Came out of the depression. Life feels manageable again.", true)


static func _family_push(w: LTWorld, c: Dictionary) -> float:
	var t: float = 0.0
	for k in c["rel"]:
		var r: Dictionary = c["rel"][k]
		if ["spouse", "parent", "child", "friend"].has(str(r["kind"])):
			var o: Dictionary = w.cit(int(k))
			if w.is_present(o):
				t = maxf(t, float(o["traits"]["kindness"]) * 0.3 + float(r["affection"]) * 0.1)
	return t


# ---------------------------------------------------------------- addiction

static func _add(c: Dictionary) -> Dictionary:
	if not c.has("addiction"):
		c["addiction"] = {"alcohol": 0.0, "gambling": 0.0, "drugs": 0.0}
	return c["addiction"]


static func level(c: Dictionary) -> float:
	var a: Dictionary = c.get("addiction", {})
	var m: float = 0.0
	for k in a:
		m = maxf(m, float(a[k]))
	return m


## Coping under pressure is scored like everything else. Some Sims drink, gamble or
## use. Discipline, family and fear of the law push the other way.
static func _coping(w: LTWorld, c: Dictionary) -> void:
	if on_leave(w, c) and int(c.get("treatment_until", -1)) > w.day:
		return
	var age: int = w.age_years(c)
	var t: Dictionary = c["traits"]
	var a: Dictionary = _add(c)
	var pressure: float = (60.0 - LTPeople.happiness(c)) + (40.0 - float(c["needs"]["money_security"])) * 0.5 + (20.0 if bool(c.get("depressed", false)) else 0.0)
	var resist: float = float(t["discipline"]) * 0.5 + _family_push(w, c) * 0.4
	var cash_ok: bool = w.cash(c) > LTMoney.dollars(30.0)
	for kind in ["alcohol", "gambling", "drugs"]:
		var lvl: float = float(a[kind])
		var pull: float = pressure * 0.4 + float(t["risk"]) * 0.2 + lvl * 0.8
		match kind:
			"alcohol":
				if age < 18:
					pull -= 25.0
			"gambling":
				pull += float(t["greed"]) * 0.15 - 10.0
			"drugs":
				pull -= 20.0 + float(t["honesty"]) * 0.2 + LTCivic.enforcement(w) * 20.0
				if age >= 15 and age <= 25:
					pull += 10.0
		if pull - resist > 5.0 and (cash_ok or lvl > 50.0) and w.rng.randf() < 0.5:
			_use(w, c, kind)
		elif lvl > 0.0:
			a[kind] = maxf(0.0, lvl - 1.5)
	_maybe_treatment(w, c)


static func drink(w: LTWorld, c: Dictionary, paid: int) -> void:
	var a: Dictionary = _add(c)
	var lvl: float = float(a["alcohol"])
	# most people drink socially and nothing comes of it
	if LTPeople.happiness(c) < 45.0 or lvl > 20.0:
		a["alcohol"] = minf(100.0, lvl + 1.2)


static func _use(w: LTWorld, c: Dictionary, kind: String) -> void:
	var a: Dictionary = _add(c)
	var before: float = float(a[kind])
	a[kind] = minf(100.0, before + 4.0 + float(c["traits"]["risk"]) / 40.0)
	var home: int = int(w.hh(int(c["household"]))["lot"])
	match kind:
		"alcohol":
			var amt: int = LTMoney.dollars(12.0 + before * 0.5)
			var paid: int = LTServices.spend(w, w.acct_p(c), "bar", amt, home, c)
			if paid == 0:
				w.ledger.pay(w.acct_p(c), "outside", amt, "liquor_store")
			c["needs"]["fun"] = float(c["needs"]["fun"]) + 8.0
		"gambling":
			# the casino two counties over: most nights lose, now and then a win
			var stake: int = mini(w.cash(c), LTMoney.dollars(20.0 + before * 3.0))
			var lost: int = w.ledger.pay(w.acct_p(c), "outside", stake, "gambling")
			if w.rng.randf() < 0.18:
				w.ledger.pay("outside", w.acct_p(c), int(float(lost) * 2.0), "gambling_wins")
			c["needs"]["fun"] = float(c["needs"]["fun"]) + 10.0
		"drugs":
			var cost: int = LTMoney.dollars(25.0 + before * 0.8)
			w.ledger.pay(w.acct_p(c), "outside", cost, "drugs")
			c["needs"]["fun"] = float(c["needs"]["fun"]) + 15.0
			LTJustice.drug_use(w, c)
	if before < 30.0 and float(a[kind]) >= 30.0:
		w.log_sim(c, "Started leaning on %s to cope. Reason: under pressure and not much holding them back." % _kind_word(kind), true)
	if before < 60.0 and float(a[kind]) >= 60.0:
		w.log_sim(c, "%s has become an addiction. It now costs money, health and trust at home." % _kind_word(kind).capitalize(), true)
		w.chronicle_add("%s is struggling with %s." % [w.full_name(c), _kind_word(kind)], "health", w.involves_watched([c["id"]]), [c["id"]])


static func _kind_word(kind: String) -> String:
	return {"alcohol": "drinking", "gambling": "gambling", "drugs": "drugs"}[kind]


static func _addiction_effects(w: LTWorld, c: Dictionary) -> void:
	var a: Dictionary = c.get("addiction", {})
	if a.is_empty():
		return
	var al: float = float(a["alcohol"])
	var dr: float = float(a["drugs"])
	var ga: float = float(a["gambling"])
	if al > 50.0:
		c["needs"]["health"] = float(c["needs"]["health"]) - (al - 50.0) * 0.004
	if dr > 40.0:
		c["needs"]["health"] = float(c["needs"]["health"]) - (dr - 40.0) * 0.008
	var worst: float = maxf(al, maxf(dr, ga))
	if worst < 55.0:
		return
	# work suffers, the family pays
	if str(c["job"]["kind"]) in ["business", "outside", "city"] and w.rng.randf() < (worst - 55.0) * 0.00012:
		w.log_sim(c, "Lost the job as a %s. Reason: kept showing up late or not at all because of %s." % [c["job"]["title"], _kind_word(_worst_kind(a))], true)
		w.remember(c, "fired", -1, -25.0)
		LTEconomy.leave_job(w, c, "fired for missing work")
	if int(c["spouse"]) >= 0 and w.rng.randf() < 0.05:
		var sp: Dictionary = w.cit(int(c["spouse"]))
		if w.is_present(sp):
			LTPeople.relate_event(w, sp, c, "spouse", -2.0, -2.5)


static func _worst_kind(a: Dictionary) -> String:
	var best: String = "alcohol"
	for k in a:
		if float(a[k]) > float(a[best]):
			best = k
	return best


static func _maybe_treatment(w: LTWorld, c: Dictionary) -> void:
	if level(c) < 55.0 or int(c.get("treatment_until", -1)) > w.day:
		return
	var t: Dictionary = c["traits"]
	var push: float = _family_push(w, c) + float(t["discipline"]) * 0.3 + float(w.city["laws"].get("health_funding", 0.5)) * 12.0
	push += float(w.age_years(c) - 40) * 0.4
	if c.has("treatment_count"):
		push -= float(c["treatment_count"]) * 5.0
	if push + w.rng.randf_range(-10.0, 10.0) < 42.0:
		return
	var cost: int = LTMoney.dollars(1800.0)
	var city_part: int = int(float(cost) * clampf(float(w.city["laws"].get("health_funding", 0.5)) * 0.3, 0.0, 0.6))
	w.ledger.pay("city", "outside", city_part, "treatment support")
	var home: int = int(w.hh(int(c["household"]))["lot"])
	var paid: int = LTServices.spend(w, w.acct_p(c), "medical", cost - city_part, home, c)
	if paid < (cost - city_part) / 2:
		return
	c["treatment_until"] = w.day + 28
	c["treatment_count"] = int(c.get("treatment_count", 0)) + 1
	var a: Dictionary = c["addiction"]
	var k: String = _worst_kind(a)
	a[k] = float(a[k]) * (0.3 if w.rng.randf() < 0.6 else 0.7)
	w.log_sim(c, "Went into a 28 day treatment program for %s. Reason: family pressure and wanting their life back." % _kind_word(k), true)
	w.chronicle_add("%s went into treatment for %s." % [w.full_name(c), _kind_word(k)], "health", w.involves_watched([c["id"]]), [c["id"]])
