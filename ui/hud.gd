extends CanvasLayer
## The mayor's desk. Everything the player can do goes through main.act(), which
## goes through LTWorld.apply_action(), so every choice is logged and replayable.
## Names in any text are links: click one to open that Sim, business, lot or project.

const ChartScript = preload("res://ui/chart.gd")
const TABS: Array = ["Mayor", "Requests", "Projects", "People", "Business", "City", "News", "Help"]
const LEFT_W: int = 480
const RIGHT_W: int = 440
const TOP_H: int = 64
const TOOL_H: int = 66
## The build tools stand in a column down the right edge.
const TOOL_COL_W: int = 176

var main: Node
var root: Control
var top_bar: PanelContainer
var lbl_town: Label
var lbl_date: Label
var lbl_stats: Label
var speed_btns: Array = []
var left: PanelContainer
var tabs: TabContainer
var tab_btns: Array = []


func _mark_tab() -> void:
	for i in tab_btns.size():
		(tab_btns[i] as Button).set_pressed_no_signal(i == tabs.current_tab)
var tab_boxes: Dictionary = {}
var right: PanelContainer
var inspect_text: RichTextLabel
var inspect_form: VBoxContainer
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
	_build_tools()
	_build_steps()
	# a notice card that stops time but never blocks the rest of the screen
	notice = PanelContainer.new()
	notice.anchor_left = 0.5
	notice.anchor_right = 0.5
	notice.offset_left = -270
	notice.offset_right = 270
	notice.offset_top = TOP_H + 6
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
	if main.resumed:
		show_toast("Welcome back to %s. Everything is as you left it on %s." % [w().city["name"], LTCalendar.short(w().day)])
	else:
		show_setup(true)


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
	t.set_font_size("font_size", "Label", 17)
	t.set_font_size("font_size", "Button", 17)
	t.set_font_size("font_size", "OptionButton", 17)
	t.set_font_size("font_size", "CheckBox", 17)
	t.set_font_size("font_size", "LineEdit", 17)
	t.set_font_size("font_size", "PopupMenu", 20)
	t.set_constant("v_separation", "PopupMenu", 16)
	t.set_font_size("normal_font_size", "RichTextLabel", 16)
	t.set_font_size("bold_font_size", "RichTextLabel", 17)
	t.set_font_size("font_size", "TabContainer", 15)
	# buttons tall enough for a thumb
	for st in ["normal", "hover", "pressed"]:
		var sb: StyleBoxFlat = t.get_stylebox(st, "Button")
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 9
		sb.content_margin_bottom = 9
	# scroll bars about a finger wide, with a grabber that is easy to hit
	var track: StyleBoxFlat = StyleBoxFlat.new()
	track.bg_color = Color(0.14, 0.16, 0.2)
	track.set_corner_radius_all(8)
	track.content_margin_left = 11
	track.content_margin_right = 11
	var grab: StyleBoxFlat = StyleBoxFlat.new()
	grab.bg_color = Color(0.45, 0.52, 0.62)
	grab.set_corner_radius_all(8)
	grab.content_margin_left = 11
	grab.content_margin_right = 11
	var grab_h: StyleBoxFlat = grab.duplicate()
	grab_h.bg_color = Color(0.85, 0.65, 0.2)
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("scroll_focus", "VScrollBar", track)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_h)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_h)
	return t


## A big, easy to hit button for the top bar and the build tools: at least 48
## pixels tall (the size touch guidelines ask for) with larger text.
func _big(b: Button, min_w: float = 0.0) -> Button:
	b.custom_minimum_size = Vector2(min_w, 48)
	b.add_theme_font_size_override("font_size", 17)
	# the game's own colors: slate, lighter on hover, gold when selected
	var looks: Dictionary = {
		"normal": Color(0.2, 0.26, 0.33), "hover": Color(0.28, 0.36, 0.46),
		"pressed": Color(0.85, 0.65, 0.2), "hover_pressed": Color(0.92, 0.72, 0.28),
		"disabled": Color(0.16, 0.18, 0.21),
	}
	for st in looks:
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = looks[st]
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_pressed_color", Color(0.1, 0.08, 0.04))
	b.add_theme_color_override("font_hover_pressed_color", Color(0.1, 0.08, 0.04))
	return b


## Touch scrolling: a drag that starts on text or a button should scroll the
## panel, not get stuck on the control. PASS lets the control still take taps
## while the drag goes on to the scroll container.
func _scroll_friendly(node: Node) -> void:
	for ch in node.get_children():
		if ch is ScrollBar:
			continue
		if ch is Control:
			(ch as Control).mouse_filter = Control.MOUSE_FILTER_PASS
		_scroll_friendly(ch)


func _make_scroll(sc: ScrollContainer) -> void:
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = 10
	sc.get_v_scroll_bar().custom_minimum_size = Vector2(22, 0)
	sc.get_v_scroll_bar().mouse_filter = Control.MOUSE_FILTER_STOP


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


# ================================================================ paper documents
## Contracts, permits, petitions, deeds and loans look like paper: a cream page,
## dark ink, the city's letterhead, a number and date, a stamp, and a line for the
## mayor's signature. Everything else stays a plain panel.

const PAPER: Color = Color(0.965, 0.94, 0.87)
const INK: Color = Color(0.17, 0.14, 0.11)
const INK_SOFT: String = "#6f6150"


func _paper_style() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.border_color = Color(0.72, 0.64, 0.5)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(2, 3)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	return sb


## Light panel colors swapped for inks that read on paper.
func _inkify(bb: String) -> String:
	return bb.replace("#9fb0c0", INK_SOFT).replace("#e8c35a", "#8a5a00").replace("#ef6b5b", "#a02818").replace("#b8c8a0", "#3d6a2a").replace("#6f8090", INK_SOFT)


## Recolors everything inside a paper so it reads as ink.
func _ink_tree(node: Node) -> void:
	for ch in node.get_children():
		if ch is RichTextLabel:
			var r: RichTextLabel = ch
			r.add_theme_color_override("default_color", INK)
			r.text = _inkify(r.text)
		elif ch is CheckBox:
			# a checkbox on paper: ink text on a faint ruled box, not a dark button
			for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
				(ch as CheckBox).add_theme_color_override(k, INK)
			var box: StyleBoxFlat = StyleBoxFlat.new()
			box.bg_color = Color(0.92, 0.88, 0.78)
			box.border_color = Color(0.72, 0.64, 0.5)
			box.set_border_width_all(1)
			box.set_corner_radius_all(3)
			box.content_margin_left = 8
			box.content_margin_right = 8
			box.content_margin_top = 6
			box.content_margin_bottom = 6
			for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
				(ch as CheckBox).add_theme_stylebox_override(st, box)
		elif ch is Label:
			(ch as Label).add_theme_color_override("font_color", INK)
		if not (ch is Button or ch is LineEdit or ch is SpinBox):
			_ink_tree(ch)


func _letterhead(doc: String, number: int, stamp: String = "") -> String:
	var ww: LTWorld = w()
	var t: String = "[center][font_size=13][color=%s]THE TOWN OF %s[/color][/font_size]\n[b][font_size=19]%s[/font_size][/b]\n[font_size=13][color=%s]No. %04d     %s[/color][/font_size][/center]" % [INK_SOFT, str(ww.city["name"]).to_upper(), doc, INK_SOFT, number, LTCalendar.short(maxi(1, ww.day))]
	if stamp != "":
		var col: String = {"APPROVED": "#2f6b2a", "SIGNED": "#2f6b2a", "DRAFT": "#8a5a00", "DENIED": "#a02818", "FILED": "#2c4f7a", "PAID": "#2f6b2a", "CANCELLED": "#a02818"}.get(stamp, "#2c4f7a")
		t += "\n[right][font_size=18][b][color=%s][ %s ][/color][/b][/font_size][/right]" % [col, stamp]
	return t + "\n[color=%s]________________________________________[/color]\n" % INK_SOFT


func _signature(by_mayor: bool, note: String = "") -> String:
	var ww: LTWorld = w()
	var who: String = "%s, Mayor of %s" % [ww.player.get("name", "The mayor"), ww.city["name"]] if by_mayor else note
	return "\n[color=%s]________________________________\n[i]%s[/i][/color]" % [INK_SOFT, who]


## Wraps a card in paper with a letterhead and a signature line.
func _paper(inner: Control, doc: String, number: int, stamp: String, signature: String) -> PanelContainer:
	var pc: PanelContainer = PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _paper_style())
	var vb: VBoxContainer = VBoxContainer.new()
	pc.add_child(vb)
	vb.add_child(_rtl(_letterhead(doc, number, stamp)))
	vb.add_child(inner)
	if signature != "":
		vb.add_child(_rtl(signature))
	_ink_tree(pc)
	return pc


func _proj_doc(p: Dictionary) -> Array:
	var doc: String = "BUILDING PERMIT" if bool(p["private"]) else ("PUBLIC WORKS CONTRACT" if LTProjects.is_road(str(p["ptype"])) or p.has("spec") else "CONTRACT")
	var stamp: String = {"draft": "DRAFT", "bidding": "FILED", "review": "FILED", "building": "SIGNED", "done": "SIGNED", "cancelled": "CANCELLED"}.get(str(p["status"]), "")
	if bool(p["private"]):
		stamp = "APPROVED"
	return [doc, stamp]


