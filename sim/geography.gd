class_name LTGeography
extends RefCounted
## Lots, the road graph, travel time, and weather.

const ZONES: Array = ["residential", "commercial", "industrial", "agricultural", "civic", "park", "mixed", "none"]
const STREET_NAMES: Array = ["Prairie Street", "Main Street", "Elm Street", "Mill Street", "River Road", "Oak Street", "Depot Street", "Lake Street"]
const AVENUE_NAMES: Array = ["1st Avenue", "2nd Avenue", "3rd Avenue", "4th Avenue", "5th Avenue", "6th Avenue", "7th Avenue", "8th Avenue", "9th Avenue", "10th Avenue"]
## One road segment is one survey step (10 meters). Driving about 40 km/h with
## stops, or walking for part of the trip, comes to about 0.1 minutes per step.
const SEGMENT_MINUTES: float = 0.1

# ---------------------------------------------------------------- the survey
## Everything is in meters. Roads run on a 10 meter survey grid; nodes exist
## only where a road touches the grid. A town block is about 100 meters between
## street centerlines, as in a real Midwest town. Lots are rectangles of any
## size, fronting one road.
const GRID: float = 10.0
const MAP_COLS: int = 160
const MAP_ROWS: int = 120
const BLOCK: int = 10
## half of a road's right of way: paved lanes plus the sidewalk or shoulder
const ROW_HALF: Dictionary = {"street": 7.5, "avenue": 7.5, "alley": 3.0, "highway": 8.0, "lane": 6.0}
## land price per square meter by zone (about $20,000 for a 20 by 40 meter house lot)
const LAND_PER_M2: Dictionary = {"residential": 25.0, "commercial": 55.0, "mixed": 45.0, "industrial": 15.0, "agricultural": 1.6, "civic": 10.0, "park": 8.0, "none": 2.0}


static func node_key(i: int, j: int) -> int:
	return j * (MAP_COLS + 1) + i


## The road node at survey corner (i, j), created if it is not there yet.
static func node_id(w: LTWorld, i: int, j: int) -> int:
	var k: int = node_key(i, j)
	var at: Dictionary = w.config["node_at"]
	if at.has(k):
		return int(at[k])
	var id: int = w.road_nodes.size()
	w.road_nodes.append({"id": id, "x": i, "y": j, "edges": [], "planned": []})
	at[k] = id
	return id


static func find_node(w: LTWorld, i: int, j: int) -> int:
	return int(w.config["node_at"].get(node_key(i, j), -1))


static func node_pos(w: LTWorld, n: int) -> Vector2:
	var nd: Dictionary = w.road_nodes[n]
	return Vector2(float(nd["x"]) * GRID, float(nd["y"]) * GRID)


static func _init_survey(w: LTWorld) -> void:
	w.config["map_cols"] = MAP_COLS
	w.config["map_rows"] = MAP_ROWS
	w.config["lot_cols"] = MAP_COLS
	w.config["lot_rows"] = MAP_ROWS
	w.config["node_at"] = {}
	w.config["districts"] = [{"name": "Town", "rows": [0, MAP_ROWS]}]
	w.config["road_name_i"] = 0


static func _road(w: LTWorld, name: String, kind: String, i0: int, j0: int, i1: int, j1: int) -> Dictionary:
	var st: Dictionary = {"id": w.streets.size(), "name": name, "segments": [], "kind": kind}
	w.streets.append(st)
	var steps: int = maxi(absi(i1 - i0), absi(j1 - j0))
	var di: int = signi(i1 - i0)
	var dj: int = signi(j1 - j0)
	for k in steps:
		var a: int = node_id(w, i0 + di * k, j0 + dj * k)
		var b: int = node_id(w, i0 + di * (k + 1), j0 + dj * (k + 1))
		if seg_between(w, a, b) >= 0:
			continue
		st["segments"].append(_add_segment(w, a, b, int(st["id"])))
	if kind == "alley":
		st["width"] = "alley"
		st["surface"] = "gravel"
	return st


