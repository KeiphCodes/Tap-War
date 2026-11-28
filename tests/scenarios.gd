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
	_sim_mayor()
	_custom_homes()
	_business_buildings()
	_business_rooms()
	_town_government()
	_map_landmarks()
	_rail_and_growth()
	_property_lines_and_bank()
	_apartments_built_for_need()
	_real_loans()
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
	# the quick path: move into an empty building already standing on the lot
	w.lot(lot)["use"] = "closed"
	var cs: Dictionary = LTEconomy.startup_costs(w, btype, false, true)
	_give(w, c, float(int(cs["total"])) / 100.0 + 5000.0)
	var plan: Dictionary = {"type": btype, "lot": lot, "score": 50.0, "est_monthly": 100000, "startup": int(cs["total"]), "loan_need": 0, "grant": 0, "need_id": -1, "funding": "savings", "reason": "a test scenario", "doubt": "", "costs": cs, "home": false}
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
	# the mayor extends the town: a new street off the east edge and an alley
	# behind it, built through bids, and new lots on it reach the rest of town
	var w: LTWorld = _town()
	# enough in the bank to award the street, whatever the land under it costs
	w.ledger.pay("outside", "city", LTMoney.dollars(400000.0), "test_grant")
	var lots0: int = w.lots.size()
	var n: Callable = func(i, j): return LTGeography.node_id(w, i, j)
	var r: Dictionary = w.apply_action({"kind": "plan_road", "a": n.call(100, 40), "b": n.call(110, 40), "live": true})
	var ra: Dictionary = w.apply_action({"kind": "plan_road", "a": n.call(100, 45), "b": n.call(110, 45), "live": true, "road_kind": "alley"})
	var pl: Dictionary = w.apply_action({"kind": "plot_lots", "x0": 1007.5, "z0": 407.5, "x1": 1100.0, "z1": 447.0, "zone": "residential", "width": 20.0})
	var new_street: int = int(r.get("street", -1))
	w.run_days(16)
	for p0 in w.projects:
		if str(p0["status"]) == "review":
			var pick: int = 0
			for i in p0["bids"].size():
				if int(p0["bids"][i]["price"]) < int(p0["bids"][pick]["price"]):
					pick = i
			w.apply_action({"kind": "award_bid", "project_id": int(p0["id"]), "bid_index": pick})
	w.run_days(200)
	var new_lot: int = lots0
	var mins: float = w.travel_minutes(0, new_lot)
	var p: Dictionary = w.projects[int(r.get("project_id", 0))]
	var cond: float = LTGeography.street_condition(w, new_street)
	var alley_ok: bool = bool(ra["ok"]) and str(w.streets[int(ra["street"])]["kind"]) == "alley"
	var ok: bool = bool(r["ok"]) and alley_ok and bool(pl["ok"]) and w.lots.size() >= lots0 + 3 and mins < 30.0 and str(p["status"]) == "done" and cond > 25.0
	_check("Plotting land: the mayor lays a new street and an alley at the edge of town, contractors build them, and new lots on them reach the rest of town", ok, "%s %s %s Lots %d to %d. Travel from lot 0 to a new lot: %.1f minutes. The new street is %s, condition %d." % [r["message"], ra["message"], pl["message"], lots0, w.lots.size(), mins, p["status"], int(cond)], w)


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
	# a severe storm hurts run down and cheaply built buildings far more than sound ones,
	# ordinary thunderstorms only touch the weak ones, and insurance pays the big bills
	var w: LTWorld = _town()
	var weak_ids: Array = []
	var sound_ids: Array = []
	for l in w.lots:
		if not ["house", "apartment", "business"].has(str(l["use"])):
			continue
		if weak_ids.size() <= sound_ids.size():
			l["condition"] = 35.0
			weak_ids.append(int(l["id"]))
		else:
			l["condition"] = 85.0
			l["build_quality"] = 0.8
			sound_ids.append(int(l["id"]))
	var loss: Callable = func(ids: Array, start: float) -> float:
		var t: float = 0.0
		for id in ids:
			t += start - float(w.lot(int(id))["condition"])
		return t / float(maxi(1, ids.size()))
	w.weather = "Storm"
	for i in 20:
		LTHazards._ordinary_weather(w)
	var ord_weak: float = loss.call(weak_ids, 35.0)
	var ord_sound: float = loss.call(sound_ids, 85.0)
	for i in 4:
		LTHazards.severe_storm(w)
	var sev_weak: float = loss.call(weak_ids, 35.0) - ord_weak
	var sev_sound: float = loss.call(sound_ids, 85.0) - ord_sound
	var repairs: int = int(w.spend_book.get("repairs", {}).get("outside", 0)) + int(w.spend_book.get("repairs", {}).get("local", 0))
	var claims: int = int(w.counters.get("insurance_claims", 0))
	var ok: bool = ord_sound == 0.0 and ord_weak > 0.0 and sev_weak > sev_sound * 2.0 and repairs > 0
	_check("Storms: ordinary thunderstorms only damage run down or cheap buildings, severe storms hit those far harder, owners and insurers pay real repair bills", ok, "Twenty ordinary thunderstorms: average loss %.1f condition points on weak buildings, %.1f on sound ones. Four severe storms: %.1f on weak, %.1f on sound. Repairs paid: %s. Insurance claims: %d." % [ord_weak, ord_sound, sev_weak, sev_sound, LTMoney.fmt(repairs), claims], w)


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
	# Main Street north from the county road, Elm Street across it, house lots on
	# both sides of Elm, storefronts on the county road, and a lot for the mayor
	var r1: Dictionary = w.apply_action({"kind": "plan_road", "a": n.call(70, 60), "b": n.call(70, 40), "live": true})
	var r2: Dictionary = w.apply_action({"kind": "plan_road", "a": n.call(60, 50), "b": n.call(90, 50), "live": true})
	w.apply_action({"kind": "plot_lots", "x0": 707.5, "z0": 452.5, "x1": 900.0, "z1": 492.5, "zone": "residential", "width": 20.0})
	w.apply_action({"kind": "plot_lots", "x0": 707.5, "z0": 507.5, "x1": 900.0, "z1": 547.5, "zone": "residential", "width": 20.0})
	w.apply_action({"kind": "plot_lots", "x0": 707.5, "z0": 552.0, "x1": 800.0, "z1": 592.0, "zone": "commercial", "width": 12.0})
	w.apply_action({"kind": "plot_lots", "x0": 640.0, "z0": 507.5, "x1": 692.5, "z1": 547.5, "zone": "civic"})
	var mh_lot: int = LTGeography.lot_at(w, 660.0, 525.0)
	w.apply_action({"kind": "define_project", "ptype": "mayor_house", "target": mh_lot, "live": true})
	var inc_day: int = -1
	# two years, or until the first election 90 days after incorporating (at most three years)
	for d in 1095:
		if d >= 730 and (inc_day < 0 or w.day > inc_day + 100):
			break
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
		w.apply_action({"kind": "plan_road", "a": n.call(70, 60), "b": n.call(70, 54)})
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
	dw.apply_action({"kind": "plan_road", "a": LTGeography.node_id(dw, 70, 60), "b": LTGeography.node_id(dw, 70, 54)})
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
	var reopened: bool = str(dl_w.projects[0]["status"]) == "draft" and dl_w.projects[0]["bids"].is_empty()
	# signed contracts are locked
	var locked: Dictionary = built_fancy.apply_action({"kind": "edit_project", "project_id": 0, "changes": {"surface": "gravel"}})
	# lot details: price, hold and zone, applied to a plotted group
	var lw: LTWorld = LTWorld.new()
	lw.new_town(SEED, {}, {"start": "founder"})
	var r: Dictionary = lw.apply_action({"kind": "plot_lots", "x0": 100.0, "z0": 552.0, "x1": 300.0, "z1": 592.0, "zone": "residential", "width": 33.3})
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


