class_name LTMayorAI
## The Sim mayor: in autonomous mode a random Sim (made from a mayor seed) wins the
## lottery, founds the town and makes every decision the player would, from their
## own personality. Every choice goes through the same mayor actions the player
## uses, so it is logged, replayable and saved like the player's, and each one is
## written in the town chronicle with the reason.
##
## Personality steers everything:
## - honesty and sociability: hold elections or rule for good; pick quality bids
## - greed: high lot prices and taxes, cheapest contracts, gold mining
## - kindness: low prices, generous services, saying yes to petitions
## - ambition and risk: build big and early, borrow, sidewalks and streetlights
## - discipline: alleys, budgets kept balanced, standard materials

const PLACES: Array = ["Sioux Falls", "Rapid City", "Mitchell", "Aberdeen", "Pierre", "Yankton", "Huron", "Brookings", "Watertown", "Spearfish"]


static func is_on(w: LTWorld) -> bool:
	return bool(w.mode.get("autonomous", false)) and not bool(w.player.get("player_took_over", false))


## A founder from the mayor seed: the same seed always makes the same person.
static func make_persona(mayor_seed: int) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = mayor_seed
	var female: bool = rng.randf() < 0.5
	var first: String = (LTPeople.FEMALE_FIRST if female else LTPeople.MALE_FIRST)[rng.randi_range(0, 35)]
	var last: String = LTPeople.LAST_NAMES[rng.randi_range(0, LTPeople.LAST_NAMES.size() - 1)]
	var traits: Dictionary = {}
	for k in ["ambition", "risk", "discipline", "honesty", "sociability", "intelligence", "greed", "kindness"]:
		traits[k] = clampi(int(round(rng.randfn(50.0, 20.0))), 5, 95)
	return {
		"name": "%s %s" % [first, last], "pronouns": "she" if female else "he",
		"age": rng.randi_range(28, 66), "hometown": PLACES[rng.randi_range(0, PLACES.size() - 1)],
		"traits": traits, "mayor_seed": mayor_seed,
		"elections": float(traits["honesty"] + traits["sociability"]) / 2.0 + rng.randf_range(-10.0, 10.0) > 55.0,
	}


## A sentence about who the Sim mayor is.
static func describe(p: Dictionary) -> String:
	var t: Dictionary = p.get("traits", {})
	if t.is_empty():
		return ""
	var words: Array = []
	var pairs: Array = [["ambition", "ambitious", "content"], ["risk", "a gambler", "cautious"], ["discipline", "orderly", "easygoing"], ["honesty", "honest", "slippery"], ["kindness", "kind", "hard nosed"], ["greed", "greedy", "generous"], ["sociability", "outgoing", "private"]]
	for pr in pairs:
		var v: int = int(t[pr[0]])
		if v >= 65:
			words.append(pr[1])
		elif v <= 35:
			words.append(pr[2])
	if words.is_empty():
		words.append("even tempered")
	return ", ".join(words)


static func _say(w: LTWorld, text: String) -> void:
	w.chronicle_add("Mayor %s %s" % [w.player["name"], text], "city", true, [])


static func _act(w: LTWorld, a: Dictionary) -> Dictionary:
	a["sim_mayor"] = true
	return w.apply_action(a)


static func daily(w: LTWorld) -> void:
	if not is_on(w):
		return
	var t: Dictionary = w.player.get("traits", {})
	if t.is_empty():
		return
	if w.day % 7 == 3:
		_plan_town(w, t)
		_contracts(w, t)
		_answer_petitions(w, t)
		_variances(w, t)
		_plats(w, t)
		_mayors_house(w, t)
		_depot(w, t)
	if w.day % 7 == 5:
		_award(w, t)
	if LTCalendar.day_of_month(w.day) == 6:
		_budget(w, t)
		_needs(w, t)
		_lot_prices(w, t)


# ---------------------------------------------------------------- laying out the town

static func _plan(w: LTWorld) -> Dictionary:
	if not w.player.has("plan"):
		w.player["plan"] = {"i0": -1, "blocks": 0, "side": -1}
	return w.player["plan"]


