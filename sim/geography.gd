class_name LTGeography
extends RefCounted
## Lots, the road graph, travel time, and weather.

const ZONES: Array = ["residential", "commercial", "industrial", "agricultural", "civic", "park", "mixed", "none"]
const STREET_NAMES: Array = ["Prairie Street", "Main Street", "Elm Street", "Mill Street", "River Road", "Oak Street", "Depot Street", "Lake Street"]
const AVENUE_NAMES: Array = ["1st Avenue", "2nd Avenue", "3rd Avenue", "4th Avenue", "5th Avenue", "6th Avenue", "7th Avenue", "8th Avenue", "9th Avenue", "10th Avenue"]
const SEGMENT_MINUTES: float = 1.5


static func build(w: LTWorld) -> void:
	var cols: int = int(w.config["lot_cols"])
	var rows: int = int(w.config["lot_rows"])
	w.config["map_cols"] = cols
	w.config["map_rows"] = rows
	w.config["lot_at"] = {}
	# road nodes on the corners of lots
	for j in rows + 1:
		for i in cols + 1:
			w.road_nodes.append({"id": w.road_nodes.size(), "x": i, "y": j, "edges": []})
	for j in rows + 1:
		var street: Dictionary = {"id": w.streets.size(), "name": STREET_NAMES[j % STREET_NAMES.size()], "segments": [], "kind": "street"}
		for i in cols:
			street["segments"].append(_add_segment(w, j * (cols + 1) + i, j * (cols + 1) + i + 1, street["id"]))
		w.streets.append(street)
	w.config["row_streets"] = range(rows + 1)
	w.config["avenue_base"] = w.streets.size()
	w.config["exit_node"] = (rows / 2) * (cols + 1)
	w.config["districts"] = [{"name": "Old Town", "rows": [0, rows - 1]}]
	for i in cols + 1:
		var ave: Dictionary = {"id": w.streets.size(), "name": AVENUE_NAMES[i % AVENUE_NAMES.size()], "segments": [], "kind": "avenue"}
		for j in rows:
			ave["segments"].append(_add_segment(w, j * (cols + 1) + i, (j + 1) * (cols + 1) + i, ave["id"]))
		w.streets.append(ave)
	# starting roads are old county roads in mixed shape
	for s in w.roads:
		if bool(s.get("planned", false)) or bool(s.get("removed", false)):
			continue
		s["condition"] = w.rng.randf_range(45.0, 85.0)
		s["quality"] = w.rng.randf_range(0.45, 0.7)
	# Main Street is the worst, the county never fixed it
	for sid in w.streets[1]["segments"]:
		w.roads[int(sid)]["condition"] = w.rng.randf_range(38.0, 52.0)
		w.roads[int(sid)]["quality"] = 0.45
	# lots
	var layout: Array = _starting_layout(cols, rows)
	for r in rows:
		for c in cols:
			var id: int = w.lots.size()
			var zone: String = layout[r * cols + c]
			w.lots.append({
				"id": id, "col": c, "row": r, "zone": zone,
				"use": "empty", "ref": -1, "units": [], "unit_rent": 0,
				"owner_kind": "city", "owner_id": -1,
				"value": land_value(zone), "condition": 80.0,
				"building": "", "built_day": 0, "name": "", "street": r, "district": "Old Town",
				"access_node": r * (cols + 1) + c,
			})
			w.config["lot_at"][cell_key(c, r)] = id


static func _add_segment(w: LTWorld, a: int, b: int, street_id: int) -> int:
	var id: int = w.roads.size()
	w.roads.append({"id": id, "a": a, "b": b, "street": street_id, "condition": 70.0, "quality": 0.55, "last_project": -1, "repaired_day": 0})
	w.road_nodes[a]["edges"].append(id)
	w.road_nodes[b]["edges"].append(id)
	return id


