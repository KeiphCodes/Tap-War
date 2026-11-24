extends Node3D
## The 3D town, built procedurally from the data. Buildings show their state.
## Sims near the camera or on the watch list (Tier 1) walk and drive their day.
## Everyone else is still fully simulated, just not drawn.

## The survey step in meters (roads snap to it) and a town street's paved width.
const CELL: float = 10.0
const ROAD_W: float = 9.0
## A building sits this far back from the front of its lot (its front yard).
const KIT_BACK: float = 8.5
const MAX_SIMS: int = 45
## Zoomed in closer than this, the town is at street level: Sims appear and the
## weather and town sounds fade in. Farther out it is a quiet planning map.
const PEOPLE_DIST: float = 85.0
## Map units are about 1.5 meters. People walk about 1.4 m/s and drive about
## 40 km/h in town, so a trip takes real minutes, not a fixed hour.
const WALK_UPH: float = 3360.0
const DRIVE_UPH: float = 26400.0
## At day by day speeds Sims are shown where they are at this time of day, still,
## until the next day.
const FREEZE_HOUR: float = 12.5
## In Watch a trip lasts at least this many real seconds, so it can be followed.
const MIN_TRIP_REAL_S: float = 1.2
## Yard furniture on every lived in house, in the lot's own coordinates.
const FLOWER_X: float = 2.0
const SOUND_FADE: float = 20.0
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
var _tier_timer: float = 0.0
var _last_hour: float = 9.0
var _watch_mode: bool = false
## Game seconds per real second at the current speed (1 in Live, 720 in Watch).
var time_scale: float = 1.0
var _season: String = ""
var _snow: bool = false
var _touches: Dictionary = {}
var hovered_lot: int = -1
# camera goals: input moves these, the camera glides to them
var g_target: Vector3 = Vector3.ZERO
var g_yaw: float = 0.75
var g_pitch: float = -0.85
var g_dist: float = 95.0
var _pinch: Dictionary = {}
var _press_pos: Vector2 = Vector2.ZERO
# build tools
var tool: String = "look"
var plot_zone: String = "residential"
var _tool_a: Vector2i = Vector2i.ZERO
var _tool_b: Vector2i = Vector2i.ZERO
var _tool_drag_on: bool = false
var preview_mi: MeshInstance3D
var grid_mi: MeshInstance3D
var road_labels: Node3D
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
var _roads_count: int = -1
var selected_lot: int = -1
var selected_road: int = -1
## Map overlay: "" for none, or value, condition, happiness, safety, sale
var overlay: String = ""
var overlay_mi: MeshInstance3D
const OVERLAYS: Dictionary = {
	"": "Normal map",
	"value": "Land and building value",
	"condition": "Building condition",
	"happiness": "Happiness of the people living there",
	"safety": "How safe people feel at home",
	"sale": "City lots for sale",
}
var road_hl_mi: MeshInstance3D
## What the town sounds like right now near the camera, for the sound node.
var audio: Dictionary = {"traffic": 0.0, "building": 0.0, "crowd": 0.0}
var highlight: MeshInstance3D


func setup(p_main: Node) -> void:
	main = p_main
	w = main.world
	_build_env()
	_build_camera()
	rebuild()


func rebuild(keep_camera: bool = false) -> void:
	w = main.world
	# a new town: its land, trees and animals are drawn fresh
	_shores.clear()
	_trail_pts.clear()
	_season = ""
	_trees_sig = ""
	land_mi = null
	water_mi = null
	pine_mm = null
	leaf_mm = null
	wildlife_root = null
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
	if not keep_camera:
		# start over the town (or the middle of the county road on open land)
		var ms: Vector2 = map_size()
		target = Vector3(ms.x * 0.5, 0.0, ms.y * 0.5)
		dist = 320.0
		var lo: Vector2 = Vector2(1e9, 1e9)
		var hi: Vector2 = Vector2(-1e9, -1e9)
		for l in w.lots:
			if bool(l.get("removed", false)):
				continue
			lo = Vector2(minf(lo.x, float(l["x0"])), minf(lo.y, float(l["z0"])))
			hi = Vector2(maxf(hi.x, float(l["x1"])), maxf(hi.y, float(l["z1"])))
		if hi.x > lo.x:
			target = Vector3((lo.x + hi.x) * 0.5, 0.0, (lo.y + hi.y) * 0.5)
			dist = clampf(maxf(hi.x - lo.x, hi.y - lo.y) * 0.95, 150.0, 1200.0)
		g_target = target
		g_dist = dist
		g_yaw = yaw
		g_pitch = pitch
	_build_tool_meshes()
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


## Where batched parts land: the building's place on its lot (set while a lot is built).
var _bxf: Transform3D = Transform3D.IDENTITY
## The lot being built: its frontage (local x) and depth (local z), in meters.
var _lw: float = 20.0
var _ld: float = 40.0


func _batch_add(pm: PrimitiveMesh, key: String, xf: Transform3D, c: Color, glow: bool) -> void:
	xf = _bxf * xf
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


func _roof(parent: Node3D, size: Vector3, pos: Vector3, c: Color, yaw: float = 0.0) -> MeshInstance3D:
	if _snow:
		c = c.lerp(Color(0.93, 0.95, 0.98), 0.8)
	if _batching:
		_batch_add(PrismMesh.new(), "prism", Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(size), pos), c, false)
		return null
	var mi: MeshInstance3D = MeshInstance3D.new()
	var pm: PrismMesh = PrismMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.rotation.y = yaw
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
	dist = maxf(dist, 14.0)
	var dir: Vector3 = Vector3(cos(pitch) * sin(yaw), -sin(pitch), cos(pitch) * cos(yaw))
	cam.position = target + dir * dist
	cam.look_at(target, Vector3.UP)


func _build_ground() -> void:
	ground_mi = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(1400, 1400)
	ground_mi.mesh = pm
	var ms: Vector2 = map_size()
	pm.size = Vector2(ms.x + 1400.0, ms.y + 1400.0)
	ground_mi.position = Vector3(ms.x * 0.5, -0.05, ms.y * 0.5)
	ground_root.add_child(ground_mi)
	# the county road runs on past the edge of town in both directions
	var names: Array = ["To County Seat (25 min)", "To Mill Creek (25 min)"]
	var k: int = 0
	for ex in LTGeography.exit_nodes(w):
		var en: Dictionary = w.road_nodes[int(ex)]
		var x: float = float(en["x"]) * CELL
		var z: float = float(en["y"]) * CELL
		var west: bool = x < ms.x * 0.5
		_box(ground_root, Vector3(700.0, 0.08, ROAD_W), Vector3(x - 350.0 if west else x + 350.0, 0.02, z), Color(0.25, 0.25, 0.27))
		var sgn: Label3D = _sign(ground_root, names[k % 2], Vector3(x - 30.0 if west else x + 30.0, 4.0, z - 8.0), 160)
		sgn.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		k += 1


func _build_roads() -> void:
	_rebuild_road_mesh()


func _road_labels() -> void:
	if road_labels != null:
		road_labels.queue_free()
	road_labels = Node3D.new()
	road_root.add_child(road_labels)
	for st in w.streets:
		if str(st["kind"]) == "avenue" or st["segments"].is_empty():
			continue
		if str(st["kind"]) == "alley":
			continue
		var s0: Dictionary = {}
		var live: Array = []
		for sid in st["segments"]:
			if not bool(w.roads[int(sid)].get("removed", false)):
				live.append(int(sid))
		if not live.is_empty():
			s0 = w.roads[int(live[live.size() / 2])]
		if s0.is_empty():
			continue
		var a2: Dictionary = w.road_nodes[int(s0["a"])]
		var b2: Dictionary = w.road_nodes[int(s0["b"])]
		var mid: Vector3 = Vector3((float(a2["x"]) + float(b2["x"])) * 0.5 * CELL, 0.25, (float(a2["y"]) + float(b2["y"])) * 0.5 * CELL)
		var tag: String = ""
		if bool(s0.get("planned", false)):
			tag = " (planned)"
			for p in w.projects:
				if int(p["street"]) == int(st["id"]) and str(p["ptype"]) == "road_build" and str(p["status"]) == "draft":
					tag = " (draft)"
		var l: Label3D = _sign(road_labels, str(st["name"]) + tag, mid, 90, Color(0.95, 0.95, 0.8))
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		l.rotation = Vector3(-PI / 2.0, 0.0 if int(a2["y"]) == int(b2["y"]) else PI / 2.0, 0.0)


func _rebuild_road_mesh() -> void:
	if road_mi != null:
		road_mi.queue_free()
	var drafts: Dictionary = {}
	for p in w.projects:
		if str(p["status"]) == "draft" and str(p["ptype"]) == "road_build":
			drafts[int(p["street"])] = true
	_batch_begin()
	for s in w.roads:
		if bool(s.get("removed", false)):
			continue
		var a: Dictionary = w.road_nodes[int(s["a"])]
		var b: Dictionary = w.road_nodes[int(s["b"])]
		var pa: Vector3 = Vector3(float(a["x"]) * CELL, 0.03, float(a["y"]) * CELL)
		var pb: Vector3 = Vector3(float(b["x"]) * CELL, 0.03, float(b["y"]) * CELL)
		var horiz: bool = absf(pa.z - pb.z) < 0.01
		var st: Dictionary = w.streets[int(s["street"])]
		var rw: float = ROAD_W if str(st["kind"]) == "highway" else _road_width(int(s["street"]))
		var size: Vector3 = Vector3(CELL + rw, 0.06, rw) if horiz else Vector3(rw, 0.06, CELL + rw)
		var cnd: float = float(s["condition"]) / 100.0
		var planned: bool = bool(s.get("planned", false))
		if not planned and str(st.get("surface", "")) == "gravel":
			cnd = minf(cnd, 0.35)
		elif not planned and str(st.get("surface", "")) == "concrete":
			cnd = maxf(cnd, 0.6)
		if not planned and bool(st.get("sidewalks", false)):
			var off: float = rw * 0.5 + 0.7
			for sgn in [-1.0, 1.0]:
				var o: Vector3 = Vector3(0, 0.05, off * sgn) if horiz else Vector3(off * sgn, 0.05, 0)
				_box(road_root, Vector3(CELL, 0.1, 1.0) if horiz else Vector3(1.0, 0.1, CELL), (pa + pb) * 0.5 + o, Color(0.72, 0.71, 0.68))
		if not planned and bool(st.get("lights", false)):
			var o2: Vector3 = Vector3(0, 0, rw * 0.5 + 1.4) if horiz else Vector3(rw * 0.5 + 1.4, 0, 0)
			var lp: Vector3 = (pa + pb) * 0.5 + o2
			_box(road_root, Vector3(0.15, 3.2, 0.15), lp + Vector3(0, 1.6, 0), Color(0.25, 0.26, 0.28))
			_box(road_root, Vector3(0.5, 0.25, 0.5), lp + Vector3(0, 3.3, 0), Color(1.0, 0.9, 0.6), _is_night())
		var col: Color = Color(0.24, 0.24, 0.26).lerp(Color(0.5, 0.44, 0.36), clampf(1.0 - cnd, 0.0, 1.0) * 0.9)
		if _snow:
			col = col.lerp(Color(0.85, 0.87, 0.9), 0.5)
		if not planned and str(st.get("surface", "")) == "concrete":
			col = Color(0.62, 0.61, 0.58).lerp(Color(0.5, 0.44, 0.36), clampf(1.0 - cnd, 0.0, 1.0) * 0.6)
		elif not planned and str(st.get("surface", "")) == "gravel":
			col = Color(0.55, 0.5, 0.42)
		if planned:
			# surveyed but not built: a strip of staked dirt; a draft is only chalked out
			col = Color(0.47, 0.33, 0.2) if not drafts.has(int(s["street"])) else Color(0.86, 0.84, 0.74)
			size.y = 0.03
		_box(road_root, size, (pa + pb) * 0.5, col)
	road_mi = _batch_end(road_root)
	_road_labels()


func _build_trees() -> void:
	if tree_mi != null:
		tree_mi.queue_free()
	var leaf: Color = _leaf_color()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = w.seed_value
	var cols: int = int(w.config["map_cols"])
	var rows: int = int(w.config["map_rows"])
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
	var snow: bool = w.weather == "Snow" or LTHazards.snow_depth(w) >= 1.0
	if season != _season or snow != _snow:
		_season = season
		_snow = snow
		_apply_season()
		_build_trees()
	if w.day % 7 == 0 or not _roads_built_day == w.day or w.roads.size() != _roads_count:
		_roads_built_day = w.day
		_roads_count = w.roads.size()
		_rebuild_road_mesh()
	for l in w.lots:
		if bool(l.get("removed", false)):
			if lot_nodes.has(int(l["id"])):
				(lot_nodes[int(l["id"])] as Node3D).queue_free()
				lot_nodes.erase(int(l["id"]))
				lot_sigs.erase(int(l["id"]))
			continue
		var sig: String = _lot_sig(l)
		if lot_sigs.get(int(l["id"]), "") != sig:
			lot_sigs[int(l["id"])] = sig
			_build_lot(l)
	_refresh_tier()
	_refresh_trucks()
	_refresh_camper()
	_rebuild_overlay()
	_build_forest()
	if wildlife_root == null or not is_instance_valid(wildlife_root):
		_build_wildlife()


func set_overlay(kind: String) -> void:
	overlay = kind if OVERLAYS.has(kind) else ""
	_rebuild_overlay()


## A score from 0 (bad, red) to 1 (good, green) for one lot, or -1 to leave it plain.
func overlay_score(l: Dictionary) -> float:
	var use: String = str(l["use"])
	match overlay:
		"value":
			if use == "empty":
				return -1.0
			return clampf(float(l["value"]) / float(LTMoney.dollars(400000.0)), 0.0, 1.0)
		"condition":
			if use == "empty" or use == "removed":
				return -1.0
			return clampf(float(l["condition"]) / 100.0, 0.0, 1.0)
		"happiness", "safety":
			var t: float = 0.0
			var n: int = 0
			for u in l["units"]:
				if int(u) < 0:
					continue
				for m in w.household_members(w.hh(int(u))):
					if w.is_present(m):
						t += LTPeople.happiness(m) if overlay == "happiness" else float(m["needs"]["safety"])
						n += 1
			if n == 0:
				return -1.0
			return clampf(t / float(n) / 100.0, 0.0, 1.0)
		"sale":
			if use != "empty" or str(l["owner_kind"]) != "city":
				return -1.0
			if bool(l.get("hold", false)):
				return 0.5
			return clampf(1.25 - float(l.get("price_pct", 100)) / 200.0, 0.0, 1.0)
	return -1.0