## The town grows a block at a time north (or south) of the county road along Main
## Street: a cross street every 100 meters, an alley down each block if the mayor
## likes order, and lots along them, storefronts on the county road.
static func _plan_town(w: LTWorld, t: Dictionary) -> void:
	if not bool(w.config.get("open_land", false)):
		return
	var pl: Dictionary = _plan(w)
	var jm: int = LTGeography.MAP_ROWS / 2
	var cash: int = w.ledger.bal("city")
	var for_sale: int = 0
	for l in w.lots:
		if str(l["use"]) == "empty" and str(l["owner_kind"]) == "city" and str(l["zone"]) == "residential" and not bool(l.get("removed", false)):
			for_sale += 1
	var want_more: bool = int(pl["blocks"]) == 0 or (for_sale < 4 and cash > LTMoney.dollars(250000.0 if float(t["risk"]) < 50.0 else 150000.0))
	if not want_more or int(pl["blocks"]) >= 6:
		return
	if int(pl["i0"]) < 0:
		# Main Street starts where the land is open, on the side with room
		for side in [-1, 1]:
			for shift in [0, 10, -10, 20, -20]:
				var i0: int = LTGeography.MAP_COLS / 2 + shift
				var ok: bool = true
				for k in 21:
					var rc: Dictionary = LTTerrain.road_cost(w, Vector2(float(i0) * 10.0, float(jm + side * k) * 10.0), Vector2(float(i0) * 10.0, float(jm + side * (k + 1)) * 10.0))
					if not bool(rc["ok"]) or str(rc["kind"]) == "bridge":
						ok = false
						break
				if ok:
					pl["i0"] = i0
					pl["side"] = side
					break
			if int(pl["i0"]) >= 0:
				break
		if int(pl["i0"]) < 0:
			pl["i0"] = LTGeography.MAP_COLS / 2
			pl["side"] = -1
	var i0b: int = int(pl["i0"])
	var sd: int = int(pl["side"])
	var k: int = int(pl["blocks"]) + 1
	var j_prev: int = jm + sd * (k - 1) * 10
	var j_new: int = jm + sd * k * 10
	var n: Callable = func(i, j): return LTGeography.node_id(w, i, j)
	var made: Array = []
	var r1: Dictionary = _act(w, {"kind": "plan_road", "a": n.call(i0b, j_prev), "b": n.call(i0b, j_new)})
	if bool(r1.get("ok", false)):
		made.append(r1)
	var width_blocks: int = 2 if float(t["ambition"]) > 60.0 else 1
	var r2: Dictionary = _act(w, {"kind": "plan_road", "a": n.call(i0b - width_blocks * 10, j_new), "b": n.call(i0b + width_blocks * 10, j_new)})
	if bool(r2.get("ok", false)):
		made.append(r2)
	var alleys: bool = float(t["discipline"]) > 50.0
	var j_alley: int = j_prev + sd * 5
	if alleys:
		var ra: Dictionary = _act(w, {"kind": "plan_road", "a": n.call(i0b - width_blocks * 10, j_alley), "b": n.call(i0b + width_blocks * 10, j_alley), "road_kind": "alley"})
		if bool(ra.get("ok", false)):
			made.append(ra)
	pl["blocks"] = k
	# lots: storefronts on the county road in the first block, homes after
	var lot_w: float = 15.0 if float(t["greed"]) > 65.0 else (25.0 if float(t["kindness"]) > 60.0 or float(t["ambition"]) > 65.0 else 20.0)
	var x_lo: float = float(i0b - width_blocks * 10) * 10.0
	var x_hi: float = float(i0b + width_blocks * 10) * 10.0
	var depth: float = 39.0 if alleys else 42.0
	var z_new: float = float(j_new) * 10.0
	var z_prev: float = float(j_prev) * 10.0
	# the side of the new street facing the older block, and the side facing out
	var inner_z0: float = z_new + 7.5 if sd < 0 else z_new - 7.5 - depth
	var inner_z1: float = inner_z0 + depth
	var outer_z0: float = z_new - 7.5 - depth if sd < 0 else z_new + 7.5
	for seg in [[x_lo, float(i0b) * 10.0 - 7.5], [float(i0b) * 10.0 + 7.5, x_hi]]:
		_act(w, {"kind": "plot_lots", "x0": seg[0], "z0": inner_z0, "x1": seg[1], "z1": inner_z1, "zone": "residential", "width": lot_w})
		_act(w, {"kind": "plot_lots", "x0": seg[0], "z0": outer_z0, "x1": seg[1], "z1": outer_z0 + depth, "zone": "residential", "width": lot_w})
		if k == 1:
			var hz0: float = z_prev - 8.0 - 39.0 if sd < 0 else z_prev + 8.0
			_act(w, {"kind": "plot_lots", "x0": seg[0], "z0": hz0, "x1": seg[1], "z1": hz0 + 39.0, "zone": "commercial", "width": 12.0})
	var why: String = "lots are running out" if k > 1 else "a town needs a Main Street"
	_say(w, "drew %s and plotted lots %d meters wide. Reason: %s." % ["Main Street, a cross street%s" % (" and an alley" if alleys else "") if k == 1 else "another block%s" % (" with an alley" if alleys else ""), int(lot_w), why])