func _pet_doc(p: Dictionary) -> Array:
	var stamp: String = {"submitted": "FILED", "denied": "DENIED", "published": "APPROVED", "resolved": "APPROVED"}.get(str(p["status"]), "")
	if p.has("project_id") and str(p["status"]) != "denied":
		stamp = "APPROVED"
	return ["PETITION TO THE MAYOR", stamp]


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
	top_bar.offset_bottom = TOP_H
	root.add_child(top_bar)
	var hb: HBoxContainer = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	top_bar.add_child(hb)
	var tg: Button = _big(_btn("Panels", _toggle_panels, "Show or hide the side panels"))
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
		var tip: String = ["Stop time to plan. Time also stops whenever the game is closed.", "Real time: one game second per real second. Use Today to match your own date and clock.", "One day in about two minutes. Watch Sims near the camera live their day.", "One day every few seconds.", "One week per step. Stops on events you care about.", "One month per step. Stops on events you care about."][i]
		var b: Button = _big(_btn(str(sp["name"]), func(): main.set_speed(i), tip))
		b.toggle_mode = true
		speed_btns.append(b)
		hb.add_child(b)
	hb.add_child(_big(_btn("Today", func(): show_toast(main.match_real_time()), "Fast forward (only forward) until the town's date and clock match yours, then run live.")))
	# the things you do now and then live in one menu, so the bar has room for big buttons
	var menu: MenuButton = MenuButton.new()
	menu.text = "Menu"
	menu.flat = false
	_big(menu, 90)
	var pm: PopupMenu = menu.get_popup()
	pm.add_theme_font_size_override("font_size", 20)
	pm.add_theme_constant_override("v_separation", 18)
	pm.add_theme_constant_override("item_start_padding", 16)
	pm.add_theme_constant_override("item_end_padding", 24)
	for it in ["Save", "Load", "New town", "Your profile", "Sound: on", "Show next steps"]:
		pm.add_item(it)
	pm.id_pressed.connect(_on_menu)
	menu_popup = pm
	hb.add_child(menu)


var menu_popup: PopupMenu
var steps_card: PanelContainer
var steps_text: RichTextLabel
var steps_hidden: bool = false


## A small card under the top bar with the next few things to do.
func _build_steps() -> void:
	steps_card = PanelContainer.new()
	steps_card.anchor_left = 0.0
	steps_card.anchor_top = 0.0
	steps_card.offset_top = TOP_H + 6
	steps_card.custom_minimum_size = Vector2(380, 0)
	root.add_child(steps_card)
	var vb: VBoxContainer = VBoxContainer.new()
	steps_card.add_child(vb)
	var hb: HBoxContainer = HBoxContainer.new()
	var t: Label = _lbl("Next steps", 16, Color(1.0, 0.85, 0.45))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	hb.add_child(_btn("Hide", func():
		steps_hidden = true
		steps_card.visible = false
		show_toast("Next steps hidden. Show them again from the Menu.")))
	vb.add_child(hb)
	steps_text = _rtl("")
	steps_text.custom_minimum_size = Vector2(360, 0)
	vb.add_child(steps_text)


func refresh_steps() -> void:
	if steps_card == null:
		return
	var all: Array = LTFounder.next_steps(w())
	var lines: Array = []
	var done_n: int = 0
	for st in all:
		if bool(st["done"]):
			done_n += 1
			continue
		lines.append(("[color=#e8c35a]> %s[/color]" if lines.is_empty() else "[color=#9fb0c0]- %s[/color]") % st["text"])
		if lines.size() >= 3:
			break
	if lines.is_empty():
		lines.append("Every goal reached. The town is yours to keep growing.")
	steps_text.text = "\n".join(lines) + "\n[color=#6f8090][font_size=12]%d of %d done[/font_size][/color]" % [done_n, all.size()]
	steps_card.visible = not steps_hidden
	steps_card.offset_left = (LEFT_W + 16) if left.visible else 8
	steps_card.offset_right = steps_card.offset_left + 380


func _on_menu(id: int) -> void:
	match id:
		0:
			show_toast(main.save_game())
		1:
			show_toast(main.load_game())
		2:
			show_setup()
		3:
			show_profile()
		4:
			main.sound.muted = not main.sound.muted
			menu_popup.set_item_text(4, "Sound: off" if main.sound.muted else "Sound: on")
			show_toast("Sound off." if main.sound.muted else "Sound on.")
		5:
			steps_hidden = false
			refresh_steps()


func _build_left() -> void:
	left = PanelContainer.new()
	left.anchor_top = 0.0
	left.anchor_bottom = 1.0
	left.offset_top = TOP_H + 6
	left.offset_bottom = -8
	left.offset_left = 8
	left.offset_right = 8 + LEFT_W
	root.add_child(left)
	var lv: VBoxContainer = VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(lv)
	# the sections as big buttons in two rows, easier to hit than small tabs
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	lv.add_child(grid)
	for i in TABS.size():
		var tb: Button = _btn(str(TABS[i]), func(): _show_tab(str(TABS[i])))
		tb.toggle_mode = true
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.custom_minimum_size = Vector2(0, 46)
		tab_btns.append(tb)
		grid.add_child(tb)
	tabs = TabContainer.new()
	tabs.tabs_visible = false
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(tabs)
	for t in TABS:
		var sc: ScrollContainer = ScrollContainer.new()
		sc.name = t
		_make_scroll(sc)
		tabs.add_child(sc)
		var vb: VBoxContainer = VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_theme_constant_override("separation", 6)
		sc.add_child(vb)
		tab_boxes[t] = vb
	tabs.tab_changed.connect(func(_i):
		_mark_tab()
		refresh_tab())
	_mark_tab()


func _build_right() -> void:
	right = PanelContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.anchor_top = 0.0
	right.anchor_bottom = 1.0
	right.offset_left = -RIGHT_W - TOOL_COL_W - 16
	right.offset_right = -TOOL_COL_W - 16
	right.offset_top = TOP_H + 6
	right.offset_bottom = -8
	root.add_child(right)
	var vb: VBoxContainer = VBoxContainer.new()
	right.add_child(vb)
	inspect_actions = HBoxContainer.new()
	vb.add_child(inspect_actions)
	var sc: ScrollContainer = ScrollContainer.new()
	_make_scroll(sc)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(sc)
	var body: VBoxContainer = VBoxContainer.new()
	body.custom_minimum_size = Vector2(RIGHT_W - 80, 0)
	sc.add_child(body)
	inspect_text = _rtl("")
	inspect_text.custom_minimum_size = Vector2(RIGHT_W - 80, 0)
	body.add_child(inspect_text)
	inspect_form = VBoxContainer.new()
	body.add_child(inspect_form)
	right.visible = false


var tool_btns: Dictionary = {}
var tool_bar: PanelContainer
var zone_opt: OptionButton
var undo_btn: Button
var map_opt: OptionButton


func refresh_undo() -> void:
	if undo_btn != null:
		undo_btn.disabled = not main.can_undo()
		undo_btn.tooltip_text = ("Undo %s. Works until the next day begins." % str(main.undo_stack[main.undo_stack.size() - 1]["label"])) if main.can_undo() else "Nothing to undo today."


## Build tools: look around, draw roads, plot lots, take lots back.
func _build_tools() -> void:
	tool_bar = PanelContainer.new()
	tool_bar.anchor_left = 1.0
	tool_bar.anchor_right = 1.0
	tool_bar.anchor_top = 0.0
	tool_bar.anchor_bottom = 1.0
	tool_bar.offset_left = -TOOL_COL_W - 8
	tool_bar.offset_right = -8
	tool_bar.offset_top = TOP_H + 6
	tool_bar.offset_bottom = -8
	root.add_child(tool_bar)
	var sc: ScrollContainer = ScrollContainer.new()
	_make_scroll(sc)
	tool_bar.add_child(sc)
	var hb: VBoxContainer = VBoxContainer.new()
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 8)
	sc.add_child(hb)
	var tips: Dictionary = {
		"look": "Tap lots, roads and people to see them. Drag to move the map.",
		"road": "Drag along the survey grid to draw a straight street or alley. It starts as a draft contract: set its terms, press Go live, and contractors bid to build it.",
		"plot": "Drag a rectangle beside a road to plot land of any size. Pick a lot width to cut a long strip into several lots.",
		"unplot": "Tap an empty lot the city still owns to return it to prairie.",
	}
	for t in [["look", "Look"], ["road", "Draw road"], ["plot", "Plot lots"], ["unplot", "Remove lot"]]:
		var b: Button = _big(_btn(t[1], func(): _set_tool(t[0]), tips[t[0]]), 0)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tool_btns[t[0]] = b
		hb.add_child(b)
		if t[0] == "road":
			road_opt = _tool_opt(["Street", "Alley"], func(i): main.view.road_kind = "alley" if i == 1 else "street")
			hb.add_child(road_opt)
		elif t[0] == "plot":
			zone_opt = OptionButton.new()
			for z in LTGeography.ZONES:
				if z != "none":
					zone_opt.add_item(z)
			zone_opt.item_selected.connect(func(i): main.view.plot_zone = zone_opt.get_item_text(i))
			_style_tool_opt(zone_opt)
			hb.add_child(zone_opt)
			width_opt = _tool_opt(PLOT_WIDTHS.map(func(e): return str(e[1])), func(i): main.view.plot_width = float(PLOT_WIDTHS[i][0]))
			hb.add_child(width_opt)
	hb.add_child(_sep())
	map_opt = OptionButton.new()
	for k in main.view.OVERLAYS:
		map_opt.add_item("Map: normal" if k == "" else str({"value": "Map: value", "condition": "Map: condition", "happiness": "Map: happiness", "safety": "Map: safety", "sale": "Map: for sale"}[k]))
		map_opt.set_item_metadata(map_opt.item_count - 1, k)
	map_opt.item_selected.connect(func(i):
		var k: String = str(map_opt.get_item_metadata(i))
		main.view.set_overlay(k)
		if k != "":
			show_toast("%s. Red is low, yellow middling, green high.%s Lots left plain have nothing to show." % [main.view.OVERLAYS[k], " Blue lots are held for the city." if k == "sale" else ""]))
	map_opt.tooltip_text = "Color the map to see problems at a glance."
	_style_tool_opt(map_opt)
	hb.add_child(map_opt)
	undo_btn = _big(_btn("Undo", func():
		show_toast(main.undo())
		refresh_undo(), "Take back your last change. Works until the next day begins."), 0)
	undo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(undo_btn)
	_set_tool("look")


