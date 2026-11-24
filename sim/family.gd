class_name LTFamily
extends RefCounted
## Marriage strain and divorce, child support, mentoring, business succession and
## sale, partnerships, home buying, and leaving town at night.


static func monthly(w: LTWorld) -> void:
	_marriages(w)
	_child_support_due(w)
	_mentoring(w)
	_succession(w)
	_home_buying(w)
	_night_flight(w)


# ---------------------------------------------------------------- marriage and divorce

static func _marriages(w: LTWorld) -> void:
	for a in w.citizens:
		if not w.is_present(a) or int(a["spouse"]) < 0 or int(a["spouse"]) < int(a["id"]):
			continue
		var b: Dictionary = w.cit(int(a["spouse"]))
		if not w.is_present(b):
			continue
		# money stress, addiction, jail and unhappiness wear a marriage down; good times build it
		var strain: float = (50.0 - LTPeople.happiness(a)) * 0.04 + (50.0 - LTPeople.happiness(b)) * 0.04
		strain += (LTFinance.debt_stress(w, a) + LTFinance.debt_stress(w, b)) * 1.5
		strain += (LTHealth.level(a) + LTHealth.level(b)) * 0.03
		if LTJustice.in_jail(w, a) or LTJustice.in_jail(w, b):
			strain += 2.0
		var bond: float = (float(a["traits"]["kindness"]) + float(b["traits"]["kindness"])) * 0.01
		for pair in [[a, b], [b, a]]:
			LTPeople.relate_event(w, pair[0], pair[1], "spouse", -strain * 0.6 + bond, -strain + bond)
		var aff: float = (float(a["rel"].get(int(b["id"]), {}).get("affection", 50.0)) + float(b["rel"].get(int(a["id"]), {}).get("affection", 50.0))) / 2.0
		# a marriage can end even without open fighting, as about 1 in 100 do each
		# year; far more often once affection has worn thin, less for long ones
		var p: float = 0.0008 + 0.0009 * exp((55.0 - aff) / 11.0)
		if w.age_years(a) >= 60:
			p *= 0.4
		if w.rng.randf() < minf(p, 0.25):
			divorce(w, a, b)


static func divorce(w: LTWorld, a: Dictionary, b: Dictionary) -> void:
	a["spouse"] = -1
	b["spouse"] = -1
	a["rel"][int(b["id"])]["kind"] = "ex-spouse"
	b["rel"][int(a["id"])]["kind"] = "ex-spouse"
	w.counters["divorces"] = int(w.counters.get("divorces", 0)) + 1
	var kids: Array = []
	for k in a["children"]:
		var kc: Dictionary = w.cit(int(k))
		if w.is_present(kc) and w.age_years(kc) < 18 and b["children"].has(int(k)):
			kids.append(kc)
	# the parent who keeps the children: more kindness and family duty, more stability
	var sa: float = float(a["traits"]["kindness"]) + float(a["needs"]["family"]) * 0.5 - LTHealth.level(a)
	var sb: float = float(b["traits"]["kindness"]) + float(b["needs"]["family"]) * 0.5 - LTHealth.level(b)
	var keeper: Dictionary = a if sa >= sb else b
	var leaver: Dictionary = b if keeper == a else a
	var h: Dictionary = w.hh(int(keeper["household"]))
	# the one who leaves needs a new place
	var nh: Dictionary = {"id": w.households.size(), "members": [], "lot": -1, "unit": -1, "tenure": "none", "rent": 0, "rent_late": 0, "mortgage": -1, "pantry": 2.0, "car": true, "moved_in": w.day, "last_grocery": "", "shop_habit": -1, "evicted_day": -1}
	w.households.append(nh)
	h["members"].erase(int(leaver["id"]))
	nh["members"].append(int(leaver["id"]))
	leaver["household"] = int(nh["id"])
	var u: Dictionary = LTPeople.free_unit(w)
	if not u.is_empty():
		LTPeople.move_household_into(w, nh, int(u["lot"]), int(u["unit"]))
		nh["tenure"] = "rent"
		nh["rent"] = int(w.lot(int(u["lot"]))["unit_rent"])
	else:
		leaver["homeless"] = true
	# a house owned by the leaver passes to the keeper in the settlement, the mortgage with it
	var l: Dictionary = w.lot(int(h["lot"])) if int(h["lot"]) >= 0 else {}
	if not l.is_empty() and str(l["owner_kind"]) == "sim" and int(l["owner_id"]) == int(leaver["id"]):
		l["owner_id"] = int(keeper["id"])
		if int(h["mortgage"]) >= 0:
			var md: Dictionary = w.debt(int(h["mortgage"]))
			if LTFinance.is_active(md):
				md["debtor_id"] = int(keeper["id"])
				md["joint"].erase(int(keeper["id"]))
				w.debt_index_dirty = true
				LTFinance._dhist(w, md, "Divorce settlement: %s keeps the house and the mortgage." % w.full_name(keeper))
	# joint debts stay joint: both still owe all of it
	var support: int = 0
	if not kids.is_empty():
		var income: int = LTFinance.monthly_income(w, leaver)
		support = maxi(LTMoney.dollars(150.0) * kids.size(), int(float(income) * minf(0.17 + 0.08 * float(kids.size() - 1), 0.4)))
		var youngest: int = 18
		for kc in kids:
			youngest = mini(youngest, w.age_years(kc))
		var months: int = maxi(1, (18 - youngest) * 12)
		var d: Dictionary = LTFinance.new_debt(w, "p", int(leaver["id"]), "person", int(keeper["id"]), "child_support", support * months, 0.0, months, "", -1, [])
		d["payment"] = support
		LTFinance._dhist(w, d, "Set by the court at %s a month until the youngest child turns 18. Bankruptcy cannot erase it." % LTMoney.fmt(support))
	var why: String = "money trouble and too many hard months" if LTFinance.debt_stress(w, a) + LTFinance.debt_stress(w, b) > 0.6 else "they grew apart"
	if LTHealth.level(a) > 55.0 or LTHealth.level(b) > 55.0:
		why = "addiction broke the trust between them"
	for p in [a, b]:
		w.remember(p, "divorce", int(keeper["id"]) if p == leaver else int(leaver["id"]), -45.0)
		p["needs"]["family"] = float(p["needs"]["family"]) - 30.0
	w.log_sim(keeper, "Divorced %s. Keeps %s. Reason: %s." % [w.full_name(leaver), "the children and the home" if not kids.is_empty() else "the home", why], true)
	w.log_sim(leaver, "Divorced %s and moved out%s. Reason: %s." % [w.full_name(keeper), ". Owes %s a month in child support" % LTMoney.fmt(support) if support > 0 else "", why], true)
	for kc in kids:
		kc["needs"]["family"] = float(kc["needs"]["family"]) - 30.0
		w.log_sim(kc, "Parents divorced. Lives with %s." % keeper["first_name"], true)
	w.chronicle_add("%s and %s divorced." % [w.full_name(a), w.full_name(b)], "family", true if w.involves_watched([a["id"], b["id"]]) else false, [a["id"], b["id"]])


