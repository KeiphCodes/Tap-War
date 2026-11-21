extends Node3D
## The 3D town, built procedurally from the data. Buildings show their state.
## Sims near the camera or on the watch list (Tier 1) walk and drive their day.
## Everyone else is still fully simulated, just not drawn.

const CELL: float = 18.0
const ROAD_W: float = 4.2
const MAX_SIMS: int = 45
const SKIN: Array = [Color(0.96, 0.8, 0.69), Color(0.87, 0.67, 0.5), Color(0.76, 0.55, 0.38), Color(0.6, 0.42, 0.28), Color(0.45, 0.31, 0.2), Color(0.33, 0.22, 0.15)]
const HAIR: Array = [Color(0.1, 0.08, 0.06), Color(0.3, 0.2, 0.1), Color(0.55, 0.35, 0.15), Color(0.85, 0.7, 0.4), Color(0.6, 0.6, 0.6), Color(0.9, 0.9, 0.88), Color(0.5, 0.15, 0.08)]

var main: Node
var w: LTWorld
var ground_root: Node3D
var road_root: Node3D
var lot_root: Node3D
var people_root: Node3D
var extra_root: Node3D
var lot_nodes: Dictionary = {}
var lot_sigs: Dictionary = {}
var road_nodes_mesh: Dictionary = {}
var sim_nodes: Dictionary = {}
var truck_nodes: Array = []
var mats: Dictionary = {}
var ground_mi: MeshInstance3D
var sun: DirectionalLight3D
var env: Environment
var cam: Camera3D
var target: Vector3 = Vector3.ZERO
var yaw: float = 0.75
var pitch: float = -0.85
var dist: float = 95.0
var _drag_rot: bool = false
var _drag_pan: bool = false
var _tier_timer: float = 0.0
var _last_hour: float = 9.0
var _watch_mode: bool = false
var _season: String = ""
var _snow: bool = false
var _touches: Dictionary = {}
var _pinch_d: float = 0.0
var hovered_lot: int = -1
# batching: while on, shapes are merged into one mesh with vertex colors
var _batching: bool = false
var _bv: PackedVector3Array
var _bn: PackedVector3Array
var _bc: PackedColorArray
var _bi: PackedInt32Array
var _gv: PackedVector3Array
var _gn: PackedVector3Array
var _gc: PackedColorArray
var _gi: PackedInt32Array
var _prim_cache: Dictionary = {}
var _batch_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var road_mi: MeshInstance3D
var tree_mi: MeshInstance3D
var _roads_built_day: int = -1
var selected_lot: int = -1
var highlight: MeshInstance3D


func setup(p_main: Node) -> void:
	main = p_main
	w = main.world
	_build_env()
	_build_camera()
	rebuild()


func rebuild() -> void:
	w = main.world
	for r in [ground_root, road_root, lot_root, people_root, extra_root]:
		if r != null:
			r.queue_free()
	lot_nodes.clear()
	lot_sigs.clear()
	road_nodes_mesh.clear()
	sim_nodes.clear()
	truck_nodes.clear()
	ground_root = Node3D.new()
	road_root = Node3D.new()
	lot_root = Node3D.new()
	people_root = Node3D.new()
	extra_root = Node3D.new()
	camper = null
	for r in [ground_root, road_root, lot_root, people_root, extra_root]:
		add_child(r)
	_build_ground()
	_build_roads()
	_build_trees()
	highlight = MeshInstance3D.new()
	var hm: BoxMesh = BoxMesh.new()
	hm.size = Vector3(CELL - ROAD_W, 0.15, CELL - ROAD_W)
	highlight.mesh = hm
	var hmat: StandardMaterial3D = StandardMaterial3D.new()
	hmat.albedo_color = Color(1.0, 0.85, 0.2, 0.35)
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	highlight.material_override = hmat
	highlight.visible = false
	extra_root.add_child(highlight)
	var cols: int = int(w.config["lot_cols"])
	var rows: int = int(w.config["lot_rows"])
	target = Vector3(cols * CELL * 0.5, 0.0, rows * CELL * 0.5)
	dist = maxf(cols, rows) * CELL * 1.05
	_update_camera()
	refresh_all()


# ------------------------------------------------------------------ materials and shapes

func _mat(c: Color, glow: bool = false) -> StandardMaterial3D:
	var key: String = "%s|%s" % [c.to_html(), glow]
	if mats.has(key):
		return mats[key]
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	if glow:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.9
	mats[key] = m
	return m


func _batch_begin() -> void:
	_batching = true
	_bv = PackedVector3Array()
	_bn = PackedVector3Array()
	_bc = PackedColorArray()
	_bi = PackedInt32Array()
	_gv = PackedVector3Array()
	_gn = PackedVector3Array()
	_gc = PackedColorArray()
	_gi = PackedInt32Array()


func _batch_end(parent: Node3D) -> MeshInstance3D:
	_batching = false
	if _batch_mat == null:
		_batch_mat = StandardMaterial3D.new()
		_batch_mat.vertex_color_use_as_albedo = true
		_batch_mat.roughness = 0.85
		_glow_mat = StandardMaterial3D.new()
		_glow_mat.vertex_color_use_as_albedo = true
		_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var am: ArrayMesh = ArrayMesh.new()
	if not _bv.is_empty():
		var a: Array = []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = _bv
		a[Mesh.ARRAY_NORMAL] = _bn
		a[Mesh.ARRAY_COLOR] = _bc
		a[Mesh.ARRAY_INDEX] = _bi
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		am.surface_set_material(am.get_surface_count() - 1, _batch_mat)
	if not _gv.is_empty():
		var g: Array = []
		g.resize(Mesh.ARRAY_MAX)
		g[Mesh.ARRAY_VERTEX] = _gv
		g[Mesh.ARRAY_NORMAL] = _gn
		g[Mesh.ARRAY_COLOR] = _gc
		g[Mesh.ARRAY_INDEX] = _gi
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, g)
		am.surface_set_material(am.get_surface_count() - 1, _glow_mat)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = am
	parent.add_child(mi)
	return mi


func _batch_add(pm: PrimitiveMesh, key: String, xf: Transform3D, c: Color, glow: bool) -> void:
	if not _prim_cache.has(key):
		_prim_cache[key] = pm.get_mesh_arrays()
	var arrs: Array = _prim_cache[key]
	var verts: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrs[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrs[Mesh.ARRAY_INDEX]
	if glow:
		var base_g: int = _gv.size()
		for v in verts:
			_gv.append(xf * v)
			_gc.append(c)
		for nn in norms:
			_gn.append((xf.basis * nn).normalized())
		for k in idx:
			_gi.append(base_g + k)
	else:
		var base: int = _bv.size()
		for v in verts:
			_bv.append(xf * v)
			_bc.append(c)
		for nn in norms:
			_bn.append((xf.basis * nn).normalized())
		for k in idx:
			_bi.append(base + k)


func _box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, glow: bool = false, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	if _batching:
		var unit: BoxMesh = BoxMesh.new()
		var xf: Transform3D = Transform3D(Basis.from_euler(rot) * Basis.from_scale(size), pos)
		_batch_add(unit, "box", xf, c, glow)
		return null
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.rotation = rot
	mi.position = pos
	mi.material_override = _mat(c, glow)
	parent.add_child(mi)
	return mi


func _roof(parent: Node3D, size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	if _batching:
		_batch_add(PrismMesh.new(), "prism", Transform3D(Basis().scaled(size), pos), c, false)
		return null
	var mi: MeshInstance3D = MeshInstance3D.new()
	var pm: PrismMesh = PrismMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.position = pos
	mi.material_override = _mat(c)
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, c: Color) -> MeshInstance3D:
	if _batching:
		var cu: CylinderMesh = CylinderMesh.new()
		cu.top_radius = 0.5
		cu.bottom_radius = 0.5
		cu.height = 1.0
		cu.radial_segments = 8
		cu.rings = 1
		_batch_add(cu, "cyl", Transform3D(Basis().scaled(Vector3(r * 2.0, h, r * 2.0)), pos), c, false)
		return null
	var mi: MeshInstance3D = MeshInstance3D.new()
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 8
	mi.mesh = cm
	mi.position = pos
	mi.material_override = _mat(c)
	parent.add_child(mi)
	return mi


func _ball(parent: Node3D, r: float, pos: Vector3, c: Color) -> MeshInstance3D:
	if _batching:
		var su: SphereMesh = SphereMesh.new()
		su.radius = 0.5
		su.height = 1.0
		su.radial_segments = 10
		su.rings = 6
		_batch_add(su, "ball", Transform3D(Basis().scaled(Vector3.ONE * r * 2.0), pos), c, false)
		return null
	var mi: MeshInstance3D = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	mi.position = pos
	mi.material_override = _mat(c)
	parent.add_child(mi)
	return mi


func _sign(parent: Node3D, text: String, pos: Vector3, size: int, c: Color = Color.WHITE) -> Label3D:
	var l: Label3D = Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = size
	l.pixel_size = 0.045
	l.modulate = c
	l.outline_size = 6
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	parent.add_child(l)
	return l


# ------------------------------------------------------------------ environment

func _build_env() -> void:
	var we: WorldEnvironment = WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.78, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.5
	env.fog_enabled = false
	env.fog_light_color = Color(0.7, 0.8, 0.9)
	env.fog_density = 0.0007
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 260.0
	sun.light_energy = 1.15
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(35.0), 0.0)
	add_child(sun)


