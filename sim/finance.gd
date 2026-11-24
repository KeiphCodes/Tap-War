class_name LTFinance
extends RefCounted
## Debt records, the collection ladder, credit scores, bank lending, bankruptcy,
## estates, and city borrowing. Every payment is a ledger transfer.

const ACTIVE_STATES: Array = ["current", "late30", "late60", "late90", "collections", "judgment", "in_bankruptcy", "assumed"]
const LATE_FEE: int = 3500
const FUNERAL_COST: int = 750000
const ESTATE_ADMIN: int = 60000
const CASH_EXEMPTION: int = 700000
const BANK_NAME: String = "Prairie State Bank"


static func setup_bank(w: LTWorld) -> void:
	w.bank = {
		"name": BANK_NAME, "kind": "outside", "lent_12m": 0, "losses_12m": 0,
		"losses_total": 0, "tightness": 0.25, "monthly": [], "bankruptcies_12m": 0,
		"note": "An outside bank serves the town until it is big enough for a city chartered bank.",
	}


static func is_active(d: Dictionary) -> bool:
	return not d.is_empty() and ACTIVE_STATES.has(str(d["status"]))


static func amortized_payment(principal: int, rate: float, months: int) -> int:
	if months <= 0:
		return 0
	var r: float = rate / 12.0
	if r <= 0.0:
		return principal / months
	return int(ceil(float(principal) * r / (1.0 - pow(1.0 + r, -months))))


static func new_debt(w: LTWorld, debtor_kind: String, debtor_id: int, creditor: String, creditor_id: int, dtype: String, principal: int, rate: float, term: int, secured_by: String, collateral_lot: int, joint: Array) -> Dictionary:
	var d: Dictionary = {
		"id": w.debts.size(), "debtor_kind": debtor_kind, "debtor_id": debtor_id,
		"creditor": creditor, "creditor_id": creditor_id, "type": dtype,
		"original": principal, "balance": principal, "rate": rate, "term": term,
		"payment": amortized_payment(principal, rate, term), "due_dom": 1 + (w.debts.size() * 7) % 28,
		"secured_by": secured_by, "collateral_lot": collateral_lot, "joint": joint.duplicate(),
		"guarantor": -1, "status": "current", "missed": 0, "opened_day": w.day,
		"history": [], "dischargeable": not ["tax", "child_support", "fraud"].has(dtype), "limit": 0,
		"paid_total": 0, "loss": 0,
	}
	w.debts.append(d)
	w.debt_index_dirty = true
	_dhist(w, d, "Opened: %s of %s, %s owed to %s at %.1f%%." % [LTMoney.fmt(principal), dtype.replace("_", " "), "secured by the " + secured_by if secured_by != "" else "unsecured", creditor_name(w, d), rate * 100.0])
	return d


static func _dhist(w: LTWorld, d: Dictionary, text: String) -> void:
	d["history"].append({"day": w.day, "text": text})


static func creditor_name(w: LTWorld, d: Dictionary) -> String:
	match str(d["creditor"]):
		"bank":
			return BANK_NAME
		"city":
			return "the city"
		"supplier":
			return "Valley Wholesale"
		"clinic":
			return "County Medical Center"
		"college":
			return "the county college's student lender"
		"business":
			return str(w.biz(int(d["creditor_id"])).get("name", "a local business"))
		"person":
			return w.full_name(w.cit(int(d["creditor_id"])))
	return str(d["creditor"])


static func creditor_acct(w: LTWorld, d: Dictionary) -> String:
	match str(d["creditor"]):
		"bank":
			return "bank"
		"city":
			return "city"
		"business":
			return "b:%d" % int(d["creditor_id"])
		"person":
			return "p:%d" % int(d["creditor_id"])
	return "outside"


static func debtor_name(w: LTWorld, d: Dictionary) -> String:
	match str(d["debtor_kind"]):
		"p":
			return w.full_name(w.cit(int(d["debtor_id"])))
		"b":
			return str(w.biz(int(d["debtor_id"])).get("name", "a business"))
	return "the city"


static func debts_of(w: LTWorld, kind: String, id: int, active_only: bool = true) -> Array:
	var out: Array = []
	for d in w.debts:
		if str(d["debtor_kind"]) == kind and int(d["debtor_id"]) == id and (not active_only or is_active(d)):
			out.append(d)
	return out


## Debts a person answers for: their own, joint ones, sole proprietor business debts, and guarantees.
## Built as an index once per change so each lookup is cheap at any town size.
static func personal_exposure(w: LTWorld, c: Dictionary) -> Array:
	if w.debt_index_dirty:
		_rebuild_index(w)
	var out: Array = []
	for d in w.debt_index.get(int(c["id"]), []):
		if is_active(d):
			out.append(d)
	return out


static func _rebuild_index(w: LTWorld) -> void:
	var idx: Dictionary = {}
	for d in w.debts:
		if not is_active(d):
			continue
		var who: Array = []
		match str(d["debtor_kind"]):
			"p":
				who.append(int(d["debtor_id"]))
				for j in d["joint"]:
					who.append(int(j))
			"b":
				var b: Dictionary = w.biz(int(d["debtor_id"]))
				if b.is_empty():
					continue
				if str(b["legal_form"]) == "sole":
					for o in b["owners"]:
						who.append(int(o))
				if int(d["guarantor"]) >= 0 and not who.has(int(d["guarantor"])):
					who.append(int(d["guarantor"]))
		for pid in who:
			if not idx.has(pid):
				idx[pid] = []
			idx[pid].append(d)
	w.debt_index = idx
	w.debt_index_dirty = false


static func total_owed(w: LTWorld, c: Dictionary) -> int:
	var t: int = 0
	for d in personal_exposure(w, c):
		t += int(d["balance"])
	return t


## How heavy debt sits on a Sim: the household's monthly payments against the
## household's income, plus every debt that is behind. Shared debts count once.
static func debt_stress(w: LTWorld, c: Dictionary) -> float:
	if int(w.market.get("stress_day", -1)) != w.day:
		w.market["stress_day"] = w.day
		w.market["stress"] = {}
	var cache: Dictionary = w.market["stress"]
	if cache.has(int(c["id"])):
		return float(cache[int(c["id"])])
	var v: float = _debt_stress(w, c)
	cache[int(c["id"])] = v
	return v


static func _debt_stress(w: LTWorld, c: Dictionary) -> float:
	var h: Dictionary = w.hh(int(c["household"]))
	var seen: Dictionary = {}
	var monthly: int = 0
	var late: int = 0
	var income: int = 0
	for a in w.household_adults(h):
		income += monthly_income(w, a)
		for d in personal_exposure(w, a):
			if seen.has(int(d["id"])):
				continue
			seen[int(d["id"])] = true
			if str(d["debtor_kind"]) == "p":
				monthly += min_due(d)
			if int(d["id"]) >= 0 and personal_exposure_has(d, c) and str(d["status"]) != "current" and str(d["status"]) != "assumed":
				late += 1
	if income <= 0:
		income = LTMoney.dollars(300.0)
	var ratio: float = float(monthly) / float(income)
	return clampf((ratio - 0.15) * 1.3 + float(late) * 0.25, 0.0, 1.0)


static func personal_exposure_has(d: Dictionary, c: Dictionary) -> bool:
	var cid: int = int(c["id"])
	return (str(d["debtor_kind"]) == "p" and int(d["debtor_id"]) == cid) or d["joint"].has(cid) or int(d["guarantor"]) == cid or str(d["debtor_kind"]) == "b"


static func min_due(d: Dictionary) -> int:
	if int(d["term"]) > 0:
		return mini(int(d["payment"]), int(d["balance"]))
	var interest: int = int(float(d["balance"]) * float(d["rate"]) / 12.0)
	return mini(int(d["balance"]) + interest, maxi(2500, int(float(d["balance"]) * 0.025) + interest))


# ================================================================ credit score

static func refresh_score(w: LTWorld, c: Dictionary) -> void:
	var cr: Dictionary = c["credit"]
	if not bool(cr["has_file"]):
		cr["score"] = 0
		return
	var months: float = float(cr["months"])
	var on_time: float = float(cr["on_time"])
	var late: float = float(cr["late"])
	var pay_hist: float = 1.0
	if on_time + late > 0.0:
		pay_hist = on_time / (on_time + late * 4.0)
	var s: float = 300.0 + pay_hist * 300.0
	s += clampf(months / 120.0, 0.0, 1.0) * 90.0
	# utilization of revolving credit
	var used: int = 0
	var limit: int = 0
	for d in personal_exposure(w, c):
		if str(d["type"]) == "credit_card":
			used += int(d["balance"])
			limit += maxi(int(d["limit"]), 1)
	var util: float = 0.0 if limit == 0 else float(used) / float(limit)
	s += (1.0 - clampf(util, 0.0, 1.0)) * 110.0
	s -= float(cr["collections"]) * 55.0
	s -= float(cr["chargeoffs"]) * 70.0
	var bk_age: int = w.day - int(cr["bankruptcy_day"])
	if bk_age < 3650:
		s -= 160.0 * (1.0 - float(bk_age) / 3650.0) + 40.0
	var recent: int = 0
	for q in cr["inquiries"]:
		if w.day - int(q) < 180:
			recent += 1
	s -= float(recent) * 8.0
	cr["score"] = int(clampf(s, 300.0, 850.0))


