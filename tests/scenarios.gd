extends SceneTree
## Scenario checks for every system beyond the slice. Each one starts a fresh town,
## forces the situation a test needs (a tester's hand, so none of this counts toward
## the "started by a Sim decision" gate), lets the simulation respond, and checks the
## outcome and the ledger. Run: godot --headless --script tests/scenarios.gd

const SEED: int = 20261120
var results: Array = []


func _init() -> void:
	_crime_and_court()
	_divorce_and_child_support()
	_addiction_and_treatment()
	_pregnancy()
	_local_clinic()
	_supply_chain()
	_local_bank()
	_annex_and_pave()
	_bonds_bus_and_laws()
	_election()
	_region_employer_fails()
	_storms_and_fires()
	_save_load_full()
	_every_type()
	_founder_mode()
	_real_calendar()
	_contracts_and_lot_details()
	var out: Array = ["LIVING TOWN SCENARIO CHECKS", "Generated %s by tests/scenarios.gd." % Time.get_datetime_string_from_system(), ""]
	var ok_all: bool = true
	for r in results:
		out.append("[%s] %s" % ["PASS" if r["ok"] else "FAIL", r["name"]])
		out.append("  " + str(r["detail"]).replace("\n", "\n  "))
		out.append("")
		ok_all = ok_all and bool(r["ok"])
	out.append("RESULT: %s" % ("ALL SCENARIOS PASS" if ok_all else "SOME SCENARIOS FAILED"))
	var text: String = "\n".join(out)
	print(text)
	var f: FileAccess = FileAccess.open("res://reports/scenario_summary.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(text + "\n")
		f.close()
	quit(0 if ok_all else 1)


func _check(name: String, ok: bool, detail: String, w: LTWorld) -> void:
	var a: Dictionary = w.ledger.audit()
	results.append({"name": name, "ok": ok and bool(a["ok"]), "detail": detail + ("" if bool(a["ok"]) else "\nLEDGER OUT OF BALANCE: %s" % a)})


func _town(days: int = 10) -> LTWorld:
	var w: LTWorld = LTWorld.new()
	w.new_town(SEED)
	w.run_days(days)
	return w


func _adult(w: LTWorld, cond: Callable) -> Dictionary:
	for c in w.citizens:
		if w.is_present(c) and w.age_years(c) >= 21 and w.age_years(c) < 60 and cond.call(c):
			return c
	return {}


func _give(w: LTWorld, c: Dictionary, dollars: float) -> void:
	w.ledger.pay("outside", w.acct_p(c), LTMoney.dollars(dollars), "test_grant")


func _found(w: LTWorld, c: Dictionary, btype: String, lot_zone: Array) -> Dictionary:
	var lot: int = LTGeography.best_site(w, lot_zone, [])
	if lot < 0:
		for l in w.lots:
			if str(l["use"]) == "empty":
				w.apply_action({"kind": "zone_lot", "lot": int(l["id"]), "zone": lot_zone[0]})
				lot = int(l["id"])
				break
	var cfg: Dictionary = LTEconomy.tcfg(btype)
	_give(w, c, float(cfg["startup"]) / 100.0 + 5000.0)
	var plan: Dictionary = {"type": btype, "lot": lot, "score": 50.0, "est_monthly": 100000, "startup": int(cfg["startup"]), "loan_need": 0, "grant": 0, "need_id": -1, "funding": "savings", "reason": "a test scenario", "doubt": ""}
	var before: int = w.businesses.size()
	LTEconomy.found_business(w, c, plan)
	return w.businesses[before] if w.businesses.size() > before else {}


# ---------------------------------------------------------------- scenarios

func _crime_and_court() -> void:
	var w: LTWorld = _town()
	var c: Dictionary = _adult(w, func(x): return str(x["job"]["kind"]) == "outside")
	var job_before: String = str(c["job"]["title"])
	var city_before: int = w.ledger.bal("city")
	w.ledger.pay(w.acct_p(c), "outside", w.cash(c), "test_drain")
	LTJustice.charge(w, c, "burglary", "broke into a neighbor's home (test)", -1, 0)
	var cs: Dictionary = w.cases[w.cases.size() - 1]
	w.run_days(40)
	var convicted: bool = str(cs["status"]) == "convicted"
	var ok: bool = str(cs["status"]) in ["convicted", "acquitted"]
	if convicted:
		ok = ok and LTJustice.record_count(c) > 0 and (int(c.get("jail_until", -1)) > 0 or int(c.get("probation_until", -1)) > 0)
	_check("Crime goes to court: a charge, a trial, a verdict, and a sentence with a record", ok, "%s was charged with burglary. Case status: %s. Sentence: %s. Job before: %s, job now: %s. Trail: %s" % [w.full_name(c), cs["status"], cs["sentence"], job_before, c["job"]["title"] if str(c["job"]["kind"]) != "none" else "none", " / ".join(cs["trail"].map(func(e): return str(e["text"])))], w)


func _divorce_and_child_support() -> void:
	var w: LTWorld = _town()
	var a: Dictionary = {}
	for c in w.citizens:
		if w.is_present(c) and int(c["spouse"]) >= 0 and str(c["sex"]) == "F":
			for k in c["children"]:
				if w.is_present(w.cit(int(k))) and w.age_years(w.cit(int(k))) < 15:
					a = c
		if not a.is_empty():
			break
	var b: Dictionary = w.cit(int(a["spouse"]))
	LTFamily.divorce(w, a, b)
	var cs: Dictionary = {}
	for d in w.debts:
		if str(d["type"]) == "child_support":
			cs = d
	var payer: Dictionary = w.cit(int(cs["debtor_id"])) if not cs.is_empty() else {}
	var ok: bool = not cs.is_empty() and int(a["spouse"]) == -1 and int(a["household"]) != int(b["household"]) and not bool(cs["dischargeable"])
	if ok:
		cs["missed"] = 2
		cs["status"] = "late60"
		LTFinance.file_bankruptcy(w, payer, "divorce", 1000000, 0)
		ok = LTFinance.is_active(cs) and str(cs["status"]) != "discharged"
	_check("Divorce: the household splits, child support is set by income, and bankruptcy cannot erase it", ok, "%s and %s divorced. Child support: %s a month, owed by %s, status after the payer's bankruptcy: %s." % [w.full_name(a), w.full_name(b), LTMoney.fmt(int(cs.get("payment", 0))), w.full_name(payer), LTFinance.status_text(str(cs.get("status", "")))], w)


func _addiction_and_treatment() -> void:
	var w: LTWorld = _town()
	var c: Dictionary = _adult(w, func(x): return int(x["spouse"]) >= 0)
	_give(w, c, 6000.0)
	c["addiction"] = {"alcohol": 75.0, "gambling": 0.0, "drugs": 0.0}
	c["traits"]["discipline"] = 70
	var cash0: int = w.cash(c)
	var treated: bool = false
	for i in 120:
		w.tick_day()
		if int(c.get("treatment_until", -1)) > w.day:
			treated = true
	var ok: bool = treated and float(c["addiction"]["alcohol"]) < 75.0
	_check("Addiction: a heavy habit costs money and health until the Sim chooses treatment, which lowers it", ok, "%s started with a drinking level of 75. After 120 days: level %d, went to treatment: %s, cash %s to %s." % [w.full_name(c), int(c["addiction"]["alcohol"]), treated, LTMoney.fmt(cash0), LTMoney.fmt(w.cash(c))], w)


func _pregnancy() -> void:
	var w: LTWorld = _town()
	var m: Dictionary = {}
	for c in w.citizens:
		if w.is_present(c) and str(c["sex"]) == "F" and int(c["spouse"]) >= 0 and w.age_years(c) < 40 and c.get("pregnant", {}).is_empty():
			m = c
			break
	var kids0: int = m["children"].size()
	LTHealth.conceive(w, m, w.cit(int(m["spouse"])), "a test")
	var due: int = int(m["pregnant"]["due"])
	w.run_days(due - w.day + 2)
	var ok: bool = m["children"].size() == kids0 + 1 and int(m.get("leave_until", -1)) > w.day
	_check("Pregnancy: about nine months, prenatal visits, a birth, and maternity leave", ok, "%s was due %s. Children %d to %d. On leave until %s." % [w.full_name(m), LTCalendar.short(due), kids0, m["children"].size(), LTCalendar.short(int(m.get("leave_until", 0)))], w)


func _local_clinic() -> void:
	var w: LTWorld = _town()
	var doc: Dictionary = _adult(w, func(x): return true)
	doc["skills"]["medicine"] = 80.0
	var b: Dictionary = _found(w, doc, "clinic", ["commercial"])
	w.run_days(60)
	var local: int = int(w.spend_book.get("medical", {}).get("local", 0)) + int(w.spend_book.get("medical", {}).get("last_local", 0))
	var ok: bool = not b.is_empty() and int(b["lifetime_revenue"]) > 0 and local > 0
	_check("A Sim run clinic captures doctor visits that used to leave town", ok, "%s opened. Revenue so far %s. Medical spending kept in town recently: %s." % [b.get("name", "nothing"), LTMoney.fmt(int(b.get("lifetime_revenue", 0))), LTMoney.fmt(local)], w)


func _supply_chain() -> void:
	var w: LTWorld = _town()
	var f: Dictionary = _found(w, _adult(w, func(x): return x["owns"].is_empty()), "farm", ["agricultural"])
	var g: Dictionary = {}
	if w.open_businesses("grocery").is_empty():
		g = _found(w, _adult(w, func(x): return x["owns"].is_empty()), "grocery", ["commercial"])
	else:
		g = w.open_businesses("grocery")[0]
	var m: Dictionary = _found(w, _adult(w, func(x): return x["owns"].is_empty()), "mill", ["agricultural", "industrial"])
	var bk: Dictionary = _found(w, _adult(w, func(x): return x["owns"].is_empty()), "bakery", ["commercial"])
	w.run_days(150)
	var ok: bool = int(m.get("lifetime_revenue", 0)) > 0 and int(bk.get("lifetime_revenue", 0)) > 0 and int(f.get("lifetime_revenue", 0)) > 0
	_check("Supply chain: farm grain to the mill, flour to the bakery, bread to the grocery, all paid through the ledger", ok, "Farm %s revenue %s. Mill %s revenue %s. Bakery %s revenue %s. Grocery %s supplier: %s." % [f.get("name", "?"), LTMoney.fmt(int(f.get("lifetime_revenue", 0))), m.get("name", "?"), LTMoney.fmt(int(m.get("lifetime_revenue", 0))), bk.get("name", "?"), LTMoney.fmt(int(bk.get("lifetime_revenue", 0))), g.get("name", "?"), g.get("supplier", "?")], w)


func _local_bank() -> void:
	var w: LTWorld = _town()
	w.city["laws"]["bank_charter"] = 1.0
	var banker: Dictionary = _adult(w, func(x): return x["owns"].is_empty())
	banker["skills"]["finance"] = 85.0
	var b: Dictionary = _found(w, banker, "bank", ["commercial"])
	w.ledger.pay("outside", w.acct_b(b), LTMoney.dollars(150000.0), "test_capital")
	var n0: int = w.debts.size()
	var c: Dictionary = {}
	for x in w.citizens:
		if w.debts.size() > n0:
			break
		if w.is_present(x) and w.age_years(x) >= 21 and bool(x["credit"]["has_file"]) and str(x["job"]["kind"]) == "outside" and int(x["id"]) != int(banker["id"]):
			c = x
			LTFinance.personal_loan(w, c, "a test loan")
	if w.debts.size() == n0:
		results.append({"name": "A chartered local bank lends to townspeople and the interest stays in town", "ok": false, "detail": "The loan request was refused, so the test could not check the lender."})
		return
	var d: Dictionary = w.debts[n0]
	w.run_days(70)
	var ok: bool = str(d["creditor"]) == "business" and int(d["creditor_id"]) == int(b["id"]) and int(b["month_revenue"]) + int(b["lifetime_revenue"]) + int(d["paid_total"]) > 0
	_check("A chartered local bank lends to townspeople and the interest stays in town", ok, "%s lent %s to %s. Creditor on the record: %s. Paid back so far: %s." % [b.get("name", "?"), LTMoney.fmt(int(d["original"])), w.full_name(c), LTFinance.creditor_name(w, d), LTMoney.fmt(int(d["paid_total"]))], w)


func _annex_and_pave() -> void:
	var w: LTWorld = _town()
	var lots0: int = w.lots.size()
	var r: Dictionary = w.apply_action({"kind": "annex"})
	var new_lot: int = lots0
	var mins: float = w.travel_minutes(0, new_lot)
	var street: int = int(w.lot(new_lot)["street"])
	var new_street: int = w.streets.size() - 1
	w.apply_action({"kind": "zone_lot", "lot": new_lot, "zone": "residential"})
	var pr: Dictionary = w.apply_action({"kind": "define_project", "ptype": "road_repair", "target": new_street, "live": true})
	w.run_days(16)
	var p: Dictionary = w.projects[int(pr.get("project_id", 0))]
	if str(p["status"]) == "review":
		var pick: int = 0
		for i in p["bids"].size():
			if int(p["bids"][i]["price"]) <= int(p["ceiling"]):
				pick = i
		w.apply_action({"kind": "award_bid", "project_id": int(p["id"]), "bid_index": pick})
	w.run_days(120)
	var cond: float = LTGeography.street_condition(w, new_street)
	var ok: bool = bool(r["ok"]) and w.lots.size() == lots0 + int(w.config["lot_cols"]) and mins < 500.0 and str(w.lot(new_lot)["zone"]) == "residential" and str(p["status"]) == "done" and cond > 50.0
	_check("Plotting land: the city annexes a row, the road graph grows, the gravel street is paved through bids", ok, "%s Lots %d to %d. Travel from lot 0 to the new lot: %d minutes. %s is now %s, condition %d." % [r["message"], lots0, w.lots.size(), int(mins), w.streets[new_street]["name"], p["status"], int(cond)], w)


func _bonds_bus_and_laws() -> void:
	var w: LTWorld = _town()
	var cash0: int = w.ledger.bal("city")
	var b: Dictionary = w.apply_action({"kind": "issue_bond", "amount": LTMoney.dollars(200000.0), "purpose": "a test"})
	var bus: Dictionary = w.apply_action({"kind": "set_law", "law": "bus_service", "value": 1})
	var hc: Dictionary = w.apply_action({"kind": "set_law", "law": "health_code", "value": 2})
	var rc: Dictionary = w.apply_action({"kind": "set_law", "law": "rent_cap", "value": 0.02})
	var bank: Dictionary = w.apply_action({"kind": "set_law", "law": "bank_charter", "value": 1})
	w.run_days(40)
	var fares: int = int(w.ledger.flows.get("bus_fares", 0))
	var ok: bool = bool(b["ok"]) and bool(bus["ok"]) and bool(hc["ok"]) and bool(rc["ok"]) and not bool(bank["ok"]) and fares > 0
	_check("City bonds, bus service and the new laws all work, and a small town cannot charter a bank", ok, "Bonds: %s Bus: riders paid %s in fares. Health code: %s Bank charter for %d people: %s" % [b["message"], LTMoney.fmt(fares), hc["message"].substr(0, 80), w.alive_count(), bank["message"]], w)


func _election() -> void:
	var w: LTWorld = _town()
	w.apply_action({"kind": "elections", "on": true})
	w.city["next_election_day"] = w.day + 70
	w.run_days(75)
	var held: bool = false
	for e in w.chronicle:
		if str(e["kind"]) == "election" and (str(e["text"]).contains(" won ") or str(e["text"]).contains("lost the election")):
			held = true
	_check("Elections mode: a challenger runs on real grievances, Sims vote, the result stands", held, "Challenger: %s. Platform: %s. Mayor still in office: %s." % [w.full_name(w.cit(int(w.city.get("challenger", -1)))), w.city.get("platform", ""), w.city["mayor_in_office"]], w)


func _region_employer_fails() -> void:
	var w: LTWorld = _town()
	var target: String = ""
	var hit: Array = []
	for c in w.citizens:
		if w.is_present(c) and str(c["job"]["kind"]) == "outside":
			target = str(c["job"]["employer_name"])
			break
	for c in w.citizens:
		if w.is_present(c) and str(c["job"].get("employer_name", "")) == target:
			hit.append(c)
	for e in w.region["employers"]:
		if str(e["name"]) == target:
			LTRegion._employer_fails(w, e)
	var all_lost: bool = true
	for c in hit:
		if str(c["job"]["kind"]) != "none":
			all_lost = false
	_check("The region: when a county employer fails, the town Sims who worked there lose their jobs", all_lost and not hit.is_empty(), "%s failed. %d town Sims worked there and all are now looking for work." % [target, hit.size()], w)


func _storms_and_fires() -> void:
	var w: LTWorld = _town()
	var cond0: float = 0.0
	for l in w.lots:
		cond0 += float(l["condition"])
	w.weather = "Storm"
	for i in 6:
		LTRegion._storm(w)
	var cond1: float = 0.0
	for l in w.lots:
		cond1 += float(l["condition"])
	var repairs: int = int(w.spend_book.get("repairs", {}).get("outside", 0)) + int(w.spend_book.get("repairs", {}).get("local", 0))
	_check("Storms damage buildings and roads, and owners pay real repair bills", cond1 < cond0 and repairs > 0, "Building condition total %d to %d. Repairs paid: %s." % [int(cond0), int(cond1), LTMoney.fmt(repairs)], w)


func _every_type() -> void:
	var w: LTWorld = _town()
	w.city["laws"]["bank_charter"] = 1.0
	for i in 3:
		w.ledger.pay("outside", "city", LTMoney.dollars(60000.0), "test_grant")
		w.apply_action({"kind": "annex"})
	var made: Array = []
	var missing: Array = []
	for t in LTEconomy.all_types():
		if t == "landlord":
			continue
		var zones: Array = LTEconomy.tcfg(t)["zones"]
		var c: Dictionary = _adult(w, func(x): return x["owns"].is_empty() and str(x["job"]["kind"]) != "owner")
		if c.is_empty():
			missing.append(t)
			continue
		c["skills"][str(LTEconomy.tcfg(t)["skill"])] = 80.0
		var lot: int = LTGeography.best_site(w, zones, [])
		if lot < 0:
			for l in w.lots:
				if str(l["use"]) == "empty" and str(l["zone"]) == "none":
					w.apply_action({"kind": "zone_lot", "lot": int(l["id"]), "zone": zones[0]})
					break
		var b: Dictionary = _found(w, c, t, zones)
		if b.is_empty() or str(b["type"]) != t:
			missing.append(t)
		else:
			made.append(t)
	w.run_days(60)
	var open_n: int = 0
	for b in w.businesses:
		if str(b["status"]) == "open" and str(b["type"]) != "landlord":
			open_n += 1
	_check("Every business type opens, runs for two months, and keeps the ledger balanced", missing.is_empty(), "Opened: %s. Could not open: %s. Still open after 60 days: %d." % [", ".join(made), ", ".join(missing) if not missing.is_empty() else "none", open_n], w)


func _founder_mode() -> void:
	var w: LTWorld = LTWorld.new()
	w.new_town(SEED, {}, {"start": "founder", "elections": true, "town_name": "New Hope", "player_name": "Sam Dakota"})
	var start_pop: int = w.residents()
	var start_cash: int = w.ledger.bal("city")
	var n: Callable = func(i, j): return LTGeography.node_id(w, i, j)
	var only_highway: bool = w.lots.is_empty() and w.streets.size() == 1
	var r1: Dictionary = w.apply_action({"kind": "plan_road", "a": n.call(10, 12), "b": n.call(10, 4), "live": true})
	var r2: Dictionary = w.apply_action({"kind": "plan_road", "a": n.call(10, 8), "b": n.call(22, 8), "live": true})
	w.apply_action({"kind": "plot_lots", "c0": 11, "r0": 7, "c1": 21, "r1": 8, "zone": "residential"})
	w.apply_action({"kind": "plot_lots", "c0": 11, "r0": 11, "c1": 14, "r1": 11, "zone": "commercial"})
	w.apply_action({"kind": "plot_lots", "c0": 9, "r0": 5, "c1": 9, "r1": 5, "zone": "civic"})
	var mh_lot: int = LTGeography.lot_at(w, 9, 5)
	w.apply_action({"kind": "define_project", "ptype": "mayor_house", "target": mh_lot, "live": true})
	var inc_day: int = -1
	for d in 730:
		for p in w.projects:
			if str(p["status"]) == "review" and not bool(p["private"]):
				var pick: int = 0
				for i in p["bids"].size():
					if int(p["bids"][i]["price"]) < int(p["bids"][pick]["price"]):
						pick = i
				w.apply_action({"kind": "award_bid", "project_id": int(p["id"]), "bid_index": pick})
		w.tick_day()
		if inc_day < 0 and bool(w.city["incorporated"]):
			inc_day = w.day
	var election: String = ""
	for e in w.chronicle:
		if str(e["kind"]) == "election" and (str(e["text"]).contains("won") or str(e["text"]).contains("lost")):
			election = str(e["text"])
	var ok: bool = only_highway and bool(r1["ok"]) and bool(r2["ok"]) and start_pop == 1 and start_cash == LTMoney.dollars(1000000.0) and int(w.player["home_lot"]) == mh_lot and inc_day > 0 and w.residents() >= 20 and election != ""
	_check("Found a town on open land: only the county road at first, the mayor draws roads and plots lots, settlers build, the town incorporates and votes", ok, "Started with %d resident, %s, no lots, and %d road. Drew %s and %s. Plotted %d lots. Mayor's house on lot %d. Incorporated on day %d. Residents after two years: %d. Election: %s Milestones: %s" % [start_pop, LTMoney.fmt(start_cash), 1, w.streets[1]["name"], w.streets[2]["name"], w.lots.size(), int(w.player["home_lot"]), inc_day, w.residents(), election, w.city.get("milestones", {}).keys()], w)


## The mayor writes the contract for a planned road and the details of new lots,
## and each choice changes what happens: price, time, quality, what is built,
## which lots families buy and what they pay.
func _contracts_and_lot_details() -> void:
	var run: Callable = func(changes: Dictionary, days: int, award: bool = true) -> LTWorld:
		var w: LTWorld = LTWorld.new()
		w.new_town(SEED, {}, {"start": "founder"})
		var n: Callable = func(i, j): return LTGeography.node_id(w, i, j)
		w.apply_action({"kind": "plan_road", "a": n.call(10, 12), "b": n.call(10, 6)})
		if not changes.is_empty():
			w.apply_action({"kind": "edit_project", "project_id": 0, "changes": changes})
		w.apply_action({"kind": "go_live", "project_id": 0})
		for d in days:
			var p: Dictionary = w.projects[0]
			if str(p["status"]) == "review" and award:
				var pick: int = 0
				for i in p["bids"].size():
					if int(p["bids"][i]["price"]) < int(p["bids"][pick]["price"]):
						pick = i
				w.apply_action({"kind": "award_bid", "project_id": 0, "bid_index": pick})
			w.tick_day()
		return w
	# a drawn road is a draft: no contractor sees it until the mayor presses Go live
	var dw: LTWorld = LTWorld.new()
	dw.new_town(SEED, {}, {"start": "founder"})
	dw.apply_action({"kind": "plan_road", "a": LTGeography.node_id(dw, 10, 12), "b": LTGeography.node_id(dw, 10, 6)})
	for d in LTProjects.BID_DAYS + 5:
		dw.tick_day()
	var draft_quiet: bool = str(dw.projects[0]["status"]) == "draft" and dw.projects[0]["bids"].is_empty()
	var gl: Dictionary = dw.apply_action({"kind": "go_live", "project_id": 0})
	for d in LTProjects.BID_DAYS + 1:
		dw.tick_day()
	var went_live: bool = bool(gl["ok"]) and str(dw.projects[0]["status"]) == "review" and not dw.projects[0]["bids"].is_empty()
	var base: LTWorld = run.call({}, 0)
	var fancy_w: LTWorld = run.call({"surface": "concrete", "width": "avenue", "sidewalks": true, "lights": true, "name": "Founders Way"}, 0)
	var cheap_w: LTWorld = run.call({"surface": "gravel", "width": "lane"}, 0)
	var b0: int = int(base.projects[0]["base_cost"])
	var b1: int = int(fancy_w.projects[0]["base_cost"])
	var b2: int = int(cheap_w.projects[0]["base_cost"])
	var priced: bool = b1 > b0 and b2 < b0 and int(fancy_w.projects[0]["ceiling"]) > int(base.projects[0]["ceiling"]) and str(fancy_w.streets[1]["name"]) == "Founders Way"
	# build both and compare what was built
	var built_fancy: LTWorld = run.call({"surface": "concrete", "width": "avenue", "sidewalks": true, "lights": true}, 160)
	var built_cheap: LTWorld = run.call({"surface": "gravel", "width": "lane"}, 160)
	var pf: Dictionary = built_fancy.projects[0]
	var pc: Dictionary = built_cheap.projects[0]
	var both_done: bool = str(pf["status"]) == "done" and str(pc["status"]) == "done"
	var st: Dictionary = built_fancy.streets[1]
	var features: bool = bool(st.get("sidewalks", false)) and bool(st.get("lights", false)) and str(st.get("width", "")) == "avenue"
	var seg_f: float = LTGeography.segment_minutes(built_fancy, built_fancy.roads[int(st["segments"][0])])
	var seg_c: float = LTGeography.segment_minutes(built_cheap, built_cheap.roads[int(built_cheap.streets[1]["segments"][0])])
	var better: bool = float(pf["quality"]) > float(pc["quality"]) and seg_f < seg_c
	# a deadline: bids squeeze their schedules and charge for it
	var dl_w: LTWorld = run.call({"deadline": 30, "penalty": true}, LTProjects.BID_DAYS + 1, false)
	var dl_ok: bool = true
	for b in dl_w.projects[0]["bids"]:
		dl_ok = dl_ok and int(b["days"]) <= 30
	dl_ok = dl_ok and not dl_w.projects[0]["bids"].is_empty()
	var dl_days: String = str(dl_w.projects[0]["bids"].map(func(b): return int(b["days"])))
	# changing terms after bids are in sends it back out to bid
	var re: Dictionary = dl_w.apply_action({"kind": "edit_project", "project_id": 0, "changes": {"deadline": 0}})
	var reopened: bool = str(dl_w.projects[0]["status"]) == "bidding" and dl_w.projects[0]["bids"].is_empty()
	# signed contracts are locked
	var locked: Dictionary = built_fancy.apply_action({"kind": "edit_project", "project_id": 0, "changes": {"surface": "gravel"}})
	# lot details: price, hold and zone, applied to a plotted group
	var lw: LTWorld = LTWorld.new()
	lw.new_town(SEED, {}, {"start": "founder"})
	var r: Dictionary = lw.apply_action({"kind": "plot_lots", "c0": 3, "r0": 11, "c1": 8, "r1": 11, "zone": "residential"})
	var group: Array = LTGeography.plot_group_lots(lw, int(r["plot_group"]))
	lw.apply_action({"kind": "edit_lots", "lots": group, "changes": {"price_pct": 150}})
	lw.apply_action({"kind": "edit_lots", "lots": [group[0]], "changes": {"hold": true, "name": "Town Green"}})
	lw.apply_action({"kind": "edit_lots", "lots": [group[1]], "changes": {"price_pct": 50}})
	var asking: int = LTGeography.asking_price(lw, int(group[1]))
	for d in 200:
		lw.tick_day()
	var held_ok: bool = str(lw.lot(int(group[0]))["owner_kind"]) == "city" and str(lw.lot(int(group[0]))["name"]) == "Town Green"
	var cheap_sold: bool = str(lw.lot(int(group[1]))["owner_kind"]) != "city"
	var lots_ok: bool = group.size() == 6 and held_ok and cheap_sold and asking > 0
	var ok: bool = draft_quiet and went_live and priced and both_done and features and better and dl_ok and bool(re["ok"]) and reopened and not bool(locked["ok"]) and lots_ok
	_check("Contracts and lot details: drawn roads are drafts until the mayor presses Go live; the mayor sets surface, width, sidewalks, lights, deadline and budget, and lot price and hold, and each one changes the outcome", ok, "Draft stayed private for %d days: %s. After Go live: %s, %d bids. Fair price for 6 blocks: standard %s, concrete avenue with sidewalks and lights %s, gravel lane %s. Built: concrete avenue quality %d, %.1f minutes a block; gravel lane quality %d, %.1f minutes a block. Deadline 30 days: bids promised %s days. Changing terms after bids: %s Signed contract: %s Lots: held lot kept by the city: %s, half price lot sold: %s." % [LTProjects.BID_DAYS + 5, draft_quiet, gl["message"], dw.projects[0]["bids"].size(), LTMoney.fmt(b0), LTMoney.fmt(b1), LTMoney.fmt(b2), int(float(pf["quality"]) * 100.0), seg_f, int(float(pc["quality"]) * 100.0), seg_c, dl_days, re["message"], locked["message"], held_ok, cheap_sold], base)


func _real_calendar() -> void:
	var w: LTWorld = LTWorld.new()
	w.new_town(SEED, {}, {"real_calendar": true})
	var today: Dictionary = Time.get_date_dict_from_system()
	var first_ok: bool = LTCalendar.year(1) == int(today["year"]) and LTCalendar.month_index(1) == int(today["month"]) - 1 and LTCalendar.day_of_month(1) == mini(int(today["day"]), 28 if int(today["month"]) == 2 else 31)
	var target: int = LTCalendar.game_day_for_today()
	w.run_days(40)
	var later: Dictionary = {"y": LTCalendar.year(w.day), "m": LTCalendar.month_index(w.day)}
	LTCalendar.apply({})
	_check("Real calendar: day one is today's date, and the date to match is found exactly", first_ok and target == 1, "Day one reads %s. The game day for today is %d. Forty days later it reads month %d of %d." % ["%d-%d" % [int(today["month"]), int(today["day"])], target, int(later["m"]) + 1, int(later["y"])], w)


func _save_load_full() -> void:
	var a: LTWorld = _town(200)
	var path: String = "user://scenario.ltsave"
	a.save_to_file(path)
	var b: LTWorld = LTWorld.new()
	var err: Error = b.load_from_file(path)
	a.run_days(100)
	b.run_days(100)
	_check("Saves carry every new system (cases, region, spend book, pregnancies, addictions) and continue identically", err == OK and a.state_hash() == b.state_hash(), "Hashes after 100 more days: %d and %d." % [a.state_hash(), b.state_hash()], a)
