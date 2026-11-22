class_name LTChoices
## Everyday choices Sims make about their own lives, beyond jobs, homes, money and
## family: helping someone they love through a bad month, taking extra shifts,
## going back to school at night, volunteering, and caring for an aging parent.
## Each comes from the Sim's traits, needs and relationships, never from a dice
## roll alone, and each is written in their history with the reason.

const CLASS_TUITION: int = 120000       # $1,200 a term at the county college
const CLASS_DAYS: int = 120
const VOLUNTEER_KINDS: Dictionary = {
	"fire": "the volunteer fire department",
	"pantry": "the church food pantry",
	"coach": "youth sports as a coach",
	"seniors": "meals for shut in seniors",
}


static func monthly(w: LTWorld) -> void:
	for c in w.citizens:
		if not w.is_present(c) or w.age_years(c) < 18 or LTJustice.in_jail(w, c):
			continue
		_extra_work(w, c)
		_night_classes(w, c)
		_volunteer(w, c)
		_help_someone(w, c)
		_care_for_parent(w, c)


## Daily: classes finish, extra shifts end.
static func daily(w: LTWorld) -> void:
	for c in w.citizens:
		if not w.is_present(c):
			continue
		var st: Dictionary = c.get("study", {})
		if not st.is_empty() and w.day >= int(st["until"]):
			_finish_classes(w, c)
		var sj: Dictionary = c.get("side_job", {})
		if not sj.is_empty() and w.day >= int(sj["until"]):
			c["side_job"] = {}
			w.log_sim(c, "Stopped the extra shifts. Reason: %s." % ("the money is steadier now" if float(c["needs"]["money_security"]) > 40.0 else "worn out"), false)


# ---------------------------------------------------------------- extra work

static func _extra_work(w: LTWorld, c: Dictionary) -> void:
	var sj: Dictionary = c.get("side_job", {})
	var n: Dictionary = c["needs"]
	var t: Dictionary = c["traits"]
	if not sj.is_empty():
		# a month of extra shifts: more money, less rest and family time
		var got: int = w.ledger.pay("outside", w.acct_p(c), int(sj["monthly"]), "wages")
		n["energy"] = float(n["energy"]) - 8.0
		n["family"] = float(n["family"]) - 6.0
		n["social"] = float(n["social"]) - 4.0
		sj["earned"] = int(sj.get("earned", 0)) + got
		if float(n["money_security"]) > 55.0 and w.rng.randf() < 0.5:
			sj["until"] = w.day
		return
	if str(c["job"]["kind"]) == "none" or bool(c["retired"]) or w.age_years(c) > 66:
		return
	var pressed: float = (40.0 - float(n["money_security"])) + LTFinance.debt_stress(w, c) * 30.0
	if pressed <= 0.0 or float(n["energy"]) < 35.0:
		return
	var will: float = (float(t["discipline"]) + float(t["ambition"])) / 200.0
	if w.rng.randf() >= clampf(pressed / 100.0 * will, 0.0, 0.5):
		return
	var what: Array = ["weekend shifts at the grain elevator", "driving deliveries at night", "helping on a farm at harvest", "cleaning offices in the county seat", "extra shifts at work"]
	var job: String = what[w.rng.randi_range(0, what.size() - 1)]
	var monthly: int = int(float(c["job"]["daily_wage"]) * 0.3 * 21.0)
	c["side_job"] = {"until": w.day + w.rng.randi_range(60, 150), "monthly": monthly, "what": job}
	_count(w, "side_jobs")
	w.log_sim(c, "Took on %s for about %s a month. Reason: %s, and %s." % [job, LTMoney.fmt(monthly), "bills were piling up" if LTFinance.debt_stress(w, c) > 0.3 else "money was too tight", "would rather work more than fall behind" if float(t["discipline"]) > 50.0 else "the family needs it"], true)


# ---------------------------------------------------------------- night classes