func _build_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.far = 2000.0
	add_child(cam)
	cam.current = true


func _update_camera() -> void:
	pitch = clampf(pitch, -1.45, -0.25)
	dist = clampf(dist, 18.0, 420.0)
	var dir: Vector3 = Vector3(cos(pitch) * sin(yaw), -sin(pitch), cos(pitch) * cos(yaw))
	cam.position = target + dir * dist
	cam.look_at(target, Vector3.UP)


func _build_ground() -> void:
	ground_mi = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(1400, 1400)
	ground_mi.mesh = pm
	var cols: int = int(w.config["lot_cols"])
	var rows: int = int(w.config["lot_rows"])
	ground_mi.position = Vector3(cols * CELL * 0.5, -0.05, rows * CELL * 0.5)
	ground_root.add_child(ground_mi)
	# the highway to the next town
	var ex: int = LTGeography.exit_node(w)
	var en: Dictionary = w.road_nodes[ex]
	var z: float = float(en["y"]) * CELL
	_box(ground_root, Vector3(400.0, 0.08, ROAD_W + 1.0), Vector3(-200.0, 0.02, z), Color(0.25, 0.25, 0.27))
	var sgn: Label3D = _sign(ground_root, "To County Seat (25 min)", Vector3(-30.0, 3.0, z - 4.0), 64)
	sgn.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y


func _build_roads() -> void:
	_rebuild_road_mesh()
	for st in w.streets:
		if str(st["kind"]) == "street":
			var sid: int = int(st["segments"][0])
			var s0: Dictionary = w.roads[sid]
			var a2: Dictionary = w.road_nodes[int(s0["a"])]
			var l: Label3D = _sign(road_root, str(st["name"]), Vector3(float(a2["x"]) * CELL + CELL * 0.5, 0.25, float(a2["y"]) * CELL), 40, Color(0.95, 0.95, 0.8))
			l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			l.rotation = Vector3(-PI / 2.0, 0.0, 0.0)


func _rebuild_road_mesh() -> void:
	if road_mi != null:
		road_mi.queue_free()
	_batch_begin()
	for s in w.roads:
		var a: Dictionary = w.road_nodes[int(s["a"])]
		var b: Dictionary = w.road_nodes[int(s["b"])]
		var pa: Vector3 = Vector3(float(a["x"]) * CELL, 0.03, float(a["y"]) * CELL)
		var pb: Vector3 = Vector3(float(b["x"]) * CELL, 0.03, float(b["y"]) * CELL)
		var horiz: bool = absf(pa.z - pb.z) < 0.01
		var size: Vector3 = Vector3(CELL + ROAD_W, 0.06, ROAD_W) if horiz else Vector3(ROAD_W, 0.06, CELL + ROAD_W)
		var cnd: float = float(s["condition"]) / 100.0
		var col: Color = Color(0.24, 0.24, 0.26).lerp(Color(0.5, 0.44, 0.36), clampf(1.0 - cnd, 0.0, 1.0) * 0.9)
		if _snow:
			col = col.lerp(Color(0.85, 0.87, 0.9), 0.5)
		_box(road_root, size, (pa + pb) * 0.5, col)
	road_mi = _batch_end(road_root)


func _build_trees() -> void:
	if tree_mi != null:
		tree_mi.queue_free()
	var leaf: Color = _leaf_color()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = w.seed_value
	var cols: int = int(w.config["lot_cols"])
	var rows: int = int(w.config["lot_rows"])
	var exit_z: float = float(w.road_nodes[LTGeography.exit_node(w)]["y"]) * CELL
	_batch_begin()
	for i in 90:
		var side: int = rng.randi_range(0, 3)
		var p: Vector3
		match side:
			0:
				p = Vector3(rng.randf_range(-40.0, cols * CELL + 40.0), 0.0, rng.randf_range(-40.0, -8.0))
			1:
				p = Vector3(rng.randf_range(-40.0, cols * CELL + 40.0), 0.0, rows * CELL + rng.randf_range(8.0, 50.0))
			2:
				p = Vector3(rng.randf_range(-50.0, -8.0), 0.0, rng.randf_range(0.0, rows * CELL))
			_:
				p = Vector3(cols * CELL + rng.randf_range(8.0, 50.0), 0.0, rng.randf_range(0.0, rows * CELL))
		var h: float = rng.randf_range(3.0, 6.5)
		if absf(p.z - exit_z) < 5.0 and p.x < 0.0:
			continue
		_cyl(extra_root, 0.25, h * 0.5, p + Vector3(0, h * 0.25, 0), Color(0.35, 0.25, 0.15))
		_ball(extra_root, h * 0.32, p + Vector3(0, h * 0.65, 0), leaf.lerp(Color(0.2, 0.3, 0.15), rng.randf() * 0.25))
	tree_mi = _batch_end(extra_root)


func _leaf_color() -> Color:
	match _season:
		"Winter":
			return Color(0.42, 0.36, 0.3) if not _snow else Color(0.85, 0.88, 0.9)
		"Spring":
			return Color(0.4, 0.65, 0.3)
		"Fall":
			return Color(0.82, 0.45, 0.15)
	return Color(0.22, 0.48, 0.18)


# ------------------------------------------------------------------ refresh from data

func refresh_all() -> void:
	w = main.world
	var season: String = LTCalendar.season(w.day)
	var snow: bool = w.weather == "Snow"
	if season != _season or snow != _snow:
		_season = season
		_snow = snow
		_apply_season()
		_build_trees()
	if w.day % 7 == 0 or not _roads_built_day == w.day:
		_roads_built_day = w.day
		_rebuild_road_mesh()
	for l in w.lots:
		var sig: String = _lot_sig(l)
		if lot_sigs.get(int(l["id"]), "") != sig:
			lot_sigs[int(l["id"])] = sig
			_build_lot(l)
	_refresh_tier()
	_refresh_trucks()
	_refresh_camper()


func _apply_season() -> void:
	var g: Color = Color(0.42, 0.6, 0.3)
	var leaf: Color = Color(0.25, 0.5, 0.2)
	match _season:
		"Winter":
			g = Color(0.8, 0.82, 0.85) if _snow else Color(0.46, 0.47, 0.36)
			leaf = Color(0.4, 0.33, 0.25)
		"Spring":
			g = Color(0.45, 0.65, 0.32)
			leaf = Color(0.4, 0.65, 0.3)
		"Summer":
			g = Color(0.45, 0.6, 0.28)
			leaf = Color(0.22, 0.48, 0.18)
		"Fall":
			g = Color(0.6, 0.55, 0.32)
			leaf = Color(0.8, 0.45, 0.15)
	if _snow:
		g = Color(0.8, 0.82, 0.85)
	ground_mi.material_override = _mat(g)


func lot_center(lot_id: int) -> Vector3:
	var l: Dictionary = w.lot(lot_id)
	return Vector3((float(l["col"]) + 0.5) * CELL, 0.0, (float(l["row"]) + 0.5) * CELL)


