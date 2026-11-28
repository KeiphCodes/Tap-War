class_name LTGov
extends RefCounted
## Town government the way a small South Dakota town really runs: an elected mayor
## who can serve two four-year terms in a row, an elected town board once the
## town is big enough to fill one, and officials the mayor appoints with the
## board's consent: a finance officer who keeps the books, a police chief, and a
## street superintendent.
##
## The board votes on laws, bonds and city loans, each member from their own
## values and what the change does to them. A mayor near the end of the second
## term can ask voters to drop term limits, step down, or grab power and rule by
## decree, and a mayor who does that faces the town's anger and the state courts.

const BOARD_AT: int = 50            # residents before a town board is elected
const TERM_LIMIT: int = 2
const ROLES: Dictionary = {
	"finance_officer": {"label": "Finance officer", "skill": "finance", "trait": "discipline", "does": "keeps the city's books, pays the bills and sells its bonds"},
	"police_chief": {"label": "Police chief", "skill": "management", "trait": "discipline", "does": "runs the police and decides where they patrol"},
	"street_super": {"label": "Street superintendent", "skill": "construction", "trait": "discipline", "does": "keeps the streets patched, plowed and graded"},
}
## Which way each trait pulls a board member when a law goes UP.
const LEANS: Dictionary = {
	"property_tax": {"kindness": 0.3, "greed": -0.5, "discipline": 0.2}, "sales_tax": {"greed": -0.3, "discipline": 0.2},
	"income_tax": {"greed": -0.6, "kindness": 0.3}, "business_tax": {"greed": -0.4, "ambition": -0.2, "kindness": 0.2},
	"min_wage": {"kindness": 0.5, "greed": -0.4}, "school_funding": {"kindness": 0.4, "intelligence": 0.3, "greed": -0.3},
	"police_funding": {"discipline": 0.5}, "health_funding": {"kindness": 0.5, "greed": -0.2},
	"welfare": {"kindness": 0.6, "greed": -0.4, "discipline": -0.2}, "fire_funding": {"discipline": 0.4},
	"license_fee": {"greed": -0.3}, "building_code": {"discipline": 0.4, "intelligence": 0.2, "greed": -0.3},
	"health_code": {"discipline": 0.4, "intelligence": 0.2}, "pollution_rule": {"kindness": 0.4, "intelligence": 0.2, "greed": -0.4},
	"zoning_density": {"ambition": 0.3, "greed": 0.2, "discipline": -0.2}, "rent_cap": {"kindness": 0.5, "greed": -0.6},
	"late_fee_cap": {"greed": 0.3, "kindness": -0.3}, "bus_service": {"kindness": 0.4, "ambition": 0.2},
	"bank_charter": {"ambition": 0.4}, "transfer_tax": {"greed": -0.4}, "lot_coverage": {"ambition": 0.2, "discipline": -0.2},
	"mining": {"greed": 0.5, "kindness": -0.3, "ambition": 0.3},
}


static func g(w: LTWorld) -> Dictionary:
	if not w.city.has("gov"):
		w.city["gov"] = {"form": "elected", "term_limit": TERM_LIMIT, "mayor_terms": 0, "board": [], "board_next": -1,
			"officials": {}, "votes": [], "decree_day": -1, "referendum": {}, "history": []}
	return w.city["gov"]


static func board_seated(w: LTWorld) -> bool:
	return bool(w.city.get("elections", false)) and not g(w)["board"].is_empty()


static func board_size(w: LTWorld) -> int:
	var n: int = w.residents()
	return 7 if n >= 2000 else (5 if n >= 500 else 3)


static func by_decree(w: LTWorld) -> bool:
	return int(g(w).get("decree_day", -1)) >= 0


static func _note(w: LTWorld, text: String) -> void:
	var gv: Dictionary = g(w)
	gv["history"].append({"day": w.day, "text": text})
	if gv["history"].size() > 60:
		gv["history"].pop_front()


static func mayor_citizen(w: LTWorld) -> int:
	return int(w.player.get("citizen_id", -1))


# ---------------------------------------------------------------- daily