## Prairie Hollow at real scale: a grid of 100 meter blocks with an alley down
## the middle of each, homes on the north side, Main Street through the middle
## lined with narrow storefront lots, civic land and a park, and farmland on the
## south edge. The county road comes in from both ends of Main Street.
static func build(w: LTWorld) -> void:
	_init_survey(w)
	var bx: int = int(w.config.get("town_blocks_x", 4))
	var by: int = int(w.config.get("town_blocks_y", 3))
	var ox: int = (MAP_COLS - bx * BLOCK) / 2 / BLOCK * BLOCK
	var oy: int = (MAP_ROWS - by * BLOCK) / 2 / BLOCK * BLOCK
	var main_row: int = by / 2
	var jm: int = oy + main_row * BLOCK
	# the county road, edge to edge along Main Street's line
	_road(w, "County Road 12", "highway", 0, jm, ox, jm)
	_road(w, "County Road 12", "highway", ox + bx * BLOCK, jm, MAP_COLS, jm)
	w.config["exit_node"] = find_node(w, 0, jm)
	w.config["exit_nodes"] = [find_node(w, 0, jm), find_node(w, MAP_COLS, jm)]
	# streets east to west, avenues north to south, alleys through each block
	var street_ids: Array = []
	for r in by + 1:
		var nm: String = "Main Street" if r == main_row else STREET_NAMES[(r + (0 if r < main_row else 1)) % STREET_NAMES.size()]
		if nm == "Main Street" and r != main_row:
			nm = "Prairie Street"
		street_ids.append(int(_road(w, nm, "street", ox, oy + r * BLOCK, ox + bx * BLOCK, oy + r * BLOCK)["id"]))
	for c in bx + 1:
		_road(w, AVENUE_NAMES[c % AVENUE_NAMES.size()], "avenue", ox + c * BLOCK, oy, ox + c * BLOCK, oy + by * BLOCK)
	for r in by:
		if r == by - 1:
			continue   # farm blocks have no alley
		_road(w, "Alley", "alley", ox, oy + r * BLOCK + BLOCK / 2, ox + bx * BLOCK, oy + r * BLOCK + BLOCK / 2)
	# the land around the town: forest, mountain and lakes from the map seed
	LTTerrain.setup(w, int(w.config["map_seed"]), Rect2(float(ox) * GRID, float(oy) * GRID, float(bx * BLOCK) * GRID, float(by * BLOCK) * GRID))
	for s in w.roads:
		s["condition"] = w.rng.randf_range(45.0, 85.0)
		s["quality"] = w.rng.randf_range(0.45, 0.7)
	for sid in w.streets[street_ids[main_row]]["segments"]:
		w.roads[int(sid)]["condition"] = w.rng.randf_range(38.0, 52.0)
		w.roads[int(sid)]["quality"] = 0.45
	# lots
	for r in by:
		for c in bx:
			var x0: float = float(ox + c * BLOCK) * GRID + ROW_HALF["avenue"]
			var x1: float = float(ox + (c + 1) * BLOCK) * GRID - ROW_HALF["avenue"]
			var zt: float = float(oy + r * BLOCK) * GRID + ROW_HALF["street"]
			var zb: float = float(oy + (r + 1) * BLOCK) * GRID - ROW_HALF["street"]
			var za: float = float(oy + r * BLOCK + BLOCK / 2) * GRID
			var zone: String = "residential"
			var width: float = 21.25
			if r == by - 1:
				zone = "agricultural" if c < bx / 2 else ("park" if c == bx / 2 else "civic")
				width = 42.5
			if r == by - 1 and zone == "agricultural":
				_make_lots(w, x0, zt, x1, zb, zone, x1 - x0, "n")
				continue
			if r == by - 1:
				_make_lots(w, x0, zt, x1, zb, zone, x1 - x0, "n")
				continue
			# north half fronts the street above, south half the street below;
			# both sides of Main Street are narrow storefront lots
			var downtown: bool = c >= bx / 2 - 1 and c <= bx / 2
			var north_zone: String = "commercial" if r == main_row and downtown else zone
			var south_zone: String = "commercial" if r == main_row - 1 and downtown else zone
			_make_lots(w, x0, zt, x1, za - ROW_HALF["alley"], north_zone, 12.1 if north_zone == "commercial" else width, "n")
			_make_lots(w, x0, za + ROW_HALF["alley"], x1, zb, south_zone, 12.1 if south_zone == "commercial" else width, "s")