func _rebuild_overlay() -> void:
	if overlay_mi != null:
		overlay_mi.queue_free()
		overlay_mi = null
	if overlay == "":
		return
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any: bool = false
	for l in w.lots:
		if bool(l.get("removed", false)):
			continue
		var v: float = overlay_score(l)
		if v < 0.0:
			continue
		any = true
		var c: Color = Color(0.85, 0.2, 0.15).lerp(Color(0.95, 0.85, 0.2), clampf(v * 2.0, 0.0, 1.0)) if v < 0.5 else Color(0.95, 0.85, 0.2).lerp(Color(0.2, 0.8, 0.3), clampf((v - 0.5) * 2.0, 0.0, 1.0))
		if overlay == "sale" and bool(l.get("hold", false)):
			c = Color(0.3, 0.5, 0.95)
		c.a = 0.55
		var a: Vector3 = Vector3(float(l["x0"]) + 0.4, 0.35, float(l["z0"]) + 0.4)
		var b: Vector3 = Vector3(float(l["x1"]) - 0.4, 0.35, float(l["z0"]) + 0.4)
		var d: Vector3 = Vector3(float(l["x1"]) - 0.4, 0.35, float(l["z1"]) - 0.4)
		var e: Vector3 = Vector3(float(l["x0"]) + 0.4, 0.35, float(l["z1"]) - 0.4)
		for q in [a, b, d, a, d, e]:
			st.set_color(c)
			st.set_normal(Vector3.UP)
			st.add_vertex(q)
	if not any:
		return
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 2
	overlay_mi = MeshInstance3D.new()
	overlay_mi.mesh = st.commit()
	overlay_mi.material_override = m
	overlay_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_root.add_child(overlay_mi)


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
			g = Color(0.52, 0.52, 0.32)
			leaf = Color(0.8, 0.45, 0.15)
	if _snow:
		g = Color(0.8, 0.82, 0.85)
	_ground_color = g
	_build_land()


# ------------------------------------------------------------------ the land: hills, lakes, forest, wildlife

var _ground_color: Color = Color(0.45, 0.6, 0.28)
var land_mi: MeshInstance3D
var water_mi: MeshInstance3D
var pine_mm: MultiMeshInstance3D
var leaf_mm: MultiMeshInstance3D
var wildlife_root: Node3D
var _trees_sig: String = ""
const LAND_STEP: float = 20.0


## The ground: flat prairie with the mountain rising in its corner, colored by
## season, forest floor darker, bare granite up high and snow on the peak in winter.
func _build_land() -> void:
	if land_mi != null:
		land_mi.queue_free()
	if water_mi != null:
		water_mi.queue_free()
	var ms: Vector2 = map_size()
	var margin: float = 700.0
	var nx: int = int((ms.x + margin * 2.0) / LAND_STEP)
	var nz: int = int((ms.y + margin * 2.0) / LAND_STEP)
	var peak: float = maxf(1.0, LTTerrain.mountain_peak(w))
	var winter: bool = _season == "Winter"
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hs: PackedFloat32Array = PackedFloat32Array()
	hs.resize((nx + 1) * (nz + 1))
	var cols: PackedColorArray = PackedColorArray()
	cols.resize((nx + 1) * (nz + 1))
	for j in nz + 1:
		for i in nx + 1:
			var x: float = -margin + float(i) * LAND_STEP
			var z: float = -margin + float(j) * LAND_STEP
			var h: float = LTTerrain.height(w, x, z)
			hs[j * (nx + 1) + i] = h
			var c: Color = _ground_color
			if LTTerrain.forest_value(w, x, z) > 0.0 and h < peak * 0.55:
				c = c.darkened(0.18) if not _snow else c.darkened(0.06)
			var k: float = h / peak
			if k > 0.35:
				c = c.lerp(Color(0.55, 0.53, 0.5), clampf((k - 0.35) / 0.25, 0.0, 1.0))
			if (winter or _snow) and k > 0.62:
				c = c.lerp(Color(0.95, 0.96, 0.98), clampf((k - 0.62) / 0.12, 0.0, 1.0))
			cols[j * (nx + 1) + i] = c
	for j in nz:
		for i in nx:
			var x0: float = -margin + float(i) * LAND_STEP
			var z0: float = -margin + float(j) * LAND_STEP
			var idx: Array = [j * (nx + 1) + i, j * (nx + 1) + i + 1, (j + 1) * (nx + 1) + i + 1, (j + 1) * (nx + 1) + i]
			var pts: Array = [Vector3(x0, hs[idx[0]], z0), Vector3(x0 + LAND_STEP, hs[idx[1]], z0), Vector3(x0 + LAND_STEP, hs[idx[2]], z0 + LAND_STEP), Vector3(x0, hs[idx[3]], z0 + LAND_STEP)]
			for tri in [[0, 2, 1], [0, 3, 2]]:
				var a: Vector3 = pts[tri[0]]
				var b: Vector3 = pts[tri[1]]
				var cc: Vector3 = pts[tri[2]]
				var nrm: Vector3 = (b - a).cross(cc - a).normalized()
				if nrm.y < 0.0:
					nrm = -nrm
				for q in tri:
					st.set_color(cols[idx[q]])
					st.set_normal(nrm)
					st.add_vertex(pts[q] + Vector3(0, -0.3, 0))
	land_mi = MeshInstance3D.new()
	land_mi.mesh = st.commit()
	var lm: StandardMaterial3D = StandardMaterial3D.new()
	lm.vertex_color_use_as_albedo = true
	lm.roughness = 0.95
	lm.cull_mode = BaseMaterial3D.CULL_DISABLED
	land_mi.material_override = lm
	ground_root.add_child(land_mi)
	if ground_mi != null:
		ground_mi.visible = false
	# lakes: open water, or white ice from December to February
	var frozen: bool = winter and LTCalendar.month_index(w.day) != 2
	var ws: SurfaceTool = SurfaceTool.new()
	ws.begin(Mesh.PRIMITIVE_TRIANGLES)
	for lk in LTTerrain.t(w).get("lakes", []):
		var c2: Vector2 = lk["c"]
		var seg: int = 48
		for k2 in seg:
			var a0: float = TAU * float(k2) / float(seg)
			var a1: float = TAU * float(k2 + 1) / float(seg)
			var p0: Vector3 = Vector3(c2.x, 0.12, c2.y)
			var p1: Vector3 = Vector3(c2.x + cos(a0) * float(lk["rx"]), 0.12, c2.y + sin(a0) * float(lk["rz"]))
			var p2: Vector3 = Vector3(c2.x + cos(a1) * float(lk["rx"]), 0.12, c2.y + sin(a1) * float(lk["rz"]))
			for v in [p0, p2, p1]:
				ws.set_normal(Vector3.UP)
				ws.add_vertex(v)
	water_mi = MeshInstance3D.new()
	water_mi.mesh = ws.commit()
	var wm: StandardMaterial3D = StandardMaterial3D.new()
	wm.albedo_color = Color(0.86, 0.9, 0.95) if frozen else Color(0.2, 0.42, 0.62, 0.92)
	wm.roughness = 0.2 if not frozen else 0.6
	wm.metallic = 0.1
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	if not frozen:
		wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mi.material_override = wm
	ground_root.add_child(water_mi)
	_build_forest()


## Animals for the eye only (the simulation does not count them): deer at the
## forest edge, ducks and geese on the lakes, elk and mountain goats on the hills,
## and pheasants in the fields. They wander slowly and only near the camera.
func _build_wildlife() -> void:
	wildlife_root = Node3D.new()
	extra_root.add_child(wildlife_root)
	var tt: Dictionary = LTTerrain.t(w)
	if tt.is_empty():
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(tt["seed"]) + 99
	var f: Dictionary = tt["forest"]
	for i in 8:
		var a: float = rng.randf() * TAU
		var p: Vector2 = (f["c"] as Vector2) + Vector2(cos(a) * float(f["rx"]), sin(a) * float(f["rz"])) * rng.randf_range(0.6, 1.0)
		_animal("deer", p, rng)
	for lk in tt["lakes"]:
		for i in (6 if float(lk["rx"]) > 80.0 else 3):
			var a2: float = rng.randf() * TAU
			_animal("duck", (lk["c"] as Vector2) + Vector2(cos(a2) * float(lk["rx"]), sin(a2) * float(lk["rz"])) * rng.randf_range(0.2, 0.8), rng)
	var m: Dictionary = tt["mountain"]
	for i in 5:
		var a3: float = rng.randf() * TAU
		_animal("elk" if i < 3 else "goat", (m["c"] as Vector2) + Vector2(cos(a3), sin(a3)) * float(m["r"]) * rng.randf_range(0.2, 0.6), rng)
	for i in 6:
		_animal("pheasant", Vector2(rng.randf_range(100.0, 1500.0), rng.randf_range(100.0, 1100.0)), rng)


func _animal(kind: String, at: Vector2, rng: RandomNumberGenerator) -> void:
	if kind == "pheasant" and (LTTerrain.is_water(w, at.x, at.y) or LTGeography.lot_at(w, at.x, at.y) >= 0):
		return
	var n: Node3D = Node3D.new()
	n.set_meta("home", at)
	n.set_meta("kind", kind)
	n.set_meta("phase", rng.randf() * 100.0)
	wildlife_root.add_child(n)
	match kind:
		"deer":
			_box(n, Vector3(0.5, 0.8, 1.4), Vector3(0, 1.0, 0), Color(0.55, 0.38, 0.22))
			_box(n, Vector3(0.3, 0.6, 0.3), Vector3(0, 1.6, 0.75), Color(0.55, 0.38, 0.22))
			for lx in [-0.18, 0.18]:
				for lz in [-0.5, 0.5]:
					_box(n, Vector3(0.1, 0.7, 0.1), Vector3(lx, 0.35, lz), Color(0.4, 0.28, 0.16))
		"elk":
			_box(n, Vector3(0.7, 1.1, 2.0), Vector3(0, 1.4, 0), Color(0.45, 0.32, 0.2))
			_box(n, Vector3(0.4, 0.8, 0.4), Vector3(0, 2.2, 1.0), Color(0.35, 0.25, 0.16))
			for lx in [-0.25, 0.25]:
				_box(n, Vector3(0.08, 0.6, 0.08), Vector3(lx, 2.8, 1.0), Color(0.8, 0.75, 0.6))
			for lx in [-0.25, 0.25]:
				for lz in [-0.7, 0.7]:
					_box(n, Vector3(0.14, 0.9, 0.14), Vector3(lx, 0.45, lz), Color(0.3, 0.22, 0.14))
		"goat":
			_box(n, Vector3(0.45, 0.6, 1.0), Vector3(0, 0.8, 0), Color(0.92, 0.92, 0.9))
			_box(n, Vector3(0.25, 0.35, 0.3), Vector3(0, 1.2, 0.55), Color(0.92, 0.92, 0.9))
		"duck":
			_box(n, Vector3(0.3, 0.2, 0.5), Vector3(0, 0.22, 0), Color(0.45, 0.35, 0.25))
			_box(n, Vector3(0.15, 0.18, 0.15), Vector3(0, 0.42, 0.22), Color(0.1, 0.45, 0.2))
		"pheasant":
			_box(n, Vector3(0.25, 0.25, 0.55), Vector3(0, 0.35, 0), Color(0.65, 0.3, 0.12))
			_box(n, Vector3(0.12, 0.2, 0.12), Vector3(0, 0.55, 0.25), Color(0.15, 0.4, 0.25))
			_box(n, Vector3(0.05, 0.05, 0.5), Vector3(0, 0.4, -0.5), Color(0.55, 0.4, 0.2))


func _move_wildlife(delta: float) -> void:
	if wildlife_root == null or not is_instance_valid(wildlife_root):
		return
	wildlife_root.visible = dist < PEOPLE_DIST * 2.0
	if not wildlife_root.visible:
		return
	var tsec: float = float(Time.get_ticks_msec()) / 1000.0
	var frozen: bool = _season == "Winter"
	for a in wildlife_root.get_children():
		var home: Vector2 = a.get_meta("home")
		var ph: float = float(a.get_meta("phase"))
		var kind: String = str(a.get_meta("kind"))
		# ducks leave when the lake freezes; everything wanders slowly around home
		if kind == "duck":
			a.visible = not frozen
		var r: float = 6.0 if kind == "duck" else 12.0
		var p: Vector2 = home + Vector2(sin(tsec * 0.05 + ph) * r, cos(tsec * 0.037 + ph * 1.3) * r)
		var nxt: Vector2 = home + Vector2(sin((tsec + 0.5) * 0.05 + ph) * r, cos((tsec + 0.5) * 0.037 + ph * 1.3) * r)
		a.position = Vector3(p.x, LTTerrain.height(w, p.x, p.y) + (0.1 if kind == "duck" else 0.0), p.y)
		var d: Vector2 = nxt - p
		if d.length() > 0.001:
			a.rotation.y = atan2(d.x, d.y)


## Thousands of trees, drawn in two batches: ponderosa pines (always green) and
## leafy trees that turn in the fall and go bare in winter. None stand on a lot
## that has something built on it.
func _build_forest() -> void:
	var built: Array = []
	var buckets: Dictionary = {}
	for l in w.lots:
		if not bool(l.get("removed", false)) and str(l["use"]) != "empty":
			var rr: Rect2 = Rect2(float(l["x0"]), float(l["z0"]), float(l["x1"]) - float(l["x0"]), float(l["z1"]) - float(l["z0"]))
			built.append(rr)
			for bx in range(int(rr.position.x / 50.0), int(rr.end.x / 50.0) + 1):
				for bz in range(int(rr.position.y / 50.0), int(rr.end.y / 50.0) + 1):
					var key: int = bz * 1000 + bx
					if not buckets.has(key):
						buckets[key] = []
					buckets[key].append(rr)
	var sig: String = "%s|%d|%d" % [_season, built.size(), int(_snow)]
	if sig == _trees_sig and pine_mm != null:
		return
	_trees_sig = sig
	if pine_mm != null:
		pine_mm.queue_free()
	if leaf_mm != null:
		leaf_mm.queue_free()
	var tt: Dictionary = LTTerrain.t(w)
	if tt.is_empty():
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(tt["seed"])
	var pines: Array = []
	var leafy: Array = []
	var peak: float = maxf(1.0, LTTerrain.mountain_peak(w))
	var step: float = 9.0
	var ms: Vector2 = map_size()
	var x: float = 0.0
	while x < ms.x:
		var z: float = 0.0
		while z < ms.y:
			var px: float = x + rng.randf_range(-3.5, 3.5)
			var pz: float = z + rng.randf_range(-3.5, 3.5)
			var h: float = LTTerrain.height(w, px, pz)
			var in_forest: bool = LTTerrain.forest_value(w, px, pz) > 0.0
			var on_hill: bool = h > 3.0 and h < peak * 0.55 and rng.randf() < 0.55
			if (in_forest or on_hill) and not LTTerrain.is_water(w, px, pz):
				var blocked: bool = false
				for r in buckets.get(int(pz / 50.0) * 1000 + int(px / 50.0), []):
					if (r as Rect2).has_point(Vector2(px, pz)):
						blocked = true
						break
				if not blocked:
					var tr: Transform3D = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * rng.randf_range(0.8, 1.35)), Vector3(px, h, pz))
					if on_hill or rng.randf() < 0.55:
						pines.append(tr)
					else:
						leafy.append(tr)
			z += step
		x += step
	pine_mm = _tree_batch(pines, true)
	leaf_mm = _tree_batch(leafy, false)


