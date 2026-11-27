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


# ---------------------------------------------------------------- hover

func _gui_input(ev: InputEvent) -> void:
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
	# a sparkline of the last year along the right
	if values.size() >= 3:
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
