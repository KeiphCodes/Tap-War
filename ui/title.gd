extends CanvasLayer
## The title screen: the game's name over a live view of the town with the camera
## slowly circling it, and the things a player does before playing: continue,
## start a new game, load a save, change settings, learn how to play.

const NAVY: Color = Color("0b111b")
const PANEL: Color = Color("111a27")
const LINE: Color = Color("2a3446")
const TEXT: Color = Color("e8edf4")
const TEXT_2: Color = Color("93a1b5")
const ACCENT: Color = Color("338ced")
const GOLD: Color = Color("e8c35a")

var main: Node
var root: Control
var side: PanelContainer
var body: VBoxContainer
var fade: ColorRect
var is_open: bool = false
var _cam: Dictionary = {}
var _t: float = 0.0
var _wash_grad: Gradient


func setup(p_main: Node) -> void:
	main = p_main
	layer = 20
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = main.hud.root.theme
	add_child(root)
	# a dark wash over the town so the words read, heavier on the menu's side
	var wash: TextureRect = TextureRect.new()
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gt: GradientTexture2D = GradientTexture2D.new()
	var gr: Gradient = Gradient.new()
	gr.set_color(0, Color(NAVY, 0.94))
	gr.set_color(1, Color(NAVY, 0.05))
	gr.add_point(0.45, Color(NAVY, 0.7))
	gt.gradient = gr
	_wash_grad = gr
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	wash.texture = gt
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(wash)
	side = PanelContainer.new()
	side.anchor_top = 0.0
	side.anchor_bottom = 1.0
	var sb: StyleBoxEmpty = StyleBoxEmpty.new()
	side.add_theme_stylebox_override("panel", sb)
	root.add_child(side)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	var margin: MarginContainer = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(k, 40)
	scroll.add_child(margin)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(body)
	# the footer
	var foot: Label = Label.new()
	foot.text = "Living Town  ·  early access  ·  made with Godot"
	foot.add_theme_color_override("font_color", Color(TEXT_2, 0.8))
	foot.add_theme_font_size_override("font_size", 13)
	foot.anchor_left = 1.0
	foot.anchor_right = 1.0
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.offset_left = -420
	foot.offset_right = -20
	foot.offset_top = -34
	foot.offset_bottom = -12
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(foot)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)
	get_viewport().size_changed.connect(_layout)
	_layout()
	visible = false


func _layout() -> void:
	var vis: Vector2 = get_viewport().get_visible_rect().size
	# a phone held upright: make the menu big and give it the whole width
	var k: float = clampf(vis.x / 720.0, 1.0, 3.0) if vis.y > vis.x * 1.2 else 1.0
	scale = Vector2(k, k)
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2.ZERO
	root.size = vis / k
	var vw: float = vis.x / k
	var w: float = vw if k > 1.0 else clampf(vw * 0.42, minf(vw, 360.0), 620.0)
	side.offset_left = 0
	side.offset_right = w
	body.custom_minimum_size = Vector2(w - 80.0, 0)
	# upright phones: the town shows through evenly so every line reads
	if _wash_grad != null:
		_wash_grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		_wash_grad.colors = PackedColorArray([Color(NAVY, 0.94), Color(NAVY, 0.78 if k > 1.0 else 0.7), Color(NAVY, 0.68 if k > 1.0 else 0.05)])


# ---------------------------------------------------------------- open and close

func open(first: bool) -> void:
	is_open = true
	visible = true
	main.set_speed(0)
	main.hud.root.visible = false
	var v: Node3D = main.view
	_cam = {"target": v.g_target, "yaw": v.g_yaw, "pitch": v.g_pitch, "dist": v.g_dist}
	v.g_target = _town_center()
	v.g_dist = 230.0
	v.g_pitch = -0.42
	_page_main()
	fade.color.a = 1.0 if first else 0.6
	var tw: Tween = create_tween()
	tw.tween_property(fade, "color:a", 0.0, 1.2 if first else 0.4)


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	main.hud.root.visible = true
	if not _cam.is_empty():
		var v: Node3D = main.view
		v.g_target = _cam["target"]
		v.g_yaw = float(_cam["yaw"])
		v.g_pitch = float(_cam["pitch"])
		v.g_dist = float(_cam["dist"])
	_cam = {}


