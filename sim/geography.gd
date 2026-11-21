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
			})


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
	return int(l["row"]) * (cols + 1) + int(l["col"])


static func exit_node(w: LTWorld) -> int:
	return int(w.config["exit_node"])


static func segment_minutes(w: LTWorld, s: Dictionary) -> float:
	var cond: float = float(s["condition"])
	var m: float = SEGMENT_MINUTES * (1.0 + (100.0 - cond) / 100.0 * 0.9)
	match w.weather:
		"Snow":
			m *= 1.6
		"Storm":
			m *= 1.4
		"Rain":
			m *= 1.1
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
	var src: int = lot_access_node(w, from_lot) if from_lot >= 0 else exit_node(w)
	var dst: int = lot_access_node(w, to_lot) if to_lot >= 0 else exit_node(w)
	var extra: float = 0.0
	if from_lot < 0 or to_lot < 0:
		extra = float(w.config["next_town_minutes"]) * (1.5 if w.weather == "Snow" else 1.0)
	if src == dst:
		return 2.0 + extra
	var dist: Dictionary = node_distances(w, src)
	return float(dist.get(dst, 999.0)) * weather_factor(w) + 2.0 + extra


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
		})
	w.config["lot_rows"] = rows + 1
	w.dist_cache.clear()
	w.chronicle_add("The city bought %d lots of farmland from the county for %s. The %s has a gravel road, %s, until a contractor paves it. Zone the lots to open them up." % [cols, LTMoney.fmt(cost), dname, sname], "city", true, [])
	return {"ok": true, "message": "Annexed %s: %d new lots. Zone them, and put %s out to bid to pave it." % [dname, cols, sname]}


static func lot_label(w: LTWorld, lot_id: int) -> String:
	if lot_id < 0:
		return "no lot"
	var l: Dictionary = w.lot(lot_id)
	return "Lot %d (%s, %s)" % [lot_id, lot_street(w, lot_id)["name"], l["zone"]]


static func roll_weather(w: LTWorld) -> void:
	var s: String = LTCalendar.season(w.day)
	var r: float = w.rng.randf()
	match s:
		"Winter":
			w.weather = "Clear" if r < 0.45 else ("Snow" if r < 0.78 else ("Rain" if r < 0.9 else "Storm"))
		"Spring":
			w.weather = "Clear" if r < 0.5 else ("Rain" if r < 0.9 else "Storm")
		"Summer":
			w.weather = "Clear" if r < 0.7 else ("Rain" if r < 0.9 else "Storm")
		_:
			w.weather = "Clear" if r < 0.55 else ("Rain" if r < 0.9 else "Storm")


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
		var q: float = float(s["quality"])
		var rate: float = 0.02 + (1.0 - q) * (1.0 - q) * 0.22
		s["condition"] = maxf(0.0, float(s["condition"]) - rate * wx)


static func street_condition(w: LTWorld, street_id: int) -> float:
	var st: Dictionary = w.streets[street_id]
	var t: float = 0.0
	for sid in st["segments"]:
		t += float(w.roads[int(sid)]["condition"])
	return t / maxf(1.0, float(st["segments"].size()))


static func street_quality(w: LTWorld, street_id: int) -> float:
	var st: Dictionary = w.streets[street_id]
	var t: float = 0.0
	for sid in st["segments"]:
		t += float(w.roads[int(sid)]["quality"])
	return t / maxf(1.0, float(st["segments"].size()))


static func vacant_lots(w: LTWorld, zones: Array) -> Array:
	var out: Array = []
	for l in w.lots:
		if str(l["use"]) == "empty" and zones.has(str(l["zone"])):
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
			if str(l["use"]) == "empty" and not reserved.has(int(l["id"])):
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
