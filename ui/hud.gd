extends CanvasLayer
## The mayor's desk. Everything the player can do goes through main.act(), which
## goes through LTWorld.apply_action(), so every choice is logged and replayable.
## Names in any text are links: click one to open that Sim, business, lot or project.

const ChartScript = preload("res://ui/chart.gd")
const TABS: Array = ["Mayor", "Requests", "Projects", "People", "Business", "City", "News", "Help"]
const LEFT_W: int = 480
const RIGHT_W: int = 440

var main: Node
var root: Control
var top_bar: PanelContainer
var lbl_town: Label
var lbl_date: Label
var lbl_stats: Label
var speed_btns: Array = []
var left: PanelContainer
var tabs: TabContainer
var tab_boxes: Dictionary = {}
var right: PanelContainer
var inspect_text: RichTextLabel
var inspect_actions: HBoxContainer
var inspect_kind: String = ""
var inspect_id: int = -1
var feed_box: VBoxContainer
var toast: Label
var notice: PanelContainer
var notice_text: RichTextLabel
var people_filter: OptionButton
var people_search: LineEdit
var chron_filter: OptionButton
var req_sort: OptionButton
var _collapsed: bool = false
var _need_inc: Dictionary = {"free_lot": true, "tax_break_years": 2, "grant": 0, "loan_guarantee": false}
var _toast_t: float = 0.0


func setup(p_main: Node) -> void:
	main = p_main
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_build_top()
	_build_left()
	_build_right()
	_build_feed()
	# a notice card that stops time but never blocks the rest of the screen
	notice = PanelContainer.new()
	notice.anchor_left = 0.5
	notice.anchor_right = 0.5
	notice.offset_left = -270
	notice.offset_right = 270
	notice.offset_top = 60
	root.add_child(notice)
	var nv: VBoxContainer = VBoxContainer.new()
	notice.add_child(nv)
	notice_text = _rtl("")
	nv.add_child(notice_text)
	var nh: HBoxContainer = HBoxContainer.new()
	nh.alignment = BoxContainer.ALIGNMENT_END
	nh.add_child(_btn("Keep going", func():
		notice.visible = false
		main.set_speed(main.last_fast_speed)))
	nh.add_child(_btn("OK", func(): notice.visible = false))
	nv.add_child(nh)
	notice.visible = false
	_welcome()


func w() -> LTWorld:
	return main.world


# ================================================================ theme and helpers

func _make_theme() -> Theme:
	var t: Theme = Theme.new()
	var panel: StyleBoxFlat = StyleBoxFlat.new()
	panel.bg_color = Color(0.09, 0.105, 0.13, 0.93)
	panel.border_color = Color(0.25, 0.3, 0.36)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(8)
	t.set_stylebox("panel", "PanelContainer", panel)
	var btn: StyleBoxFlat = StyleBoxFlat.new()
	btn.bg_color = Color(0.2, 0.26, 0.33)
	btn.set_corner_radius_all(4)
	btn.set_content_margin_all(5)
	var btn_h: StyleBoxFlat = btn.duplicate()
	btn_h.bg_color = Color(0.28, 0.36, 0.46)
	var btn_p: StyleBoxFlat = btn.duplicate()
	btn_p.bg_color = Color(0.85, 0.65, 0.2)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", btn_h)
	t.set_stylebox("pressed", "Button", btn_p)
	t.set_color("font_color", "Label", Color(0.88, 0.9, 0.93))
	t.set_color("default_color", "RichTextLabel", Color(0.88, 0.9, 0.93))
	t.set_font_size("font_size", "Label", 15)
	t.set_font_size("font_size", "Button", 14)
	t.set_font_size("normal_font_size", "RichTextLabel", 14)
	t.set_font_size("bold_font_size", "RichTextLabel", 15)
	t.set_font_size("font_size", "TabContainer", 13)
	return t


func _btn(text: String, cb: Callable, tip: String = "") -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.pressed.connect(cb)
	return b


func _lbl(text: String, size: int = 15, color: Color = Color(0.88, 0.9, 0.93)) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	# wrap long help text only; short labels in rows stay on one line
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if text.length() > 40 else TextServer.AUTOWRAP_OFF
	return l


func _rtl(bb: String) -> RichTextLabel:
	var r: RichTextLabel = RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.selection_enabled = false
	r.text = bb
	r.meta_clicked.connect(_on_meta)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


func _sep() -> HSeparator:
	return HSeparator.new()


func _clear(box: Node) -> void:
	for ch in box.get_children():
		box.remove_child(ch)
		ch.queue_free()


func _h(text: String) -> Label:
	return _lbl(text, 17, Color(1.0, 0.85, 0.45))


func sim_link(cid: int) -> String:
	var c: Dictionary = w().cit(cid)
	if c.is_empty():
		return "nobody"
	return "[url=sim:%d]%s[/url]" % [cid, w().full_name(c)]


func biz_link(bid: int) -> String:
	var b: Dictionary = w().biz(bid)
	if b.is_empty():
		return "a business"
	return "[url=biz:%d]%s[/url]" % [bid, b["name"]]


func lot_link(lid: int) -> String:
	if lid < 0:
		return "no site"
	return "[url=lot:%d]%s[/url]" % [lid, LTGeography.lot_label(w(), lid)]


func _money(c: int) -> String:
	return LTMoney.fmt(c)


func _bar(v: float) -> String:
	var n: int = int(clampf(v, 0.0, 100.0) / 10.0)
	var col: String = "#7fd37f" if v >= 60.0 else ("#e8c15a" if v >= 35.0 else "#ef6b5b")
	return "[color=%s]%s[/color][color=#3a4048]%s[/color] %d" % [col, "|".repeat(n * 2), "|".repeat((10 - n) * 2), int(v)]


func _on_meta(meta) -> void:
	var s: String = str(meta)
	var parts: PackedStringArray = s.split(":")
	if parts.size() != 2:
		return
	var id: int = int(parts[1])
	match parts[0]:
		"sim":
			inspect("sim", id)
			main.focus_sim(id)
		"biz":
			inspect("biz", id)
			main.focus_lot(int(w().biz(id)["lot"]))
		"lot":
			inspect("lot", id)
			main.focus_lot(id)
		"proj":
			inspect("proj", id)
		"pet":
			inspect("pet", id)
		"debt":
			inspect("debt", id)


# ================================================================ layout

func _build_top() -> void:
	top_bar = PanelContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = 46
	root.add_child(top_bar)
	var hb: HBoxContainer = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	top_bar.add_child(hb)
	var tg: Button = _btn("Panels", _toggle_panels, "Show or hide the side panels")
	hb.add_child(tg)
	lbl_town = _lbl("", 18, Color(1.0, 0.85, 0.45))
	lbl_town.autowrap_mode = TextServer.AUTOWRAP_OFF
	hb.add_child(lbl_town)
	lbl_date = _lbl("", 15)
	lbl_date.autowrap_mode = TextServer.AUTOWRAP_OFF
	hb.add_child(lbl_date)
	lbl_stats = _lbl("", 14, Color(0.75, 0.8, 0.86))
	lbl_stats.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_stats.clip_text = true
	hb.add_child(lbl_stats)
	for i in main.SPEEDS.size():
		var sp: Dictionary = main.SPEEDS[i]
		var tip: String = ["Stop time to plan.", "One day in about two minutes. Watch Sims near the camera live their day.", "One day every few seconds.", "One week per step. Stops on events you care about.", "One month per step. Stops on events you care about."][i]
		var b: Button = _btn(str(sp["name"]), func(): main.set_speed(i), tip)
		b.toggle_mode = true
		speed_btns.append(b)
		hb.add_child(b)
	hb.add_child(_btn("Save", func(): show_toast(main.save_game())))
	hb.add_child(_btn("Load", func(): show_toast(main.load_game())))
	hb.add_child(_btn("New town", func(): main.new_town(randi() % 1000000)))