func _lot_sig(l: Dictionary) -> String:
	var use: String = str(l["use"])
	var extra: String = ""
	match use:
		"business", "closed":
			var b: Dictionary = w.biz(int(l["ref"]))
			if not b.is_empty():
				extra = "%s|%s|%d|%d|%d" % [b["status"], b["name"], mini(int(b["loss_months"]), 2), int(float(b["stock"]) > 5.0), int(float(b.get("produce", 0.0)) / 300.0)]
		"site", "reserved":
			var p: Dictionary = w.projects[int(l["ref"])] if int(l["ref"]) >= 0 and int(l["ref"]) < w.projects.size() else {}
			if not p.is_empty():
				extra = "%s|%d" % [p["status"], int(float(p["progress"]) * 5.0)]
		"house", "apartment":
			var occ: int = 0
			for u in l["units"]:
				if int(u) >= 0:
					occ += 1
			extra = "%d|%s|%d" % [occ, l["owner_kind"], int(float(l["condition"]) / 25.0)]
	return "%s|%s|%s|%s|%s|%s" % [use, l["zone"], l["building"], extra, _season, _snow]


func _zone_color(z: String) -> Color:
	match z:
		"residential":
			return Color(0.5, 0.66, 0.38)
		"commercial":
			return Color(0.55, 0.6, 0.68)
		"agricultural":
			return Color(0.66, 0.58, 0.38)
		"civic":
			return Color(0.62, 0.55, 0.7)
		"park":
			return Color(0.35, 0.62, 0.32)
		"industrial":
			return Color(0.55, 0.53, 0.5)
		"mixed":
			return Color(0.5, 0.65, 0.65)
	return Color(0.5, 0.5, 0.5)


func _hash_color(seed_v: int, palette: Array) -> Color:
	return palette[absi(seed_v * 7919) % palette.size()]


func _build_lot(l: Dictionary) -> void:
	var id: int = int(l["id"])
	if lot_nodes.has(id):
		(lot_nodes[id] as Node3D).queue_free()
	var root: Node3D = Node3D.new()
	root.position = lot_center(id)
	lot_root.add_child(root)
	lot_nodes[id] = root
	_batch_begin()
	var inner: float = CELL - ROAD_W - 0.6
	var pad_col: Color = _zone_color(str(l["zone"]))
	if _snow:
		pad_col = pad_col.lerp(Color(0.9, 0.92, 0.95), 0.3)
	_box(root, Vector3(inner, 0.1, inner), Vector3(0, 0.0, 0), pad_col)
	var use: String = str(l["use"])
	var cond: float = float(l["condition"]) / 100.0
	match use:
		"house":
			_house(root, l, cond)
		"apartment":
			_apartment(root, l, cond)
		"business", "closed":
			_business(root, l)
		"civic":
			_civic(root, l)
		"mayor_house":
			_mayor_house(root, l)
		"site", "reserved":
			_site(root, l)
		"empty":
			if str(l["zone"]) == "commercial" or str(l["zone"]) == "mixed":
				_box(root, Vector3(0.15, 1.6, 0.15), Vector3(-inner * 0.35, 0.8, -inner * 0.35), Color(0.4, 0.3, 0.2))
				var s: Label3D = _sign(root, "Lot %d for lease" % id, Vector3(-inner * 0.35, 2.0, -inner * 0.35), 32)
				s.pixel_size = 0.04
			elif str(l["zone"]) == "agricultural":
				for i in 5:
					_box(root, Vector3(inner * 0.9, 0.08, 0.6), Vector3(0, 0.08, -inner * 0.4 + i * inner * 0.2), Color(0.5, 0.42, 0.3))
			elif str(l["zone"]) == "park":
				for i in 3:
					var tp: Vector3 = Vector3(-4.0 + i * 4.0, 0, 2.0 - i)
					_cyl(root, 0.2, 2.0, tp + Vector3(0, 1.0, 0), Color(0.35, 0.25, 0.15))
					_ball(root, 1.4, tp + Vector3(0, 2.6, 0), _leaf_color())
	_batch_end(root)


func _wear(c: Color, cond: float) -> Color:
	return c.lerp(Color(0.45, 0.42, 0.38), clampf(1.0 - cond, 0.0, 1.0) * 0.55)


func _house(root: Node3D, l: Dictionary, cond: float) -> void:
	var walls: Array = [Color(0.92, 0.88, 0.78), Color(0.75, 0.82, 0.9), Color(0.9, 0.78, 0.66), Color(0.82, 0.9, 0.8), Color(0.95, 0.95, 0.95), Color(0.7, 0.62, 0.55)]
	var roofs: Array = [Color(0.35, 0.2, 0.18), Color(0.25, 0.27, 0.3), Color(0.45, 0.3, 0.2), Color(0.3, 0.35, 0.25)]
	var wc: Color = _wear(_hash_color(int(l["id"]), walls), cond)
	_box(root, Vector3(7.0, 3.6, 6.0), Vector3(0, 1.8, -0.5), wc)
	_roof(root, Vector3(7.6, 2.4, 6.6), Vector3(0, 4.8, -0.5), _hash_color(int(l["id"]) + 3, roofs))
	var occupied: bool = int(l["units"][0]) >= 0
	var lit: bool = occupied
	for x in [-2.0, 2.0]:
		_box(root, Vector3(1.2, 1.0, 0.1), Vector3(x, 2.1, 2.55), Color(1.0, 0.86, 0.5) if lit else Color(0.25, 0.3, 0.35), lit)
	_box(root, Vector3(1.0, 2.0, 0.1), Vector3(0, 1.0, 2.55), Color(0.4, 0.25, 0.15))
	_box(root, Vector3(1.2, 0.05, 4.0), Vector3(0, 0.07, 4.5), Color(0.6, 0.6, 0.6))
	if not occupied:
		var s: Label3D = _sign(root, "For sale", Vector3(3.5, 1.5, 4.5), 28)
		s.pixel_size = 0.04
	if cond < 0.4:
		_box(root, Vector3(1.4, 0.1, 1.1), Vector3(2.0, 2.1, 2.62), Color(0.4, 0.3, 0.2))


func _apartment(root: Node3D, l: Dictionary, cond: float) -> void:
	var units: Array = l["units"]
	var floors: int = maxi(2, (units.size() + 1) / 2)
	var h: float = 3.2 * floors
	var c: Color = _wear(Color(0.72, 0.5, 0.42) if int(l["id"]) % 2 == 0 else Color(0.78, 0.74, 0.66), cond)
	_box(root, Vector3(10.0, h, 7.0), Vector3(0, h * 0.5, -0.5), c)
	_box(root, Vector3(10.4, 0.4, 7.4), Vector3(0, h + 0.2, -0.5), Color(0.3, 0.3, 0.32))
	for f in floors:
		for k in 2:
			var ui: int = f * 2 + k
			var occ: bool = ui < units.size() and int(units[ui]) >= 0
			_box(root, Vector3(2.4, 1.3, 0.1), Vector3(-2.5 + k * 5.0, 1.8 + f * 3.2, 3.05), Color(1.0, 0.86, 0.5) if occ else Color(0.22, 0.26, 0.3), occ)
	var vac: int = 0
	for u in units:
		if int(u) < 0:
			vac += 1
	var owner: String = str(l["name"])
	var txt: String = owner if owner != "" else "Apartments"
	if vac > 0:
		txt += "\n%d for rent" % vac
	var s: Label3D = _sign(root, txt, Vector3(0, h + 1.6, 0), 30)
	s.pixel_size = 0.042