static func _starting_layout(cols: int, rows: int) -> Array:
	# scales with the map: the top half is homes, then shops and civic land, farmland at the edge
	var res_rows: int = maxi(2, rows / 2)
	var ag_n: int = maxi(1, cols / 2)
	var out: Array = []
	for r in rows:
		for c in cols:
			var z: String = "residential"
			if r >= res_rows:
				if r == rows - 1 and c < ag_n:
					z = "agricultural"
				elif r == res_rows and c >= cols - 2:
					z = "civic"
				elif r == rows - 1 and c == ag_n:
					z = "park"
				else:
					z = "commercial"
			out.append(z)
	return out


static func land_value(zone: String) -> int:
	match zone:
		"commercial", "mixed":
			return LTMoney.dollars(45000.0)
		"agricultural":
			return LTMoney.dollars(60000.0)
		"industrial":
			return LTMoney.dollars(35000.0)
		"residential":
			return LTMoney.dollars(30000.0)
	return LTMoney.dollars(20000.0)


static func lot_access_node(w: LTWorld, lot_id: int) -> int:
	var l: Dictionary = w.lot(lot_id)
	var cols: int = int(w.config["lot_cols"])
	if l.has("access_node"):
		return int(l["access_node"])
	return int(l["row"]) * (cols + 1) + int(l["col"])


static func exit_node(w: LTWorld) -> int:
	return int(w.config["exit_node"])


static func exit_nodes(w: LTWorld) -> Array:
	return w.config.get("exit_nodes", [exit_node(w)])


static func segment_minutes(w: LTWorld, s: Dictionary) -> float:
	var cond: float = float(s["condition"])
	var m: float = SEGMENT_MINUTES * (1.0 + (100.0 - cond) / 100.0 * 0.9)
	var wd: String = str(w.streets[int(s["street"])].get("width", "street"))
	if wd != "street":
		m *= float(LTProjects.WIDTHS[wd]["speed"])
	match w.weather:
		"Snow":
			m *= 1.6
		"Storm":
			m *= 1.4
		"Rain":
			m *= 1.1
	if str(w.region.get("event_today", "")) == "blizzard":
		m *= 2.5
	return m


static func weather_factor(w: LTWorld) -> float:
	match w.weather:
		"Snow":
			return 1.6
		"Storm":
			return 1.4
		"Rain":
			return 1.1
	return 1.0


## Shortest paths on the road graph. Weather slows every road the same, so paths are
## cached by road condition (refreshed weekly or after a road job) and scaled by weather.
static func travel_minutes(w: LTWorld, from_lot: int, to_lot: int) -> float:
	if from_lot < 0 and to_lot < 0:
		return 2.0
	var extra: float = 0.0
	if from_lot < 0 or to_lot < 0:
		extra = float(w.config["next_town_minutes"]) * (1.5 if w.weather == "Snow" else 1.0)
		# the nearest way out of town: any end of the county road
		var lot_id: int = to_lot if from_lot < 0 else from_lot
		var a: int = lot_access_node(w, lot_id)
		var best: float = 1e9
		var dist0: Dictionary = node_distances(w, a)
		for ex in exit_nodes(w):
			if int(ex) == a:
				best = 0.0
			best = minf(best, float(dist0.get(int(ex), 1e9)))
		if best >= 1e8:
			return 999.0
		return best * weather_factor(w) + 2.0 + extra
	var src: int = lot_access_node(w, from_lot)
	var dst: int = lot_access_node(w, to_lot)
	if src == dst:
		return 2.0
	var dist: Dictionary = node_distances(w, src)
	if not dist.has(dst):
		return 999.0
	return float(dist[dst]) * weather_factor(w) + 2.0


## Is the lot connected to the outside world by built road?
static func connected(w: LTWorld, lot_id: int) -> bool:
	return travel_minutes(w, lot_id, -1) < 500.0