static func credit_event(w: LTWorld, c: Dictionary, kind: String) -> void:
	if c.is_empty():
		return
	var cr: Dictionary = c["credit"]
	match kind:
		"on_time", "on_time_rent":
			if kind == "on_time_rent" and not bool(cr["has_file"]):
				# on time rent reporting is how a young Sim with no history starts a file
				if int(c.get("rent_months", 0)) >= 5:
					cr["has_file"] = true
					w.log_sim(c, "Six months of on time rent reported. Now has a credit file for the first time.", true)
				c["rent_months"] = int(c.get("rent_months", 0)) + 1
			if bool(cr["has_file"]):
				cr["on_time"] = int(cr["on_time"]) + 1
		"late":
			cr["has_file"] = true
			cr["late"] = int(cr["late"]) + 1
		"collections":
			cr["has_file"] = true
			cr["collections"] = int(cr["collections"]) + 1
		"chargeoff":
			cr["chargeoffs"] = int(cr["chargeoffs"]) + 1
		"eviction":
			cr["collections"] = int(cr["collections"]) + 1
		"inquiry":
			cr["inquiries"].append(w.day)
			if cr["inquiries"].size() > 8:
				cr["inquiries"].remove_at(0)
		"bankruptcy":
			cr["bankruptcy_day"] = w.day
	refresh_score(w, c)


static func score_text(c: Dictionary) -> String:
	var cr: Dictionary = c["credit"]
	if not bool(cr["has_file"]):
		return "No credit history yet. Lenders treat them as an unknown, not a bad risk."
	var s: int = int(cr["score"])
	var band: String = "excellent" if s >= 760 else ("good" if s >= 690 else ("fair" if s >= 630 else ("poor" if s >= 560 else "very poor")))
	return "%d (%s)" % [s, band]


# ================================================================ lending

static func bank_min_score(w: LTWorld, dtype: String) -> int:
	var base: int = 620
	match dtype:
		"mortgage":
			base = 640
		"business_loan":
			base = 650
		"personal_loan":
			base = 600
		"credit_card":
			base = 580
	return base + int(float(w.bank["tightness"]) * 120.0)


static func bank_rate(w: LTWorld, dtype: String, score: int) -> float:
	var base: float = 0.08
	match dtype:
		"mortgage":
			base = 0.06
		"business_loan":
			base = 0.085
		"personal_loan":
			base = 0.12
		"credit_card":
			base = 0.229
		"city_loan":
			base = 0.05
	return base + float(w.bank["tightness"]) * 0.04 + maxf(0.0, float(760 - score)) / 100.0 * 0.012


## Returns {"ok", "reason", "rate", "max"} without lending.
static func bank_decision(w: LTWorld, c: Dictionary, dtype: String, amount: int, monthly_income: int) -> Dictionary:
	credit_event(w, c, "inquiry")
	var cr: Dictionary = c["credit"]
	var score: int = int(cr["score"])
	if w.day - int(cr["bankruptcy_day"]) < 730:
		return {"ok": false, "reason": "a bankruptcy less than two years old is on the record"}
	if not bool(cr["has_file"]):
		var starter_cap: int = LTMoney.dollars(1500.0)
		if amount <= starter_cap and dtype != "business_loan":
			return {"ok": true, "reason": "a small starter loan to build a credit file", "rate": bank_rate(w, dtype, 600), "max": starter_cap}
		return {"ok": false, "reason": "no credit history yet, so the bank will only make a small starter loan"}
	var need: int = bank_min_score(w, dtype)
	if score < need:
		return {"ok": false, "reason": "credit score %d is under the %d the bank wants right now" % [score, need]}
	var existing: int = 0
	for d in personal_exposure(w, c):
		existing += min_due(d)
	var rate: float = bank_rate(w, dtype, score)
	var term: int = 360 if dtype == "mortgage" else (84 if dtype == "business_loan" else 36)
	var new_pay: int = amortized_payment(amount, rate, term)
	var dti: float = float(existing + new_pay) / maxf(float(monthly_income), 1.0)
	var max_dti: float = 0.43 - float(w.bank["tightness"]) * 0.1
	if dti > max_dti:
		return {"ok": false, "reason": "payments would take %d%% of income, the bank allows %d%%" % [int(dti * 100.0), int(max_dti * 100.0)]}
	return {"ok": true, "reason": "credit %d and income cover it" % score, "rate": rate, "max": amount, "term": term}


## ---------------------------------------------------------------- loan programs
## The bank looks for a way to say yes, the way real lenders do. A buyer who can
## put money down and whose credit is good enough gets the program that fits:
## - Conventional mortgage: credit 620 or better, 5% down (private mortgage
##   insurance under 20% down), payments under 43% of income.
## - FHA: credit 580 with 3.5% down (500 to 579 with 10% down), payments up to
##   50% of income, with mortgage insurance for the life of the loan.
## - USDA Rural Development: no money down in a small rural town, credit 640,
##   for families earning under about $110,000, payments under 41% of income.
## - Business: a conventional bank loan with 20% down and cash flow 1.25 times
##   the payments; an SBA 7(a) loan with 10% down and cash flow 1.15 times; or,
##   for $50,000 or less, an SBA microloan from a nonprofit lender with credit 600
##   and some money of one's own in it.
## Everyone also needs cash for closing costs. When the answer is no, the bank
## says what it would take, and the Sim remembers.

const USDA_INCOME_LIMIT: int = 1100000000   # $110,000 a year, in cents


static func _score(w: LTWorld, c: Dictionary) -> int:
	return int(c["credit"]["score"]) if bool(c["credit"]["has_file"]) else 0


static func _existing_dues(w: LTWorld, c: Dictionary) -> int:
	var t: int = 0
	for d in personal_exposure(w, c):
		t += min_due(d)
	return t


## The best mortgage the household can get for this price, or why not.
static func mortgage_offer(w: LTWorld, h: Dictionary, head: Dictionary, price: int) -> Dictionary:
	var adults: Array = w.household_adults(h)
	var income: int = 0
	for a in adults:
		income += monthly_income(w, a)
	var cash: int = w.household_cash(h)
	var closing: int = int(float(price) * 0.03)
	# on a joint loan the lender goes by the lower score of the borrowers with income
	var score: int = 999
	for a in adults:
		if monthly_income(w, a) > 0 or a == head:
			score = mini(score, _score(w, a))
	if score == 999:
		score = _score(w, head)
	credit_event(w, head, "inquiry")
	if w.day - int(head["credit"]["bankruptcy_day"]) < 730:
		return {"ok": false, "reason": "a bankruptcy less than two years old is on the record", "advice": "wait until it is two years old"}
	var dues: int = _existing_dues(w, head)
	var tight: float = float(w.bank["tightness"])
	var programs: Array = [
		# name, min score, down share, max payments share of income, rate add, insurance a year
		["conventional", 620 + int(tight * 60.0), 0.2, 0.43, 0.0, 0.0],
		["conventional", 620 + int(tight * 60.0), 0.05, 0.43, 0.0025, 0.005],
		["USDA", 640 + int(tight * 40.0), 0.0, 0.41, 0.0, 0.0035],
		["FHA", 580, 0.035, 0.5, 0.0025, 0.0055],
		["FHA", 500, 0.1, 0.5, 0.005, 0.0055],
	]
	var why_not: Array = []
	for pg in programs:
		var name: String = str(pg[0])
		if name == "USDA" and income * 12 > USDA_INCOME_LIMIT:
			continue
		var down: int = int(float(price) * float(pg[2]))
		if cash < down + closing:
			why_not.append("%s needs %s down plus %s closing costs" % [name, LTMoney.fmt(down), LTMoney.fmt(closing)])
			continue
		if score < int(pg[1]):
			why_not.append("%s needs credit %d" % [name, int(pg[1])])
			continue
		var loan: int = price - down
		if name == "FHA":
			loan += int(float(loan) * 0.0175)   # the upfront premium is added to the loan
		var rate: float = bank_rate(w, "mortgage", score) + float(pg[4])
		var pay: int = amortized_payment(loan, rate, 360) + int(float(loan) * float(pg[5]) / 12.0)
		var dti: float = float(pay + dues) / maxf(1.0, float(income))
		if dti > float(pg[3]) - tight * 0.05:
			why_not.append("%s payments would be %d%% of income" % [name, int(dti * 100.0)])
			continue
		return {"ok": true, "program": name, "down": down, "loan": loan, "rate": rate, "closing": closing, "insurance": float(pg[5]),
			"reason": "%s loan: %s down, credit %d, payments %d%% of income" % [name, LTMoney.fmt(down), score, int(dti * 100.0)]}
	var advice: String = ""
	if score < 580:
		advice = "bring credit up to 580 and save %s for 3.5%% down and closing" % LTMoney.fmt(int(float(price) * 0.065))
	elif cash < int(float(price) * 0.065):
		advice = "save %s more for the down payment and closing costs" % LTMoney.fmt(int(float(price) * 0.065) - cash)
	else:
		advice = "earn more or pay down other debts, or look at a cheaper house"
	return {"ok": false, "reason": "; ".join(why_not.slice(0, 2)) if not why_not.is_empty() else "no program fits", "advice": advice}