func _sim_mayor() -> void:
	# the same mayor seed always makes the same person, who founds and runs the town
	var a: Dictionary = LTMayorAI.make_persona(4242)
	var b: Dictionary = LTMayorAI.make_persona(4242)
	var w: LTWorld = LTWorld.new()
	w.new_town(21, {}, {"start": "founder", "autonomous": true, "mayor_seed": 4242})
	for d in 300:
		w.tick_day()
	var moves: int = 0
	for c in w.chronicle:
		if str(c.get("text", "")).begins_with("Mayor %s" % w.player["name"]):
			moves += 1
	var built: int = 0
	for p in w.projects:
		if ["building", "done"].has(str(p["status"])):
			built += 1
	var r: Dictionary = w.apply_action({"kind": "take_over", "on": true})
	var ok: bool = str(a["name"]) == str(b["name"]) and a["traits"] == b["traits"] and str(w.player["name"]) == str(a["name"]) and moves >= 5 and built >= 2 and w.streets.size() >= 3 and bool(r["ok"]) and not LTMayorAI.is_on(w) and w.action_log.size() == 1
	_check("Sim mayor: a seeded Sim founds the town, lays roads, awards contracts and logs each reason, and the player can take over", ok, "%s (%s) made %d decisions in 300 days. Streets %d, projects under way or done %d, residents %d. Take over: %s" % [w.player["name"], LTMayorAI.describe(w.player), moves, w.streets.size(), built, w.residents(), r["message"]], w)