## Cuts a strip of land into lots of a given width along its front.
static func _make_lots(w: LTWorld, x0: float, z0: float, x1: float, z1: float, zone: String, width: float, front: String) -> void:
	var n: int = maxi(1, int(floor((x1 - x0) / width + 0.01)))
	var wd: float = (x1 - x0) / float(n)
	for k in n:
		_add_lot(w, x0 + wd * float(k), z0, x0 + wd * float(k + 1), z1, zone, front, "Town")


static func _add_lot(w: LTWorld, x0: float, z0: float, x1: float, z1: float, zone: String, front: String, district: String) -> int:
	var cx: float = (x0 + x1) * 0.5
	var cz: float = (z0 + z1) * 0.5
	var fx: float = cx
	var fz: float = cz
	match front:
		"n":
			fz = z0 - 1.0
		"s":
			fz = z1 + 1.0
		"w":
			fx = x0 - 1.0
		"e":
			fx = x1 + 1.0
	var seg: int = _nearest_segment(w, Vector2(fx, fz))
	if seg < 0:
		return -1
	var sg: Dictionary = w.roads[seg]
	var pa: Vector2 = node_pos(w, int(sg["a"]))
	var pb: Vector2 = node_pos(w, int(sg["b"]))
	var access: int = int(sg["a"]) if pa.distance_to(Vector2(cx, cz)) <= pb.distance_to(Vector2(cx, cz)) else int(sg["b"])
	var id: int = w.lots.size()
	var area: float = (x1 - x0) * (z1 - z0)
	var land: Dictionary = LTTerrain.survey(w, Rect2(x0, z0, x1 - x0, z1 - z0))
	var worth: float = 1.0 + (0.6 if bool(land.get("lakefront", false)) else 0.0) + (0.2 if bool(land.get("view", false)) else 0.0) + (0.1 if bool(land.get("wooded", false)) else 0.0)
	w.lots.append({
		"id": id, "x0": x0, "z0": z0, "x1": x1, "z1": z1, "front": front,
		"col": int(cx / 18.0), "row": int(cz / 18.0), "zone": zone,
		"use": "empty", "ref": -1, "units": [], "unit_rent": 0,
		"owner_kind": "city", "owner_id": -1,
		"value": int(float(land_value(zone, area)) * worth), "condition": 80.0,
		"building": "", "built_day": 0, "name": "", "street": int(sg["street"]), "district": district,
		"access_node": access, "price_pct": 100, "hold": false, "plot_group": 0,
		"wooded": bool(land.get("wooded", false)), "lakefront": bool(land.get("lakefront", false)), "view": bool(land.get("view", false)),
	})
	return id


## The road segment closest to a point (any kind, built or planned), or -1.
static func _nearest_segment(w: LTWorld, p: Vector2) -> int:
	var best: int = -1
	var best_d: float = 1e9
	for sg in w.roads:
		if bool(sg.get("removed", false)):
			continue
		var a: Vector2 = node_pos(w, int(sg["a"]))
		var b: Vector2 = node_pos(w, int(sg["b"]))
		var d: float = Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
		if d < best_d:
			best_d = d
			best = int(sg["id"])
	return best


static func _add_segment(w: LTWorld, a: int, b: int, street_id: int) -> int:
	var id: int = w.roads.size()
	w.roads.append({"id": id, "a": a, "b": b, "street": street_id, "condition": 70.0, "quality": 0.55, "last_project": -1, "repaired_day": 0})
	w.road_nodes[a]["edges"].append(id)
	w.road_nodes[b]["edges"].append(id)
	return id


## What a lot of this size and zone is worth as bare land.
static func land_value(zone: String, area: float = 800.0) -> int:
	return LTMoney.dollars(maxf(1000.0, area * float(LAND_PER_M2.get(zone, 2.0))))