## How a founder could finance a start up. equity is the founder's own money in
## it (savings, family gifts, grants). est_monthly is the founder's own guess of
## monthly profit; the bank only counts 70% of it.
static func business_offer(w: LTWorld, c: Dictionary, cs: Dictionary, equity: int, est_monthly: int) -> Dictionary:
	var total: int = int(cs["total"])
	var gap: int = maxi(0, total - equity)
	var share: float = float(equity) / maxf(1.0, float(total))
	var score: int = _score(w, c)
	credit_event(w, c, "inquiry")
	if w.day - int(c["credit"]["bankruptcy_day"]) < 730:
		return {"ok": false, "reason": "a bankruptcy less than two years old is on the record", "advice": "wait until it is two years old"}
	var tight: float = float(w.bank["tightness"])
	var cash_flow: float = float(est_monthly) * 0.7 + float(monthly_income(w, c)) * 0.25
	var dues: int = _existing_dues(w, c)
	var building: int = mini(gap, int(float(cs["building"]) * 0.9))
	var programs: Array = [
		# name, min score, min own share, min coverage, rate add, fee share, real estate years, other years, max amount
		["bank loan", bank_min_score(w, "business_loan"), 0.2, 1.25, 0.0, 0.0, 20, 7, 0],
		["SBA 7(a) loan", 640 + int(tight * 60.0), 0.1, 1.15, 0.0125, 0.03, 25, 10, 0],
		["SBA microloan", 600, 0.05, 1.05, 0.025, 0.0, 6, 6, 5000000],
	]
	var why_not: Array = []
	for pg in programs:
		var name: String = str(pg[0])
		if int(pg[8]) > 0 and gap > int(pg[8]):
			continue
		if share < float(pg[2]):
			why_not.append("a %s needs %d%% down, %s" % [name, int(float(pg[2]) * 100.0), LTMoney.fmt(int(float(total) * float(pg[2])))])
			continue
		if score < int(pg[1]):
			why_not.append("a %s needs credit %d" % [name, int(pg[1])])
			continue
		var rate: float = bank_rate(w, "business_loan", maxi(score, 600)) + float(pg[4])
		var re_part: int = building if int(pg[8]) == 0 else 0
		var pay: int = amortized_payment(re_part, rate - 0.01, int(pg[6]) * 12) + amortized_payment(gap - re_part, rate, int(pg[7]) * 12)
		var cover: float = cash_flow / maxf(1.0, float(pay + dues))
		if cover < float(pg[3]) + tight * 0.1:
			why_not.append("the %s would need the business to earn %.2f times the payments, the plan shows %.2f" % [name, float(pg[3]), cover])
			continue
		return {"ok": true, "program": name, "rate": rate, "fee": int(float(gap) * float(pg[5]) * 0.75), "re_part": re_part, "re_years": int(pg[6]), "years": int(pg[7]),
			"sba": name.begins_with("SBA"), "reason": "%s at %.1f%%, %d%% down, credit %d" % [name, rate * 100.0, int(share * 100.0), score]}
	var advice: String = ""
	if share < 0.05:
		advice = "save at least %s to put into it" % LTMoney.fmt(int(float(total) * 0.1))
	elif score < 600:
		advice = "build credit to at least 640"
	elif share < 0.1:
		advice = "put in %s more of their own money" % LTMoney.fmt(int(float(total) * 0.1) - equity)
	else:
		advice = "start smaller or show more income"
	return {"ok": false, "reason": "; ".join(why_not.slice(0, 2)) if not why_not.is_empty() else "no program fits", "advice": advice}


## Pays out a new loan from the local bank if the town has one with the money, else
## from the outside bank. The debt record names whichever lender it really was.
static func fund_loan(w: LTWorld, d: Dictionary, to_acct: String, amount: int) -> void:
	var lb: Dictionary = LTServices.local_bank(w)
	if not lb.is_empty() and w.biz_cash(lb) - amount > LTMoney.dollars(15000.0) and str(d["debtor_kind"]) != "city":
		d["creditor"] = "business"
		d["creditor_id"] = int(lb["id"])
		w.ledger.pay(w.acct_b(lb), to_acct, amount, "loans_out_local")
		lb["loans_made"] = int(lb.get("loans_made", 0)) + 1
		_dhist(w, d, "Funded by %s, the local bank. The interest stays in town." % lb["name"])
		w.log_biz(lb, "Lent %s to %s." % [LTMoney.fmt(amount), debtor_name(w, d)])
		return
	w.ledger.pay("bank", to_acct, amount, "loans_out")


static func monthly_income(w: LTWorld, c: Dictionary) -> int:
	if bool(c["retired"]):
		return LTPeople.PENSION_MONTHLY
	var pay: int = int(c["job"]["daily_wage"]) * 21
	# an owner lives on the business: the average of its last three months' profit
	for bid in c.get("owns", []):
		var b: Dictionary = w.biz(int(bid))
		if b.is_empty() or str(b["status"]) != "open":
			continue
		var hist: Array = b.get("month_profit_hist", [])
		if hist.is_empty():
			continue
		var t: int = 0
		var n: int = 0
		for i in range(maxi(0, hist.size() - 3), hist.size()):
			t += int(hist[i])
			n += 1
		pay += maxi(0, t / maxi(1, n)) / maxi(1, b["owners"].size())
	return pay


static func personal_loan(w: LTWorld, c: Dictionary, reason: String) -> void:
	var amount: int = LTMoney.dollars(clampf(float(LTPeople.monthly_bills(w, w.hh(int(c["household"])))) / 100.0, 500.0, 4000.0))
	var dec: Dictionary = bank_decision(w, c, "personal_loan", amount, maxi(monthly_income(w, c), 1))
	if not bool(dec["ok"]):
		w.counters["loans_denied"] = int(w.counters["loans_denied"]) + 1
		w.log_sim(c, "Asked %s for a %s personal loan and was turned down. Reason: %s." % [BANK_NAME, LTMoney.fmt(amount), dec["reason"]], true)
		w.remember(c, "loan_denied", -1, -10.0)
		return
	amount = mini(amount, int(dec["max"]))
	var d: Dictionary = new_debt(w, "p", int(c["id"]), "bank", -1, "personal_loan", amount, float(dec["rate"]), 24, "", -1, [])
	LTFinance.fund_loan(w, d, w.acct_p(c), amount)
	w.bank["lent_12m"] = int(w.bank["lent_12m"]) + amount
	w.counters["loans_made"] = int(w.counters["loans_made"]) + 1
	if not bool(c["credit"]["has_file"]):
		c["credit"]["has_file"] = true
	w.log_sim(c, "Took a %s personal loan at %.1f%%. Reason: %s." % [LTMoney.fmt(amount), float(d["rate"]) * 100.0, reason], true)


static func open_card_room(w: LTWorld, c: Dictionary) -> int:
	var room: int = 0
	for d in personal_exposure(w, c):
		if str(d["type"]) == "credit_card" and str(d["status"]) == "current":
			room += maxi(0, int(d["limit"]) - int(d["balance"]))
	return room


## Draw on a credit card to cover a shortfall. Returns amount drawn.
static func card_draw(w: LTWorld, c: Dictionary, amount: int, why: String) -> int:
	for d in personal_exposure(w, c):
		if str(d["type"]) != "credit_card" or str(d["status"]) != "current" or int(d["debtor_id"]) != int(c["id"]):
			continue
		var room: int = int(d["limit"]) - int(d["balance"])
		if room <= 0:
			continue
		var take: int = mini(room, amount)
		d["balance"] = int(d["balance"]) + take
		w.ledger.pay("bank", w.acct_p(c), take, "card_draws")
		if take >= LTMoney.dollars(200.0):
			w.log_sim(c, "Put %s on a credit card to cover %s." % [LTMoney.fmt(take), why], false)
		return take
	return 0