func _business(root: Node3D, l: Dictionary) -> void:
	var b: Dictionary = w.biz(int(l["ref"]))
	if b.is_empty():
		return
	var btype: String = str(b["type"])
	var open: bool = str(b["status"]) == "open"
	var stocked: bool = ["grocery", "cafe", "general_store", "bakery"].has(btype)
	var struggling: bool = open and (int(b["loss_months"]) >= 1 or (stocked and float(b["stock"]) < 5.0))
	var accent: Color = {"grocery": Color(0.2, 0.55, 0.3), "cafe": Color(0.7, 0.35, 0.2), "general_store": Color(0.25, 0.4, 0.65), "farm": Color(0.6, 0.2, 0.15), "construction": Color(0.85, 0.65, 0.1), "bakery": Color(0.85, 0.6, 0.3), "pharmacy": Color(0.2, 0.6, 0.4), "repair_shop": Color(0.3, 0.3, 0.35), "law_office": Color(0.3, 0.25, 0.4), "real_estate": Color(0.2, 0.45, 0.6), "private_school": Color(0.55, 0.15, 0.15)}.get(btype, Color(0.5, 0.5, 0.5))
	if btype == "farm":
		_farm(root, b, open)
	elif ["factory", "mill", "warehouse", "trucking", "hotel", "bank", "clinic", "bar", "childcare", "funeral_home"].has(btype):
		_special(root, b, btype, open, struggling)
	elif btype == "construction":
		_box(root, Vector3(8.0, 4.0, 6.0), Vector3(-1.5, 2.0, -2.0), Color(0.6, 0.6, 0.62))
		_box(root, Vector3(3.0, 1.6, 1.6), Vector3(3.5, 0.9, 3.0), accent)
		_box(root, Vector3(1.6, 1.2, 1.6), Vector3(4.6, 1.8, 3.0), accent)
		for i in 4:
			_box(root, Vector3(3.0, 0.3, 0.3), Vector3(-3.0, 0.2 + i * 0.32, 4.0), Color(0.75, 0.6, 0.4))
	else:
		var wall: Color = Color(0.85, 0.82, 0.75) if open else Color(0.5, 0.48, 0.45)
		_box(root, Vector3(10.0, 4.4, 7.0), Vector3(0, 2.2, -1.0), wall)
		_box(root, Vector3(10.4, 0.5, 7.4), Vector3(0, 4.6, -1.0), Color(0.3, 0.3, 0.32))
		_box(root, Vector3(10.2, 0.3, 1.8), Vector3(0, 3.5, 3.2), accent if open else Color(0.35, 0.33, 0.3))
		var lit: bool = open and not struggling
		var glass: Color = Color(1.0, 0.92, 0.65) if lit else (Color(0.55, 0.5, 0.4) if open else Color(0.15, 0.15, 0.17))
		_box(root, Vector3(7.0, 2.2, 0.1), Vector3(-0.8, 1.5, 2.55), glass, lit)
		if open and float(b["stock"]) > 5.0:
			for i in 4:
				_box(root, Vector3(1.2, 0.8, 0.5), Vector3(-3.5 + i * 1.8, 0.6, 2.2), Color(0.8, 0.6, 0.3))
		_box(root, Vector3(1.2, 2.4, 0.12), Vector3(3.8, 1.2, 2.55), Color(0.35, 0.22, 0.12))
		if not open:
			for i in 3:
				_box(root, Vector3(7.4, 0.35, 0.12), Vector3(-0.8, 0.8 + i * 0.7, 2.65), Color(0.55, 0.42, 0.28), false, Vector3(0, 0, 0.08 * (i - 1)))
		if struggling:
			var sale: Label3D = _sign(root, "SALE", Vector3(-3.0, 2.0, 2.75), 40, Color(1, 0.3, 0.25))
			sale.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			sale.pixel_size = 0.03
	var title: String = str(b["name"])
	if not open:
		title += "\nCLOSED"
	var s: Label3D = _sign(root, title, Vector3(0, 6.6, 0), 36, Color(1, 1, 1) if open else Color(0.75, 0.7, 0.65))
	s.pixel_size = 0.05


func _special(root: Node3D, b: Dictionary, btype: String, open: bool, struggling: bool) -> void:
	var lit: bool = open and not struggling
	var win: Color = Color(1.0, 0.9, 0.6) if lit else (Color(0.5, 0.48, 0.42) if open else Color(0.15, 0.15, 0.17))
	match btype:
		"factory":
			_box(root, Vector3(12.0, 5.0, 8.0), Vector3(0, 2.5, -1.0), Color(0.55, 0.52, 0.5) if open else Color(0.4, 0.38, 0.36))
			_roof(root, Vector3(12.4, 1.6, 8.4), Vector3(0, 5.8, -1.0), Color(0.35, 0.35, 0.38))
			_cyl(root, 0.6, 9.0, Vector3(4.5, 4.5, -3.5), Color(0.5, 0.35, 0.3))
			if open and float(b.get("pollution", 0.0)) > 0.05:
				for i in 3:
					_ball(root, 0.9 + i * 0.4, Vector3(4.5 + i * 0.6, 9.8 + i * 1.1, -3.5), Color(0.45, 0.45, 0.45))
			for i in 4:
				_box(root, Vector3(1.8, 1.2, 0.1), Vector3(-4.5 + i * 3.0, 3.0, 3.05), win, lit)
		"mill":
			_box(root, Vector3(6.0, 7.0, 6.0), Vector3(-2.5, 3.5, -1.0), Color(0.75, 0.7, 0.6))
			_roof(root, Vector3(6.4, 2.0, 6.4), Vector3(-2.5, 8.0, -1.0), Color(0.4, 0.3, 0.25))
			_cyl(root, 1.8, 9.0, Vector3(3.5, 4.5, -1.0), Color(0.78, 0.78, 0.8))
			_ball(root, 1.8, Vector3(3.5, 9.0, -1.0), Color(0.7, 0.7, 0.72))
		"warehouse":
			_box(root, Vector3(13.0, 5.0, 9.0), Vector3(0, 2.5, -1.0), Color(0.62, 0.6, 0.55))
			for i in 3:
				_box(root, Vector3(2.4, 3.0, 0.1), Vector3(-4.0 + i * 4.0, 1.5, 3.55), Color(0.35, 0.4, 0.45))
		"trucking":
			_box(root, Vector3(8.0, 4.0, 6.0), Vector3(-2.5, 2.0, -2.0), Color(0.6, 0.6, 0.62))
			for i in 2:
				_box(root, Vector3(2.2, 2.2, 5.5), Vector3(2.5 + i * 3.0, 1.4, 2.0), Color(0.9, 0.9, 0.9))
				_box(root, Vector3(2.2, 1.6, 1.6), Vector3(2.5 + i * 3.0, 1.0, 5.4), Color(0.6, 0.15, 0.1))
		"hotel":
			_box(root, Vector3(13.0, 3.4, 5.0), Vector3(0, 1.7, -2.0), Color(0.9, 0.85, 0.7))
			_box(root, Vector3(13.4, 0.3, 6.0), Vector3(0, 3.5, -1.6), Color(0.6, 0.25, 0.2))
			for i in 6:
				_box(root, Vector3(0.9, 2.0, 0.1), Vector3(-5.5 + i * 2.2, 1.0, 0.55), Color(0.3, 0.45, 0.6))
				_box(root, Vector3(0.9, 0.7, 0.1), Vector3(-5.0 + i * 2.2, 2.2, 0.55), win, lit)
			_cyl(root, 0.15, 6.0, Vector3(6.0, 3.0, 4.5), Color(0.5, 0.5, 0.5))
			_box(root, Vector3(2.4, 1.2, 0.2), Vector3(6.0, 6.2, 4.5), Color(0.9, 0.3, 0.3) if lit else Color(0.4, 0.3, 0.3), lit)
		"bank":
			_box(root, Vector3(10.0, 5.0, 7.0), Vector3(0, 2.5, -1.0), Color(0.85, 0.83, 0.78))
			_roof(root, Vector3(10.6, 1.6, 2.4), Vector3(0, 5.8, 2.3), Color(0.8, 0.78, 0.72))
			for i in 4:
				_cyl(root, 0.35, 4.6, Vector3(-3.6 + i * 2.4, 2.3, 3.2), Color(0.92, 0.9, 0.86))
			_box(root, Vector3(1.6, 2.6, 0.1), Vector3(0, 1.3, 2.55), Color(0.3, 0.2, 0.15))
		"clinic":
			_box(root, Vector3(9.0, 3.6, 6.5), Vector3(0, 1.8, -1.0), Color(0.93, 0.93, 0.95))
			_box(root, Vector3(1.6, 0.4, 0.1), Vector3(0, 3.0, 2.3), Color(0.15, 0.4, 0.85), true)
			_box(root, Vector3(0.4, 1.6, 0.1), Vector3(0, 3.0, 2.3), Color(0.15, 0.4, 0.85), true)
			_box(root, Vector3(5.0, 1.4, 0.1), Vector3(0, 1.4, 2.3), win, lit)
		"bar":
			_box(root, Vector3(9.0, 4.0, 7.0), Vector3(0, 2.0, -1.0), Color(0.4, 0.28, 0.2))
			_box(root, Vector3(4.0, 1.4, 0.1), Vector3(-1.5, 1.8, 2.55), win, lit)
			_box(root, Vector3(2.4, 0.6, 0.15), Vector3(2.5, 3.2, 2.6), Color(1.0, 0.3, 0.6) if lit else Color(0.3, 0.2, 0.25), lit)
		"childcare":
			_box(root, Vector3(8.0, 3.2, 6.0), Vector3(-1.5, 1.6, -2.0), Color(0.95, 0.85, 0.5))
			_roof(root, Vector3(8.4, 1.6, 6.4), Vector3(-1.5, 4.0, -2.0), Color(0.3, 0.5, 0.8))
			_box(root, Vector3(0.2, 1.8, 2.0), Vector3(4.0, 0.9, 3.0), Color(0.9, 0.3, 0.3))
			_box(root, Vector3(2.0, 0.15, 2.0), Vector3(4.0, 0.08, 3.0), Color(0.9, 0.8, 0.5))
			_ball(root, 0.5, Vector3(2.0, 0.5, 4.0), Color(0.3, 0.7, 0.3))
			for i in 3:
				_box(root, Vector3(1.2, 1.0, 0.1), Vector3(-4.0 + i * 2.5, 1.8, 1.05), win, lit)
		"funeral_home":
			_box(root, Vector3(9.0, 4.0, 7.0), Vector3(0, 2.0, -1.0), Color(0.82, 0.8, 0.78))
			_roof(root, Vector3(9.4, 2.4, 7.4), Vector3(0, 5.2, -1.0), Color(0.2, 0.2, 0.22))
			_box(root, Vector3(1.4, 4.0, 1.4), Vector3(0, 7.5, 2.0), Color(0.82, 0.8, 0.78))
			_roof(root, Vector3(1.6, 2.0, 1.6), Vector3(0, 10.5, 2.0), Color(0.2, 0.2, 0.22))
	if bool(b.get("unlicensed", false)) and open:
		var u: Label3D = _sign(root, "no license posted", Vector3(-3.0, 1.0, 3.2), 22, Color(1.0, 0.6, 0.4))
		u.pixel_size = 0.03