static func daily(w: LTWorld) -> void:
	if not bool(w.city.get("incorporated", true)):
		return
	var gv: Dictionary = g(w)
	if bool(w.city.get("elections", false)) and not by_decree(w):
		# the first town board, once there are enough people to fill one
		if gv["board"].is_empty() and int(gv["board_next"]) < 0 and w.residents() >= BOARD_AT:
			gv["board_next"] = w.day + 60
			w.chronicle_add("%s has %d residents, enough for a town board. Candidates have 60 days to file; the election is %s." % [w.city["name"], w.residents(), LTCalendar.short(w.day + 60)], "election", true, [])
		if int(gv["board_next"]) >= 0 and w.day == int(gv["board_next"]):
			_board_election(w)
		_referendum_day(w)
	if LTCalendar.is_month_start(w.day):
		_monthly(w)


static func _monthly(w: LTWorld) -> void:
	var gv: Dictionary = g(w)
	# people who died or moved leave their seats; the board fills them
	var keep: Array = []
	for s in gv["board"]:
		var c: Dictionary = w.cit(int(s["cid"]))
		if not c.is_empty() and w.is_present(c):
			keep.append(s)
		else:
			_note(w, "%s left the town board." % w.full_name(c))
			var rep: Array = _candidates(w, 1, _board_ids(w))
			if not rep.is_empty():
				keep.append({"cid": int(rep[0]["id"]), "ends": int(s["ends"]), "since": w.day, "appointed": true})
				w.chronicle_add("The town board appointed %s to fill the empty seat until %s." % [w.full_name(rep[0]), LTCalendar.short(int(s["ends"]))], "election", false, [rep[0]["id"]])
	gv["board"] = keep
	for role in gv["officials"].keys():
		var oc: Dictionary = w.cit(int(gv["officials"][role]))
		if oc.is_empty() or not w.is_present(oc):
			gv["officials"].erase(role)
			_note(w, "The %s post is empty." % str(ROLES[role]["label"]).to_lower())
	_pay(w)
	_finance_officer_honesty(w)
	# the Sim mayor fills empty posts; so does the board when a player leaves them
	if w.residents() >= BOARD_AT and (LTMayorAI.is_on(w) or by_decree(w)):
		for role in ROLES:
			if not gv["officials"].has(role):
				var best: Array = nominees(w, role)
				if not best.is_empty():
					appoint(w, role, int(best[0]["id"]))
	if by_decree(w):
		_decree_month(w)


## Part time pay, as in a real small town: council members a little each month,
## appointed officials a part time salary that grows with the town.
static func _pay(w: LTWorld) -> void:
	var gv: Dictionary = g(w)
	var n: int = w.residents()
	var off_pay: int = LTMoney.dollars(3500.0 if n >= 2000 else (1500.0 if n >= 500 else 400.0))
	for role in gv["officials"]:
		var c: Dictionary = w.cit(int(gv["officials"][role]))
		if not c.is_empty():
			LTCivic._spend(w, w.acct_p(c), off_pay, "officials_pay")
	for s in gv["board"]:
		var c2: Dictionary = w.cit(int(s["cid"]))
		if not c2.is_empty():
			LTCivic._spend(w, w.acct_p(c2), LTMoney.dollars(75.0), "officials_pay")


# ---------------------------------------------------------------- the board

static func _board_ids(w: LTWorld) -> Array:
	var ids: Array = []
	for s in g(w)["board"]:
		ids.append(int(s["cid"]))
	return ids


## People willing to serve: civic minded adults who are known around town.
static func _candidates(w: LTWorld, n: int, skip: Array) -> Array:
	var pool: Array = []
	var mc: int = mayor_citizen(w)
	for c in w.citizens:
		if not w.is_present(c) or w.age_years(c) < 21 or skip.has(int(c["id"])) or int(c["id"]) == mc:
			continue
		var t: Dictionary = c["traits"]
		var sc: float = float(t["sociability"]) * 0.4 + float(t["ambition"]) * 0.3 + float(t["kindness"]) * 0.2 + float(c["rel"].size()) * 1.5 + w.rng.randf_range(0.0, 25.0)
		pool.append([sc, c])
	pool.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var out: Array = []
	for i in mini(n, pool.size()):
		out.append(pool[i][1])
	return out


