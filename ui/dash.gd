extends Control
## Dashboard widgets drawn in one place so they share a look: a KPI tile with the
## change since last month and a sparkline, a line/area chart with a hover
## crosshair, a donut with a legend, and stacked horizontal bars.
##
## Colors follow a validated dark palette (categorical slots in a fixed order,
## status colors only with an icon). Text always uses the text inks, never a
## series color; the colored mark beside it carries the identity.

const SURFACE: Color = Color("1b2230")
const BORDER: Color = Color("2a3446")
const GRID: Color = Color("263044")
const TEXT: Color = Color("e8edf4")
const TEXT_2: Color = Color("93a1b5")
const GOOD: Color = Color("0aac23")
const BAD: Color = Color("eb6263")
const SERIES: Array = [Color("338ced"), Color("e76624"), Color("00a888"), Color("d28e05"), Color("e24d8b"), Color("0aac23"), Color("9887ef"), Color("eb6263")]

var kind: String = ""
var title: String = ""
var values: Array = []        # numbers, oldest first
var labels: Array = []        # x labels (line) or category names (donut, bars)
var parts: Array = []         # bars: [[a, b], ...]; donut: [v, ...]
var part_names: Array = []
var fmt: Callable
var higher_is_better: bool = true
var color: Color = SERIES[0]
var _hover: int = -1
var _plot: Rect2 = Rect2()
var info: Dictionary = {}     # biz card: everything it shows
signal pressed
var _press_at: Vector2 = Vector2(-1, -1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_exited.connect(func():
		_hover = -1
		queue_redraw())


func _f(v) -> String:
	return str(fmt.call(v)) if fmt.is_valid() else str(v)


func _font() -> Font:
	return get_theme_default_font()


func _text(p: Vector2, s: String, size: int, c: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	draw_string(_font(), p, s, align, width, size, c)


func _card() -> void:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = SURFACE
	sb.border_color = BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	draw_style_box(sb, Rect2(Vector2.ZERO, size))


# ---------------------------------------------------------------- setup

func as_kpi(p_title: String, p_values: Array, p_fmt: Callable, p_higher_is_better: bool = true, p_color: Color = SERIES[0]) -> void:
	kind = "kpi"
	title = p_title
	values = p_values
	fmt = p_fmt
	higher_is_better = p_higher_is_better
	color = p_color
	custom_minimum_size = Vector2(0, 108)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_redraw()


func as_line(p_title: String, p_values: Array, p_labels: Array, p_fmt: Callable, p_color: Color = SERIES[0]) -> void:
	kind = "line"
	title = p_title
	values = p_values
	labels = p_labels
	fmt = p_fmt
	color = p_color
	custom_minimum_size = Vector2(0, 190)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_redraw()


func as_donut(p_title: String, p_values: Array, p_names: Array, p_fmt: Callable) -> void:
	kind = "donut"
	title = p_title
	parts = p_values
	part_names = p_names
	fmt = p_fmt
	custom_minimum_size = Vector2(0, 176)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_redraw()


## rows: [[name, a, b], ...]; two stacked series named by p_series.
func as_bars(p_title: String, rows: Array, p_series: Array, p_fmt: Callable) -> void:
	kind = "bars"
	title = p_title
	labels = []
	parts = []
	for r in rows:
		labels.append(str(r[0]))
		parts.append([float(r[1]), float(r[2])])
	part_names = p_series
	fmt = p_fmt
	custom_minimum_size = Vector2(0, 64 + 30 * maxi(1, rows.size()))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_redraw()


## A clickable card for one business. info: name, kind, where, status, owner,
## revenue (last months), profit (last months), staff, target, reputation, since.
func as_biz(p_info: Dictionary) -> void:
	kind = "biz"
	info = p_info
	values = info.get("revenue", [])
	fmt = info.get("fmt", Callable())
	color = SERIES[0]
	custom_minimum_size = Vector2(0, 184)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Open everything about %s" % info.get("name", "this business")
	queue_redraw()


# ---------------------------------------------------------------- hover

func _gui_input(ev: InputEvent) -> void:
	if kind == "biz":
		# a tap opens it; a drag scrolls the list instead
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var mb: InputEventMouseButton = ev
			if mb.pressed:
				_press_at = mb.position
			elif _press_at.x >= 0.0 and mb.position.distance_to(_press_at) < 14.0:
				_press_at = Vector2(-1, -1)
				pressed.emit()
		elif ev is InputEventMouseMotion:
			var hv: int = 0 if Rect2(Vector2.ZERO, size).has_point((ev as InputEventMouseMotion).position) else -1
			if hv != _hover:
				_hover = hv
				queue_redraw()
		return
	if ev is InputEventMouseMotion:
		var h: int = -1
		var p: Vector2 = (ev as InputEventMouseMotion).position
		if kind == "line" and values.size() >= 2 and _plot.grow(6.0).has_point(p):
			h = clampi(int(round((p.x - _plot.position.x) / _plot.size.x * float(values.size() - 1))), 0, values.size() - 1)
		elif kind == "bars":
			var i: int = int((p.y - 52.0) / 30.0)
			if p.y >= 52.0 and i >= 0 and i < parts.size():
				h = i
		if h != _hover:
			_hover = h
			queue_redraw()


func _tooltip(at: Vector2, lines: Array) -> void:
	var w: float = 0.0
	for ln in lines:
		w = maxf(w, _font().get_string_size(str(ln), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)
	var box: Rect2 = Rect2(at + Vector2(10, -10), Vector2(w + 16, 8 + 18 * lines.size()))
	if box.end.x > size.x - 4:
		box.position.x = at.x - box.size.x - 10
	box.position.y = clampf(box.position.y, 4, maxf(4.0, size.y - box.size.y - 4))
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color("0f141c")
	sb.border_color = BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	draw_style_box(sb, box)
	for i in lines.size():
		_text(box.position + Vector2(8, 18 + 18 * i), str(lines[i]), 13, TEXT if i > 0 else TEXT_2)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	match kind:
		"kpi":
			_draw_kpi()
		"line":
			_draw_line()
		"donut":
			_draw_donut()
		"bars":
			_draw_bars()
		"biz":
			_draw_biz()


func _draw_kpi() -> void:
	_card()
	_text(Vector2(14, 24), title, 13, TEXT_2)
	if values.is_empty():
		_text(Vector2(14, 60), "-", 28, TEXT)
		return
	var now = values[values.size() - 1]
	_text(Vector2(14, 60), _f(now), 28, TEXT)
	# change since last month: a triangle in the status color, the words in text ink
	if values.size() >= 2:
		var prev = values[values.size() - 2]
		var d: float = float(now) - float(prev)
		if absf(d) > 0.0001 and _f(now) != _f(prev):
			var up: bool = d > 0.0
			var good: bool = up == higher_is_better
			var c: Color = GOOD if good else BAD
			var tri: PackedVector2Array = PackedVector2Array([Vector2(14, 84), Vector2(24, 84), Vector2(19, 76)]) if up else PackedVector2Array([Vector2(14, 76), Vector2(24, 76), Vector2(19, 84)])
			draw_colored_polygon(tri, c)
			_text(Vector2(30, 85), "%s%s vs last month" % ["+" if up else "-", _f(absf(d))], 12, TEXT_2)
		else:
			_text(Vector2(14, 85), "no change vs last month", 12, TEXT_2)
	# a sparkline of the last year along the right, when it clears the number
	var vw: float = _font().get_string_size(_f(now), HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	if values.size() >= 3 and 14.0 + vw + 10.0 < size.x - 96.0:
		var n: int = mini(12, values.size())
		var vs: Array = values.slice(values.size() - n)
		var lo: float = 1e18
		var hi: float = -1e18
		for v in vs:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
		if hi - lo < 0.0001:
			hi = lo + 1.0
		var r: Rect2 = Rect2(size.x - 96, 34, 82, 30)
		var pts: PackedVector2Array = PackedVector2Array()
		for i in vs.size():
			pts.append(Vector2(r.position.x + r.size.x * float(i) / float(vs.size() - 1), r.end.y - (float(vs[i]) - lo) / (hi - lo) * r.size.y))
		draw_polyline(pts, color, 2.0, true)
		draw_circle(pts[pts.size() - 1], 3.0, color)


func _draw_line() -> void:
	_card()
	_text(Vector2(14, 24), title, 15, TEXT)
	if values.size() < 2:
		_text(Vector2(14, 60), "Fills in after the first two months.", 13, TEXT_2)
		return
	_text(Vector2(0, 24), _f(values[values.size() - 1]), 15, TEXT, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 14)
	var lo: float = 1e18
	var hi: float = -1e18
	for v in values:
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	if hi - lo < 0.0001:
		hi = lo + 1.0
	var pad: float = (hi - lo) * 0.1
	lo -= pad
	hi += pad
	var left: float = 64.0
	_plot = Rect2(left, 40, size.x - left - 16, size.y - 40 - 30)
	# recessive grid with three value labels
	for k in 3:
		var fy: float = float(k) / 2.0
		var y: float = _plot.end.y - fy * _plot.size.y
		draw_line(Vector2(_plot.position.x, y), Vector2(_plot.end.x, y), GRID, 1.0)
		_text(Vector2(0, y + 4), _f(lo + (hi - lo) * fy), 11, TEXT_2, HORIZONTAL_ALIGNMENT_RIGHT, left - 8)
	var pts: PackedVector2Array = PackedVector2Array()
	for i in values.size():
		pts.append(Vector2(_plot.position.x + _plot.size.x * float(i) / float(values.size() - 1), _plot.end.y - (float(values[i]) - lo) / (hi - lo) * _plot.size.y))
	# soft area under the line
	var area: PackedVector2Array = pts.duplicate()
	area.append(Vector2(_plot.end.x, _plot.end.y))
	area.append(Vector2(_plot.position.x, _plot.end.y))
	var fill: Color = color
	fill.a = 0.14
	draw_colored_polygon(area, fill)
	draw_polyline(pts, color, 2.0, true)
	var last: Vector2 = pts[pts.size() - 1]
	draw_circle(last, 6.0, SURFACE)
	draw_circle(last, 4.0, color)
	# first and last month under the plot
	if labels.size() == values.size():
		_text(Vector2(_plot.position.x, size.y - 10), str(labels[0]), 11, TEXT_2)
		_text(Vector2(0, size.y - 10), str(labels[labels.size() - 1]), 11, TEXT_2, HORIZONTAL_ALIGNMENT_RIGHT, _plot.end.x)
	if _hover >= 0 and _hover < pts.size():
		var hp: Vector2 = pts[_hover]
		draw_line(Vector2(hp.x, _plot.position.y), Vector2(hp.x, _plot.end.y), TEXT_2, 1.0)
		draw_circle(hp, 6.0, SURFACE)
		draw_circle(hp, 4.0, color)
		_tooltip(hp, [str(labels[_hover]) if _hover < labels.size() else "", "%s: %s" % [title, _f(values[_hover])]])


func _draw_donut() -> void:
	_card()
	_text(Vector2(14, 24), title, 15, TEXT)
	var total: float = 0.0
	for v in parts:
		total += float(v)
	var c: Vector2 = Vector2(84, 100)
	var r_out: float = 58.0
	var r_in: float = 38.0
	if total <= 0.0:
		draw_arc(c, (r_out + r_in) * 0.5, 0.0, TAU, 64, GRID, r_out - r_in, true)
	else:
		var a: float = -PI * 0.5
		var gap: float = 0.03 if parts.size() > 1 else 0.0
		for i in parts.size():
			var sweep: float = TAU * float(parts[i]) / total
			if sweep <= 0.0:
				continue
			var a0: float = a + gap * 0.5
			var a1: float = a + sweep - gap * 0.5
			if a1 > a0:
				draw_arc(c, (r_out + r_in) * 0.5, a0, a1, maxi(8, int(sweep * 24.0)), SERIES[i % SERIES.size()], r_out - r_in, true)
			a += sweep
	_text(Vector2(c.x - 50, c.y + 6), _f(total), 20, TEXT, HORIZONTAL_ALIGNMENT_CENTER, 100)
	# legend: swatch, name, value and share
	var lx: float = 168.0
	for i in parts.size():
		var y: float = 58.0 + 26.0 * i
		draw_rect(Rect2(lx, y - 10, 12, 12), SERIES[i % SERIES.size()])
		_text(Vector2(lx + 20, y), str(part_names[i]), 13, TEXT)
		var share: String = "%d%%" % int(round(float(parts[i]) / total * 100.0)) if total > 0.0 else ""
		_text(Vector2(0, y), "%s  %s" % [_f(parts[i]), share], 13, TEXT_2, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 14)


func _draw_bars() -> void:
	_card()
	_text(Vector2(14, 24), title, 15, TEXT)
	# legend in one row under the title
	var lx: float = 14.0
	for i in part_names.size():
		draw_rect(Rect2(lx, 34, 10, 10), SERIES[i])
		_text(Vector2(lx + 16, 44), str(part_names[i]), 12, TEXT_2)
		lx += 26.0 + _font().get_string_size(str(part_names[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	if parts.is_empty():
		_text(Vector2(14, 76), "Fills in after the first month.", 13, TEXT_2)
		return
	var mx: float = 1.0
	for p in parts:
		mx = maxf(mx, float(p[0]) + float(p[1]))
	var name_w: float = 132.0
	var val_w: float = 70.0
	var bw: float = size.x - name_w - val_w - 28.0
	for i in parts.size():
		var y: float = 52.0 + 30.0 * i
		if i == _hover:
			draw_rect(Rect2(6, y, size.x - 12, 28), Color(1, 1, 1, 0.04))
		_text(Vector2(14, y + 19), str(labels[i]), 12, TEXT, HORIZONTAL_ALIGNMENT_LEFT, name_w - 8)
		var x: float = 14.0 + name_w
		for k in 2:
			var w: float = bw * float(parts[i][k]) / mx
			if w >= 1.0:
				var sb: StyleBoxFlat = StyleBoxFlat.new()
				sb.bg_color = SERIES[k]
				sb.corner_radius_top_right = 4 if k == 1 or float(parts[i][1]) <= 0.0 else 0
				sb.corner_radius_bottom_right = sb.corner_radius_top_right
				draw_style_box(sb, Rect2(x, y + 7, maxf(1.0, w - 2.0), 14))
				x += w
		_text(Vector2(0, y + 19), _f(float(parts[i][0]) + float(parts[i][1])), 12, TEXT_2, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 14)
	if _hover >= 0 and _hover < parts.size():
		var hy: float = 52.0 + 30.0 * _hover
		_tooltip(Vector2(14.0 + name_w + bw * 0.5, hy + 14), [str(labels[_hover]), "%s: %s" % [part_names[0], _f(parts[_hover][0])], "%s: %s" % [part_names[1], _f(parts[_hover][1])]])


func _draw_biz() -> void:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = SURFACE.lightened(0.04) if _hover == 0 else SURFACE
	sb.border_color = SERIES[0] if _hover == 0 else BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
	var st: String = str(info.get("status", "open"))
	# status pill: a colored dot and the word, never the color alone
	var pill_txt: String = {"open": "Open", "building": "Being built", "closed": "Closed"}.get(st, st.capitalize())
	var pill_c: Color = {"open": GOOD, "building": SERIES[3], "closed": TEXT_2}.get(st, TEXT_2)
	var pw: float = _font().get_string_size(pill_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 26.0
	var pill: StyleBoxFlat = StyleBoxFlat.new()
	pill.bg_color = Color("0f141c")
	pill.set_corner_radius_all(10)
	draw_style_box(pill, Rect2(size.x - pw - 12, 12, pw, 22))
	draw_circle(Vector2(size.x - pw - 1, 23), 4.0, pill_c)
	_text(Vector2(size.x - pw + 8, 28), pill_txt, 12, TEXT)
	_text(Vector2(14, 28), str(info.get("name", "")), 16, TEXT, HORIZONTAL_ALIGNMENT_LEFT, size.x - pw - 34)
	_text(Vector2(14, 48), str(info.get("kind", "")), 12, TEXT_2, HORIZONTAL_ALIGNMENT_LEFT, size.x - 28)
	_text(Vector2(14, 66), "Owner %s" % info.get("owner", ""), 12, TEXT_2, HORIZONTAL_ALIGNMENT_LEFT, size.x - 28)
	# three numbers across
	var rev: Array = info.get("revenue", [])
	var prof: Array = info.get("profit", [])
	var cols: Array = [
		["Revenue", _f(rev[rev.size() - 1]) if not rev.is_empty() else "-", rev],
		["Profit", _f(prof[prof.size() - 1]) if not prof.is_empty() else "-", prof],
		["Staff", "Owner only" if int(info.get("staff", 0)) == 0 and int(info.get("target", 0)) == 0 else "%d of %d" % [int(info.get("staff", 0)), int(info.get("target", 0))], []],
	]
	var cw: float = (size.x - 28.0) / 3.0
	for i in 3:
		var x: float = 14.0 + cw * float(i)
		_text(Vector2(x, 92), str(cols[i][0]), 11, TEXT_2)
		_text(Vector2(x, 116), str(cols[i][1]), 18, TEXT, HORIZONTAL_ALIGNMENT_LEFT, cw - 6)
		var arr: Array = cols[i][2]
		if arr.size() >= 2:
			var d: float = float(arr[arr.size() - 1]) - float(arr[arr.size() - 2])
			if absf(d) > 0.5:
				var tri: PackedVector2Array = PackedVector2Array([Vector2(x, 130), Vector2(x + 8, 130), Vector2(x + 4, 124)]) if d > 0.0 else PackedVector2Array([Vector2(x, 124), Vector2(x + 8, 124), Vector2(x + 4, 130)])
				draw_colored_polygon(tri, GOOD if d > 0.0 else BAD)
				_text(Vector2(x + 12, 131), "vs month before", 10, TEXT_2)
	# reputation bar and a revenue sparkline along the bottom
	var rep: float = clampf(float(info.get("reputation", 50.0)) / 100.0, 0.0, 1.0)
	_text(Vector2(14, 156), "Reputation", 11, TEXT_2)
	var bar: Rect2 = Rect2(84, 148, size.x * 0.38 - 70, 8)
	draw_rect(bar, GRID)
	if rep > 0.0:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * rep, bar.size.y)), SERIES[0])
	_text(Vector2(14, 174), str(info.get("since", "")), 11, TEXT_2, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.55)
	if rev.size() >= 3:
		var vs: Array = rev.slice(maxi(0, rev.size() - 12))
		var lo: float = 1e18
		var hi: float = -1e18
		for v in vs:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
		if hi - lo < 0.0001:
			hi = lo + 1.0
		var r: Rect2 = Rect2(size.x * 0.58, 142, size.x * 0.42 - 16, 30)
		var pts: PackedVector2Array = PackedVector2Array()
		for i in vs.size():
			pts.append(Vector2(r.position.x + r.size.x * float(i) / float(vs.size() - 1), r.end.y - (float(vs[i]) - lo) / (hi - lo) * r.size.y))
		draw_polyline(pts, SERIES[0], 2.0, true)
		draw_circle(pts[pts.size() - 1], 3.0, SERIES[0])