## Leave the title for the town, with a short fade.
func _enter(cb: Callable) -> void:
	var tw: Tween = create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.35)
	tw.tween_callback(func():
		cb.call()
		fade.color.a = 0.0)


func _town_center() -> Vector3:
	var w: LTWorld = main.world
	var n: int = 0
	var c: Vector2 = Vector2.ZERO
	for l in w.lots:
		if not bool(l.get("removed", false)) and str(l["use"]) != "empty":
			c += Vector2((float(l["x0"]) + float(l["x1"])) * 0.5, (float(l["z0"]) + float(l["z1"])) * 0.5)
			n += 1
	if n == 0:
		return Vector3(800.0, 0.0, LTTerrain.road_z())
	c /= float(n)
	return Vector3(c.x, 0.0, c.y)


func _process(delta: float) -> void:
	if not is_open:
		return
	_t += delta
	# a slow drone's circle around the town
	main.view.g_yaw += delta * 0.045


# ---------------------------------------------------------------- pieces

func _clear() -> void:
	for c in body.get_children():
		c.queue_free()


func _label(text: String, size: int, color: Color = TEXT) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _rich(bb: String) -> RichTextLabel:
	var r: RichTextLabel = RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = bb
	r.add_theme_font_size_override("normal_font_size", 16)
	r.add_theme_font_size_override("bold_font_size", 16)
	r.add_theme_color_override("default_color", TEXT)
	return r


func _box(color: Color, border: Color, radius: int = 12) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(14)
	return s


## A big menu button: a title, and a line under it.
func _menu_btn(text: String, sub: String, cb: Callable, primary: bool = false) -> Button:
	var b: Button = Button.new()
	b.text = text if sub == "" else "%s\n%s" % [text, sub]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 64 if sub != "" else 54)
	b.add_theme_font_size_override("font_size", 22 if sub == "" else 20)
	b.add_theme_stylebox_override("normal", _box(Color(ACCENT, 0.9) if primary else Color(PANEL, 0.85), ACCENT if primary else LINE))
	b.add_theme_stylebox_override("hover", _box(Color(ACCENT, 1.0) if primary else Color("1b2a40"), ACCENT))
	b.add_theme_stylebox_override("pressed", _box(Color("1f6fc0"), ACCENT))
	b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), ACCENT))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.pressed.connect(cb)
	return b


func _back() -> Button:
	return _menu_btn("Back", "", _page_main)


func _heading(text: String) -> void:
	body.add_child(_label(text, 40, TEXT))


# ---------------------------------------------------------------- pages

func _page_main() -> void:
	_clear()
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	body.add_child(spacer)
	var t: Label = _label("LIVING TOWN", 72, TEXT)
	t.add_theme_constant_override("outline_size", 10)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	body.add_child(t)
	body.add_child(_label("Found a town. Every Sim has a life, and a reason for everything they do.", 18, TEXT_2))
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	body.add_child(gap)
	var auto: Dictionary = main.slot_info(main.AUTOSAVE_PATH)
	if not main.demo and main.world != null:
		body.add_child(_menu_btn("Continue", "%s, %s, %d people" % [main.world.city["name"], LTCalendar.short(main.world.day), main.world.residents()], func(): _enter(func(): close()), true))
	elif not auto.is_empty():
		body.add_child(_menu_btn("Continue", "%s, %s" % [auto.get("town", "your town"), auto.get("date", "")], func(): _enter(func(): main.load_game(0)), true))
	body.add_child(_menu_btn("New game", "", func(): _page_new(), main.demo and auto.is_empty()))
	body.add_child(_menu_btn("Load game", "", _page_load))
	body.add_child(_menu_btn("Settings", "", _page_settings))
	body.add_child(_menu_btn("How to play", "", _page_help))
	body.add_child(_menu_btn("Credits", "", _page_credits))
	if not (OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("web")):
		body.add_child(_menu_btn("Quit", "", func():
			if not main.demo:
				main.autosave()
			get_tree().quit()))