static func _board_election(w: LTWorld) -> void:
	var gv: Dictionary = g(w)
	var size: int = board_size(w)
	var keep: Array = []
	for s in gv["board"]:
		if int(s["ends"]) > w.day + 1:
			keep.append(s)
	var open: int = size - keep.size()
	gv["board_next"] = w.day + 365 * 2
	if open <= 0:
		gv["board"] = keep
		return
	var skip: Array = []
	for s in keep:
		skip.append(int(s["cid"]))
	var cands: Array = _candidates(w, open + 2, skip)
	if cands.is_empty():
		return
	# each voter backs the candidates they know and like best
	var votes: Dictionary = {}
	for c in cands:
		votes[int(c["id"])] = 0
	for v in w.citizens:
		if not w.is_present(v) or w.age_years(v) < 18 or w.rng.randf() < 0.4:
			continue
		var scored: Array = []
		for c in cands:
			var s: float = w.rng.randf_range(0.0, 30.0) + float(c["traits"]["sociability"]) * 0.2
			if v["rel"].has(int(c["id"])):
				s += float(v["rel"][int(c["id"])]["affection"]) * 0.5
			if int(v["id"]) == int(c["id"]):
				s += 100.0
			scored.append([s, int(c["id"])])
		scored.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
		for i in mini(open, scored.size()):
			votes[scored[i][1]] = int(votes[scored[i][1]]) + 1
	var order: Array = votes.keys()
	order.sort_custom(func(a, b): return int(votes[a]) > int(votes[b]))
	var first: bool = gv["board"].is_empty()
	var names: Array = []
	for i in mini(open, order.size()):
		var cid: int = int(order[i])
		# the first board staggers its terms so half the seats come up every two years
		var years: int = 2 if first and i >= int(ceil(size / 2.0)) else 4
		keep.append({"cid": cid, "ends": w.day + 365 * years, "since": w.day})
		names.append("%s (%d votes)" % [w.full_name(w.cit(cid)), int(votes[cid])])
		w.log_sim(w.cit(cid), "Elected to the town board. Reason: neighbors who know %s voted for %s." % [w.cit(cid)["first_name"], "them"], true)
	gv["board"] = keep
	var txt: String = "%s elected %s to the town board: %s." % [w.city["name"], "its first members" if first else "%d members" % names.size(), LTHomes._join(names)]
	_note(w, txt)
	w.chronicle_add(txt, "election", true, order.slice(0, open))


## A board vote on the mayor's proposal. Returns [passed, yes, no, text].
static func vote(w: LTWorld, what: String, law: String, up: bool, hurts_owners: bool = false) -> Array:
	var gv: Dictionary = g(w)
	var yes: Array = []
	var no: Array = []
	var appr: float = LTCivic.approval(w)
	var lean: Dictionary = LEANS.get(law, {})
	var mc: int = mayor_citizen(w)
	for s in gv["board"]:
		var m: Dictionary = w.cit(int(s["cid"]))
		if m.is_empty():
			continue
		var sc: float = 55.0 + (appr - 50.0) * 0.4 + w.rng.randf_range(-15.0, 15.0)
		for k in lean:
			sc += float(lean[k]) * (float(m["traits"].get(k, 50)) - 50.0) * (1.0 if up else -1.0)
		if mc >= 0 and m["rel"].has(mc):
			sc += float(m["rel"][mc]["affection"]) * 0.2
		if hurts_owners and up and m["job"].get("kind", "") == "owner":
			sc -= 15.0
		(yes if sc >= 50.0 else no).append(str(m["first_name"]) + " " + str(m["last_name"]))
	var passed: bool = yes.size() > no.size()
	var txt: String = "The town board %s %s, %d to %d.%s%s" % ["passed" if passed else "voted down", what, yes.size(), no.size(),
		" Yes: %s." % ", ".join(yes) if not yes.is_empty() else "", " No: %s." % ", ".join(no) if not no.is_empty() else ""]
	gv["votes"].append({"day": w.day, "what": what, "yes": yes.size(), "no": no.size(), "passed": passed})
	if gv["votes"].size() > 40:
		gv["votes"].pop_front()
	w.chronicle_add(txt, "law", not passed, [])
	return [passed, yes.size(), no.size(), txt]