# ---------------------------------------------------------------- contracts

## Writes each draft's terms from personality and sends it out to bid.
static func _contracts(w: LTWorld, t: Dictionary) -> void:
	for p in w.projects:
		if str(p["status"]) != "draft" or bool(p["private"]):
			continue
		var ch: Dictionary = {}
		if str(p["ptype"]) == "road_build" and str(w.streets[int(p["street"])]["kind"]) != "alley":
			if float(t["greed"]) > 65.0 and float(t["kindness"]) < 50.0:
				ch["surface"] = "gravel"
			elif float(t["ambition"]) > 65.0 and float(t["discipline"]) > 55.0:
				ch["surface"] = "concrete"
			ch["sidewalks"] = float(t["kindness"]) + float(t["ambition"]) > 115.0
			ch["lights"] = float(t["kindness"]) > 60.0 or float(t["ambition"]) > 70.0
		elif p.has("spec") and p["spec"].has("grade"):
			ch["grade"] = "premium" if float(t["ambition"]) > 70.0 else ("budget" if float(t["greed"]) > 70.0 else "standard")
		if not ch.is_empty():
			_act(w, {"kind": "edit_project", "project_id": int(p["id"]), "changes": ch})
		var r: Dictionary = _act(w, {"kind": "go_live", "project_id": int(p["id"])})
		if bool(r.get("ok", false)):
			_say(w, "sent \"%s\" out to bid: %s." % [p["title"], LTProjects.spec_text(p)])


## Picks a bid: the careful and honest weigh quality and record; the greedy take
## the cheapest. Waits if the city cannot afford any of them.
static func _award(w: LTWorld, t: Dictionary) -> void:
	for p in w.projects:
		if str(p["status"]) != "review" or bool(p["private"]):
			continue
		var quality_w: float = (float(t["honesty"]) + float(t["discipline"]) - float(t["greed"])) / 100.0
		var best: int = -1
		var best_s: float = -1e18
		var cash: int = w.ledger.bal("city")
		for i in p["bids"].size():
			var b: Dictionary = p["bids"][i]
			if int(b["price"]) > int(p["ceiling"]) or int(b["price"]) > cash + LTMoney.dollars(5000.0):
				continue
			var grade: float = {"A": 1.0, "B": 0.8, "C": 0.6, "D": 0.4, "F": 0.2, "new": 0.55}.get(str(b["grade"]), 0.5)
			var s: float = -float(b["price"]) / float(maxi(1, int(p["ceiling"]))) + grade * maxf(0.0, quality_w) + (0.1 if bool(b["local"]) and float(t["kindness"]) > 50.0 else 0.0)
			if s > best_s:
				best_s = s
				best = i
		if best < 0:
			if cash < int(p["ceiling"]) / 2 and float(t["risk"]) > 45.0 and w.day - int(p.get("bid_close_day", 0)) > 20:
				var r0: Dictionary = _act(w, {"kind": "city_borrow", "amount": int(p["ceiling"]), "purpose": str(p["title"])})
				if bool(r0.get("ok", false)):
					_say(w, "borrowed for \"%s\". Reason: the town needs it and waiting costs more." % p["title"])
			continue
		var bid: Dictionary = p["bids"][best]
		var r: Dictionary = _act(w, {"kind": "award_bid", "project_id": int(p["id"]), "bid_index": best})
		if bool(r.get("ok", false)):
			_say(w, "awarded \"%s\" to %s for %s. Reason: %s." % [p["title"], bid["name"], LTMoney.fmt(int(bid["price"])), "the best work for the money" if quality_w > 0.3 else "the lowest price"])