func _custom_homes() -> void:
	# a family designs its house from its life, it fits the lot facing the street,
	# it remodels when life changes, and a variance goes to the mayor
	var w: LTWorld = _town(5)
	var fitting: int = 0
	var houses: int = 0
	for l in w.lots:
		if str(l["use"]) == "house" and l.has("home"):
			houses += 1
			if bool(LTHomes.layout(l, l["home"])["fits"]):
				fitting += 1
	var lot: Dictionary = {}
	var h: Dictionary = {}
	for hh in w.households:
		if str(hh["tenure"]) == "own" and int(hh["lot"]) >= 0 and str(w.lot(int(hh["lot"]))["use"]) == "house":
			h = hh
			lot = w.lot(int(hh["lot"]))
			break
	var before: Dictionary = LTHomes.upgrade(lot["home"])
	var head: Dictionary = w.household_adults(h)[0]
	var r: Array = LTHomes.apply_want(before, "bedroom")
	_give(w, head, 200000.0)
	LTHomes.start_remodel(w, h, lot, head, {"key": "bedroom", "label": "add a bedroom", "why": "a new baby"}, r[0], int(r[1]), "cash")
	for d in 200:
		w.tick_day()
	var after: Dictionary = LTHomes.upgrade(lot["home"])
	# a variance: the mayor grants it
	if not w.city.has("variances"):
		w.city["variances"] = []
	w.city["variances"].append({"id": w.city["variances"].size(), "lot": int(lot["id"]), "hh": int(h["id"]), "cid": int(head["id"]), "family": str(head["last_name"]),
		"want": {"key": "deck", "label": "build a back deck", "why": "summer evenings"}, "home": LTHomes.apply_want(after, "deck")[0], "cost": LTMoney.dollars(15000.0), "funding": "cash",
		"rule": "test", "day": w.day, "status": "pending", "for": 1, "against": 0, "voices": []})
	var vr: Dictionary = w.apply_action({"kind": "decide_variance", "variance_id": w.city["variances"].size() - 1, "approve": true})
	var ok: bool = houses > 0 and fitting == houses and int(after["beds"]) == int(before["beds"]) + 1 and bool(vr["ok"]) and LTHomes.home_cost(after) > 0 and not LTHomes.plan(lot, after).is_empty()
	_check("Custom homes: families design houses room by room that fit their lots, remodel as life changes, and ask the mayor for variances", ok, "%d of %d houses fit their lots. %s family: %s became %s. Variance: %s" % [fitting, houses, head["last_name"], LTHomes.text(before), LTHomes.text(after), vr["message"]], w)