# ---------------------------------------------------------------- the deed

const PAPER: Color = Color("f3ead3")
const PAPER_EDGE: Color = Color("b89b6a")
const INK: Color = Color("3a2a1a")
const INK_2: Color = Color("7a6448")
const STAMP: Color = Color("b3261e")
const COUNTIES: Array = ["Prairie", "Meadow", "Buffalo", "Spirit Lake", "Wolf Creek", "Antelope", "Cedar", "Sand Hill", "Big Stone", "Pheasant"]

var deed_layer: Control
var _deed: Dictionary = {}


## A new game starts with paperwork, as owning land really does: the warranty
## deed for the prairie (or an oath of office, or a deed to a Sim lottery winner).
func _page_new() -> void:
	if _deed.is_empty():
		_deed = {"start": 0, "runner": 0, "elected": false, "lottery": 1, "calendar": true, "name": "", "pronouns": 0, "age": 38, "home": "Sioux Falls", "town": "New Hope", "seed": randi() % 999999 + 1, "mayor_seed": randi() % 999999 + 1, "doc": randi() % 90000 + 10000}
	side.visible = false
	if deed_layer != null:
		deed_layer.queue_free()
	deed_layer = Control.new()
	deed_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(deed_layer)
	root.move_child(fade, root.get_child_count() - 1)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	deed_layer.add_child(dim)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	deed_layer.add_child(scroll)
	var center: CenterContainer = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var pad: MarginContainer = MarginContainer.new()
	for k in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(k, 28)
	center.add_child(pad)
	var paper: PanelContainer = PanelContainer.new()
	var ps: StyleBoxFlat = StyleBoxFlat.new()
	ps.bg_color = PAPER
	ps.border_color = PAPER_EDGE
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(4)
	ps.shadow_color = Color(0, 0, 0, 0.5)
	ps.shadow_size = 18
	ps.content_margin_left = 56
	ps.content_margin_right = 56
	ps.content_margin_top = 40
	ps.content_margin_bottom = 40
	paper.add_theme_stylebox_override("panel", ps)
	paper.custom_minimum_size = Vector2(880, 0)
	pad.add_child(paper)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	paper.add_child(v)
	_deed_body(v)


func _ink(text: String, size: int = 18, color: Color = INK, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## A blank on the paper: a line to write on.
func _blank(text: String, width: float, on_change: Callable, placeholder: String = "") -> LineEdit:
	var e: LineEdit = LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(width, 36)
	var st: StyleBoxFlat = StyleBoxFlat.new()
	st.bg_color = Color(1, 1, 1, 0.0)
	st.border_color = INK_2
	st.border_width_bottom = 2
	st.content_margin_left = 4
	st.content_margin_right = 4
	e.add_theme_stylebox_override("normal", st)
	var fo: StyleBoxFlat = st.duplicate()
	fo.bg_color = Color(1, 1, 1, 0.35)
	fo.border_color = INK
	e.add_theme_stylebox_override("focus", fo)
	e.add_theme_color_override("font_color", Color("1d2a6b"))
	e.add_theme_color_override("font_placeholder_color", Color(INK_2, 0.6))
	e.add_theme_color_override("caret_color", INK)
	e.add_theme_font_size_override("font_size", 19)
	e.text_changed.connect(on_change)
	return e


func _paper_check(cb: CheckBox) -> void:
	var none: StyleBoxEmpty = StyleBoxEmpty.new()
	for k in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		cb.add_theme_stylebox_override(k, none)
	for k in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
		cb.add_theme_color_override(k, INK)
	cb.add_theme_color_override("checkbox_checked_color", Color("1d2a6b"))
	cb.add_theme_color_override("checkbox_unchecked_color", INK_2)


## A small button on the paper, outlined in ink.
func _paper_btn(text: String, cb: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.add_theme_stylebox_override("normal", _box(Color(1, 1, 1, 0.25), INK_2, 6))
	b.add_theme_stylebox_override("hover", _box(Color(1, 1, 1, 0.55), INK, 6))
	b.add_theme_stylebox_override("pressed", _box(Color(1, 1, 1, 0.7), INK, 6))
	b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), INK, 6))
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, INK)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(cb)
	return b