static func _mayors_house(w: LTWorld, t: Dictionary) -> void:
	if int(w.player.get("home_lot", -1)) >= 0:
		return
	for p in w.projects:
		if str(p["ptype"]) == "mayor_house" and str(p["status"]) != "cancelled":
			return
	var need: int = LTMoney.dollars(450000.0 if float(t["discipline"]) > 50.0 else 300000.0)
	if w.ledger.bal("city") < need or int(_plan(w)["blocks"]) < 1:
		return
	var lot: int = -1
	for l in w.lots:
		if str(l["use"]) == "empty" and str(l["owner_kind"]) == "city" and str(l["zone"]) == "residential":
			lot = int(l["id"])
			break
	if lot < 0:
		return
	var r: Dictionary = _act(w, {"kind": "define_project", "ptype": "mayor_house", "target": lot})
	if bool(r.get("ok", false)):
		_say(w, "decided to build a house for the mayor on %s. Reason: the camper gets old." % LTGeography.lot_label(w, lot))


## The railroad, step by step: ask for an agreement once the town ships enough to
## be worth it, apply for state aid, then build the public loading track. If the
## railroad wants to abandon the line, ask the state to buy it.
static func _depot(w: LTWorld, t: Dictionary) -> void:
	if LTTerrain.t(w).is_empty() or not bool(w.city.get("incorporated", true)):
		return
	var rr: Dictionary = LTRail.r(w)
	var cars0: float = LTRail.expected_cars(w)
	if not LTTerrain.has(w, "rail"):
		var nl: Dictionary = rr["new_line"]
		if str(nl.get("status", "")) == "share" and w.ledger.bal("city") > int(nl["share"]) + LTMoney.dollars(200000.0) and float(t["ambition"]) > 45.0:
			if bool(_act(w, {"kind": "rail_share"}).get("ok", false)):
				_say(w, "paid the town's share of a new branch line. Reason: shipping by rail keeps the farms and mills here.")
		elif (nl.is_empty() or str(nl.get("status", "")) == "declined" and w.day - int(nl["day"]) >= 365) and cars0 >= LTRail.CARS_SHARED * 0.8:
			if bool(_act(w, {"kind": "rail_new_line"}).get("ok", false)):
				_say(w, "asked a railroad to build a branch line to town. Reason: the town's shippers could load about %d cars a year." % int(cars0))
		return
	# a passenger stop when enough people would ride
	if LTRail.has_line(w) and not bool(rr["pax_ok"]) and str(rr["pax"].get("status", "")) != "asked" and LTRail.expected_riders(w) >= int(float(LTRail.RIDERS_NEEDED) * 0.9):
		if str(rr["pax"].get("status", "")) != "declined" or w.day - int(rr["pax"]["day"]) >= 365:
			if bool(_act(w, {"kind": "rail_stop"}).get("ok", false)):
				_say(w, "asked the passenger trains to stop here. Reason: about %d riders a year would bring visitors to town." % LTRail.expected_riders(w))
	if bool(rr["pax_ok"]) and not LTRail.has_station(w) and w.ledger.bal("city") > LTRail.STATION_COST + LTMoney.dollars(150000.0):
		var busy: bool = false
		for p in w.projects:
			if str(p["ptype"]) == "station" and not ["cancelled", "done"].has(str(p["status"])):
				busy = true
		if not busy:
			for l in w.lots:
				if str(l["use"]) == "empty" and str(l["owner_kind"]) == "city" and LTRail.station_lot_ok(w, l) == "":
					if not ["civic", "mixed", "industrial", "commercial"].has(str(l["zone"])):
						_act(w, {"kind": "zone_lot", "lot": int(l["id"]), "zone": "civic"})
					if bool(_act(w, {"kind": "define_project", "ptype": "station", "target": int(l["id"])}).get("ok", false)):
						_say(w, "put a passenger station out to bid on %s. Reason: the trains will stop once it is built." % LTGeography.lot_label(w, int(l["id"])))
					break
	if int(rr["abandon_day"]) >= 0 and rr["state_request"].is_empty():
		if bool(_act(w, {"kind": "rail_state"}).get("ok", false)):
			_say(w, "asked the state to buy the branch line. Reason: the town's farms and mills need the railroad.")
		return
	if not LTRail.has_line(w) or LTRail.has_depot(w):
		return
	var cars: float = LTRail.expected_cars(w)
	if str(rr["agreement"]) != "signed":
		if cars >= LTRail.CARS_FOR_AGREEMENT * 0.8 and rr["request"].is_empty() and bool(_act(w, {"kind": "rail_request"}).get("ok", false)):
			_say(w, "asked the railroad for an agreement to build a public loading track. Reason: the town's shippers could load about %d cars a year." % int(cars))
		return
	if int(rr["grant_amt"]) == 0 and (rr["grant"].is_empty() or str(rr["grant"].get("status", "")) == "denied" and w.day - int(rr["grant"]["day"]) >= 365):
		if bool(_act(w, {"kind": "rail_grant"}).get("ok", false)):
			_say(w, "applied for state rail aid. Reason: the state can pay up to half.")
		return
	if not rr["grant"].is_empty() and str(rr["grant"].get("status", "")) == "pending" and float(t["discipline"]) > 45.0:
		return
	for p in w.projects:
		if str(p["ptype"]) == "depot" and not ["cancelled", "done"].has(str(p["status"])):
			return
	if w.ledger.bal("city") < LTRail.DEPOT_COST - int(rr["grant_amt"]) + LTMoney.dollars(150000.0):
		return
	for l in w.lots:
		if str(l["use"]) == "empty" and str(l["owner_kind"]) == "city" and LTRail.depot_lot_ok(w, l) == "":
			if not ["civic", "mixed", "industrial", "commercial"].has(str(l["zone"])):
				_act(w, {"kind": "zone_lot", "lot": int(l["id"]), "zone": "civic"})
			var r: Dictionary = _act(w, {"kind": "define_project", "ptype": "depot", "target": int(l["id"])})
			if bool(r.get("ok", false)):
				_say(w, "put a public rail loading track out to bid on %s. Reason: shippers without their own spur can load cars there, and the city earns a fee on every car." % LTGeography.lot_label(w, int(l["id"])))
			return