func _build_left() -> void:
	left = PanelContainer.new()
	left.anchor_top = 0.0
	left.anchor_bottom = 1.0
	left.offset_top = 52
	left.offset_bottom = -8
	left.offset_left = 8
	left.offset_right = 8 + LEFT_W
	root.add_child(left)
	tabs = TabContainer.new()
	left.add_child(tabs)
	for t in TABS:
		var sc: ScrollContainer = ScrollContainer.new()
		sc.name = t
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(sc)
		var vb: VBoxContainer = VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_theme_constant_override("separation", 6)
		sc.add_child(vb)
		tab_boxes[t] = vb
	tabs.tab_changed.connect(func(_i): refresh_tab())


func _build_right() -> void:
	right = PanelContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.anchor_top = 0.0
	right.anchor_bottom = 1.0
	right.offset_left = -RIGHT_W - 8
	right.offset_right = -8
	right.offset_top = 52
	right.offset_bottom = -8
	root.add_child(right)
	var vb: VBoxContainer = VBoxContainer.new()
	right.add_child(vb)
	inspect_actions = HBoxContainer.new()
	vb.add_child(inspect_actions)
	var sc: ScrollContainer = ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	inspect_text = _rtl("")
	inspect_text.custom_minimum_size = Vector2(RIGHT_W - 30, 0)
	sc.add_child(inspect_text)
	right.visible = false


func _build_feed() -> void:
	feed_box = VBoxContainer.new()
	feed_box.anchor_left = 0.0
	feed_box.anchor_right = 0.0
	feed_box.anchor_top = 1.0
	feed_box.anchor_bottom = 1.0
	feed_box.offset_left = LEFT_W + 24
	feed_box.offset_right = LEFT_W + 24 + 600
	feed_box.offset_top = -170
	feed_box.offset_bottom = -10
	feed_box.alignment = BoxContainer.ALIGNMENT_END
	feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(feed_box)
	toast = _lbl("", 15, Color(1, 0.95, 0.7))
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.offset_left = -300
	toast.offset_right = 300
	toast.offset_top = 56
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast)


func _toggle_panels() -> void:
	_collapsed = not _collapsed
	left.visible = not _collapsed
	if _collapsed:
		right.visible = false


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	# keep panels usable on narrow screens
	var vw: float = root.size.x
	if vw < LEFT_W + RIGHT_W + 200 and right.visible and left.visible:
		left.visible = false


func show_toast(text: String) -> void:
	toast.text = text
	_toast_t = 4.0
	toast.modulate.a = 1.0


func feed(events: Array) -> void:
	for e in events:
		if not bool(e["important"]):
			continue
		var r: RichTextLabel = _rtl("[bgcolor=#101418cc] %s: %s [/bgcolor]" % [LTCalendar.short(int(e["day"])), _linkify(str(e["text"]), e["refs"])])
		r.mouse_filter = Control.MOUSE_FILTER_PASS
		feed_box.add_child(r)
	while feed_box.get_child_count() > 4:
		var ch: Node = feed_box.get_child(0)
		feed_box.remove_child(ch)
		ch.queue_free()


func _linkify(text: String, refs: Array) -> String:
	var out: String = text
	for r in refs:
		var c: Dictionary = w().cit(int(r))
		if c.is_empty():
			continue
		var name: String = w().full_name(c)
		if out.contains(name) and not out.contains("sim:%d]" % int(r)):
			out = out.replace(name, sim_link(int(r)))
	return out


func show_interrupt(events: Array) -> void:
	var linked: Array = []
	for e in events.slice(0, 6):
		linked.append("[color=#9fb0c0]%s[/color]  %s" % [LTCalendar.short(int(e["day"])), _linkify(str(e["text"]), e["refs"])])
	notice_text.text = "[b]Time stopped because:[/b]\n" + "\n".join(linked)
	notice.visible = true
	refresh_top()


func _welcome() -> void:
	notice_text.text = "[b]Welcome, Mayor of %s.[/b]\nAbout %d people live here. Most drive to the next town to work and shop. There is no grocery, no school, no clinic.\nYou cannot build any of that yourself. Zone land, set laws, answer petitions, and put public projects out to bid. The people decide the rest, and every big decision they make is written in their history with the reason.\nPress [b]Normal[/b] to start time, or [b]Watch[/b] to see a single day up close. The Help tab has the controls." % [w().city["name"], w().alive_count()]
	notice.visible = true


# ================================================================ refresh

func on_new_world() -> void:
	inspect_kind = ""
	right.visible = false
	_welcome()
	_clear(feed_box)
	refresh_all()


func refresh_all() -> void:
	refresh_top()
	refresh_tab()
	if right.visible and inspect_kind != "":
		inspect(inspect_kind, inspect_id, false)


func refresh_clock() -> void:
	var h: int = int(main.hour)
	var m: int = int((main.hour - float(h)) * 60.0)
	lbl_date.text = "%s  %02d:%02d" % [LTCalendar.text(w().day), h, m]


func refresh_top() -> void:
	var ww: LTWorld = w()
	lbl_town.text = str(ww.city["name"])
	if main.speed == 1:
		refresh_clock()
	else:
		lbl_date.text = LTCalendar.text(ww.day)
	lbl_stats.text = "%s, %s  |  %d people  |  city cash %s  |  approval %d%%  |  %d businesses open" % [LTCalendar.season(ww.day), ww.weather, ww.alive_count(), _money(ww.ledger.bal("city")), int(LTCivic.approval(ww)), ww.open_businesses().size() - ww.open_businesses("landlord").size()]
	for i in speed_btns.size():
		(speed_btns[i] as Button).button_pressed = i == main.speed


func refresh_tab() -> void:
	if tabs == null:
		return
	var t: String = TABS[tabs.current_tab]
	match t:
		"Mayor":
			_tab_mayor()
		"Requests":
			_tab_requests()
		"Projects":
			_tab_projects()
		"People":
			_tab_people(false)
		"Business":
			_tab_business()
		"City":
			_tab_city()
		"News":
			_tab_chronicle()
		"Help":
			_tab_help()


# ================================================================ Mayor desk