## Missed child support climbs the same ladder as any debt, and a judge can jail for contempt.
static func _child_support_due(w: LTWorld) -> void:
	for d in w.debts:
		if str(d["type"]) != "child_support" or not LTFinance.is_active(d):
			continue
		if int(d["missed"]) >= 3 and int(d.get("contempt_day", -1)) < w.day - 180:
			var c: Dictionary = w.cit(int(d["debtor_id"]))
			if w.is_present(c) and w.cash(c) < LTMoney.dollars(500.0):
				d["contempt_day"] = w.day
				LTJustice.charge(w, c, "nonpayment", "fell %d months behind on child support" % d["missed"], int(d["creditor_id"]), 0)


# ---------------------------------------------------------------- mentoring

static func _mentoring(w: LTWorld) -> void:
	for s in w.citizens:
		if not w.is_present(s) or w.age_years(s) < 60 or float(s["traits"]["kindness"]) < 55.0:
			continue
		var best_sk: String = ""
		var best_v: float = 0.0
		for k in LTPeople.SKILL_KEYS:
			if float(s["skills"][k]) > best_v:
				best_v = float(s["skills"][k])
				best_sk = k
		if best_v < 60.0:
			continue
		var mentee: Dictionary = {}
		for k in s["rel"]:
			var o: Dictionary = w.cit(int(k))
			if w.is_present(o) and w.age_years(o) >= 14 and w.age_years(o) < 35 and float(o["skills"][best_sk]) < best_v - 15.0:
				mentee = o
				break
		if mentee.is_empty():
			continue
		mentee["skills"][best_sk] = minf(best_v, float(mentee["skills"][best_sk]) + 1.5)
		if int(mentee.get("mentored_by", -1)) != int(s["id"]):
			mentee["mentored_by"] = int(s["id"])
			w.log_sim(mentee, "%s started teaching them %s." % [w.full_name(s), best_sk], true)
			w.log_sim(s, "Started mentoring %s in %s. Reason: kindness, and a lifetime of skill to pass on." % [w.full_name(mentee), best_sk], true)
			LTPeople.relate_event(w, mentee, s, "mentor", 8.0, 6.0)


# ---------------------------------------------------------------- succession and sale