# ---------------------------------------------------------------- the people

static func _answer_petitions(w: LTWorld, t: Dictionary) -> void:
	for p in w.petitions:
		if str(p["status"]) != "submitted":
			continue
		var kind: String = str(p["kind"])
		var civic: bool = bool(LTCivic.PETITION_KINDS[kind]["civic"])
		var cost: int = LTCivic.petition_cost_estimate(w, p)
		var cash: int = w.ledger.bal("city")
		var yes: float = float(t["kindness"]) * 0.6 + float(t["sociability"]) * 0.3 - float(t["greed"]) * 0.3 + (20.0 if bool(w.city.get("elections", false)) else 0.0)
		if civic and cost > cash:
			yes -= 30.0 if float(t["risk"]) < 60.0 else 10.0
		var r: Dictionary = {}
		if yes >= 25.0 and civic:
			for resp in (["approve", "approve_smaller"] if cost <= cash or float(t["risk"]) > 55.0 else ["approve_smaller"]):
				r = _act(w, {"kind": "respond_petition", "petition_id": int(p["id"]), "response": resp})
				if not bool(r.get("ok", false)) and kind != "road":
					# the signers' spot is not zoned for it: rezone an empty city lot and build there
					var zone: String = "park" if kind == "park" else "civic"
					var own: int = int(p["site"])
					if own >= 0 and bool(_act(w, {"kind": "zone_lot", "lot": own, "zone": zone}).get("ok", false)):
						r = _act(w, {"kind": "respond_petition", "petition_id": int(p["id"]), "response": resp})
					var site: int = -1 if bool(r.get("ok", false)) else _civic_site(w, zone)
					if site >= 0:
						r = _act(w, {"kind": "respond_petition", "petition_id": int(p["id"]), "response": "approve_moved", "lot": site})
				if bool(r.get("ok", false)):
					_say(w, "said yes to \"%s\"%s." % [p["title"], "" if resp == "approve" else ", smaller than asked"])
					break
		elif yes >= 25.0:
			if kind == "housing":
				r = _act(w, {"kind": "respond_petition", "petition_id": int(p["id"]), "response": "approve"})
			else:
				r = _act(w, {"kind": "respond_petition", "petition_id": int(p["id"]), "response": "publish_need", "need": "grocery" if kind == "grocery" else "general_store", "incentives": _incentives(t)})
			if bool(r.get("ok", false)):
				_say(w, "answered \"%s\" by asking for a business to come, with help from the city." % p["title"])
		if not bool(r.get("ok", false)):
			var reason: String = LTCivic.DENY_REASONS[0] if (civic and cost > cash) or yes >= 25.0 else LTCivic.DENY_REASONS[1 if float(t["greed"]) > 60.0 else 3]
			r = _act(w, {"kind": "respond_petition", "petition_id": int(p["id"]), "response": "deny", "reason": reason})
			if bool(r.get("ok", false)):
				_say(w, "said no to \"%s\". Reason: %s." % [p["title"], reason])


