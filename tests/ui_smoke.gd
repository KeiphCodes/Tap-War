extends SceneTree
## Drives the real game scene headless: plays two months, opens every tab and every
## kind of inspector, uses the new mayor actions, and fails on any script error.
## Run: godot --headless --script tests/ui_smoke.gd

func _init() -> void:
	var main: Node = load("res://town/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	for card in main.hud.root.get_children():
		if card is PanelContainer and card != main.hud.top_bar and card != main.hud.left and card != main.hud.right and card != main.hud.notice and card != main.hud.tool_bar and card != main.hud.steps_card:
			card.queue_free()
	main.new_town(20261120, {"start": "founder", "elections": true, "real_calendar": true})
	await process_frame
	var n: Callable = func(i, j): return LTGeography.node_id(main.world, i, j)
	print("road: ", main.act({"kind": "plan_road", "a": n.call(70, 60), "b": n.call(70, 54)})["message"])
	print("plot: ", main.act({"kind": "plot_lots", "x0": 707.5, "z0": 552.0, "x1": 787.5, "z1": 592.0, "zone": "residential", "width": 20.0})["message"])
	main.act({"kind": "define_project", "ptype": "mayor_house", "target": 0})
	for t in ["road", "plot", "unplot", "look"]:
		main.hud._set_tool(t)
		main.view._ta = Vector3(700.0, 0, 560.0)
		main.view._tb = Vector3(790.0, 0, 590.0)
		main.view._show_preview()
	main.hud.inspect("lot", 0)
	main.hud.inspect("road", 1)
	main.hud.inspect("proj", 0)
	print("contract: ", main.act({"kind": "edit_project", "project_id": 0, "changes": {"surface": "concrete", "sidewalks": true, "lights": true, "deadline": 90, "penalty": true}})["message"])
	main.hud.inspect("road", 1)
	print("go live: ", main.act({"kind": "go_live", "project_id": 0})["message"])
	print("go live house: ", main.act({"kind": "go_live", "project_id": 1})["message"])
	main.hud.inspect("road", 1)
	main.hud.inspect("road", 0)
	# undo: a drawn road comes back off the map the same day
	var streets_before: int = main.world.streets.size()
	var roads_before: int = main.world.projects.size()
	main.act({"kind": "plan_road", "a": n.call(30, 60), "b": n.call(30, 50)})
	var drew: bool = main.world.streets.size() == streets_before + 1
	print("undo: ", main.undo(), " drew ", drew, " back to ", main.world.streets.size() == streets_before and main.world.projects.size() == roads_before)
	if not drew or main.world.streets.size() != streets_before:
		push_error("undo did not restore the town")
	main.autosave()
	var aw: LTWorld = LTWorld.new()
	print("autosave: ", aw.load_from_file(main.AUTOSAVE_PATH) == OK and aw.day == main.world.day)
	for k in main.view.OVERLAYS:
		main.view.set_overlay(k)
	main.view.set_overlay("")
	main.hud.show_profile()
	print("profile: ", main.act({"kind": "set_profile", "name": "Jordan Reyes", "pronouns": "she", "age": 45, "hometown": "Mitchell", "color": "green", "town_name": "Prairie Rose"})["message"], " | ", main.world.player["name"], ", ", main.world.player_age(), ", ", main.world.player_pronoun("subject"), ", ", main.world.city["name"])
	main.hud._tab_mayor()
	main.view.refresh_all()
	print("lots: ", main.act({"kind": "edit_lots", "lots": [2, 3], "changes": {"price_pct": 75, "hold": false}})["message"])
	main.hud.inspect("lot", 2)
	main.view.select_road(1)
	main.view.focus_street(1)
	print("street level sound: ", main.view.street_level(), " at distance ", main.view.dist)
	print("unplot: ", main.act({"kind": "unplot", "lot": 1})["message"])
	main.view.focus_lot(0)
	for i in 30:
		main._advance(1)
	main.view.animate(0.5, 12.0, false)
	print("match: ", main.match_real_time())
	main.set_speed(0)
	main.new_town(20261120)
	await process_frame
	main.world.city["laws"]["bank_charter"] = 1.0
	main.act({"kind": "annex"})
	main.view.rebuild()
	main.act({"kind": "set_law", "law": "bus_service", "value": 1})
	main.act({"kind": "issue_bond", "amount": 10000000})
	main.act({"kind": "elections", "on": true})
	for i in 60:
		main._advance(1)
	main.view.animate(0.016, 8.0, true)
	main.view.animate(0.016, 17.5, true)
	var hud: Node = main.hud
	for t in hud.TABS.size():
		hud.tabs.current_tab = t
		hud.refresh_tab()
		await process_frame
	var w: LTWorld = main.world
	var shown: int = 0
	for c in w.citizens.slice(0, 40):
		hud.inspect("sim", int(c["id"]))
		shown += 1
	for b in w.businesses:
		hud.inspect("biz", int(b["id"]))
	for l in w.lots:
		hud.inspect("lot", int(l["id"]))
	for p in w.petitions:
		hud.inspect("pet", int(p["id"]))
	for p in w.projects:
		hud.inspect("proj", int(p["id"]))
	for d in w.debts.slice(0, 30):
		hud.inspect("debt", int(d["id"]))
	main.focus_sim(0)
	main.focus_lot(w.lots.size() - 1)
	hud.show_interrupt(w.chronicle.slice(maxi(0, w.chronicle.size() - 3)))
	print("UI SMOKE OK: day %d, %d Sims inspected, %d lots, newspaper editions %d, ledger %s" % [w.day, shown, w.lots.size(), w.city["newspapers"].size(), w.ledger.audit()["ok"]])
	quit(0)
