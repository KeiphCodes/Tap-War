class_name LTLoans
extends RefCounted
## Loans built like real ones. A loan officer puts several products in front of the
## borrower (a 30 year fixed, a 15 year fixed, a 5/1 adjustable, a balloon, points
## to buy down the rate), each with its payment, APR, fees at closing and total
## interest. The borrower picks the one that fits their budget and their nature,
## and the reason is written down. Over the years the loan behaves like a real
## one: adjustable rates reset to the market within caps, interest only periods
## end, balloons come due and are refinanced, mortgage insurance drops off at 78%
## of the home's value, careful owners pay extra principal, and people refinance
## when market rates fall far enough.
##
## A loan's terms live in debt["terms"]; the offers it was chosen from in
## debt["offers"], with debt["choice"] saying why.

const GRACE_DAYS: int = 15
const ARM_MARGIN: float = 0.0275
const ARM_CAP_FIRST: float = 0.02
const ARM_CAP_LATER: float = 0.02
const ARM_CAP_LIFE: float = 0.05


# ---------------------------------------------------------------- the market

## The bank's cost of money (like the one year Treasury), wandering month to month.
static func index_rate(w: LTWorld) -> float:
	if not w.bank.has("index"):
		w.bank["index"] = 0.042
		w.bank["index_hist"] = []
	return float(w.bank["index"])


static func market_month(w: LTWorld) -> void:
	var r: float = index_rate(w)
	# slow drift with a pull back toward about 4%; recessions push it down
	var pull: float = (0.04 - r) * 0.05
	var shock: float = w.rng.randfn(0.0, 0.0012)
	if str(w.region.get("phase", "")) == "recession":
		shock -= 0.0008
	w.bank["index"] = clampf(r + pull + shock, 0.005, 0.09)
	w.bank["index_hist"].append(float(w.bank["index"]))
	if w.bank["index_hist"].size() > 240:
		w.bank["index_hist"].remove_at(0)


# ---------------------------------------------------------------- the arithmetic

static func payment(principal: int, rate: float, months: int) -> int:
	return LTFinance.amortized_payment(principal, rate, months)


## The APR: the rate at which the payments repay the money actually received
## (the loan less fees paid to the lender), solved by bisection.
static func apr(principal: int, fees: int, pay: int, months: int) -> float:
	var net: float = float(principal - fees)
	if net <= 0.0 or months <= 0 or pay <= 0:
		return 0.0
	var lo: float = 0.0
	var hi: float = 1.0
	for i in 60:
		var mid: float = (lo + hi) * 0.5
		var r: float = mid / 12.0
		var pv: float = float(pay) * months if r <= 0.0 else float(pay) * (1.0 - pow(1.0 + r, -months)) / r
		if pv > net:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


## Interest over the life of an offer, with its interest only months and balloon.
static func total_interest(principal: int, o: Dictionary) -> int:
	var bal: float = float(principal)
	var r: float = float(o["rate"]) / 12.0
	var paid_int: float = 0.0
	var months: int = int(o["term"])
	var io: int = int(o.get("io_months", 0))
	var pay: float = float(o["pi"])
	for m in months:
		var it: float = bal * r
		paid_int += it
		if m < io:
			continue
		bal = maxf(0.0, bal - (pay - it))
		if bal <= 0.0:
			break
	return int(paid_int)


## Closing costs, line by line, in cents.
static func closing_costs(kind: String, principal: int, points: float) -> Array:
	var lines: Array = []
	match kind:
		"mortgage":
			lines.append(["Origination fee (1%)", maxi(LTMoney.dollars(500.0), int(float(principal) * 0.01))])
			lines.append(["Appraisal", LTMoney.dollars(550.0)])
			lines.append(["Title insurance and search", LTMoney.dollars(900.0)])
			lines.append(["Credit report", LTMoney.dollars(50.0)])
			lines.append(["Recording fees", LTMoney.dollars(120.0)])
		"business":
			lines.append(["Loan packaging fee (1.5%)", int(float(principal) * 0.015)])
			lines.append(["Business valuation and appraisal", LTMoney.dollars(2500.0)])
			lines.append(["Lender's legal fees", LTMoney.dollars(1200.0)])
		"commercial":
			lines.append(["Origination fee (1%)", int(float(principal) * 0.01)])
			lines.append(["Commercial appraisal", LTMoney.dollars(3500.0)])
			lines.append(["Environmental review", LTMoney.dollars(1800.0)])
			lines.append(["Title and recording", LTMoney.dollars(1500.0)])
		"personal":
			lines.append(["Origination fee (3%)", int(float(principal) * 0.03)])
		"equity":
			lines.append(["Appraisal", LTMoney.dollars(450.0)])
			lines.append(["Recording fees", LTMoney.dollars(120.0)])
	if points > 0.0:
		lines.append(["Discount points (%.0f)" % points, int(float(principal) * points / 100.0)])
	return lines