func _tab_mayor() -> void:
	var box: VBoxContainer = tab_boxes["Mayor"]
	_clear(box)
	var ww: LTWorld = w()
	box.add_child(_h("Budget"))
	var last: Dictionary = ww.city["budget_months"][ww.city["budget_months"].size() - 1] if not ww.city["budget_months"].is_empty() else {}
	var bb: String = "City cash [b]%s[/b]. Last 12 months: income %s, spending %s. Credit standing [b]%s[/b].\n" % [_money(ww.ledger.bal("city")), _money(int(ww.city["income_12m"])), _money(int(ww.city["spend_12m"])), LTFinance.city_credit_rating(ww)]
	if not last.is_empty():
		bb += "[color=#9fb0c0]Last month in:[/color] "
		var parts: Array = []
		for k in last["income"]:
			parts.append("%s %s" % [str(k).replace("_", " "), _money(int(last["income"][k]))])
		bb += ", ".join(parts) + "\n[color=#9fb0c0]Last month out:[/color] "
		parts = []
		for k in last["spend"]:
			parts.append("%s %s" % [str(k).replace("_", " "), _money(int(last["spend"][k]))])
		bb += ", ".join(parts)
	var cdebt: Array = LTFinance.debts_of(ww, "city", 0)
	if not cdebt.is_empty():
		var owed: int = 0
		var pay: int = 0
		for d in cdebt:
			owed += int(d["balance"])
			pay += int(d["payment"])
		bb += "\nCity debt: %s owed, %s a month in payments." % [_money(owed), _money(pay)]
	box.add_child(_rtl(bb))
	var borrow: HBoxContainer = HBoxContainer.new()
	var amt: SpinBox = SpinBox.new()
	amt.min_value = 10000
	amt.max_value = 1000000
	amt.step = 10000
	amt.value = 100000
	amt.prefix = "$"
	borrow.add_child(_lbl("Borrow"))
	borrow.add_child(amt)
	borrow.add_child(_btn("Borrow from the bank", func(): show_toast(str(main.act({"kind": "city_borrow", "amount": int(amt.value) * 100, "purpose": "city needs"})["message"]))))
	box.add_child(borrow)
	box.add_child(_sep())
	box.add_child(_h("Laws"))
	box.add_child(_lbl("A law changes the numbers Sims and businesses decide with. It never sets an outcome. Each change shows an estimate first, and the City tab tracks what really happened.", 13, Color(0.7, 0.75, 0.8)))
	for key in LTCivic.LAWS:
		box.add_child(_law_row(key))
	box.add_child(_sep())
	box.add_child(_h("Publish a city need"))
	box.add_child(_lbl("Say what the town needs and offer help. A Sim still decides whether to take it, and the one who does may not be good at it.", 13, Color(0.7, 0.75, 0.8)))
	var need_opt: OptionButton = OptionButton.new()
	for k in ["grocery", "cafe", "general_store", "farm", "construction"]:
		need_opt.add_item(str(LTEconomy.TYPES[k]["display"]))
		need_opt.set_item_metadata(need_opt.item_count - 1, k)
	box.add_child(need_opt)
	var lot_opt: OptionButton = OptionButton.new()
	lot_opt.add_item("Best fitting empty lot")
	lot_opt.set_item_metadata(0, -1)
	for l in ww.lots:
		if str(l["use"]) == "empty":
			lot_opt.add_item("Lot %d (%s, %s)" % [l["id"], LTGeography.lot_street(ww, int(l["id"]))["name"], l["zone"]])
			lot_opt.set_item_metadata(lot_opt.item_count - 1, int(l["id"]))
	box.add_child(lot_opt)
	box.add_child(_incentive_editor())
	box.add_child(_btn("Publish this need", func():
		var r: Dictionary = main.act({"kind": "publish_need", "need": need_opt.get_item_metadata(need_opt.selected), "lot": int(lot_opt.get_item_metadata(lot_opt.selected)), "incentives": _need_inc.duplicate()})
		show_toast(str(r["message"]))))
	var open_needs: Array = []
	for n in ww.city_needs:
		var tb: String = ""
		if int(n["taken_by"]) >= 0:
			tb = ", taken by %s" % biz_link(int(n["taken_by"]))
		open_needs.append("%s on %s: %s%s" % [str(LTEconomy.TYPES[n["need"]]["display"]), lot_link(int(n["lot"])), n["status"], tb])
	if not open_needs.is_empty():
		box.add_child(_rtl("[b]Published needs[/b]\n" + "\n".join(open_needs)))


func _incentive_editor() -> VBoxContainer:
	var vb: VBoxContainer = VBoxContainer.new()
	var fl: CheckBox = CheckBox.new()
	fl.text = "Free lot (no lease payments)"
	fl.button_pressed = bool(_need_inc["free_lot"])
	fl.toggled.connect(func(v): _need_inc["free_lot"] = v)
	vb.add_child(fl)
	var hb: HBoxContainer = HBoxContainer.new()
	hb.add_child(_lbl("Years with no business tax"))
	var tb: SpinBox = SpinBox.new()
	tb.min_value = 0
	tb.max_value = 10
	tb.value = int(_need_inc["tax_break_years"])
	tb.value_changed.connect(func(v): _need_inc["tax_break_years"] = int(v))
	hb.add_child(tb)
	vb.add_child(hb)
	var hb2: HBoxContainer = HBoxContainer.new()
	hb2.add_child(_lbl("Start up grant"))
	var gr: SpinBox = SpinBox.new()
	gr.min_value = 0
	gr.max_value = 50000
	gr.step = 1000
	gr.prefix = "$"
	gr.value = int(_need_inc["grant"]) / 100
	gr.value_changed.connect(func(v): _need_inc["grant"] = int(v) * 100)
	hb2.add_child(gr)
	vb.add_child(hb2)
	var lg: CheckBox = CheckBox.new()
	lg.text = "City guarantees the bank loan (the city pays if it fails)"
	lg.button_pressed = bool(_need_inc["loan_guarantee"])
	lg.toggled.connect(func(v): _need_inc["loan_guarantee"] = v)
	vb.add_child(lg)
	return vb


func _law_row(key: String) -> VBoxContainer:
	var ww: LTWorld = w()
	var cfg: Dictionary = LTCivic.LAWS[key]
	var vb: VBoxContainer = VBoxContainer.new()
	var cur: float = float(ww.city["laws"][key])
	var hb: HBoxContainer = HBoxContainer.new()
	var name_l: Label = _lbl("%s: %s" % [cfg["label"], LTCivic.law_text(key, cur)], 14)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(name_l)
	vb.add_child(hb)
	var hb2: HBoxContainer = HBoxContainer.new()
	var sl: HSlider = HSlider.new()
	sl.min_value = float(cfg["min"])
	sl.max_value = float(cfg["max"])
	sl.step = float(cfg["step"])
	sl.value = cur
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size = Vector2(200, 0)
	var val_l: Label = _lbl(LTCivic.law_text(key, cur), 14, Color(1, 0.9, 0.6))
	val_l.custom_minimum_size = Vector2(70, 0)
	var est_l: RichTextLabel = _rtl("")
	var pass_b: Button = _btn("Pass", func():
		var r: Dictionary = main.act({"kind": "set_law", "law": key, "value": sl.value})
		show_toast(str(r["message"]).substr(0, 160)))
	pass_b.disabled = true
	sl.value_changed.connect(func(v):
		val_l.text = LTCivic.law_text(key, v)
		var changed: bool = not is_equal_approx(v, float(w().city["laws"][key]))
		pass_b.disabled = not changed
		if changed:
			var e: Dictionary = LTCivic.law_estimate(w(), key, v)
			est_l.text = "[color=#c8d3a0]Estimate if passed:[/color] %s" % e["hits"]
		else:
			est_l.text = "")
	hb2.add_child(sl)
	hb2.add_child(val_l)
	hb2.add_child(pass_b)
	vb.add_child(hb2)
	vb.add_child(est_l)
	return vb


# ================================================================ Requests inbox

func _tab_requests() -> void:
	var box: VBoxContainer = tab_boxes["Requests"]
	_clear(box)
	var ww: LTWorld = w()
	box.add_child(_h("Requests from citizens"))
	box.add_child(_lbl("Petitions come from real needs Sims feel. They gather signatures over time. Answer them here.", 13, Color(0.7, 0.75, 0.8)))
	var sort: OptionButton = OptionButton.new()
	for s in ["Sort by need strength", "Sort by signatures", "Sort by cost", "Newest first"]:
		sort.add_item(s)
	if req_sort != null:
		sort.selected = req_sort.selected
	req_sort = sort
	sort.item_selected.connect(func(_i): _tab_requests())
	box.add_child(sort)
	var list: Array = ww.petitions.duplicate()
	match sort.selected:
		0:
			list.sort_custom(func(a, b): return float(a["strength"]) > float(b["strength"]))
		1:
			list.sort_custom(func(a, b): return a["signers"].size() > b["signers"].size())
		2:
			list.sort_custom(func(a, b): return LTCivic.petition_cost_estimate(ww, a) < LTCivic.petition_cost_estimate(ww, b))
		3:
			list.sort_custom(func(a, b): return int(a["created_day"]) > int(b["created_day"]))
	var open_first: Array = []
	var rest: Array = []
	for p in list:
		if ["gathering", "submitted"].has(str(p["status"])):
			open_first.append(p)
		else:
			rest.append(p)
	if open_first.is_empty():
		box.add_child(_lbl("No open petitions right now.", 14))
	for p in open_first:
		box.add_child(_petition_card(p, true))
	if not rest.is_empty():
		box.add_child(_sep())
		box.add_child(_h("Answered"))
		for p in rest:
			box.add_child(_petition_card(p, false))