func _tree_batch(xfs: Array, pine: bool) -> MultiMeshInstance3D:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var m: Mesh
	if pine:
		var cone: CylinderMesh = CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 2.2
		cone.height = 9.0
		cone.radial_segments = 6
		m = cone
	else:
		var ball: SphereMesh = SphereMesh.new()
		ball.radius = 2.6
		ball.height = 4.6
		ball.radial_segments = 6
		ball.rings = 4
		m = ball
	mm.mesh = m
	mm.instance_count = xfs.size()
	for i in xfs.size():
		var tr: Transform3D = xfs[i]
		tr.origin += Vector3(0, 4.5 if pine else 4.0, 0)
		mm.set_instance_transform(i, tr)
	var mi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	if pine:
		mat.albedo_color = Color(0.16, 0.32, 0.18) if not _snow else Color(0.6, 0.68, 0.64)
	else:
		mat.albedo_color = _leaf_color()
		if _season == "Winter" and not _snow:
			mat.albedo_color = Color(0.4, 0.33, 0.25)
	mat.roughness = 0.9
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_root.add_child(mi)
	return mi


func lot_center(lot_id: int) -> Vector3:
	var l: Dictionary = w.lot(lot_id)
	if l.is_empty():
		return Vector3.ZERO
	return Vector3((float(l["x0"]) + float(l["x1"])) * 0.5, 0.0, (float(l["z0"]) + float(l["z1"])) * 0.5)


## A lot faces its road: its local +z points at the street.
func lot_rot(l: Dictionary) -> float:
	match str(l.get("front", "s")):
		"n":
			return PI
		"e":
			return PI * 0.5
		"w":
			return -PI * 0.5
	return 0.0


func lot_xform(lot_id: int) -> Transform3D:
	var l: Dictionary = w.lot(lot_id)
	return Transform3D(Basis(Vector3.UP, lot_rot(l)), lot_center(lot_id))


## Where the building stands on its lot: near the front, behind a front yard,
## narrowed to fit a lot thinner than the building.
func kit_local(l: Dictionary) -> Transform3D:
	var fw: float = LTGeography.lot_frontage(l)
	var dp: float = LTGeography.lot_depth(l)
	var sx: float = 1.0
	if str(l["use"]) != "house":
		sx = clampf((fw - 0.8) / 13.2, 0.4, 1.0)
	var z: float = maxf(0.0, dp * 0.5 - KIT_BACK)
	return Transform3D(Basis.IDENTITY.scaled(Vector3(sx, 1.0, 1.0)), Vector3(0, 0, z))


func kit_xform(lot_id: int) -> Transform3D:
	return lot_xform(lot_id) * kit_local(w.lot(lot_id))


func _lot_sig(l: Dictionary) -> String:
	var use: String = str(l["use"])
	var extra: String = ""
	match use:
		"mayor_house":
			extra = "%s|%s" % [w.player.get("name", ""), w.player.get("color", "")]
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
			extra = "%d|%s|%d|%s|%s" % [occ, l["owner_kind"], int(float(l["condition"]) / 25.0), str(l.get("home", {})), _home_biz_name(int(l["id"]))]
	return "%s|%s|%s|%s|%s|%s|%.1f|%.1f|%.1f|%.1f" % [use, l["zone"], l["building"], extra, _season, _snow, float(l["x0"]), float(l["z0"]), float(l["x1"]), float(l["z1"])]


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
	_lay_cache.erase(int(l["id"]))
	var id: int = int(l["id"])
	if lot_nodes.has(id):
		(lot_nodes[id] as Node3D).queue_free()
	var root: Node3D = Node3D.new()
	root.transform = lot_xform(id)
	lot_root.add_child(root)
	lot_nodes[id] = root
	_lw = LTGeography.lot_frontage(l)
	_ld = LTGeography.lot_depth(l)
	_bxf = Transform3D.IDENTITY
	_batch_begin()
	var pad_col: Color = _zone_color(str(l["zone"]))
	if _snow:
		pad_col = pad_col.lerp(Color(0.9, 0.92, 0.95), 0.3)
	_box(root, Vector3(_lw - 0.6, 0.1, _ld - 0.6), Vector3(0, 0.0, 0), pad_col)
	var use: String = str(l["use"])
	var cond: float = float(l["condition"]) / 100.0
	# buildings stand near the front of the lot; fields and parks use all of it
	var kit: Node3D = Node3D.new()
	var farm: bool = use == "business" and str(w.biz(int(l["ref"])).get("type", "")) == "farm"
	if use != "empty" and not farm:
		kit.transform = kit_local(l)
		_bxf = kit.transform
	root.add_child(kit)
	match use:
		"house":
			_house(kit, l, cond)
		"apartment":
			_apartment(kit, l, cond)
		"business", "closed":
			_business(kit, l)
		"civic":
			_civic(kit, l)
		"mayor_house":
			_mayor_house(kit, l)
		"site", "reserved":
			_site(kit, l)
		"empty":
			if str(l["zone"]) == "commercial" or str(l["zone"]) == "mixed":
				var sp: Vector3 = Vector3(-_lw * 0.3, 0, _ld * 0.5 - 2.0)
				_box(root, Vector3(0.15, 1.6, 0.15), sp + Vector3(0, 0.8, 0), Color(0.4, 0.3, 0.2))
				var s: Label3D = _sign(root, "Lot %d for lease" % id, sp + Vector3(0, 2.0, 0), 32)
				s.pixel_size = 0.04
			elif str(l["zone"]) == "agricultural":
				var rows_n: int = clampi(int(_ld / 6.0), 3, 30)
				for i in rows_n:
					_box(root, Vector3(_lw * 0.9, 0.08, 0.6), Vector3(0, 0.08, -_ld * 0.45 + float(i) * _ld * 0.9 / float(rows_n)), Color(0.5, 0.42, 0.3))
			elif str(l["zone"]) == "park":
				var trees_n: int = clampi(int(_lw * _ld / 120.0), 3, 24)
				for i in trees_n:
					var tp: Vector3 = Vector3(fmod(float(i) * 7.3, _lw - 3.0) - (_lw - 3.0) * 0.5, 0, fmod(float(i) * 11.9, _ld - 3.0) - (_ld - 3.0) * 0.5)
					_cyl(root, 0.2, 2.0, tp + Vector3(0, 1.0, 0), Color(0.35, 0.25, 0.15))
					_ball(root, 1.4, tp + Vector3(0, 2.6, 0), _leaf_color())
	_bxf = Transform3D.IDENTITY
	_batch_end(root)


func _wear(c: Color, cond: float) -> Color:
	return c.lerp(Color(0.45, 0.42, 0.38), clampf(1.0 - cond, 0.0, 1.0) * 0.55)


## The business run from this house, if any: its name, or "".
func _home_biz_name(lot_id: int) -> String:
	for b in w.businesses:
		if int(b["lot"]) == lot_id and bool(b.get("home_based", false)) and str(b["status"]) == "open":
			return str(b["name"]) + "|" + str(b["type"])
	return ""


## A house drawn from what the family built, where they put it on their lot. It
## always faces the street. Lot coordinates from LTHomes (x along the front, d back
## from the street) become kit coordinates: x the same, z = KIT_BACK - d.
func _kr(r: Array, y: float, h: float) -> Array:
	return [Vector3(float(r[2]) - float(r[0]), h, float(r[3]) - float(r[1])), Vector3((float(r[0]) + float(r[2])) * 0.5, y + h * 0.5, KIT_BACK - (float(r[1]) + float(r[3])) * 0.5)]


func _flat(root: Node3D, r: Array, y: float, h: float, c: Color) -> void:
	var k: Array = _kr(r, y, h)
	_box(root, k[0], k[1], c)


const SIDING: Dictionary = {
	"vinyl": [Color(0.92, 0.88, 0.78), Color(0.75, 0.82, 0.9), Color(0.82, 0.9, 0.8), Color(0.95, 0.95, 0.95), Color(0.86, 0.8, 0.7), Color(0.7, 0.74, 0.7)],
	"wood": [Color(0.66, 0.48, 0.32), Color(0.55, 0.36, 0.24), Color(0.74, 0.6, 0.42), Color(0.5, 0.56, 0.5), Color(0.62, 0.3, 0.24), Color(0.85, 0.82, 0.72)],
	"brick": [Color(0.62, 0.3, 0.24), Color(0.55, 0.27, 0.22), Color(0.68, 0.38, 0.3), Color(0.5, 0.3, 0.26), Color(0.7, 0.45, 0.36), Color(0.58, 0.34, 0.28)],
	"stone": [Color(0.66, 0.63, 0.58), Color(0.72, 0.68, 0.6), Color(0.6, 0.58, 0.55), Color(0.7, 0.64, 0.55), Color(0.62, 0.6, 0.56), Color(0.75, 0.72, 0.66)],
}
const ROOFS: Dictionary = {
	"shingle": [Color(0.35, 0.2, 0.18), Color(0.25, 0.27, 0.3), Color(0.45, 0.3, 0.2), Color(0.3, 0.3, 0.28)],
	"metal": [Color(0.3, 0.42, 0.32), Color(0.55, 0.2, 0.18), Color(0.45, 0.48, 0.52), Color(0.2, 0.25, 0.35)],
}