static func lot_area(l: Dictionary) -> float:
	return (float(l["x1"]) - float(l["x0"])) * (float(l["z1"]) - float(l["z0"]))


## Street frontage in meters (the side that faces the road).
static func lot_frontage(l: Dictionary) -> float:
	return (float(l["x1"]) - float(l["x0"])) if ["n", "s"].has(str(l["front"])) else (float(l["z1"]) - float(l["z0"]))


static func lot_depth(l: Dictionary) -> float:
	return (float(l["z1"]) - float(l["z0"])) if ["n", "s"].has(str(l["front"])) else (float(l["x1"]) - float(l["x0"]))


static func lot_access_node(w: LTWorld, lot_id: int) -> int:
	return int(w.lot(lot_id)["access_node"])


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
			best = minf(best, dist_to(w, dist0, a, int(ex)))
		if best >= 1e8:
			return 999.0
		return best * weather_factor(w) + 2.0 + extra
	var src: int = lot_access_node(w, from_lot)
	var dst: int = lot_access_node(w, to_lot)
	if src == dst:
		return 2.0
	var dist: Dictionary = node_distances(w, src)
	var d: float = dist_to(w, dist, src, dst)
	if d >= 1e8:
		return 999.0
	return d * weather_factor(w) + 2.0


## Is the lot connected to the outside world by built road?
static func connected(w: LTWorld, lot_id: int) -> bool:
	return travel_minutes(w, lot_id, -1) < 500.0


## The road graph has a node every 10 meters, but almost all of them sit in the
## middle of a straight run with one road in and one out. Paths are found on the
## junctions only (crossings, corners, dead ends, exits); a node in the middle of a
## run is reached from the junctions at either end of it. Rebuilt whenever the
## distance cache is cleared (weekly, or when a road opens or wears).
static func _junction_graph(w: LTWorld) -> Dictionary:
	if w.dist_cache.has("_g"):
		return w.dist_cache["_g"]
	var exits: Dictionary = {}
	for ex in exit_nodes(w):
		exits[int(ex)] = true
	var is_j: Dictionary = {}
	for nd in w.road_nodes:
		var deg: int = nd["edges"].size()
		if deg > 0 and (deg != 2 or exits.has(int(nd["id"]))):
			is_j[int(nd["id"])] = true
	var adj: Dictionary = {}
	var chain: Dictionary = {}
	for j in is_j:
		adj[j] = []
	for j in is_j:
		for sid in w.road_nodes[j]["edges"]:
			# walk the run of road until the next junction
			var prev: int = j
			var cur_s: int = int(sid)
			var acc: float = 0.0
			var mids: Array = []
			var guard: int = 0
			while guard < 100000:
				guard += 1
				var sg: Dictionary = w.roads[cur_s]
				acc += SEGMENT_MINUTES * (1.0 + (100.0 - float(sg["condition"])) / 100.0 * 0.9)
				var nxt: int = int(sg["b"]) if int(sg["a"]) == prev else int(sg["a"])
				if is_j.has(nxt):
					adj[j].append([nxt, acc])
					for m in mids:
						# each middle node remembers both ends of its run and how far each is
						if not chain.has(int(m[0])):
							chain[int(m[0])] = [j, float(m[1]), nxt, acc - float(m[1])]
					break
				mids.append([nxt, acc])
				var es: Array = w.road_nodes[nxt]["edges"]
				var other_s: int = int(es[0]) if int(es[0]) != cur_s else int(es[1])
				prev = nxt
				cur_s = other_s
	var g: Dictionary = {"adj": adj, "chain": chain, "j": is_j}
	w.dist_cache["_g"] = g
	return g