static func _succession(w: LTWorld) -> void:
	for b in w.businesses:
		if str(b["status"]) != "open" or str(b["type"]) == "landlord":
			continue
		var o: Dictionary = w.cit(int(b["owners"][0]))
		if not w.is_present(o) or w.age_years(o) < 64:
			continue
		var tired: float = float(w.age_years(o) - 64) * 6.0 + (100.0 - float(o["needs"]["energy"])) * 0.2 - float(o["traits"]["ambition"]) * 0.2
		if tired + w.rng.randf_range(-10.0, 10.0) < 20.0:
			continue
		# family first
		for k in o["rel"]:
			if str(o["rel"][k]["kind"]) != "child":
				continue
			var heir: Dictionary = w.cit(int(k))
			if w.is_present(heir) and w.age_years(heir) >= 21 and LTEconomy.heir_keeps_business(w, heir, b):
				LTEconomy.transfer_business(w, b, o, heir)
				w.log_sim(o, "Handed %s down to %s and retired." % [b["name"], heir["first_name"]], true)
				o["retired"] = true
				LTPeople.clear_job(w, o)
				w.chronicle_add("%s handed %s down to %s." % [w.full_name(o), b["name"], w.full_name(heir)], "business", true, [o["id"], heir["id"]])
				return
		# otherwise sell it, at a price set by its profits, to a buyer who wants it
		var profit: int = 0
		for p in b["month_profit_hist"]:
			profit += int(p)
		var price: int = maxi(LTMoney.dollars(5000.0), profit * 2)
		var buyer: Dictionary = {}
		var skill: String = str(LTEconomy.tcfg(b["type"])["skill"])
		var best: float = 30.0
		for sid in b["staff"]:
			var s: Dictionary = w.cit(int(sid))
			if w.is_present(s) and w.cash(s) >= price / 4:
				var sc: float = float(s["skills"][skill]) * 0.5 + float(s["traits"]["ambition"]) * 0.5
				if sc > best:
					best = sc
					buyer = s
		if buyer.is_empty():
			continue
		var paid_own: int = w.ledger.pay(w.acct_p(buyer), w.acct_p(o), mini(w.cash(buyer) - LTMoney.dollars(1000.0), price), "business_sale")
		if paid_own < price:
			var dec: Dictionary = LTFinance.bank_decision(w, buyer, "business_loan", price - paid_own, maxi(1, LTFinance.monthly_income(w, buyer) + profit / 12))
			if not bool(dec["ok"]):
				# the seller carries a note instead: a Sim to Sim loan
				LTFinance.new_debt(w, "p", int(buyer["id"]), "person", int(o["id"]), "seller_note", price - paid_own, 0.05, 60, "", -1, [])
			else:
				var bl: Dictionary = LTFinance.new_debt(w, "p", int(buyer["id"]), "bank", -1, "business_loan", price - paid_own, float(dec["rate"]), 84, "equipment", -1, [])
				LTFinance.fund_loan(w, bl, w.acct_p(o), price - paid_own)
		LTServices.spend(w, w.acct_p(o), "legal", LTMoney.dollars(600.0), int(b["lot"]), o)
		b["staff"].erase(int(buyer["id"]))
		LTPeople.clear_job(w, buyer)
		LTEconomy.transfer_business(w, b, o, buyer)
		o["retired"] = true
		LTPeople.clear_job(w, o)
		w.log_sim(o, "Sold %s to %s for %s and retired." % [b["name"], w.full_name(buyer), LTMoney.fmt(price)], true)
		w.log_sim(buyer, "Bought %s from %s for %s. Reason: knew the work and wanted to own it." % [b["name"], w.full_name(o), LTMoney.fmt(price)], true)
		w.chronicle_add("%s sold %s to %s." % [w.full_name(o), b["name"], w.full_name(buyer)], "business", true, [o["id"], buyer["id"]])
		return


## A founder short on money may bring in a partner who puts in cash for a share.
static func find_partner(w: LTWorld, c: Dictionary, gap: int) -> Dictionary:
	for k in c["rel"]:
		var r: Dictionary = c["rel"][k]
		var o: Dictionary = w.cit(int(k))
		if not w.is_present(o) or int(o["household"]) == int(c["household"]) or not o["owns"].is_empty():
			continue
		if float(r["trust"]) < 55.0:
			continue
		if w.cash(o) - LTMoney.dollars(5000.0) >= gap and float(o["traits"]["risk"]) + float(o["traits"]["ambition"]) > 90.0:
			return o
	return {}


# ---------------------------------------------------------------- buying a home