static func node_distances(w: LTWorld, src: int) -> Dictionary:
	var cache: Dictionary = w.dist_cache
	if cache.has(src):
		return cache[src]
	var n_nodes: int = w.road_nodes.size()
	var dist: Array = []
	dist.resize(n_nodes)
	dist.fill(1e18)
	var done: PackedByteArray = PackedByteArray()
	done.resize(n_nodes)
	dist[src] = 0.0
	var heap: Array = [[0.0, src]]
	while not heap.is_empty():
		var top: Array = _heap_pop(heap)
		var n: int = int(top[1])
		if done[n] == 1:
			continue
		done[n] = 1
		for sid in w.road_nodes[n]["edges"]:
			var s: Dictionary = w.roads[int(sid)]
			var other: int = int(s["b"]) if int(s["a"]) == n else int(s["a"])
			if done[other] == 1:
				continue
			var cond: float = float(s["condition"])
			var nd: float = float(dist[n]) + SEGMENT_MINUTES * (1.0 + (100.0 - cond) / 100.0 * 0.9)
			if nd < float(dist[other]):
				dist[other] = nd
				_heap_push(heap, [nd, other])
	var out: Dictionary = {}
	for i in n_nodes:
		if float(dist[i]) < 1e17:
			out[i] = dist[i]
	cache[src] = out
	return out


static func _heap_push(h: Array, item: Array) -> void:
	h.append(item)
	var i: int = h.size() - 1
	while i > 0:
		var p: int = (i - 1) / 2
		if float(h[p][0]) <= float(h[i][0]):
			break
		var t: Array = h[p]
		h[p] = h[i]
		h[i] = t
		i = p


static func _heap_pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if h.is_empty():
		return top
	h[0] = last
	var i: int = 0
	var n: int = h.size()
	while true:
		var l: int = i * 2 + 1
		var r: int = l + 1
		var m: int = i
		if l < n and float(h[l][0]) < float(h[m][0]):
			m = l
		if r < n and float(h[r][0]) < float(h[m][0]):
			m = r
		if m == i:
			break
		var t: Array = h[m]
		h[m] = h[i]
		h[i] = t
		i = m
	return top


static func lot_front_segments(w: LTWorld, lot_id: int) -> Array:
	var l: Dictionary = w.lot(lot_id)
	var cols: int = int(w.config["lot_cols"])
	var street: Dictionary = w.streets[int(l["street"])]
	return [street["segments"][int(l["col"])]] if int(l["col"]) < cols else []


static func lot_street(w: LTWorld, lot_id: int) -> Dictionary:
	return w.streets[int(w.lot(lot_id)["street"])]


static func district(w: LTWorld, lot_id: int) -> String:
	return str(w.lot(lot_id).get("district", "Old Town"))