## Shortest times from a node to every junction (cached per source node).
static func node_distances(w: LTWorld, src: int) -> Dictionary:
	var cache: Dictionary = w.dist_cache
	if cache.has(src):
		return cache[src]
	var g: Dictionary = _junction_graph(w)
	var adj: Dictionary = g["adj"]
	var dist: Dictionary = {}
	var heap: Array = []
	if g["j"].has(src):
		dist[src] = 0.0
		heap.append([0.0, src])
	elif g["chain"].has(src):
		var ch: Array = g["chain"][src]
		dist[int(ch[0])] = float(ch[1])
		_heap_push(heap, [float(ch[1]), int(ch[0])])
		if float(ch[3]) < float(dist.get(int(ch[2]), 1e18)):
			dist[int(ch[2])] = float(ch[3])
			_heap_push(heap, [float(ch[3]), int(ch[2])])
	var done: Dictionary = {}
	while not heap.is_empty():
		var top: Array = _heap_pop(heap)
		var n: int = int(top[1])
		if done.has(n):
			continue
		done[n] = true
		for e in adj.get(n, []):
			var other: int = int(e[0])
			if done.has(other):
				continue
			var nd: float = float(dist[n]) + float(e[1])
			if nd < float(dist.get(other, 1e18)):
				dist[other] = nd
				_heap_push(heap, [nd, other])
	cache[src] = dist
	return dist


## The time from `src` to node `t`, given src's junction distances.
static func dist_to(w: LTWorld, dist: Dictionary, src: int, t: int) -> float:
	if t == src:
		return 0.0
	var g: Dictionary = _junction_graph(w)
	if g["j"].has(t):
		return float(dist.get(t, 1e9))
	if not g["chain"].has(t):
		return 1e9
	var ct: Array = g["chain"][t]
	var best: float = minf(float(dist.get(int(ct[0]), 1e9)) + float(ct[1]), float(dist.get(int(ct[2]), 1e9)) + float(ct[3]))
	# both on the same run of road: straight along it
	if g["chain"].has(src):
		var cs: Array = g["chain"][src]
		if int(cs[0]) == int(ct[0]) and int(cs[2]) == int(ct[2]):
			best = minf(best, absf(float(cs[1]) - float(ct[1])))
		elif int(cs[0]) == int(ct[2]) and int(cs[2]) == int(ct[0]):
			best = minf(best, absf(float(cs[1]) - float(ct[3])))
	return best


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
	var n: int = lot_access_node(w, lot_id)
	var out: Array = []
	for sid in w.road_nodes[n]["edges"]:
		if int(w.roads[int(sid)]["street"]) == int(w.lot(lot_id)["street"]):
			out.append(int(sid))
	return out


static func lot_street(w: LTWorld, lot_id: int) -> Dictionary:
	return w.streets[int(w.lot(lot_id)["street"])]


static func district(w: LTWorld, lot_id: int) -> String:
	return str(w.lot(lot_id).get("district", "Old Town"))


## Annexing is no longer needed: the whole survey is open for roads and lots.
static func annex_row(w: LTWorld) -> Dictionary:
	return {"ok": false, "message": "The whole survey is open: draw roads and plot lots wherever you like."}


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
	var street_crew: float = 2.0 - LTGov.factor(w, "street_super")
	for s in w.roads:
		if bool(s.get("planned", false)) or bool(s.get("removed", false)):
			continue
		var q: float = float(s["quality"])
		var rate: float = (0.02 + (1.0 - q) * (1.0 - q) * 0.22) * street_crew
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
## A founded town starts as open prairie: only the county road crosses it. The
## player draws streets and alleys on the survey grid (each a contract that goes
## out to bid) and plots lots of any size beside them.

const ROAD_NAMES: Array = ["Main Street", "Elm Street", "Oak Street", "Prairie Avenue", "Mill Road", "Church Street", "School Street", "Park Avenue", "Maple Street", "Depot Road", "Cedar Street", "Lake Road", "Hill Street", "Bluff Road", "Sunset Drive", "Ash Street", "Willow Lane", "Union Street", "Grant Avenue", "Lincoln Street"]


static func build_open(w: LTWorld) -> void:
	_init_survey(w)
	w.config["open_land"] = true
	w.config["districts"] = [{"name": "Founders' Plat", "rows": [0, MAP_ROWS]}]
	var jm: int = MAP_ROWS / 2
	_road(w, "County Road 12", "highway", 0, jm, MAP_COLS, jm)
	w.config["exit_node"] = find_node(w, 0, jm)
	w.config["exit_nodes"] = [find_node(w, 0, jm), find_node(w, MAP_COLS, jm)]
	# keep the middle of the county road open prairie for the first streets
	LTTerrain.setup(w, int(w.config["map_seed"]), Rect2(float(MAP_COLS) * GRID * 0.5 - 300.0, float(MAP_ROWS) * GRID * 0.5 - 180.0, 600.0, 360.0))
	for s in w.roads:
		s["condition"] = 75.0
		s["quality"] = 0.6


