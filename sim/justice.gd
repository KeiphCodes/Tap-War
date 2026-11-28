class_name LTJustice
extends RefCounted
## Crime, policing, courts, fines and jail. Crimes are scored choices like any
## other. Police funding sets how often they are caught; a court decides; jail
## takes a Sim away from work and family; the record follows them.

const CHARGES: Dictionary = {
	"theft": {"label": "theft", "fine": 25000, "jail": [0, 10], "felony": false},
	"burglary": {"label": "burglary", "fine": 100000, "jail": [30, 120], "felony": true},
	"fraud": {"label": "fraud", "fine": 200000, "jail": [30, 180], "felony": true},
	"tax_evasion": {"label": "tax evasion", "fine": 150000, "jail": [0, 60], "felony": true},
	"unlicensed": {"label": "running an unlicensed business", "fine": 50000, "jail": [0, 0], "felony": false},
	"assault": {"label": "assault", "fine": 80000, "jail": [10, 90], "felony": true},
	"drugs": {"label": "drug possession", "fine": 40000, "jail": [0, 30], "felony": false},
	"nonpayment": {"label": "contempt for unpaid child support", "fine": 0, "jail": [5, 30], "felony": false},
	"health_code": {"label": "health code violations", "fine": 60000, "jail": [0, 0], "felony": false},
}


static func record_count(c: Dictionary) -> int:
	return c.get("record", []).size() + int(c.get("theft_record", 0))


static func in_jail(w: LTWorld, c: Dictionary) -> bool:
	return int(c.get("jail_until", -1)) > w.day


static func daily(w: LTWorld) -> void:
	# cases come to court on their day
	for cs in w.cases:
		if str(cs["status"]) == "pending" and int(cs["trial_day"]) <= w.day:
			_trial(w, cs)
	for c in w.citizens:
		if not w.is_present(c):
			continue
		if int(c.get("jail_until", -1)) == w.day:
			_release(w, c)
		if in_jail(w, c):
			c["needs"]["fun"] = float(c["needs"]["fun"]) - 3.0
			c["needs"]["social"] = float(c["needs"]["social"]) - 3.0
			c["needs"]["respect"] = float(c["needs"]["respect"]) - 1.0
	if w.day % 7 == 5:
		_weekly_crime(w)
	if LTCalendar.day_of_month(w.day) == 12:
		_business_wrongdoing(w)
		_health_inspections(w)


## How likely a crime is seen and solved this week.
## How anonymous the town is, from 0 (everyone knows everyone) to 1 (a small city
## of strangers). In a town of a few hundred, a stranger's car gets noticed and a
## thief is somebody's cousin, so crime is rare and usually solved.
static func anonymity(w: LTWorld) -> float:
	return clampf(float(w.alive_count()) / 3000.0, 0.05, 1.0)


static func detection(w: LTWorld, kind: String) -> float:
	# neighbors are the best police a small town has
	var base: float = LTCivic.enforcement(w) * LTGov.factor(w, "police_chief") + (1.0 - anonymity(w)) * 0.3
	match kind:
		"fraud", "tax_evasion":
			base *= 0.5
		"unlicensed":
			base *= 0.7
		"assault":
			base = minf(0.9, base * 1.4)
	return base


const CRIME_BASE: float = 0.0005
const ASSAULT_BASE: float = 0.00008


static func _weekly_crime(w: LTWorld) -> void:
	var safety: float = LTCivic.safety_level(w)
	var anon: float = anonymity(w)
	# even a desperate person thinks twice when the shopkeeper taught their kids
	var shame: float = 0.35 + 0.65 * anon
	for c in w.citizens:
		if not w.is_present(c) or w.age_years(c) < 14 or in_jail(w, c):
			continue
		var t: Dictionary = c["traits"]
		var n: Dictionary = c["needs"]
		var need: float = (100.0 - float(n["money_security"])) * 0.35 + (100.0 - float(n["hunger"])) * 0.25 + float(t["greed"]) * 0.2
		var restraint: float = float(t["honesty"]) * 0.55 + LTCivic.enforcement(w) * 35.0 + float(t["kindness"]) * 0.1
		var teen: float = 8.0 if w.age_years(c) >= 14 and w.age_years(c) <= 19 else 0.0
		var addict: float = LTHealth.level(c) * 0.15
		var cornered: float = LTFinance.debt_stress(w, c) * 15.0
		var score: float = need + teen + addict + cornered - restraint - 30.0 + w.rng.randf_range(-8.0, 8.0)
		var p_crime: float = (clampf(score / 60.0, 0.0, 0.4) * shame if score > 0.0 else 0.0) + minf(CRIME_BASE * exp((score + 50.0) / 14.0), 0.1) * anon
		if w.rng.randf() < p_crime:
			if w.rng.randf() < 0.25 and float(t["risk"]) > 55.0 and w.age_years(c) >= 17:
				burglary(w, c)
			else:
				LTCivic.theft(w, c, "needed money and did not think they would get caught")
		# assault risk: unsafe areas, drinking, anger
		var anger: float = float(LTHealth.level(c)) * 0.2 + (40.0 - safety) * 0.3 + (100.0 - float(t["kindness"])) * 0.1 - 15.0
		# fights come from grudges, drink and hard times; most are between people who know each other
		var p_fight: float = (anger / 2500.0 if anger > 0.0 else 0.0) + minf(ASSAULT_BASE * exp(anger / 10.0), 0.03)
		if w.age_years(c) >= 16 and w.rng.randf() < p_fight:
			assault(w, c)