static func _night_classes(w: LTWorld, c: Dictionary) -> void:
	if not c.get("study", {}).is_empty() or not c.get("side_job", {}).is_empty():
		return
	var age: int = w.age_years(c)
	var t: Dictionary = c["traits"]
	if age > 55 or bool(c["retired"]) or float(t["ambition"]) < 55.0 or float(t["intelligence"]) < 40.0:
		return
	var stuck: bool = str(c["job"]["kind"]) == "none" or float(c["job"]["daily_wage"]) < float(LTMoney.dollars(135.0))
	if not stuck:
		return
	if w.rng.randf() >= (float(t["ambition"]) - 50.0) / 400.0:
		return
	# the skill the town needs most from what they already know a little
	var skill: String = ""
	var best: float = -1.0
	for k in LTPeople.SKILL_KEYS:
		var v: float = float(c["skills"][k])
		var want: float = (100.0 - v) * 0.3 + v * 0.7 + w.rng.randf_range(0.0, 15.0)
		if v < 85.0 and want > best:
			best = want
			skill = k
	if skill == "":
		return
	var paid: String = "savings"
	if w.cash(c) >= CLASS_TUITION + LTMoney.dollars(800.0):
		w.ledger.pay(w.acct_p(c), "outside", CLASS_TUITION, "tuition")
	elif bool(c["credit"]["has_file"]) and int(c["credit"]["score"]) >= 560:
		# a small student loan from the college's lender
		LTFinance.new_debt(w, "p", int(c["id"]), "college", -1, "student_loan", CLASS_TUITION, 0.055, 60, "", -1, [])
		paid = "a student loan"
	else:
		w.log_sim(c, "Wanted to take night classes in %s but could not pay the %s tuition." % [skill, LTMoney.fmt(CLASS_TUITION)], false)
		return
	c["study"] = {"skill": skill, "until": w.day + CLASS_DAYS, "start": w.day}
	_count(w, "night_classes")
	w.log_sim(c, "Signed up for night classes in %s at the county college, paid with %s. Reason: %s." % [skill, paid, "out of work and wants a better shot" if str(c["job"]["kind"]) == "none" else "tired of a low paying job"], true)


static func _finish_classes(w: LTWorld, c: Dictionary) -> void:
	var st: Dictionary = c["study"]
	var skill: String = str(st["skill"])
	var t: Dictionary = c["traits"]
	var gain: float = 8.0 + float(t["intelligence"]) / 10.0 + float(t["discipline"]) / 20.0
	if float(c["needs"]["energy"]) < 25.0 and w.rng.randf() < 0.4:
		c["study"] = {}
		w.log_sim(c, "Dropped out of the %s classes. Too tired to keep up." % skill, true)
		return
	c["skills"][skill] = minf(100.0, float(c["skills"][skill]) + gain)
	c["education"] = float(c.get("education", 0.0)) + 0.5
	c["study"] = {}
	c["needs"]["respect"] = float(c["needs"]["respect"]) + 10.0
	w.log_sim(c, "Finished night classes in %s. Skill up %d points, to %d." % [skill, int(gain), int(c["skills"][skill])], true)


# ---------------------------------------------------------------- volunteering

static func volunteers(w: LTWorld, kind: String) -> int:
	var n: int = 0
	for c in w.citizens:
		if w.is_present(c) and str(c.get("volunteer", "")) == kind:
			n += 1
	return n


static func _volunteer(w: LTWorld, c: Dictionary) -> void:
	var t: Dictionary = c["traits"]
	var n: Dictionary = c["needs"]
	var cur: String = str(c.get("volunteer", ""))
	if cur != "":
		n["social"] = float(n["social"]) + 6.0
		n["respect"] = float(n["respect"]) + 4.0
		n["energy"] = float(n["energy"]) - 3.0
		# people drop out when life gets heavy
		if (not c.get("side_job", {}).is_empty() or float(n["energy"]) < 20.0) and w.rng.randf() < 0.3:
			c["volunteer"] = ""
			w.log_sim(c, "Stepped back from %s. Reason: no time or energy left." % VOLUNTEER_KINDS[cur], false)
		elif cur == "fire" and w.age_years(c) > 62:
			c["volunteer"] = ""
			w.log_sim(c, "Retired from the volunteer fire department after years on the crew.", true)
		return
	if not c.get("side_job", {}).is_empty() or not c.get("study", {}).is_empty():
		return
	var pull: float = (float(t["kindness"]) + float(t["sociability"])) / 2.0 - 50.0 + (100.0 - float(n["social"])) * 0.1
	if pull <= 0.0 or w.rng.randf() >= pull / 600.0:
		return
	var options: Array = ["pantry", "seniors"]
	if w.age_years(c) <= 55 and float(t["risk"]) > 40.0:
		options.append("fire")
		options.append("fire")
	if w.age_years(c) <= 60 and _kids_in_town(w) >= 6:
		options.append("coach")
	var kind: String = options[w.rng.randi_range(0, options.size() - 1)]
	c["volunteer"] = kind
	_count(w, "volunteers_joined")
	var why: String = {"fire": "a small town only has the fire crew it raises itself", "pantry": "wants to help neighbors who are short this month", "coach": "the kids need someone to show up", "seniors": "the old folks should not eat alone"}[kind]
	w.log_sim(c, "Joined %s. Reason: %s." % [VOLUNTEER_KINDS[kind], why], true)


static func _kids_in_town(w: LTWorld) -> int:
	var n: int = 0
	for c in w.citizens:
		if w.is_present(c) and w.age_years(c) >= 6 and w.age_years(c) <= 16:
			n += 1
	return n


# ---------------------------------------------------------------- helping someone