func _farm(root: Node3D, b: Dictionary, open: bool) -> void:
	var inner: float = CELL - ROAD_W - 1.0
	var crop: Color
	match _season:
		"Spring":
			crop = Color(0.45, 0.62, 0.3)
		"Summer":
			crop = Color(0.3, 0.55, 0.2)
		"Fall":
			crop = Color(0.8, 0.68, 0.3)
		_:
			crop = Color(0.5, 0.42, 0.32)
	if not open:
		crop = Color(0.55, 0.5, 0.35)
	var hgt: float = 0.15 + (0.6 if _season == "Summer" or _season == "Fall" else 0.15)
	for i in 6:
		_box(root, Vector3(inner * 0.62, hgt, 0.8), Vector3(-inner * 0.17, hgt * 0.5, -inner * 0.42 + i * inner * 0.16), crop)
	_box(root, Vector3(4.0, 4.0, 5.0), Vector3(inner * 0.32, 2.0, 0.0), Color(0.62, 0.18, 0.14) if open else Color(0.45, 0.3, 0.28))
	_roof(root, Vector3(4.4, 1.8, 5.4), Vector3(inner * 0.32, 4.9, 0.0), Color(0.3, 0.3, 0.3))
	_cyl(root, 0.9, 5.0, Vector3(inner * 0.32, 2.5, -3.6), Color(0.75, 0.75, 0.78))
	if open and b["staff"].size() + 1 > 0 and _season != "Winter":
		# the tractor works the rows it has planted
		var tz: float = -inner * 0.42 + float(w.day % 6) * inner * 0.16
		_box(root, Vector3(1.4, 1.0, 2.2), Vector3(-inner * 0.1, 0.9, tz), Color(0.75, 0.15, 0.1))
		_cyl(root, 0.55, 0.4, Vector3(-inner * 0.1 - 0.8, 0.55, tz - 0.6), Color(0.15, 0.15, 0.15))
		_cyl(root, 0.55, 0.4, Vector3(-inner * 0.1 + 0.8, 0.55, tz - 0.6), Color(0.15, 0.15, 0.15))


func _mayor_house(root: Node3D, l: Dictionary) -> void:
	var c: Color = _wear(Color(0.95, 0.93, 0.86), float(l["condition"]) / 100.0)
	_box(root, Vector3(10.0, 4.2, 7.0), Vector3(0, 2.1, -1.0), c)
	_roof(root, Vector3(10.6, 2.6, 7.6), Vector3(0, 5.5, -1.0), Color(0.25, 0.28, 0.35))
	_box(root, Vector3(10.4, 0.25, 2.2), Vector3(0, 3.2, 3.4), Color(0.85, 0.83, 0.78))
	for x in [-4.6, -1.6, 1.6, 4.6]:
		_cyl(root, 0.18, 3.2, Vector3(x, 1.6, 4.3), Color(0.95, 0.95, 0.95))
	for x in [-3.0, 3.0]:
		_box(root, Vector3(1.6, 1.3, 0.1), Vector3(x, 2.2, 2.55), Color(1.0, 0.88, 0.55), true)
	_box(root, Vector3(1.3, 2.3, 0.1), Vector3(0, 1.15, 2.55), Color(0.35, 0.2, 0.12))
	_cyl(root, 0.07, 8.0, Vector3(5.5, 4.0, 5.5), Color(0.85, 0.85, 0.85))
	_box(root, Vector3(1.6, 1.0, 0.05), Vector3(6.35, 7.4, 5.5), Color(0.2, 0.3, 0.65))
	var s2: Label3D = _sign(root, "%s\nMayor %s" % [l["name"], w.player.get("name", "")], Vector3(0, 8.0, 0), 34, Color(1.0, 0.92, 0.6))
	s2.pixel_size = 0.05


func _civic(root: Node3D, l: Dictionary) -> void:
	var kind: String = str(l["building"])
	match kind:
		"school":
			_box(root, Vector3(11.0, 4.0, 7.0), Vector3(0, 2.0, -1.0), Color(0.68, 0.33, 0.25))
			_box(root, Vector3(11.4, 0.4, 7.4), Vector3(0, 4.2, -1.0), Color(0.3, 0.3, 0.3))
			for i in 4:
				_box(root, Vector3(1.6, 1.3, 0.1), Vector3(-4.0 + i * 2.6, 2.2, 2.55), Color(1.0, 0.9, 0.6), true)
			_cyl(root, 0.08, 7.0, Vector3(5.5, 3.5, 4.0), Color(0.8, 0.8, 0.8))
			_box(root, Vector3(1.4, 0.9, 0.05), Vector3(6.2, 6.4, 4.0), Color(0.2, 0.3, 0.6))
		"clinic":
			_box(root, Vector3(9.0, 3.6, 6.5), Vector3(0, 1.8, -1.0), Color(0.93, 0.93, 0.95))
			_box(root, Vector3(1.6, 0.4, 0.1), Vector3(0, 3.0, 2.3), Color(0.85, 0.15, 0.15), true)
			_box(root, Vector3(0.4, 1.6, 0.1), Vector3(0, 3.0, 2.3), Color(0.85, 0.15, 0.15), true)
			_box(root, Vector3(5.0, 1.4, 0.1), Vector3(0, 1.4, 2.3), Color(0.7, 0.85, 0.95), true)
		"park":
			for i in 5:
				var tp2: Vector3 = Vector3(-5.0 + (i % 3) * 5.0, 0, -4.0 + (i / 3) * 6.0)
				_cyl(root, 0.22, 2.2, tp2 + Vector3(0, 1.1, 0), Color(0.35, 0.25, 0.15))
				_ball(root, 1.6, tp2 + Vector3(0, 2.9, 0), _leaf_color())
			_box(root, Vector3(2.4, 0.5, 0.7), Vector3(0, 0.45, 4.0), Color(0.5, 0.35, 0.2))
			_box(root, Vector3(3.0, 0.08, 3.0), Vector3(4.0, 0.06, 3.5), Color(0.85, 0.75, 0.5))
	var s: Label3D = _sign(root, str(l["name"]), Vector3(0, 6.0, 0), 34, Color(0.9, 0.95, 1.0))
	s.pixel_size = 0.05