func _house(root: Node3D, l: Dictionary, cond: float) -> void:
	var spec: Dictionary = LTHomes.upgrade(l.get("home", {}))
	if spec.is_empty():
		spec = LTHomes.upgrade({"beds": 3, "baths": 2.0, "stories": 1, "garage": 1, "basement": false})
	var lay: Dictionary = _lay(l) if l.has("home") else LTHomes.layout(l, spec)
	var ci: int = int(spec.get("color", int(l["id"])))
	var wc: Color = _wear((SIDING[str(spec["siding"])] as Array)[ci % 6], cond)
	var rc: Color = (ROOFS[str(spec["roof"])] as Array)[ci % 4]
	var trim: Color = Color(0.96, 0.95, 0.92)
	var style: String = str(spec["style"])
	var floors: int = int(spec["stories"])
	var hr: Array = lay["house"]
	var W: float = float(lay["W"])
	var D: float = float(lay["D"])
	var hx: float = (float(hr[0]) + float(hr[2])) * 0.5
	var front_z: float = KIT_BACK - float(hr[1])
	var cz: float = front_z - D * 0.5
	var wall_h: float = 3.0 if floors == 1 else 5.8
	# the drive and walk first, so the house sits on top
	if lay.has("drive"):
		_flat(root, lay["drive"], 0.0, 0.06, Color(0.62, 0.62, 0.6))
	_box(root, Vector3(1.2, 0.05, KIT_BACK - front_z + 0.5), Vector3(float(lay["door_x"]), 0.05, (KIT_BACK + front_z) * 0.5), Color(0.7, 0.68, 0.64))
	if style == "split_level":
		# two halves a half story apart
		var half: float = W * 0.5
		_box(root, Vector3(half, 3.0, D), Vector3(hx - half * 0.5, 1.5, cz), wc)
		_box(root, Vector3(half, 4.4, D), Vector3(hx + half * 0.5, 2.2 + 0.6, cz), wc)
		_roof(root, Vector3(D + 0.6, 1.6, half + 0.5), Vector3(hx - half * 0.5, 3.8, cz), rc, PI * 0.5)
		_roof(root, Vector3(D + 0.6, 1.6, half + 0.5), Vector3(hx + half * 0.5, 6.0, cz), rc, PI * 0.5)
		wall_h = 3.0
	else:
		_box(root, Vector3(W, wall_h, D), Vector3(hx, wall_h * 0.5, cz), wc)
		var pitch: float = {"ranch": 1.6, "two_story": 2.2, "farmhouse": 3.0, "craftsman": 2.0}.get(style, 2.0)
		if style == "farmhouse" or style == "craftsman":
			# gable to the street
			_roof(root, Vector3(W + 0.6, pitch, D + 0.6), Vector3(hx, wall_h + pitch * 0.5, cz), rc)
		else:
			# ridge along the street
			_roof(root, Vector3(D + 0.6, pitch, W + 0.6), Vector3(hx, wall_h + pitch * 0.5, cz), rc, PI * 0.5)
		if bool(spec["solar"]):
			_box(root, Vector3(minf(W * 0.6, 7.0), 0.08, D * 0.35), Vector3(hx, wall_h + pitch * 0.55, cz + D * 0.2), Color(0.12, 0.16, 0.3), false, Vector3(-0.45, 0, 0))
	# chimney for a fireplace or wood stove
	if bool(spec["fireplace"]) or str(spec["heat"]) == "wood_stove":
		_box(root, Vector3(0.8, wall_h + 3.0, 0.8), Vector3(float(hr[0]) + 0.6, (wall_h + 3.0) * 0.5, cz), Color(0.55, 0.32, 0.26) if str(spec["siding"]) != "stone" else Color(0.6, 0.58, 0.55))
	# windows on the front, lit when someone is home
	var occupied: bool = int(l["units"][0]) >= 0
	var win_c: Color = Color(1.0, 0.86, 0.5) if occupied else Color(0.25, 0.3, 0.35)
	var n_win: int = clampi(int(W / 2.6), 2, 6)
	var door_x: float = float(lay["door_x"])
	for f in (floors if style != "split_level" else 1):
		for i in n_win:
			var x: float = float(hr[0]) + W * (float(i) + 0.5) / float(n_win)
			if f == 0 and absf(x - door_x) < 0.9:
				continue
			_box(root, Vector3(1.0, 1.1, 0.1), Vector3(x, 1.7 + f * 2.8, front_z + 0.05), win_c, occupied)
	_box(root, Vector3(1.0, 2.0, 0.12), Vector3(door_x, 1.0, front_z + 0.06), Color(0.4, 0.25, 0.15))
	# porch: a floor, posts and a shed roof
	if lay.has("porch"):
		var pr: Array = lay["porch"]
		_flat(root, pr, 0.0, 0.35, Color(0.7, 0.62, 0.52))
		var pk: Array = _kr(pr, 2.7, 0.2)
		_box(root, (pk[0] as Vector3) + Vector3(0.3, 0, 0.3), pk[1], rc)
		var pz: float = KIT_BACK - float(pr[1]) - 0.2
		var nposts: int = clampi(int((float(pr[2]) - float(pr[0])) / 2.5) + 1, 2, 6)
		for i in nposts:
			var px: float = lerpf(float(pr[0]) + 0.2, float(pr[2]) - 0.2, float(i) / float(nposts - 1))
			_box(root, Vector3(0.18, 2.4, 0.18), Vector3(px, 1.55, pz), trim)
	# garage, with a door per stall facing the street (or the alley behind)
	if lay.has("garage"):
		var gr: Array = lay["garage"]
		var gk: Array = _kr(gr, 0.0, 2.9)
		_box(root, gk[0], gk[1], wc.darkened(0.06))
		var gwid: float = float(gr[2]) - float(gr[0])
		var gdep: float = float(gr[3]) - float(gr[1])
		_roof(root, Vector3(gdep + 0.4, 1.2, gwid + 0.4), (gk[1] as Vector3) + Vector3(0, 2.05, 0), rc, PI * 0.5)
		var stalls: int = int(spec["garage"])
		var rear_door: bool = bool(lay.get("garage_rear", false)) and LTHomes.alley_behind(w, l)
		var door_z: float = (KIT_BACK - float(gr[3]) - 0.06) if rear_door else (KIT_BACK - float(gr[1]) + 0.06)
		var sw: float = 3.3
		for i in stalls:
			_box(root, Vector3(sw - 0.6, 2.1, 0.1), Vector3(float(gr[0]) + (float(i) + 0.5) * sw, 1.05, door_z), Color(0.88, 0.88, 0.86))
		if bool(spec["workshop"]):
			_box(root, Vector3(0.9, 2.0, 0.1), Vector3(float(gr[2]) - 1.5, 1.0, door_z), Color(0.45, 0.3, 0.2))
		if bool(lay.get("garage_rear", false)) and not rear_door:
			# a long drive down the side to the garage out back
			_box(root, Vector3(3.0, 0.06, float(gr[1])), Vector3((float(gr[0]) + float(gr[2])) * 0.5, 0.04, KIT_BACK - float(gr[1]) * 0.5), Color(0.62, 0.62, 0.6))
	# the back yard
	if lay.has("fence"):
		var fr: Array = lay["fence"]
		var fc: Color = Color(0.85, 0.82, 0.75)
		var z0: float = KIT_BACK - float(fr[1])
		var z1: float = KIT_BACK - float(fr[3])
		_box(root, Vector3(0.08, 1.2, z0 - z1), Vector3(float(fr[0]), 0.6, (z0 + z1) * 0.5), fc)
		_box(root, Vector3(0.08, 1.2, z0 - z1), Vector3(float(fr[2]), 0.6, (z0 + z1) * 0.5), fc)
		_box(root, Vector3(float(fr[2]) - float(fr[0]), 1.2, 0.08), Vector3((float(fr[0]) + float(fr[2])) * 0.5, 0.6, z1), fc)
	if lay.has("deck"):
		_flat(root, lay["deck"], 0.0, 0.6, Color(0.6, 0.45, 0.3))
	if lay.has("patio"):
		_flat(root, lay["patio"], 0.0, 0.08, Color(0.72, 0.7, 0.66))
	if lay.has("shed"):
		var sk: Array = _kr(lay["shed"], 0.0, 2.3)
		_box(root, sk[0], sk[1], Color(0.6, 0.35, 0.25))
		_roof(root, (sk[0] as Vector3) * Vector3(1.1, 0.4, 1.1), (sk[1] as Vector3) + Vector3(0, 1.6, 0), rc)
	if lay.has("garden") and _season != "Winter":
		_flat(root, lay["garden"], 0.0, 0.12, Color(0.35, 0.25, 0.17))
		var gr2: Array = lay["garden"]
		for i in 5:
			_box(root, Vector3(float(gr2[2]) - float(gr2[0]) - 0.6, 0.35, 0.25), Vector3((float(gr2[0]) + float(gr2[2])) * 0.5, 0.25, KIT_BACK - float(gr2[1]) - 0.4 - float(i) * 0.55), Color(0.3, 0.55, 0.25))
	if lay.has("greenhouse"):
		var gh: Array = _kr(lay["greenhouse"], 0.0, 2.4)
		_box(root, gh[0], gh[1], Color(0.8, 0.92, 0.95, 0.6), true)
	if lay.has("pool"):
		_flat(root, lay["pool"], 0.0, 0.12, Color(0.92, 0.9, 0.85))
		var pk2: Array = _kr(lay["pool"], 0.05, 0.1)
		_box(root, (pk2[0] as Vector3) - Vector3(0.6, 0, 0.6), pk2[1], Color(0.25, 0.6, 0.85) if _season != "Winter" else Color(0.6, 0.65, 0.7))
	if lay.has("shelter"):
		var shk: Array = _kr(lay["shelter"], 0.0, 0.5)
		_box(root, shk[0], shk[1], Color(0.45, 0.5, 0.4))
		_box(root, Vector3(1.0, 0.1, 1.0), (shk[1] as Vector3) + Vector3(0, 0.3, 0), Color(0.5, 0.5, 0.52))
	if not occupied:
		var s: Label3D = _sign(root, "For sale", Vector3(_chair_x(l, 0), 1.5, KIT_BACK - 1.5), 28)
		s.pixel_size = 0.04
	else:
		# two lawn chairs on the side away from the drive, and a flower bed by the front wall
		for i in 2:
			var cv: Vector3 = _chair(l, i)
			_box(root, Vector3(0.7, 0.12, 0.7), cv + Vector3(0, 0.45, 0), Color(0.85, 0.85, 0.8))
			_box(root, Vector3(0.7, 0.7, 0.1), cv + Vector3(0, 0.8, -0.33), Color(0.85, 0.85, 0.8))
			for lx in [-0.3, 0.3]:
				_box(root, Vector3(0.06, 0.45, 0.6), cv + Vector3(lx, 0.22, 0), Color(0.5, 0.5, 0.5))
		var bed: Vector3 = Vector3(door_x + FLOWER_X, 0, front_z + 0.6)
		_box(root, Vector3(1.8, 0.25, 0.7), bed + Vector3(0, 0.12, 0), Color(0.35, 0.25, 0.18))
		if _season != "Winter":
			for i in 4:
				_ball(root, 0.16, bed + Vector3(-0.6 + i * 0.4, 0.35, 0), [Color(0.9, 0.3, 0.4), Color(0.95, 0.85, 0.3), Color(0.6, 0.4, 0.85), Color(0.95, 0.6, 0.3)][i])
	if cond < 0.4:
		_box(root, Vector3(1.4, 0.1, 1.1), Vector3(hx + 2.0, wall_h - 0.9, front_z + 0.12), Color(0.4, 0.3, 0.2))
	# a business run from home: a yard sign, and the work truck in the drive
	var hb: String = _home_biz_name(int(l["id"]))
	if hb != "":
		var nm: String = hb.get_slice("|", 0)
		var bt: String = hb.get_slice("|", 1)
		var sx: float = _chair_x(l, 0)
		_box(root, Vector3(0.12, 1.2, 0.12), Vector3(sx, 0.6, KIT_BACK - 1.0), Color(0.35, 0.25, 0.15))
		_box(root, Vector3(2.2, 0.9, 0.1), Vector3(sx, 1.5, KIT_BACK - 1.0), Color(0.95, 0.93, 0.85))
		var bs: Label3D = _sign(root, nm, Vector3(sx, 2.6, KIT_BACK - 1.0), 26, Color(1.0, 0.95, 0.7))
		bs.pixel_size = 0.035
		if (bt == "construction" or bt == "trucking" or bt == "repair_shop") and lay.has("drive"):
			var dr: Array = lay["drive"]
			var tx: float = (float(dr[0]) + float(dr[2])) * 0.5
			var tc: Color = Color(0.85, 0.65, 0.1) if bt == "construction" else (Color(0.6, 0.15, 0.1) if bt == "trucking" else Color(0.3, 0.3, 0.35))
			_box(root, Vector3(1.8, 1.0, 3.6), Vector3(tx, 0.8, KIT_BACK - 3.0), tc)
			_box(root, Vector3(1.7, 0.8, 1.4), Vector3(tx, 1.6, KIT_BACK - 4.0), Color(0.6, 0.75, 0.85))


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
	elif ["factory", "mill", "warehouse", "trucking", "hotel", "bank", "clinic", "bar", "childcare", "funeral_home", "outfitter", "marina", "campground", "guide_service", "sawmill", "quarry", "gold_mine"].has(btype):
		_special(root, b, btype, open, struggling)
	elif btype == "construction":
		_box(root, Vector3(8.0, 4.0, 6.0), Vector3(-1.5, 2.0, -2.0), Color(0.6, 0.6, 0.62))
		_box(root, Vector3(3.0, 1.6, 1.6), Vector3(3.5, 0.9, 3.0), accent)
		_box(root, Vector3(1.6, 1.2, 1.6), Vector3(4.6, 1.8, 3.0), accent)
		for i in 4:
			_box(root, Vector3(3.0, 0.3, 0.3), Vector3(-3.0, 0.2 + i * 0.32, 4.0), Color(0.75, 0.6, 0.4))
	else:
		_storefront(root, b, btype, open, struggling, accent)
	var two: bool = b.has("bplan") and int(b["bplan"].get("stories", 1)) == 2
	if b.has("bplan"):
		_biz_extras(root, l, b, open)
	var title: String = str(b["name"])
	if not open:
		title += "\nCLOSED"
	var s: Label3D = _sign(root, title, Vector3(0, 9.6 if two else 6.6, 0), 36, Color(1, 1, 1) if open else Color(0.75, 0.7, 0.65))
	s.pixel_size = 0.05


## What the owner built beyond the basic building: apartments upstairs, a
## drive-through, a patio, a loading dock, a parking lot, a playground.
func _biz_extras(root: Node3D, l: Dictionary, b: Dictionary, open: bool) -> void:
	var plan: Dictionary = b["bplan"]
	var feats: Array = plan.get("features", [])
	var lay: Dictionary = LTBuildings.layout(l, plan)
	if feats.has("apartments"):
		var occupied: int = 0
		for u in l["units"]:
			if int(u) >= 0:
				occupied += 1
		_box(root, Vector3(8.0, 3.0, 6.0), Vector3(-0.5, 5.9, -1.5), Color(0.72, 0.52, 0.42))
		_box(root, Vector3(8.4, 0.3, 6.4), Vector3(-0.5, 7.5, -1.5), Color(0.3, 0.3, 0.32))
		for i in 4:
			var lit: bool = i < occupied * 2
			_box(root, Vector3(1.0, 1.3, 0.1), Vector3(-3.5 + float(i) * 2.0, 5.9, 1.55), Color(1.0, 0.86, 0.5) if lit else Color(0.25, 0.3, 0.35), lit)
	if lay.has("parking"):
		var pr: Array = lay["parking"]
		_box(root, Vector3(float(pr[2]) - float(pr[0]), 0.05, float(pr[3]) - float(pr[1])), Vector3((float(pr[0]) + float(pr[2])) * 0.5, 0.04, KIT_BACK - (float(pr[1]) + float(pr[3])) * 0.5), Color(0.32, 0.32, 0.34))
		var cols: int = maxi(1, int((float(pr[2]) - float(pr[0])) / 2.7))
		for i in cols + 1:
			_box(root, Vector3(0.1, 0.02, 4.8), Vector3(float(pr[0]) + float(i) * 2.7, 0.08, KIT_BACK - float(pr[1]) - 2.6), Color(0.95, 0.95, 0.95))
	if lay.has("drive_thru"):
		var dr: Array = lay["drive_thru"]
		var dx: float = (float(dr[0]) + float(dr[2])) * 0.5
		_box(root, Vector3(float(dr[2]) - float(dr[0]), 0.05, KIT_BACK), Vector3(dx, 0.05, KIT_BACK * 0.5 - 1.0), Color(0.36, 0.36, 0.38))
		_box(root, Vector3(0.6, 2.6, 1.6), Vector3(float(dr[0]) + 0.3, 1.3, -1.0), Color(0.95, 0.85, 0.3) if open else Color(0.5, 0.48, 0.4), open)
		_box(root, Vector3(0.12, 1.8, 0.12), Vector3(dx, 0.9, KIT_BACK - 3.0), Color(0.3, 0.3, 0.3))
		_box(root, Vector3(1.4, 1.0, 0.1), Vector3(dx, 2.0, KIT_BACK - 3.0), Color(0.2, 0.25, 0.3))
	if lay.has("patio") and LTCalendar.season(w.day) != "Winter":
		var pa: Array = lay["patio"]
		var n: int = clampi(int((float(pa[2]) - float(pa[0])) / 2.2), 1, 4)
		for i in n:
			var tp: Vector3 = Vector3(float(pa[0]) + 1.1 + float(i) * 2.2, 0, KIT_BACK - (float(pa[1]) + float(pa[3])) * 0.5)
			_cyl(root, 0.5, 0.08, tp + Vector3(0, 0.8, 0), Color(0.92, 0.92, 0.9))
			_cyl(root, 0.06, 0.8, tp + Vector3(0, 0.4, 0), Color(0.3, 0.3, 0.3))
			if open:
				_cyl(root, 0.05, 2.2, tp + Vector3(0, 1.1, 0), Color(0.4, 0.4, 0.4))
				_roof(root, Vector3(1.8, 0.5, 1.8), tp + Vector3(0, 2.3, 0), Color(0.8, 0.3, 0.25))
	if lay.has("dock"):
		var dk: Array = lay["dock"]
		_box(root, Vector3(float(dk[2]) - float(dk[0]), 1.2, 2.5), Vector3((float(dk[0]) + float(dk[2])) * 0.5, 0.6, -5.8), Color(0.55, 0.55, 0.55))
		_box(root, Vector3(2.6, 2.8, 0.1), Vector3((float(dk[0]) + float(dk[2])) * 0.5, 1.6, -4.5), Color(0.4, 0.45, 0.5))
	if lay.has("playground"):
		var pg: Array = lay["playground"]
		var pc: Vector3 = Vector3((float(pg[0]) + float(pg[2])) * 0.5, 0, -7.0)
		_box(root, Vector3(0.2, 1.8, 2.0), pc + Vector3(-1.5, 0.9, 0), Color(0.9, 0.3, 0.3))
		_box(root, Vector3(2.0, 0.15, 2.0), pc + Vector3(1.0, 0.08, 0), Color(0.9, 0.8, 0.5))
	if feats.has("solar"):
		_box(root, Vector3(5.0, 0.1, 3.0), Vector3(-0.5, 4.7 if not feats.has("apartments") else 7.8, -2.0), Color(0.12, 0.16, 0.3))