static func _sum(lines: Array) -> int:
	var t: int = 0
	for ln in lines:
		t += int(ln[1])
	return t


## One offer, priced out: payment, APR, fees, total interest.
static func price(kind: String, name: String, principal: int, rate: float, term: int, extra: Dictionary = {}) -> Dictionary:
	var io: int = int(extra.get("io_months", 0))
	var amort: int = int(extra.get("amort", term))
	var points: float = float(extra.get("points", 0.0))
	var pi: int = payment(principal, rate, maxi(1, amort - io))
	var ins_rate: float = float(extra.get("insurance", 0.0))
	var ins: int = int(float(principal) * ins_rate / 12.0)
	var fees: Array = closing_costs(kind, principal, points)
	var o: Dictionary = {"name": name, "kind": kind, "rate": rate, "term": term, "amort": amort, "io_months": io,
		"rate_type": str(extra.get("rate_type", "fixed")), "fixed_months": int(extra.get("fixed_months", 0)),
		"points": points, "pi": pi, "insurance": ins_rate, "ins_month": ins, "payment": pi + ins,
		"io_payment": int(float(principal) * rate / 12.0) if io > 0 else 0, "fees": fees, "fee_total": _sum(fees),
		"prepay_penalty": str(extra.get("prepay_penalty", "none")), "balloon": term < amort, "note": str(extra.get("note", ""))}
	o["apr"] = apr(principal, int(o["fee_total"]), pi + ins, term if term >= amort else amort)
	o["total_interest"] = total_interest(principal, o)
	if term < amort:
		# what is still owed when the balloon comes due
		var bal: float = float(principal)
		var r: float = rate / 12.0
		for m in term:
			bal -= float(pi) - bal * r
		o["balloon_amount"] = int(maxf(0.0, bal))
	return o


# ---------------------------------------------------------------- what the bank offers

## Mortgage products under the program the buyer qualified for (from
## LTFinance.mortgage_offer): the usual 30 and 15 year fixed loans, a 5/1 ARM on
## conventional loans, and a version that buys the rate down with a point.
static func mortgage_offers(w: LTWorld, base: Dictionary, income: int, max_dti: float, dues: int) -> Array:
	var loan: int = int(base["loan"])
	var r: float = float(base["rate"])
	var ins: float = float(base.get("insurance", 0.0))
	var prog: String = str(base["program"])
	var out: Array = []
	out.append(price("mortgage", "30-year fixed", loan, r, 360, {"insurance": ins}))
	if prog != "USDA":
		out.append(price("mortgage", "15-year fixed", loan, r - 0.006, 180, {"insurance": ins}))
	if prog == "conventional":
		out.append(price("mortgage", "5/1 adjustable (ARM)", loan, maxf(0.02, r - 0.0075), 360, {"insurance": ins, "rate_type": "arm", "fixed_months": 60, "note": "fixed 5 years, then resets yearly to the market rate plus 2.75%, at most 2% a year and 5% over the loan"}))
	out.append(price("mortgage", "30-year fixed, 1 point paid", loan, r - 0.0025, 360, {"insurance": ins, "points": 1.0}))
	# only what the buyer's income can carry
	var ok: Array = []
	for o in out:
		if float(int(o["payment"]) + dues) <= float(income) * max_dti:
			ok.append(o)
	return ok


## Business products for a qualified founder: a fully amortizing term loan, and a
## five year balloon on 20 year amortization that keeps payments low.
static func business_offers(w: LTWorld, amount: int, rate: float, years: int, sba: bool) -> Array:
	var out: Array = []
	out.append(price("business", "%d-year term loan" % years, amount, rate, years * 12, {"prepay_penalty": "3-2-1" if not sba else "none"}))
	if not sba:
		out.append(price("business", "5-year balloon, 20-year amortization", amount, rate + 0.0025, 60, {"amort": 240, "prepay_penalty": "3-2-1", "note": "low payments; the rest comes due in five years and is usually refinanced"}))
		out.append(price("business", "%d-year term, first year interest only" % years, amount, rate + 0.005, years * 12, {"io_months": 12, "prepay_penalty": "3-2-1", "note": "only interest the first year while the business gets going"}))
	return out


