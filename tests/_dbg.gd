extends SceneTree
func _init() -> void:
	var w: LTWorld = LTWorld.new()
	w.new_town(5, {}, {"start": "founder"})
	var n: Callable = func(i, j): return LTGeography.node_id(w, i, j)
	print(w.apply_action({"kind": "plan_road", "a": n.call(10, 12), "b": n.call(10, 4)}))
	print(w.apply_action({"kind": "plan_road", "a": n.call(10, 8), "b": n.call(20, 8)}))
	print(w.apply_action({"kind": "plot_lots", "c0": 11, "r0": 8, "c1": 19, "r1": 11, "zone": "residential"}))
	print(w.apply_action({"kind": "plot_lots", "c0": 11, "r0": 7, "c1": 14, "r1": 7, "zone": "commercial"}))
	print(w.apply_action({"kind": "plot_lots", "c0": 25, "r0": 2, "c1": 26, "r1": 3, "zone": "residential"}))
	print("lots ", w.lots.size(), " connected ", LTGeography.connected(w, 0))
	for d in 400:
		for p in w.projects:
			if str(p["status"]) == "review" and not bool(p["private"]):
				var pick: int = 0
				for i in p["bids"].size():
					if int(p["bids"][i]["price"]) < int(p["bids"][pick]["price"]):
						pick = i
				w.apply_action({"kind": "award_bid", "project_id": int(p["id"]), "bid_index": pick})
		if d == 40:
			w.apply_action({"kind": "define_project", "ptype": "mayor_house", "target": 20})
		w.tick_day()
		if d % 50 == 49:
			print(LTCalendar.short(w.day), " res ", w.residents(), " fund ", LTMoney.fmt(w.ledger.bal("city")), " connected0 ", LTGeography.connected(w, 0), " min ", int(w.travel_minutes(0, -1)), " houses ", w.lots.filter(func(l): return str(l["use"]) == "house").size())
	for p in w.projects:
		print(p["title"], " ", p["status"])
	print(w.ledger.audit()["ok"])
	quit(0)