func _petition_card(p: Dictionary, actions: bool) -> VBoxContainer:
	var ww: LTWorld = w()
	var vb: VBoxContainer = VBoxContainer.new()
	var ready: bool = str(p["status"]) == "submitted"
	var t: String = "[b][url=pet:%d]%s[/url][/b]  [color=#9fb0c0](%s, %d of %d signatures needed%s)[/color]\n" % [p["id"], p["title"], p["status"], p["signers"].size(), p["threshold"], ", ready for you" if ready else ""]
	t += "%s\nStarted by %s on %s. Suggested site: %s. Rough cost: %s." % [p["why"], sim_link(int(p["starter"])), LTCalendar.short(int(p["created_day"])), lot_link(int(p["site"])) if str(p["kind"]) != "road" else str(p["site_text"]), _money(LTCivic.petition_cost_estimate(ww, p))]
	for o in p["offers"]:
		t += "\nOffer: " + str(o["text"])
	for o in p["outcome"]:
		t += "\n[color=#b8c8a0]%s[/color]" % o
	vb.add_child(_rtl(t))
	if actions:
		var hb: HFlowContainer = HFlowContainer.new()
		var pid: int = int(p["id"])
		hb.add_child(_btn("Approve as asked", func(): _answer(pid, "approve", {})))
		if str(p["kind"]) != "road":
			var alt: OptionButton = OptionButton.new()
			alt.add_item("Different site...")
			alt.set_item_metadata(0, -1)
			for l in ww.lots:
				if str(l["use"]) == "empty" and int(l["id"]) != int(p["site"]):
					alt.add_item("Lot %d (%s)" % [l["id"], l["zone"]])
					alt.set_item_metadata(alt.item_count - 1, int(l["id"]))
			alt.item_selected.connect(func(i):
				var lid: int = int(alt.get_item_metadata(i))
				if lid >= 0:
					_answer(pid, "approve_moved", {"lot": lid}))
			hb.add_child(alt)
		hb.add_child(_btn("Approve smaller", func(): _answer(pid, "approve_smaller", {})))
		if not ["school", "clinic", "park", "road"].has(str(p["kind"])):
			var need: String = "grocery" if str(p["kind"]) == "grocery" else "general_store"
			hb.add_child(_btn("Publish need with incentives", func(): _answer(pid, "publish_need", {"need": need, "incentives": _need_inc.duplicate()}), "Uses the incentives set on the Mayor tab"))
		var deny: OptionButton = OptionButton.new()
		deny.add_item("Deny because...")
		for r in LTCivic.DENY_REASONS:
			deny.add_item(r)
		deny.item_selected.connect(func(i):
			if i > 0:
				_answer(pid, "deny", {"reason": LTCivic.DENY_REASONS[i - 1]}))
		hb.add_child(deny)
		vb.add_child(hb)
	vb.add_child(_sep())
	return vb


func _answer(pid: int, response: String, extra: Dictionary) -> void:
	var a: Dictionary = {"kind": "respond_petition", "petition_id": pid, "response": response}
	for k in extra:
		a[k] = extra[k]
	var r: Dictionary = main.act(a)
	show_toast(str(r["message"]).substr(0, 200))


# ================================================================ Projects and bids

func _tab_projects() -> void:
	var box: VBoxContainer = tab_boxes["Projects"]
	_clear(box)
	var ww: LTWorld = w()
	box.add_child(_h("Public projects"))
	box.add_child(_lbl("The city never builds. Define a project and a budget ceiling, put it out to bid, then pick a contractor. Cheapest is a choice, not the default.", 13, Color(0.7, 0.75, 0.8)))
	var types: OptionButton = OptionButton.new()
	var tlist: Array = ["road_repair", "road_patch", "school", "school_small", "clinic", "clinic_small", "park"]
	for t in tlist:
		types.add_item("%s (about %s)" % [str(LTProjects.TITLES[t]).replace(" %s", "").replace("%s", "a street"), _money(int(LTProjects.BASE_COST[t]))])
	box.add_child(types)
	var tgt: OptionButton = OptionButton.new()
	var fill_targets: Callable = func():
		tgt.clear()
		var pt: String = tlist[types.selected]
		if LTProjects.is_road(pt):
			for st in ww.streets:
				tgt.add_item("%s (condition %d)" % [st["name"], int(LTGeography.street_condition(ww, int(st["id"])))])
				tgt.set_item_metadata(tgt.item_count - 1, int(st["id"]))
		else:
			for l in ww.lots:
				if str(l["use"]) == "empty" and ["civic", "mixed", "park"].has(str(l["zone"])):
					tgt.add_item("Lot %d (%s, %s)" % [l["id"], LTGeography.lot_street(ww, int(l["id"]))["name"], l["zone"]])
					tgt.set_item_metadata(tgt.item_count - 1, int(l["id"]))
			if tgt.item_count == 0:
				tgt.add_item("No empty civic lot. Rezone one first.")
				tgt.set_item_metadata(0, -1)
	fill_targets.call()
	types.item_selected.connect(func(_i): fill_targets.call())
	box.add_child(tgt)
	var hb: HBoxContainer = HBoxContainer.new()
	hb.add_child(_lbl("Budget ceiling"))
	var ceil_s: SpinBox = SpinBox.new()
	ceil_s.min_value = 0
	ceil_s.max_value = 2000000
	ceil_s.step = 5000
	ceil_s.prefix = "$"
	ceil_s.value = 0
	ceil_s.tooltip_text = "0 means about 45% over the typical cost"
	hb.add_child(ceil_s)
	box.add_child(hb)
	box.add_child(_btn("Put out to bid", func():
		var r: Dictionary = main.act({"kind": "define_project", "ptype": tlist[types.selected], "target": int(tgt.get_item_metadata(tgt.selected)) if tgt.item_count > 0 else -1, "ceiling": int(ceil_s.value) * 100})
		show_toast(str(r["message"]))))
	box.add_child(_sep())
	var plist: Array = ww.projects.duplicate()
	plist.reverse()
	for p in plist:
		box.add_child(_project_card(p))


func _project_card(p: Dictionary) -> VBoxContainer:
	var ww: LTWorld = w()
	var vb: VBoxContainer = VBoxContainer.new()
	var t: String = "[b][url=proj:%d]%s[/url][/b]  [color=#9fb0c0]%s%s[/color]" % [p["id"], p["title"], p["status"], ", private" if bool(p["private"]) else ""]
	t += "\nCeiling %s. %s" % [_money(int(p["ceiling"])), "Bids close " + LTCalendar.short(int(p["bid_close_day"])) if str(p["status"]) == "bidding" else ""]
	match str(p["status"]):
		"building":
			t += "\nBuilt by %s for %s. Stage: %s, %d%% done. Promised %d days, started %s." % [p["winner_name"], _money(int(p["price"]) + int(p["change_orders"])), p["stage"], int(float(p["progress"]) * 100.0), p["days_promised"], LTCalendar.short(int(p["start_day"]))]
		"done":
			t += "\nBuilt by %s. Quality %d of 100. Finished %s. %s" % [p["winner_name"], int(float(p["quality"]) * 100.0), LTCalendar.short(int(p["done_day"])), ("Expected to need repair in about %d days." % int(p.get("expected_repair_days", 0))) if LTProjects.is_road(str(p["ptype"])) else ""]
	vb.add_child(_rtl(t))
	if str(p["status"]) == "review" and not bool(p["private"]):
		var grid: GridContainer = GridContainer.new()
		grid.columns = 1
		for i in p["bids"].size():
			var b: Dictionary = p["bids"][i]
			var row: VBoxContainer = VBoxContainer.new()
			var over: bool = int(b["price"]) > int(p["ceiling"])
			row.add_child(_rtl("[b]%s[/b]%s  %s, %d days, crew %d, warranty %d years. Past quality grade [b]%s[/b]. Record: %s.\n[color=#9fb0c0]%s[/color]%s" % [b["name"], " (local)" if bool(b["local"]) else "", _money(int(b["price"])), b["days"], b["crew"], b["warranty_years"], b["grade"], b["record"], b["money_note"], "\n[color=#ef6b5b]Over the ceiling.[/color]" if over else ""]))
			var pid: int = int(p["id"])
			var bi: int = i
			var aw: Button = _btn("Award to %s" % b["name"], func():
				var r: Dictionary = main.act({"kind": "award_bid", "project_id": pid, "bid_index": bi})
				show_toast(str(r["message"])))
			aw.disabled = over
			row.add_child(aw)
			grid.add_child(row)
		vb.add_child(grid)
		var pid2: int = int(p["id"])
		vb.add_child(_btn("Cancel project", func(): show_toast(str(main.act({"kind": "cancel_project", "project_id": pid2})["message"]))))
	vb.add_child(_sep())
	return vb