## Personal loans: shorter terms cost less in all, longer ones pay less a month.
static func personal_offers(w: LTWorld, amount: int, rate: float) -> Array:
	return [price("personal", "24-month personal loan", amount, rate - 0.01, 24),
		price("personal", "36-month personal loan", amount, rate, 36),
		price("personal", "60-month personal loan", amount, rate + 0.015, 60)]


# ---------------------------------------------------------------- how a Sim chooses

## The borrower's pick and their reason. ctx: income (monthly), cash, years they
## expect to keep the loan.
static func choose(c: Dictionary, offers: Array, ctx: Dictionary) -> Dictionary:
	if offers.is_empty():
		return {}
	var t: Dictionary = c.get("traits", {})
	var judg: float = (float(t.get("intelligence", 50.0)) * 0.5 + float(c.get("skills", {}).get("finance", 30.0)) * 0.5) / 100.0
	var risk: float = float(t.get("risk", 50.0)) / 100.0
	var disc: float = float(t.get("discipline", 50.0)) / 100.0
	var income: float = maxf(1.0, float(ctx.get("income", 1)))
	var cash: float = float(ctx.get("cash", 0))
	var stay: float = float(ctx.get("years", 10.0))
	var best: Dictionary = {}
	var best_s: float = -1e18
	for o in offers:
		var pay_share: float = float(o["payment"]) / income
		var horizon: int = mini(int(o["term"]), int(stay * 12.0))
		var cost_horizon: float = float(o["fee_total"]) + float(o["payment"]) * float(horizon)
		var s: float = -pay_share * (2.0 + (1.0 - disc) * 2.0) * 100.0
		s -= cost_horizon / income * (0.4 + judg * 0.8)
		if str(o["rate_type"]) == "arm":
			s += (risk - 0.5) * 30.0 + (8.0 if stay < 6.0 else -8.0)
		if bool(o["balloon"]):
			# the whole rest comes due in a few years: the sharper the borrower, the
			# more that risk weighs against the low payment
			s += (risk - 0.4) * 20.0 - 10.0 - judg * 25.0
		if int(o["io_months"]) > 0:
			s += (risk - 0.5) * 15.0 - disc * 6.0
		if float(o["points"]) > 0.0 and cash < float(o["fee_total"]) * 3.0:
			s -= 20.0
		if s > best_s:
			best_s = s
			best = o
	var why: String = _reason(best, offers, ctx, disc, risk, judg)
	return {"offer": best, "why": why}


static func _reason(o: Dictionary, offers: Array, ctx: Dictionary, disc: float, risk: float, judg: float) -> String:
	var lowest_pay: bool = true
	var lowest_cost: bool = true
	for x in offers:
		if int(x["payment"]) < int(o["payment"]):
			lowest_pay = false
		if int(x["total_interest"]) + int(x["fee_total"]) < int(o["total_interest"]) + int(o["fee_total"]):
			lowest_cost = false
	if str(o["rate_type"]) == "arm":
		return "took the adjustable rate for the lower start, betting on moving or rates staying put"
	if bool(o["balloon"]):
		return "took the balloon for the low payment, planning to refinance when it comes due"
	if int(o["io_months"]) > 0:
		return "took interest only for the first year to keep cash in the business while it gets going"
	if float(o["points"]) > 0.0:
		return "paid a point up front for a lower rate, planning to keep the loan for years"
	if lowest_cost and not lowest_pay:
		return "chose the shorter loan: a bigger payment, but far less interest in all"
	if lowest_pay:
		return "chose the lowest monthly payment to keep the budget safe"
	return "chose the steady middle: a fixed payment they can count on"


# ---------------------------------------------------------------- booking it