## The board's say on a mayor's action, before it happens. {} means go ahead.
static func check_action(w: LTWorld, act: Dictionary) -> Dictionary:
	if not board_seated(w) or by_decree(w):
		return {}
	match str(act.get("kind", "")):
		"set_law":
			var key: String = str(act["law"])
			if not LTCivic.LAWS.has(key):
				return {}
			var old: float = float(w.city["laws"][key])
			if is_equal_approx(float(act["value"]), old):
				return {}
			var what: String = "changing %s from %s to %s" % [str(LTCivic.LAWS[key]["label"]).to_lower(), LTCivic.law_text(key, old), LTCivic.law_text(key, float(act["value"]))]
			var r: Array = vote(w, what, key, float(act["value"]) > old, key == "business_tax" or key == "min_wage")
			if not bool(r[0]):
				return {"ok": false, "message": str(r[3])}
		"define_project":
			if str(act.get("ptype", "")) == "depot":
				var cost: int = maxi(0, LTRail.DEPOT_COST - int(LTRail.r(w)["grant_amt"]))
				var r3: Array = vote(w, "spending about %s of city money on a public rail loading track" % LTMoney.fmt(cost), "property_tax", true)
				if not bool(r3[0]):
					return {"ok": false, "message": str(r3[3])}
		"issue_bond", "city_borrow":
			var r2: Array = vote(w, "%s %s" % ["selling bonds for" if str(act["kind"]) == "issue_bond" else "borrowing", LTMoney.fmt(int(act["amount"]))], "property_tax", true)
			if not bool(r2[0]):
				return {"ok": false, "message": str(r2[3])}
	return {}


# ---------------------------------------------------------------- officials

static func nominees(w: LTWorld, role: String) -> Array:
	var cfg: Dictionary = ROLES[role]
	var held: Array = g(w)["officials"].values()
	var pool: Array = []
	for c in w.citizens:
		if not w.is_present(c) or w.age_years(c) < 21 or held.has(int(c["id"])) or int(c["id"]) == mayor_citizen(w):
			continue
		pool.append([quality(c, role), c])
	pool.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var out: Array = []
	for i in mini(3, pool.size()):
		out.append(pool[i][1])
	return out


static func quality(c: Dictionary, role: String) -> float:
	var cfg: Dictionary = ROLES[role]
	return clampf((float(c["skills"].get(str(cfg["skill"]), 0.0)) * 0.6 + float(c["traits"].get(str(cfg["trait"]), 50)) * 0.25 + float(c["traits"]["honesty"]) * 0.15) / 100.0, 0.0, 1.0)


## The mayor names someone; the board confirms (or, with no board, it simply happens).
static func appoint(w: LTWorld, role: String, cid: int) -> Dictionary:
	if not ROLES.has(role):
		return {"ok": false, "message": "Unknown post."}
	var c: Dictionary = w.cit(cid)
	if c.is_empty() or not w.is_present(c) or w.age_years(c) < 21:
		return {"ok": false, "message": "That person cannot serve."}
	if not bool(w.city.get("incorporated", true)):
		return {"ok": false, "message": "The town has to incorporate before it has officials."}
	var label: String = str(ROLES[role]["label"]).to_lower()
	if board_seated(w) and not by_decree(w):
		var r: Array = vote(w, "confirming %s as %s" % [w.full_name(c), label], "", true)
		if not bool(r[0]):
			return {"ok": false, "message": str(r[3])}
	g(w)["officials"][role] = cid
	var q: float = quality(c, role)
	w.log_sim(c, "Appointed %s of %s. Reason: %s %s." % [label, w.city["name"], "the mayor picked the best qualified person in town" if q > 0.45 else "the mayor picked a friend more than a qualified hand", "and the board agreed" if board_seated(w) else ""], true)
	var txt: String = "Mayor %s appointed %s as %s. The %s %s." % [w.player["name"], w.full_name(c), label, label, ROLES[role]["does"]]
	_note(w, txt)
	w.chronicle_add(txt, "city", false, [cid])
	return {"ok": true, "message": txt}


## How much better or worse a post is run than by nobody in particular: 0.92 to 1.08.
static func factor(w: LTWorld, role: String) -> float:
	if not w.city.has("gov"):
		return 1.0
	var cid: int = int(g(w)["officials"].get(role, -1))
	if cid < 0:
		return 1.0
	var c: Dictionary = w.cit(cid)
	if c.is_empty():
		return 1.0
	return 0.92 + quality(c, role) * 0.16


## A dishonest finance officer can quietly skim; an honest audit can catch it.
static func _finance_officer_honesty(w: LTWorld) -> void:
	var gv: Dictionary = g(w)
	var c: Dictionary = w.cit(int(gv["officials"].get("finance_officer", -1)))
	if c.is_empty():
		return
	var t: Dictionary = c["traits"]
	var temptation: float = (float(t["greed"]) - float(t["honesty"])) / 100.0
	if temptation > 0.2 and w.rng.randf() < temptation * 0.05:
		var took: int = mini(int(float(w.ledger.bal("city")) * 0.02), LTMoney.dollars(5000.0))
		if took > LTMoney.dollars(100.0):
			w.ledger.pay("city", w.acct_p(c), took, "embezzled")
			gv["skimmed"] = int(gv.get("skimmed", 0)) + took
			w.log_sim(c, "Moved %s of city money into a personal account and covered it in the books. Reason: greed beat honesty." % LTMoney.fmt(took), true)
	if int(gv.get("skimmed", 0)) > 0 and w.rng.randf() < 0.12:
		var amt: int = int(gv["skimmed"])
		gv["skimmed"] = 0
		gv["officials"].erase("finance_officer")
		w.chronicle_add("The state auditor found %s missing from the city's books. Finance officer %s is charged and out of the job." % [LTMoney.fmt(amt), w.full_name(c)], "crime", true, [c["id"]])
		LTJustice.charge(w, c, "fraud", "took %s of city money as finance officer" % LTMoney.fmt(amt), -1, amt)


