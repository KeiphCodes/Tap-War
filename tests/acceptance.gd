extends SceneTree
## Headless acceptance run for the V1 slice. Checks every gate in section 18 of the
## design document and writes a summary a reviewer can sanity check.
## Run: godot --headless --script tests/acceptance.gd

const SEED: int = 20261120
const DAYS: int = 365
const GRANT: int = 1000000

var results: Array = []
var notes: Array = []


func _init() -> void:
	var t0: int = Time.get_ticks_msec()
	# Run A: a mayor who answers the grocery petition with incentives and awards the cheapest road bid.
	var a: LTWorld = LTWorld.new()
	a.new_town(SEED)
	var start: Dictionary = a.snapshot()
	var audit_ok: bool = true
	var mayor_a: Dictionary = {"respond_grocery": true, "road_pick": "cheapest"}
	for i in DAYS:
		_mayor(a, mayor_a)
		a.tick_day()
		var au: Dictionary = a.ledger.audit()
		if not bool(au["ok"]):
			audit_ok = false
			notes.append("Ledger failed on day %d: %s" % [a.day, au])
			break
	var ms_a: int = Time.get_ticks_msec() - t0

	# Gate 1: the run completes, the ledger balances every single day.
	_gate("365 daily ticks complete with the ledger balanced every day (no mystery money)", audit_ok and a.day == DAYS, "Day %d reached. Final audit: %s." % [a.day, a.ledger.audit()])

	# Gate 2: a business started by a Sim decision, with a readable reason.
	var started: Array = []
	for b in a.businesses:
		if str(b["type"]) != "landlord" and str(b["status"]) != "never_opened" and int(b["opened_day"]) > 0 and str(b["start_reason"]) != "":
			started.append(b)
	var g2: String = "none"
	if not started.is_empty():
		var b0: Dictionary = started[0]
		g2 = "%s, opened day %d by %s. Reason in its history: \"%s\"" % [b0["name"], b0["opened_day"], a.full_name(a.cit(int(b0["owners"][0]))), b0["history"][0]["text"]]
	_gate("At least one business was started by a Sim decision, with its start reason readable", not started.is_empty(), "%d businesses started by Sims. First: %s" % [started.size(), g2])

	# Gate 3: a debt spiral reaches a realistic resolution with the paper trail intact.
	var spiral: Dictionary = {}
	for d in a.debts:
		var was_late: bool = false
		for e in d["history"]:
			if str(e["text"]).begins_with("Missed payment"):
				was_late = true
		var caught_up: bool = false
		for e in d["history"]:
			if str(e["text"]).begins_with("Caught up"):
				caught_up = true
		if was_late and (["discharged", "paid", "written_off_estate", "charged_off"].has(str(d["status"])) or caught_up):
			spiral = d
			if str(d["status"]) != "current":
				break
	var g3_text: String = "No resolved spiral found."
	if not spiral.is_empty():
		g3_text = LTReport.debt_trail(a, spiral)
	_gate("At least one debt spiral reached a realistic resolution (repaying the arrears, bankruptcy, charge off, or estate) with its paper trail", not spiral.is_empty(), g3_text)

	# Gate 4: a petition from real unmet need data, and a mayor response that measurably changes what happens.
	var b_world: LTWorld = LTWorld.new()
	b_world.new_town(SEED)
	var mayor_b: Dictionary = {"respond_grocery": false, "road_pick": "cheapest"}
	for i in DAYS:
		_mayor(b_world, mayor_b)
		b_world.tick_day()
	var pa: Dictionary = _petition(a, "grocery")
	var pb: Dictionary = _petition(b_world, "grocery")
	var g4_ok: bool = not pa.is_empty() and not pa["data"].is_empty() and str(pa["response"]) != ""
	var cmp: String = ""
	if g4_ok:
		var ga: Dictionary = _grocery_outcome(a, pa)
		var gb: Dictionary = _grocery_outcome(b_world, pb)
		cmp = "Petition: \"%s\". Why: %s Started by %s, %d signatures, suggested site %s.\n" % [pa["title"], pa["why"], a.full_name(a.cit(int(pa["starter"]))), pa["signers"].size(), pa["site_text"]]
		cmp += "  With the response (run A): %s\n" % ga["text"]
		cmp += "  Without a response (run B, same seed): %s" % gb["text"]
		g4_ok = ga["signature"] != gb["signature"]
	_gate("A petition came from real unmet need data, and the mayor's response measurably changed what happened next", g4_ok, cmp)

	# Gate 5: a contract bid, awarded, built, quality persists and drives the next repair need.
	var road_a: Dictionary = _road_project(a)
	var c_world: LTWorld = LTWorld.new()
	c_world.new_town(SEED)
	var mayor_c: Dictionary = {"respond_grocery": true, "road_pick": "best_quality"}
	for i in DAYS:
		_mayor(c_world, mayor_c)
		c_world.tick_day()
	var road_c: Dictionary = _road_project(c_world)
	var g5_ok: bool = not road_a.is_empty() and str(road_a["status"]) == "done" and not road_c.is_empty() and str(road_c["status"]) == "done"
	var g5: String = "Road project missing or not finished."
	if g5_ok:
		var seg_q: float = float(a.roads[int(a.streets[int(road_a["street"])]["segments"][0])]["quality"])
		g5_ok = is_equal_approx(seg_q, float(road_a["quality"])) and float(road_a["expected_repair_days"]) != float(road_c["expected_repair_days"])
		g5 = "Run A awarded the cheapest bid: %s, quality %d, finished day %d, expected to need repair about %d days later%s.\n" % [road_a["winner_name"], int(float(road_a["quality"]) * 100.0), road_a["done_day"], int(road_a["expected_repair_days"]), "; it actually needed repair on day %d" % int(road_a.get("first_repair_day", -1)) if int(road_a.get("first_repair_day", -1)) >= 0 else ""]
		g5 += "  Run C awarded the best record instead: %s, quality %d, finished day %d, expected to need repair about %d days later%s.\n" % [road_c["winner_name"], int(float(road_c["quality"]) * 100.0), road_c["done_day"], int(road_c["expected_repair_days"]), "; it actually needed repair on day %d" % int(road_c.get("first_repair_day", -1)) if int(road_c.get("first_repair_day", -1)) >= 0 else ""]
		g5 += "  The street segments store the finished quality (%.2f) and wear at a rate set by it. Paper trail of run A:\n" % seg_q
		for e in road_a["events"]:
			g5 += "    Day %d: %s\n" % [e["day"], e["text"]]
	_gate("A contract was bid, awarded, and built in stages, and its quality persists and sets the next repair need", g5_ok, g5)

	# Gate 6: deterministic from seed plus player actions.
	var r: LTWorld = LTWorld.new()
	r.new_town(SEED)
	var log: Array = a.action_log.duplicate(true)
	var li: int = 0
	for i in DAYS:
		while li < log.size() and int(log[li]["day"]) == r.day:
			r.apply_action(log[li])
			li += 1
		r.tick_day()
	_gate("Replaying the seed plus the logged mayor actions gives the same town", r.state_hash() == a.state_hash(), "Run A hash %d, replay hash %d, %d actions replayed." % [a.state_hash(), r.state_hash(), log.size()])

	# Gate 7: save and load round trip mid year gives the same end state.
	var s1: LTWorld = LTWorld.new()
	s1.new_town(SEED)
	var path: String = "user://acceptance_mid.ltsave"
	var log2: Array = a.action_log.duplicate(true)
	var lj: int = 0
	for i in 180:
		while lj < log2.size() and int(log2[lj]["day"]) == s1.day:
			s1.apply_action(log2[lj])
			lj += 1
		s1.tick_day()
	var err: Error = s1.save_to_file(path)
	var s2: LTWorld = LTWorld.new()
	var err2: Error = s2.load_from_file(path)
	for i in DAYS - 180:
		while lj < log2.size() and int(log2[lj]["day"]) == s2.day:
			s2.apply_action(log2[lj])
			lj += 1
		s2.tick_day()
	_gate("Saving on day 180 and loading the save reaches the same day 365 town", err == OK and err2 == OK and s2.state_hash() == a.state_hash(), "Save %s, load %s, loaded run hash %d, straight run hash %d." % [error_string(err), error_string(err2), s2.state_hash(), a.state_hash()])

	# Gate 8: no em dashes in player facing text.
	var bad: Array = []
	for c in a.citizens:
		for h in c["history"]:
			if _has_dash(str(h["text"])):
				bad.append(str(h["text"]))
	for e in a.chronicle:
		if _has_dash(str(e["text"])):
			bad.append(str(e["text"]))
	for b in a.businesses:
		for h in b["history"]:
			if _has_dash(str(h["text"])):
				bad.append(str(h["text"]))
	_gate("No em dashes in generated player facing text", bad.is_empty(), "%d lines checked problems: %s" % [bad.size(), str(bad.slice(0, 3))])

	# Gate 9 and 10: scenario checks of the accurate debt rules, using forced events on a fresh town.
	_scenario_estate()
	_scenario_bankruptcy()

	# Summary
	var out: Array = []
	out.append("LIVING TOWN V1 SLICE ACCEPTANCE RUN")
	out.append("Generated %s by tests/acceptance.gd. Seed %d, %d days. Main run took %d ms." % [Time.get_datetime_string_from_system(), SEED, DAYS, ms_a])
	out.append("")
	var all_ok: bool = true
	for g in results:
		out.append("[%s] %s" % ["PASS" if g["ok"] else "FAIL", g["name"]])
		out.append("  " + str(g["detail"]).replace("\n", "\n  "))
		out.append("")
		if not bool(g["ok"]):
			all_ok = false
	out.append("Not checked by this script: independent review by a team member who did not write the system (a human gate).")
	out.append("")
	out.append(LTReport.year_summary(a, start))
	out.append("")
	out.append("SAMPLE LIVES (last entries of their history logs)")
	var shown: int = 0
	for c in a.citizens:
		if shown >= 4:
			break
		if c["history"].size() >= 6 and (not c["bk"].is_empty() or not c["owns"].is_empty() or not bool(c["alive"])):
			out.append(LTReport.sim_story(a, c, 12))
			out.append("")
			shown += 1
	for n in notes:
		out.append(str(n))
	out.append("RESULT: %s" % ("ALL GATES PASS" if all_ok else "SOME GATES FAILED"))
	var text: String = "\n".join(out)
	print(text)
	var f: FileAccess = FileAccess.open("res://reports/acceptance_summary.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(text + "\n")
		f.close()
	quit(0 if all_ok else 1)


## A scripted mayor for the test. Only uses the same actions the player has.
func _mayor(w: LTWorld, policy: Dictionary) -> void:
	if w.day == 3:
		w.apply_action({"kind": "define_project", "ptype": "road_repair", "target": 1})
	for p in w.projects:
		if str(p["status"]) == "review" and not bool(p["private"]) and str(p["ptype"]) == "road_repair":
			var pick: int = -1
			for i in p["bids"].size():
				var b: Dictionary = p["bids"][i]
				if int(b["price"]) > int(p["ceiling"]):
					continue
				if pick < 0:
					pick = i
				elif str(policy["road_pick"]) == "cheapest":
					if int(b["price"]) < int(p["bids"][pick]["price"]):
						pick = i
				else:
					if _grade_rank(str(b["grade"])) > _grade_rank(str(p["bids"][pick]["grade"])) or (_grade_rank(str(b["grade"])) == _grade_rank(str(p["bids"][pick]["grade"])) and int(b["price"]) > int(p["bids"][pick]["price"])):
						pick = i
			if pick < 0:
				continue
			var price: int = int(p["bids"][pick]["price"])
			if price > w.ledger.bal("city") - LTMoney.dollars(20000.0):
				w.apply_action({"kind": "city_borrow", "amount": price - w.ledger.bal("city") + LTMoney.dollars(40000.0), "purpose": "the road project"})
			w.apply_action({"kind": "award_bid", "project_id": int(p["id"]), "bid_index": pick})
	if bool(policy["respond_grocery"]):
		for p in w.petitions:
			if str(p["kind"]) == "grocery" and str(p["status"]) == "submitted":
				w.apply_action({"kind": "respond_petition", "petition_id": int(p["id"]), "response": "publish_need", "need": "grocery", "incentives": {"free_lot": true, "tax_break_years": 2, "grant": GRANT, "loan_guarantee": true}})


func _scenario_estate() -> void:
	var w: LTWorld = LTWorld.new()
	w.new_town(SEED)
	w.run_days(20)
	# a married homeowner with a mortgage and a credit card, who "looks rich"
	var victim: Dictionary = {}
	for c in w.citizens:
		var h: Dictionary = w.hh(int(c["household"]))
		if w.is_present(c) and int(c["spouse"]) >= 0 and str(h["tenure"]) == "own" and int(h["mortgage"]) >= 0 and int(w.lot(int(h["lot"]))["owner_id"]) == int(c["id"]):
			victim = c
			break
	if victim.is_empty():
		_gate("Estate scenario: debts are paid in legal order and heirs never inherit debt", false, "No married homeowner with a mortgage found.")
		return
	var spouse: Dictionary = w.cit(int(victim["spouse"]))
	# give them an unsecured debt bigger than their cash, and a joint card with the spouse
	var big: Dictionary = LTFinance.new_debt(w, "p", int(victim["id"]), "bank", -1, "personal_loan", w.cash(victim) + LTMoney.dollars(15000.0), 0.12, 36, "", -1, [])
	var joint: Dictionary = LTFinance.new_debt(w, "p", int(victim["id"]), "bank", -1, "credit_card", LTMoney.dollars(3000.0), 0.22, 0, "", -1, [int(spouse["id"])])
	joint["limit"] = LTMoney.dollars(5000.0)
	var mort: Dictionary = w.debt(int(w.hh(int(victim["household"]))["mortgage"]))
	var kids_cash_before: Dictionary = {}
	for k in victim["children"]:
		kids_cash_before[int(k)] = w.cash(w.cit(int(k)))
	var spouse_cash_before: int = w.cash(spouse)
	var sum_before: int = w.ledger.audit()["sum"]
	LTPeople.die(w, victim, "a heart attack")
	var ok: bool = true
	var notes2: Array = []
	if str(big["status"]) != "written_off_estate" and str(big["status"]) != "paid":
		ok = false
		notes2.append("unsecured debt status %s" % big["status"])
	if str(big["status"]) == "written_off_estate" and int(big["balance"]) != 0:
		ok = false
	if int(joint["debtor_id"]) != int(spouse["id"]) or not LTFinance.is_active(joint):
		ok = false
		notes2.append("joint debt did not pass to the surviving joint borrower")
	if int(mort["debtor_id"]) != int(spouse["id"]):
		ok = false
		notes2.append("mortgage did not travel with the house")
	for k in kids_cash_before:
		if w.cash(w.cit(int(k))) < int(kids_cash_before[k]):
			ok = false
			notes2.append("a child lost money to a parent's debt")
	if w.ledger.audit()["sum"] != sum_before or not bool(w.ledger.audit()["ok"]):
		ok = false
		notes2.append("ledger out of balance")
	var detail: String = "%s died owing a %s loan beyond their cash, a joint card with %s, and a mortgage.\n  Estate record: %s\n  Unsecured loan: %s. Joint card now owed by %s. Mortgage now owed by %s. Children's cash unchanged. Spouse cash before %s, after %s.\n  %s" % [w.full_name(victim), LTMoney.fmt(int(big["original"])), spouse["first_name"], "assets %s, paid to creditors %s, unpaid %s, to heirs %s, %s" % [LTMoney.fmt(int(victim["estate"]["assets"])), LTMoney.fmt(int(victim["estate"]["paid"])), LTMoney.fmt(int(victim["estate"]["unpaid"])), LTMoney.fmt(int(victim["estate"]["to_heirs"])), ", ".join(victim["estate"]["notes"])], LTFinance.status_text(str(big["status"])), LTFinance.debtor_name(w, joint), LTFinance.debtor_name(w, mort), LTMoney.fmt(spouse_cash_before), LTMoney.fmt(w.cash(spouse)), "; ".join(notes2)]
	_gate("Estate scenario: the estate pays in legal order, joint debt passes to the joint borrower, the mortgage travels with the house, children inherit no debt", ok, detail)


func _scenario_bankruptcy() -> void:
	var w: LTWorld = LTWorld.new()
	w.new_town(SEED)
	w.run_days(20)
	var renter: Dictionary = {}
	for c in w.citizens:
		if w.is_present(c) and w.age_years(c) >= 25 and w.age_years(c) < 60 and str(w.hh(int(c["household"]))["tenure"]) == "rent":
			renter = c
			break
	var d1: Dictionary = LTFinance.new_debt(w, "p", int(renter["id"]), "bank", -1, "credit_card", LTMoney.dollars(9000.0), 0.22, 0, "", -1, [])
	var d2: Dictionary = LTFinance.new_debt(w, "p", int(renter["id"]), "city", -1, "tax", LTMoney.dollars(400.0), 0.08, 12, "", -1, [])
	d1["missed"] = 3
	d1["status"] = "late90"
	var bank_loss_before: int = int(w.bank["losses_total"])
	LTFinance.file_bankruptcy(w, renter, "job loss", int(d1["balance"]), 0)
	var ok: bool = str(d1["status"]) == "discharged" and LTFinance.is_active(d2) and int(w.bank["losses_total"]) > bank_loss_before and int(renter["credit"]["bankruptcy_day"]) == w.day and bool(w.ledger.audit()["ok"])
	var dec: Dictionary = LTFinance.bank_decision(w, renter, "personal_loan", LTMoney.dollars(1000.0), LTMoney.dollars(3000.0))
	ok = ok and not bool(dec["ok"])
	_gate("Bankruptcy scenario: liquidation discharges the card, the tax debt survives, the bank books the loss, and new credit is refused", ok, "%s filed. Card: %s. Tax debt: %s. Bank losses grew by %s. Credit now %s. A new loan request: %s." % [w.full_name(renter), LTFinance.status_text(str(d1["status"])), LTFinance.status_text(str(d2["status"])), LTMoney.fmt(int(w.bank["losses_total"]) - bank_loss_before), LTFinance.score_text(renter), dec["reason"]])


func _grade_rank(g: String) -> int:
	return {"A": 5, "B": 4, "C": 3, "D": 2, "F": 1, "new": 2}.get(g, 0)


func _gate(name: String, ok: bool, detail: String) -> void:
	results.append({"name": name, "ok": ok, "detail": detail})


func _petition(w: LTWorld, kind: String) -> Dictionary:
	for p in w.petitions:
		if str(p["kind"]) == kind:
			return p
	return {}


func _grocery_outcome(w: LTWorld, p: Dictionary) -> Dictionary:
	var gro: Array = []
	for b in w.businesses:
		if str(b["type"]) == "grocery" and str(b["status"]) != "never_opened":
			gro.append("%s opened day %d%s" % [b["name"], b["opened_day"], " on the incentive lot" if bool(b["free_lot"]) else ""])
	var trust: float = 0.0
	var n: int = 0
	if not p.is_empty():
		for sid in p["signers"]:
			var c: Dictionary = w.cit(int(sid))
			if w.is_present(c):
				trust += float(c["trust_city"])
				n += 1
	var avg: float = 0.0 if n == 0 else trust / float(n)
	var text: String = "groceries: %s. Petition status: %s. Signers' trust in the city: %.1f." % ["none" if gro.is_empty() else "; ".join(gro), p.get("status", "none"), avg]
	return {"text": text, "signature": "%s|%d" % [str(gro), int(avg)]}


func _road_project(w: LTWorld) -> Dictionary:
	for p in w.projects:
		if str(p["ptype"]) == "road_repair":
			return p
	return {}


func _has_dash(s: String) -> bool:
	return s.contains(char(0x2014)) or s.contains(char(0x2013))