func _business_rooms() -> void:
	# every kind of business has the rooms, equipment and code items its trade
	# really needs; the rooms that limit service are the bottleneck
	var w: LTWorld = _town(5)
	var c: Dictionary = _adult(w, func(x): return true)
	var missing: Array = []
	for bt in LTEconomy.COSTS.keys():
		var p: Dictionary = LTBuildings.design(w, bt, c, int(LTEconomy.COSTS[bt]["sqft"]), LTMoney.dollars(50000.0))
		var keys: Array = []
		for r in LTBuildings.rooms_of(p):
			keys.append(str(r["key"]))
		if keys.has("main") or LTBuildings.equipment_list(p).is_empty() or LTBuildings.code_list(p).is_empty():
			missing.append(bt)
	var cafe: Dictionary = LTBuildings.design(w, "cafe", c, 1500, 0)
	cafe["mix"] = 0.0
	cafe["rooms"] = LTBuildings.rooms_for(cafe)
	var shop: Dictionary = LTBuildings.design(w, "repair_shop", c, 2000, 0)
	var codes: String = ""
	for x in LTBuildings.code_list(cafe) + LTBuildings.code_list(shop):
		codes += str(x[0]) + "; "
	var greedy: Dictionary = cafe.duplicate(true)
	greedy["mix"] = 0.25
	greedy["rooms"] = LTBuildings.rooms_for(greedy)
	var front_ok: bool = true
	var fp: Array = LTBuildings.floor_plan(w.lots[0], cafe)
	for rc in fp[0]["rects"]:
		if str(rc[4]) == "Dining room" and float(rc[1]) > 0.0:
			front_ok = false
	var ok: bool = missing.is_empty() and codes.contains("hood") and codes.contains("Grease trap") and codes.contains("Oil water separator") \
		and LTBuildings.bottleneck(greedy) == "kitchen" and LTBuildings.capacity(greedy) < LTBuildings.capacity(cafe) and front_ok
	_check("Business rooms: every kind of business has its own rooms, equipment and code items, and a cramped kitchen is the bottleneck", ok,
		"Without their own rooms or equipment: %s. Balanced cafe serves %d a day; one with seats crammed in serves %d (%s)." % [str(missing), int(LTBuildings.capacity(cafe)), int(LTBuildings.capacity(greedy)), LTBuildings.capacity_text(greedy)], w)


func _town_government() -> void:
	# a board is elected once the town is big enough, it votes on laws and
	# confirms appointments, the mayor is limited to two terms and an open race
	# makes a new mayor; a mayor who grabs power loses the town's trust
	var w: LTWorld = _town(5)
	w.apply_action({"kind": "elections", "on": true})
	w.run_days(65)
	var gv: Dictionary = LTGov.g(w)
	var board_n: int = gv["board"].size()
	var law: Dictionary = w.apply_action({"kind": "set_law", "law": "school_funding", "value": 1.5})
	var voted: bool = gv["votes"].size() >= 1
	var nom: Array = LTGov.nominees(w, "finance_officer")
	var ap: Dictionary = w.apply_action({"kind": "appoint", "role": "finance_officer", "citizen_id": int(nom[0]["id"])}) if not nom.is_empty() else {"ok": false, "message": "nobody"}
	# the end of a second term: an open race and a new mayor
	gv["mayor_terms"] = 2
	w.city["held_election"] = true
	w.city["next_election_day"] = w.day + 62
	var old: String = str(w.player["name"])
	w.run_days(64)
	var new_mayor: bool = str(w.player["name"]) != old and bool(w.city.get("player_out", false)) and LTMayorAI.is_on(w)
	# a separate town where the mayor rules by decree
	var w2: LTWorld = _town(5)
	w2.apply_action({"kind": "elections", "on": true})
	w2.city["held_election"] = true
	var before: float = LTCivic.approval(w2)
	var dc: Dictionary = w2.apply_action({"kind": "decree", "why": "test"})
	var after: float = LTCivic.approval(w2)
	var ok: bool = board_n == 3 and voted and bool(ap.get("ok", false)) == LTGov.g(w)["officials"].has("finance_officer") and new_mayor and bool(dc["ok"]) and not bool(w2.city["elections"]) and after < before - 10.0
	_check("Town government: an elected board votes on laws and appointments, two terms and out, and ruling by decree costs the town's trust", ok,
		"Board of %d. School funding vote: %s Appointment: %s After two terms: %s took over from %s. Decree: approval %d to %d." % [board_n, law["message"].substr(0, 120), ap["message"].substr(0, 100), w.player["name"], old, int(before), int(after)], w)


func _map_landmarks() -> void:
	# every map seed comes with the county already settled around it, the same
	# way each time, and none of it on water or where the town starts
	var w: LTWorld = LTWorld.new()
	w.new_town(11, {}, {"start": "founder"})
	var a: Array = LTTerrain.landmarks(w)
	var w2: LTWorld = LTWorld.new()
	w2.new_town(11, {}, {"start": "founder"})
	var kinds: Dictionary = {}
	var bad: int = 0
	for m in a:
		kinds[str(m["kind"])] = true
		if LTTerrain.is_water(w, float(m["x"]), float(m["z"])):
			bad += 1
	var ok: bool = kinds.has("farmstead") and kinds.has("elevator") and kinds.has("church") and kinds.has("lookout") and bad == 0 and a == LTTerrain.landmarks(w2)
	_check("Map landmarks: each map seed has farms, a grain elevator on the railroad, a country church, cabins and a lookout, the same every time", ok, "%d landmarks: %s. On water: %d." % [a.size(), str(kinds.keys()), bad], w)