# ================================================================ People and businesses

func _tab_people(keep: bool) -> void:
	var box: VBoxContainer = tab_boxes["People"]
	var ww: LTWorld = w()
	if people_filter == null or not is_instance_valid(people_filter):
		_clear(box)
		box.add_child(_h("People"))
		people_search = LineEdit.new()
		people_search.placeholder_text = "Search by name"
		people_search.text_changed.connect(func(_t): _people_list())
		box.add_child(people_search)
		people_filter = OptionButton.new()
		for f in ["Everyone in town", "Watched", "Out of work", "Behind on debts", "Business owners", "Children and teens", "Seniors", "Gone (died or moved away)"]:
			people_filter.add_item(f)
		people_filter.item_selected.connect(func(_i): _people_list())
		box.add_child(people_filter)
		var list_box: VBoxContainer = VBoxContainer.new()
		list_box.name = "List"
		box.add_child(list_box)
	_people_list()


func _people_list() -> void:
	var box: VBoxContainer = tab_boxes["People"]
	var list_box: VBoxContainer = box.get_node_or_null("List")
	if list_box == null:
		return
	_clear(list_box)
	var ww: LTWorld = w()
	var q: String = people_search.text.to_lower()
	var f: int = people_filter.selected
	var lines: Array = []
	for c in ww.citizens:
		var present: bool = ww.is_present(c)
		if f == 7:
			if present:
				continue
		elif not present:
			continue
		if q != "" and not ww.full_name(c).to_lower().contains(q):
			continue
		var age: int = ww.age_years(c)
		match f:
			1:
				if not ww.watch_list.has(int(c["id"])):
					continue
			2:
				if age < 18 or bool(c["retired"]) or str(c["job"]["kind"]) != "none":
					continue
			3:
				var behind: bool = false
				for d in LTFinance.personal_exposure(ww, c):
					if str(d["status"]) != "current" and str(d["status"]) != "assumed":
						behind = true
				if not behind:
					continue
			4:
				if c["owns"].is_empty():
					continue
			5:
				if age >= 18:
					continue
			6:
				if age < 65:
					continue
		var job: String = str(c["job"]["title"]) if str(c["job"]["kind"]) != "none" else ("retired" if bool(c["retired"]) else ("student" if age < 18 else "no job"))
		lines.append("%s%s, %d, %s. %s" % ["[color=#ffd75a]*[/color] " if ww.watch_list.has(int(c["id"])) else "", sim_link(int(c["id"])), age, job, "" if present else ("died" if not bool(c["alive"]) else "moved away")])
		if lines.size() >= 300:
			break
	list_box.add_child(_rtl("%d shown\n" % lines.size() + "\n".join(lines)))


func _tab_business() -> void:
	var box: VBoxContainer = tab_boxes["Business"]
	_clear(box)
	var ww: LTWorld = w()
	box.add_child(_h("Businesses"))
	box.add_child(_lbl("Every business here was started by a Sim. You cannot place, run or close one.", 13, Color(0.7, 0.75, 0.8)))
	var lines: Array = []
	for b in ww.businesses:
		if str(b["status"]) == "never_opened":
			continue
		var owner: Dictionary = ww.cit(int(b["owners"][0]))
		var st: String = "open" if str(b["status"]) == "open" else "closed %s" % LTCalendar.short(int(b["closed_day"]))
		var profit: String = ""
		var ph: Array = b["month_profit_hist"]
		if not ph.is_empty():
			profit = ", last month %s" % _money(int(ph[ph.size() - 1]))
		lines.append("%s (%s), %s. Owner %s. Staff %d%s." % [biz_link(int(b["id"])), str(LTEconomy.TYPES[b["type"]]["display"]).to_lower(), st, sim_link(int(owner.get("id", -1))), b["staff"].size(), profit])
	box.add_child(_rtl("\n".join(lines) if not lines.is_empty() else "No businesses yet."))
	box.add_child(_sep())
	box.add_child(_h("Contractors"))
	var cl: Array = []
	for co in ww.companies:
		cl.append("%s (outside): grade %s, %s jobs, %d overruns, %d late, %d defects." % [co["name"], LTProjects._grade(LTProjects._avg(co["quality_hist"])), co["jobs"], co["overruns"], co["late"], co["defects"]])
	box.add_child(_rtl("\n".join(cl)))
	box.add_child(_sep())
	box.add_child(_h("Bank"))
	box.add_child(_rtl("%s. Lending tightness %d%%. Losses in the last year about %s. %s" % [LTFinance.BANK_NAME, int(float(ww.bank["tightness"]) * 100.0), _money(int(ww.bank["losses_12m"])), ww.bank["note"]]))


# ================================================================ City dashboard