## The outdoor businesses: an outfitter with a canoe on the roof, a marina with
## docks and boats, a campground of tents and cabins, a guide's log cabin, a
## sawmill with log decks, a quarry pit with gravel piles, and a mine headframe.
func _special_outdoors(root: Node3D, b: Dictionary, btype: String, open: bool, win: Color, lit: bool) -> void:
	var dim: float = 1.0 if open else 0.6
	match btype:
		"outfitter":
			_box(root, Vector3(9.0, 4.0, 7.0), Vector3(0, 2.0, -1.0), Color(0.55, 0.38, 0.22) * dim)
			_roof(root, Vector3(9.6, 2.2, 7.6), Vector3(0, 5.1, -1.0), Color(0.25, 0.32, 0.22))
			_box(root, Vector3(1.0, 0.5, 5.0), Vector3(0, 6.5, -1.0), Color(0.85, 0.35, 0.15))
			_box(root, Vector3(6.0, 1.8, 0.1), Vector3(-0.5, 1.4, 2.55), win, lit)
			_box(root, Vector3(1.1, 2.3, 0.12), Vector3(3.6, 1.15, 2.55), Color(0.35, 0.22, 0.12))
		"marina":
			_box(root, Vector3(6.0, 3.2, 5.0), Vector3(-3.0, 1.6, -2.0), Color(0.85, 0.88, 0.9) * dim)
			_box(root, Vector3(6.4, 0.3, 5.4), Vector3(-3.0, 3.3, -2.0), Color(0.2, 0.35, 0.6))
			_box(root, Vector3(2.0, 0.3, 14.0), Vector3(3.5, 0.4, 2.0), Color(0.55, 0.42, 0.28))
			for i in 3:
				_box(root, Vector3(1.4, 0.5, 3.6), Vector3(5.2, 0.45, -2.0 + float(i) * 4.5), [Color(0.9, 0.9, 0.92), Color(0.8, 0.25, 0.2), Color(0.25, 0.45, 0.7)][i])
			_box(root, Vector3(3.0, 1.2, 0.1), Vector3(-3.0, 1.6, 0.55), win, lit)
		"campground":
			for i in 4:
				var tp: Vector3 = Vector3(-4.5 + float(i % 2) * 6.0, 0.0, -3.5 + float(i / 2) * 5.5)
				_roof(root, Vector3(2.6, 1.8, 3.0), tp + Vector3(0, 0.9, 0), [Color(0.25, 0.5, 0.3), Color(0.8, 0.5, 0.15), Color(0.3, 0.4, 0.7), Color(0.7, 0.25, 0.2)][i])
			_box(root, Vector3(4.0, 3.0, 4.0), Vector3(4.0, 1.5, 3.0), Color(0.5, 0.35, 0.2) * dim)
			_roof(root, Vector3(4.4, 1.6, 4.4), Vector3(4.0, 3.8, 3.0), Color(0.3, 0.25, 0.2))
			_cyl(root, 0.6, 0.3, Vector3(0, 0.15, 1.0), Color(0.3, 0.3, 0.3))
		"guide_service":
			_box(root, Vector3(7.0, 3.2, 6.0), Vector3(0, 1.6, -1.0), Color(0.5, 0.33, 0.18) * dim)
			_roof(root, Vector3(7.6, 2.2, 6.6), Vector3(0, 4.3, -1.0), Color(0.22, 0.3, 0.2))
			_box(root, Vector3(1.2, 0.45, 3.4), Vector3(4.6, 0.5, 2.5), Color(0.3, 0.45, 0.3))
			_box(root, Vector3(2.4, 1.0, 0.1), Vector3(-1.5, 1.8, 2.05), win, lit)
		"sawmill":
			_box(root, Vector3(12.0, 5.0, 7.0), Vector3(0, 2.5, -2.0), Color(0.6, 0.6, 0.62) * dim)
			_roof(root, Vector3(12.4, 1.6, 7.4), Vector3(0, 5.8, -2.0), Color(0.4, 0.4, 0.42))
			for i in 3:
				for k in 3:
					_cyl(root, 0.4, 5.0, Vector3(-4.0 + float(i) * 3.0, 0.4 + float(k) * 0.75, 4.0), Color(0.55, 0.38, 0.22))
		"quarry":
			for i in 3:
				var sz: float = 11.0 - float(i) * 3.0
				_box(root, Vector3(sz, 0.6, sz), Vector3(0, 0.1 - float(i) * 0.05, -1.0), Color(0.6, 0.58, 0.55).darkened(float(i) * 0.12))
			for i in 2:
				_roof(root, Vector3(4.0, 3.0, 4.0), Vector3(-4.5 + float(i) * 9.0, 1.5, 4.0), Color(0.7, 0.68, 0.62))
			_box(root, Vector3(2.2, 1.6, 3.8), Vector3(3.0, 1.0, -5.0), Color(0.95, 0.75, 0.15))
		"gold_mine":
			for x in [-1.6, 1.6]:
				for z in [-1.6, 1.6]:
					_box(root, Vector3(0.3, 10.0, 0.3), Vector3(x, 5.0, z - 1.0), Color(0.35, 0.3, 0.25))
			_box(root, Vector3(3.8, 0.4, 3.8), Vector3(0, 10.2, -1.0), Color(0.35, 0.3, 0.25))
			_cyl(root, 1.2, 0.4, Vector3(0, 10.8, -1.0), Color(0.2, 0.2, 0.22))
			_box(root, Vector3(8.0, 4.0, 5.0), Vector3(-4.0, 2.0, 3.0), Color(0.55, 0.3, 0.2) * dim)
			_roof(root, Vector3(8.4, 1.6, 5.4), Vector3(-4.0, 4.8, 3.0), Color(0.3, 0.3, 0.32))
			_roof(root, Vector3(5.0, 3.0, 5.0), Vector3(5.0, 1.5, 3.0), Color(0.6, 0.5, 0.35))


## Main street businesses, each with its own building: a wide grocery with a
## cart corral, a small cafe with tables out front, a false front general store
## with a porch, a cottage bakery with a chimney, a pharmacy with a green cross and
## a drive through, a two bay repair garage, a brick law office, a little realty
## office with a big sign, and a brick academy with a bell cupola.
func _storefront(root: Node3D, b: Dictionary, btype: String, open: bool, struggling: bool, accent: Color) -> void:
	var lit: bool = open and not struggling
	var glass: Color = Color(1.0, 0.92, 0.65) if lit else (Color(0.55, 0.5, 0.4) if open else Color(0.15, 0.15, 0.17))
	var dim: float = 1.0 if open else 0.6
	var front_z: float = 2.55
	var glass_w: float = 6.0
	var glass_x: float = -0.8
	match btype:
		"grocery":
			_box(root, Vector3(12.4, 4.2, 7.4), Vector3(0, 2.1, -1.2), Color(0.88, 0.86, 0.8) * dim)
			_box(root, Vector3(12.8, 0.4, 7.8), Vector3(0, 4.4, -1.2), Color(0.3, 0.3, 0.32))
			_box(root, Vector3(12.6, 0.35, 1.6), Vector3(0, 3.4, 3.2), accent if open else Color(0.35, 0.33, 0.3))
			glass_w = 9.0
			glass_x = -1.2
			for i in 3:
				_box(root, Vector3(0.1, 0.02, 2.6), Vector3(-4.0 + i * 3.0, 0.08, 5.2), Color(0.95, 0.95, 0.95))
			_box(root, Vector3(1.8, 0.8, 0.9), Vector3(5.0, 0.4, 4.6), Color(0.7, 0.7, 0.72))
			front_z = 2.65
		"cafe":
			_box(root, Vector3(7.5, 3.6, 6.0), Vector3(-1.5, 1.8, -1.5), Color(0.92, 0.86, 0.72) * dim)
			_box(root, Vector3(7.9, 0.4, 6.4), Vector3(-1.5, 3.8, -1.5), Color(0.35, 0.25, 0.2))
			for i in 4:
				_box(root, Vector3(1.9, 0.12, 1.6), Vector3(-4.35 + i * 1.9, 2.9, 2.3), (accent if i % 2 == 0 else Color(0.95, 0.95, 0.9)) if open else Color(0.4, 0.38, 0.35), false, Vector3(0.35, 0, 0))
			glass_w = 4.6
			glass_x = -2.2
			front_z = 1.55
			if open:
				for t in 2:
					_cyl(root, 0.5, 0.08, Vector3(3.2 + t * 2.0, 0.8, 2.4), Color(0.9, 0.9, 0.9))
					_cyl(root, 0.06, 0.8, Vector3(3.2 + t * 2.0, 0.4, 2.4), Color(0.3, 0.3, 0.3))
		"general_store":
			_box(root, Vector3(9.0, 4.0, 7.0), Vector3(0, 2.0, -1.5), Color(0.72, 0.6, 0.45) * dim)
			_box(root, Vector3(9.4, 6.6, 0.3), Vector3(0, 3.3, 2.1), Color(0.78, 0.66, 0.5) * dim)
			_box(root, Vector3(9.6, 0.25, 2.0), Vector3(0, 3.0, 3.2), Color(0.45, 0.32, 0.22))
			for x in [-4.4, -1.5, 1.5, 4.4]:
				_box(root, Vector3(0.2, 3.0, 0.2), Vector3(x, 1.5, 4.1), Color(0.5, 0.36, 0.24))
			_box(root, Vector3(9.6, 0.2, 2.2), Vector3(0, 0.1, 3.2), Color(0.55, 0.42, 0.3))
			front_z = 2.3
		"bakery":
			_box(root, Vector3(7.0, 3.6, 6.0), Vector3(-1.0, 1.8, -1.0), Color(0.95, 0.88, 0.8) * dim)
			_roof(root, Vector3(7.6, 2.4, 6.6), Vector3(-1.0, 4.8, -1.0), Color(0.55, 0.3, 0.25))
			_box(root, Vector3(0.9, 2.4, 0.9), Vector3(1.4, 5.6, -2.0), Color(0.6, 0.35, 0.3))
			_box(root, Vector3(7.2, 0.15, 1.3), Vector3(-1.0, 2.9, 2.6), Color(0.95, 0.6, 0.65) if open else Color(0.4, 0.35, 0.35), false, Vector3(0.3, 0, 0))
			glass_w = 4.0
			glass_x = -2.0
			front_z = 2.05
		"pharmacy":
			_box(root, Vector3(9.0, 3.8, 7.0), Vector3(-1.0, 1.9, -1.0), Color(0.95, 0.95, 0.95) * dim)
			_box(root, Vector3(9.4, 0.4, 7.4), Vector3(-1.0, 4.0, -1.0), Color(0.2, 0.5, 0.35))
			_box(root, Vector3(1.6, 0.45, 0.12), Vector3(-1.0, 3.2, 2.6), Color(0.2, 0.8, 0.35), lit)
			_box(root, Vector3(0.45, 1.6, 0.12), Vector3(-1.0, 3.2, 2.6), Color(0.2, 0.8, 0.35), lit)
			_box(root, Vector3(3.4, 0.3, 4.0), Vector3(5.0, 3.0, -1.0), Color(0.9, 0.9, 0.9))
			for z in [-2.6, 0.6]:
				_box(root, Vector3(0.2, 3.0, 0.2), Vector3(6.4, 1.5, z), Color(0.7, 0.7, 0.7))
			glass_w = 5.0
			glass_x = -1.6
			front_z = 2.55
		"repair_shop":
			_box(root, Vector3(10.0, 4.6, 7.0), Vector3(0, 2.3, -1.0), Color(0.62, 0.62, 0.66) * dim)
			_box(root, Vector3(10.4, 0.3, 7.4), Vector3(0, 4.7, -1.0), Color(0.35, 0.35, 0.38))
			for x in [-2.6, 1.4]:
				_box(root, Vector3(3.2, 3.2, 0.12), Vector3(x, 1.6, 2.55), Color(0.85, 0.85, 0.82) if not open else Color(0.25, 0.27, 0.3))
			_box(root, Vector3(1.6, 1.0, 3.2), Vector3(4.4, 0.7, 4.5), Color(0.55, 0.2, 0.15))
			for i in 3:
				_cyl(root, 0.45, 0.3, Vector3(-4.6, 0.15 + i * 0.3, 4.0), Color(0.1, 0.1, 0.1))
			glass_w = 1.2
			glass_x = 4.2
		"law_office":
			_box(root, Vector3(6.5, 5.4, 6.0), Vector3(0, 2.7, -1.0), Color(0.62, 0.3, 0.25) * dim)
			_box(root, Vector3(6.9, 0.4, 6.4), Vector3(0, 5.6, -1.0), Color(0.85, 0.83, 0.78))
			for x in [-2.0, 2.0]:
				for y in [1.6, 4.0]:
					_box(root, Vector3(1.0, 1.3, 0.1), Vector3(x, y, 2.05), glass, lit)
			_box(root, Vector3(1.2, 0.5, 0.1), Vector3(1.6, 2.6, 2.1), Color(0.75, 0.62, 0.25))
			glass_w = 0.0
			front_z = 2.05
		"real_estate":
			_box(root, Vector3(6.0, 3.4, 5.0), Vector3(-1.5, 1.7, -1.5), Color(0.85, 0.9, 0.95) * dim)
			_roof(root, Vector3(6.4, 1.6, 5.4), Vector3(-1.5, 4.2, -1.5), Color(0.25, 0.35, 0.5))
			_box(root, Vector3(0.15, 2.6, 0.15), Vector3(4.0, 1.3, 3.6), Color(0.9, 0.9, 0.9))
			_box(root, Vector3(2.6, 1.4, 0.1), Vector3(4.0, 2.4, 3.6), accent if open else Color(0.4, 0.4, 0.42))
			glass_w = 3.6
			glass_x = -2.0
			front_z = 1.05
		"private_school":
			_box(root, Vector3(11.0, 4.6, 7.0), Vector3(0, 2.3, -1.2), Color(0.62, 0.32, 0.26) * dim)
			_roof(root, Vector3(11.4, 2.0, 7.4), Vector3(0, 5.6, -1.2), Color(0.25, 0.25, 0.28))
			_box(root, Vector3(1.6, 2.0, 1.6), Vector3(0, 7.4, -1.2), Color(0.92, 0.92, 0.9))
			_roof(root, Vector3(1.9, 1.4, 1.9), Vector3(0, 9.1, -1.2), Color(0.25, 0.25, 0.28))
			_cyl(root, 0.07, 7.0, Vector3(5.2, 3.5, 4.6), Color(0.85, 0.85, 0.85))
			_box(root, Vector3(1.4, 0.9, 0.05), Vector3(5.95, 6.4, 4.6), Color(0.2, 0.3, 0.65))
			for x in [-4.0, -2.0, 2.0, 4.0]:
				_box(root, Vector3(1.2, 1.4, 0.1), Vector3(x, 2.0, 2.35), glass, lit)
			glass_w = 0.0
			front_z = 2.35
		_:
			_box(root, Vector3(10.0, 4.4, 7.0), Vector3(0, 2.2, -1.0), Color(0.85, 0.82, 0.75) * dim)
			_box(root, Vector3(10.4, 0.5, 7.4), Vector3(0, 4.6, -1.0), Color(0.3, 0.3, 0.32))
			_box(root, Vector3(10.2, 0.3, 1.8), Vector3(0, 3.5, 3.2), accent if open else Color(0.35, 0.33, 0.3))
	if glass_w > 0.0:
		_box(root, Vector3(glass_w, 2.0, 0.1), Vector3(glass_x, 1.4, front_z), glass, lit)
		if open and float(b["stock"]) > 5.0 and ["grocery", "general_store", "bakery", "cafe"].has(btype):
			for i in 3:
				_box(root, Vector3(1.0, 0.7, 0.4), Vector3(glass_x - glass_w * 0.3 + i * glass_w * 0.3, 0.6, front_z - 0.35), Color(0.8, 0.6, 0.3))
	_box(root, Vector3(1.1, 2.3, 0.12), Vector3(glass_x + glass_w * 0.5 + 0.9, 1.15, front_z), Color(0.35, 0.22, 0.12))
	if not open:
		for i in 3:
			_box(root, Vector3(maxf(glass_w, 3.0) + 0.4, 0.35, 0.12), Vector3(glass_x, 0.8 + i * 0.7, front_z + 0.1), Color(0.55, 0.42, 0.28), false, Vector3(0, 0, 0.08 * (i - 1)))
	if struggling:
		var sale: Label3D = _sign(root, "SALE", Vector3(glass_x, 2.0, front_z + 0.2), 40, Color(1, 0.3, 0.25))
		sale.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sale.pixel_size = 0.03


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
	_special_outdoors(root, b, btype, open, win, lit)
	if bool(b.get("unlicensed", false)) and open:
		var u: Label3D = _sign(root, "no license posted", Vector3(-3.0, 1.0, 3.2), 22, Color(1.0, 0.6, 0.4))
		u.pixel_size = 0.03