func _rail_and_growth() -> void:
	# a busy bulk shipper puts in its own spur, the city can only put a depot
	# beside the tracks, nobody builds on the right of way, a full lot builds up
	# to the height limit, and a farm that keeps making money buys more land
	var w: LTWorld = _town(5)
	var b: Dictionary = {}
	for x in w.businesses:
		if str(x["status"]) == "open" and int(x["lot"]) >= 0 and not bool(x.get("home_based", false)):
			b = x
			break
	if not b.is_empty() and not b.has("bplan"):
		b["bplan"] = LTBuildings.design(w, "general_store", w.cit(int(b["owners"][0])), 2500, 0)
	if b.is_empty():
		_check("Railroad and growth", false, "no business with a building", w)
		return
	var keep_type: String = str(b["type"])
	b["type"] = "mill"
	b["month_revenue"] = LTMoney.dollars(90000.0)
	w.ledger.pay("outside", w.acct_b(b), LTMoney.dollars(400000.0), "test_capital")
	var why: String = LTRail.consider_spur(w, b)
	var spur: bool = bool(b.get("rail_spur", false)) and LTRail.export_rev(w, b, 100000) > 100000
	var rz: float = LTRail.line_z(w)
	var row: Dictionary = LTTerrain.survey(w, Rect2(400.0, rz - 10.0, 20.0, 30.0))
	var far: Dictionary = {}
	for l in w.lots:
		if LTRail.distance(w, l) > 200.0:
			far = l
			break
	# the city's loading track, the real way: ask, the railroad answers on traffic
	var no_deal: String = LTRail.depot_lot_ok(w, far)
	var rr: Dictionary = LTRail.r(w)
	var asked: Dictionary = w.apply_action({"kind": "rail_request"})
	b["month_revenue"] = LTMoney.dollars(90000.0)
	for i in 46:
		LTRail.daily(w)
		w.day += 1
	var signed: bool = str(rr["agreement"]) == "signed"
	var depot_no: String = LTRail.depot_lot_ok(w, far)
	# building up
	b["type"] = keep_type
	var plan: Dictionary = b["bplan"].duplicate(true)
	plan["sqft"] = int(plan["sqft"]) * 3
	w.city["laws"]["height_limit"] = 2.0
	var low: bool = LTBuildings._go_up(w, b, plan.duplicate(true), w.lot(int(b["lot"])))
	w.city["laws"]["height_limit"] = 6.0
	var up_plan: Dictionary = plan.duplicate(true)
	var high: bool = LTBuildings._go_up(w, b, up_plan, w.lot(int(b["lot"])))
	# a farm that has made money for a year
	b["type"] = "farm"
	b["month_profit_hist"] = []
	for i in 12:
		b["month_profit_hist"].append(LTMoney.dollars(60000.0))
	b["expanded_day"] = -9999
	w.cit(int(b["owners"][0]))["traits"]["ambition"] = 80
	w.ledger.pay("outside", w.acct_b(b), LTMoney.dollars(600000.0), "test_capital")
	var staff_before: int = int(b["target_staff"])
	LTBuildings._grow_production(w, b)
	var grew: bool = int(b.get("acres", 160)) == 320 and int(b["target_staff"]) == staff_before + 2
	# a light branch line the railroad gives up on
	b["type"] = "mill"
	rr["abandon_day"] = w.day
	LTRail.daily(w)
	var pulled: bool = not LTRail.has_line(w) and not bool(b.get("rail_spur", false))
	b["type"] = keep_type
	var ok: bool = no_deal.contains("agree") and bool(asked["ok"]) and signed and pulled and spur and not bool(row["ok"]) and depot_no.contains("beside the main line") and not low and high and int(up_plan["stories"]) >= 3 and grew
	_check("Railroad and growth: shippers build spurs, the city gets a loading track only through the railroad's agreement and beside the tracks, lines can be abandoned, the right of way stays clear, full lots build up to the height limit, farms buy land", ok,
		"Spur: %s. Right of way: %s. Before an agreement: %s. Railroad signed: %s. Lot far from the track: %s. Line abandoned and spur gone: %s. Up to 2 stories: %s, up to 6: %s (%d stories). Farm acres: %d." % [why, row["why"], no_deal, signed, depot_no, pulled, low, high, int(up_plan.get("stories", 1)), int(b.get("acres", 0))], w)


