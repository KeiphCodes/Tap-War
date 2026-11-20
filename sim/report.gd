class_name LTReport
extends RefCounted
## Plain text summaries a reviewer can sanity check.


static func year_summary(w: LTWorld, start: Dictionary) -> String:
	var s: Dictionary = w.snapshot()
	var c: Dictionary = w.counters
	var lines: Array = []
	lines.append("LIVING TOWN RUN SUMMARY")
	lines.append("Town: %s. Seed %d. Day %d (%s)." % [w.city["name"], w.seed_value, w.day, LTCalendar.text(w.day)])
	lines.append("")
	lines.append("PEOPLE")
	lines.append("  Population: %d at start, %d now." % [int(start.get("population", 0)), s["population"]])
	lines.append("  Births %d, deaths %d, moved in %d, moved out %d, marriages %d." % [c["births"], c["deaths"], c["moved_in"], c["moved_out"], c["marriages"]])
	lines.append("  Working age adults %d, employed %d, unemployment %d%%, local jobs %d (was %d)." % [s["adults"], s["employed"], int(float(s["unemployment"]) * 100.0), s["local_jobs"], int(start.get("local_jobs", 0))])
	lines.append("  Hires %d, layoffs %d, quits %d. Homeless now: %d. Evictions: %d." % [c["hires"], c["layoffs"], c["quits"], s["homeless"], c["evictions"]])
	lines.append("  Average happiness %.1f, approval of the city %.1f." % [s["happiness"], s["approval"]])
	lines.append("")
	lines.append("BUSINESSES")
	lines.append("  Opened %d, closed %d, open now %d. Founding attempts that could not raise money: %d. Times a Sim looked and said no: %d." % [c["businesses_opened"], c["businesses_closed"], s["businesses_open"], c["founding_attempts"] - c["businesses_opened"], c["founding_failed"]])
	for b in w.businesses:
		if str(b["type"]) == "landlord" or str(b["status"]) == "never_opened":
			continue
		var owner: Dictionary = w.cit(int(b["owners"][0]))
		var line: String = "  - %s (%s, %s), opened day %d by %s." % [b["name"], b["type"], b["legal_form"], b["opened_day"], w.full_name(owner)]
		if str(b["status"]) == "closed":
			line += " Closed day %d: %s." % [b["closed_day"], b["close_reason"]]
		else:
			line += " Open, %d staff, cash %s, reputation %d." % [b["staff"].size(), LTMoney.fmt(w.biz_cash(b)), int(b["reputation"])]
		lines.append(line)
		lines.append("      Start reason: %s" % b["start_reason"])
	lines.append("")
	lines.append("DEBT AND CREDIT")
	var active: int = 0
	var bal: int = 0
	var by_status: Dictionary = {}
	for d in w.debts:
		by_status[str(d["status"])] = int(by_status.get(str(d["status"]), 0)) + 1
		if LTFinance.is_active(d):
			active += 1
			bal += int(d["balance"])
	lines.append("  Debt records: %d total, %d active, %s owed now." % [w.debts.size(), active, LTMoney.fmt(bal)])
	var parts: Array = []
	for k in by_status:
		parts.append("%s %d" % [LTFinance.status_text(str(k)), by_status[k]])
	lines.append("  By status: %s." % ", ".join(parts))
	lines.append("  Loans made %d, denied %d. Paid off %d. Charged off %d. Repossessions %d. Foreclosures %d." % [c["loans_made"], c["loans_denied"], c["debts_paid_off"], c["debts_charged_off"], c["repossessions"], c["foreclosures"]])
	lines.append("  Bankruptcies %d (liquidation %d, repayment plan %d). Estates settled %d." % [c["bankruptcies"], c["bankruptcies_ch7"], c["bankruptcies_ch13"], c["estates"]])
	lines.append("  %s: lending tightness %.2f, losses in the last year about %s." % [LTFinance.BANK_NAME, float(w.bank["tightness"]), LTMoney.fmt(int(w.bank["losses_12m"]))])
	lines.append("")
	lines.append("CITY")
	lines.append("  City cash %s (was %s). Income last 12 months %s, spending %s. Credit standing %s." % [LTMoney.fmt(w.ledger.bal("city")), LTMoney.fmt(int(start.get("city_cash", 0))), LTMoney.fmt(int(w.city["income_12m"])), LTMoney.fmt(int(w.city["spend_12m"])), LTFinance.city_credit_rating(w)])
	lines.append("  Petitions %d. Projects finished %d. Protests %d. Thefts %d." % [c["petitions"], c["projects_done"], w.city["protests"], c["thefts"]])
	for p in w.petitions:
		lines.append("  - Petition \"%s\": %d signers, status %s." % [p["title"], p["signers"].size(), p["status"]])
	for p in w.projects:
		lines.append("  - Project \"%s\": %s%s." % [p["title"], p["status"], ", quality %d" % int(float(p["quality"]) * 100.0) if str(p["status"]) == "done" else ""])
	lines.append("")
	lines.append("MONEY CHECK")
	var a: Dictionary = w.ledger.audit()
	lines.append("  Ledger: %s. Sum of all accounts %d cents (must be 0). Accounts below zero that should not be: %d. Transfers: %d." % ["balanced" if bool(a["ok"]) else "NOT BALANCED", a["sum"], a["negatives"].size(), a["transfers"]])
	var net_out: int = w.ledger.bal("outside") - int(w.city.get("outside_at_start", 0))
	lines.append("  Across the town line this run: %s %s town (imports, commutes, rent to outside owners against outside wages, pensions, exports)." % [LTMoney.fmt(absi(net_out)), "more left" if net_out > 0 else "more came into"])
	return "\n".join(lines)


static func sim_story(w: LTWorld, c: Dictionary, max_lines: int = 40) -> String:
	var out: Array = ["%s, %s %s, %d. %s." % [w.full_name(c), LTPeople.life_stage(w, c).to_lower(), LTPeople.archetype(c), w.age_years(c), "alive" if bool(c["alive"]) else "died"]]
	var h: Array = c["history"]
	var start: int = maxi(0, h.size() - max_lines)
	for i in range(start, h.size()):
		out.append("  Day %d: %s" % [h[i]["day"], h[i]["text"]])
	return "\n".join(out)


static func debt_trail(w: LTWorld, d: Dictionary) -> String:
	var out: Array = ["Debt #%d: %s owed by %s to %s. Status: %s." % [d["id"], str(d["type"]).replace("_", " "), LTFinance.debtor_name(w, d), LTFinance.creditor_name(w, d), LTFinance.status_text(str(d["status"]))]]
	for e in d["history"]:
		out.append("  Day %d: %s" % [e["day"], e["text"]])
	return "\n".join(out)
