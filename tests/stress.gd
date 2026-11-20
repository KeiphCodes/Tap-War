extends SceneTree
## Headless stress run: the same systems at about 1,000 Sims. The design requires
## this profile before V2 scope is approved. Run: godot --headless --script tests/stress.gd


func _init() -> void:
	var w: LTWorld = LTWorld.new()
	var t0: int = Time.get_ticks_msec()
	w.new_town(77, {"lot_cols": 14, "lot_rows": 12, "target_households": 330, "target_population": 1000, "house_lots": 34, "apartment_lots": 50, "apartment_units": 6, "city_start_cash": LTMoney.dollars(1500000.0)})
	var gen_ms: int = Time.get_ticks_msec() - t0
	var start_pop: int = w.alive_count()
	var worst: int = 0
	var total: int = 0
	var days: int = 90
	for i in days:
		var t: int = Time.get_ticks_usec()
		w.tick_day()
		var d: int = (Time.get_ticks_usec() - t) / 1000
		worst = maxi(worst, d)
		total += d
	var a: Dictionary = w.ledger.audit()
	var text: String = "STRESS RUN\nGenerated %d Sims in %d households on %d lots in %d ms.\n%d days: average tick %d ms, worst tick %d ms. Population now %d. Ledger %s.\nBusinesses opened %d, bankruptcies %d, petitions %d." % [start_pop, w.households.size(), w.lots.size(), gen_ms, days, total / days, worst, w.alive_count(), "balanced" if bool(a["ok"]) else "NOT BALANCED", w.counters["businesses_opened"], w.counters["bankruptcies"], w.counters["petitions"]]
	print(text)
	var f: FileAccess = FileAccess.open("res://reports/stress_summary.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(text + "\n")
		f.close()
	quit(0 if bool(a["ok"]) else 1)