func _business_buildings() -> void:
	# an owner designs a cafe with seats, a hood and wishes as money allows; the
	# seats cap how many it serves; a busy, profitable business adds on
	var w: LTWorld = _town(5)
	var c: Dictionary = _adult(w, func(x): return str(x["job"]["kind"]) != "owner")
	c["traits"]["sociability"] = 80
	var lean: Dictionary = LTBuildings.design(w, "cafe", c, 1500, 0)
	var rich: Dictionary = LTBuildings.design(w, "cafe", c, 1500, LTMoney.dollars(200000.0))
	var b: Dictionary = _found(w, c, "cafe", ["commercial", "mixed"])
	var grew: bool = false
	var before_sq: int = 0
	if not b.is_empty() and b.has("bplan"):
		before_sq = int(b["bplan"]["sqft"])
		b["opened_day"] = w.day - 800
		b["customers_avg"] = LTBuildings.capacity(b["bplan"]) * 2.0
		_give(w, c, 0.0)
		w.ledger.pay("outside", w.acct_b(b), LTMoney.dollars(300000.0), "test_grant")
		LTBuildings._expand(w, b)
		for d in 150:
			w.tick_day()
		grew = int(b["bplan"]["sqft"]) > before_sq
	var ok: bool = lean["features"].has("hood") and not lean["features"].has("patio") and rich["features"].has("patio") and LTBuildings.capacity(rich) > 0.0 and not b.is_empty() and b.has("bplan") and grew
	_check("Business buildings: owners design them room by room within their money, rooms set how many they serve, and busy ones add on", ok, "Lean cafe: %s. With money to spare: %s. %s grew from %d to %d sq ft." % [LTBuildings.text(lean), LTBuildings.text(rich), b.get("name", "?"), before_sq, int(b.get("bplan", {}).get("sqft", 0))], w)


func _property_lines_and_bank() -> void:
	var w: LTWorld = _town(5)
	# a family owns its house lot and buys the empty lot beside it, then combines them
	var a: Dictionary = {}
	var b: Dictionary = {}
	for l in w.lots:
		if str(l["use"]) == "house" and str(l["owner_kind"]) == "sim":
			for n in LTLand.side_neighbors(w, l):
				a = l
				b = n
				break
		if not a.is_empty():
			break
	var fw_a: float = LTGeography.lot_frontage(a)
	var fw_b: float = LTGeography.lot_frontage(b)
	b["use"] = "empty"
	b["units"] = []
	b.erase("home")
	b["zone"] = a["zone"]
	b["owner_kind"] = a["owner_kind"]
	b["owner_id"] = a["owner_id"]
	var m: Dictionary = LTLand.merge(w, int(a["id"]), int(b["id"]), "test")
	var merged: bool = bool(m["ok"]) and absf(LTGeography.lot_frontage(a) - (fw_a + fw_b)) < 0.2 and bool(b.get("removed", false))
	# then asks the mayor to split a building lot back off
	var owner: Dictionary = w.cit(int(a["owner_id"]))
	var lots_before: int = w.lots.size()
	LTLand._file_plat(w, a, owner, float(LTLand.minimum(str(a["zone"]))[0]) + 0.5, "test")
	var pid: int = w.city["plats"].size() - 1
	var r: Dictionary = w.apply_action({"kind": "decide_plat", "plat_id": pid, "approve": true})
	var split_ok: bool = bool(r["ok"]) and w.lots.size() == lots_before + 1 and bool(LTHomes.layout(a, a["home"])["fits"]) and w.lot(lots_before).has("for_sale")
	# the bank: good credit and 20% down gets a conventional mortgage; fair credit
	# and a little cash gets FHA; a founder with 12% down gets an SBA loan
	var h: Dictionary = w.hh(int(owner["household"]))
	var head: Dictionary = w.household_adults(h)[0]
	head["credit"]["has_file"] = true
	head["credit"]["score"] = 760
	head["job"]["daily_wage"] = 40000
	_give(w, head, 120000.0)
	var conv: Dictionary = LTFinance.mortgage_offer(w, h, head, LTMoney.dollars(250000.0))
	head["credit"]["score"] = 590
	for o in w.household_adults(h):
		if o != head:
			w.ledger.pay(w.acct_p(o), "outside", w.cash(o), "test")
	w.ledger.pay(w.acct_p(head), "outside", maxi(0, w.cash(head) - LTMoney.dollars(20000.0)), "test")
	var fha: Dictionary = LTFinance.mortgage_offer(w, h, head, LTMoney.dollars(250000.0))
	head["credit"]["score"] = 665
	var cs: Dictionary = {"total": LTMoney.dollars(200000.0), "building": LTMoney.dollars(120000.0)}
	var sba: Dictionary = LTFinance.business_offer(w, head, cs, LTMoney.dollars(24000.0), LTMoney.dollars(5000.0))
	var none: Dictionary = LTFinance.business_offer(w, head, cs, LTMoney.dollars(2000.0), LTMoney.dollars(5000.0))
	var bank_ok: bool = bool(conv["ok"]) and str(conv["program"]) == "conventional" and bool(fha["ok"]) and str(fha["program"]) == "FHA" and bool(sba["ok"]) and str(sba["program"]).begins_with("SBA") and not bool(none["ok"]) and str(none.get("advice", "")) != ""
	_check("Property lines and the bank: owners combine and split lots (splits need the mayor), and the bank finds a program for buyers who have the down payment and the credit", merged and split_ok and bank_ok, "Merge: %s Split: %s Conventional: %s. FHA: %s. Business: %s. Too little down: %s; advice: %s." % [m["message"], r["message"], conv.get("reason", conv.get("advice", "")), fha.get("reason", fha.get("advice", "")), sba.get("reason", ""), none.get("reason", ""), none.get("advice", "")], w)