## The mayor plots new land: the city buys a row of farmland from the county, the
## road graph grows, and the new street is gravel until a contractor paves it.
static func annex_row(w: LTWorld) -> Dictionary:
	var cols: int = int(w.config["lot_cols"])
	var rows: int = int(w.config["lot_rows"])
	var cost: int = cols * LTMoney.dollars(9000.0)
	if w.ledger.bal("city") < cost:
		return {"ok": false, "message": "Buying a new row of %d lots from the county costs %s. The city has %s." % [cols, LTMoney.fmt(cost), LTMoney.fmt(w.ledger.bal("city"))]}
	w.ledger.pay("city", "outside", cost, "land_purchase")
	var j: int = rows + 1
	for i in cols + 1:
		w.road_nodes.append({"id": w.road_nodes.size(), "x": i, "y": j, "edges": []})
	var sname: String = STREET_NAMES[j % STREET_NAMES.size()]
	for st in w.streets:
		if str(st["name"]) == sname:
			sname = "South " + sname
	var street: Dictionary = {"id": w.streets.size(), "name": sname, "segments": [], "kind": "street"}
	for i in cols:
		var sid: int = _add_segment(w, j * (cols + 1) + i, j * (cols + 1) + i + 1, street["id"])
		street["segments"].append(sid)
		w.roads[sid]["condition"] = 18.0
		w.roads[sid]["quality"] = 0.2
	w.streets.append(street)
	for i in cols + 1:
		var ave: Dictionary = w.streets[int(w.config["avenue_base"]) + i]
		var sid2: int = _add_segment(w, (j - 1) * (cols + 1) + i, j * (cols + 1) + i, ave["id"])
		ave["segments"].append(sid2)
		w.roads[sid2]["condition"] = 18.0
		w.roads[sid2]["quality"] = 0.2
	w.config["row_streets"].append(int(street["id"]))
	var dname: String = "South Addition" if w.config["districts"].size() == 1 else "South Addition %d" % w.config["districts"].size()
	w.config["districts"].append({"name": dname, "rows": [rows, rows]})
	var top_street: int = int(w.config["row_streets"][rows])
	for c in cols:
		w.lots.append({
			"id": w.lots.size(), "col": c, "row": rows, "zone": "none",
			"use": "empty", "ref": -1, "units": [], "unit_rent": 0,
			"owner_kind": "city", "owner_id": -1,
			"value": land_value("none"), "condition": 80.0,
			"building": "", "built_day": 0, "name": "", "street": top_street, "district": dname,
			"access_node": rows * (cols + 1) + c,
		})
		w.config["lot_at"][cell_key(c, rows)] = w.lots.size() - 1
	w.config["lot_rows"] = rows + 1
	w.config["map_rows"] = rows + 1
	w.dist_cache.clear()
	w.chronicle_add("The city bought %d lots of farmland from the county for %s. The %s has a gravel road, %s, until a contractor paves it. Zone the lots to open them up." % [cols, LTMoney.fmt(cost), dname, sname], "city", true, [])
	return {"ok": true, "message": "Annexed %s: %d new lots. Zone them, and put %s out to bid to pave it." % [dname, cols, sname]}


static func lot_label(w: LTWorld, lot_id: int) -> String:
	if lot_id < 0:
		return "no lot"
	var l: Dictionary = w.lot(lot_id)
	return "Lot %d (%s, %s)" % [lot_id, lot_street(w, lot_id)["name"], l["zone"]]


static func roll_weather(w: LTWorld) -> void:
	LTHazards.roll_weather(w)


## Daily wear on every road. Low quality roads wear faster, storms and snow add wear.
static func wear_roads(w: LTWorld) -> void:
	var wx: float = 1.0
	if w.weather == "Snow":
		wx = 1.8
	elif w.weather == "Storm":
		wx = 2.2
	elif w.weather == "Rain":
		wx = 1.2
	for s in w.roads:
		if bool(s.get("planned", false)) or bool(s.get("removed", false)):
			continue
		var q: float = float(s["quality"])
		var rate: float = 0.02 + (1.0 - q) * (1.0 - q) * 0.22
		var sf: String = str(w.streets[int(s["street"])].get("surface", "asphalt"))
		if sf != "asphalt":
			rate *= float(LTProjects.SURFACES[sf]["wear"])
		s["condition"] = maxf(0.0, float(s["condition"]) - rate * wx)


static func street_condition(w: LTWorld, street_id: int) -> float:
	var st: Dictionary = w.streets[street_id]
	var t: float = 0.0
	var n: int = 0
	for sid in st["segments"]:
		var sg: Dictionary = w.roads[int(sid)]
		if bool(sg.get("planned", false)) or bool(sg.get("removed", false)):
			continue
		t += float(sg["condition"])
		n += 1
	return 100.0 if n == 0 else t / float(n)