static func burglary(w: LTWorld, c: Dictionary) -> void:
	var homes: Array = []
	for h in w.households:
		if int(h["id"]) != int(c["household"]) and int(h["lot"]) >= 0 and w.household_cash(h) > LTMoney.dollars(500.0):
			homes.append(h)
	if homes.is_empty():
		return
	var vh: Dictionary = homes[w.rng.randi_range(0, homes.size() - 1)]
	var victim: Dictionary = w.household_adults(vh)[0]
	var took: int = w.ledger.pay(w.acct_p(victim), w.acct_p(c), mini(w.cash(victim) / 4, LTMoney.dollars(w.rng.randf_range(200.0, 1500.0))), "burglary")
	w.counters["thefts"] = int(w.counters["thefts"]) + 1
	w.counters["burglaries"] = int(w.counters.get("burglaries", 0)) + 1
	w.city["thefts_90d"].append(w.day)
	for m in w.household_members(vh):
		m["needs"]["safety"] = float(m["needs"]["safety"]) - 30.0
		w.remember(m, "robbed", int(c["id"]), -30.0)
	w.log_sim(victim, "The house was broken into. %s was taken." % LTMoney.fmt(took), true)
	w.chronicle_add("The %s home was broken into." % victim["last_name"], "crime", true, [victim["id"]])
	if w.rng.randf() < detection(w, "burglary"):
		charge(w, c, "burglary", "broke into the %s home and took %s" % [victim["last_name"], LTMoney.fmt(took)], int(victim["id"]), took)
	else:
		w.log_sim(c, "Broke into the %s home and took %s. Not caught. Reason: desperate and willing to risk it." % [victim["last_name"], LTMoney.fmt(took)], true)


static func assault(w: LTWorld, c: Dictionary) -> void:
	var victims: Array = []
	for k in c["rel"]:
		var o: Dictionary = w.cit(int(k))
		if w.is_present(o) and float(c["rel"][k]["affection"]) < 40.0:
			victims.append(o)
	if victims.is_empty():
		return
	var v: Dictionary = victims[w.rng.randi_range(0, victims.size() - 1)]
	w.counters["assaults"] = int(w.counters.get("assaults", 0)) + 1
	v["sick_days"] = maxi(int(v["sick_days"]), w.rng.randi_range(2, 10))
	v["health_cond"] = "injured in a fight"
	v["needs"]["health"] = float(v["needs"]["health"]) - 10.0
	v["needs"]["safety"] = float(v["needs"]["safety"]) - 30.0
	w.remember(v, "assaulted", int(c["id"]), -40.0)
	LTPeople.relate_event(w, v, c, "rival", -40.0, -40.0)
	w.log_sim(v, "Was hurt in a fight with %s." % w.full_name(c), true)
	w.chronicle_add("%s was hurt in a fight with %s." % [w.full_name(v), w.full_name(c)], "crime", true, [v["id"], c["id"]])
	if w.rng.randf() < detection(w, "assault"):
		charge(w, c, "assault", "hurt %s in a fight" % w.full_name(v), int(v["id"]), 0)
	else:
		w.log_sim(c, "Got into a fight with %s and hurt them. Nobody pressed charges." % w.full_name(v), true)


static func drug_use(w: LTWorld, c: Dictionary) -> void:
	if w.rng.randf() < detection(w, "drugs") * 0.08:
		charge(w, c, "drugs", "was caught with drugs", -1, 0)


