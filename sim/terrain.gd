class_name LTTerrain
## The land itself, made from a map seed: a forest in one corner, a Black Hills
## style mountain in another, and one or two lakes. The same seed always makes the
## same map. Heights are in meters, like everything else.
##
## The deep forest is state forest and the upper mountain is a state park: open to
## everyone for trails, fishing and hunting, but nobody may build there. The rest is
## county land the town can buy and plot like the prairie.

const MAP_W: float = 1600.0
const MAP_H: float = 1200.0
## below this height the land is the flat valley floor; above it, only trails
const BUILD_MAX_HEIGHT: float = 4.0
const BRIDGE_COST: float = 8.0       # a bridge costs about 8 times a road on land
const HILL_COST: float = 5.0         # extra cost per unit of slope
const CLEAR_COST: float = 0.35       # clearing trees adds about a third to a road
const LOT_CLEARING: int = 1200000    # $12,000 to clear a wooded lot before building

static var _noise_seed: int = -1
static var _noise: FastNoiseLite = null


## Lays out the land from the map seed, keeping clear of the town and the county road.
static func setup(w: LTWorld, map_seed: int, avoid: Rect2) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = map_seed
	var corners: Array = [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]
	for i in range(corners.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var t: Vector2 = corners[i]
		corners[i] = corners[j]
		corners[j] = t
	var fc: Vector2 = corners[0]
	var mc: Vector2 = corners[1]
	var oc: Vector2 = corners[2]
	var forest: Dictionary = {
		"c": _inset(fc, rng.randf_range(260.0, 320.0), rng.randf_range(200.0, 240.0)),
		"rx": rng.randf_range(320.0, 390.0), "rz": rng.randf_range(210.0, 260.0),
	}
	var mountain: Dictionary = {
		"c": _inset(mc, rng.randf_range(250.0, 290.0), rng.randf_range(220.0, 250.0)),
		"r": rng.randf_range(270.0, 320.0), "peak": rng.randf_range(120.0, 165.0),
	}
	# the big lake lies between the forest and the middle of the map; a pond elsewhere
	var mid: Vector2 = Vector2(MAP_W, MAP_H) * 0.5
	var lake_c: Vector2 = (forest["c"] as Vector2).lerp(mid, rng.randf_range(0.45, 0.6)) + Vector2(rng.randf_range(-60.0, 60.0), rng.randf_range(-40.0, 40.0))
	var lakes: Array = [{"c": lake_c, "rx": rng.randf_range(95.0, 145.0), "rz": rng.randf_range(65.0, 100.0), "name": "%s Lake" % ["Pine", "Clear", "Long", "Elk", "Willow", "Mirror", "Otter", "Cedar"][rng.randi_range(0, 7)]}]
	if rng.randf() < 0.75:
		lakes.append({"c": _inset(oc, rng.randf_range(180.0, 320.0), rng.randf_range(160.0, 260.0)), "rx": rng.randf_range(35.0, 60.0), "rz": rng.randf_range(28.0, 50.0), "name": "Mill Pond"})
	var keep_out: Rect2 = avoid.grow(40.0)
	var road_band: Rect2 = Rect2(0, MAP_H * 0.5 - 45.0, MAP_W, 90.0)
	# shrink anything that would cover the town or the county road
	for guard in 30:
		if not _ellipse_rect(forest["c"], forest["rx"], forest["rz"]).intersects(keep_out) and not _ellipse_rect(forest["c"], forest["rx"], forest["rz"]).intersects(road_band):
			break
		forest["rx"] = float(forest["rx"]) * 0.93
		forest["rz"] = float(forest["rz"]) * 0.93
	for guard in 30:
		var mr: Rect2 = _ellipse_rect(mountain["c"], mountain["r"], mountain["r"])
		if not mr.intersects(keep_out) and not mr.intersects(road_band):
			break
		mountain["r"] = float(mountain["r"]) * 0.94
	for lk in lakes:
		for guard in 40:
			var lr: Rect2 = _ellipse_rect(lk["c"], lk["rx"], lk["rz"])
			if not lr.grow(25.0).intersects(keep_out) and not lr.grow(25.0).intersects(road_band):
				break
			# slide it away from the middle, then shrink a little
			lk["c"] = (lk["c"] as Vector2) + ((lk["c"] as Vector2) - mid).normalized() * 18.0
			lk["rx"] = float(lk["rx"]) * 0.97
			lk["rz"] = float(lk["rz"]) * 0.97
	w.config["terrain"] = {
		"seed": map_seed, "forest": forest, "mountain": mountain, "lakes": lakes,
		"forest_name": "%s State Forest" % ["Black Pine", "Bear Butte", "Spearfish", "Deadwood", "Harney", "Custer"][rng.randi_range(0, 5)],
		"park_name": "%s State Park" % ["Eagle Peak", "Granite Ridge", "Elk Mountain", "Thunder Butte", "Iron Hill"][rng.randi_range(0, 4)],
	}
	w.config["map_seed"] = map_seed
	w.config["terrain"]["avoid"] = [avoid.position.x, avoid.position.y, avoid.size.x, avoid.size.y]
	w.config["terrain"]["landmarks"] = _make_landmarks(w, map_seed, avoid)


static func _inset(corner: Vector2, ix: float, iz: float) -> Vector2:
	return Vector2(ix if corner.x == 0.0 else MAP_W - ix, iz if corner.y == 0.0 else MAP_H - iz)


static func _ellipse_rect(c: Vector2, rx: float, rz: float) -> Rect2:
	return Rect2(c - Vector2(rx, rz), Vector2(rx, rz) * 2.0)


static func t(w: LTWorld) -> Dictionary:
	return w.config.get("terrain", {})


static func noise(w: LTWorld) -> FastNoiseLite:
	var sd: int = int(t(w).get("seed", 0))
	if _noise == null or _noise_seed != sd:
		_noise = FastNoiseLite.new()
		_noise.seed = sd
		_noise.frequency = 0.006
		_noise.fractal_octaves = 3
		_noise_seed = sd
	return _noise


# ---------------------------------------------------------------- what is where

## How deep into the forest a point is: above 0 is forest, above 0.45 is the
## state forest's protected core.
static func forest_value(w: LTWorld, x: float, z: float) -> float:
	var tt: Dictionary = t(w)
	if tt.is_empty():
		return -1.0
	var f: Dictionary = tt["forest"]
	var c: Vector2 = f["c"]
	var dx: float = (x - c.x) / float(f["rx"])
	var dz: float = (z - c.y) / float(f["rz"])
	return 1.0 - (dx * dx + dz * dz) + noise(w).get_noise_2d(x, z) * 0.45


static func is_forest(w: LTWorld, x: float, z: float) -> bool:
	return forest_value(w, x, z) > 0.0 and not is_water(w, x, z) and height(w, x, z) < mountain_peak(w) * 0.55


static func mountain_peak(w: LTWorld) -> float:
	return float(t(w).get("mountain", {}).get("peak", 0.0))


## Ground height in meters: the valley floor is 0, the mountain rises in its corner.
static func height(w: LTWorld, x: float, z: float) -> float:
	var tt: Dictionary = t(w)
	if tt.is_empty():
		return 0.0
	var m: Dictionary = tt["mountain"]
	var c: Vector2 = m["c"]
	var d: float = Vector2(x, z).distance_to(c) / float(m["r"])
	if d >= 1.0:
		return 0.0
	var base: float = pow(1.0 - d, 1.7)
	# ridges and gullies, stronger up high
	var ridge: float = 1.0 + noise(w).get_noise_2d(x * 2.2 + 500.0, z * 2.2) * 0.35 * (1.0 - d)
	return maxf(0.0, float(m["peak"]) * base * ridge)


static func is_water(w: LTWorld, x: float, z: float) -> bool:
	return lake_at(w, x, z) >= 0


static func lake_at(w: LTWorld, x: float, z: float) -> int:
	var tt: Dictionary = t(w)
	var lakes: Array = tt.get("lakes", [])
	for i in lakes.size():
		var lk: Dictionary = lakes[i]
		var c: Vector2 = lk["c"]
		var dx: float = (x - c.x) / float(lk["rx"])
		var dz: float = (z - c.y) / float(lk["rz"])
		if dx * dx + dz * dz + noise(w).get_noise_2d(x * 1.5, z * 1.5) * 0.12 < 1.0:
			return i
	return -1


## State land nobody may build on: the deep forest and the upper mountain.
static func protected(w: LTWorld, x: float, z: float) -> String:
	if t(w).is_empty():
		return ""
	if height(w, x, z) > mountain_peak(w) * 0.3:
		return str(t(w)["park_name"])
	if forest_value(w, x, z) > 0.45:
		return str(t(w)["forest_name"])
	return ""


static func slope(w: LTWorld, x: float, z: float) -> float:
	var h: float = height(w, x, z)
	return maxf(absf(height(w, x + 5.0, z) - h), absf(height(w, x, z + 5.0) - h)) / 5.0


static func water_distance(w: LTWorld, x: float, z: float) -> float:
	var best: float = 1e9
	for lk in t(w).get("lakes", []):
		var c: Vector2 = lk["c"]
		var rx: float = float(lk["rx"])
		var rz: float = float(lk["rz"])
		var v: Vector2 = Vector2((x - c.x) / rx, (z - c.y) / rz)
		var len: float = v.length()
		if len < 0.0001:
			return 0.0
		# distance to the shore along the line to the center, close enough for this
		var shore: Vector2 = c + Vector2(v.x / len * rx, v.y / len * rz)
		best = minf(best, 0.0 if len < 1.0 else Vector2(x, z).distance_to(shore))
	return best


# ---------------------------------------------------------------- building rules

## What the land under a rectangle allows: {ok, why, wooded, lakefront, view}.
static func survey(w: LTWorld, r: Rect2) -> Dictionary:
	var out: Dictionary = {"ok": true, "why": "", "wooded": false, "lakefront": false, "view": false}
	if t(w).is_empty():
		return out
	# the railroad's right of way: 15 meters each side of the track
	var rz0: float = rail_z(w)
	if r.position.y < rz0 + 15.0 and r.end.y > rz0 - 15.0:
		out["ok"] = false
		out["why"] = "the land is the railroad's right of way, 15 meters each side of the track"
		return out
	var trees: int = 0
	var n: int = 0
	var step: float = clampf(minf(r.size.x, r.size.y) / 4.0, 3.0, 8.0)
	var x: float = r.position.x
	while x <= r.end.x + 0.01:
		var z: float = r.position.y
		while z <= r.end.y + 0.01:
			n += 1
			if is_water(w, x, z):
				return {"ok": false, "why": "that land is under %s" % lake_name(w, x, z)}
			var prot: String = protected(w, x, z)
			if prot != "":
				return {"ok": false, "why": "that is %s: open to everyone, but nobody may build there" % prot}
			if height(w, x, z) > BUILD_MAX_HEIGHT or slope(w, x, z) > 0.15:
				return {"ok": false, "why": "the ground there is too steep to build on"}
			if is_forest(w, x, z):
				trees += 1
			z += step
		x += step
	out["wooded"] = trees * 3 >= n
	var c: Vector2 = r.get_center()
	out["lakefront"] = water_distance(w, c.x, c.y) < maxf(r.size.x, r.size.y) * 0.5 + 25.0
	var m: Dictionary = t(w)["mountain"]
	out["view"] = c.distance_to(m["c"]) < float(m["r"]) * 1.6
	return out


static func lake_name(w: LTWorld, x: float, z: float) -> String:
	var i: int = lake_at(w, x, z)
	return str(t(w)["lakes"][i]["name"]) if i >= 0 else "the lake"


## How much more a 10 meter piece of road costs here than on flat open prairie,
## and why: a bridge over water, a hillside, or trees to clear.
static func road_cost(w: LTWorld, a: Vector2, b: Vector2) -> Dictionary:
	if t(w).is_empty():
		return {"factor": 1.0, "kind": "", "ok": true}
	var m: Vector2 = (a + b) * 0.5
	var prot: String = protected(w, m.x, m.y)
	if prot != "":
		return {"factor": 0.0, "kind": "protected", "ok": false, "why": "the road would cross %s, where nobody may build" % prot}
	if is_water(w, m.x, m.y):
		return {"factor": BRIDGE_COST, "kind": "bridge", "ok": true}
	if height(w, m.x, m.y) > BUILD_MAX_HEIGHT * 2.5:
		return {"factor": 0.0, "kind": "steep", "ok": false, "why": "the mountainside is too steep for a town road"}
	var f: float = 1.0 + slope(w, m.x, m.y) * HILL_COST
	var kind: String = "hill" if f > 1.15 else ""
	if is_forest(w, m.x, m.y):
		f += CLEAR_COST
		kind = "forest" if kind == "" else kind
	return {"factor": f, "kind": kind, "ok": true}


## The empty lot in these zones nearest a land feature ("lake", "forest",
## "mountain"), within `reach` meters, or -1.
static func site_near(w: LTWorld, zones: Array, feature: String, reach: float, lakefront: bool = false) -> int:
	# founders ask this often; the answer only changes when lots change, so once a day
	var key: String = "%s|%s|%d|%s" % [str(zones), feature, int(reach), lakefront]
	if int(w.market.get("near_day", -1)) != w.day:
		w.market["near_day"] = w.day
		w.market["near_cache"] = {}
	if w.market["near_cache"].has(key):
		var cached: int = int(w.market["near_cache"][key])
		if cached < 0 or str(w.lot(cached)["use"]) == "empty":
			return cached
	var r: int = _site_near(w, zones, feature, reach, lakefront)
	w.market["near_cache"][key] = r
	return r


static func _site_near(w: LTWorld, zones: Array, feature: String, reach: float, lakefront: bool) -> int:
	var best: int = -1
	var best_d: float = reach
	for l in w.lots:
		if str(l["use"]) != "empty" or bool(l.get("hold", false)) or bool(l.get("removed", false)) or not zones.has(str(l["zone"])):
			continue
		if lakefront and not bool(l.get("lakefront", false)):
			continue
		var c: Vector2 = Vector2((float(l["x0"]) + float(l["x1"])) * 0.5, (float(l["z0"]) + float(l["z1"])) * 0.5)
		var d: float = feature_distance(w, feature, c)
		if d < best_d:
			best_d = d
			best = int(l["id"])
	return best


static func feature_distance(w: LTWorld, feature: String, p: Vector2) -> float:
	var tt: Dictionary = t(w)
	if tt.is_empty():
		return 1e9
	match feature:
		"lake":
			return water_distance(w, p.x, p.y)
		"forest":
			var f: Dictionary = tt["forest"]
			return maxf(0.0, p.distance_to(f["c"]) - minf(float(f["rx"]), float(f["rz"])))
		"mountain":
			var m: Dictionary = tt["mountain"]
			return maxf(0.0, p.distance_to(m["c"]) - float(m["r"]) * 0.75)
	return 1e9


## Spots for outdoor life: along a lake shore, at the forest edge, and a trail up
## the mountain from its foot to the top. In meters, built once from the seed.
static func shore_spots(w: LTWorld, lake: int, n: int) -> Array:
	var lk: Dictionary = t(w)["lakes"][lake]
	var c: Vector2 = lk["c"]
	var out: Array = []
	for i in n:
		var a: float = TAU * float(i) / float(n)
		out.append(c + Vector2(cos(a) * (float(lk["rx"]) + 4.0), sin(a) * (float(lk["rz"]) + 4.0)))
	return out


static func trail(w: LTWorld) -> Array:
	var m: Dictionary = t(w)["mountain"]
	var c: Vector2 = m["c"]
	var toward: Vector2 = (Vector2(MAP_W, MAP_H) * 0.5 - c).normalized()
	var start: Vector2 = c + toward * float(m["r"]) * 0.95
	var out: Array = []
	var steps: int = 24
	for i in steps + 1:
		var k: float = float(i) / float(steps)
		# switchbacks up the slope
		var side: Vector2 = Vector2(-toward.y, toward.x) * sin(k * PI * 5.0) * 30.0 * (1.0 - k)
		out.append(start.lerp(c, k * 0.97) + side)
	return out


# ---------------------------------------------------------------- what was here first

## The county around the town was settled long before it: farmsteads with a red
## barn, silos and a windbreak of trees, a grain elevator on the railroad, a white
## country church with its cemetery, the old one room schoolhouse, windmills over
## stock tanks, cabins on the lake and a fire lookout on the mountain. Each map
## seed lays them out its own way. They belong to the neighbors and the county.
static func landmarks(w: LTWorld) -> Array:
	var tt: Dictionary = t(w)
	if tt.is_empty():
		return []
	_find_road_z(w)
	if not tt.has("landmarks"):
		var av: Array = tt.get("avoid", [MAP_W * 0.5 - 300.0, MAP_H * 0.5 - 180.0, 600.0, 360.0])
		tt["landmarks"] = _make_landmarks(w, int(tt["seed"]), Rect2(float(av[0]), float(av[1]), float(av[2]), float(av[3])))
	return tt["landmarks"]


static var _road_z: float = MAP_H * 0.5


## Where the county road runs across the map.
static func road_z() -> float:
	return _road_z


static func _find_road_z(w: LTWorld) -> void:
	if w.config.has("exit_node") and not w.road_nodes.is_empty():
		_road_z = float(w.road_nodes[int(w.config["exit_node"])]["y"]) * LTGeography.GRID
	else:
		_road_z = MAP_H * 0.5


static func rail_z(w: LTWorld) -> float:
	if not t(w).has("rail_z"):
		landmarks(w)
	return float(t(w).get("rail_z", road_z() - 70.0))


static func _make_landmarks(w: LTWorld, map_seed: int, avoid: Rect2) -> Array:
	_find_road_z(w)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = map_seed * 7919 + 17
	var out: Array = []
	var keep: Rect2 = avoid.grow(110.0)
	var rz: float = road_z() + (-1.0 if rng.randf() < 0.5 else 1.0) * rng.randf_range(160.0, 230.0)
	if not bool(w.config.get("open_land", false)):
		# an old town grew up beside the tracks, not on them
		rz = avoid.position.y - 30.0 if rng.randf() < 0.5 else avoid.end.y + 30.0
	t(w)["rail_z"] = rz
	var fits: Callable = func(p: Vector2, gap: float, wooded_ok: bool) -> bool:
		if p.x < 40.0 or p.y < 40.0 or p.x > MAP_W - 40.0 or p.y > MAP_H - 40.0 or keep.has_point(p):
			return false
		if absf(p.y - road_z()) < 32.0 or absf(p.y - rz) < 22.0:
			return false
		if water_distance(w, p.x, p.y) < 18.0 or height(w, p.x, p.y) > BUILD_MAX_HEIGHT * 0.8 or slope(w, p.x, p.y) > 0.12:
			return false
		if not wooded_ok and forest_value(w, p.x, p.y) > -0.05:
			return false
		for o in out:
			if p.distance_to(Vector2(float(o["x"]), float(o["z"]))) < gap:
				return false
		return true
	var place: Callable = func(kind: String, n: int, gap: float, wooded_ok: bool, near_road: float) -> Array:
		var got: Array = []
		for tries in n * 60:
			if got.size() >= n:
				break
			var p: Vector2 = Vector2(rng.randf_range(60.0, MAP_W - 60.0), rng.randf_range(60.0, MAP_H - 60.0))
			if near_road > 0.0:
				p.y = road_z() + (-1.0 if rng.randf() < 0.5 else 1.0) * rng.randf_range(40.0, near_road)
			if fits.call(p, gap, wooded_ok):
				# face the county road, the way farmhouses and churches were set
				var e: Dictionary = {"kind": kind, "x": p.x, "z": p.y, "rot": 0.0 if p.y < road_z() else PI}
				out.append(e)
				got.append(e)
		return got
	var names: Array = LTPeople.LAST_NAMES.duplicate()
	for f in place.call("farmstead", rng.randi_range(4, 7), 170.0, false, 0.0):
		f["name"] = "%s farm" % names[rng.randi_range(0, names.size() - 1)]
		f["silos"] = rng.randi_range(1, 3)
		f["barn"] = ["red", "red", "white", "gray"][rng.randi_range(0, 3)]
		f["cattle"] = rng.randf() < 0.6
	# the elevator stands on the rail siding by the county road
	for tries in 80:
		var ex: float = rng.randf_range(120.0, MAP_W - 120.0)
		var ep: Vector2 = Vector2(ex, rz + (14.0 if rz > road_z() else -14.0))
		if not keep.grow(-40.0).has_point(ep) and water_distance(w, ep.x, ep.y) > 30.0 and height(w, ep.x, ep.y) < BUILD_MAX_HEIGHT:
			out.append({"kind": "elevator", "x": ep.x, "z": ep.y, "rot": 0.0, "name": "%s Grain Co op elevator" % ["Farmers", "Prairie", "Valley", "Dakota"][rng.randi_range(0, 3)]})
			break
	for c in place.call("church", 1, 220.0, false, 140.0):
		c["name"] = "%s Lutheran Church and cemetery" % ["St. John's", "Trinity", "Zion", "Our Savior's", "Bethany"][rng.randi_range(0, 4)]
	for c in place.call("schoolhouse", 1, 200.0, false, 0.0):
		c["name"] = "District %d schoolhouse, closed since %d" % [rng.randi_range(3, 41), rng.randi_range(1952, 1968)]
	for c in place.call("windmill", rng.randi_range(2, 4), 120.0, false, 0.0):
		c["name"] = "windmill and stock tank"
	# cabins and a boat ramp on the big lake
	var lakes: Array = t(w)["lakes"]
	if not lakes.is_empty():
		var lk: Dictionary = lakes[0]
		var c0: Vector2 = lk["c"]
		var n: int = rng.randi_range(2, 4)
		var a0: float = rng.randf_range(0.0, TAU)
		for i in n + 1:
			var a: float = a0 + float(i) * 0.38
			var p: Vector2 = c0 + Vector2(cos(a) * (float(lk["rx"]) + 22.0), sin(a) * (float(lk["rz"]) + 22.0))
			if keep.has_point(p) or height(w, p.x, p.y) > BUILD_MAX_HEIGHT:
				continue
			var face: float = atan2(c0.x - p.x, c0.y - p.y)
			out.append({"kind": "dock" if i == n else "cabin", "x": p.x, "z": p.y, "rot": face, "name": "public boat ramp" if i == n else "%s cabin" % names[rng.randi_range(0, names.size() - 1)]})
	# a fire lookout near the top of the mountain
	var m: Dictionary = t(w)["mountain"]
	var mc: Vector2 = m["c"]
	var lp: Vector2 = mc + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized() * float(m["r"]) * 0.12
	out.append({"kind": "lookout", "x": lp.x, "z": lp.y, "rot": 0.0, "name": "fire lookout tower"})
	return out