# ---------------------------------------------------------------- terms and the charter

## Whether the mayor may run again under the charter.
static func can_run(w: LTWorld) -> bool:
	var gv: Dictionary = g(w)
	if bool(gv.get("barred", false)):
		return false
	return int(gv["term_limit"]) <= 0 or int(gv["mayor_terms"]) < int(gv["term_limit"])


## Called 60 days before a mayoral election: a term limited mayor decides.
static func before_election(w: LTWorld) -> void:
	if can_run(w):
		return
	var gv: Dictionary = g(w)
	if LTMayorAI.is_on(w):
		var t: Dictionary = w.player.get("traits", {})
		var grab: float = float(t.get("ambition", 50)) * 0.4 + float(t.get("greed", 50)) * 0.4 - float(t.get("honesty", 50)) * 0.5 - float(t.get("kindness", 50)) * 0.2 + w.rng.randf_range(-10.0, 10.0)
		if grab > 22.0 and not bool(gv.get("court_ordered", false)):
			declare_decree(w, "would not give up power after two terms")
			return
	w.chronicle_add("Mayor %s has served %d terms, the most the town charter allows, and will step down. The race for mayor is open." % [w.player["name"], int(gv["mayor_terms"])], "election", true, [])


## A charter amendment goes to the voters: a special election in 60 days.
static func propose_charter(w: LTWorld, change: String) -> Dictionary:
	var gv: Dictionary = g(w)
	if not bool(w.city.get("elections", false)) or by_decree(w):
		return {"ok": false, "message": "Charter amendments go to the voters, and this town is not voting."}
	if not gv["referendum"].is_empty():
		return {"ok": false, "message": "A charter question is already on the ballot."}
	var q: String
	match change:
		"no_term_limits":
			if int(gv["term_limit"]) <= 0:
				return {"ok": false, "message": "There are no term limits."}
			q = "Should the town charter drop the two term limit for mayor?"
		"term_limits":
			if int(gv["term_limit"]) > 0:
				return {"ok": false, "message": "The charter already limits the mayor to two terms."}
			q = "Should the town charter limit the mayor to two terms in a row?"
		_:
			return {"ok": false, "message": "Unknown charter change."}
	gv["referendum"] = {"change": change, "question": q, "day": w.day + 60}
	w.chronicle_add("On the ballot %s: \"%s\"" % [LTCalendar.short(w.day + 60), q], "election", true, [])
	return {"ok": true, "message": "The question goes to the voters %s." % LTCalendar.short(w.day + 60)}


static func _referendum_day(w: LTWorld) -> void:
	var gv: Dictionary = g(w)
	var rf: Dictionary = gv["referendum"]
	if rf.is_empty() or w.day < int(rf["day"]):
		return
	var yes: int = 0
	var no: int = 0
	var appr: float = LTCivic.approval(w)
	for c in w.citizens:
		if not w.is_present(c) or w.age_years(c) < 18 or w.rng.randf() < 0.45:
			continue
		var v: float = w.rng.randf_range(-20.0, 20.0)
		if str(rf["change"]) == "no_term_limits":
			# people only hand a mayor more time when they like the mayor, and a
			# lot of them distrust it on principle
			v += (appr - 50.0) * 0.8 - 12.0 + (float(c["traits"]["discipline"]) - 50.0) * -0.2
		else:
			v += 15.0 - (appr - 50.0) * 0.4
		if v > 0.0:
			yes += 1
		else:
			no += 1
	var passed: bool = yes > no
	if passed:
		gv["term_limit"] = 0 if str(rf["change"]) == "no_term_limits" else TERM_LIMIT
	var txt: String = "Voters %s the charter question \"%s\" %d to %d." % ["approved" if passed else "rejected", rf["question"], yes, no]
	_note(w, txt)
	w.chronicle_add(txt, "election", true, [])
	gv["referendum"] = {}