## The share of the town's built streets that have sidewalks or streetlights
## (key "sidewalks" or "lights"). Lit streets feel safer; sidewalks draw families.
static func amenity_share(w: LTWorld, key: String) -> float:
	var ck: String = "amen_" + key
	if int(w.market.get(ck + "_day", -1)) == w.day:
		return float(w.market[ck])
	var have: int = 0
	var n: int = 0
	for st in w.streets:
		if str(st["kind"]) == "highway" or _all_planned(w, st):
			continue
		n += 1
		if bool(st.get(key, false)):
			have += 1
	var v: float = 0.0 if n == 0 else float(have) / float(n)
	w.market[ck + "_day"] = w.day
	w.market[ck] = v
	return v


static func _all_planned(w: LTWorld, st: Dictionary) -> bool:
	for sid in st["segments"]:
		var sg: Dictionary = w.roads[int(sid)]
		if not bool(sg.get("planned", false)) and not bool(sg.get("removed", false)):
			return false
	return true


static func street_quality(w: LTWorld, street_id: int) -> float:
	var st: Dictionary = w.streets[street_id]
	var t: float = 0.0
	var n: int = 0
	for sid in st["segments"]:
		var sg: Dictionary = w.roads[int(sid)]
		if bool(sg.get("planned", false)) or bool(sg.get("removed", false)):
			continue
		t += float(sg["quality"])
		n += 1
	return 1.0 if n == 0 else t / float(n)


static func vacant_lots(w: LTWorld, zones: Array) -> Array:
	var out: Array = []
	for l in w.lots:
		if str(l["use"]) == "empty" and not bool(l.get("hold", false)) and zones.has(str(l["zone"])) and (not bool(w.config.get("open_land", false)) or connected(w, int(l["id"]))):
			out.append(l)
	return out


## Lot that fits a zone and is closest to a set of homes. Used for suggested sites.
static func best_site(w: LTWorld, zones: Array, near_lots: Array) -> int:
	var key: String = "%d|%s|%s" % [w.day, str(zones), str(near_lots)]
	if not w.market.has("site_cache") or int(w.market.get("site_day", -1)) != w.day:
		w.market["site_cache"] = {}
		w.market["site_day"] = w.day
	if w.market["site_cache"].has(key):
		var cached: int = int(w.market["site_cache"][key])
		if cached < 0 or str(w.lot(cached)["use"]) == "empty":
			return cached
	var r: int = _best_site(w, zones, near_lots)
	w.market["site_cache"][key] = r
	return r


static func _best_site(w: LTWorld, zones: Array, near_lots: Array) -> int:
	# the open, unreserved lots of each zone, worked out once a day
	if int(w.market.get("vac_day", -1)) != w.day:
		var reserved: Dictionary = {}
		for n in w.city_needs:
			if str(n["status"]) == "open":
				reserved[int(n["lot"])] = true
		for p in w.projects:
			if not ["cancelled", "done"].has(str(p["status"])):
				reserved[int(p.get("lot", -1))] = true
		var byz: Dictionary = {}
		for l in w.lots:
			if str(l["use"]) == "empty" and not bool(l.get("hold", false)) and not reserved.has(int(l["id"])) and (not bool(w.config.get("open_land", false)) or connected(w, int(l["id"]))):
				if not byz.has(str(l["zone"])):
					byz[str(l["zone"])] = []
				byz[str(l["zone"])].append(l)
		w.market["vac_by_zone"] = byz
		w.market["vac_day"] = w.day
	var byz2: Dictionary = w.market["vac_by_zone"]
	var best: int = -1
	var best_d: float = 1e9
	for z in zones:
		for l in byz2.get(str(z), []):
			if str(l["use"]) != "empty":
				continue
			var d: float = 0.0
			for nl in near_lots:
				if int(nl) < 0:
					continue
				var a2: Dictionary = w.lot(int(nl))
				d += absf(float(a2["col"]) - float(l["col"])) + absf(float(a2["row"]) - float(l["row"]))
			if d < best_d or (d == best_d and int(l["id"]) < best):
				best_d = d
				best = int(l["id"])
	return best