## A lot this point falls in, or -1. Points are in meters.
static func lot_at(w: LTWorld, x: float, z: float) -> int:
	for l in w.lots:
		if bool(l.get("removed", false)):
			continue
		if x >= float(l["x0"]) and x <= float(l["x1"]) and z >= float(l["z0"]) and z <= float(l["z1"]):
			return int(l["id"])
	return -1


## The ground a road segment takes up: its lanes plus sidewalk or shoulder.
static func seg_rect(w: LTWorld, sg: Dictionary) -> Rect2:
	var a: Vector2 = node_pos(w, int(sg["a"]))
	var b: Vector2 = node_pos(w, int(sg["b"]))
	var st: Dictionary = w.streets[int(sg["street"])]
	var hw: float = float(ROW_HALF.get(str(st.get("width", st["kind"])), ROW_HALF.get(str(st["kind"]), 7.5)))
	var r: Rect2 = Rect2(a, Vector2.ZERO).expand(b)
	return r.grow(hw)


static func _rect_hits_roads(w: LTWorld, r: Rect2) -> bool:
	var inner: Rect2 = r.grow(-0.05)
	for sg in w.roads:
		if bool(sg.get("removed", false)):
			continue
		if inner.intersects(seg_rect(w, sg)):
			return true
	return false


static func _rect_hits_lots(w: LTWorld, r: Rect2) -> bool:
	var inner: Rect2 = r.grow(-0.05)
	for l in w.lots:
		if bool(l.get("removed", false)):
			continue
		if inner.intersects(Rect2(float(l["x0"]), float(l["z0"]), float(l["x1"]) - float(l["x0"]), float(l["z1"]) - float(l["z0"]))):
			return true
	return false


static func seg_between(w: LTWorld, a: int, b: int) -> int:
	for key in ["edges", "planned"]:
		for sid in w.road_nodes[a].get(key, []):
			var sg: Dictionary = w.roads[int(sid)]
			if (int(sg["a"]) == a and int(sg["b"]) == b) or (int(sg["a"]) == b and int(sg["b"]) == a):
				return int(sid)
	return -1


## Lays out a straight road between two grid corners. New pieces are planned, not
## built: they become a project for contractors to bid on.
## Lays out a straight road (or an alley) between two survey corners.
static func plan_road(w: LTWorld, a: int, b: int, draft: bool = false, kind: String = "street") -> Dictionary:
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
	if kind == "alley":
		w.config["alley_i"] = int(w.config.get("alley_i", 0)) + 1
	var street: Dictionary = {"id": w.streets.size(), "name": _next_road_name(w) if kind != "alley" else "Alley %d" % int(w.config["alley_i"]), "segments": [], "kind": "alley" if kind == "alley" else "street"}
	if kind == "alley":
		street["width"] = "alley"
	# nothing may run through a lot
	var probe: Rect2 = Rect2(Vector2(float(ax), float(ay)) * GRID, Vector2.ZERO).expand(Vector2(float(bx), float(by)) * GRID).grow(float(ROW_HALF["alley" if kind == "alley" else "street"]))
	if _rect_hits_lots(w, probe):
		return {"ok": false, "message": "A plotted lot is in the way. Remove the lot or draw the road elsewhere."}
	var new_segs: Array = []
	var steps0: int = maxi(absi(bx - ax), absi(by - ay))
	for k in steps0:
		var pa: Vector2 = Vector2(float(ax + signi(bx - ax) * k), float(ay + signi(by - ay) * k)) * GRID
		var pb: Vector2 = Vector2(float(ax + signi(bx - ax) * (k + 1)), float(ay + signi(by - ay) * (k + 1))) * GRID
		var rc: Dictionary = LTTerrain.road_cost(w, pa, pb)
		if not bool(rc["ok"]):
			return {"ok": false, "message": "Can't build that road: %s." % rc["why"]}
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
	if kind == "alley" and int(r.get("project_id", -1)) >= 0:
		var pr: Dictionary = w.projects[int(r["project_id"])]
		pr["spec"]["width"] = "alley"
		pr["spec"]["surface"] = "gravel"
		LTProjects._apply_spec(pr)
	r["street"] = int(street["id"])
	return r