func _tab_city() -> void:
	var box: VBoxContainer = tab_boxes["City"]
	_clear(box)
	var ww: LTWorld = w()
	var s: Dictionary = ww.snapshot()
	var c: Dictionary = ww.counters
	box.add_child(_h("City dashboard"))
	box.add_child(_rtl("Population [b]%d[/b]. Births %d, deaths %d, moved in %d, moved out %d.\nWorking age adults %d, employed %d (%d in town), unemployment [b]%d%%[/b]. Average day's pay %s.\nBusinesses opened %d, closed %d. Bankruptcies %d. Evictions %d. Homeless now %d. Thefts %d.\nHappiness %d, approval %d. Safety %d.\nServices: %s." % [s["population"], c["births"], c["deaths"], c["moved_in"], c["moved_out"], s["adults"], s["employed"], s["local_jobs"], int(float(s["unemployment"]) * 100.0), _money(int(s["avg_daily_wage"])), c["businesses_opened"], c["businesses_closed"], c["bankruptcies"], c["evictions"], s["homeless"], c["thefts"], int(s["happiness"]), int(s["approval"]), int(LTCivic.safety_level(ww)), _services_text()]))
	var hist: Array = ww.stats_history
	var series: Array = [
		["Population", "population", Color(0.45, 0.75, 1.0), func(v): return str(int(v))],
		["Unemployment", "unemployment", Color(1.0, 0.55, 0.4), func(v): return "%d%%" % int(float(v) * 100.0)],
		["City cash", "city_cash", Color(0.5, 0.9, 0.5), func(v): return LTMoney.fmt(int(v))],
		["Happiness", "happiness", Color(1.0, 0.85, 0.4), func(v): return str(int(v))],
		["Businesses open", "businesses_open", Color(0.8, 0.6, 1.0), func(v): return str(int(v))],
	]
	for se in series:
		var ch: Control = ChartScript.new()
		ch.custom_minimum_size = Vector2(LEFT_W - 40, 84)
		var vals: Array = []
		for h in hist:
			vals.append(h[se[1]])
		ch.set_data(se[0], vals, se[2], se[3])
		box.add_child(ch)
	box.add_child(_h("Happiness by street"))
	var rows: Dictionary = {}
	for cc in ww.citizens:
		if not ww.is_present(cc):
			continue
		var hl: int = int(ww.hh(int(cc["household"]))["lot"])
		var key: String = "No home" if hl < 0 else str(LTGeography.lot_street(ww, hl)["name"])
		if not rows.has(key):
			rows[key] = [0.0, 0]
		rows[key][0] += LTPeople.happiness(cc)
		rows[key][1] += 1
	var rl: Array = []
	for k in rows:
		rl.append("%s: %s (%d people)" % [k, _bar(float(rows[k][0]) / float(rows[k][1])), rows[k][1]])
	box.add_child(_rtl("\n".join(rl)))
	box.add_child(_h("Laws passed: estimate against what happened"))
	if ww.laws_log.is_empty():
		box.add_child(_lbl("No laws changed yet.", 14))
	for e in ww.laws_log:
		var tr: String = "\n".join(e["tracked"]) if not e["tracked"].is_empty() else "Tracking starts after a month."
		box.add_child(_rtl("[b]%s[/b] on %s: %s to %s.\n[color=#c8d3a0]Estimate:[/color] %s\n[color=#a8c8e8]Tracked:[/color] %s" % [e["label"], LTCalendar.short(int(e["day"])), LTCivic.law_text(str(e["law"]), float(e["old"])), LTCivic.law_text(str(e["law"]), float(e["new"])), e["estimate"]["hits"], tr]))
	box.add_child(_h("Roads"))
	var rd: Array = []
	for st in ww.streets:
		rd.append("%s: %s" % [st["name"], _bar(LTGeography.street_condition(ww, int(st["id"])))])
	box.add_child(_rtl("\n".join(rd)))


func _services_text() -> String:
	var ww: LTWorld = w()
	var out: Array = []
	for s in ww.city["services"]:
		out.append("%s (quality %d)" % [s["kind"], int(float(s["quality"]) * 100.0)])
	return "none yet. Kids ride a bus to the county school and the nearest clinic is the county medical center" if out.is_empty() else ", ".join(out)


func _tab_chronicle() -> void:
	var box: VBoxContainer = tab_boxes["News"]
	_clear(box)
	var ww: LTWorld = w()
	box.add_child(_h("Town chronicle"))
	var f: OptionButton = OptionButton.new()
	var kinds: Array = ["all", "business", "debt", "bankruptcy", "estate", "death", "birth", "family", "move", "petition", "project", "city", "law", "housing", "work", "crime", "protest"]
	for k in kinds:
		f.add_item(k)
	if chron_filter != null:
		f.selected = chron_filter.selected
	chron_filter = f
	f.item_selected.connect(func(_i): _tab_chronicle())
	box.add_child(f)
	var lines: Array = []
	var want: String = kinds[f.selected]
	for i in range(ww.chronicle.size() - 1, -1, -1):
		var e: Dictionary = ww.chronicle[i]
		if want != "all" and str(e["kind"]) != want:
			continue
		lines.append("[color=#9fb0c0]%s[/color]  %s" % [LTCalendar.short(int(e["day"])), _linkify(str(e["text"]), e["refs"])])
		if lines.size() >= 250:
			break
	box.add_child(_rtl("\n".join(lines)))


func _tab_help() -> void:
	var box: VBoxContainer = tab_boxes["Help"]
	_clear(box)
	box.add_child(_h("How to play"))
	box.add_child(_rtl("""You are the mayor of [b]%s[/b]. You do not build the town. The people do.

[b]What you can do[/b]
Zone empty lots (click a lot). Pass laws and set taxes on the Mayor tab. Publish a city need with incentives. Answer petitions on the Requests tab. Put public projects out to bid and award them on the Projects tab. Borrow money for the city. Watch anyone.

[b]What you cannot do[/b]
Place a business, hire or fire anyone, set a shop price, or force anyone to stay. Sims decide all of that, and every big decision is written in their history with the reason.

[b]Time[/b]
Pause to plan. Watch shows one day in about two minutes, and Sims near the camera walk, drive and work their real day. Normal runs a day every few seconds. Fast and Turbo jump a week or a month and stop when something important happens. Every speed runs the full daily simulation.

[b]Camera[/b]
Right drag to turn, middle drag or Shift and left drag to move, wheel to zoom. W A S D or the arrow keys move, Q and E turn. On a touch screen drag with one finger, pinch with two.

[b]Reading the town[/b]
A lit shop with crates in the window is doing fine. A dim one with a SALE sign is struggling. Boards over the windows mean it closed. Roads turn brown as they wear. Construction sites rise in stages. Clothes show work: blue commutes out of town, green works in a local shop, red owns one, navy works for the city, gold marks someone you are watching.

[b]Money is real[/b]
Every dollar moves between accounts. Nothing is created by a sale or deleted by a closure. Debts carry interest, late payments climb a ladder, and a Sim may file for bankruptcy when their own math says they cannot pay. When someone dies, the estate pays their debts in legal order. Children do not inherit debt.""" % w().city["name"]))


# ================================================================ Inspect panel

func inspect(kind: String, id: int, show: bool = true) -> void:
	inspect_kind = kind
	inspect_id = id
	if show:
		right.visible = true
	_clear(inspect_actions)
	var t: String = ""
	match kind:
		"sim":
			t = _sim_text(id)
			var c: Dictionary = w().cit(id)
			inspect_actions.add_child(_btn("Stop watching" if w().watch_list.has(id) else "Watch", func():
				main.act({"kind": "watch", "citizen_id": id})
				inspect("sim", id)))
			inspect_actions.add_child(_btn("Find", func(): main.focus_sim(id)))
		"biz":
			t = _biz_text(id)
			inspect_actions.add_child(_btn("Find", func(): main.focus_lot(int(w().biz(id)["lot"]))))
		"lot":
			t = _lot_text(id)
			main.view.select_lot(id)
			var l: Dictionary = w().lot(id)
			if ["empty", "closed"].has(str(l["use"])):
				var z: OptionButton = OptionButton.new()
				z.add_item("Rezone...")
				for zone in LTGeography.ZONES:
					if zone != str(l["zone"]):
						z.add_item(zone)
				z.item_selected.connect(func(i):
					if i > 0:
						var r: Dictionary = main.act({"kind": "zone_lot", "lot": id, "zone": z.get_item_text(i)})
						show_toast(str(r["message"]))
						inspect("lot", id))
				inspect_actions.add_child(z)
		"proj":
			t = _proj_text(id)
		"pet":
			t = _pet_text(id)
		"debt":
			t = _debt_text(id)
	inspect_actions.add_child(_btn("Close", func():
		right.visible = false
		main.view.select_lot(-1)))
	inspect_text.text = t