static func _help_someone(w: LTWorld, c: Dictionary) -> void:
	var t: Dictionary = c["traits"]
	var h: Dictionary = w.hh(int(c["household"]))
	var bills: int = maxi(LTMoney.dollars(800.0), LTPeople.monthly_bills(w, h))
	var spare: int = w.cash(c) - bills * 3
	if spare < LTMoney.dollars(300.0) or float(t["kindness"]) < 45.0:
		return
	var best: Dictionary = {}
	var best_need: float = 0.0
	for k in c["rel"]:
		var r: Dictionary = c["rel"][k]
		var o: Dictionary = w.cit(int(k))
		if not w.is_present(o) or w.age_years(o) < 18 or int(o["household"]) == int(c["household"]):
			continue
		if float(r["affection"]) < 55.0:
			continue
		var oh: Dictionary = w.hh(int(o["household"]))
		var short: float = float(LTPeople.monthly_bills(w, oh)) - float(w.household_cash(oh))
		var need: float = short / 100.0 + LTFinance.debt_stress(w, o) * 400.0
		if need > best_need:
			best_need = need
			best = o
	if best.is_empty() or best_need < 150.0:
		return
	var r2: Dictionary = c["rel"][int(best["id"])]
	var family: bool = ["spouse", "child", "parent", "sibling"].has(str(r2["kind"]))
	var chance: float = (float(t["kindness"]) - 40.0) / 100.0 * (float(r2["affection"]) / 100.0) * (1.5 if family else 0.7)
	if w.rng.randf() >= chance:
		return
	var amount: int = mini(int(best_need * 100.0), int(float(spare) * (0.25 if family else 0.12)))
	if amount < LTMoney.dollars(100.0):
		return
	var gift: bool = family and (float(t["kindness"]) > 65.0 or float(t["greed"]) < 35.0)
	w.ledger.pay(w.acct_p(c), w.acct_p(best), amount, "family_help" if gift else "family_loans")
	if not gift:
		LTFinance.new_debt(w, "p", int(best["id"]), "person", int(c["id"]), "family_loan", amount, 0.0, 24, "", -1, [])
	LTPeople.relate_event(w, best, c, str(r2["kind"]), 12.0, 10.0)
	_count(w, "helped_someone")
	w.remember(best, "helped", int(c["id"]), 25.0)
	var who: String = "%s %s" % [str(r2["kind"]).replace("_", " "), best["first_name"]] if family else w.full_name(best)
	w.log_sim(c, "%s %s %s to get through the month. Reason: %s." % ["Gave" if gift else "Lent", who, LTMoney.fmt(amount), "family looks after family" if family else "a friend in trouble"], true)
	w.log_sim(best, "%s %s from %s to get through the month%s." % ["Got" if gift else "Borrowed", LTMoney.fmt(amount), w.full_name(c), "" if gift else ", to pay back over two years"], true)


# ---------------------------------------------------------------- caring for a parent

static func _care_for_parent(w: LTWorld, c: Dictionary) -> void:
	for pid in [int(c["mother"]), int(c["father"])]:
		if pid < 0:
			continue
		var p: Dictionary = w.cit(pid)
		if not w.is_present(p) or w.age_years(p) < 75 or int(p["household"]) == int(c["household"]):
			continue
		var ph: Dictionary = w.hh(int(p["household"]))
		if w.household_members(ph).size() > 1 or float(p["needs"]["health"]) > 50.0:
			continue
		var t: Dictionary = c["traits"]
		var aff: float = float(c["rel"].get(pid, {}).get("affection", 50.0))
		if w.rng.randf() >= (float(t["kindness"]) + aff - 80.0) / 150.0:
			continue
		var ch: Dictionary = w.hh(int(c["household"]))
		var room: bool = int(ch["lot"]) >= 0 and str(w.lot(int(ch["lot"]))["use"]) == "house"
		if room and str(ph["tenure"]) != "own" and float(p["needs"]["health"]) < 35.0:
			ph["members"].erase(pid)
			LTPeople.vacate(w, ph)
			p["household"] = int(ch["id"])
			ch["members"].append(pid)
			c["needs"]["energy"] = float(c["needs"]["energy"]) - 10.0
			w.log_sim(c, "Moved %s in to look after them. Reason: %s is %d and cannot manage alone anymore." % [w.full_name(p), p["first_name"], w.age_years(p)], true)
			w.log_sim(p, "Moved in with %s, who looks after them now." % w.full_name(c), true)
			w.chronicle_add("%s moved their parent %s in to care for them." % [w.full_name(c), w.full_name(p)], "family", w.involves_watched([c["id"], pid]), [c["id"], pid])
		else:
			# daily visits: meals, medicine, company
			p["needs"]["health"] = float(p["needs"]["health"]) + 8.0
			p["needs"]["social"] = float(p["needs"]["social"]) + 15.0
			c["needs"]["energy"] = float(c["needs"]["energy"]) - 6.0
			if not bool(c.get("caregiver", false)):
				c["caregiver"] = true
				_count(w, "caregivers")
				w.log_sim(c, "Started checking on %s every day: meals, medicine, company. Reason: family." % w.full_name(p), true)
		return


static func _count(w: LTWorld, key: String) -> void:
	w.counters[key] = int(w.counters.get(key, 0)) + 1