static func _civic_site(w: LTWorld, zone: String) -> int:
	for l in w.lots:
		if str(l["use"]) == "empty" and str(l["owner_kind"]) == "city" and not bool(l.get("removed", false)):
			if str(l["zone"]) == zone or str(l["zone"]) == "mixed":
				return int(l["id"])
	for l in w.lots:
		if str(l["use"]) == "empty" and str(l["owner_kind"]) == "city" and not bool(l.get("removed", false)) and LTGeography.lot_area(l) >= 1500.0:
			if bool(_act(w, {"kind": "zone_lot", "lot": int(l["id"]), "zone": zone}).get("ok", false)):
				return int(l["id"])
	return -1


static func _incentives(t: Dictionary) -> Dictionary:
	var inc: Dictionary = {"free_lot": float(t["kindness"]) > 45.0 or float(t["ambition"]) > 60.0}
	if float(t["ambition"]) > 55.0:
		inc["tax_break_years"] = 2
	if float(t["risk"]) > 60.0:
		inc["loan_guarantee"] = true
	if float(t["kindness"]) > 65.0 and float(t["greed"]) < 50.0:
		inc["grant"] = LTMoney.dollars(10000.0)
	return inc


## Once the town has people, the mayor asks for the businesses it lacks.
static func _needs(w: LTWorld, t: Dictionary) -> void:
	if w.residents() < 40 or float(t["ambition"]) < 40.0:
		return
	if w.open_businesses("grocery").is_empty() and LTCivic.open_need_for(w, "grocery").is_empty():
		var r: Dictionary = _act(w, {"kind": "publish_need", "need": "grocery", "incentives": _incentives(t)})
		if bool(r.get("ok", false)):
			_say(w, "asked for a grocery store, offering help to whoever opens one. Reason: people drive too far for food.")


static func _lot_prices(w: LTWorld, t: Dictionary) -> void:
	var pct: int = 100 + int(round((float(t["greed"]) - float(t["kindness"])) / 25.0)) * 25
	pct = clampi(pct, 50, 175)
	var ids: Array = []
	for l in w.lots:
		if str(l["use"]) == "empty" and str(l["owner_kind"]) == "city" and int(l.get("price_pct", 100)) != pct and not bool(l.get("removed", false)):
			ids.append(int(l["id"]))
	if not ids.is_empty():
		_act(w, {"kind": "edit_lots", "lots": ids, "changes": {"price_pct": pct}})