## The age written on a blank, with small arrows.
func _age_box() -> SpinBox:
	var ag: SpinBox = SpinBox.new()
	ag.min_value = 18
	ag.max_value = 99
	ag.value = int(_deed["age"])
	ag.custom_minimum_size = Vector2(90, 36)
	var le: LineEdit = ag.get_line_edit()
	var st: StyleBoxFlat = StyleBoxFlat.new()
	st.bg_color = Color(1, 1, 1, 0.0)
	st.border_color = INK_2
	st.border_width_bottom = 2
	le.add_theme_stylebox_override("normal", st)
	le.add_theme_stylebox_override("focus", st)
	le.add_theme_color_override("font_color", Color("1d2a6b"))
	le.add_theme_font_size_override("font_size", 19)
	ag.value_changed.connect(func(x): _deed["age"] = int(x))
	return ag


## Choices on the paper: boxes to check, only one marked.
func _checks(items: Array, sel: int, on_pick: Callable) -> HBoxContainer:
	var hb: HBoxContainer = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 22)
	var group: ButtonGroup = ButtonGroup.new()
	for i in items.size():
		var cb: CheckBox = CheckBox.new()
		cb.text = str(items[i])
		cb.button_group = group
		_paper_check(cb)
		cb.button_pressed = i == sel
		cb.add_theme_color_override("font_color", INK)
		cb.add_theme_color_override("font_pressed_color", INK)
		cb.add_theme_color_override("font_hover_color", Color("1d2a6b"))
		cb.add_theme_font_size_override("font_size", 17)
		var ii: int = i
		cb.toggled.connect(func(on):
			if on:
				on_pick.call(ii))
		hb.add_child(cb)
	return hb


