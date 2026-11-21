extends Control
## A small line chart for the city dashboard.

var title: String = ""
var values: Array = []
var color: Color = Color(0.45, 0.75, 1.0)
var fmt: Callable


func set_data(p_title: String, p_values: Array, p_color: Color, p_fmt: Callable) -> void:
	title = p_title
	values = p_values
	color = p_color
	fmt = p_fmt
	queue_redraw()


func _draw() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.08, 0.09, 0.11, 0.9))
	var font: Font = get_theme_default_font()
	var last_txt: String = ""
	if not values.is_empty() and fmt.is_valid():
		last_txt = str(fmt.call(values[values.size() - 1]))
	draw_string(font, Vector2(8, 16), "%s  %s" % [title, last_txt], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.88, 0.92))
	if values.size() < 2:
		draw_string(font, Vector2(8, size.y - 10), "Shows after the first two months.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.62, 0.66))
		return
	var lo: float = 1e18
	var hi: float = -1e18
	for v in values:
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	if hi - lo < 0.0001:
		hi = lo + 1.0
	var top: float = 24.0
	var bottom: float = size.y - 8.0
	var pts: PackedVector2Array = PackedVector2Array()
	for i in values.size():
		var x: float = 8.0 + (size.x - 16.0) * float(i) / float(values.size() - 1)
		var y: float = bottom - (float(values[i]) - lo) / (hi - lo) * (bottom - top)
		pts.append(Vector2(x, y))
	draw_polyline(pts, color, 2.0, true)
	draw_circle(pts[pts.size() - 1], 3.0, color)