func _apartments_built_for_need() -> void:
	# a town with no rentals free: a Sim with money builds apartments designed for
	# who is waiting, renters move in at each unit's own rent, a family gets room
	var w: LTWorld = _town(5)
	var lot: Dictionary = {}
	for l in w.lots:
		if str(l["use"]) == "empty" and ["residential", "mixed"].has(str(l["zone"])) and LTGeography.lot_area(l) >= 700.0:
			lot = l
			break
	if lot.is_empty():
		for l in w.lots:
			if str(l["use"]) == "empty" and LTGeography.lot_area(l) >= 700.0:
				l["zone"] = "residential"
				lot = l
				break
	lot["owner_kind"] = "city"
	var dev: Dictionary = _adult(w, func(x): return w.age_years(x) >= 35)
	dev["traits"]["ambition"] = 80
	dev["traits"]["greed"] = 50
	dev["skills"]["finance"] = 70
	dev["credit"]["has_file"] = true
	dev["credit"]["score"] = 760
	_give(w, dev, 600000.0)
	# fill every free home so the town is short
	for i in 20:
		var u: Dictionary = LTPeople.free_unit(w)
		if u.is_empty():
			break
		var hh: Dictionary = LTPeople.make_household(w, false, true)
		LTPeople.move_household_into(w, hh, int(u["lot"]), int(u["unit"]))
		hh["tenure"] = "rent"
	for i in 6:
		var hx: Dictionary = LTPeople.make_household(w, true, true)
		hx["lot"] = -1
	var before: int = w.projects.size()
	for i in 20:
		if w.projects.size() > before:
			break
		LTApartments.monthly(w)
	var built: Dictionary = {}
	for p in w.projects.slice(before):
		if str(p["ptype"]) == "apartments":
			built = p
	for d in 400:
		w.tick_day()
	var l2: Dictionary = w.lot(int(built.get("lot", -1))) if not built.is_empty() else {}
	var rented: int = 0
	var rent_ok: bool = true
	if not l2.is_empty() and l2.has("apt"):
		for i in l2["units"].size():
			if int(l2["units"][i]) >= 0:
				rented += 1
				var hh2: Dictionary = w.hh(int(l2["units"][i]))
				if absi(int(hh2["rent"]) - LTApartments.rent_for(w, l2, i)) > int(LTApartments.rent_for(w, l2, i) * 0.15):
					rent_ok = false
	var spec: Dictionary = l2.get("apt", {})
	var ok: bool = not built.is_empty() and str(l2.get("use", "")) == "apartment" and not spec.is_empty() and spec["units"].size() >= 4 and rented > 0 and rent_ok and not LTApartments.floor_plan(l2, spec).is_empty()
	_check("Apartments: a Sim builds homes designed for who is waiting, each unit with its own rent, and renters move in", ok, "%s. %s. Rents %s. %d of %d rented. Why: %s." % [built.get("title", "nothing built"), LTApartments.text(spec), LTApartments.rent_range(spec), rented, l2.get("units", []).size(), "; ".join(spec.get("why", []))], w)