## Opens the chosen offer as a debt and files the terms, the offers and the reason.
static func book(w: LTWorld, debtor_kind: String, debtor_id: int, dtype: String, principal: int, o: Dictionary, secured_by: String, collateral_lot: int, offers: Array, why: String) -> Dictionary:
	var d: Dictionary = LTFinance.new_debt(w, debtor_kind, debtor_id, "bank", -1, dtype, principal, float(o["rate"]), int(o["amort"]), secured_by, collateral_lot, [])
	d["payment"] = int(o["pi"])
	var terms: Dictionary = o.duplicate(true)
	terms["start_rate"] = float(o["rate"])
	terms["months_paid"] = 0
	terms["balloon_month"] = int(o["term"]) if bool(o["balloon"]) else 0
	terms["home_value"] = int(w.lot(collateral_lot)["value"]) if collateral_lot >= 0 and secured_by == "house" else 0
	d["terms"] = terms
	var summary: Array = []
	for x in offers:
		summary.append({"name": x["name"], "rate": x["rate"], "apr": x["apr"], "payment": x["payment"], "fee_total": x["fee_total"], "total_interest": x["total_interest"], "chosen": x["name"] == o["name"]})
	d["offers"] = summary
	d["choice"] = why
	LTFinance._dhist(w, d, "%s at %.2f%% (APR %.2f%%). Closing costs %s. %s." % [o["name"], float(o["rate"]) * 100.0, float(o["apr"]) * 100.0, LTMoney.fmt(int(o["fee_total"])), why.substr(0, 1).to_upper() + why.substr(1)])
	return d


## Gives a loan made the plain way its full written terms, so it reads and behaves
## like the real product it is.
static func attach(w: LTWorld, d: Dictionary, name: String, kind: String, extra: Dictionary = {}) -> void:
	var o: Dictionary = price(kind, name, int(d["original"]), float(d["rate"]), int(d["term"]), extra)
	var terms: Dictionary = o.duplicate(true)
	terms["start_rate"] = float(d["rate"])
	terms["months_paid"] = 0
	terms["balloon_month"] = 0
	terms["home_value"] = int(w.lot(int(d["collateral_lot"]))["value"]) if int(d["collateral_lot"]) >= 0 and str(d["secured_by"]) == "house" else 0
	d["terms"] = terms
	d["payment"] = int(o["pi"])


## Pays the closing costs out of the borrower's account (lender fees to the bank,
## third party fees to the outside world).
static func pay_closing(w: LTWorld, from_acct: String, o: Dictionary) -> int:
	var paid: int = 0
	for ln in o["fees"]:
		var to: String = "bank" if str(ln[0]).begins_with("Origination") or str(ln[0]).begins_with("Discount") or str(ln[0]).begins_with("Loan packaging") else "outside"
		paid += w.ledger.pay(from_acct, to, int(ln[1]), "closing_costs")
	return paid


# ---------------------------------------------------------------- living with a loan

## Called by the payment cycle each month before the payment is due: interest only
## months, resets, balloons and insurance. Returns the amount due this month.
static func due_this_month(w: LTWorld, d: Dictionary) -> int:
	var t: Dictionary = d.get("terms", {})
	if t.is_empty():
		return -1
	var n: int = int(t["months_paid"])
	t["months_paid"] = n + 1
	var bal: int = int(d["balance"])
	# an adjustable rate resets to the market, within its caps
	if str(t["rate_type"]) == "arm" and n >= int(t["fixed_months"]) and (n - int(t["fixed_months"])) % 12 == 0:
		var cap: float = ARM_CAP_FIRST if n == int(t["fixed_months"]) else ARM_CAP_LATER
		var target: float = index_rate(w) + ARM_MARGIN
		var old: float = float(d["rate"])
		var nr: float = clampf(target, maxf(old - cap, float(t["start_rate"]) - ARM_CAP_LIFE), minf(old + cap, float(t["start_rate"]) + ARM_CAP_LIFE))
		if absf(nr - old) > 0.0001:
			d["rate"] = nr
			var left: int = maxi(1, int(t["amort"]) - n)
			d["payment"] = payment(bal, nr, left)
			LTFinance._dhist(w, d, "The adjustable rate reset from %.2f%% to %.2f%% (market %.2f%% plus the %.2f%% margin, within its caps). New payment %s." % [old * 100.0, nr * 100.0, index_rate(w) * 100.0, ARM_MARGIN * 100.0, LTMoney.fmt(int(d["payment"]))])
			for c in LTFinance._score_people(w, d):
				w.log_sim(c, "The adjustable rate on the %s %s to %.2f%%. The payment is now %s." % [str(d["type"]).replace("_", " "), "went up" if nr > old else "came down", nr * 100.0, LTMoney.fmt(int(d["payment"]))], true)
	# interest only months
	if n < int(t["io_months"]):
		return int(float(bal) * float(d["rate"]) / 12.0)
	if n == int(t["io_months"]) and int(t["io_months"]) > 0:
		d["payment"] = payment(bal, float(d["rate"]), maxi(1, int(t["amort"]) - n))
		LTFinance._dhist(w, d, "The interest only year is over. Payments now repay principal too: %s a month." % LTMoney.fmt(int(d["payment"])))
	# the balloon comes due
	if int(t["balloon_month"]) > 0 and n + 1 == int(t["balloon_month"]):
		return -2
	return mini(int(d["payment"]), bal + int(float(bal) * float(d["rate"]) / 12.0))