static func rental_approved(w: LTWorld, h: Dictionary) -> bool:
	for m in w.household_adults(h):
		var cr: Dictionary = m["credit"]
		if not bool(cr["has_file"]) or int(cr["score"]) >= 560:
			return true
	return false


# ================================================================ daily debt cycle

static func daily(w: LTWorld) -> void:
	var dom: int = LTCalendar.day_of_month(w.day)
	for d in w.debts:
		if not is_active(d) or str(d["status"]) == "in_bankruptcy":
			continue
		if int(d["due_dom"]) == dom:
			_cycle(w, d)
	if dom == 20:
		_bankruptcy_month(w)
		_plans_month(w)
	if dom == 1:
		_bank_month(w)
	if w.day % 30 == 0:
		for c in w.citizens:
			if w.is_present(c) and bool(c["credit"]["has_file"]):
				c["credit"]["months"] = int(c["credit"]["months"]) + 1


static func _payer_accounts(w: LTWorld, d: Dictionary) -> Array:
	match str(d["debtor_kind"]):
		"p":
			var out: Array = []
			var c: Dictionary = w.cit(int(d["debtor_id"]))
			if w.is_present(c):
				out.append(c)
			for j in d["joint"]:
				var jc: Dictionary = w.cit(int(j))
				if w.is_present(jc):
					out.append(jc)
			return out
	return []


static func _cycle(w: LTWorld, d: Dictionary) -> void:
	if str(d["debtor_kind"]) == "p":
		var dc: Dictionary = w.cit(int(d["debtor_id"]))
		if not dc.is_empty() and bool(dc["left_town"]):
			return
	var interest: int = int(float(d["balance"]) * float(d["rate"]) / 12.0)
	d["balance"] = int(d["balance"]) + interest
	if str(d["debtor_kind"]) == "b":
		var db: Dictionary = w.biz(int(d["debtor_id"]))
		if not db.is_empty() and str(db["status"]) == "building":
			# while the building goes up the interest is added to the loan; payments
			# start when the doors open
			if not bool(d.get("deferred_note", false)):
				d["deferred_note"] = true
				_dhist(w, d, "Payments wait until the business opens; the interest meanwhile is added to the loan.")
			return
	var due: int = min_due(d)
	if int(d["term"]) > 0:
		due = mini(int(d["payment"]) + int(d["missed"]) * 0, int(d["balance"]))
	var paid: int = 0
	var to_acct: String = creditor_acct(w, d)
	match str(d["debtor_kind"]):
		"p":
			var payers: Array = _payer_accounts(w, d)
			for c in payers:
				if paid >= due:
					break
				paid += w.ledger.pay(w.acct_p(c), to_acct, due - paid, "debt_payments")
			if paid < due and not payers.is_empty() and str(d["type"]) != "credit_card":
				# a disciplined Sim will lean on a card to stay current on secured debt
				var c0: Dictionary = payers[0]
				if int(c0["traits"]["discipline"]) > 45 and (str(d["secured_by"]) != ""):
					var drawn: int = card_draw(w, c0, due - paid, "a %s payment" % str(d["type"]).replace("_", " "))
					paid += w.ledger.pay(w.acct_p(c0), to_acct, drawn, "debt_payments")
		"b":
			var b: Dictionary = w.biz(int(d["debtor_id"]))
			paid += w.ledger.pay(w.acct_b(b), to_acct, due, "debt_payments")
			if paid < due and str(b["legal_form"]) == "sole":
				for oid in b["owners"]:
					var o: Dictionary = w.cit(int(oid))
					if w.is_present(o) and paid < due:
						var p2: int = w.ledger.pay(w.acct_p(o), to_acct, due - paid, "debt_payments")
						if p2 > 0:
							w.log_sim(o, "Paid %s of %s's loan from personal savings. As a sole owner, the business debt is theirs too." % [LTMoney.fmt(p2), b["name"]], false)
						paid += p2
		"city":
			paid += w.ledger.pay("city", to_acct, due, "city_debt_service")
	d["balance"] = int(d["balance"]) - paid
	d["paid_total"] = int(d["paid_total"]) + paid
	if str(d["creditor"]) == "business":
		var cb: Dictionary = w.biz(int(d["creditor_id"]))
		if not cb.is_empty() and str(cb["type"]) == "bank":
			cb["month_revenue"] = int(cb["month_revenue"]) + mini(paid, interest)
	var people: Array = _score_people(w, d)
	if int(d["balance"]) <= 0:
		d["balance"] = 0
		d["status"] = "paid"
		_dhist(w, d, "Paid off.")
		w.counters["debts_paid_off"] = int(w.counters["debts_paid_off"]) + 1
		for c in people:
			w.log_sim(c, "Paid off the %s with %s." % [str(d["type"]).replace("_", " "), creditor_name(w, d)], true)
			credit_event(w, c, "on_time")
		return
	if paid >= due:
		if str(d["status"]) != "current" and str(d["status"]) != "assumed":
			_dhist(w, d, "Caught up. Back to current.")
			for c in people:
				w.log_sim(c, "Caught up on the %s. It is current again." % str(d["type"]).replace("_", " "), true)
		d["status"] = "current" if str(d["status"]) != "assumed" else "assumed"
		d["missed"] = 0
		for c in people:
			credit_event(w, c, "on_time")
		return
	_missed(w, d, paid, due, people)


static func _score_people(w: LTWorld, d: Dictionary) -> Array:
	var out: Array = []
	match str(d["debtor_kind"]):
		"p":
			out = _payer_accounts(w, d)
		"b":
			var b: Dictionary = w.biz(int(d["debtor_id"]))
			if not b.is_empty():
				for oid in b["owners"]:
					var o: Dictionary = w.cit(int(oid))
					if w.is_present(o) and (str(b["legal_form"]) == "sole" or int(d["guarantor"]) == int(oid)):
						out.append(o)
	return out


static func _missed(w: LTWorld, d: Dictionary, paid: int, due: int, people: Array) -> void:
	d["missed"] = int(d["missed"]) + 1
	d["balance"] = int(d["balance"]) + mini(LATE_FEE, int(w.city["laws"].get("late_fee_cap", LATE_FEE)))
	var m: int = int(d["missed"])
	var steps: Array = ["current", "late30", "late60", "late90", "collections"]
	d["status"] = steps[mini(m, 4)]
	var what: String = str(d["type"]).replace("_", " ")
	var cname: String = creditor_name(w, d)
	_dhist(w, d, "Missed payment. Paid %s of %s. Late fee added. Now %s." % [LTMoney.fmt(paid), LTMoney.fmt(due), status_text(str(d["status"]))])
	for c in people:
		credit_event(w, c, "late")
		w.log_sim(c, "Missed the %s payment to %s (paid %s of %s). The debt is now %s." % [what, cname, LTMoney.fmt(paid), LTMoney.fmt(due), status_text(str(d["status"]))], true)
		c["needs"]["money_security"] = float(c["needs"]["money_security"]) - 8.0
	if m >= 4:
		_enforce(w, d, people)


## The creditor acts in its own interest. Each step costs it money, so small debts get charged off.
static func _enforce(w: LTWorld, d: Dictionary, people: Array) -> void:
	var bal: int = int(d["balance"])
	var secured: String = str(d["secured_by"])
	if int(d["missed"]) == 4:
		for c in people:
			credit_event(w, c, "collections")
	if secured == "house" and str(d["type"]) == "mortgage" and int(d["missed"]) >= 2 and int(d["missed"]) < 5 and not people.is_empty():
		# behind on the mortgage with equity in the house: most owners sell before the
		# bank forecloses and keep what is left; sharper ones see it sooner
		var c0: Dictionary = people[0]
		var h0: Dictionary = w.hh(int(c0["household"]))
		var l0: Dictionary = w.lot(int(d["collateral_lot"]))
		if int(h0.get("mortgage", -1)) == int(d["id"]) and int(h0["lot"]) == int(l0["id"]) and float(l0["value"]) * 0.9 > float(bal):
			var sense: float = float(c0["skills"]["finance"]) * 0.4 + float(c0["traits"]["discipline"]) * 0.3 + float(int(d["missed"]) - 2) * 25.0 - float(c0["traits"]["risk"]) * 0.2
			if sense + w.rng.randf_range(-10.0, 10.0) > 15.0:
				sell_house(w, h0, "behind on the mortgage; selling before the bank forecloses keeps the equity and the credit record")
				h0["tenure"] = "rent"
				h0["rent"] = int(l0["unit_rent"])
				w.counters["distress_sales"] = int(w.counters.get("distress_sales", 0)) + 1
				return
	if secured == "house" and int(d["missed"]) >= 5:
		_foreclose(w, d, people)
		return
	if (secured == "vehicle" or secured == "equipment") and int(d["missed"]) >= 4:
		_repossess(w, d, people)
		return
	if secured == "" and bal < LTMoney.dollars(2500.0) and int(d["missed"]) >= 6:
		_charge_off(w, d, people, "too small to be worth a court case")
		return
	if secured == "" and int(d["missed"]) == 6 and str(d["debtor_kind"]) == "p":
		d["status"] = "judgment"
		_dhist(w, d, "Creditor won a court judgment. Wages can now be garnished.")
		for c in people:
			w.log_sim(c, "%s won a court judgment over the %s. Up to a quarter of wages can now be taken each month." % [creditor_name(w, d), str(d["type"]).replace("_", " ")], true)
		return
	if str(d["status"]) == "judgment" or int(d["missed"]) > 6:
		if str(d["debtor_kind"]) == "p":
			for c in people:
				var garn: int = int(float(monthly_income(w, c)) * 0.25)
				var got: int = w.ledger.pay(w.acct_p(c), creditor_acct(w, d), mini(garn, int(d["balance"])), "garnishment")
				if got > 0:
					d["balance"] = int(d["balance"]) - got
					_dhist(w, d, "Garnished %s from wages." % LTMoney.fmt(got))
					w.log_sim(c, "%s was garnished from wages for the %s." % [LTMoney.fmt(got), str(d["type"]).replace("_", " ")], true)
		if int(d["missed"]) >= 12:
			_charge_off(w, d, people, "a year of missed payments")