func _site(root: Node3D, l: Dictionary) -> void:
	var p: Dictionary = w.projects[int(l["ref"])] if int(l["ref"]) >= 0 and int(l["ref"]) < w.projects.size() else {}
	if p.is_empty():
		return
	var prog: float = float(p["progress"]) if str(p["status"]) == "building" else 0.0
	var inner: float = CELL - ROAD_W - 1.0
	# fence
	for i in 4:
		var horiz: bool = i < 2
		var off: float = inner * 0.48 * (1.0 if i % 2 == 0 else -1.0)
		_box(root, Vector3(inner if horiz else 0.1, 1.0, 0.1 if horiz else inner), Vector3(0.0 if horiz else off, 0.5, off if horiz else 0.0), Color(0.9, 0.55, 0.15))
	if str(p["status"]) != "building":
		var sg: Label3D = _sign(root, "%s\nout to bid" % p["title"], Vector3(0, 3.0, 0), 30)
		sg.pixel_size = 0.016
		return
	if prog > 0.05:
		_box(root, Vector3(10.0, 0.5, 7.0), Vector3(0, 0.25, -1.0), Color(0.6, 0.6, 0.6))
	if prog > 0.35:
		var fh: float = 4.0 * clampf((prog - 0.35) / 0.3, 0.1, 1.0)
		for x in [-4.8, -1.6, 1.6, 4.8]:
			for z in [-4.3, 2.3]:
				_box(root, Vector3(0.25, fh, 0.25), Vector3(x, 0.5 + fh * 0.5, z), Color(0.85, 0.7, 0.45))
	if prog > 0.65:
		_box(root, Vector3(10.0, 3.6, 7.0), Vector3(0, 2.3, -1.0), Color(0.75, 0.72, 0.65))
	if prog > 0.85:
		_roof(root, Vector3(10.6, 1.8, 7.6), Vector3(0, 5.0, -1.0), Color(0.35, 0.33, 0.3))
	_cyl(root, 0.18, 12.0, Vector3(inner * 0.4, 6.0, inner * 0.4), Color(0.95, 0.75, 0.1))
	if prog < 0.4:
		_box(root, Vector3(2.4, 1.2, 3.2), Vector3(-inner * 0.3, 0.9, inner * 0.3), Color(0.95, 0.7, 0.1))
		_box(root, Vector3(0.4, 0.4, 3.0), Vector3(-inner * 0.3, 2.0, inner * 0.3 - 2.4), Color(0.95, 0.7, 0.1), false, Vector3(0.5, 0, 0))
	_box(root, Vector3(8.0, 0.3, 0.3), Vector3(inner * 0.4 - 3.5, 12.0, inner * 0.4), Color(0.95, 0.75, 0.1))
	var s: Label3D = _sign(root, "%s\n%s, %d%%" % [p["winner_name"], p["stage"], int(prog * 100.0)], Vector3(0, 8.0, 0), 28)
	s.pixel_size = 0.042


# ------------------------------------------------------------------ Sims near the camera (Tier 1)

func _refresh_tier() -> void:
	var want: Array = []
	for cid in w.watch_list:
		var c: Dictionary = w.cit(int(cid))
		if w.is_present(c):
			want.append(int(cid))
	var cand: Array = []
	for c in w.citizens:
		if not w.is_present(c) or want.has(int(c["id"])):
			continue
		var hl: int = int(w.hh(int(c["household"]))["lot"])
		var pos: Vector3 = lot_center(hl) if hl >= 0 else Vector3(-20, 0, 0)
		cand.append([pos.distance_squared_to(target), int(c["id"])])
	cand.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for e in cand:
		if want.size() >= MAX_SIMS:
			break
		if float(e[0]) < pow(dist * 1.1 + 40.0, 2.0):
			want.append(int(e[1]))
	for cid in sim_nodes.keys():
		if not want.has(cid):
			(sim_nodes[cid] as Node3D).queue_free()
			sim_nodes.erase(cid)
	for cid in want:
		if not sim_nodes.has(cid):
			sim_nodes[cid] = _make_sim(w.cit(cid))
		_update_sim_look(sim_nodes[cid], w.cit(cid))


func _make_sim(c: Dictionary) -> Node3D:
	var n: Node3D = Node3D.new()
	n.set_meta("cid", int(c["id"]))
	people_root.add_child(n)
	var body: MeshInstance3D = MeshInstance3D.new()
	var cm: CapsuleMesh = CapsuleMesh.new()
	cm.radius = 0.28
	cm.height = 1.2
	body.mesh = cm
	body.name = "Body"
	n.add_child(body)
	var head: MeshInstance3D = _ball(n, 0.2, Vector3.ZERO, Color.WHITE)
	head.name = "Head"
	var hair: MeshInstance3D = _ball(n, 0.21, Vector3.ZERO, Color.BLACK)
	hair.name = "Hair"
	var car: Node3D = Node3D.new()
	car.name = "Car"
	n.add_child(car)
	_box(car, Vector3(1.8, 0.8, 3.6), Vector3(0, 0.6, 0), Color(0.5, 0.1, 0.1))
	_box(car, Vector3(1.6, 0.6, 1.8), Vector3(0, 1.25, -0.2), Color(0.6, 0.75, 0.85))
	car.visible = false
	n.set_meta("from", Vector3.ZERO)
	n.set_meta("to", Vector3.ZERO)
	return n


func _update_sim_look(n: Node3D, c: Dictionary) -> void:
	var age: int = w.age_years(c)
	var looks: Dictionary = c["looks"]
	var h: float = 1.75 * float(looks["height"])
	if age < 2:
		h = 0.55
	elif age < 13:
		h = 0.75 + float(age) * 0.07
	elif age < 18:
		h = 1.45 + float(age - 13) * 0.05
	elif age >= 70:
		h *= 0.95
	var bw: float = float(looks["build"])
	var body: MeshInstance3D = n.get_node("Body")
	body.scale = Vector3(bw * h / 1.75, h / 1.75, bw * h / 1.75)
	body.position = Vector3(0, h * 0.4, 0)
	var head: MeshInstance3D = n.get_node("Head")
	head.scale = Vector3.ONE * clampf(h / 1.75, 0.6, 1.0) * (1.25 if age < 6 else 1.0)
	head.position = Vector3(0, h * 0.85, 0)
	head.material_override = _mat(SKIN[int(looks["skin"]) % SKIN.size()])
	var hair: MeshInstance3D = n.get_node("Hair")
	hair.scale = head.scale * Vector3(1.0, 0.6, 1.0)
	hair.position = head.position + Vector3(0, 0.08, -0.02)
	var hc: Color = HAIR[int(looks["hair"]) % HAIR.size()]
	if age >= 60:
		hc = Color(0.85, 0.85, 0.85)
	hair.material_override = _mat(hc)
	var cloth: Color = Color(0.5, 0.5, 0.55)
	match str(c["job"]["kind"]):
		"outside":
			cloth = Color(0.3, 0.4, 0.6)
		"business":
			cloth = Color(0.25, 0.55, 0.35)
		"owner":
			cloth = Color(0.6, 0.2, 0.2)
		"city":
			cloth = Color(0.2, 0.25, 0.45)
		_:
			if age < 18:
				cloth = Color(0.85, 0.65, 0.2)
			elif bool(c["retired"]):
				cloth = Color(0.55, 0.45, 0.6)
			else:
				cloth = Color(0.55, 0.5, 0.42)
	if w.cash(c) < 10000 and age >= 18:
		cloth = cloth.lerp(Color(0.45, 0.42, 0.4), 0.5)
	if w.watch_list.has(int(c["id"])):
		cloth = cloth.lerp(Color(1.0, 0.85, 0.2), 0.45)
	body.material_override = _mat(Color(snappedf(cloth.r, 0.02), snappedf(cloth.g, 0.02), snappedf(cloth.b, 0.02)))