static func _home_buying(w: LTWorld) -> void:
	var for_sale: Array = []
	for l in w.lots:
		if str(l["use"]) == "house" and int(l["units"][0]) == -1 and (str(l["owner_kind"]) == "outside" or l.has("for_sale")):
			for_sale.append(l)
	# the cheapest listing first
	for_sale.sort_custom(func(a, b): return int(a.get("for_sale", a["value"])) < int(b.get("for_sale", b["value"])))
	if for_sale.is_empty():
		return
	for h in w.households:
		if for_sale.is_empty():
			return
		if str(h["tenure"]) != "rent":
			continue
		var adults: Array = w.household_adults(h)
		if adults.is_empty():
			continue
		var head: Dictionary = adults[0]
		var income: int = 0
		for a in adults:
			income += LTFinance.monthly_income(w, a)
		var l: Dictionary = for_sale[0]
		var price: int = int(l.get("for_sale", l["value"]))
		var seller: String = LTCivic.owner_acct(w, l)
		var cash: int = w.household_cash(h)
		if cash < int(float(price) * 0.03) + LTMoney.dollars(1000.0):
			continue
		var want: float = float(w.household_members(h).size()) * 8.0 + float(head["traits"]["ambition"]) * 0.3 + float(head["traits"]["discipline"]) * 0.2 - 30.0
		if want + w.rng.randf_range(-10.0, 10.0) < 20.0:
			continue
		var offer: Dictionary = LTFinance.mortgage_offer(w, h, head, price)
		if not bool(offer["ok"]):
			w.log_sim(head, "Tried to buy the house on %s and the bank said no: %s. The banker's advice: %s." % [LTGeography.lot_label(w, int(l["id"])), offer["reason"], offer["advice"]], true)
			head["bank_advice"] = {"day": w.day, "text": str(offer["advice"]), "for": "home"}
			continue
		var down: int = int(offer["down"])
		var dec: Dictionary = {"rate": float(offer["rate"])}
		w.household_pay(h, "outside", int(offer["closing"]), "closing_costs")
		var paid: int = w.household_pay(h, seller, down, "house_purchases")
		var d: Dictionary = LTFinance.new_debt(w, "p", int(head["id"]), "bank", -1, "mortgage", int(offer["loan"]), float(dec["rate"]), 360, "house", int(l["id"]), [])
		d["program"] = str(offer["program"])
		LTFinance._dhist(w, d, "%s." % offer["reason"])
		LTFinance.fund_loan(w, d, seller, price - down)
		if int(offer["loan"]) > price - down:
			# the FHA upfront premium is part of the loan
			w.ledger.pay(LTFinance.creditor_acct(w, d), "outside", int(offer["loan"]) - (price - down), "fha_premiums")
		LTCivic.transfer_tax(w, seller, paid + price - down, int(l["id"]))
		w.bank["lent_12m"] = int(w.bank["lent_12m"]) + price - down
		LTServices.spend(w, "outside", "real_estate", int(float(price) * 0.05), int(l["id"]))
		LTServices.spend(w, w.acct_p(head), "legal", LTMoney.dollars(800.0), int(l["id"]), head)
		var old_lot: int = int(h["lot"])
		LTPeople.vacate(w, h)
		LTPeople.move_household_into(w, h, int(l["id"]), 0)
		h["tenure"] = "own"
		h["rent"] = 0
		h["mortgage"] = int(d["id"])
		l["owner_kind"] = "sim"
		l["owner_id"] = int(head["id"])
		for_sale.erase(l)
		w.log_sim(head, "Bought the house on %s for %s with %s down and a %s mortgage. Reason: the family wanted a place of its own." % [LTGeography.lot_label(w, int(l["id"])), LTMoney.fmt(price), LTMoney.fmt(paid), offer["program"]], true)
		w.chronicle_add("The %s household bought a house on %s." % [head["last_name"], LTGeography.lot_street(w, int(l["id"]))["name"]], "housing", w.involves_watched(h["members"]), h["members"].duplicate())


# ---------------------------------------------------------------- leaving at night

static func _night_flight(w: LTWorld) -> void:
	for h in w.households:
		var adults: Array = w.household_adults(h)
		if adults.is_empty():
			continue
		var head: Dictionary = adults[0]
		var stress: float = 0.0
		for a in adults:
			stress = maxf(stress, LTFinance.debt_stress(w, a))
		if stress < 0.85:
			continue
		var collections: int = 0
		for d in LTFinance.personal_exposure(w, head):
			if ["collections", "judgment"].has(str(d["status"])):
				collections += 1
		if collections == 0:
			continue
		var t: Dictionary = head["traits"]
		var score: float = stress * 40.0 + float(collections) * 10.0 + float(t["risk"]) * 0.2 - float(t["honesty"]) * 0.3 - (20.0 if str(h["tenure"]) == "own" else 0.0)
		if score + w.rng.randf_range(-10.0, 10.0) > 35.0:
			for a in w.household_members(h):
				w.log_sim(a, "Left town in the middle of the night. Reason: buried in debt with collectors calling, and no way out here.", true)
			LTPeople._household_leaves(w, h, score)