static func _charge_off(w: LTWorld, d: Dictionary, people: Array, why: String) -> void:
	var loss: int = int(d["balance"])
	d["status"] = "charged_off"
	d["loss"] = loss
	_dhist(w, d, "Charged off as a loss of %s. Reason: %s." % [LTMoney.fmt(loss), why])
	_book_loss(w, d, loss)
	w.counters["debts_charged_off"] = int(w.counters["debts_charged_off"]) + 1
	for c in people:
		credit_event(w, c, "chargeoff")
		w.log_sim(c, "%s charged off the %s (%s). It stops calling but the mark stays on the credit record." % [creditor_name(w, d), str(d["type"]).replace("_", " "), LTMoney.fmt(loss)], true)


static func _book_loss(w: LTWorld, d: Dictionary, loss: int) -> void:
	if bool(d.get("sba", false)):
		# the SBA pays the lender 75% of what is lost
		var paid: int = w.ledger.pay("outside", creditor_acct(w, d), int(float(loss) * 0.75), "sba_guarantee")
		_dhist(w, d, "The SBA guarantee paid the lender %s." % LTMoney.fmt(paid))
		loss -= paid
	if str(d["creditor"]) == "bank":
		w.bank["losses_12m"] = int(w.bank["losses_12m"]) + loss
		w.bank["losses_total"] = int(w.bank["losses_total"]) + loss
	elif str(d["creditor"]) == "business":
		var b: Dictionary = w.biz(int(d["creditor_id"]))
		if not b.is_empty():
			w.log_biz(b, "Took a %s loss on money owed by %s." % [LTMoney.fmt(loss), debtor_name(w, d)])
	elif str(d["creditor"]) == "city":
		w.city["bad_debt"] = int(w.city.get("bad_debt", 0)) + loss


static func _repossess(w: LTWorld, d: Dictionary, people: Array) -> void:
	var resale: int = int(float(d["original"]) * 0.35)
	var applied: int = mini(resale, int(d["balance"]))
	d["balance"] = int(d["balance"]) - applied
	_dhist(w, d, "The %s was repossessed and sold for %s." % [d["secured_by"], LTMoney.fmt(applied)])
	w.counters["repossessions"] = int(w.counters["repossessions"]) + 1
	for c in people:
		w.log_sim(c, "The %s was repossessed by %s. The sale covered %s of the debt." % [d["secured_by"], creditor_name(w, d), LTMoney.fmt(applied)], true)
		if str(d["secured_by"]) == "vehicle":
			w.hh(int(c["household"]))["car"] = false
	if str(d["debtor_kind"]) == "b":
		var b: Dictionary = w.biz(int(d["debtor_id"]))
		b["equipment"] = maxf(0.0, float(b.get("equipment", 1.0)) - 0.6)
		w.log_biz(b, "Equipment repossessed by %s." % creditor_name(w, d))
	if int(d["balance"]) <= 0:
		d["status"] = "paid"
		d["balance"] = 0
	else:
		d["secured_by"] = ""
		d["status"] = "collections"
		_dhist(w, d, "The remaining %s is now unsecured." % LTMoney.fmt(int(d["balance"])))


static func _foreclose(w: LTWorld, d: Dictionary, people: Array) -> void:
	var l: Dictionary = w.lot(int(d["collateral_lot"]))
	var sale: int = int(float(l.get("value", 0)) * 0.8)
	w.counters["foreclosures"] = int(w.counters["foreclosures"]) + 1
	# the bank sells the house to an outside buyer, the money comes into town to the bank
	w.ledger.pay("outside", "bank", sale, "foreclosure_sales")
	var to_debt: int = mini(sale, int(d["balance"]))
	var surplus: int = sale - to_debt
	d["balance"] = int(d["balance"]) - to_debt
	_dhist(w, d, "Foreclosed. The house sold for %s." % LTMoney.fmt(sale))
	if surplus > 0 and not people.is_empty():
		w.ledger.pay("bank", w.acct_p(people[0]), surplus, "foreclosure_surplus")
	var h: Dictionary = {}
	if not people.is_empty():
		h = w.hh(int(people[0]["household"]))
	l["owner_kind"] = "outside"
	l["owner_id"] = -1
	l["unit_rent"] = LTMoney.dollars(1100.0)
	for c in people:
		w.remember(c, "foreclosed", -1, -60.0)
		w.log_sim(c, "Lost the house on %s to foreclosure. The bank sold it for %s." % [LTGeography.lot_label(w, int(l["id"])), LTMoney.fmt(sale)], true)
	w.chronicle_add("%s lost their house to foreclosure." % debtor_name(w, d), "debt", true, people.map(func(x): return x["id"]))
	if int(d["balance"]) <= 0:
		d["status"] = "paid"
		d["balance"] = 0
	else:
		_charge_off(w, d, people, "the house sale did not cover the loan")
	if not h.is_empty() and int(h["lot"]) == int(l["id"]):
		h["mortgage"] = -1
		# the outside buyer rents it back if they can pay, otherwise they must leave
		if w.household_cash(h) > int(l["unit_rent"]) and LTFinance.rental_approved(w, h):
			h["tenure"] = "rent"
			h["rent"] = int(l["unit_rent"])
			for c in w.household_members(h):
				w.log_sim(c, "Stayed in the house as a renter of the new owner.", true)
		else:
			LTPeople.evict(w, h, "the new owner")


static func status_text(s: String) -> String:
	match s:
		"current":
			return "current"
		"late30":
			return "30 days late"
		"late60":
			return "60 days late"
		"late90":
			return "90 days late"
		"collections":
			return "in collections"
		"judgment":
			return "under a court judgment"
		"charged_off":
			return "charged off"
		"in_bankruptcy":
			return "frozen in bankruptcy"
		"discharged":
			return "discharged in bankruptcy"
		"paid":
			return "paid off"
		"written_off_estate":
			return "unpaid when the estate ran out"
		"assumed":
			return "assumed by an heir"
		"moved_away":
			return "followed the debtor out of town"
	return s


# ================================================================ bankruptcy (a Sim decision)

static func _bankruptcy_month(w: LTWorld) -> void:
	for c in w.citizens:
		if not w.is_present(c) or w.age_years(c) < 18 or not c["bk"].is_empty():
			continue
		var exp: Array = personal_exposure(w, c)
		if exp.is_empty():
			continue
		var unsecured: int = 0
		var behind: int = 0
		var trigger: String = ""
		for d in exp:
			if str(d["secured_by"]) == "" and bool(d["dischargeable"]):
				unsecured += int(d["balance"])
			if int(d["missed"]) >= 2:
				behind += 1
			if str(d["status"]) == "judgment":
				trigger = "a court judgment and wage garnishment"
			if str(d["secured_by"]) == "house" and int(d["missed"]) >= 3:
				trigger = "a foreclosure notice"
		# filing costs about $1,650 and stays on the record ten years, so people only
		# file over about $10,000 or more they cannot pay; smaller debts go to collections
		if behind == 0 or unsecured < LTMoney.dollars(10000.0):
			continue
		var h: Dictionary = w.hh(int(c["household"]))
		var income: int = monthly_income(w, c)
		var bills: int = LTPeople.monthly_bills(w, h) / maxi(1, w.household_adults(h).size())
		var spare: int = maxi(0, income - bills)
		var months_to_repay: float = 999.0 if spare <= 0 else float(unsecured) / float(spare)
		if trigger == "":
			if str(c["job"]["kind"]) == "none":
				trigger = "job loss"
			elif not c["owns"].is_empty():
				trigger = "a business that is not making it"
			else:
				trigger = "debts that keep growing"
		var t: Dictionary = c["traits"]
		var desperation: float = clampf(months_to_repay / 60.0, 0.0, 2.0) * 30.0 + float(behind) * 8.0 + (100.0 - float(c["needs"]["money_security"])) * 0.2
		var advice: float = _advice(w, c)
		var pride: float = float(t["honesty"]) * 0.15 + float(t["discipline"]) * 0.2
		var score: float = desperation + advice - pride + w.rng.randf_range(-8.0, 8.0)
		if score > 38.0:
			file_bankruptcy(w, c, trigger, unsecured, spare)
		elif score > 25.0 and w.rng.randf() < 0.3:
			w.log_sim(c, "Thought about filing for bankruptcy and decided to keep struggling. Reason: pride and hope that things turn around.", true)