# ================================================================ open land (found a town)
## A founded town starts as open prairie on a survey grid: every grid corner is a
## possible road node, but only the county road exists. The player draws roads
## (which go out to bid and are built by contractors) and plots lots beside them.

const OPEN_COLS: int = 32
const OPEN_ROWS: int = 24
const ROAD_NAMES: Array = ["Main Street", "Elm Street", "Oak Street", "Prairie Avenue", "Mill Road", "Church Street", "School Street", "Park Avenue", "Maple Street", "Depot Road", "Cedar Street", "Lake Road", "Hill Street", "Bluff Road", "Sunset Drive", "Ash Street", "Willow Lane", "Union Street", "Grant Avenue", "Lincoln Street"]


static func cell_key(c: int, r: int) -> int:
	return r * 10000 + c


static func node_id(w: LTWorld, i: int, j: int) -> int:
	return j * (int(w.config["map_cols"]) + 1) + i


static func lot_at(w: LTWorld, c: int, r: int) -> int:
	return int(w.config.get("lot_at", {}).get(cell_key(c, r), -1))


static func build_open(w: LTWorld) -> void:
	var cols: int = OPEN_COLS
	var rows: int = OPEN_ROWS
	w.config["lot_cols"] = cols
	w.config["lot_rows"] = rows
	w.config["map_cols"] = cols
	w.config["map_rows"] = rows
	w.config["lot_at"] = {}
	w.config["open_land"] = true
	w.config["districts"] = [{"name": "Founders' Plat", "rows": [0, rows - 1]}]
	w.config["row_streets"] = []
	w.config["avenue_base"] = 0
	w.config["road_name_i"] = 0
	for j in rows + 1:
		for i in cols + 1:
			w.road_nodes.append({"id": w.road_nodes.size(), "x": i, "y": j, "edges": [], "planned": []})
	# the county road crosses the land edge to edge
	var jm: int = rows / 2
	var hw: Dictionary = {"id": w.streets.size(), "name": "County Road 12", "segments": [], "kind": "highway"}
	w.streets.append(hw)
	for i in cols:
		var sid: int = _add_segment(w, node_id(w, i, jm), node_id(w, i + 1, jm), int(hw["id"]))
		w.roads[sid]["condition"] = w.rng.randf_range(62.0, 75.0)
		w.roads[sid]["quality"] = 0.6
		hw["segments"].append(sid)
	w.config["exit_node"] = node_id(w, 0, jm)
	w.config["exit_nodes"] = [node_id(w, 0, jm), node_id(w, cols, jm)]


## The segment between two neighboring nodes, built or planned, or -1.
static func seg_between(w: LTWorld, a: int, b: int) -> int:
	for key in ["edges", "planned"]:
		for sid in w.road_nodes[a].get(key, []):
			var sg: Dictionary = w.roads[int(sid)]
			if (int(sg["a"]) == a and int(sg["b"]) == b) or (int(sg["a"]) == b and int(sg["b"]) == a):
				return int(sid)
	return -1