## Where a Sim is at an hour, from their real job, school, and home. Visual only.
func sim_plan(c: Dictionary, hour: float) -> Dictionary:
	var hh: Dictionary = w.hh(int(c["household"]))
	var home: int = int(hh["lot"])
	var home_p: Vector3 = lot_center(home) + Vector3(0, 0, 5.0) if home >= 0 else _rough_spot(c)
	var age: int = w.age_years(c)
	var job: Dictionary = c["job"]
	var j: float = float(int(c["id"]) % 7) * 0.12
	var dest: Vector3 = home_p
	var dest_lot: int = home
	var outside: bool = false
	var kind: String = str(job["kind"])
	if age >= 5 and age < 18 and str(c["student"]) != "dropout" and str(c["student"]) != "graduated":
		var sch: Dictionary = LTCivic.service(w, "school")
		if not sch.is_empty():
			dest_lot = int(sch["lot"])
			dest = lot_center(dest_lot) + Vector3(-3.0 + j * 6.0, 0, 5.0)
		else:
			outside = true
	elif kind == "business" or kind == "owner":
		var b: Dictionary = w.biz(int(job["employer"]))
		if not b.is_empty():
			dest_lot = int(b["lot"])
			dest = lot_center(dest_lot) + Vector3(-3.0 + j * 6.0, 0, 4.5)
	elif kind == "city":
		var jobrec: Dictionary = w.city["jobs"][int(job["employer"])]
		var svc: Dictionary = LTCivic.service(w, str(jobrec["service"]))
		if not svc.is_empty():
			dest_lot = int(svc["lot"])
			dest = lot_center(dest_lot) + Vector3(2.0, 0, 5.0)
		else:
			dest_lot = 0
			dest = lot_center(0) + Vector3(0, 0, 5.0)
	elif kind == "outside":
		outside = true
	var weekend: bool = LTCalendar.is_weekend(w.day)
	if weekend or int(c["sick_days"]) > 0 or (age < 5) or bool(c["retired"]) or kind == "none":
		# a stroll in the afternoon, otherwise home
		if hour > 13.0 + j and hour < 15.0 + j and age >= 5 and int(c["sick_days"]) == 0:
			var shop: Array = w.open_businesses("grocery") + w.open_businesses("cafe")
			if not shop.is_empty():
				var sb: Dictionary = shop[int(c["id"]) % shop.size()]
				return _between(home_p, lot_center(int(sb["lot"])) + Vector3(j * 4.0, 0, 5.0), clampf((hour - 13.0 - j) * 2.0, 0.0, 1.0), false, home, int(sb["lot"]))
		return {"pos": home_p + Vector3(sin(float(c["id"])) * 2.0, 0, 0), "visible": hour > 8.0 and hour < 20.0, "car": false, "moving": false}
	var leave: float = 7.0 + j
	var back: float = 17.0 + j
	if hour < leave - 0.1 or hour > back + 1.1:
		return {"pos": home_p, "visible": hour > 6.5 and hour < 21.5, "car": false, "moving": false}
	var exit_p: Vector3 = _exit_pos() + Vector3(-60.0, 0, 0)
	if outside:
		var by_car: bool = age >= 18
		if hour < leave + 1.0:
			return _between(home_p, exit_p, hour - leave, by_car, home, -1)
		if hour > back:
			return _between(exit_p, home_p, hour - back, by_car, -1, home)
		return {"pos": exit_p, "visible": false, "car": false, "moving": false}
	if hour < leave + 1.0:
		return _between(home_p, dest, hour - leave, false, home, dest_lot)
	if hour > back:
		return _between(dest, home_p, hour - back, false, dest_lot, home)
	return {"pos": dest, "visible": true, "car": false, "moving": false}


func _rough_spot(c: Dictionary) -> Vector3:
	var ex: Vector3 = _exit_pos()
	return ex + Vector3(6.0 + float(int(c["id"]) % 5), 0, 4.0)


func _exit_pos() -> Vector3:
	var en: Dictionary = w.road_nodes[LTGeography.exit_node(w)]
	return Vector3(float(en["x"]) * CELL, 0, float(en["y"]) * CELL)


func _node_pos(n: int) -> Vector3:
	var nd: Dictionary = w.road_nodes[n]
	return Vector3(float(nd["x"]) * CELL, 0, float(nd["y"]) * CELL)


## Travel along the roads: down to the street, along it, up the avenue.
func _between(a: Vector3, b: Vector3, t: float, car: bool, from_lot: int, to_lot: int) -> Dictionary:
	t = clampf(t, 0.0, 1.0)
	var pts: Array = [a]
	var na: Vector3 = _node_pos(LTGeography.lot_access_node(w, from_lot)) if from_lot >= 0 else _exit_pos()
	var nb: Vector3 = _node_pos(LTGeography.lot_access_node(w, to_lot)) if to_lot >= 0 else _exit_pos()
	pts.append(Vector3(a.x, 0, na.z))
	pts.append(Vector3(nb.x, 0, na.z))
	pts.append(Vector3(nb.x, 0, b.z))
	pts.append(b)
	var total: float = 0.0
	for i in range(1, pts.size()):
		total += (pts[i] as Vector3).distance_to(pts[i - 1])
	var want: float = total * t
	var acc: float = 0.0
	var pos: Vector3 = b
	var dir: Vector3 = Vector3.FORWARD
	for i in range(1, pts.size()):
		var seg: float = (pts[i] as Vector3).distance_to(pts[i - 1])
		if acc + seg >= want and seg > 0.001:
			pos = (pts[i - 1] as Vector3).lerp(pts[i], (want - acc) / seg)
			dir = ((pts[i] as Vector3) - (pts[i - 1] as Vector3)).normalized()
			break
		acc += seg
	var side: Vector3 = Vector3(dir.z, 0, -dir.x) * (1.2 if car else 2.6)
	return {"pos": pos + side, "visible": t > 0.0 and t < 1.0 or not car, "car": car and t > 0.0 and t < 1.0, "moving": t > 0.0 and t < 1.0, "dir": dir}


func animate(delta: float, hour: float, watch: bool) -> void:
	_watch_mode = watch
	_last_hour = hour
	# sun and sky follow the hour in watch mode
	var day_t: float = (hour - 6.0) / 12.0
	var elev: float = sin(clampf(day_t, 0.0, 1.0) * PI)
	sun.rotation = Vector3(-deg_to_rad(8.0 + 62.0 * elev), deg_to_rad(-60.0 + 120.0 * clampf(day_t, 0.0, 1.0)), 0.0)
	var night: bool = hour < 6.0 or hour > 19.5
	sun.light_energy = 0.05 if night else 0.35 + elev * 0.9
	var sky: Color = Color(0.62, 0.78, 0.92)
	if w.weather == "Rain" or w.weather == "Storm":
		sky = Color(0.5, 0.55, 0.6)
	elif w.weather == "Snow":
		sky = Color(0.78, 0.8, 0.84)
	if night:
		sky = Color(0.06, 0.08, 0.15)
	elif hour < 7.5 or hour > 18.0:
		sky = sky.lerp(Color(0.95, 0.6, 0.4), 0.45)
	env.background_color = env.background_color.lerp(sky, clampf(delta * 2.0, 0.0, 1.0))
	env.ambient_light_energy = 0.25 if night else 0.55
	_tier_timer += delta
	if _tier_timer > 1.5:
		_tier_timer = 0.0
		_refresh_tier()
	for cid in sim_nodes:
		var n: Node3D = sim_nodes[cid]
		var c: Dictionary = w.cit(int(cid))
		if not w.is_present(c):
			n.visible = false
			continue
		var plan: Dictionary = sim_plan(c, hour if watch else 12.5 + float(int(cid) % 3))
		n.visible = bool(plan["visible"])
		var car: Node3D = n.get_node("Car")
		car.visible = bool(plan["car"])
		n.get_node("Body").visible = not bool(plan["car"])
		n.get_node("Head").visible = not bool(plan["car"])
		n.get_node("Hair").visible = not bool(plan["car"])
		var p: Vector3 = plan["pos"]
		if not watch:
			p += Vector3(sin(Time.get_ticks_msec() / 900.0 + float(cid)) * 0.6, 0, cos(Time.get_ticks_msec() / 1100.0 + float(cid)) * 0.6)
		n.position = n.position.lerp(p, clampf(delta * 6.0, 0.0, 1.0)) if n.position.distance_to(p) < 30.0 else p
		if plan.has("dir"):
			var d: Vector3 = plan["dir"]
			n.rotation.y = atan2(d.x, d.z)
		if bool(plan["moving"]) and not bool(plan["car"]):
			n.get_node("Body").rotation.z = sin(Time.get_ticks_msec() / 120.0) * 0.08
	for t in truck_nodes:
		var tn: Node3D = t["node"]
		var tt: float = (hour - float(t["start"])) / 1.5 if watch else 0.5
		var plan2: Dictionary = _between(_exit_pos() + Vector3(-60, 0, 0), lot_center(int(t["lot"])) + Vector3(5.0, 0, 5.0), tt, true, -1, int(t["lot"]))
		tn.visible = watch and tt > 0.0 and tt < 1.0
		tn.position = plan2["pos"]
		if plan2.has("dir"):
			tn.rotation.y = atan2((plan2["dir"] as Vector3).x, (plan2["dir"] as Vector3).z)
	_camera_keys(delta)