static func _advice(w: LTWorld, c: Dictionary) -> float:
	var best: float = float(c["skills"]["finance"]) * 0.15
	for k in c["rel"]:
		var o: Dictionary = w.cit(int(k))
		if w.is_present(o) and float(c["rel"][k]["trust"]) > 55.0:
			best = maxf(best, float(o["skills"]["finance"]) * 0.2)
	# a lawyer in town gives sharper advice about when filing makes sense
	if not w.open_businesses("law_office").is_empty():
		best += 8.0
	return best


static func file_bankruptcy(w: LTWorld, c: Dictionary, trigger: String, unsecured: int, spare: int) -> void:
	var h: Dictionary = w.hh(int(c["household"]))
	var owns_house: bool = str(h["tenure"]) == "own"
	var wants_house: float = 30.0 if owns_house else 0.0
	var income: int = monthly_income(w, c)
	var median: int = LTMoney.dollars(3200.0)
	var chapter: int = 7
	LTServices.spend(w, w.acct_p(c), "legal", LTMoney.dollars(1650.0), int(h["lot"]), c)
	if income > median and spare > LTMoney.dollars(150.0):
		chapter = 13
	elif owns_house and spare > LTMoney.dollars(200.0) and wants_house + float(c["traits"]["discipline"]) * 0.3 > 40.0:
		chapter = 13
	w.counters["bankruptcies"] = int(w.counters["bankruptcies"]) + 1
	w.counters["bankruptcies_ch%d" % chapter] = int(w.counters["bankruptcies_ch%d" % chapter]) + 1
	w.bank["bankruptcies_12m"] = int(w.bank["bankruptcies_12m"]) + 1
	credit_event(w, c, "bankruptcy")
	w.remember(c, "bankruptcy", -1, -50.0)
	var path: String = "liquidation (like Chapter 7)" if chapter == 7 else "a repayment plan (like Chapter 13)"
	w.log_sim(c, "Filed for bankruptcy under %s. Trigger: %s. Unsecured debt of %s could not be repaid in any realistic time." % [path, trigger, LTMoney.fmt(unsecured)], true)
	w.chronicle_add("%s filed for bankruptcy under %s after %s." % [w.full_name(c), path, trigger], "bankruptcy", true, [c["id"]])
	if chapter == 7:
		_chapter7(w, c, h)
	else:
		_chapter13(w, c, h, spare)


static func _chapter7(w: LTWorld, c: Dictionary, h: Dictionary) -> void:
	var exp: Array = personal_exposure(w, c)
	# trustee takes non exempt cash and sole proprietor business assets
	var pool: int = 0
	var non_exempt: int = maxi(0, w.cash(c) - CASH_EXEMPTION)
	pool += w.ledger.pay(w.acct_p(c), "outside", non_exempt, "bk_trustee_hold")
	for bid in c["owns"].duplicate():
		var b: Dictionary = w.biz(int(bid))
		if b.is_empty() or str(b["status"]) != "open":
			continue
		if str(b["legal_form"]) == "sole":
			pool += w.ledger.pay(w.acct_b(b), "outside", w.biz_cash(b), "bk_trustee_hold")
			LTEconomy.close_business(w, b, "the owner's bankruptcy. The trustee sold what it had")
	# the trustee fee comes off the top, the rest goes back in to pay creditors
	var fee: int = int(float(pool) * 0.1)
	var to_creditors: int = pool - fee
	# secured debts: surrender collateral if behind, otherwise keep paying
	var unsecured_list: Array = []
	var unsecured_total: int = 0
	for d in exp:
		if str(d["secured_by"]) == "house":
			if int(d["missed"]) >= 2:
				_foreclose(w, d, [c])
			else:
				_dhist(w, d, "Kept through the bankruptcy. Payments continue.")
		elif str(d["secured_by"]) != "":
			if int(d["missed"]) >= 1:
				_repossess(w, d, [c])
				if is_active(d) and int(d["balance"]) > 0:
					unsecured_list.append(d)
					unsecured_total += int(d["balance"])
		elif bool(d["dischargeable"]):
			unsecured_list.append(d)
			unsecured_total += int(d["balance"])
	for d in unsecured_list:
		var share: int = 0 if unsecured_total == 0 else int(float(to_creditors) * float(d["balance"]) / float(unsecured_total))
		if share > 0:
			w.ledger.pay("outside", creditor_acct(w, d), share, "bk_trustee_paid")
		var loss: int = int(d["balance"]) - share
		d["balance"] = 0
		d["status"] = "discharged"
		d["loss"] = loss
		_dhist(w, d, "Discharged in bankruptcy. The trustee paid %s, the creditor lost %s." % [LTMoney.fmt(share), LTMoney.fmt(loss)])
		_book_loss(w, d, loss)
	w.log_sim(c, "The bankruptcy court discharged %d debts. Kept exempt basics. The filing stays on the credit record for about 10 years, new credit will be slow and expensive." % unsecured_list.size(), true)
	c["bk"] = {"chapter": 7, "filed": w.day, "status": "discharged"}


static func _chapter13(w: LTWorld, c: Dictionary, h: Dictionary, spare: int) -> void:
	var plan: int = maxi(LTMoney.dollars(100.0), int(float(spare) * 0.7))
	var months: int = 36 if monthly_income(w, c) < LTMoney.dollars(3200.0) else 60
	var claims: Array = []
	for d in personal_exposure(w, c):
		if str(d["secured_by"]) == "" and bool(d["dischargeable"]):
			d["status"] = "in_bankruptcy"
			_dhist(w, d, "Frozen in a repayment plan.")
			claims.append(int(d["id"]))
	c["bk"] = {"chapter": 13, "filed": w.day, "status": "plan", "plan_monthly": plan, "months_left": months, "missed": 0, "claims": claims}
	w.log_sim(c, "The court set a plan of %s a month for %d months. Keeps the house and pays creditors a share of income. If the plan is finished, what is left of the eligible debt is discharged." % [LTMoney.fmt(plan), months], true)


static func _plans_month(w: LTWorld) -> void:
	for c in w.citizens:
		if not w.is_present(c) or c["bk"].is_empty() or str(c["bk"]["status"]) != "plan":
			continue
		var bk: Dictionary = c["bk"]
		var claims: Array = bk["claims"]
		var total: int = 0
		for did in claims:
			total += int(w.debt(int(did))["balance"])
		var paid: int = w.ledger.pay(w.acct_p(c), "outside", int(bk["plan_monthly"]), "bk_plan_payments")
		if paid >= int(bk["plan_monthly"]):
			bk["months_left"] = int(bk["months_left"]) - 1
			# trustee forwards the plan payment to creditors pro rata
			for did in claims:
				var d: Dictionary = w.debt(int(did))
				var share: int = 0 if total == 0 else int(float(paid) * float(d["balance"]) / float(total))
				share = mini(share, int(d["balance"]))
				w.ledger.pay("outside", creditor_acct(w, d), share, "bk_trustee_paid")
				d["balance"] = int(d["balance"]) - share
			w.ledger.pay(w.acct_p(c), "outside", 0, "none")
		else:
			# refund what came in: an incomplete plan payment stays with the trustee for this simple model
			bk["missed"] = int(bk["missed"]) + 1
			w.log_sim(c, "Missed a bankruptcy plan payment (%d missed)." % bk["missed"], true)
			if int(bk["missed"]) >= 3:
				bk["status"] = "dismissed"
				for did in claims:
					var d2: Dictionary = w.debt(int(did))
					d2["status"] = "collections"
					d2["missed"] = 4
					_dhist(w, d2, "Bankruptcy case dismissed. Collection resumes.")
				w.log_sim(c, "The bankruptcy case was dismissed after three missed plan payments. Creditors can collect again.", true)
				w.chronicle_add("%s's bankruptcy plan was dismissed." % w.full_name(c), "bankruptcy", true, [c["id"]])
		if int(bk["months_left"]) <= 0 and str(bk["status"]) == "plan":
			for did in claims:
				var d3: Dictionary = w.debt(int(did))
				var loss: int = int(d3["balance"])
				d3["balance"] = 0
				d3["status"] = "discharged"
				d3["loss"] = loss
				_book_loss(w, d3, loss)
				_dhist(w, d3, "Plan finished. Remaining %s discharged." % LTMoney.fmt(loss))
			bk["status"] = "discharged"
			w.log_sim(c, "Finished the bankruptcy plan. The rest of the eligible debt is discharged.", true)