## Mortgage insurance on top of the payment, until the loan is paid down to 78%
## of what the home was worth (FHA insurance stays for the life of the loan).
static func insurance_due(w: LTWorld, d: Dictionary) -> int:
	var t: Dictionary = d.get("terms", {})
	if t.is_empty() or float(t.get("insurance", 0.0)) <= 0.0:
		return 0
	var hv: int = int(t.get("home_value", 0))
	var fha: bool = float(t["insurance"]) >= 0.0055
	if not fha and hv > 0 and float(d["balance"]) <= float(hv) * 0.78:
		t["insurance"] = 0.0
		LTFinance._dhist(w, d, "The loan is down to 78% of the home's value: mortgage insurance dropped off.")
		for c in LTFinance._score_people(w, d):
			w.log_sim(c, "The mortgage insurance came off the house payment. %s a month saved." % LTMoney.fmt(int(t.get("ins_month", 0))), true)
		return 0
	return int(t.get("ins_month", 0))


## A balloon comes due: the bank refinances a loan that has been paid on time and
## whose borrower still qualifies; otherwise the full amount is owed now.
static func balloon_due(w: LTWorld, d: Dictionary) -> bool:
	var t: Dictionary = d["terms"]
	var bal: int = int(d["balance"])
	var good: bool = str(d["status"]) == "current"
	if str(d["debtor_kind"]) == "b":
		var b: Dictionary = w.biz(int(d["debtor_id"]))
		good = good and not b.is_empty() and str(b["status"]) == "open" and int(b.get("loss_months", 0)) < 3
	if good:
		var nr: float = LTFinance.bank_rate(w, "business_loan", 700) + (index_rate(w) - 0.042)
		var o: Dictionary = price("business", "Refinance of the balloon, 15-year term", bal, nr, 180)
		var nd: Dictionary = book(w, str(d["debtor_kind"]), int(d["debtor_id"]), str(d["type"]), bal, o, str(d["secured_by"]), int(d["collateral_lot"]), [o], "refinanced the balloon at the going rate")
		nd["guarantor"] = int(d["guarantor"])
		w.debt_index_dirty = true
		d["balance"] = 0
		d["status"] = "paid"
		LTFinance._dhist(w, d, "The balloon of %s came due and was refinanced into a new 15-year loan at %.2f%%." % [LTMoney.fmt(bal), nr * 100.0])
		return true
	LTFinance._dhist(w, d, "The balloon of %s came due. The bank would not refinance: the whole amount is owed now." % LTMoney.fmt(bal))
	d["payment"] = bal
	t["balloon_month"] = 0
	return false