func _sim_text(id: int) -> String:
	var ww: LTWorld = w()
	var c: Dictionary = ww.cit(id)
	if c.is_empty():
		return "Nobody."
	var age: int = ww.age_years(c)
	var h: Dictionary = ww.hh(int(c["household"]))
	var t: String = "[font_size=19][b]%s[/b][/font_size]\n" % ww.full_name(c)
	var status: String = "alive"
	if not bool(c["alive"]):
		status = "died %s of %s" % [LTCalendar.short(int(c["death_day"])), c["death_cause"]]
	elif bool(c["left_town"]):
		status = "moved away"
	var arch: String = LTPeople.archetype(c)
	t += "%d, %s, %s. %s.\n%s\n" % [age, LTPeople.life_stage(ww, c).to_lower(), "woman" if str(c["sex"]) == "F" else "man", status.capitalize(), "Nothing unusual in their personality." if arch == "ordinary" else "Their personality reads like a %s." % arch]
	var home: String = "no home" if int(h["lot"]) < 0 else "%s at %s" % ["owns a home" if str(h["tenure"]) == "own" else "rents", lot_link(int(h["lot"]))]
	t += "Home: %s. Household of %d.\n" % [home, ww.household_members(h).size()]
	var job: Dictionary = c["job"]
	var jt: String = "no job"
	match str(job["kind"]):
		"outside":
			jt = "%s outside town, %s a day, drives to the next town" % [job["title"], _money(int(job["daily_wage"]))]
		"business":
			jt = "%s at %s, %s a day" % [job["title"], biz_link(int(job["employer"])), _money(int(job["daily_wage"]))]
		"owner":
			jt = "owns and runs %s" % biz_link(int(job["employer"]))
		"city":
			jt = "%s for the city, %s a day" % [job["title"], _money(int(job["daily_wage"]))]
	if age < 18:
		jt = "student at the %s" % c["student"] if str(c["student"]) != "none" else "too young for school"
		if str(c["student"]) == "dropout":
			jt = "dropped out of school"
	elif bool(c["retired"]):
		jt = "retired"
	elif str(job["kind"]) == "none":
		jt += ", looking for %d days" % int(c["days_unemployed"])
	t += "Work: %s.\n" % jt
	if age >= 18:
		t += "Education %d.\n" % int(c["education"])
	else:
		t += "Education so far %d.\n" % int(c["education"])
	# family
	var fam: Array = []
	if int(c["spouse"]) >= 0:
		fam.append("spouse " + sim_link(int(c["spouse"])))
	for k in c["rel"]:
		var r: Dictionary = c["rel"][k]
		if str(r["kind"]) == "child":
			fam.append("child " + sim_link(int(k)))
		elif str(r["kind"]) == "parent":
			fam.append("parent " + sim_link(int(k)))
	if not fam.is_empty():
		t += "Family: %s.\n" % ", ".join(fam)
	var friends: Array = []
	for k in c["rel"]:
		var r2: Dictionary = c["rel"][k]
		if ["friend", "neighbor", "coworker", "employer", "employee", "acquaintance"].has(str(r2["kind"])):
			friends.append("%s (%s, trust %d)" % [sim_link(int(k)), r2["kind"], int(r2["trust"])])
	if not friends.is_empty():
		t += "Knows: %s.\n" % ", ".join(friends.slice(0, 8))
	# money and debt in plain words
	t += "\n[b]Money[/b]\nCash and savings %s. Credit: %s.\n" % [_money(ww.cash(c)), LTFinance.score_text(c)]
	var exp: Array = LTFinance.personal_exposure(ww, c)
	if exp.is_empty():
		t += "Owes nothing.\n"
	else:
		for d in exp:
			var whose: String = ""
			if str(d["debtor_kind"]) == "b":
				var b: Dictionary = ww.biz(int(d["debtor_id"]))
				if str(b["legal_form"]) == "sole":
					whose = " Business debt of %s, but as a sole owner it is theirs personally too." % biz_link(int(b["id"]))
				else:
					whose = " Debt of %s (an LLC). Theirs only because they signed a personal guarantee." % biz_link(int(b["id"]))
			elif d["joint"].has(id):
				whose = " A joint debt with %s. Both owe all of it." % sim_link(int(d["debtor_id"]))
			t += "- [url=debt:%d]%s[/url] to %s: %s left, %s a month, %s.%s\n" % [d["id"], str(d["type"]).replace("_", " "), LTFinance.creditor_name(ww, d), _money(int(d["balance"])), _money(LTFinance.min_due(d)), LTFinance.status_text(str(d["status"])), whose]
	for bid in c["owns"]:
		var bo: Dictionary = ww.biz(int(bid))
		if str(bo["legal_form"]) == "llc":
			t += "Owns %s as an LLC: its debts stay with the company unless they guaranteed them.\n" % biz_link(int(bid))
		else:
			t += "Owns %s as a sole proprietor: if it fails, its debts reach their house and savings.\n" % biz_link(int(bid))
	if not c["bk"].is_empty():
		t += "Bankruptcy: filed %s under %s, now %s.\n" % [LTCalendar.short(int(c["bk"]["filed"])), "liquidation" if int(c["bk"]["chapter"]) == 7 else "a repayment plan", c["bk"]["status"]]
	if c.has("estate"):
		var e: Dictionary = c["estate"]
		t += "Estate: %s in, %s paid to creditors, %s unpaid and lost by creditors, %s to heirs.\n" % [_money(int(e["assets"])), _money(int(e["paid"])), _money(int(e["unpaid"])), _money(int(e["to_heirs"]))]
	t += "Trust in the city: %d.\n" % int(c["trust_city"])
	# needs, traits, skills
	t += "\n[b]Needs[/b]  (happiness %d)\n" % int(LTPeople.happiness(c))
	for k in LTPeople.NEED_KEYS:
		t += "%s %s\n" % [str(k).replace("_", " ").rpad(15), _bar(float(c["needs"][k]))]
	if int(c["sick_days"]) > 0 or bool(c["chronic"]):
		t += "Health note: %s.\n" % (c["health_cond"] if str(c["health_cond"]) != "" else "chronic condition")
	t += "\n[b]Personality[/b]\n"
	var tp: Array = []
	for k in LTPeople.TRAIT_KEYS:
		tp.append("%s %d" % [k, int(c["traits"][k])])
	t += ", ".join(tp) + "\n"
	var sk: Array = LTPeople.SKILL_KEYS.duplicate()
	sk.sort_custom(func(a, b): return float(c["skills"][a]) > float(c["skills"][b]))
	var sp: Array = []
	for k in sk.slice(0, 5):
		sp.append("%s %d" % [k, int(c["skills"][k])])
	t += "[b]Best skills[/b]: %s\n" % ", ".join(sp)
	if not c["memory"].is_empty():
		var mm: Array = []
		for m in c["memory"]:
			mm.append(str(m["kind"]).replace("_", " "))
		t += "[b]Remembers[/b]: %s\n" % ", ".join(mm)
	t += "\n[b]History, newest first[/b]\n"
	var hist: Array = c["history"]
	for i in range(hist.size() - 1, maxi(-1, hist.size() - 61), -1):
		var e2: Dictionary = hist[i]
		t += "[color=#9fb0c0]%s[/color] %s%s%s\n" % [LTCalendar.short(maxi(1, int(e2["day"]))), "" if bool(e2["major"]) else "[color=#aab4bf]", e2["text"], "" if bool(e2["major"]) else "[/color]"]
	return t