## Lot widths for the plot tool: one lot as dragged, or cut into lots this wide.
const PLOT_WIDTHS: Array = [[0.0, "One lot as drawn"], [12.0, "12 m storefronts"], [15.0, "15 m (50 ft)"], [20.0, "20 m (66 ft)"], [25.0, "25 m (80 ft)"], [30.0, "30 m (100 ft)"], [45.0, "45 m (150 ft)"]]
var road_opt: OptionButton
var width_opt: OptionButton


func _tool_opt(items: Array, cb: Callable) -> OptionButton:
	var o: OptionButton = OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.item_selected.connect(cb)
	_style_tool_opt(o)
	return o


func _style_tool_opt(o: OptionButton) -> void:
	o.focus_mode = Control.FOCUS_NONE
	o.clip_text = true
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_big(o, 0)
	o.get_popup().add_theme_font_size_override("font_size", 20)
	o.get_popup().add_theme_constant_override("v_separation", 16)


func _set_tool(t: String) -> void:
	main.view.set_tool(t)
	main.view.plot_zone = zone_opt.get_item_text(zone_opt.selected)
	for k in tool_btns:
		(tool_btns[k] as Button).button_pressed = k == t
	zone_opt.visible = t == "plot"
	width_opt.visible = t == "plot"
	road_opt.visible = t == "road"
	if t != "look":
		show_toast({"road": "Drag to draw a straight street or alley on the survey grid.", "plot": "Drag a rectangle up against a road. Its sides snap to the road's edge.", "unplot": "Tap an empty city lot to take it back."}[t])


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
	toast.offset_top = TOP_H + 8
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var tsb: StyleBoxFlat = StyleBoxFlat.new()
	tsb.bg_color = Color(0.06, 0.07, 0.09, 0.9)
	tsb.set_corner_radius_all(6)
	tsb.set_content_margin_all(8)
	toast.add_theme_stylebox_override("normal", tsb)
	toast.z_index = 5
	toast.modulate.a = 0.0
	root.add_child(toast)


func _toggle_panels() -> void:
	_collapsed = not _collapsed
	left.visible = not _collapsed
	if _collapsed:
		right.visible = false


## Last time a finger or the mouse touched a side panel, in milliseconds. While
## someone is reading or scrolling a panel it is not rebuilt under them.
var _panel_touch_ms: int = -100000
var _refresh_pending: bool = false
const PANEL_QUIET_MS: int = 2500