func _farm(root: Node3D, b: Dictionary, open: bool) -> void:
	var inner: float = minf(_lw, _ld) - 1.0
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
	_box(root, Vector3(1.6, 1.0, 0.05), Vector3(6.35, 7.4, 5.5), w.player_color())
	for sx in [-4.0, -2.0, 2.0, 4.0]:
		_box(root, Vector3(0.5, 1.4, 0.12), Vector3(sx, 2.2, 2.55), w.player_color())
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
	var inner: float = 13.2
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
		# someone out at the lake or on the trail is shown there, not at home
		if _watch_mode and (LTCalendar.is_weekend(w.day) or bool(c["retired"])) and LTChoices.hobby_of(c) != "":
			var od: Dictionary = _outdoor_plan(c, _last_hour)
			if not od.is_empty():
				pos = od["pos"]
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
	# a face, so you can tell which way a Sim is looking
	var face: Node3D = Node3D.new()
	face.name = "Face"
	n.add_child(face)
	for x in [-0.075, 0.075]:
		_ball(face, 0.035, Vector3(x, 0.03, 0.175), Color(0.08, 0.08, 0.1))
	_ball(face, 0.03, Vector3(0, -0.03, 0.2), Color(0.85, 0.6, 0.5))
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
	hair.position = head.position + Vector3(0, 0.08, -0.04)
	var face: Node3D = n.get_node_or_null("Face")
	if face != null:
		face.position = head.position
		face.scale = head.scale
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
	var home_p: Vector3 = kit_xform(home) * Vector3(0, 0, 5.0) if home >= 0 else _rough_spot(c)
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
			dest = kit_xform(dest_lot) * Vector3(-3.0 + j * 6.0, 0, 5.0)
		else:
			outside = true
	elif kind == "business" or kind == "owner":
		var b: Dictionary = w.biz(int(job["employer"]))
		if not b.is_empty():
			dest_lot = int(b["lot"])
			dest = kit_xform(dest_lot) * Vector3(-3.0 + j * 6.0, 0, 4.5)
	elif kind == "city":
		var jobrec: Dictionary = w.city["jobs"][int(job["employer"])]
		var svc: Dictionary = LTCivic.service(w, str(jobrec["service"]))
		if not svc.is_empty():
			dest_lot = int(svc["lot"])
			dest = kit_xform(dest_lot) * Vector3(2.0, 0, 5.0)
		else:
			dest_lot = 0
			dest = kit_xform(0) * Vector3(0, 0, 5.0)
	elif kind == "outside":
		outside = true
	var weekend: bool = LTCalendar.is_weekend(w.day)
	if (weekend or bool(c["retired"])) and int(c["sick_days"]) == 0 and age >= 10:
		var od: Dictionary = _outdoor_plan(c, hour)
		if not od.is_empty():
			return od
	if weekend or int(c["sick_days"]) > 0 or (age < 5) or bool(c["retired"]) or kind == "none":
		# an afternoon walk to the shops and back, otherwise around home
		if age >= 5 and int(c["sick_days"]) == 0:
			var shop: Array = w.open_businesses("grocery") + w.open_businesses("cafe")
			if not shop.is_empty():
				var sb: Dictionary = shop[int(c["id"]) % shop.size()]
				var sp: Vector3 = kit_xform(int(sb["lot"])) * Vector3(j * 4.0, 0, 5.0)
				var go: float = 13.0 + j
				var d: float = _trip_hours(home_p, sp, home, int(sb["lot"]), false)
				var stay_until: float = go + d + 0.75
				if hour >= go and hour < go + d:
					return _between(home_p, sp, (hour - go) / d, false, home, int(sb["lot"]))
				if hour >= go + d and hour < stay_until:
					return _potter(c, sp, hour, true)
				if hour >= stay_until and hour < stay_until + d:
					return _between(sp, home_p, (hour - stay_until) / d, false, int(sb["lot"]), home)
		return _at_home(c, home, home_p, hour, hour > 8.0 and hour < 20.0)
	var leave: float = 7.0 + j
	var back: float = 17.0 + j
	var exit_p: Vector3 = _exit_pos() + Vector3(-60.0, 0, 0)
	var by_car: bool = outside and age >= 18
	var far: Vector3 = exit_p if outside else dest
	var far_lot: int = -1 if outside else dest_lot
	var d_out: float = _trip_hours(home_p, far, home, far_lot, by_car)
	if hour < leave or hour >= back + d_out:
		return _at_home(c, home, home_p, hour, hour > 6.5 and hour < 21.5)
	if hour < leave + d_out:
		return _between(home_p, far, (hour - leave) / d_out, by_car, home, far_lot)
	if hour >= back:
		return _between(far, home_p, (hour - back) / d_out, by_car, far_lot, home)
	if outside:
		return {"pos": exit_p, "visible": false, "car": false, "moving": false}
	return _at_work(c, dest, hour)


## How long a trip takes in game hours: by distance and by foot or car, and in
## Watch never shorter than a moment you can actually see.
func _trip_hours(a: Vector3, b: Vector3, from_lot: int, to_lot: int, car: bool) -> float:
	var length: float = _path_len(a, b, from_lot, to_lot)
	var h: float = length / (DRIVE_UPH if car else WALK_UPH)
	h = maxf(h, 2.0 / 60.0)
	if time_scale > 1.5:
		h = maxf(h, MIN_TRIP_REAL_S * time_scale / 3600.0)
	return h


func _path_pts(a: Vector3, b: Vector3, from_lot: int, to_lot: int) -> Array:
	var na: Vector3 = _node_pos(LTGeography.lot_access_node(w, from_lot)) if from_lot >= 0 else _exit_pos()
	var nb: Vector3 = _node_pos(LTGeography.lot_access_node(w, to_lot)) if to_lot >= 0 else _exit_pos()
	return [a, Vector3(a.x, 0, na.z), Vector3(nb.x, 0, na.z), Vector3(nb.x, 0, b.z), b]


func _path_len(a: Vector3, b: Vector3, from_lot: int, to_lot: int) -> float:
	var pts: Array = _path_pts(a, b, from_lot, to_lot)
	var total: float = 0.0
	for i in range(1, pts.size()):
		total += (pts[i] as Vector3).distance_to(pts[i - 1])
	return total


func _hash01(cid: int, k: int, salt: int) -> float:
	var v: float = sin(float(cid) * 12.9898 + float(k) * 78.233 + float(salt) * 37.719) * 43758.5453
	return v - floor(v)


var _shores: Dictionary = {}
var _trail_pts: Array = []


## Free time outdoors, in two hour stretches: fishing from the lake shore, hiking
## the trail up the mountain and back down, or in season, hunting at the forest edge.
func _outdoor_plan(c: Dictionary, hour: float) -> Dictionary:
	var tt: Dictionary = LTTerrain.t(w)
	if tt.is_empty() or hour < 9.0 or hour > 17.0:
		return {}
	var cid: int = int(c["id"])
	var block: int = int(hour / 2.0)
	if _hash01(cid, block + w.day * 13, 21) > 0.45:
		return {}
	match LTChoices.hobby_of(c):
		"fishing":
			if tt["lakes"].is_empty():
				return {}
			var li: int = cid % tt["lakes"].size()
			if not _shores.has(li):
				_shores[li] = LTTerrain.shore_spots(w, li, 28)
			var spot: Vector2 = _shores[li][cid % 28]
			var cen: Vector2 = tt["lakes"][li]["c"]
			var d: Vector2 = cen - spot
			return {"pos": Vector3(spot.x, 0, spot.y), "visible": true, "car": false, "moving": false, "face": atan2(d.x, d.y)}
		"hiking":
			if _trail_pts.is_empty():
				_trail_pts = LTTerrain.trail(w)
			var k: float = fmod(hour, 2.0) / 2.0
			var up: bool = k < 0.5
			var tpos: float = (k * 2.0 if up else (1.0 - k) * 2.0) * float(_trail_pts.size() - 1)
			var i0: int = clampi(int(tpos), 0, _trail_pts.size() - 2)
			var a: Vector2 = _trail_pts[i0]
			var b: Vector2 = _trail_pts[i0 + 1]
			var p: Vector2 = a.lerp(b, tpos - float(i0)) + Vector2(sin(float(cid)) * 1.5, 0)
			var dirv: Vector2 = (b - a) if up else (a - b)
			return {"pos": Vector3(p.x, 0, p.y), "visible": true, "car": false, "moving": time_scale > 0.0, "dir": Vector3(dirv.x, 0, dirv.y).normalized()}
		"hunting":
			if not LTChoices.hunting_open(w):
				return {}
			var f: Dictionary = tt["forest"]
			var ang: float = _hash01(cid, 3, 7) * TAU
			var spot2: Vector2 = (f["c"] as Vector2) + Vector2(cos(ang) * float(f["rx"]), sin(ang) * float(f["rz"])) * 0.97
			var d2: Vector2 = (f["c"] as Vector2) - spot2
			return {"pos": Vector3(spot2.x, 0, spot2.y), "visible": true, "car": false, "moving": false, "face": atan2(d2.x, d2.y)}
	return {}


## The front door's x on the lot.
func _house_hx(l: Dictionary) -> float:
	return float(_house_dims(l)[2])


var _lay_cache: Dictionary = {}


## A lot's house layout, cached until the family changes the house.
func _lay(l: Dictionary) -> Dictionary:
	var c = _lay_cache.get(int(l["id"]))
	if c != null and is_same(c[0], l["home"]):
		return c[1]
	var lay: Dictionary = LTHomes.layout(l, l["home"])
	_lay_cache[int(l["id"])] = [l["home"], lay]
	return lay


## [house width, garage width, door x] from the family's own layout.
func _house_dims(l: Dictionary) -> Array:
	if not l.has("home"):
		return [8.0, 0.0, 0.0]
	var lay: Dictionary = _lay(l)
	return [float(lay["W"]), float(lay["gw"]), float(lay["door_x"])]


## The kit z of the house front.
func _front_z(l: Dictionary) -> float:
	if not l.has("home"):
		return 2.5
	return KIT_BACK - float(_lay(l)["house"][1])


## Lawn chairs sit in the front yard on the side away from the driveway.
func _chair_x(l: Dictionary, i: int) -> float:
	var side: float = -1.0
	if l.has("home"):
		var lay: Dictionary = _lay(l)
		if lay.has("drive"):
			var dr: Array = lay["drive"]
			side = 1.0 if (float(dr[0]) + float(dr[2])) * 0.5 < float(lay["door_x"]) else -1.0
	var fw: float = LTGeography.lot_frontage(l)
	return side * minf(fw * 0.5 - 2.0, 4.7) + (1.1 if side < 0.0 else -1.1) * float(i)


func _chair(l: Dictionary, i: int) -> Vector3:
	return Vector3(_chair_x(l, i), 0, minf(KIT_BACK - 2.5, _front_z(l) + 3.0))