## Lays out a straight road between two grid corners. New pieces are planned, not
## built: they become a project for contractors to bid on.
static func plan_road(w: LTWorld, a: int, b: int, draft: bool = false) -> Dictionary:
	var na: Dictionary = w.road_nodes[a]
	var nb: Dictionary = w.road_nodes[b]
	var ax: int = int(na["x"])
	var ay: int = int(na["y"])
	var bx: int = int(nb["x"])
	var by: int = int(nb["y"])
	if ax != bx and ay != by:
		# straight roads only: follow the longer direction
		if absi(bx - ax) >= absi(by - ay):
			by = ay
		else:
			bx = ax
	if ax == bx and ay == by:
		return {"ok": false, "message": "Drag farther to draw a road."}
	var street: Dictionary = {"id": w.streets.size(), "name": _next_road_name(w), "segments": [], "kind": "street"}
	var new_segs: Array = []
	var steps: int = maxi(absi(bx - ax), absi(by - ay))
	var dx: int = signi(bx - ax)
	var dy: int = signi(by - ay)
	for k in steps:
		var p: int = node_id(w, ax + dx * k, ay + dy * k)
		var q: int = node_id(w, ax + dx * (k + 1), ay + dy * (k + 1))
		if seg_between(w, p, q) >= 0:
			continue
		var sid: int = w.roads.size()
		w.roads.append({"id": sid, "a": p, "b": q, "street": int(street["id"]), "condition": 8.0, "quality": 0.0, "last_project": -1, "repaired_day": 0, "planned": true})
		w.road_nodes[p]["planned"].append(sid)
		w.road_nodes[q]["planned"].append(sid)
		street["segments"].append(sid)
		new_segs.append(sid)
	if new_segs.is_empty():
		return {"ok": false, "message": "There is already a road there."}
	w.streets.append(street)
	var r: Dictionary = LTProjects.define_road_build(w, int(street["id"]), new_segs, draft)
	r["street"] = int(street["id"])
	return r


static func _next_road_name(w: LTWorld) -> String:
	var i: int = int(w.config.get("road_name_i", 0))
	w.config["road_name_i"] = i + 1
	var base: String = ROAD_NAMES[i % ROAD_NAMES.size()]
	if i >= ROAD_NAMES.size():
		base = "%s %d" % [base, i / ROAD_NAMES.size() + 1]
	return base


## Builds the planned pieces of a road when a contractor finishes the job.
static func open_segment(w: LTWorld, sid: int, quality: float) -> void:
	var sg: Dictionary = w.roads[sid]
	if not bool(sg.get("planned", false)):
		return
	sg["planned"] = false
	for n in [int(sg["a"]), int(sg["b"])]:
		w.road_nodes[n]["planned"].erase(sid)
		w.road_nodes[n]["edges"].append(sid)
	sg["quality"] = quality
	sg["condition"] = 70.0 + quality * 30.0
	w.dist_cache.clear()


## Removes a planned road that is not under contract yet.
static func cancel_planned(w: LTWorld, street_id: int) -> void:
	for sid in w.streets[street_id]["segments"]:
		var sg: Dictionary = w.roads[int(sid)]
		if bool(sg.get("planned", false)):
			for n in [int(sg["a"]), int(sg["b"])]:
				w.road_nodes[n]["planned"].erase(int(sid))
			sg["removed"] = true


## Marks lots on open land. Each lot must touch a road, built or planned.
static func plot_lots(w: LTWorld, c0: int, r0: int, c1: int, r1: int, zone: String) -> Dictionary:
	if not ZONES.has(zone):
		return {"ok": false, "message": "Unknown zone."}
	var cols: int = int(w.config["map_cols"])
	var rows: int = int(w.config["map_rows"])
	var made: int = 0
	var no_road: int = 0
	var group: int = int(w.config.get("plot_group_i", 0)) + 1
	for r in range(mini(r0, r1), maxi(r0, r1) + 1):
		for c in range(mini(c0, c1), maxi(c0, c1) + 1):
			if c < 0 or r < 0 or c >= cols or r >= rows or lot_at(w, c, r) >= 0:
				continue
			# a road along any side of the cell gives the lot its driveway
			var sides: Array = [[node_id(w, c, r), node_id(w, c + 1, r)], [node_id(w, c, r + 1), node_id(w, c + 1, r + 1)], [node_id(w, c, r), node_id(w, c, r + 1)], [node_id(w, c + 1, r), node_id(w, c + 1, r + 1)]]
			var seg: int = -1
			for sd in sides:
				var sid: int = seg_between(w, int(sd[0]), int(sd[1]))
				if sid >= 0 and (seg < 0 or not bool(w.roads[sid].get("planned", false))):
					seg = sid
			if seg < 0:
				no_road += 1
				continue
			var id: int = w.lots.size()
			w.lots.append({
				"id": id, "col": c, "row": r, "zone": zone,
				"use": "empty", "ref": -1, "units": [], "unit_rent": 0,
				"owner_kind": "city", "owner_id": -1,
				"value": land_value(zone), "condition": 80.0,
				"building": "", "built_day": 0, "name": "", "street": int(w.roads[seg]["street"]),
				"district": str(w.config["districts"][0]["name"]), "access_node": int(w.roads[seg]["a"]),
				"plot_group": group, "price_pct": 100, "hold": false,
			})
			w.config["lot_at"][cell_key(c, r)] = id
			made += 1
	if made == 0:
		return {"ok": false, "message": "No lots plotted. Lots must touch a road, built or planned." if no_road > 0 else "Nothing to plot there."}
	w.config["plot_group_i"] = group
	var msg: String = "Plotted %d %s lot%s. Tap one to set its price and details." % [made, zone, "" if made == 1 else "s"]
	if no_road > 0:
		msg += " %d spots were skipped because no road touches them." % no_road
	return {"ok": true, "message": msg, "plot_group": group}