static func _next_road_name(w: LTWorld) -> String:
	# the next name on the list that no street in town already has
	var used: Dictionary = {}
	for st in w.streets:
		used[str(st["name"])] = true
	var guard: int = 0
	while guard < 500:
		guard += 1
		var i: int = int(w.config.get("road_name_i", 0))
		w.config["road_name_i"] = i + 1
		var base: String = ROAD_NAMES[i % ROAD_NAMES.size()]
		if i >= ROAD_NAMES.size():
			base = "%s %d" % [base, i / ROAD_NAMES.size() + 1]
		if not used.has(base):
			return base
	return "New Street %d" % w.streets.size()


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


## Plots lots of any size on open land. The rectangle (in meters) must sit beside
## a road, built or planned, and may not cover a road or another lot. With a
## `width`, the strip is cut into lots of about that frontage along the road.
static func plot_lots(w: LTWorld, x0: float, z0: float, x1: float, z1: float, zone: String, width: float = 0.0) -> Dictionary:
	if not ZONES.has(zone):
		return {"ok": false, "message": "Unknown zone."}
	# the plot tool already snaps sides onto road edges (which sit on half meters)
	var r: Rect2 = Rect2(Vector2(minf(x0, x1), minf(z0, z1)), Vector2.ZERO).expand(Vector2(maxf(x0, x1), maxf(z0, z1)))
	r = r.intersection(Rect2(0, 0, float(MAP_COLS) * GRID, float(MAP_ROWS) * GRID))
	if r.size.x < 6.0 or r.size.y < 6.0:
		return {"ok": false, "message": "Drag out a bigger lot: at least 6 by 6 meters."}
	var front: String = _front_side(w, r)
	if front == "":
		return {"ok": false, "message": "A lot has to sit right beside a road, built or planned. Drag it up to the edge of one."}
	var pieces: Array = [r]
	if width >= 6.0:
		pieces = []
		var along_x: bool = front == "n" or front == "s"
		var span: float = r.size.x if along_x else r.size.y
		var n: int = maxi(1, int(floor(span / width + 0.25)))
		var each: float = span / float(n)
		for k in n:
			if along_x:
				pieces.append(Rect2(r.position.x + each * float(k), r.position.y, each, r.size.y))
			else:
				pieces.append(Rect2(r.position.x, r.position.y + each * float(k), r.size.x, each))
	var group: int = int(w.config.get("plot_group_i", 0)) + 1
	var made: int = 0
	var blocked: int = 0
	var land_why: String = ""
	for pc in pieces:
		var pr: Rect2 = pc
		if _rect_hits_roads(w, pr) or _rect_hits_lots(w, pr):
			blocked += 1
			continue
		var land: Dictionary = LTTerrain.survey(w, pr)
		if not bool(land["ok"]):
			land_why = str(land["why"])
			blocked += 1
			continue
		var f: String = _front_side(w, pr)
		if f == "":
			blocked += 1
			continue
		var id: int = _add_lot(w, pr.position.x, pr.position.y, pr.end.x, pr.end.y, zone, f, str(w.config["districts"][0]["name"]))
		if id < 0:
			blocked += 1
			continue
		w.lots[id]["plot_group"] = group
		made += 1
	if made == 0:
		if land_why != "":
			return {"ok": false, "message": "No lots plotted: %s." % land_why}
		return {"ok": false, "message": "No lots plotted: they would cover a road or another lot, or nothing touches a road."}
	w.config["plot_group_i"] = group
	var msg: String = "Plotted %d %s lot%s. Tap one to set its price and details." % [made, zone, "" if made == 1 else "s"]
	if blocked > 0:
		msg += " %d %s skipped because a road or another lot was in the way." % [blocked, "was" if blocked == 1 else "were"]
	return {"ok": true, "message": msg, "plot_group": group}