## Business owners: tax evasion, gouging customers through fraud, running without a license.
static func _business_wrongdoing(w: LTWorld) -> void:
	for b in w.businesses:
		if str(b["status"]) != "open" or str(b["type"]) == "landlord":
			continue
		var o: Dictionary = w.cit(int(b["owners"][0]))
		if not w.is_present(o):
			continue
		if bool(b.get("unlicensed", false)) and w.rng.randf() < detection(w, "unlicensed") * 0.5:
			b["unlicensed"] = false
			charge(w, o, "unlicensed", "ran %s without a license" % b["name"], -1, 0)
			b["unlicensed"] = true
			continue
		var t: Dictionary = o["traits"]
		var temptation: float = float(t["greed"]) * 0.6 - float(t["honesty"]) * 0.8 + (20.0 if int(b["loss_months"]) > 0 else 0.0) - LTCivic.enforcement(w) * 30.0
		if temptation < 5.0:
			continue
		if w.rng.randf() < temptation / 200.0:
			# skims the tax: under reports last month's profit
			var ph: Array = b["month_profit_hist"]
			var hidden: int = int(float(maxi(0, int(ph[ph.size() - 1]) if not ph.is_empty() else 0)) * LTCivic.business_tax_rate(w))
			if hidden > LTMoney.dollars(20.0):
				b["evaded_tax"] = int(b.get("evaded_tax", 0)) + hidden
				w.log_sim(o, "Under reported %s's profit to dodge %s in business tax. Reason: greed beat honesty." % [b["name"], LTMoney.fmt(hidden)], false)
				if w.rng.randf() < detection(w, "tax_evasion"):
					charge(w, o, "tax_evasion", "hid profit at %s to dodge %s in tax" % [b["name"], LTMoney.fmt(int(b["evaded_tax"]))], -1, int(b["evaded_tax"]))
					b["evaded_tax"] = 0
		elif w.rng.randf() < temptation / 400.0 and ["repair_shop", "construction", "clinic", "law_office"].has(str(b["type"])):
			# bills customers for work never done
			var victims: Array = w.present_citizens()
			var v: Dictionary = victims[w.rng.randi_range(0, victims.size() - 1)]
			if v["owns"].has(int(b["id"])):
				continue
			var amt: int = w.ledger.pay(w.acct_p(v), w.acct_b(b), LTMoney.dollars(w.rng.randf_range(150.0, 800.0)), "fraud")
			if amt <= 0:
				continue
			w.remember(v, "cheated", int(b["id"]), -25.0)
			w.log_sim(v, "Was billed %s by %s for work that was never done." % [LTMoney.fmt(amt), b["name"]], true)
			b["reputation"] = float(b["reputation"]) - 6.0
			if w.rng.randf() < detection(w, "fraud") + 0.2:
				charge(w, o, "fraud", "billed %s %s for work never done at %s" % [w.full_name(v), LTMoney.fmt(amt), b["name"]], int(v["id"]), amt)


static func _health_inspections(w: LTWorld) -> void:
	var code: float = float(w.city["laws"].get("health_code", 1.0))
	if code <= 0.0:
		return
	for b in w.businesses:
		if str(b["status"]) != "open" or not ["grocery", "cafe", "bakery", "bar", "childcare", "clinic", "hotel"].has(str(b["type"])):
			continue
		if w.rng.randf() > 0.25 * code:
			continue
		var bar: float = 30.0 + code * 15.0
		_spend_inspection(w, b)
		if float(b["cleanliness"]) < bar:
			var o: Dictionary = w.cit(int(b["owners"][0]))
			b["reputation"] = float(b["reputation"]) - 8.0
			w.log_biz(b, "Failed a city health inspection. Cleanliness %d, the code asks for %d." % [int(b["cleanliness"]), int(bar)])
			if float(b["cleanliness"]) < bar - 20.0 and w.is_present(o):
				charge(w, o, "health_code", "kept %s far below the health code" % b["name"], -1, 0)
		else:
			b["reputation"] = minf(100.0, float(b["reputation"]) + 1.0)


static func _spend_inspection(w: LTWorld, b: Dictionary) -> void:
	# owners spend on cleaning to meet the code; the stricter the code, the more
	var cost: int = int(float(LTMoney.dollars(60.0)) * float(w.city["laws"].get("health_code", 1.0)))
	var paid: int = w.ledger.pay(w.acct_b(b), "outside", cost, "code_compliance")
	b["month_costs"] = int(b["month_costs"]) + paid
	b["cleanliness"] = minf(100.0, float(b["cleanliness"]) + float(paid) / 600.0)