static func _bank_month(w: LTWorld) -> void:
	var book: float = 0.0
	for d in w.debts:
		if is_active(d) and str(d["creditor"]) == "bank":
			book += float(d["balance"])
	var loss_ratio: float = float(w.bank["losses_12m"]) / maxf(book, float(LTMoney.dollars(200000.0)))
	var bk_wave: float = float(w.bank["bankruptcies_12m"]) / maxf(1.0, float(w.alive_count()) / 100.0)
	var old: float = float(w.bank["tightness"])
	var target: float = clampf(0.2 + loss_ratio * 9.0 + bk_wave * 0.05, 0.1, 0.95)
	w.bank["tightness"] = old + (target - old) * 0.35
	w.bank["monthly"].append({"day": w.day, "tightness": w.bank["tightness"], "losses": w.bank["losses_12m"], "lent": w.bank["lent_12m"]})
	if w.bank["monthly"].size() > 120:
		w.bank["monthly"].remove_at(0)
	if float(w.bank["tightness"]) - old > 0.05:
		w.chronicle_add("%s tightened lending after %s in losses and %d bankruptcies this year. New founders will find loans harder to get." % [BANK_NAME, LTMoney.fmt(int(w.bank["losses_12m"])), w.bank["bankruptcies_12m"]], "debt", true, [])
	# twelve month windows decay
	w.bank["losses_12m"] = int(float(w.bank["losses_12m"]) * 0.92)
	w.bank["lent_12m"] = int(float(w.bank["lent_12m"]) * 0.92)
	w.bank["bankruptcies_12m"] = int(floor(float(w.bank["bankruptcies_12m"]) * 0.92))


# ================================================================ houses, death, leaving

static func sell_house(w: LTWorld, h: Dictionary, why: String) -> void:
	var l: Dictionary = w.lot(int(h["lot"]))
	var sale: int = int(float(l["value"]) * 0.95)
	var seller: Dictionary = w.cit(int(l["owner_id"]))
	if seller.is_empty():
		return
	w.ledger.pay("outside", w.acct_p(seller), sale, "house_sales")
	LTServices.spend(w, w.acct_p(seller), "real_estate", int(float(sale) * 0.05), int(l["id"]), seller)
	if int(h["mortgage"]) >= 0:
		var d: Dictionary = w.debt(int(h["mortgage"]))
		if is_active(d):
			var pay: int = w.ledger.pay(w.acct_p(seller), "bank", int(d["balance"]), "mortgage_payoff")
			d["balance"] = int(d["balance"]) - pay
			if int(d["balance"]) <= 0:
				d["status"] = "paid"
				d["balance"] = 0
				_dhist(w, d, "Paid off from the house sale.")
	h["mortgage"] = -1
	l["owner_kind"] = "outside"
	l["owner_id"] = -1
	l["unit_rent"] = LTMoney.dollars(1050.0)
	w.log_sim(seller, "Sold the house for %s. Reason: %s." % [LTMoney.fmt(sale), why], true)


static func debtor_left_town(w: LTWorld, c: Dictionary) -> void:
	for d in debts_of(w, "p", int(c["id"])):
		d["status"] = "moved_away"
		_dhist(w, d, "The debtor moved out of town. The account went to an outside collector.")