## Once a month: extra principal from careful owners, and refinancing when market
## rates have fallen well below a loan's rate.
static func monthly(w: LTWorld) -> void:
	for d in w.debts:
		if not LTFinance.is_active(d) or str(d["debtor_kind"]) != "p" or not d.has("terms") or str(d["status"]) != "current":
			continue
		var c: Dictionary = w.cit(int(d["debtor_id"]))
		if not w.is_present(c):
			continue
		var t: Dictionary = d["terms"]
		var h: Dictionary = w.hh(int(c["household"]))
		var cushion: int = LTPeople.monthly_bills(w, h) * 6
		# extra principal: the disciplined with money sense and cash to spare
		var tr: Dictionary = c["traits"]
		if float(tr["discipline"]) + float(c["skills"]["finance"]) > 110.0 and w.cash(c) > cushion + LTMoney.dollars(2000.0) and str(t.get("prepay_penalty", "none")) == "none":
			var extra: int = mini(int(d["balance"]), mini(w.cash(c) - cushion, int(d["payment"])))
			if extra > LTMoney.dollars(100.0):
				var got: int = w.ledger.pay(w.acct_p(c), LTFinance.creditor_acct(w, d), extra, "extra_principal")
				d["balance"] = int(d["balance"]) - got
				d["paid_total"] = int(d["paid_total"]) + got
				t["extra_paid"] = int(t.get("extra_paid", 0)) + got
				if int(t.get("extra_paid", 0)) == got:
					w.log_sim(c, "Started paying extra on the %s, %s this month. Reason: every extra dollar saves interest for years." % [str(d["type"]).replace("_", " "), LTMoney.fmt(got)], true)
				if int(d["balance"]) <= 0:
					d["balance"] = 0
					d["status"] = "paid"
					LTFinance._dhist(w, d, "Paid off early with extra payments.")
		# refinancing a mortgage when rates have fallen a full point
		if str(d["type"]) == "mortgage" and int(t["months_paid"]) >= 12 and float(d["rate"]) - (LTFinance.bank_rate(w, "mortgage", int(c["credit"]["score"])) + (index_rate(w) - 0.042)) >= 0.01:
			var nr: float = LTFinance.bank_rate(w, "mortgage", int(c["credit"]["score"])) + (index_rate(w) - 0.042)
			var left: int = maxi(60, int(t["amort"]) - int(t["months_paid"]))
			var bal: int = int(d["balance"])
			var o: Dictionary = price("mortgage", "Refinance, %d-year fixed" % int(round(float(left) / 12.0)), bal, nr, left)
			var saves: int = int(d["payment"]) - int(o["pi"])
			if saves <= 0 or float(o["fee_total"]) / float(maxi(1, saves)) > 48.0 or w.cash(c) < int(o["fee_total"]):
				continue
			pay_closing(w, w.acct_p(c), o)
			var nd: Dictionary = book(w, "p", int(c["id"]), "mortgage", bal, o, "house", int(d["collateral_lot"]), [o], "refinanced when rates fell: %s a month less, the closing costs paid back in %d months" % [LTMoney.fmt(saves), int(float(o["fee_total"]) / float(saves)) + 1])
			nd["terms"]["home_value"] = int(t.get("home_value", 0))
			LTFinance.fund_loan(w, nd, LTFinance.creditor_acct(w, d), bal)
			if int(h.get("mortgage", -1)) == int(d["id"]):
				h["mortgage"] = int(nd["id"])
			d["balance"] = 0
			d["status"] = "paid"
			LTFinance._dhist(w, d, "Paid off by a refinance at %.2f%%." % (nr * 100.0))
			w.log_sim(c, "Refinanced the mortgage from %.2f%% to %.2f%%. Saves %s a month." % [float(d["rate"]) * 100.0, nr * 100.0, LTMoney.fmt(saves)], true)
			w.counters["refinances"] = int(w.counters.get("refinances", 0)) + 1


# ---------------------------------------------------------------- for the loan page

## The balance month by month as scheduled from the start, and the principal and
## interest paid in each year: [balances, [[year, principal, interest], ...]].
static func schedule(d: Dictionary) -> Array:
	var t: Dictionary = d.get("terms", {})
	var bal: float = float(d["original"])
	var rate: float = float(t.get("start_rate", d["rate"]))
	var months: int = int(t.get("term", d["term"])) if not bool(t.get("balloon", false)) else int(t["term"])
	var amort: int = int(t.get("amort", d["term"]))
	var io: int = int(t.get("io_months", 0))
	var pay: float = float(t.get("pi", d["payment"]))
	var bals: Array = [int(bal)]
	var years: Array = []
	var yp: float = 0.0
	var yi: float = 0.0
	for m in maxi(1, months):
		var it: float = bal * rate / 12.0
		var pr: float = 0.0 if m < io else minf(bal, pay - it)
		bal -= pr
		yp += pr
		yi += it
		bals.append(int(bal))
		if (m + 1) % 12 == 0 or m == months - 1:
			years.append(["Year %d" % ((m / 12) + 1), int(yp), int(yi)])
			yp = 0.0
			yi = 0.0
		if bal <= 0.5:
			break
	return [bals, years, amort]