## Taxes and services: keep the books near even, the way this mayor sees it.
static func _budget(w: LTWorld, t: Dictionary) -> void:
	if not bool(w.city.get("incorporated", false)):
		return
	var laws: Dictionary = w.city["laws"]
	var gap: int = int(w.city["income_12m"]) - int(w.city["spend_12m"])
	if gap < 0 and w.ledger.bal("city") < LTMoney.dollars(100000.0):
		if float(t["kindness"]) < 45.0 and float(laws["welfare"]) > 0.2:
			_act(w, {"kind": "set_law", "law": "welfare", "value": float(laws["welfare"]) - 0.1})
			_say(w, "cut unemployment and food support. Reason: the budget is short and %s thinks people should stand on their own." % w.player_pronoun("subject"))
		elif float(laws["property_tax"]) < 0.025:
			_act(w, {"kind": "set_law", "law": "property_tax", "value": float(laws["property_tax"]) + 0.0025})
			_say(w, "raised the property tax. Reason: the town spends more than it takes in.")
	elif gap > LTMoney.dollars(40000.0):
		if float(t["kindness"]) > 55.0 and float(laws["school_funding"]) < 1.5:
			_act(w, {"kind": "set_law", "law": "school_funding", "value": float(laws["school_funding"]) + 0.1})
			_say(w, "put more money into the schools. Reason: the budget has room and the kids come first.")
		elif float(t["greed"]) < 50.0 and float(laws["property_tax"]) > 0.01:
			_act(w, {"kind": "set_law", "law": "property_tax", "value": float(laws["property_tax"]) - 0.0025})
			_say(w, "cut the property tax. Reason: the town takes in more than it needs.")
	# mining: the greedy and bold want the gold, the kind keep the hills quiet
	var want_mining: float = 2.0 if float(t["greed"]) + float(t["risk"]) > 120.0 else (0.0 if float(t["kindness"]) > 70.0 and float(t["greed"]) < 40.0 else 1.0)
	if float(laws.get("mining", 1.0)) != want_mining and LTCalendar.month_index(w.day) == 3:
		_act(w, {"kind": "set_law", "law": "mining", "value": want_mining})
		_say(w, "set mining to %s." % ["banned", "quarries only", "gold mines allowed"][int(want_mining)])


## Zoning exceptions: kind and outgoing mayors bend the rules for families, orderly
## ones hold the line, and everyone listens to the neighbors.
static func _variances(w: LTWorld, t: Dictionary) -> void:
	for v in LTHomes.pending_variances(w):
		var score: float = float(t["kindness"]) * 0.5 + float(t["sociability"]) * 0.3 - float(t["discipline"]) * 0.4 + float(int(v["for"]) - int(v["against"])) * 12.0 + 10.0
		var yes: bool = score > 20.0
		var r: Dictionary = _act(w, {"kind": "decide_variance", "variance_id": int(v["id"]), "approve": yes})
		if bool(r.get("ok", false)):
			_say(w, "%s the %s family's variance to %s. Reason: %s." % ["granted" if yes else "denied", v["family"], v["want"]["label"], ("the family needs it and the neighbors can live with it" if int(v["against"]) == 0 else "the family's need outweighs the neighbors' worries") if yes else ("the rules are there for everyone" if int(v["against"]) == 0 else "the neighbors objected")])


## Lot splits: growth-minded mayors like more lots on the tax roll; orderly ones
## listen when neighbors object.
static func _plats(w: LTWorld, t: Dictionary) -> void:
	for p in LTLand.pending_plats(w):
		var score: float = float(t["ambition"]) * 0.4 + float(t["greed"]) * 0.2 + float(t["kindness"]) * 0.2 - float(t["discipline"]) * 0.2 + float(int(p["for"]) - int(p["against"]) * 2) * 10.0
		var yes: bool = score > 18.0
		var r: Dictionary = _act(w, {"kind": "decide_plat", "plat_id": int(p["id"]), "approve": yes})
		if bool(r.get("ok", false)):
			_say(w, "%s the request to split lot %d. Reason: %s." % ["approved" if yes else "denied", int(p["lot"]), "more lots mean more homes and more taxes" if yes else ("the neighbors objected" if int(p["against"]) > 0 else "the block should stay as it was planned")])