## The estate pays, children do not inherit debt. Creditors are paid in legal order.
static func settle_estate(w: LTWorld, c: Dictionary) -> void:
	var cid: int = int(c["id"])
	var h: Dictionary = w.hh(int(c["household"]))
	var spouse: Dictionary = w.cit(int(c.get("spouse_before_death", -1)))
	for k in c["rel"]:
		if str(c["rel"][k]["kind"]) == "spouse" and w.is_present(w.cit(int(k))):
			spouse = w.cit(int(k))
	var heirs: Array = []
	if w.is_present(spouse):
		heirs.append(spouse)
	else:
		for kid in c["children"]:
			var kc: Dictionary = w.cit(int(kid))
			if w.is_present(kc):
				heirs.append(kc)
	var report: Array = []
	var looked_rich: bool = w.cash(c) > LTMoney.dollars(20000.0) or not c["owns"].is_empty() or (str(h["tenure"]) == "own" and int(w.lot(int(h["lot"])).get("owner_id", -1)) == cid)
	var estate: String = "estate:%d" % cid
	w.ledger.pay(w.acct_p(c), estate, w.cash(c), "estate_opened")
	var assets_start: int = w.ledger.bal(estate)
	# 1. joint ownership passes to the spouse outside the estate: the house
	var house_lot: int = -1
	if int(h["lot"]) >= 0 and str(w.lot(int(h["lot"]))["owner_kind"]) == "sim" and int(w.lot(int(h["lot"]))["owner_id"]) == cid:
		house_lot = int(h["lot"])
	if house_lot >= 0:
		var l: Dictionary = w.lot(house_lot)
		var taker: Dictionary = {}
		if w.is_present(spouse):
			taker = spouse
		else:
			for hm in heirs:
				if int(hm["household"]) == int(h["id"]) and w.age_years(hm) >= 18:
					taker = hm
		if not taker.is_empty():
			l["owner_id"] = int(taker["id"])
			var mort: Dictionary = w.debt(int(h["mortgage"])) if int(h["mortgage"]) >= 0 else {}
			if is_active(mort):
				mort["debtor_id"] = int(taker["id"])
				w.debt_index_dirty = true
				mort["joint"].erase(int(taker["id"]))
				mort["status"] = "assumed" if int(mort["missed"]) == 0 else mort["status"]
				_dhist(w, mort, "%s took the house and assumed the mortgage. The debt travels with the house." % w.full_name(taker))
				report.append("the house and its %s mortgage went to %s" % [LTMoney.fmt(int(mort["balance"])), taker["first_name"]])
				w.log_sim(taker, "Took over the house and assumed its mortgage of %s. The debt travels with the house, not the person." % LTMoney.fmt(int(mort["balance"])), true)
			else:
				report.append("the house went to %s free and clear" % taker["first_name"])
				w.log_sim(taker, "Inherited the house free and clear.", true)
		else:
			# nobody to take it: the estate sells it
			var sale: int = int(float(l["value"]) * 0.9)
			w.ledger.pay("outside", estate, sale, "house_sales")
			LTServices.spend(w, estate, "real_estate", int(float(sale) * 0.05), int(l["id"]))
			l["owner_kind"] = "outside"
			l["owner_id"] = -1
			l["unit_rent"] = LTMoney.dollars(1050.0)
			report.append("the house was sold for %s" % LTMoney.fmt(sale))
			if int(h["mortgage"]) >= 0:
				var md: Dictionary = w.debt(int(h["mortgage"]))
				if is_active(md):
					var mp: int = w.ledger.pay(estate, "bank", int(md["balance"]), "estate_secured")
					md["balance"] = int(md["balance"]) - mp
					md["status"] = "paid" if int(md["balance"]) <= 0 else md["status"]
					_dhist(w, md, "Paid %s from the house sale in the estate." % LTMoney.fmt(mp))
	# 2. funeral and administration
	var funeral: int = LTServices.spend(w, estate, "funeral", FUNERAL_COST, int(h["lot"]))
	funeral += LTServices.spend(w, estate, "legal", ESTATE_ADMIN, int(h["lot"]))
	if funeral < FUNERAL_COST + ESTATE_ADMIN:
		var rest: int = FUNERAL_COST + ESTATE_ADMIN - funeral
		var covered: bool = false
		for by in heirs:
			if w.age_years(by) < 18:
				continue
			# family paying for the funeral is a choice, scored like any other
			var duty: float = float(by["traits"]["kindness"]) * 0.5 + float(by["needs"]["family"]) * 0.3 + 20.0
			var spare: int = w.cash(by) - LTMoney.dollars(800.0)
			if duty > 45.0 and spare > 0:
				var p: int = w.ledger.pay(w.acct_p(by), "outside", mini(rest, spare), "funeral_admin")
				w.log_sim(by, "Chose to pay %s toward %s's funeral because the estate could not cover it. Reason: duty and love, not law." % [LTMoney.fmt(p), c["first_name"]], true)
				covered = true
				break
		if not covered:
			report.append("the funeral home took a %s loss" % LTMoney.fmt(rest))
	# 3. business shares carry their debts with them
	for bid in c["owns"].duplicate():
		var b: Dictionary = w.biz(int(bid))
		if b.is_empty() or str(b["status"]) != "open":
			continue
		var heir: Dictionary = {}
		for hc in heirs:
			if w.age_years(hc) >= 18:
				heir = hc
				break
		if not heir.is_empty() and LTEconomy.heir_keeps_business(w, heir, b):
			LTEconomy.transfer_business(w, b, c, heir)
			report.append("%s passed to %s with its debts" % [b["name"], heir["first_name"]])
		else:
			LTEconomy.close_business(w, b, "the owner died and no heir took it on")
			if str(b["legal_form"]) == "sole":
				w.ledger.pay(w.acct_b(b), estate, w.biz_cash(b), "estate_business_assets")
			report.append("%s closed" % b["name"])
	c["owns"] = []
	# 4. taxes, then secured, then unsecured
	var exp: Array = personal_exposure(w, c)
	var order: Array = []
	for d in exp:
		if str(d["type"]) == "tax":
			order.append(d)
	for d in exp:
		if str(d["secured_by"]) != "" and str(d["type"]) != "tax":
			order.append(d)
	for d in exp:
		if str(d["secured_by"]) == "" and str(d["type"]) != "tax":
			order.append(d)
	var paid_total: int = 0
	var unpaid_total: int = 0
	var written: Array = []
	for d in order:
		if not is_active(d) or str(d["status"]) == "assumed":
			continue
		if str(d["debtor_kind"]) == "b":
			continue
		# co-signed or joint debt becomes the survivor's full responsibility
		var survivor: Dictionary = {}
		for j in d["joint"]:
			if int(j) != cid and w.is_present(w.cit(int(j))):
				survivor = w.cit(int(j))
		if int(d["debtor_id"]) != cid and str(d["debtor_kind"]) == "p":
			if w.is_present(w.cit(int(d["debtor_id"]))):
				d["joint"].erase(cid)
				w.debt_index_dirty = true
				continue
		if not survivor.is_empty():
			d["debtor_id"] = int(survivor["id"])
			w.debt_index_dirty = true
			d["joint"].erase(int(survivor["id"]))
			d["joint"].erase(cid)
			w.debt_index_dirty = true
			_dhist(w, d, "%s, a joint borrower, is now fully responsible." % w.full_name(survivor))
			w.log_sim(survivor, "As joint borrower, now fully responsible for the %s of %s." % [str(d["type"]).replace("_", " "), LTMoney.fmt(int(d["balance"]))], true)
			continue
		if str(d["secured_by"]) == "vehicle":
			_repossess(w, d, [])
			if not is_active(d):
				continue
		var pay: int = w.ledger.pay(estate, creditor_acct(w, d), int(d["balance"]), "estate_debt_payments")
		paid_total += pay
		d["balance"] = int(d["balance"]) - pay
		if int(d["balance"]) <= 0:
			d["status"] = "paid"
			d["balance"] = 0
			_dhist(w, d, "Paid in full by the estate.")
		else:
			var loss: int = int(d["balance"])
			unpaid_total += loss
			d["status"] = "written_off_estate"
			d["loss"] = loss
			d["balance"] = 0
			_dhist(w, d, "The estate ran out. %s went unpaid and the creditor took the loss. Heirs do not owe it." % LTMoney.fmt(loss))
			_book_loss(w, d, loss)
			written.append(d)
	# 5. heirs get what is left
	var left: int = w.ledger.bal(estate)
	var to_heirs: int = 0
	if left > 0:
		if heirs.is_empty():
			w.ledger.pay(estate, "outside", left, "estate_to_outside_heirs")
			report.append("%s went to relatives outside town" % LTMoney.fmt(left))
		else:
			var share: int = left / heirs.size()
			for i in heirs.size():
				var amt: int = share if i < heirs.size() - 1 else w.ledger.bal(estate)
				w.ledger.pay(estate, w.acct_p(heirs[i]), amt, "inheritance")
				w.log_sim(heirs[i], "Received %s from the estate of %s after debts were paid." % [LTMoney.fmt(amt), w.full_name(c)], true)
			to_heirs = left
	# 6. a heir may choose to pay a dead relative's bills out of duty: a scored decision
	for d in written:
		for hc in heirs:
			if w.age_years(hc) < 18:
				continue
			var duty: float = float(hc["traits"]["kindness"]) * 0.4 + float(hc["traits"]["honesty"]) * 0.3 + (15.0 if str(d["creditor"]) == "business" or str(d["creditor"]) == "person" else 0.0)
			var can: int = w.cash(hc) - LTMoney.dollars(3000.0)
			if duty > 50.0 and can > 0:
				var vol: int = mini(int(d["loss"]), can / 3)
				if vol > LTMoney.dollars(50.0):
					w.ledger.pay(w.acct_p(hc), creditor_acct(w, d), vol, "voluntary_estate_payments")
					_dhist(w, d, "%s paid %s voluntarily, though the law did not require it." % [w.full_name(hc), LTMoney.fmt(vol)])
					w.log_sim(hc, "Paid %s of %s's unpaid bill to %s. Not legally owed. Reason: duty and kindness." % [LTMoney.fmt(vol), c["first_name"], creditor_name(w, d)], true)
				break
	w.counters["estates"] = int(w.counters["estates"]) + 1
	var summary: String = "Estate settled. Cash and assets in: %s. Paid to creditors: %s. Unpaid debt that died with the estate: %s. To heirs: %s." % [LTMoney.fmt(assets_start), LTMoney.fmt(paid_total), LTMoney.fmt(unpaid_total), LTMoney.fmt(to_heirs)]
	if not report.is_empty():
		summary += " Also: " + ", ".join(report) + "."
	w.log_sim(c, summary, true)
	c["estate"] = {"day": w.day, "paid": paid_total, "unpaid": unpaid_total, "to_heirs": to_heirs, "assets": assets_start, "notes": report}
	if looked_rich and unpaid_total > LTMoney.dollars(5000.0):
		w.chronicle_add("%s looked comfortable, but died owing %s more than the estate could pay. The family was shocked. Heirs do not owe it, the creditors took the loss." % [w.full_name(c), LTMoney.fmt(unpaid_total)], "estate", true, [c["id"]])
	else:
		w.chronicle_add("The estate of %s was settled: %s paid to creditors, %s unpaid, %s to heirs." % [w.full_name(c), LTMoney.fmt(paid_total), LTMoney.fmt(unpaid_total), LTMoney.fmt(to_heirs)], "estate", w.involves_watched([c["id"]]), [c["id"]])
	w.ledger.balances.erase(estate)


# ================================================================ city borrowing

static func city_credit_rating(w: LTWorld) -> String:
	var debt_service: int = 0
	for d in debts_of(w, "city", 0):
		debt_service += int(d["payment"])
	var income: int = maxi(1, int(w.city["income_12m"]) / 12)
	var ratio: float = float(debt_service) / float(income)
	var late: bool = false
	for d in debts_of(w, "city", 0):
		if str(d["status"]) != "current":
			late = true
	if late:
		return "C"
	if ratio < 0.1 and w.ledger.bal("city") > LTMoney.dollars(50000.0):
		return "A"
	if ratio < 0.25:
		return "B"
	return "C"


static func city_borrow(w: LTWorld, amount: int, purpose: String) -> Dictionary:
	if amount <= 0:
		return {"ok": false, "message": "Amount must be positive."}
	var rating: String = city_credit_rating(w)
	if rating == "C":
		return {"ok": false, "message": "%s will not lend. The city's credit standing is C (debt service too high or payments late)." % BANK_NAME}
	var rate: float = 0.045 + (0.0 if rating == "A" else 0.015) + float(w.bank["tightness"]) * 0.02
	var d: Dictionary = new_debt(w, "city", 0, "bank", -1, "city_loan", amount, rate, 180, "", -1, [])
	w.ledger.pay("bank", "city", amount, "city_borrowing")
	w.chronicle_add("The city borrowed %s from %s at %.1f%% over 15 years for %s. Payments are %s a month." % [LTMoney.fmt(amount), BANK_NAME, rate * 100.0, purpose, LTMoney.fmt(int(d["payment"]))], "city", true, [])
	return {"ok": true, "message": "Borrowed %s at %.1f%%. Monthly payment %s for 15 years." % [LTMoney.fmt(amount), rate * 100.0, LTMoney.fmt(int(d["payment"]))]}