## Free time at home. Most of it is spent indoors, out of sight, as real people
## do. Outside you can tell what a Sim is doing: sitting in a lawn chair, kneeling
## at the flower bed, walking down the sidewalk and back, or (children) playing
## in the yard. Each stretch of about twenty minutes is one choice.
func _at_home(c: Dictionary, home: int, home_p: Vector3, hour: float, window: bool) -> Dictionary:
	var inside: Dictionary = {"pos": home_p, "visible": false, "car": false, "moving": false}
	if not window or home < 0 or str(w.lot(home)["use"]) != "house":
		return inside if home >= 0 else {"pos": home_p, "visible": window, "car": false, "moving": false}
	if w.weather == "Rain" or w.weather == "Storm" or (w.weather == "Snow" and w.age_years(c) >= 13):
		return inside
	var cid: int = int(c["id"])
	var block_min: float = maxf(20.0, time_scale * 4.0 / 60.0)
	var minute: float = hour * 60.0
	var k: int = int(floor(minute / block_min))
	var roll: float = _hash01(cid, k, 5)
	var age: int = w.age_years(c)
	var kx: Transform3D = kit_xform(home)
	var face0: float = lot_rot(w.lot(home))
	if age < 13:
		if roll < 0.55:
			# playing: quicker and wider than an adult's pottering
			var pl: Dictionary = _potter(c, kx * Vector3(-2.0, 0, 4.6), hour * 2.5, true)
			pl["visible"] = true
			return pl
		return inside
	var sit_p: float = 0.4 if age >= 60 else 0.22
	if roll < sit_p:
		var hh: Dictionary = w.hh(int(c["household"]))
		var idx: int = maxi(0, hh["members"].find(cid)) % 2
		return {"pos": kx * (_chair(w.lot(home), idx) + Vector3(0, 0, 0.1)), "visible": true, "car": false, "moving": false, "pose": "sit", "face": face0}
	if roll < sit_p + 0.12 and _season != "Winter":
		return {"pos": kx * Vector3(_house_hx(w.lot(home)) + FLOWER_X, 0, _front_z(w.lot(home)) + 1.35), "visible": true, "car": false, "moving": false, "pose": "kneel", "face": face0 + PI}
	if roll < sit_p + 0.25:
		# a walk down the sidewalk and back
		var walk_t: float = fmod(minute, block_min) / block_min
		var side: float = -1.0 if _hash01(cid, k, 6) < 0.5 else 1.0
		var gate: Vector3 = kx * Vector3(0, 0, KIT_BACK + 2.5)
		var far: Vector3 = gate + lot_xform(home).basis.x * side * 40.0
		var pos: Vector3
		var dir: Vector3
		if walk_t < 0.1:
			pos = home_p.lerp(gate, walk_t / 0.1)
			dir = (gate - home_p).normalized()
		elif walk_t < 0.5:
			pos = gate.lerp(far, (walk_t - 0.1) / 0.4)
			dir = (far - gate).normalized()
		elif walk_t < 0.9:
			pos = far.lerp(gate, (walk_t - 0.5) / 0.4)
			dir = (gate - far).normalized()
		else:
			pos = gate.lerp(home_p, (walk_t - 0.9) / 0.1)
			dir = (home_p - gate).normalized()
		return {"pos": pos, "visible": true, "car": false, "moving": time_scale > 0.0, "dir": dir}
	return inside


## At work or school: inside, except for a mid morning break, lunch and a mid
## afternoon break (recess for children), when they step out front.
func _at_work(c: Dictionary, spot: Vector3, hour: float) -> Dictionary:
	var student: bool = w.age_years(c) < 18
	var breaks: Array = [[10.25, 10.6], [12.25, 12.75]] if student else [[10.0, 10.25], [12.0, 12.5], [15.0, 15.2]]
	for br in breaks:
		if hour >= float(br[0]) and hour < float(br[1]):
			var p: Dictionary = _potter(c, spot, hour * (2.5 if student else 1.0), true)
			p["visible"] = true
			return p
	return {"pos": spot, "visible": false, "car": false, "moving": false}


## A Sim at home or at work does not stand frozen: every few minutes they walk a
## few steps to somewhere nearby and stop again. Driven by the game clock, so it
## is the same at any speed; only shown when time runs close to real time.
func _potter(c: Dictionary, spot: Vector3, hour: float, visible: bool) -> Dictionary:
	if time_scale > 60.0 or not visible:
		return {"pos": spot, "visible": visible, "car": false, "moving": false}
	var cid: int = int(c["id"])
	var minute: float = hour * 60.0
	var period: float = 2.0 + _hash01(cid, 0, 9) * 3.0
	var k: int = int(floor(minute / period))
	var p0: Vector3 = spot + Vector3(_hash01(cid, k - 1, 1) * 2.0 - 1.0, 0, _hash01(cid, k - 1, 2) * 2.0 - 1.0) * 2.4
	var p1: Vector3 = spot + Vector3(_hash01(cid, k, 1) * 2.0 - 1.0, 0, _hash01(cid, k, 2) * 2.0 - 1.0) * 2.4
	var walk_min: float = p0.distance_to(p1) / (WALK_UPH / 60.0) * 1.6
	var into: float = minute - float(k) * period
	if into < walk_min and walk_min > 0.0:
		var dir: Vector3 = (p1 - p0).normalized()
		return {"pos": p0.lerp(p1, into / walk_min), "visible": true, "car": false, "moving": true, "dir": dir}
	return {"pos": p1, "visible": true, "car": false, "moving": false}


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
	var pts: Array = _path_pts(a, b, from_lot, to_lot)
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
	# keep to the side of the road, easing on and off it at each end of the trip
	var side: Vector3 = Vector3(dir.z, 0, -dir.x) * (1.2 if car else 2.6) * clampf(minf(t, 1.0 - t) * 12.0, 0.0, 1.0)
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
	people_root.visible = dist < PEOPLE_DIST
	_tier_timer += delta
	if _tier_timer > 1.5:
		_tier_timer = 0.0
		if people_root.visible:
			_refresh_tier()
		_listen()
	var cars: int = 0
	var walkers: int = 0
	for cid in (sim_nodes if people_root.visible else {}):
		var n: Node3D = sim_nodes[cid]
		var c: Dictionary = w.cit(int(cid))
		if not w.is_present(c):
			n.visible = false
			continue
		# day by day speeds show everyone still, where they are at one time of day
		var plan: Dictionary = sim_plan(c, hour if watch else FREEZE_HOUR)
		var was_visible: bool = n.visible
		n.visible = bool(plan["visible"])
		var car: Node3D = n.get_node("Car")
		car.visible = bool(plan["car"])
		if n.visible:
			if bool(plan["car"]) and bool(plan["moving"]):
				cars += 1
			elif not bool(plan["car"]):
				walkers += 1
		n.get_node("Body").visible = not bool(plan["car"])
		n.get_node("Head").visible = not bool(plan["car"])
		n.get_node("Hair").visible = not bool(plan["car"])
		if n.has_node("Face"):
			n.get_node("Face").visible = not bool(plan["car"])
		var p: Vector3 = plan["pos"]
		if not watch or not was_visible or n.position.distance_to(p) > 60.0:
			# still frames, or the Sim was out of sight: just be there
			n.position = p
		else:
			n.position = n.position.lerp(p, clampf(delta * 10.0, 0.0, 1.0))
		# Sims walk on the ground, up the mountain trail too
		var gy: float = LTTerrain.height(w, n.position.x, n.position.z)
		if plan.has("dir") and bool(plan["moving"]):
			var d: Vector3 = plan["dir"]
			n.rotation.y = atan2(d.x, d.z)
		elif plan.has("face"):
			n.rotation.y = float(plan["face"])
		# sitting in a chair or kneeling in the garden: lower the whole Sim a little
		var pose: String = str(plan.get("pose", ""))
		var sink: float = 0.45 if pose == "sit" else (0.35 if pose == "kneel" else 0.0)
		n.position.y = lerpf(n.position.y, gy - sink, clampf(delta * 8.0, 0.0, 1.0)) if watch else gy - sink
		var body: Node3D = n.get_node("Body")
		body.rotation.z = sin(Time.get_ticks_msec() / 120.0) * 0.08 if watch and time_scale > 0.0 and bool(plan["moving"]) and not bool(plan["car"]) else 0.0
	for t in truck_nodes:
		var tn: Node3D = t["node"]
		var tt: float = (hour - float(t["start"])) / 1.5 if watch else 0.5
		var plan2: Dictionary = _between(_exit_pos() + Vector3(-60, 0, 0), kit_xform(int(t["lot"])) * Vector3(5.0, 0, 9.0), tt, true, -1, int(t["lot"]))
		tn.visible = watch and tt > 0.0 and tt < 1.0
		if tn.visible and tn.position.distance_to(target) < dist * 1.2:
			cars += 2
		tn.position = plan2["pos"]
		if plan2.has("dir"):
			tn.rotation.y = atan2((plan2["dir"] as Vector3).x, (plan2["dir"] as Vector3).z)
	if people_root.visible:
		audio["traffic"] = lerpf(float(audio["traffic"]), clampf(float(cars) / 6.0, 0.0, 1.0), clampf(delta, 0.0, 1.0))
		audio["crowd"] = lerpf(float(audio["crowd"]), clampf(float(walkers) / 15.0, 0.0, 1.0), clampf(delta, 0.0, 1.0))
	_move_wildlife(delta)
	_camera_keys(delta)


## How much of the town's own sound reaches the camera: none above street level,
## fading in over the last stretch of zoom.
func street_level() -> float:
	return clampf((PEOPLE_DIST - dist) / SOUND_FADE, 0.0, 1.0)


## Building sites near the camera make construction noise.
func _listen() -> void:
	var sites: int = 0
	for l in w.lots:
		if str(l["use"]) == "site" and lot_center(int(l["id"])).distance_to(target) < dist * 1.3 + 20.0:
			sites += 1
	for p in w.projects:
		if str(p["status"]) == "building" and LTProjects.is_road(str(p["ptype"])):
			for sid in p.get("segments", w.streets[int(p["street"])]["segments"]):
				var sg: Dictionary = w.roads[int(sid)]
				if (_node_pos(int(sg["a"])) + _node_pos(int(sg["b"]))).distance_to(target * 2.0) < (dist * 1.3 + 20.0) * 2.0:
					sites += 1
					break
	audio["building"] = clampf(float(sites) / 2.0, 0.0, 1.0)


var camper: Node3D


## Until the mayor's house is built, the founder lives in a camper by the county road.
func _refresh_camper() -> void:
	var need: bool = int(w.player.get("home_lot", -1)) < 0
	if not need:
		if camper != null:
			camper.queue_free()
			camper = null
		return
	var sig: String = "%s|%s" % [w.player.get("name", ""), w.player.get("color", "")]
	if camper != null and is_instance_valid(camper):
		if str(camper.get_meta("sig", "")) == sig:
			return
		camper.queue_free()
	camper = Node3D.new()
	camper.set_meta("sig", sig)
	camper.position = _exit_pos() + (Vector3(CELL * 1.5, 0, -8.0) if bool(w.config.get("open_land", false)) else Vector3(-12.0, 0, -7.0))
	extra_root.add_child(camper)
	_box(camper, Vector3(2.6, 2.6, 7.0), Vector3(0, 1.6, 0), Color(0.93, 0.92, 0.88))
	_box(camper, Vector3(2.65, 0.4, 7.05), Vector3(0, 1.6, 0), w.player_color())
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
	var fwd: Vector3 = Vector3(-sin(g_yaw), 0, -cos(g_yaw))
	var right: Vector3 = Vector3(cos(g_yaw), 0, -sin(g_yaw))
	if not _typing():
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			move += fwd
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			move -= fwd
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			move += right
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			move -= right
		if Input.is_key_pressed(KEY_Q):
			g_yaw += delta * 1.2
		if Input.is_key_pressed(KEY_E):
			g_yaw -= delta * 1.2
	if move != Vector3.ZERO:
		g_target += move.normalized() * delta * g_dist * 0.8
	_clamp_goals()
	# glide toward the goal instead of jumping, so nothing ever flings
	var k: float = clampf(delta * 9.0, 0.0, 1.0)
	target = target.lerp(g_target, k)
	yaw = lerp_angle(yaw, g_yaw, k)
	pitch = lerpf(pitch, g_pitch, k)
	dist = lerpf(dist, g_dist, k)
	_update_camera()


func _typing() -> bool:
	var f: Control = get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit or f is SpinBox


func map_size() -> Vector2:
	return Vector2(float(w.config["map_cols"]) * CELL, float(w.config["map_rows"]) * CELL)


func _clamp_goals() -> void:
	var ms: Vector2 = map_size()
	g_target.x = clampf(g_target.x, -CELL * 3.0, ms.x + CELL * 3.0)
	g_target.z = clampf(g_target.z, -CELL * 3.0, ms.y + CELL * 3.0)
	g_target.y = 0.0
	g_pitch = clampf(g_pitch, -1.45, -0.25)
	g_dist = clampf(g_dist, 14.0, maxf(420.0, maxf(ms.x, ms.y) * 1.25))


func _pan(rel: Vector2) -> void:
	var right: Vector3 = Vector3(cos(g_yaw), 0, -sin(g_yaw))
	var fwd: Vector3 = Vector3(-sin(g_yaw), 0, -cos(g_yaw))
	g_target -= right * rel.x * g_dist * 0.0016
	g_target += fwd * rel.y * g_dist * 0.0016


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			g_dist *= 0.9
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			g_dist *= 1.1
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press_pos = mb.position
				if tool != "look":
					_tool_start(mb.position)
			else:
				if tool != "look":
					_tool_end(mb.position)
				elif _press_pos.distance_to(mb.position) < 8.0 and _touches.size() <= 1:
					_pick(mb.position)
		_clamp_goals()
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		# read the buttons held right now, not a remembered flag, so a release over a panel never sticks
		if mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			g_yaw -= mm.relative.x * 0.006
			g_pitch -= mm.relative.y * 0.005
		elif mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE or (mm.button_mask & MOUSE_BUTTON_MASK_LEFT and Input.is_key_pressed(KEY_SHIFT)):
			_pan(mm.relative)
		elif mm.button_mask & MOUSE_BUTTON_MASK_LEFT and tool != "look":
			_tool_drag(mm.position)
		_clamp_goals()
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		_pinch = {}
	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event
		_touches[sd.index] = sd.position
		if _touches.size() == 1:
			if tool == "look":
				_pan(sd.relative)
		elif _touches.size() >= 2:
			# two fingers: pinch to zoom, twist to turn, move together to pan
			var ks: Array = _touches.keys()
			var p0: Vector2 = _touches[ks[0]]
			var p1: Vector2 = _touches[ks[1]]
			var d: float = maxf(p0.distance_to(p1), 1.0)
			var ang: float = (p1 - p0).angle()
			var mid: Vector2 = (p0 + p1) * 0.5
			if not _pinch.is_empty():
				g_dist *= clampf(float(_pinch["d"]) / d, 0.8, 1.25)
				g_yaw += clampf(angle_difference(float(_pinch["a"]), ang), -0.2, 0.2)
				_pan((mid - (_pinch["m"] as Vector2)) * 0.5)
			_pinch = {"d": d, "a": ang, "m": mid}
		_clamp_goals()