func _biz_text(id: int) -> String:
	var ww: LTWorld = w()
	var b: Dictionary = ww.biz(id)
	if b.is_empty():
		return "No business."
	var owners: Array = []
	for o in b["owners"]:
		owners.append(sim_link(int(o)))
	var t: String = "[font_size=19][b]%s[/b][/font_size]\n%s on %s. %s since %s.\n" % [b["name"], str(LTEconomy.TYPES[b["type"]]["display"]), lot_link(int(b["lot"])), "Open" if str(b["status"]) == "open" else "Closed " + LTCalendar.short(int(b["closed_day"])) + ": " + str(b["close_reason"]), LTCalendar.short(maxi(1, int(b["opened_day"])))]
	t += "Owner: %s. Legal form: %s.\n" % [", ".join(owners), "LLC, so its debts stay with the company unless the owner guaranteed them" if str(b["legal_form"]) == "llc" else "sole proprietorship, so the owner and the business are one legal pocket"]
	t += "Cash %s. Reputation %d. Condition %d, cleanliness %d.\n" % [_money(ww.biz_cash(b)), int(b["reputation"]), int(b["condition"]), int(b["cleanliness"])]
	if str(b["type"]) != "landlord":
		t += "Staff (%d of %d wanted): " % [b["staff"].size(), b["target_staff"]]
		var st: Array = []
		for sid in b["staff"]:
			st.append(sim_link(int(sid)))
		t += ("none" if st.is_empty() else ", ".join(st)) + ". Pays %s a day.\n" % _money(int(b["wage"]))
	if ["grocery", "cafe", "general_store"].has(str(b["type"])):
		t += "Stock on the shelves: %d units. Prices %d%% of the outside supermarket. Supplier: %s.\nCustomers today %d. Average customer experience %d.\n" % [int(b["stock"]), int(float(b["price_level"]) * 100.0), b["supplier"], b["customers_today"], int(b["experience_avg"])]
	elif str(b["type"]) == "farm":
		t += "Produce in storage: %d units. Sells to town first, surplus to the outside co-op.\n" % int(b["produce"])
	elif str(b["type"]) == "construction":
		t += "Public jobs done %d. Crew quality %d.\n" % [b["jobs_done"], int(float(b["crew_quality"]) * 100.0)]
	if bool(b["free_lot"]) or int(b["tax_break_until"]) > ww.day:
		t += "City incentives: %s%s.\n" % ["free lot " if bool(b["free_lot"]) else "", "no business tax until " + LTCalendar.short(int(b["tax_break_until"])) if int(b["tax_break_until"]) > ww.day else ""]
	var ph: Array = b["month_profit_hist"]
	if not ph.is_empty():
		var pp: Array = []
		for v in ph.slice(maxi(0, ph.size() - 6)):
			pp.append(_money(int(v)))
		t += "Profit by month: %s.\n" % ", ".join(pp)
	var ds: Array = LTFinance.debts_of(ww, "b", id)
	if not ds.is_empty():
		t += "\n[b]Debts[/b]\n"
		for d in ds:
			t += "- [url=debt:%d]%s[/url] to %s: %s, %s.%s\n" % [d["id"], str(d["type"]).replace("_", " "), LTFinance.creditor_name(ww, d), _money(int(d["balance"])), LTFinance.status_text(str(d["status"])), " Personally guaranteed by %s." % sim_link(int(d["guarantor"])) if int(d["guarantor"]) >= 0 else ""]
	if str(b["start_reason"]) != "":
		t += "\n[b]Why it started[/b]\n%s\n" % b["start_reason"]
	t += "\n[b]History, newest first[/b]\n"
	var hist: Array = b["history"]
	for i in range(hist.size() - 1, maxi(-1, hist.size() - 41), -1):
		t += "[color=#9fb0c0]%s[/color] %s\n" % [LTCalendar.short(maxi(1, int(hist[i]["day"]))), hist[i]["text"]]
	return t


func _lot_text(id: int) -> String:
	var ww: LTWorld = w()
	var l: Dictionary = ww.lot(id)
	var t: String = "[font_size=19][b]Lot %d[/b][/font_size]\n%s. Zoned %s. Value %s.\n" % [id, LTGeography.lot_street(ww, id)["name"], l["zone"], _money(int(l["value"]))]
	var owner: String = "the city"
	match str(l["owner_kind"]):
		"sim":
			owner = sim_link(int(l["owner_id"]))
		"business":
			owner = biz_link(int(l["owner_id"]))
		"outside":
			owner = "an outside owner"
	t += "Owner: %s.\n" % owner
	match str(l["use"]):
		"house", "apartment":
			t += "%s. Condition %d.\nWho lives here:\n" % [str(l["use"]).capitalize(), int(l["condition"])]
			for u in l["units"]:
				if int(u) < 0:
					t += "- empty unit%s\n" % (", rent %s" % _money(int(l["unit_rent"])) if int(l["unit_rent"]) > 0 else "")
				else:
					var hh: Dictionary = ww.hh(int(u))
					var ms: Array = []
					for m in ww.household_members(hh):
						ms.append(sim_link(int(m["id"])))
					t += "- %s%s\n" % [", ".join(ms), " (rent %s)" % _money(int(hh["rent"])) if str(hh["tenure"]) == "rent" else ""]
		"business", "closed":
			t += "Business: %s.\n" % biz_link(int(l["ref"]))
		"civic":
			t += "City %s.\n" % l["building"]
		"site", "reserved":
			t += "Project: [url=proj:%d]%s[/url].\n" % [int(l["ref"]), ww.projects[int(l["ref"])]["title"]]
		"empty":
			t += "Empty. You can rezone it. A Sim may build here if the zone fits what they want.\n"
	if str(l["zone"]) == "commercial" and str(l["use"]) == "empty":
		t += "Lease if a business opens here: %s a month.\n" % _money(LTCivic.lot_rent(ww, id))
	return t


func _proj_text(id: int) -> String:
	var ww: LTWorld = w()
	if id < 0 or id >= ww.projects.size():
		return "No project."
	var p: Dictionary = ww.projects[id]
	var t: String = "[font_size=19][b]%s[/b][/font_size]\nStatus %s. Ceiling %s.\n" % [p["title"], p["status"], _money(int(p["ceiling"]))]
	if int(p["petition_id"]) >= 0:
		t += "Came from the petition [url=pet:%d]%s[/url].\n" % [p["petition_id"], ww.petitions[int(p["petition_id"])]["title"]]
	if str(p["winner_name"]) != "":
		t += "Contractor %s. Price %s plus %s in change orders. Paid so far %s.\n" % [p["winner_name"], _money(int(p["price"])), _money(int(p["change_orders"])), _money(int(p["paid"]))]
	if str(p["status"]) == "done":
		t += "Quality %d of 100. Warranty until %s.\n" % [int(float(p["quality"]) * 100.0), LTCalendar.short(int(p["warranty_until"]))]
	t += "\n[b]Paper trail[/b]\n"
	for e in p["events"]:
		t += "[color=#9fb0c0]%s[/color] %s\n" % [LTCalendar.short(maxi(1, int(e["day"]))), e["text"]]
	return t


func _pet_text(id: int) -> String:
	var ww: LTWorld = w()
	var p: Dictionary = ww.petitions[id]
	var t: String = "[font_size=19][b]%s[/b][/font_size]\nStatus: %s.\n%s\n" % [p["title"], p["status"], p["why"]]
	t += "Started by %s. Suggested site: %s.\nSigned by (%d): " % [sim_link(int(p["starter"])), p["site_text"], p["signers"].size()]
	var ss: Array = []
	for s in p["signers"]:
		ss.append(sim_link(int(s)))
	t += ", ".join(ss) + "\n"
	if str(p["response"]) != "":
		t += "Your answer: %s %s\n" % [str(p["response"]).replace("_", " "), p["response_reason"]]
	for o in p["outcome"]:
		t += "%s\n" % o
	return t


func _debt_text(id: int) -> String:
	var ww: LTWorld = w()
	var d: Dictionary = ww.debt(id)
	if d.is_empty():
		return "No debt."
	var t: String = "[font_size=19][b]%s[/b][/font_size]\n" % str(d["type"]).replace("_", " ").capitalize()
	t += "Owed by %s to %s. Original %s, now %s at %.1f%%. Status: %s.\n" % [LTFinance.debtor_name(ww, d), LTFinance.creditor_name(ww, d), _money(int(d["original"])), _money(int(d["balance"])), float(d["rate"]) * 100.0, LTFinance.status_text(str(d["status"]))]
	if str(d["secured_by"]) != "":
		t += "Secured by the %s.\n" % d["secured_by"]
	if not bool(d["dischargeable"]):
		t += "Bankruptcy cannot erase this kind of debt.\n"
	t += "\n[b]Paper trail[/b]\n"
	for e in d["history"]:
		t += "[color=#9fb0c0]%s[/color] %s\n" % [LTCalendar.short(maxi(1, int(e["day"]))), e["text"]]
	return t