func _real_loans() -> void:
	var w: LTWorld = _town(5)
	var c: Dictionary = _adult(w, func(x): return w.age_years(x) >= 30)
	c["credit"]["has_file"] = true
	c["credit"]["score"] = 740
	_give(w, c, 200000.0)
	# the bank lays out real products and the borrower picks one, with a reason
	var base: Dictionary = {"program": "conventional", "loan": LTMoney.dollars(240000.0), "rate": 0.065, "insurance": 0.005}
	var offers: Array = LTLoans.mortgage_offers(w, base, LTMoney.dollars(9000.0), 0.43, 0)
	var pick: Dictionary = LTLoans.choose(c, offers, {"income": LTMoney.dollars(9000.0), "cash": w.cash(c), "years": 10.0})
	var names: Array = offers.map(func(o): return str(o["name"]))
	# an adjustable rate resets after five years, within its 2% cap
	var arm: Dictionary = {}
	for o in offers:
		if str(o["rate_type"]) == "arm":
			arm = o
	var d: Dictionary = LTLoans.book(w, "p", int(c["id"]), "mortgage", LTMoney.dollars(240000.0), arm, "", -1, offers, "test")
	d["terms"]["months_paid"] = 60
	w.bank["index"] = 0.08
	var r0: float = float(d["rate"])
	LTLoans.due_this_month(w, d)
	var reset_ok: bool = float(d["rate"]) > r0 and float(d["rate"]) <= r0 + 0.02 + 0.0001
	# a balloon that has been paid on time is refinanced when it comes due
	var bo: Dictionary = LTLoans.price("business", "5-year balloon, 20-year amortization", LTMoney.dollars(100000.0), 0.08, 60, {"amort": 240})
	var bd: Dictionary = LTLoans.book(w, "p", int(c["id"]), "business_loan", LTMoney.dollars(100000.0), bo, "", -1, [bo], "test")
	bd["terms"]["months_paid"] = 59
	var before: int = w.debts.size()
	var due: int = LTLoans.due_this_month(w, bd)
	var refi: bool = due == -2 and LTLoans.balloon_due(w, bd) and w.debts.size() == before + 1 and str(bd["status"]) == "paid"
	# mortgage insurance comes off at 78% of the home's value
	var po: Dictionary = LTLoans.price("mortgage", "30-year fixed", LTMoney.dollars(190000.0), 0.065, 360, {"insurance": 0.005})
	var pd: Dictionary = LTLoans.book(w, "p", int(c["id"]), "mortgage", LTMoney.dollars(190000.0), po, "", -1, [po], "test")
	pd["terms"]["home_value"] = LTMoney.dollars(200000.0)
	var ins0: int = LTLoans.insurance_due(w, pd)
	pd["balance"] = LTMoney.dollars(150000.0)
	var ins1: int = LTLoans.insurance_due(w, pd)
	var ok: bool = offers.size() >= 3 and not pick.is_empty() and str(pick["why"]) != "" and reset_ok and refi and ins0 > 0 and ins1 == 0 and float(arm.get("apr", 0.0)) > float(arm.get("rate", 1.0))
	_check("Real loans: the bank offers products, the borrower picks with a reason, adjustable rates reset within caps, balloons refinance, mortgage insurance drops at 78%", ok, "Offers: %s. Picked %s: %s. ARM %.2f%% to %.2f%%. Balloon refinanced: %s. Insurance %s then %s." % [", ".join(names), pick.get("offer", {}).get("name", "?"), pick.get("why", ""), r0 * 100.0, float(d["rate"]) * 100.0, refi, LTMoney.fmt(ins0), LTMoney.fmt(ins1)], w)