# ---------------------------------------------------------------- courts

static func charge(w: LTWorld, c: Dictionary, kind: String, what: String, victim: int, amount: int) -> void:
	var cs: Dictionary = {
		"id": w.cases.size(), "defendant": int(c["id"]), "charge": kind, "what": what, "victim": victim,
		"amount": amount, "filed_day": w.day, "trial_day": w.day + w.rng.randi_range(14, 35),
		"status": "pending", "verdict": "", "sentence": "", "lawyer": false, "trail": [],
	}
	cs["trail"].append({"day": w.day, "text": "Charged with %s: %s." % [CHARGES[kind]["label"], what]})
	w.cases.append(cs)
	w.log_sim(c, "Charged with %s: %s. Court date %s." % [CHARGES[kind]["label"], what, LTCalendar.short(int(cs["trial_day"]))], true)
	w.chronicle_add("%s was charged with %s." % [w.full_name(c), CHARGES[kind]["label"]], "crime", w.involves_watched([c["id"]]) or bool(CHARGES[kind]["felony"]), [c["id"]])
	# hiring a lawyer is a choice: money, the stakes, finance sense
	var stakes: float = 30.0 if bool(CHARGES[kind]["felony"]) else 10.0
	if w.cash(c) > LTMoney.dollars(1500.0) and stakes + float(c["skills"]["finance"]) * 0.2 > 25.0:
		var fee: int = LTMoney.dollars(1200.0 if bool(CHARGES[kind]["felony"]) else 500.0)
		var paid: int = LTServices.spend(w, w.acct_p(c), "legal", fee, int(w.hh(int(c["household"]))["lot"]), c)
		if paid > 0:
			cs["lawyer"] = true
			cs["trail"].append({"day": w.day, "text": "Hired a lawyer for %s." % LTMoney.fmt(paid)})