var camper: Node3D


## Until the mayor's house is built, the founder lives in a camper by the county road.
func _refresh_camper() -> void:
	var need: bool = int(w.player.get("home_lot", -1)) < 0
	if not need:
		if camper != null:
			camper.queue_free()
			camper = null
		return
	if camper != null and is_instance_valid(camper):
		return
	camper = Node3D.new()
	camper.position = _exit_pos() + Vector3(-12.0, 0, -7.0)
	extra_root.add_child(camper)
	_box(camper, Vector3(2.6, 2.6, 7.0), Vector3(0, 1.6, 0), Color(0.93, 0.92, 0.88))
	_box(camper, Vector3(2.65, 0.4, 7.05), Vector3(0, 1.6, 0), Color(0.3, 0.45, 0.65))
	_box(camper, Vector3(1.2, 0.8, 0.05), Vector3(1.31, 2.0, 1.5), Color(1.0, 0.88, 0.55), true)
	_box(camper, Vector3(2.4, 1.6, 3.0), Vector3(0, 1.0, 5.4), Color(0.55, 0.15, 0.12))
	var l: Label3D = _sign(camper, "%s's camper" % w.player.get("name", "The founder"), Vector3(0, 4.2, 0), 28, Color(1.0, 0.92, 0.6))
	l.pixel_size = 0.04


func _refresh_trucks() -> void:
	for t in truck_nodes:
		(t["node"] as Node3D).queue_free()
	truck_nodes.clear()
	for b in w.open_businesses():
		var arriving: bool = false
		for p in b["pending"]:
			if int(p["day"]) == w.day + 1 or int(p["day"]) == w.day:
				arriving = true
		if not arriving:
			continue
		var n: Node3D = Node3D.new()
		people_root.add_child(n)
		_box(n, Vector3(2.2, 2.2, 5.5), Vector3(0, 1.5, -0.6), Color(0.9, 0.9, 0.9))
		_box(n, Vector3(2.2, 1.6, 1.6), Vector3(0, 1.1, 2.8), Color(0.2, 0.35, 0.6))
		var l: Label3D = _sign(n, _local_trucker() if _local_trucker() != "" else "Valley Wholesale", Vector3(0, 3.2, 0), 24)
		l.pixel_size = 0.04
		truck_nodes.append({"node": n, "lot": int(b["lot"]), "start": 9.5, "trucker": _local_trucker()})
	if LTCivic.bus_available(w):
		# the county bus runs in for the morning and back in the evening
		for start in [6.5, 17.2]:
			var bn: Node3D = Node3D.new()
			people_root.add_child(bn)
			_box(bn, Vector3(2.6, 2.8, 9.0), Vector3(0, 1.8, 0), Color(0.95, 0.8, 0.2))
			_box(bn, Vector3(2.65, 0.9, 8.0), Vector3(0, 2.4, 0), Color(0.3, 0.4, 0.5))
			var bl: Label3D = _sign(bn, "County Bus", Vector3(0, 4.0, 0), 24)
			bl.pixel_size = 0.04
			truck_nodes.append({"node": bn, "lot": 0, "start": start, "trucker": ""})


func _local_trucker() -> String:
	for t in w.open_businesses("trucking"):
		return str(t["name"])
	return ""


# ------------------------------------------------------------------ camera and picking

func _camera_keys(delta: float) -> void:
	var move: Vector3 = Vector3.ZERO
	var fwd: Vector3 = Vector3(-sin(yaw), 0, -cos(yaw))
	var right: Vector3 = Vector3(cos(yaw), 0, -sin(yaw))
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move += fwd
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move -= fwd
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move += right
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move -= right
	if Input.is_key_pressed(KEY_Q):
		yaw += delta * 1.2
	if Input.is_key_pressed(KEY_E):
		yaw -= delta * 1.2
	if move != Vector3.ZERO:
		target += move.normalized() * delta * dist * 0.8
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			dist *= 0.9
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			dist *= 1.1
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_drag_rot = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag_pan = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.is_echo():
			_pick(mb.position)
		_update_camera()
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _drag_rot:
			yaw -= mm.relative.x * 0.006
			pitch -= mm.relative.y * 0.005
		elif _drag_pan or (mm.button_mask & MOUSE_BUTTON_MASK_LEFT and Input.is_key_pressed(KEY_SHIFT)):
			var right: Vector3 = Vector3(cos(yaw), 0, -sin(yaw))
			var fwd: Vector3 = Vector3(-sin(yaw), 0, -cos(yaw))
			target -= right * mm.relative.x * dist * 0.0018
			target += fwd * mm.relative.y * dist * 0.0018
		_update_camera()
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if st.pressed:
			_touches[st.index] = st.position
		else:
			if _touches.size() == 1 and _touches.has(st.index) and (_touches[st.index] as Vector2).distance_to(st.position) < 8.0:
				_pick(st.position)
			_touches.erase(st.index)
			_pinch_d = 0.0
	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event
		_touches[sd.index] = sd.position
		if _touches.size() == 1:
			var right2: Vector3 = Vector3(cos(yaw), 0, -sin(yaw))
			var fwd2: Vector3 = Vector3(-sin(yaw), 0, -cos(yaw))
			target -= right2 * sd.relative.x * dist * 0.0018
			target += fwd2 * sd.relative.y * dist * 0.0018
		elif _touches.size() == 2:
			var ks: Array = _touches.keys()
			var d: float = (_touches[ks[0]] as Vector2).distance_to(_touches[ks[1]])
			if _pinch_d > 0.0:
				dist *= _pinch_d / maxf(d, 1.0)
			_pinch_d = d
			yaw -= sd.relative.x * 0.003
		_update_camera()


func _pick(screen: Vector2) -> void:
	# Sims first, then lots, by distance on screen
	var best: float = 22.0
	var hit_sim: int = -1
	for cid in sim_nodes:
		var n: Node3D = sim_nodes[cid]
		if not n.visible:
			continue
		var p: Vector3 = n.global_position + Vector3(0, 1.0, 0)
		if cam.is_position_behind(p):
			continue
		var sp: Vector2 = cam.unproject_position(p)
		var d: float = sp.distance_to(screen)
		if d < best:
			best = d
			hit_sim = int(cid)
	if hit_sim >= 0:
		main.hud.inspect("sim", hit_sim)
		return
	var from: Vector3 = cam.project_ray_origin(screen)
	var dir: Vector3 = cam.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return
	var t: float = -from.y / dir.y
	if t < 0.0:
		return
	var g: Vector3 = from + dir * t
	var col: int = int(floor(g.x / CELL))
	var row: int = int(floor(g.z / CELL))
	var cols: int = int(w.config["lot_cols"])
	var rows: int = int(w.config["lot_rows"])
	if col >= 0 and col < cols and row >= 0 and row < rows:
		var lid: int = row * cols + col
		select_lot(lid)
		main.hud.inspect("lot", lid)


func select_lot(lid: int) -> void:
	selected_lot = lid
	if lid < 0:
		highlight.visible = false
		return
	highlight.visible = true
	highlight.position = lot_center(lid) + Vector3(0, 0.12, 0)


func focus_lot(lid: int) -> void:
	target = lot_center(lid)
	dist = minf(dist, 60.0)
	select_lot(lid)
	_update_camera()


func focus_sim(cid: int, hour: float) -> void:
	var c: Dictionary = w.cit(cid)
	if c.is_empty():
		return
	var plan: Dictionary = sim_plan(c, hour if _watch_mode else 12.5)
	target = plan["pos"]
	if not bool(plan["visible"]) or target.x < 0.0:
		# away at work out of town or asleep: show their home instead
		var hl: int = int(w.hh(int(c["household"]))["lot"])
		if hl >= 0:
			target = lot_center(hl)
	dist = minf(dist, 45.0)
	_update_camera()
	_refresh_tier()