## Which side of a rectangle sits against a road's edge: n, s, w, e, or "".
## A built road wins over a planned one, and a street over an alley.
static func _front_side(w: LTWorld, r: Rect2) -> String:
	# add up how much of each side runs along road, built streets counting most;
	# the side with the most is the lot's front, as with real lots
	var touch: Dictionary = {"n": 0.0, "s": 0.0, "w": 0.0, "e": 0.0}
	for sg in w.roads:
		if bool(sg.get("removed", false)):
			continue
		var rr: Rect2 = seg_rect(w, sg)
		var st: Dictionary = w.streets[int(sg["street"])]
		var weight: float = (1.5 if not bool(sg.get("planned", false)) else 1.0) * (0.5 if str(st["kind"]) == "alley" else 1.0)
		var ox: float = minf(rr.end.x, r.end.x) - maxf(rr.position.x, r.position.x)
		var oz: float = minf(rr.end.y, r.end.y) - maxf(rr.position.y, r.position.y)
		if ox > 0.0 and absf(rr.end.y - r.position.y) < 2.0:
			touch["n"] += ox * weight
		if ox > 0.0 and absf(rr.position.y - r.end.y) < 2.0:
			touch["s"] += ox * weight
		if oz > 0.0 and absf(rr.end.x - r.position.x) < 2.0:
			touch["w"] += oz * weight
		if oz > 0.0 and absf(rr.position.x - r.end.x) < 2.0:
			touch["e"] += oz * weight
	var best: String = ""
	var best_t: float = 0.5
	for k in ["n", "s", "w", "e"]:
		if float(touch[k]) > best_t:
			best_t = float(touch[k])
			best = k
	return best


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
	return {"ok": true, "message": "Lot %d is open prairie again." % lot_id}



# ================================================================ homes

## What a family builds: bedrooms, bathrooms, stories, garage stalls and a
## basement. Size and price follow, at small town new build prices: about $175
## a finished square foot, $18,000 a garage stall, $35,000 for a basement.
const HOME_PER_SQFT: float = 175.0
const GARAGE_STALL: float = 18000.0
const BASEMENT: float = 35000.0


static func home_sqft(spec: Dictionary) -> int:
	return LTHomes.sqft(spec)


static func home_cost(spec: Dictionary) -> int:
	return LTHomes.home_cost(spec)


static func _thousands(n: int) -> String:
	var t: String = str(n)
	return t if n < 1000 else "%s,%s" % [t.substr(0, t.length() - 3), t.substr(t.length() - 3)]


static func home_text(spec: Dictionary) -> String:
	return "" if spec.is_empty() else LTHomes.text(spec)


## A family decides what to build from who they are and what they can carry:
## a bedroom for the couple and roughly one for every one or two children, a
## second bath once the family grows, a garage on the prairie where winters are
## long, a basement for storm shelter if they can afford it. Ambitious or proud
## families reach for more, careful ones build what they need. The bank lends up
## to about four times the family's yearly income.
static func choose_home(w: LTWorld, adults: int, kids: int, yearly_income: int, ambition: float, discipline: float, lot: Dictionary = {}, budget: int = 0) -> Dictionary:
	var tr: Dictionary = {}
	for k in LTPeople.TRAIT_KEYS:
		tr[k] = w.rng.randf_range(25.0, 75.0)
	tr["ambition"] = ambition
	tr["discipline"] = discipline
	var ctx: Dictionary = {"adults": adults, "kids": kids, "income": yearly_income, "traits": tr, "head_age": w.rng.randi_range(25, 60),
		"cook": w.rng.randf() < 0.12, "builder": w.rng.randf() < 0.1, "hunter": w.rng.randf() < 0.2, "works_home": w.rng.randf() < 0.1}
	if not lot.is_empty():
		ctx["lot"] = lot
	if budget > 0:
		ctx["budget"] = budget
	return LTHomes.design(w, ctx)