func _row(parent: Control, parts: Array) -> HBoxContainer:
	var hb: HBoxContainer = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	for p in parts:
		if p is Label:
			(p as Label).autowrap_mode = TextServer.AUTOWRAP_OFF
		(p as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(p)
	parent.add_child(hb)
	return hb


## What the surveyor found on this parcel: the kind of country and what is on it.
func _survey(seed_v: int) -> String:
	var wt: LTWorld = LTWorld.new()
	wt.config["map_seed"] = seed_v
	LTTerrain.setup(wt, seed_v, Rect2(500, 420, 600, 360))
	var bits: Array = []
	if LTTerrain.has(wt, "mountain"):
		bits.append("mountains")
	if LTTerrain.has(wt, "forest"):
		bits.append("timber")
	var lakes: int = LTTerrain.t(wt)["lakes"].size()
	if lakes > 0:
		bits.append("%d lake%s" % [lakes, "" if lakes == 1 else "s"])
	bits.append("a railroad" if LTTerrain.has(wt, "rail") else "no railroad")
	return "%s, with %s" % [LTTerrain.kind_name(wt), LTHomes._join(bits)]


func _deed_body(v: VBoxContainer) -> void:
	var d: Dictionary = _deed
	var county: String = "%s County" % COUNTIES[int(d["seed"]) % COUNTIES.size()]
	var sim: bool = int(d["runner"]) == 1
	var classic: bool = int(d["start"]) == 1 and not sim
	var redo: Callable = func(): _page_new()
	# how this game begins
	v.add_child(_checks(["Found a new town on open prairie", "Take office in Prairie Hollow (about 100 people)"], 1 if classic else 0, func(i):
		d["start"] = i
		if i == 1:
			d["runner"] = 0
		redo.call()))
	v.add_child(_checks(["I will run it", "A Sim wins the lottery and runs it (I watch, and can take over)"], int(d["runner"]), func(i):
		d["runner"] = i
		if i == 1:
			d["start"] = 0
		redo.call()))
	v.add_child(HSeparator.new())
	if classic:
		v.add_child(_ink("OATH OF OFFICE", 34, INK, HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(_ink("Town of Prairie Hollow  ·  %s, South Dakota" % county, 15, INK_2, HORIZONTAL_ALIGNMENT_CENTER))
		_row(v, [_ink("I,"), _blank(str(d["name"]), 280, func(t): d["name"] = t, "your full name"), _ink(", age"), _age_box()])
		_row(v, [_ink("of"), _blank(str(d["home"]), 220, func(t): d["home"] = t, "hometown"), _ink("   pronouns"), _checks(["they/them", "she/her", "he/him"], int(d["pronouns"]), func(i): d["pronouns"] = i)])
		v.add_child(_ink("do solemnly swear that I will support the Constitution of the United States and of the State of South Dakota, and faithfully discharge the duties of Mayor of Prairie Hollow to the best of my ability.", 18))
	else:
		v.add_child(_ink("WARRANTY DEED", 38, INK, HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(_ink("State of South Dakota  ·  %s  ·  Register of Deeds  ·  Document No. %d" % [county, int(d["doc"])], 15, INK_2, HORIZONTAL_ALIGNMENT_CENTER))
		var money: String = ["two hundred fifty thousand dollars ($250,000)", "one million dollars ($1,000,000)", "five million dollars ($5,000,000)"][int(d["lottery"])]
		v.add_child(_ink("KNOW ALL BY THESE PRESENTS, that %s, Grantor, for and in consideration of %s in lottery winnings, paid in hand, does hereby grant, convey and warrant unto" % [county.to_upper(), money], 18))
		if sim:
			v.add_child(_ink("GRANTEE: a lottery winner drawn by mayor seed", 19))
			var rs: HBoxContainer = _row(v, [_ink("Mayor seed No."), _blank(str(d["mayor_seed"]), 160, func(t):
				if t.strip_edges().is_valid_int():
					d["mayor_seed"] = int(t.strip_edges()), "")])
			rs.add_child(_paper_btn("Draw another winner", func():
				d["mayor_seed"] = randi() % 999999 + 1
				redo.call()))
			var who: Dictionary = LTMayorAI.make_persona(int(d["mayor_seed"]))
			v.add_child(_ink("The winner: %s, %d, of %s, who is %s." % [who["name"], int(who["age"]), who["hometown"], LTMayorAI.describe(who)], 18, Color("1d2a6b")))
		else:
			_row(v, [_ink("GRANTEE:"), _blank(str(d["name"]), 300, func(t): d["name"] = t, "your full name"), _ink("age"), _age_box()])
			_row(v, [_ink("of"), _blank(str(d["home"]), 220, func(t): d["home"] = t, "hometown"), _ink("   pronouns"), _checks(["they/them", "she/her", "he/him"], int(d["pronouns"]), func(i): d["pronouns"] = i)])
		v.add_child(_ink("the following described real estate in %s:" % county, 18))
		var land: HBoxContainer = _row(v, [_ink("Parcel (map seed) No."), _blank(str(d["seed"]), 150, func(t):
			if t.strip_edges().is_valid_int():
				d["seed"] = int(t.strip_edges()), "")])
		land.add_child(_paper_btn("Survey another parcel", func():
			d["seed"] = randi() % 999999 + 1
			redo.call()))
		v.add_child(_ink("Surveyed as: %s, on County Road 12." % _survey(int(d["seed"])), 18, Color("1d2a6b")))
		_row(v, [_ink("to be platted as the Town of"), _blank(str(d["town"]), 260, func(t): d["town"] = t, "name your town")])
		v.add_child(_ink("Consideration paid:", 17, INK_2))
		v.add_child(_checks(["$250,000 (hard)", "$1,000,000", "$5,000,000 (easy)"], int(d["lottery"]), func(i):
			d["lottery"] = i
			redo.call()))
	v.add_child(HSeparator.new())
	if not sim:
		v.add_child(_ink("Terms of governance:", 17, INK_2))
		v.add_child(_checks(["Permanent mayor", "Elected mayor (two four-year terms)"], 1 if bool(d["elected"]) else 0, func(i): d["elected"] = i == 1))
	var cal: CheckBox = CheckBox.new()
	_paper_check(cal)
	cal.text = "Date this document today, and keep the town on the real calendar"
	cal.button_pressed = bool(d["calendar"])
	cal.add_theme_color_override("font_color", INK)
	cal.add_theme_color_override("font_pressed_color", INK)
	cal.toggled.connect(func(on): d["calendar"] = on)
	v.add_child(cal)
	# the signature line
	var sig_row: HBoxContainer = HBoxContainer.new()
	sig_row.add_theme_constant_override("separation", 16)
	v.add_child(sig_row)
	var sig_box: VBoxContainer = VBoxContainer.new()
	sig_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sig_row.add_child(sig_box)
	var sig: Label = _ink("", 34, Color("1d2a6b"))
	var fv: FontVariation = FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.32, 1.0), Vector2.ZERO)
	fv.variation_embolden = 0.4
	sig.add_theme_font_override("font", fv)
	sig.custom_minimum_size = Vector2(0, 48)
	sig_box.add_child(sig)
	var line: ColorRect = ColorRect.new()
	line.color = INK
	line.custom_minimum_size = Vector2(0, 2)
	sig_box.add_child(line)
	sig_box.add_child(_ink("Grantee" if not classic else "Mayor", 14, INK_2))
	var holder: Control = Control.new()
	holder.custom_minimum_size = Vector2(250, 70)
	sig_row.add_child(holder)
	var stamp_box: PanelContainer = PanelContainer.new()
	var ss: StyleBoxFlat = StyleBoxFlat.new()
	ss.bg_color = Color(0, 0, 0, 0)
	ss.border_color = STAMP
	ss.set_border_width_all(4)
	ss.set_corner_radius_all(6)
	ss.content_margin_left = 14
	ss.content_margin_right = 14
	stamp_box.add_theme_stylebox_override("panel", ss)
	stamp_box.position = Vector2(10, 6)
	stamp_box.size = Vector2(230, 58)
	stamp_box.pivot_offset = Vector2(115, 29)
	stamp_box.rotation = -0.18
	stamp_box.visible = false
	holder.add_child(stamp_box)
	var stamp: Label = _ink("", 34, STAMP, HORIZONTAL_ALIGNMENT_CENTER)
	stamp.autowrap_mode = TextServer.AUTOWRAP_OFF
	stamp_box.add_child(stamp)
	var btns: HBoxContainer = HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_END
	btns.add_theme_constant_override("separation", 12)
	v.add_child(btns)
	var back: Button = _paper_btn("Back", func():
		deed_layer.queue_free()
		deed_layer = null
		side.visible = true
		_page_main())
	back.custom_minimum_size = Vector2(120, 48)
	btns.add_child(back)
	var go: Button = Button.new()
	go.text = "Sign the deed" if not classic and not sim else ("Take the oath" if classic else "Record the deed")
	go.custom_minimum_size = Vector2(220, 48)
	go.add_theme_stylebox_override("normal", _box(Color("1d2a6b"), Color("1d2a6b"), 8))
	go.add_theme_stylebox_override("hover", _box(Color("2a3a8a"), Color("2a3a8a"), 8))
	go.add_theme_color_override("font_color", Color.WHITE)
	btns.add_child(go)
	go.pressed.connect(func():
		var nm: String = str(d["name"]).strip_edges()
		if not sim and nm == "":
			main.hud.show_toast("Write your name on the deed first.")
			return
		go.disabled = true
		back.disabled = true
		sig.text = nm if not sim else str(LTMayorAI.make_persona(int(d["mayor_seed"]))["name"])
		stamp.text = "SWORN" if classic else "RECORDED"
		stamp_box.visible = true
		stamp_box.scale = Vector2(1.7, 1.7)
		stamp_box.modulate.a = 0.0
		var tw: Tween = create_tween()
		tw.set_parallel(true)
		tw.tween_property(stamp_box, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK)
		tw.tween_property(stamp_box, "modulate:a", 0.9, 0.12)
		tw.set_parallel(false)
		tw.tween_interval(0.9)
		tw.tween_callback(func(): _enter(func(): _start_from_deed())))


func _start_from_deed() -> void:
	var d: Dictionary = _deed
	var sim: bool = int(d["runner"]) == 1
	var mode: Dictionary = {
		"start": "classic" if int(d["start"]) == 1 and not sim else "founder",
		"elections": bool(d["elected"]),
		"lottery": [LTMoney.dollars(250000.0), LTMoney.dollars(1000000.0), LTMoney.dollars(5000000.0)][int(d["lottery"])],
		"real_calendar": bool(d["calendar"]),
		"player_name": str(d["name"]).strip_edges() if str(d["name"]).strip_edges() != "" else "Sam Dakota",
		"map_seed": int(d["seed"]),
		"player_pronouns": ["they", "she", "he"][int(d["pronouns"])],
		"player_age": int(d["age"]),
		"player_hometown": str(d["home"]).strip_edges(),
		"town_name": str(d["town"]).strip_edges() if str(d["town"]).strip_edges() != "" else "New Hope",
	}
	if sim:
		mode["autonomous"] = true
		mode["mayor_seed"] = int(d["mayor_seed"])
	if deed_layer != null:
		deed_layer.queue_free()
		deed_layer = null
	side.visible = true
	_deed = {}
	main.new_town(randi() % 1000000, mode)


func _page_load() -> void:
	_clear()
	_heading("Load game")
	var any: bool = false
	var rows: Array = [[0, "Autosave", main.AUTOSAVE_PATH]]
	for n in range(1, main.SLOTS + 1):
		rows.append([n, "Slot %d" % n, main.slot_path(n)])
	for r in rows:
		var info: Dictionary = main.slot_info(str(r[2]))
		if info.is_empty():
			var empty: Button = _menu_btn("%s  ·  empty" % r[1], "", func(): pass)
			empty.disabled = true
			body.add_child(empty)
			continue
		any = true
		var n: int = int(r[0])
		var sub: String = "Saved %s" % str(info.get("saved", "")).replace("T", " ")
		if info.has("town"):
			sub = "%s  ·  %s  ·  %s people%s\n%s" % [info["town"], info.get("date", ""), str(info.get("people", "?")), "  ·  %s" % info["kind"] if info.has("kind") else "", sub]
		var go: Callable = func(): main.hud.show_toast(main.load_game(n))
		var b: Button = _menu_btn("%s" % r[1], sub, func(): _enter(go), false)
		b.custom_minimum_size = Vector2(0, 92)
		body.add_child(b)
	if not any:
		body.add_child(_label("No saved towns yet. Start a new game; it saves itself as you play, and Save in the Menu keeps a copy in a slot.", 16, TEXT_2))
	body.add_child(_back())


func _page_settings() -> void:
	_clear()
	_heading("Settings")
	var st: Dictionary = main.settings
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(Color(PANEL, 0.9), LINE))
	body.add_child(card)
	var g: VBoxContainer = VBoxContainer.new()
	g.add_theme_constant_override("separation", 16)
	card.add_child(g)
	var row: Callable = func(name: String, ctl: Control) -> void:
		var hb: HBoxContainer = HBoxContainer.new()
		hb.add_theme_constant_override("separation", 16)
		var l: Label = _label(name, 18)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.custom_minimum_size = Vector2(150, 0)
		hb.add_child(l)
		ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(ctl)
		g.add_child(hb)
	var snd: CheckButton = CheckButton.new()
	snd.flat = true
	snd.text = "On" if bool(st["sound"]) else "Off"
	snd.button_pressed = bool(st["sound"])
	snd.toggled.connect(func(on):
		snd.text = "On" if on else "Off"
		st["sound"] = on
		main.save_settings())
	row.call("Sound", snd)
	var vol: HSlider = HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = float(st["volume"])
	vol.custom_minimum_size = Vector2(180, 32)
	vol.value_changed.connect(func(v):
		st["volume"] = v
		main.save_settings())
	row.call("Volume", vol)
	var gfx: OptionButton = OptionButton.new()
	for it in ["High: sharpest, full shadows", "Balanced", "Battery saver: lighter, no shadows"]:
		gfx.add_item(it)
	gfx.selected = int(st["graphics"])
	gfx.item_selected.connect(func(i):
		st["graphics"] = i
		main.save_settings())
	row.call("Graphics", gfx)
	var stop: OptionButton = OptionButton.new()
	for it in main.STOP_LEVELS:
		stop.add_item(str(it).replace("Stop time: ", ""))
	stop.selected = int(st["stop_level"])
	stop.item_selected.connect(func(i):
		st["stop_level"] = i
		if not main.demo:
			main.world.mode["stop_level"] = i
		main.save_settings())
	row.call("Fast stops for", stop)
	var steps: CheckButton = CheckButton.new()
	steps.flat = true
	steps.text = "Shown" if bool(st["steps"]) else "Hidden"
	steps.button_pressed = bool(st["steps"])
	steps.toggled.connect(func(on):
		steps.text = "Shown" if on else "Hidden"
		st["steps"] = on
		main.save_settings())
	row.call("Next steps", steps)
	body.add_child(_label("Settings are kept on this device and apply right away.", 14, TEXT_2))
	body.add_child(_back())


func _page_help() -> void:
	_clear()
	_heading("How to play")
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(Color(PANEL, 0.9), LINE))
	body.add_child(card)
	card.add_child(_rich("""[b]You are the mayor, not a god.[/b] You cannot place businesses or hire anyone. Sims decide where to live, what to build and what to start, and every big decision goes in their history with the reason.

[b]Found the town.[/b] Draw roads off the county road; each one is a contract that builders bid on. Plot lots beside your roads and zone them. Settlers come, buy lots and build their own homes.

[b]Run it.[/b] Set taxes and laws, answer petitions, put schools, clinics and parks out to bid, and keep the budget in the black. At 25 residents the town incorporates; at 50 it elects a town board that votes on your laws.

[b]Every map is different.[/b] Open prairie, a mountain town, lake country or the north woods, with or without a railroad. Each is harder in its own way and pays back in its own way.

[b]Time.[/b] Normal, Fast and Turbo run the days; Live runs in real time; Today catches up to your own date and clock. Fast and Turbo stop for big events (change it in Settings).

[b]Look closer.[/b] Tap any home, business, Sim or road for everything about it. The Dashboard has the town's numbers, its people and every business."""))
	body.add_child(_back())


func _page_credits() -> void:
	_clear()
	_heading("Credits")
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(Color(PANEL, 0.9), LINE))
	body.add_child(card)
	card.add_child(_rich("""[b]Living Town[/b]
Designed by KeiphCodes, built with Claude.

[b]Engine[/b]
Godot Engine 4.4, made by Juan Linietsky, Ariel Manzur and contributors. godotengine.org

[b]Thanks[/b]
To the small towns of the Dakotas, whose ways this game tries to get right: the co-op elevators, the town boards, the county roads and the people who show up."""))
	body.add_child(_back())