# ------------------------------------------------------------------ build tools: draw roads, plot lots

func set_tool(t: String) -> void:
	tool = t
	_tool_drag_on = false
	if grid_mi != null:
		grid_mi.visible = t != "look"
	if preview_mi != null:
		preview_mi.visible = false


func _ground_point(screen: Vector2) -> Vector3:
	var from: Vector3 = cam.project_ray_origin(screen)
	var dir: Vector3 = cam.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return Vector3(-1e6, 0, -1e6)
	var t: float = -from.y / dir.y
	if t < 0.0:
		return Vector3(-1e6, 0, -1e6)
	return from + dir * t


## The survey corner nearest a ground point (roads snap to the 10 meter grid).
func _nearest_node(g: Vector3) -> Vector2i:
	var cols: int = int(w.config["map_cols"])
	var rows: int = int(w.config["map_rows"])
	return Vector2i(clampi(int(round(g.x / CELL)), 0, cols), clampi(int(round(g.z / CELL)), 0, rows))


## What the road tool lays: "street" or "alley". Lot width when plotting: 0 means
## one lot exactly as dragged, otherwise the strip is cut into lots that wide.
var road_kind: String = "street"
var plot_width: float = 0.0
var _ta: Vector3 = Vector3.ZERO
var _tb: Vector3 = Vector3.ZERO


func _tool_start(screen: Vector2) -> void:
	var g: Vector3 = _ground_point(screen)
	if g.x < -1e5:
		return
	_tool_drag_on = true
	_ta = g
	_tb = g
	_show_preview()


func _tool_drag(screen: Vector2) -> void:
	if not _tool_drag_on:
		return
	var g: Vector3 = _ground_point(screen)
	if g.x < -1e5:
		return
	_tb = g
	_show_preview()


## The two survey corners of the road being drawn, kept straight.
func _road_ends() -> Array:
	var a: Vector2i = _nearest_node(_ta)
	var b: Vector2i = _nearest_node(_tb)
	if absi(b.x - a.x) >= absi(b.y - a.y):
		b.y = a.y
	else:
		b.x = a.x
	return [a, b]


## The lot rectangle being dragged, in whole meters, with each side pulled onto a
## nearby road's edge so lots line up with the street like real property lines.
func _plot_rect() -> Rect2:
	var r: Rect2 = Rect2(Vector2(roundf(minf(_ta.x, _tb.x)), roundf(minf(_ta.z, _tb.z))), Vector2.ZERO).expand(Vector2(roundf(maxf(_ta.x, _tb.x)), roundf(maxf(_ta.z, _tb.z))))
	var x0: float = r.position.x
	var z0: float = r.position.y
	var x1: float = r.end.x
	var z1: float = r.end.y
	var near: Rect2 = r.grow(6.0)
	for sg in w.roads:
		if bool(sg.get("removed", false)):
			continue
		var rr: Rect2 = LTGeography.seg_rect(w, sg)
		if not near.intersects(rr):
			continue
		var over_x: bool = rr.position.x < x1 and rr.end.x > x0
		var over_z: bool = rr.position.y < z1 and rr.end.y > z0
		if over_x and absf(rr.end.y - z0) < 5.0:
			z0 = rr.end.y
		if over_x and absf(rr.position.y - z1) < 5.0:
			z1 = rr.position.y
		if over_z and absf(rr.end.x - x0) < 5.0:
			x0 = rr.end.x
		if over_z and absf(rr.position.x - x1) < 5.0:
			x1 = rr.position.x
	return Rect2(Vector2(x0, z0), Vector2(maxf(0.0, x1 - x0), maxf(0.0, z1 - z0)))


func _tool_end(screen: Vector2) -> void:
	if not _tool_drag_on:
		return
	_tool_drag(screen)
	_tool_drag_on = false
	preview_mi.visible = false
	var g0: Vector3 = _ground_point(screen)
	if tool != "unplot" and _press_pos.distance_to(screen) < 8.0:
		# a tap with a build tool opens the road or lot under it to edit its details
		if tool == "road" and _road_at(g0) >= 0 or tool == "plot" and LTGeography.lot_at(w, g0.x, g0.z) >= 0:
			_pick(screen)
		return
	var r: Dictionary = {}
	match tool:
		"road":
			var ends: Array = _road_ends()
			var a: Vector2i = ends[0]
			var b: Vector2i = ends[1]
			if a == b:
				r = {"message": "Drag farther to draw a road."}
			else:
				r = main.act({"kind": "plan_road", "a": LTGeography.node_id(w, a.x, a.y), "b": LTGeography.node_id(w, b.x, b.y), "road_kind": road_kind})
		"plot":
			var pr: Rect2 = _plot_rect()
			r = main.act({"kind": "plot_lots", "x0": pr.position.x, "z0": pr.position.y, "x1": pr.end.x, "z1": pr.end.y, "zone": plot_zone, "width": plot_width})
		"unplot":
			var lid: int = LTGeography.lot_at(w, _ta.x, _ta.z)
			r = main.act({"kind": "unplot", "lot": lid}) if lid >= 0 else {"message": "There is no lot there."}
	if not r.is_empty():
		var msg: String = str(r.get("message", ""))
		main.hud.show_toast(msg)
		if tool == "road" and bool(r.get("ok", false)):
			# open the draft contract right away: write it, then Go live
			main.hud.inspect("road", int(r.get("street", -1)))


func _show_preview() -> void:
	if preview_mi == null:
		return
	preview_mi.visible = true
	var mat: StandardMaterial3D = preview_mi.material_override
	if tool == "road":
		var ends: Array = _road_ends()
		var a: Vector2i = ends[0]
		var b: Vector2i = ends[1]
		var pa: Vector3 = Vector3(float(a.x) * CELL, 0.3, float(a.y) * CELL)
		var pb: Vector3 = Vector3(float(b.x) * CELL, 0.3, float(b.y) * CELL)
		var horiz: bool = a.y == b.y
		var rw: float = ROAD_W * (float(LTProjects.WIDTHS["alley"]["draw"]) if road_kind == "alley" else 1.0)
		var length: float = pa.distance_to(pb) + rw
		(preview_mi.mesh as BoxMesh).size = Vector3(length, 0.2, rw) if horiz else Vector3(rw, 0.2, length)
		preview_mi.position = (pa + pb) * 0.5
		mat.albedo_color = Color(1.0, 0.85, 0.2, 0.55) if road_kind != "alley" else Color(0.85, 0.75, 0.55, 0.6)
	else:
		var r: Rect2 = _plot_rect() if tool == "plot" else Rect2(_ta.x - 1.0, _ta.z - 1.0, 2.0, 2.0)
		(preview_mi.mesh as BoxMesh).size = Vector3(maxf(0.5, r.size.x), 0.2, maxf(0.5, r.size.y))
		preview_mi.position = Vector3(r.get_center().x, 0.3, r.get_center().y)
		mat.albedo_color = (_zone_color(plot_zone) if tool == "plot" else Color(0.9, 0.3, 0.25)) * Color(1, 1, 1, 0.6)
		if tool == "plot":
			main.hud.show_toast(_plot_note(r))


## Size of the lot being dragged, in meters and feet, and how many lots it makes.
func _plot_note(r: Rect2) -> String:
	var t: String = "%d x %d m (%d x %d ft)" % [int(r.size.x), int(r.size.y), int(r.size.x * 3.28), int(r.size.y * 3.28)]
	if plot_width >= 6.0:
		var span: float = maxf(r.size.x, r.size.y)
		t += ", about %d lots %d m wide" % [maxi(1, int(floor(span / plot_width + 0.25))), int(plot_width)]
	return t


func _build_tool_meshes() -> void:
	preview_mi = MeshInstance3D.new()
	preview_mi.mesh = BoxMesh.new()
	var pm: StandardMaterial3D = StandardMaterial3D.new()
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	preview_mi.material_override = pm
	preview_mi.visible = false
	extra_root.add_child(preview_mi)
	# the survey grid: where roads can go (every 10 m), with a brighter line every
	# 100 m, a standard town block; shown only while a build tool is in hand
	var cols: int = int(w.config["map_cols"])
	var rows: int = int(w.config["map_rows"])
	var im: ImmediateMesh = ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in cols + 1:
		im.surface_set_color(Color(1, 1, 1, 0.45) if i % 10 == 0 else Color(1, 1, 1, 0.12))
		im.surface_add_vertex(Vector3(float(i) * CELL, 0.12, 0.0))
		im.surface_add_vertex(Vector3(float(i) * CELL, 0.12, float(rows) * CELL))
	for j in rows + 1:
		im.surface_set_color(Color(1, 1, 1, 0.45) if j % 10 == 0 else Color(1, 1, 1, 0.12))
		im.surface_add_vertex(Vector3(0.0, 0.12, float(j) * CELL))
		im.surface_add_vertex(Vector3(float(cols) * CELL, 0.12, float(j) * CELL))
	im.surface_end()
	grid_mi = MeshInstance3D.new()
	grid_mi.mesh = im
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.vertex_color_use_as_albedo = true
	grid_mi.material_override = gm
	grid_mi.visible = tool != "look"
	extra_root.add_child(grid_mi)


func _pick(screen: Vector2) -> void:
	# Sims first, then lots, by distance on screen
	var best: float = 22.0
	var hit_sim: int = -1
	for cid in sim_nodes:
		var n: Node3D = sim_nodes[cid]
		if not n.visible or not people_root.visible:
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
	var road: int = _road_at(g)
	if road >= 0:
		select_lot(-1)
		select_road(road)
		main.hud.inspect("road", road)
		return
	var lid: int = LTGeography.lot_at(w, g.x, g.z)
	if lid >= 0:
		select_road(-1)
		select_lot(lid)
		main.hud.inspect("lot", lid)


## The street under a ground point, built or planned, or -1.
func _road_at(g: Vector3) -> int:
	var p: Vector2 = Vector2(g.x, g.z)
	var best: int = -1
	var best_d: float = 1e9
	for sg in w.roads:
		if bool(sg.get("removed", false)):
			continue
		if not LTGeography.seg_rect(w, sg).has_point(p):
			continue
		var a: Vector2 = LTGeography.node_pos(w, int(sg["a"]))
		var b: Vector2 = LTGeography.node_pos(w, int(sg["b"]))
		var d: float = Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
		if d < best_d:
			best_d = d
			best = int(sg["street"])
	return best


## Outlines the blocks of one street so the mayor can see what they picked.
func select_road(street_id: int) -> void:
	selected_road = street_id
	if road_hl_mi != null:
		road_hl_mi.queue_free()
		road_hl_mi = null
	if street_id < 0 or street_id >= w.streets.size():
		return
	_batch_begin()
	for sid in w.streets[street_id]["segments"]:
		var s: Dictionary = w.roads[int(sid)]
		if bool(s.get("removed", false)):
			continue
		var pa: Vector3 = _node_pos(int(s["a"]))
		var pb: Vector3 = _node_pos(int(s["b"]))
		var horiz: bool = absf(pa.z - pb.z) < 0.01
		var wd: float = _road_width(street_id) + 1.2
		_box(road_root, Vector3(CELL + wd, 0.05, wd) if horiz else Vector3(wd, 0.05, CELL + wd), (pa + pb) * 0.5 + Vector3(0, 0.09, 0), Color(1.0, 0.85, 0.2), true)
	road_hl_mi = _batch_end(road_root)
	road_hl_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func focus_street(street_id: int) -> void:
	if street_id < 0 or street_id >= w.streets.size():
		return
	var c: Vector3 = Vector3.ZERO
	var n: int = 0
	for sid in w.streets[street_id]["segments"]:
		var s: Dictionary = w.roads[int(sid)]
		if bool(s.get("removed", false)):
			continue
		c += _node_pos(int(s["a"])) + _node_pos(int(s["b"]))
		n += 2
	if n > 0:
		g_target = c / float(n)
		g_dist = minf(g_dist, 110.0)
		_clamp_goals()


## Width on the map for a street's contract (or what was built).
func _road_width(street_id: int) -> float:
	var st: Dictionary = w.streets[street_id]
	var wd: String = str(st.get("width", ""))
	if wd == "":
		for p in w.projects:
			if str(p["ptype"]) == "road_build" and int(p["street"]) == street_id and p.has("spec"):
				wd = str(p["spec"]["width"])
	if wd == "" and str(st["kind"]) == "alley":
		wd = "alley"
	if wd == "" or not LTProjects.WIDTHS.has(wd):
		return ROAD_W
	return ROAD_W * float(LTProjects.WIDTHS[wd]["draw"])


func select_lot(lid: int) -> void:
	selected_lot = lid
	if lid < 0:
		highlight.visible = false
		return
	highlight.visible = true
	var hl: Dictionary = w.lot(lid)
	(highlight.mesh as BoxMesh).size = Vector3(float(hl["x1"]) - float(hl["x0"]), 0.15, float(hl["z1"]) - float(hl["z0"]))
	highlight.position = lot_center(lid) + Vector3(0, 0.12, 0)


func focus_lot(lid: int) -> void:
	if lid < 0:
		return
	g_target = lot_center(lid)
	g_dist = minf(g_dist, 60.0)
	select_lot(lid)


func focus_sim(cid: int, hour: float) -> void:
	var c: Dictionary = w.cit(cid)
	if c.is_empty():
		return
	var plan: Dictionary = sim_plan(c, hour if _watch_mode else 12.5)
	var goal: Vector3 = plan["pos"]
	var ms: Vector2 = map_size()
	if not bool(plan["visible"]) or goal.x < 0.0 or goal.z < 0.0 or goal.x > ms.x or goal.z > ms.y:
		# away at work out of town, on the highway, or asleep: show their home instead
		var hl: int = int(w.hh(int(c["household"]))["lot"])
		if hl < 0:
			return
		goal = lot_center(hl)
	g_target = goal
	g_dist = minf(g_dist, 45.0)
	_refresh_tier()


func _is_night() -> bool:
	return _last_hour < 6.0 or _last_hour > 19.5