func _input(event: InputEvent) -> void:
	# only scrolling counts (a drag or the wheel), so a tap on a button still
	# updates the panel right away
	var pos: Vector2 = Vector2(-1, -1)
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask != 0:
		pos = (event as InputEventMouse).position
	elif event is InputEventMouseButton and ((event as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_UP or (event as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_DOWN):
		pos = (event as InputEventMouse).position
	elif event is InputEventScreenDrag:
		pos = (event as InputEventScreenDrag).position
	if pos.x < 0.0:
		return
	for pnl in [left, right]:
		if pnl != null and pnl.visible and pnl.get_global_rect().has_point(pos):
			_panel_touch_ms = Time.get_ticks_msec()


func _panel_busy() -> bool:
	return Time.get_ticks_msec() - _panel_touch_ms < PANEL_QUIET_MS


func _process(delta: float) -> void:
	if _refresh_pending and not _panel_busy():
		_refresh_pending = false
		refresh_tab()
		if right.visible and inspect_kind != "":
			inspect(inspect_kind, inspect_id, false)
	if _toast_t > 0.0:
		_toast_t -= delta
		toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	# keep panels usable on narrow screens
	var vw: float = root.size.x
	if vw < LEFT_W + RIGHT_W + TOOL_COL_W + 200 and right.visible and left.visible:
		left.visible = false
	if steps_card != null:
		# the welcome and event cards sit in the same spot; the steps wait behind them
		steps_card.visible = not steps_hidden and not notice.visible
		steps_card.offset_left = (LEFT_W + 16) if left.visible else 8
		steps_card.offset_right = steps_card.offset_left + 380


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


## The new town card: how this town is played.
func show_setup(first: bool = false) -> void:
	main.set_speed(0)
	var card: PanelContainer = PanelContainer.new()
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -300
	card.offset_right = 300
	card.offset_top = -270
	card.offset_bottom = 200
	root.add_child(card)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	card.add_child(vb)
	vb.add_child(_h("Start a new town"))
	var start: OptionButton = OptionButton.new()
	start.add_item("Found a town: you, your lottery money, and empty prairie")
	start.add_item("Prairie Hollow: about 100 people already live here")
	vb.add_child(start)
	var rule: OptionButton = OptionButton.new()
	rule.add_item("Permanent mayor: the town is yours to run")
	rule.add_item("Elected mayor: win the vote and keep the people's trust")
	vb.add_child(rule)
	var lotto: OptionButton = OptionButton.new()
	lotto.add_item("Lottery win of $250,000 (hard)")
	lotto.add_item("Lottery win of $1,000,000")
	lotto.add_item("Lottery win of $5,000,000 (easy)")
	lotto.selected = 1
	vb.add_child(lotto)
	start.item_selected.connect(func(i): lotto.visible = i == 0)
	var cal: CheckBox = CheckBox.new()
	cal.text = "Use the real calendar, starting today"
	cal.button_pressed = true
	vb.add_child(cal)
	var hb1: HBoxContainer = HBoxContainer.new()
	hb1.add_child(_lbl("Your name"))
	var pname: LineEdit = LineEdit.new()
	pname.text = "Sam Dakota"
	pname.custom_minimum_size = Vector2(220, 0)
	hb1.add_child(pname)
	vb.add_child(hb1)
	var who: HBoxContainer = HBoxContainer.new()
	var pron: OptionButton = _opt(["they/them", "she/her", "he/him"], 0, func(_i): pass)
	who.add_child(pron)
	who.add_child(_lbl("Age"))
	var age: SpinBox = SpinBox.new()
	age.min_value = 18
	age.max_value = 99
	age.value = 38
	who.add_child(age)
	who.add_child(_lbl("From"))
	var home: LineEdit = LineEdit.new()
	home.text = "Sioux Falls"
	home.custom_minimum_size = Vector2(130, 0)
	who.add_child(home)
	vb.add_child(who)
	var hbs: HBoxContainer = HBoxContainer.new()
	hbs.add_child(_lbl("Map seed"))
	var seed_edit: LineEdit = LineEdit.new()
	seed_edit.placeholder_text = "blank for a new random map"
	seed_edit.custom_minimum_size = Vector2(260, 0)
	seed_edit.tooltip_text = "Every map has a number. Type one you liked to play the same land again."
	hbs.add_child(seed_edit)
	vb.add_child(hbs)
	var hb2: HBoxContainer = HBoxContainer.new()
	hb2.add_child(_lbl("Town name"))
	var tname: LineEdit = LineEdit.new()
	tname.text = "New Hope"
	tname.custom_minimum_size = Vector2(220, 0)
	hb2.add_child(tname)
	vb.add_child(hb2)
	vb.add_child(_lbl("Time stops whenever the game is closed. Press Today any time to fast forward to your own date and clock, then run live.", 13, Color(0.7, 0.75, 0.8)))
	var hb3: HBoxContainer = HBoxContainer.new()
	hb3.alignment = BoxContainer.ALIGNMENT_END
	hb3.add_child(_btn("Keep this town" if first else "Cancel", func():
		card.queue_free()
		if first:
			_welcome()))
	hb3.add_child(_btn("Start", func():
		var mode: Dictionary = {
			"start": "founder" if start.selected == 0 else "classic",
			"elections": rule.selected == 1,
			"lottery": [LTMoney.dollars(250000.0), LTMoney.dollars(1000000.0), LTMoney.dollars(5000000.0)][lotto.selected],
			"real_calendar": cal.button_pressed,
			"player_name": pname.text.strip_edges() if pname.text.strip_edges() != "" else "Sam Dakota",
			"map_seed": int(seed_edit.text.strip_edges()) if seed_edit.text.strip_edges().is_valid_int() else 0,
			"player_pronouns": ["they", "she", "he"][pron.selected],
			"player_age": int(age.value),
			"player_hometown": home.text.strip_edges(),
			"town_name": tname.text.strip_edges() if tname.text.strip_edges() != "" else "New Hope",
		}
		card.queue_free()
		main.new_town(randi() % 1000000, mode)))
	vb.add_child(hb3)


func _welcome() -> void:
	if str(w().mode.get("start", "classic")) == "founder":
		notice_text.text = "[b]Welcome to %s, population 1.[/b]\n%s won %s in the lottery and bought a stretch of prairie on the county road. For now you live in a camper.\nUse [b]Draw road[/b] (right side) to lay out streets off the county road. Each one is a draft contract: set the terms, press [b]Go live[/b], and contractors bid to build it. Then [b]Plot lots[/b] beside your roads and pick a zone. Settlers will come, buy residential lots, and build their own homes. Draft the mayor's house on the Projects tab and send it live. At %d residents the town incorporates and city taxes begin%s.\nYou cannot build businesses or hire anyone. Settlers decide that, and every big decision is written in their history with the reason.\nPress [b]Normal[/b] to start time, [b]Live[/b] for real time, or [b]Today[/b] to match your own date and clock." % [w().city["name"], w().player["name"], _money(int(w().mode["lottery"])), LTFounder.INCORPORATE_AT, ", followed by your first election" if bool(w().mode.get("elections", false)) else ""]
		notice.visible = true
		return
	notice_text.text = "[b]Welcome, Mayor of %s.[/b]\nAbout %d people live here. Most drive to the next town to work and shop. There is no grocery, no school, no clinic.\nYou cannot build any of that yourself. Zone land, set laws, answer petitions, and put public projects out to bid. The people decide the rest, and every big decision they make is written in their history with the reason.\nPress [b]Normal[/b] to start time, [b]Live[/b] for real time, or [b]Watch[/b] to see a single day up close. The Help tab has the controls.%s" % [w().city["name"], w().alive_count(), "\nThis town holds elections. Keep the people's trust to stay mayor." if bool(w().mode.get("elections", false)) else ""]
	notice.visible = true


# ================================================================ refresh

func on_new_world() -> void:
	inspect_kind = ""
	right.visible = false
	_welcome()
	_clear(feed_box)
	refresh_all()


func refresh_all() -> void:
	refresh_undo()
	refresh_steps()
	refresh_top()
	if _panel_busy():
		# someone is scrolling or reading: refresh once they let go
		_refresh_pending = true
		return
	refresh_tab()
	if right.visible and inspect_kind != "":
		inspect(inspect_kind, inspect_id, false)


func refresh_clock() -> void:
	var h: int = int(main.hour)
	var mf: float = (main.hour - float(h)) * 60.0
	var m: int = int(mf)
	if main.speed == 1:
		lbl_date.text = "%s  %02d:%02d:%02d" % [LTCalendar.text(w().day), h, m, int((mf - float(m)) * 60.0)]
	else:
		lbl_date.text = "%s  %02d:%02d" % [LTCalendar.text(w().day), h, m]


func refresh_top() -> void:
	var ww: LTWorld = w()
	lbl_town.text = str(ww.city["name"])
	if main.is_hourly():
		refresh_clock()
	else:
		lbl_date.text = LTCalendar.text(ww.day)
	var pop: int = ww.residents()
	var appr: String = "approval %d%%" % int(LTCivic.approval(ww)) if ww.alive_count() > 0 else "no one to ask yet"
	lbl_stats.text = "%s, %s | %d %s | %s | %s | %d shops" % [LTCalendar.season(ww.day), ww.weather, pop, "resident" if pop == 1 else "people", _money(ww.ledger.bal("city")), appr, ww.open_businesses().size() - ww.open_businesses("landlord").size()]
	lbl_stats.tooltip_text = "Season and weather, people in town, city cash, approval of the city, Sim run businesses open"
	for i in speed_btns.size():
		(speed_btns[i] as Button).button_pressed = i == main.speed


func refresh_tab() -> void:
	if tabs == null:
		return
	var t: String = TABS[tabs.current_tab]
	var sc: ScrollContainer = tab_boxes[t].get_parent()
	var keep: int = sc.scroll_vertical
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
	_scroll_friendly(tab_boxes[TABS[tabs.current_tab]])
	sc.set_deferred("scroll_vertical", keep)


# ================================================================ Mayor desk


func _tab_mayor() -> void:
	var box: VBoxContainer = tab_boxes["Mayor"]
	_clear(box)
	var ww: LTWorld = w()
	box.add_child(_h("You"))
	var pl: Dictionary = ww.player
	var where: String = "the mayor's house" if int(pl.get("home_lot", -1)) >= 0 else "a camper by the county road"
	box.add_child(_rtl("[b]%s[/b] (%s), %d, from %s. Mayor of %s, living in %s." % [pl["name"], {"they": "they/them", "he": "he/him", "she": "she/her"}.get(str(pl.get("pronouns", "they")), "they/them"), ww.player_age(), pl.get("hometown", "somewhere"), ww.city["name"], where]))
	box.add_child(_btn("Edit your profile", func(): show_profile(), "Your name, pronouns, age, hometown, color, and the town's name."))
	var tt: Dictionary = LTTerrain.t(ww)
	if not tt.is_empty():
		var lakes: Array = tt["lakes"].map(func(lk): return str(lk["name"]))
		box.add_child(_rtl("[color=#9fb0c0]The land:[/color] %s, %s and %s. [color=#9fb0c0]Map seed[/color] [b]%d[/b] (type it in New town to play this map again)." % [tt["forest_name"], tt["park_name"], " and ".join(lakes), int(tt["seed"])]))
	box.add_child(_sep())
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
	amt.custom_minimum_size = Vector2(130, 0)
	borrow.add_child(_lbl("Borrow"))
	borrow.add_child(amt)
	borrow.add_child(_btn("Borrow from the bank", func(): show_toast(str(main.act({"kind": "city_borrow", "amount": int(amt.value) * 100, "purpose": "city needs"})["message"]))))
	box.add_child(borrow)
	box.add_child(_sep())
	box.add_child(_h("Bonds and elections"))
	var bond: HBoxContainer = HBoxContainer.new()
	var bamt: SpinBox = SpinBox.new()
	bamt.min_value = 50000
	bamt.max_value = 2000000
	bamt.step = 50000
	bamt.value = 250000
	bamt.prefix = "$"
	bamt.custom_minimum_size = Vector2(130, 0)
	bond.add_child(_lbl("Bonds"))
	bond.add_child(bamt)
	bond.add_child(_btn("Sell 20 year bonds", func(): show_toast(str(main.act({"kind": "issue_bond", "amount": int(bamt.value) * 100, "purpose": "city projects"})["message"]))))
	box.add_child(bond)
	box.add_child(_rtl("Mode: %s, %s. You live in %s.%s" % ["founded from nothing" if str(ww.mode.get("start", "")) == "founder" else "Prairie Hollow", "elected mayor" if bool(ww.city.get("elections", false)) else "permanent mayor", "the mayor's house" if int(ww.player.get("home_lot", -1)) >= 0 else "a camper until the mayor's house is built", "" if bool(ww.city.get("incorporated", true)) else " Not incorporated yet: %d of %d residents. The county taxes and serves the settlement until then." % [ww.residents(), LTFounder.INCORPORATE_AT]]))
	if bool(ww.city.get("elections", false)):
		var ch: Dictionary = ww.cit(int(ww.city.get("challenger", -1)))
		box.add_child(_rtl("Next election %s.%s" % [LTCalendar.short(int(ww.city["next_election_day"])), " Running against you: %s, promising %s." % [sim_link(int(ch["id"])), ww.city["platform"]] if not ch.is_empty() and ww.is_present(ch) else ""]))
	if not bool(ww.city.get("mayor_in_office", true)):
		box.add_child(_rtl("[color=#ef6b5b][b]You lost the election.[/b] The town goes on. You can keep watching, or start a new town.[/color]"))
	box.add_child(_sep())
	box.add_child(_h("Milestones"))
	var got: Dictionary = ww.city.get("milestones", {})
	var ml: Array = []
	for m in LTFounder.MILESTONES:
		if str(ww.mode.get("start", "")) != "founder" and ["first_settler", "incorporated"].has(m[0]):
			continue
		ml.append("%s %s%s" % ["[color=#7fd37f]done[/color]" if got.has(m[0]) else "[color=#6a737d]open[/color]", m[1], " (%s)" % LTCalendar.short(int(got[m[0]])) if got.has(m[0]) else ""])
	box.add_child(_rtl("\n".join(ml)))
	box.add_child(_sep())
	box.add_child(_h("Laws"))
	box.add_child(_lbl("A law changes the numbers Sims and businesses decide with. It never sets an outcome. Each change shows an estimate first, and the City tab tracks what really happened.", 13, Color(0.7, 0.75, 0.8)))
	for key in LTCivic.LAWS:
		box.add_child(_law_row(key))
	box.add_child(_sep())
	box.add_child(_h("Publish a city need"))
	box.add_child(_lbl("Say what the town needs and offer help. A Sim still decides whether to take it, and the one who does may not be good at it.", 13, Color(0.7, 0.75, 0.8)))
	var need_opt: OptionButton = OptionButton.new()
	for k in LTEconomy.all_types():
		if k == "landlord":
			continue
		need_opt.add_item(str(LTEconomy.tcfg(k)["display"]))
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
		open_needs.append("%s on %s: %s%s" % [str(LTEconomy.tcfg(n["need"])["display"]), lot_link(int(n["lot"])), n["status"], tb])
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


func _petition_card(p: Dictionary, actions: bool) -> Control:
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
	var pd: Array = _pet_doc(p)
	var paper: PanelContainer = _paper(vb, pd[0], int(p["id"]), pd[1], "\n[color=%s]Signed by %d residents of %s.[/color]" % [INK_SOFT, p["signers"].size(), w().city["name"]])
	var gap: VBoxContainer = VBoxContainer.new()
	gap.add_child(paper)
	gap.add_theme_constant_override("separation", 10)
	gap.add_child(Control.new())
	return gap


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
	if int(ww.player.get("home_lot", -1)) < 0:
		tlist.insert(0, "mayor_house")
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
			var zl: Array = ["civic", "mixed", "park"] if pt == "park" else ["civic", "mixed"]
			if pt == "mayor_house":
				zl = LTGeography.ZONES
			for l in ww.lots:
				if str(l["use"]) == "empty" and zl.has(str(l["zone"])):
					tgt.add_item("Lot %d (%s, %s)" % [l["id"], LTGeography.lot_street(ww, int(l["id"]))["name"], l["zone"]])
					tgt.set_item_metadata(tgt.item_count - 1, int(l["id"]))
			if tgt.item_count == 0:
				tgt.add_item("No empty lot zoned for this. Rezone one first.")
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
	box.add_child(_btn("Draft contract", func():
		var r: Dictionary = main.act({"kind": "define_project", "ptype": tlist[types.selected], "target": int(tgt.get_item_metadata(tgt.selected)) if tgt.item_count > 0 else -1, "ceiling": int(ceil_s.value) * 100})
		show_toast(str(r["message"]))
		if bool(r.get("ok", false)):
			inspect("proj", int(r["project_id"])), "Write the contract first. Nothing goes out to bid until you press Go live."))
	box.add_child(_sep())
	var plist: Array = ww.projects.duplicate()
	plist.reverse()
	box.add_child(_h("Your contracts"))
	var mine: int = 0
	for p in plist:
		if not bool(p["private"]):
			box.add_child(_project_card(p))
			mine += 1
	if mine == 0:
		box.add_child(_lbl("None yet. Draw a road or draft a project above. Nothing goes out to bid until you press Go live.", 13, Color(0.7, 0.75, 0.8)))
	var priv: Array = plist.filter(func(p): return bool(p["private"]))
	if not priv.is_empty():
		box.add_child(_h("Private builds"))
		box.add_child(_lbl("Settlers and developers hiring their own builders. Not your contracts: you only see them.", 13, Color(0.7, 0.75, 0.8)))
		for p in priv:
			box.add_child(_project_card(p))


func _project_card(p: Dictionary) -> Control:
	var ww: LTWorld = w()
	var vb: VBoxContainer = VBoxContainer.new()
	var t: String = "[b][url=proj:%d]%s[/url][/b]  [color=#9fb0c0]%s%s[/color]" % [p["id"], p["title"], {"draft": "draft, not live", "bidding": "live, taking bids", "review": "bids in, waiting for you"}.get(str(p["status"]), str(p["status"])) if not bool(p["private"]) else str(p["status"]), ", the owner's own job" if bool(p["private"]) else ""]
	t += "\nCeiling %s. %s" % [_money(int(p["ceiling"])), "Bids close " + LTCalendar.short(int(p["bid_close_day"])) if str(p["status"]) == "bidding" else ("[color=#e8c35a]Draft: contractors cannot see it until you press Go live.[/color]" if str(p["status"]) == "draft" else "")]
	if p.has("spec") and not bool(p["private"]):
		t += "\n[color=#9fb0c0]Terms: %s.[/color]" % LTProjects.spec_text(p)
	match str(p["status"]):
		"building":
			t += "\nBuilt by %s for %s. Stage: %s, %d%% done. Promised %d days, started %s." % [p["winner_name"], _money(int(p["price"]) + int(p["change_orders"])), p["stage"], int(float(p["progress"]) * 100.0), p["days_promised"], LTCalendar.short(int(p["start_day"]))]
		"done":
			t += "\nBuilt by %s. Quality %d of 100. Finished %s. %s" % [p["winner_name"], int(float(p["quality"]) * 100.0), LTCalendar.short(int(p["done_day"])), ("Expected to need repair in about %d days." % int(p.get("expected_repair_days", 0))) if LTProjects.is_road(str(p["ptype"])) else ""]
	vb.add_child(_rtl(t))
	if LTProjects.spec_editable(p):
		var pide: int = int(p["id"])
		var row2: HBoxContainer = HBoxContainer.new()
		row2.add_child(_btn("Edit contract", func(): inspect("proj", pide), "Change what is built, the deadline and the budget before it is signed."))
		if str(p["status"]) == "draft":
			row2.add_child(_go_live_btn(pide))
		vb.add_child(row2)
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
	var pd: Array = _proj_doc(p)
	var sig: String = _signature(true) if not bool(p["private"]) else _signature(false, "Permit issued by the town of %s to %s" % [w().city["name"], str(p["developer"].get("name", "the owner"))])
	var paper: PanelContainer = _paper(vb, pd[0], int(p["id"]), pd[1], sig)
	var gap: VBoxContainer = VBoxContainer.new()
	gap.add_theme_constant_override("separation", 10)
	gap.add_child(paper)
	gap.add_child(Control.new())
	return gap


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
		lines.append("%s (%s), %s. Owner %s. Staff %d%s." % [biz_link(int(b["id"])), str(LTEconomy.tcfg(b["type"])["display"]).to_lower(), st, sim_link(int(owner.get("id", -1))), b["staff"].size(), profit])
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
	box.add_child(_h("The county around town"))
	var r: Dictionary = ww.region
	var emps: Array = []
	for e in r["employers"]:
		emps.append("%s%s" % [e["name"], "" if bool(e["open"]) else " (closed)"])
	box.add_child(_rtl("Economy: [b]%s[/b], index %.2f. County unemployment %d%%. Storms this game %d.\nEmployers: %s.%s" % [r["phase"], float(r["index"]), int(float(r["unemployment"]) * 100.0), r["storms"], ", ".join(emps), _shortage_text()]))
	box.add_child(_h("Where the town spends"))
	var sl: Array = []
	for k in ww.spend_book:
		var e2: Dictionary = ww.spend_book[k]
		var loc: int = int(e2["last_local"])
		var outv: int = int(e2["last_outside"])
		var lat: int = int(e2["last_latent"])
		if loc + outv + lat == 0:
			continue
		sl.append("%s: %s in town, %s out of town%s" % [LTServices._cat_words(str(k)).capitalize(), _money(loc), _money(outv), ", %s wanted with nobody to sell it" % _money(lat) if lat > 0 else ""])
	box.add_child(_rtl("A month, on average:\n" + ("\n".join(sl) if not sl.is_empty() else "Shows after the first month.")))
	box.add_child(_h("Health"))
	var preg: int = 0
	var dep: int = 0
	var add: int = 0
	var dis: int = 0
	var jail: int = 0
	for cc in ww.citizens:
		if not ww.is_present(cc):
			continue
		if not cc.get("pregnant", {}).is_empty():
			preg += 1
		if bool(cc.get("depressed", false)):
			dep += 1
		if LTHealth.level(cc) >= 60.0:
			add += 1
		if bool(cc.get("disability", false)):
			dis += 1
		if LTJustice.in_jail(ww, cc):
			jail += 1
	box.add_child(_rtl("Expecting: %d. Depressed: %d. Struggling with addiction: %d. Living with a disability: %d." % [preg, dep, add, dis]))
	box.add_child(_h("Courts"))
	var cl: Array = []
	for i in range(ww.cases.size() - 1, maxi(-1, ww.cases.size() - 13), -1):
		var cs: Dictionary = ww.cases[i]
		cl.append("%s: %s, %s. %s%s" % [LTCalendar.short(int(cs["filed_day"])), sim_link(int(cs["defendant"])), LTJustice.CHARGES[cs["charge"]]["label"], cs["status"], ", " + str(cs["sentence"]) if str(cs["sentence"]) != "" else ""])
	box.add_child(_rtl("In the county jail now: %d.\n%s" % [jail, "\n".join(cl) if not cl.is_empty() else "No cases yet."]))
	box.add_child(_h("Happiness by district"))
	var dd: Dictionary = {}
	for cc2 in ww.citizens:
		if not ww.is_present(cc2):
			continue
		var hl2: int = int(ww.hh(int(cc2["household"]))["lot"])
		var key2: String = "No home" if hl2 < 0 else LTGeography.district(ww, hl2)
		if not dd.has(key2):
			dd[key2] = [0.0, 0]
		dd[key2][0] += LTPeople.happiness(cc2)
		dd[key2][1] += 1
	var dl: Array = []
	for k2 in dd:
		dl.append("%s: %s (%d people)" % [k2, _bar(float(dd[k2][0]) / float(dd[k2][1])), dd[k2][1]])
	box.add_child(_rtl("\n".join(dl)))
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


func _shortage_text() -> String:
	var ww: LTWorld = w()
	var out: Array = []
	for k in ww.region["shortages"]:
		if int(ww.region["shortages"][k]) >= ww.day:
			out.append(str(k).replace("_", " "))
	return "" if out.is_empty() else "\nShortages at Valley Wholesale right now: %s." % ", ".join(out)


func _tab_chronicle() -> void:
	var box: VBoxContainer = tab_boxes["News"]
	_clear(box)
	var ww: LTWorld = w()
	var papers: Array = ww.city.get("newspapers", [])
	if not papers.is_empty():
		var ed: Dictionary = papers[papers.size() - 1]
		box.add_child(_h("The Prairie Hollow Ledger, No. %d" % int(ed["number"])))
		var pt: String = "[color=#9fb0c0]Week ending %s. Edited by %s.[/color]\n[font_size=18][b]%s[/b][/font_size]\n" % [LTCalendar.short(int(ed["day"])), sim_link(int(ed["editor"])), ed["headline"]]
		for st in ed["stories"]:
			pt += "- %s\n" % _linkify(str(st["text"]), st["refs"])
		pt += "[i]From the editor:[/i] %s" % ed["editorial"]
		box.add_child(_rtl(pt))
		box.add_child(_sep())
	box.add_child(_h("Town chronicle"))
	var f: OptionButton = OptionButton.new()
	var kinds: Array = ["all", "business", "debt", "bankruptcy", "estate", "death", "birth", "family", "move", "petition", "project", "city", "law", "housing", "work", "crime", "protest", "health", "region", "election"]
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
Zone empty lots (click a lot). In a founded town, draw streets and alleys and plot lots of any size anywhere with the tools down the right side. Pass laws and set taxes on the Mayor tab. Publish a city need with incentives. Answer petitions on the Requests tab. Put public projects out to bid and award them on the Projects tab. Borrow money for the city. Watch anyone.

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
	# a refresh while the mayor is typing in the form keeps the form as it is
	var typing: bool = false
	var fo: Control = get_viewport().gui_get_focus_owner()
	if not show and fo != null and inspect_form.is_ancestor_of(fo) and inspect_kind == kind and inspect_id == id:
		typing = true
	inspect_kind = kind
	inspect_id = id
	if show:
		right.visible = true
	_clear(inspect_actions)
	if not typing:
		_clear(inspect_form)
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
			main.view.select_road(-1)
			var l: Dictionary = w().lot(id)
			if ["empty", "closed"].has(str(l["use"])) and str(l["owner_kind"]) != "city":
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
			if not typing:
				_lot_form(id)
		"road":
			t = _road_text(id)
			main.view.select_lot(-1)
			main.view.select_road(id)
			var rp: int = _road_project(id)
			if rp >= 0:
				inspect_actions.add_child(_btn("Contract", func(): inspect("proj", rp)))
			if not typing:
				_road_form(id)
		"proj":
			t = _proj_text(id)
			var pp: Dictionary = w().projects[id] if id >= 0 and id < w().projects.size() else {}
			if not pp.is_empty() and str(pp["ptype"]) == "road_build":
				inspect_actions.add_child(_btn("Find", func():
					main.view.focus_street(int(pp["street"]))
					main.view.select_road(int(pp["street"]))))
			elif not pp.is_empty() and int(pp["lot"]) >= 0:
				inspect_actions.add_child(_btn("Find", func(): main.focus_lot(int(pp["lot"]))))
			if not typing and not pp.is_empty():
				_contract_form(pp)
		"pet":
			t = _pet_text(id)
		"debt":
			t = _debt_text(id)
	inspect_actions.add_child(_btn("Close", func():
		right.visible = false
		main.view.select_lot(-1)
		main.view.select_road(-1)))
	# documents (contracts, permits, petitions, deeds, loans) are shown on paper
	var doc: Array = _doc_for(kind, id)
	if doc.is_empty():
		right.remove_theme_stylebox_override("panel")
		inspect_text.remove_theme_color_override("default_color")
		inspect_text.text = t
	else:
		right.add_theme_stylebox_override("panel", _paper_style())
		inspect_text.add_theme_color_override("default_color", INK)
		inspect_text.text = _inkify(_letterhead(str(doc[0]), id, str(doc[1])) + t + str(doc[2]))
		_ink_tree(inspect_form)
	_scroll_friendly(inspect_text.get_parent())


## [title, stamp, signature] when what is inspected is an official paper, else [].
func _doc_for(kind: String, id: int) -> Array:
	var ww: LTWorld = w()
	match kind:
		"proj":
			if id < 0 or id >= ww.projects.size():
				return []
			var p: Dictionary = ww.projects[id]
			var pd: Array = _proj_doc(p)
			var sig: String = _signature(true) if not bool(p["private"]) else _signature(false, "Permit issued by the town of %s to %s" % [ww.city["name"], str(p["developer"].get("name", "the owner"))])
			return [pd[0], pd[1], sig]
		"pet":
			if id < 0 or id >= ww.petitions.size():
				return []
			var pt: Dictionary = ww.petitions[id]
			var pdd: Array = _pet_doc(pt)
			return [pdd[0], pdd[1], "\n[color=%s]Signed by %d residents of %s.[/color]" % [INK_SOFT, pt["signers"].size(), ww.city["name"]] + _signature(true)]
		"lot":
			var l: Dictionary = ww.lot(id)
			if l.is_empty():
				return []
			var owned: bool = str(l["owner_kind"]) == "city"
			return ["LAND RECORD AND DEED", "FILED", _signature(true) if owned else _signature(false, "Recorded by the town of %s" % ww.city["name"])]
		"road":
			return ["ROAD RECORD", "FILED", _signature(true)]
		"debt":
			return ["LOAN RECORD", "", _signature(false, "Recorded by the lender")]
	return []


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
	var doing: Array = []
	if not c.get("side_job", {}).is_empty():
		doing.append("extra work: %s until %s" % [c["side_job"].get("what", "extra shifts"), LTCalendar.short(int(c["side_job"]["until"]))])
	if not c.get("study", {}).is_empty():
		doing.append("night classes in %s until %s" % [c["study"]["skill"], LTCalendar.short(int(c["study"]["until"]))])
	if str(c.get("volunteer", "")) != "":
		doing.append("volunteers with %s" % LTChoices.VOLUNTEER_KINDS.get(str(c["volunteer"]), "a local group"))
	if bool(c.get("caregiver", false)):
		doing.append("looks after an aging parent")
	if not doing.is_empty():
		t += "Also: %s.\n" % "; ".join(doing)
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
	var notes: Array = []
	if LTJustice.in_jail(ww, c):
		notes.append("[color=#ef6b5b]In the county jail until %s.[/color]" % LTCalendar.short(int(c["jail_until"])))
	elif int(c.get("probation_until", -1)) > ww.day:
		notes.append("On probation until %s." % LTCalendar.short(int(c["probation_until"])))
	var rec: Array = []
	for r2 in c.get("record", []):
		rec.append("%s (%s)" % [LTJustice.CHARGES[r2["charge"]]["label"], LTCalendar.short(int(r2["day"]))])
	if not rec.is_empty() or int(c["theft_record"]) > 0:
		notes.append("Criminal record: %s." % (", ".join(rec) if not rec.is_empty() else "theft"))
	if not c.get("pregnant", {}).is_empty():
		notes.append("Expecting a baby around %s." % LTCalendar.short(int(c["pregnant"]["due"])))
	if int(c.get("leave_until", -1)) > ww.day:
		notes.append("On leave until %s." % LTCalendar.short(int(c["leave_until"])))
	if bool(c.get("depressed", false)):
		notes.append("Struggling with depression.")
	var ad: Dictionary = c.get("addiction", {})
	for k3 in ad:
		if float(ad[k3]) >= 30.0:
			notes.append("%s habit: %d of 100%s." % [{"alcohol": "Drinking", "gambling": "Gambling", "drugs": "Drug"}[k3], int(ad[k3]), ", an addiction" if float(ad[k3]) >= 60.0 else ""])
	if int(c.get("treatment_until", -1)) > ww.day:
		notes.append("In a treatment program until %s." % LTCalendar.short(int(c["treatment_until"])))
	if bool(c.get("disability", false)):
		notes.append("Has a lasting disability from an injury.")
	if int(c.get("mentored_by", -1)) >= 0:
		notes.append("Mentored by %s." % sim_link(int(c["mentored_by"])))
	if not notes.is_empty():
		t += "\n[b]Life right now[/b]\n" + "\n".join(notes) + "\n"
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
	var t: String = "[font_size=19][b]%s[/b][/font_size]\n%s on %s. %s since %s.\n" % [b["name"], str(LTEconomy.tcfg(b["type"])["display"]), lot_link(int(b["lot"])), "Open" if str(b["status"]) == "open" else ("Building, not open yet" if str(b["status"]) == "building" else "Closed " + LTCalendar.short(int(b["closed_day"])) + ": " + str(b["close_reason"])), LTCalendar.short(maxi(1, int(b["opened_day"])))]
	if bool(b.get("home_based", false)):
		t += "Run from the owner's home.\n"
	if b.has("costs"):
		t += "Start up: %s.\n" % LTEconomy.costs_text(b["costs"])
	if str(b["status"]) == "building" and int(b.get("project_id", -1)) >= 0:
		t += "The building: [url=proj:%d]%s[/url].\n" % [int(b["project_id"]), ww.projects[int(b["project_id"])]["title"]]
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
	if bool(b.get("unlicensed", false)):
		t += "[color=#ef6b5b]Running without a business license.[/color]\n"
	if float(b.get("pollution", 0.0)) > 0.05:
		t += "Pollution reaching nearby homes: %.2f.\n" % float(b["pollution"])
	if str(b["type"]) == "bank":
		t += "Loans made: %d.\n" % int(b.get("loans_made", 0))
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
			t += "%s. Condition %d.\n" % [str(l["use"]).capitalize(), int(l["condition"])]
			if l.has("home"):
				t += "The house: %s.\n" % LTGeography.home_text(l["home"])
			for hb in ww.businesses:
				if int(hb["lot"]) == id and bool(hb.get("home_based", false)) and str(hb["status"]) == "open":
					t += "Run from here: %s.\n" % biz_link(int(hb["id"]))
			t += "Who lives here:\n"
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
		"mayor_house":
			t += "The mayor's house. %s lives here.\n" % w().player.get("name", "The mayor")
		"site", "reserved":
			var lp: Dictionary = ww.projects[int(l["ref"])]
			t += "Project: [url=proj:%d]%s[/url].\n" % [int(l["ref"]), lp["title"]]
			if lp.has("home"):
				t += "Being built: %s, %s.\n" % [LTGeography.home_text(lp["home"]), _money(int(lp["raw_cost"]))]
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
	if p.has("spec") and not bool(p["private"]):
		t += "Terms: %s.\n" % LTProjects.spec_text(p)
	if int(p.get("penalty_paid", 0)) > 0:
		t += "Late penalties collected: %s.\n" % _money(int(p["penalty_paid"]))
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


# ================================================================ roads, contracts and lot details

func _road_project(street_id: int) -> int:
	var best: int = -1
	for p in w().projects:
		if int(p["street"]) == street_id and LTProjects.is_road(str(p["ptype"])) and str(p["status"]) != "cancelled":
			best = int(p["id"])
	return best


func _road_text(id: int) -> String:
	var ww: LTWorld = w()
	if id < 0 or id >= ww.streets.size():
		return "No road."
	var st: Dictionary = ww.streets[id]
	var planned: int = 0
	var built: int = 0
	for sid in st["segments"]:
		var sg: Dictionary = ww.roads[int(sid)]
		if bool(sg.get("removed", false)):
			continue
		if bool(sg.get("planned", false)):
			planned += 1
		else:
			built += 1
	var t: String = "[font_size=19][b]%s[/b][/font_size]\n" % st["name"]
	if str(st["kind"]) == "highway":
		return t + "The county road. It runs edge to edge and the county keeps it up. Every trip out of town uses it.\n"
	if built > 0:
		t += "%d %s built. Condition %d of 100, quality %d of 100.\n" % [built, "block" if built == 1 else "blocks", int(LTGeography.street_condition(ww, id)), int(LTGeography.street_quality(ww, id) * 100.0)]
		var feat: Array = []
		if st.has("width"):
			feat.append(str(LTProjects.WIDTHS[str(st["width"])]["label"]))
		if st.has("surface"):
			feat.append(str(LTProjects.SURFACES[str(st["surface"])]["label"]).to_lower())
		if bool(st.get("sidewalks", false)):
			feat.append("sidewalks")
		if bool(st.get("lights", false)):
			feat.append("streetlights")
		if not feat.is_empty():
			t += "Built as: %s.\n" % ", ".join(feat)
	var pid: int = _road_project(id)
	if planned > 0:
		var drafted: bool = pid >= 0 and str(ww.projects[pid]["status"]) == "draft"
		t += "%d %s %s.\n" % [planned, "block" if planned == 1 else "blocks", "drawn on your plan only" if drafted else "staked out and waiting to be built"]
	if pid >= 0:
		var p: Dictionary = ww.projects[pid]
		t += "Project: [url=proj:%d]%s[/url], %s.\n" % [pid, p["title"], _status_words(p)]
	return t


func _status_words(p: Dictionary) -> String:
	match str(p["status"]):
		"draft":
			return "a draft, not out to bid yet"
		"bidding":
			return "out to bid until %s" % LTCalendar.short(int(p["bid_close_day"]))
		"review":
			return "bids are in and waiting for you"
		"building":
			return "being built by %s, %d%% done" % [p["winner_name"], int(float(p["progress"]) * 100.0)]
		"done":
			return "finished %s" % LTCalendar.short(int(p["done_day"]))
	return str(p["status"])


func _road_form(street_id: int) -> void:
	var ww: LTWorld = w()
	if street_id < 0 or street_id >= ww.streets.size() or str(ww.streets[street_id]["kind"]) == "highway":
		return
	var pid: int = _road_project(street_id)
	if pid >= 0 and str(ww.projects[pid]["ptype"]) == "road_build":
		_contract_form(ww.projects[pid])


func _form_row(label: String, ctl: Control) -> void:
	var hb: HBoxContainer = HBoxContainer.new()
	var l: Label = _lbl(label, 14)
	l.custom_minimum_size = Vector2(120, 0)
	hb.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(ctl)
	inspect_form.add_child(hb)


func _opt(items: Array, selected: int, cb: Callable) -> OptionButton:
	var o: OptionButton = OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.select(selected)
	o.item_selected.connect(cb)
	# long choices are trimmed on the button (the full text shows in the list)
	o.clip_text = true
	o.custom_minimum_size = Vector2(120, 0)
	return o


func _edit_project(pid: int, changes: Dictionary) -> void:
	var r: Dictionary = main.act({"kind": "edit_project", "project_id": pid, "changes": changes})
	show_toast(str(r["message"]))
	inspect(inspect_kind, inspect_id)


const DEADLINES: Array = [0, 30, 60, 90, 120, 180, 270, 365]


## The contract the mayor writes before a project is signed: what to build, how
## well, how fast, and the most the city will pay.
func _contract_form(p: Dictionary) -> void:
	var pid: int = int(p["id"])
	var editable: bool = LTProjects.spec_editable(p)
	inspect_form.add_child(_sep())
	inspect_form.add_child(_h("Contract"))
	if not p.has("spec"):
		inspect_form.add_child(_rtl("[color=#9fb0c0]This project was written before contracts had details.[/color]"))
		return
	if bool(p["private"]):
		inspect_form.add_child(_rtl("[color=#9fb0c0]A private job. %s wrote the contract, not the city.[/color]" % str(p["developer"].get("name", "The owner")).capitalize()))
		return
	var sp: Dictionary = p["spec"]
	if str(p["ptype"]) == "road_build":
		var nm: LineEdit = LineEdit.new()
		nm.text = str(w().streets[int(p["street"])]["name"])
		nm.max_length = 40
		nm.text_submitted.connect(func(tx): _edit_project(pid, {"name": tx}))
		nm.focus_exited.connect(func():
			if nm.text != str(w().streets[int(p["street"])]["name"]):
				_edit_project(pid, {"name": nm.text}))
		_form_row("Road name", nm)
	if not editable:
		inspect_form.add_child(_rtl("Terms: %s. Budget ceiling %s.\n[color=#9fb0c0]The contract is signed, so its terms are fixed. Only the name can change.[/color]" % [LTProjects.spec_text(p), _money(int(p["ceiling"]))]))
		return
	if str(p["ptype"]) == "road_build":
		var sk: Array = LTProjects.SURFACES.keys()
		var sl: Array = []
		for k in sk:
			sl.append("%s (%s)" % [LTProjects.SURFACES[k]["label"], LTProjects.SURFACES[k]["note"]])
		_form_row("Surface", _opt(sl, sk.find(str(sp["surface"])), func(i): _edit_project(pid, {"surface": sk[i]})))
		var wk: Array = LTProjects.WIDTHS.keys()
		var wl: Array = []
		for k in wk:
			wl.append(LTProjects.WIDTHS[k]["label"])
		_form_row("Width", _opt(wl, wk.find(str(sp["width"])), func(i): _edit_project(pid, {"width": wk[i]})))
		var sw: CheckBox = CheckBox.new()
		sw.text = "Sidewalks (+%d%%, families like them)" % int(LTProjects.SIDEWALK_COST * 100.0)
		sw.button_pressed = bool(sp["sidewalks"])
		sw.toggled.connect(func(on): _edit_project(pid, {"sidewalks": on}))
		inspect_form.add_child(sw)
		var lt: CheckBox = CheckBox.new()
		lt.text = "Streetlights (+%d%%, safer at night)" % int(LTProjects.LIGHTS_COST * 100.0)
		lt.button_pressed = bool(sp["lights"])
		lt.toggled.connect(func(on): _edit_project(pid, {"lights": on}))
		inspect_form.add_child(lt)
	else:
		var gk: Array = LTProjects.GRADES.keys()
		var gl: Array = []
		for k in gk:
			gl.append(LTProjects.GRADES[k]["label"])
		_form_row("Materials", _opt(gl, gk.find(str(sp.get("grade", "standard"))), func(i): _edit_project(pid, {"grade": gk[i]})))
	var dl: Array = []
	for d in DEADLINES:
		dl.append("No deadline" if int(d) == 0 else "Within %d days" % int(d))
	var di: int = DEADLINES.find(int(sp["deadline"]))
	_form_row("Deadline", _opt(dl, maxi(0, di), func(i): _edit_project(pid, {"deadline": DEADLINES[i]})))
	if int(sp["deadline"]) > 0:
		var pen: CheckBox = CheckBox.new()
		pen.text = "Late penalty (%.1f%% of the price a day, up to 20%%)" % (LTProjects.LATE_PENALTY * 100.0)
		pen.button_pressed = bool(sp["penalty"])
		pen.toggled.connect(func(on): _edit_project(pid, {"penalty": on}))
		inspect_form.add_child(pen)
	var ce: SpinBox = SpinBox.new()
	ce.min_value = 1
	ce.max_value = 100000
	ce.step = 1
	ce.prefix = "$"
	ce.suffix = "k"
	ce.value = roundf(float(int(p["ceiling"])) / 100000.0)
	ce.get_line_edit().text_submitted.connect(func(_tx): ce.apply())
	ce.value_changed.connect(func(v): _edit_project(pid, {"ceiling": int(v) * 100000}))
	_form_row("Budget ceiling", ce)
	var auto: Button = _btn("Use the suggested ceiling", func(): _edit_project(pid, {"ceiling": 0}))
	auto.disabled = not bool(p.get("ceiling_set", false))
	inspect_form.add_child(auto)
	var est: String = "Fair price for these terms: about %s and %d days of work." % [_money(int(p["base_cost"])), int(p["base_days"])]
	if int(sp["deadline"]) > 0 and int(sp["deadline"]) < int(p["base_days"]):
		est += " The deadline is tighter than that, so expect rush pricing."
	if str(p["status"]) == "draft":
		est += "\n[color=#e8c35a]Draft. Contractors cannot see this until you press Go live. Bidding then runs %d days.[/color]" % LTProjects.BID_DAYS
	elif str(p["status"]) == "review":
		est += "\n[color=#e8c35a]Bids are in. Changing a term sends it back out to bid.[/color]"
	else:
		est += "\nBids close %s." % LTCalendar.short(int(p["bid_close_day"]))
	inspect_form.add_child(_rtl(est))
	if str(p["status"]) == "draft":
		var gl: Button = _go_live_btn(pid)
		gl.custom_minimum_size = Vector2(0, 44)
		inspect_form.add_child(gl)
	var hb: HBoxContainer = HBoxContainer.new()
	if str(p["status"]) == "review":
		hb.add_child(_btn("See the bids", func():
			_show_tab("Projects")))
	hb.add_child(_btn("Delete draft" if str(p["status"]) == "draft" else "Cancel project", func():
		show_toast(str(main.act({"kind": "cancel_project", "project_id": pid})["message"]))
		inspect(inspect_kind, inspect_id)))
	inspect_form.add_child(hb)


func _go_live_btn(pid: int) -> Button:
	var b: Button = _btn("Go live", func():
		var r: Dictionary = main.act({"kind": "go_live", "project_id": pid})
		show_toast(str(r["message"]))
		if bool(r.get("ok", false)):
			main.sound.chime("good")
		inspect(inspect_kind, inspect_id)
		refresh_tab(), "Send this contract out to bid. Contractors will see it and bid on these terms.")
	b.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.36, 0.78, 0.45)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	b.add_theme_stylebox_override("normal", sb)
	var sbh: StyleBoxFlat = sb.duplicate()
	sbh.bg_color = Color(0.45, 0.86, 0.54)
	b.add_theme_stylebox_override("hover", sbh)
	return b


const PRICE_PCTS: Array = [50, 75, 100, 125, 150, 200]


## Details of city lots the mayor still owns: zone, asking price, hold, name.
## Lots plotted in one stroke can be changed together.
func _lot_form(id: int) -> void:
	var ww: LTWorld = w()
	var l: Dictionary = ww.lot(id)
	if l.is_empty() or str(l["owner_kind"]) != "city" or not ["empty", "closed"].has(str(l["use"])):
		return
	var group: Array = LTGeography.plot_group_lots(ww, int(l.get("plot_group", 0)))
	inspect_form.add_child(_sep())
	inspect_form.add_child(_h("Lot details"))
	var all: CheckBox = CheckBox.new()
	all.text = "Apply to all %d lots plotted together" % group.size()
	all.button_pressed = _lot_all
	all.visible = group.size() > 1
	all.toggled.connect(func(on): _lot_all = on)
	inspect_form.add_child(all)
	var ids: Callable = func() -> Array: return group if (_lot_all and group.size() > 1) else [id]
	var zs: Array = []
	for z in LTGeography.ZONES:
		zs.append(z)
	_form_row("Zone", _opt(zs, zs.find(str(l["zone"])), func(i): _edit_lots(ids.call(), {"zone": zs[i]})))
	var pl: Array = []
	for pc in PRICE_PCTS:
		pl.append("%d%% of value (%s)" % [int(pc), _money(int(float(l["value"]) * float(pc) / 100.0))])
	var pi: int = PRICE_PCTS.find(int(l.get("price_pct", 100)))
	_form_row("Asking price", _opt(pl, maxi(0, pi), func(i): _edit_lots(ids.call(), {"price_pct": PRICE_PCTS[i]})))
	var hold: CheckBox = CheckBox.new()
	hold.text = "Hold for the city (not for sale or lease)"
	hold.button_pressed = bool(l.get("hold", false))
	hold.toggled.connect(func(on): _edit_lots(ids.call(), {"hold": on}))
	inspect_form.add_child(hold)
	var nm: LineEdit = LineEdit.new()
	nm.text = str(l["name"])
	nm.placeholder_text = "a name for the map, optional"
	nm.max_length = 40
	nm.text_submitted.connect(func(tx): _edit_lots([id], {"name": tx}))
	nm.focus_exited.connect(func():
		if nm.text != str(w().lot(id)["name"]):
			_edit_lots([id], {"name": nm.text}))
	_form_row("Name", nm)
	var note: String = "Cheaper lots sell first. Above full value, many families keep looking."
	if str(l["zone"]) == "commercial":
		note += " A business here would lease it for %s a month." % _money(LTCivic.lot_rent(ww, id))
	inspect_form.add_child(_rtl("[color=#9fb0c0]%s[/color]" % note))
	inspect_form.add_child(_btn("Return to prairie", func():
		var r: Dictionary = main.act({"kind": "unplot", "lot": id})
		show_toast(str(r["message"]))
		if bool(r.get("ok", false)):
			right.visible = false
			main.view.select_lot(-1)
		else:
			inspect("lot", id)))


var _lot_all: bool = true


func _edit_lots(ids: Array, changes: Dictionary) -> void:
	var r: Dictionary = main.act({"kind": "edit_lots", "lots": ids, "changes": changes})
	show_toast(str(r["message"]))
	inspect(inspect_kind, inspect_id)


func _show_tab(name: String) -> void:
	left.visible = true
	tabs.current_tab = maxi(0, TABS.find(name))
	refresh_tab()


## A card where the player says who they are, any time during the game.
func show_profile() -> void:
	var ww: LTWorld = w()
	var pl: Dictionary = ww.player
	var card: PanelContainer = PanelContainer.new()
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -230
	card.offset_right = 230
	card.offset_top = -190
	card.offset_bottom = 190
	root.add_child(card)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	card.add_child(vb)
	vb.add_child(_h("Your profile"))
	var rows: GridContainer = GridContainer.new()
	rows.columns = 2
	vb.add_child(rows)
	var add: Callable = func(label: String, ctl: Control) -> void:
		rows.add_child(_lbl(label, 14))
		ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows.add_child(ctl)
	var nm: LineEdit = LineEdit.new()
	nm.text = str(pl["name"])
	nm.max_length = 40
	add.call("Name", nm)
	var pk: Array = ["they", "she", "he"]
	var pron: OptionButton = _opt(["they/them", "she/her", "he/him"], maxi(0, pk.find(str(pl.get("pronouns", "they")))), func(_i): pass)
	add.call("Pronouns", pron)
	var age: SpinBox = SpinBox.new()
	age.min_value = 18
	age.max_value = 99
	age.value = ww.player_age()
	add.call("Age", age)
	var home: LineEdit = LineEdit.new()
	home.text = str(pl.get("hometown", ""))
	home.max_length = 40
	add.call("Hometown", home)
	var ck: Array = LTWorld.PLAYER_COLORS.keys()
	var col: OptionButton = _opt(ck.map(func(k): return str(k).capitalize()), maxi(0, ck.find(str(pl.get("color", "blue")))), func(_i): pass)
	add.call("Your color", col)
	var tn: LineEdit = LineEdit.new()
	tn.text = str(ww.city["name"])
	tn.max_length = 40
	add.call("Town name", tn)
	vb.add_child(_lbl("Your color trims the camper and the mayor's house.", 13, Color(0.7, 0.75, 0.8)))
	var hb: HBoxContainer = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_child(_btn("Cancel", func(): card.queue_free()))
	hb.add_child(_btn("Save", func():
		var r: Dictionary = main.act({"kind": "set_profile", "name": nm.text, "pronouns": pk[pron.selected], "age": int(age.value), "hometown": home.text, "color": ck[col.selected], "town_name": tn.text})
		show_toast(str(r["message"]))
		card.queue_free()
		refresh_all()))
	vb.add_child(hb)