static func _trial(w: LTWorld, cs: Dictionary) -> void:
	var c: Dictionary = w.cit(int(cs["defendant"]))
	var cfg: Dictionary = CHARGES[str(cs["charge"])]
	if c.is_empty() or not bool(c["alive"]):
		cs["status"] = "closed"
		cs["trail"].append({"day": w.day, "text": "Case closed. The defendant died."})
		return
	if bool(c["left_town"]):
		cs["status"] = "warrant"
		cs["trail"].append({"day": w.day, "text": "The defendant left town. A warrant was issued."})
		return
	# evidence is usually solid; a lawyer and a clean record help
	var convict_p: float = 0.8 - (0.2 if bool(cs["lawyer"]) else 0.0) + float(record_count(c)) * 0.05
	if w.rng.randf() > convict_p:
		cs["status"] = "acquitted"
		cs["verdict"] = "not guilty"
		cs["trail"].append({"day": w.day, "text": "Found not guilty."})
		w.log_sim(c, "Found not guilty of %s." % cfg["label"], true)
		return
	cs["status"] = "convicted"
	cs["verdict"] = "guilty"
	w.counters["convictions"] = int(w.counters.get("convictions", 0)) + 1
	if not c.has("record"):
		c["record"] = []
	var priors: int = record_count(c)
	c["record"].append({"day": w.day, "charge": str(cs["charge"]), "felony": bool(cfg["felony"])})
	var fine: int = int(cfg["fine"]) * (1 + priors / 2)
	var jail_rng: Array = cfg["jail"]
	var days: int = 0
	if int(jail_rng[1]) > 0:
		days = w.rng.randi_range(int(jail_rng[0]), int(jail_rng[1]))
		if priors == 0 and not bool(cfg["felony"]):
			days = 0
		if bool(cs["lawyer"]):
			days = int(float(days) * 0.6)
		days += priors * 10 if days > 0 else 0
	# restitution to the victim; fraud and restitution debts survive bankruptcy
	var parts: Array = []
	if int(cs["amount"]) > 0 and int(cs["victim"]) >= 0:
		var v: Dictionary = w.cit(int(cs["victim"]))
		var back: int = w.ledger.pay(w.acct_p(c), w.acct_p(v) if w.is_present(v) else "outside", int(cs["amount"]), "restitution")
		if back < int(cs["amount"]):
			var d: Dictionary = LTFinance.new_debt(w, "p", int(c["id"]), "person", int(v["id"]), "fraud", int(cs["amount"]) - back, 0.0, 24, "", -1, [])
			parts.append("ordered to repay %s, %s still owed and bankruptcy cannot erase it" % [LTMoney.fmt(int(cs["amount"])), LTMoney.fmt(int(d["balance"]))])
		else:
			parts.append("repaid %s to the victim" % LTMoney.fmt(back))
	elif str(cs["charge"]) == "tax_evasion" and int(cs["amount"]) > 0:
		var tback: int = w.ledger.pay(w.acct_p(c), "city", int(cs["amount"]), "back_taxes")
		if tback < int(cs["amount"]):
			LTFinance.new_debt(w, "p", int(c["id"]), "city", -1, "tax", int(cs["amount"]) - tback, 0.08, 24, "", -1, [])
		parts.append("ordered to pay %s in back taxes" % LTMoney.fmt(int(cs["amount"])))
	if fine > 0:
		var fpaid: int = w.ledger.pay(w.acct_p(c), "city", fine, "court_fines")
		if fpaid < fine:
			LTFinance.new_debt(w, "p", int(c["id"]), "city", -1, "tax", fine - fpaid, 0.0, 12, "", -1, [])
		parts.append("fined %s" % LTMoney.fmt(fine))
	if days > 0:
		jail(w, c, days, str(cfg["label"]))
		parts.append("%d days in the county jail" % days)
	else:
		c["probation_until"] = w.day + 180
		parts.append("six months of probation")
	if str(cs["charge"]) == "unlicensed" or str(cs["charge"]) == "health_code":
		for bid in c["owns"].duplicate():
			var b: Dictionary = w.biz(int(bid))
			if str(cs["charge"]) == "unlicensed" and bool(b.get("unlicensed", false)):
				# a first offense: pay the fine, get licensed and keep the doors open;
				# a second one closes the business, as courts and cities really do
				if int(b.get("license_strikes", 0)) >= 1:
					LTEconomy.close_business(w, b, "the court shut it down for operating without a license a second time")
				else:
					b["license_strikes"] = 1
					var fee: int = int(float(LTEconomy.tcfg(str(b["type"]))["license"]) * LTCivic.law(w, "license_fee"))
					var got: int = w.ledger.pay(w.acct_b(b), "city", fee, "license_fees")
					if got >= fee:
						b["unlicensed"] = false
						parts.append("ordered to buy the license, which %s did" % c["first_name"])
					else:
						LTEconomy.close_business(w, b, "the court ordered it licensed and the owner could not pay the fee")
	cs["sentence"] = ", ".join(parts)
	cs["trail"].append({"day": w.day, "text": "Guilty. %s." % (str(cs["sentence"]).substr(0, 1).to_upper() + str(cs["sentence"]).substr(1))})
	w.remember(c, "convicted", -1, -40.0)
	w.log_sim(c, "Found guilty of %s: %s. The record will follow them to every job application." % [cfg["label"], cs["sentence"]], true)
	w.chronicle_add("%s was found guilty of %s: %s." % [w.full_name(c), cfg["label"], cs["sentence"]], "crime", true, [c["id"]])


static func jail(w: LTWorld, c: Dictionary, days: int, why: String) -> void:
	c["jail_until"] = w.day + days
	# employers do not hold a job for a long absence
	var kind: String = str(c["job"]["kind"])
	if kind != "none" and kind != "owner" and days > 10:
		LTEconomy.leave_job(w, c, "sent to jail for %s" % why)
	if kind == "owner" and days > 30:
		for bid in c["owns"]:
			var b: Dictionary = w.biz(int(bid))
			w.log_biz(b, "The owner is in jail for %d days. The staff keep it going as they can." % days)
	for k in c["rel"]:
		var r: Dictionary = c["rel"][k]
		if ["spouse", "child", "parent"].has(str(r["kind"])):
			var o: Dictionary = w.cit(int(k))
			if w.is_present(o):
				o["needs"]["family"] = float(o["needs"]["family"]) - 25.0
				w.log_sim(o, "%s went to jail for %d days." % [w.full_name(c), days], true)
	w.log_sim(c, "Went to the county jail for %d days." % days, true)


static func _release(w: LTWorld, c: Dictionary) -> void:
	c["jail_until"] = -1
	c["probation_until"] = w.day + 180
	w.log_sim(c, "Released from jail. On probation for six months, with a record that makes finding work harder.", true)
	w.chronicle_add("%s was released from the county jail." % w.full_name(c), "crime", w.involves_watched([c["id"]]), [c["id"]])