## The lots plotted in the same stroke, so they can be edited together.
static func plot_group_lots(w: LTWorld, group: int) -> Array:
	var out: Array = []
	if group <= 0:
		return out
	for l in w.lots:
		if int(l.get("plot_group", 0)) == group and not bool(l.get("removed", false)):
			out.append(int(l["id"]))
	return out


## What a buyer pays for a city lot: land value times the mayor's asking price.
static func asking_price(w: LTWorld, lot_id: int) -> int:
	var l: Dictionary = w.lot(lot_id)
	return int(float(l["value"]) * float(l.get("price_pct", 100)) / 100.0)


## The mayor sets the details of city lots that are still empty: zone, asking
## price, whether the city holds them back, and a name.
static func edit_lots(w: LTWorld, ids: Array, changes: Dictionary) -> Dictionary:
	var done: int = 0
	var skipped: int = 0
	for id in ids:
		var l: Dictionary = w.lot(int(id))
		if l.is_empty() or bool(l.get("removed", false)):
			continue
		var mine: bool = str(l["owner_kind"]) == "city" and ["empty", "closed"].has(str(l["use"]))
		if not mine:
			skipped += 1
			continue
		if changes.has("zone") and str(changes["zone"]) != str(l["zone"]):
			LTCivic.zone_lot(w, int(id), str(changes["zone"]))
		if changes.has("price_pct"):
			l["price_pct"] = clampi(int(changes["price_pct"]), 25, 300)
		if changes.has("hold"):
			l["hold"] = bool(changes["hold"])
		if changes.has("name"):
			l["name"] = str(changes["name"]).strip_edges().left(40)
		done += 1
	w.market["vac_day"] = -1
	w.market["site_day"] = -1
	if done == 0:
		return {"ok": false, "message": "Only empty lots the city still owns can be changed."}
	var msg: String = "Updated %d lot%s." % [done, "" if done == 1 else "s"]
	if skipped > 0:
		msg += " %d already sold or built on were left alone." % skipped
	return {"ok": true, "message": msg}


## Takes back an empty lot the city still owns.
static func unplot(w: LTWorld, lot_id: int) -> Dictionary:
	var l: Dictionary = w.lot(lot_id)
	if l.is_empty() or str(l["use"]) != "empty" or str(l["owner_kind"]) != "city" or bool(l.get("removed", false)):
		return {"ok": false, "message": "Only an empty lot the city still owns can be taken back."}
	for n in w.city_needs:
		if int(n["lot"]) == lot_id and str(n["status"]) == "open":
			return {"ok": false, "message": "A published need is waiting on that lot."}
	l["removed"] = true
	l["use"] = "removed"
	w.config["lot_at"].erase(cell_key(int(l["col"]), int(l["row"])))
	return {"ok": true, "message": "Lot %d is open prairie again." % lot_id}