## Months before a term limited election, a Sim mayor who wants to stay asks the voters.
static func sim_mayor_plans(w: LTWorld) -> void:
	if not LTMayorAI.is_on(w) or not bool(w.city.get("elections", false)) or by_decree(w):
		return
	var gv: Dictionary = g(w)
	var t: Dictionary = w.player.get("traits", {})
	var days_left: int = int(w.city["next_election_day"]) - w.day
	if int(gv["term_limit"]) > 0 and int(gv["mayor_terms"]) >= int(gv["term_limit"]) and days_left == 240 and gv["referendum"].is_empty():
		if float(t.get("ambition", 50)) > 65.0 and LTCivic.approval(w) > 52.0:
			propose_charter(w, "no_term_limits")
			LTMayorAI._say(w, "asked the voters to drop term limits. Reason: ambitious, popular, and not done yet.")


## The mayor takes power: no more elections, the board sent home.
static func declare_decree(w: LTWorld, why: String) -> Dictionary:
	var gv: Dictionary = g(w)
	if by_decree(w):
		return {"ok": false, "message": "The mayor already rules by decree."}
	gv["decree_day"] = w.day
	gv["board"] = []
	gv["board_next"] = -1
	gv["referendum"] = {}
	w.city["elections"] = false
	for c in w.citizens:
		if w.is_present(c):
			c["trust_city"] = clampf(float(c["trust_city"]) - 25.0, 0.0, 100.0)
	w.city["protests"] = int(w.city.get("protests", 0)) + 1
	var txt: String = "Mayor %s canceled the election, sent the town board home and now rules by decree. Reason: %s. People are furious, and the state attorney general is looking at it." % [w.player["name"], why]
	_note(w, txt)
	w.chronicle_add(txt, "election", true, [])
	return {"ok": true, "message": txt}


## Under decree: trust stays low, and every month the state courts may step in.
static func _decree_month(w: LTWorld) -> void:
	var gv: Dictionary = g(w)
	var months: int = int((w.day - int(gv["decree_day"])) / 30)
	if months >= 2 and w.rng.randf() < 0.12:
		gv["decree_day"] = -1
		gv["court_ordered"] = true
		gv["barred"] = true
		w.city["elections"] = true
		w.city["next_election_day"] = w.day + 90
		gv["board_next"] = w.day + 60
		var txt: String = "A state judge ruled the town's elections must go on: a board election in 60 days and a mayor's race in 90. Mayor %s may not run." % w.player["name"]
		_note(w, txt)
		w.chronicle_add(txt, "election", true, [])


static func trust_penalty(w: LTWorld) -> float:
	return 25.0 if w.city.has("gov") and by_decree(w) else 0.0


# ---------------------------------------------------------------- a new mayor

## The winner of an open race or a defeat takes office and runs the town as a Sim.
static func new_mayor(w: LTWorld, c: Dictionary, why: String) -> void:
	var gv: Dictionary = g(w)
	var was_player: bool = not LTMayorAI.is_on(w)
	var old: String = str(w.player["name"])
	if was_player:
		w.city["player_out"] = true
		w.mode["autonomous"] = true
		w.player["player_took_over"] = false
		w.player["former_player"] = old
	w.player["name"] = w.full_name(c)
	w.player["pronouns"] = "she" if str(c.get("sex", "F")) == "F" else "he"
	w.player["age"] = w.age_years(c) - w.day / 365
	w.player["hometown"] = str(w.city["name"])
	w.player["traits"] = c["traits"].duplicate()
	w.player["citizen_id"] = int(c["id"])
	w.player["sim_mayor"] = true
	w.player["title"] = "mayor"
	w.player["since"] = w.day
	gv["mayor_terms"] = 1
	gv["court_ordered"] = false
	gv["barred"] = false
	gv["board"] = gv["board"].filter(func(s): return int(s["cid"]) != int(c["id"]))
	for role in gv["officials"].keys():
		if int(gv["officials"][role]) == int(c["id"]):
			gv["officials"].erase(role)
	var txt: String = "%s took office as mayor of %s, after %s. Reason: %s." % [w.full_name(c), w.city["name"], old, why]
	_note(w, txt)
	w.log_sim(c, "Sworn in as mayor. Reason: %s." % why, true)
	w.chronicle_add(txt, "election", true, [c["id"]])
