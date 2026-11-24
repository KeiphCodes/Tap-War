extends Control
## The drawing on a building permit: a site plan of the lot (house, garage, drive,
## deck, shed) with the street at the bottom, then each floor room by room.

const INK: Color = Color(0.17, 0.14, 0.1)
const SOFT: Color = Color(0.45, 0.4, 0.33)
const FILL: Color = Color(0.97, 0.94, 0.86)
const WIDTH: float = 330.0

var lot: Dictionary = {}
var spec: Dictionary = {}
var _lay: Dictionary = {}
var _plan: Array = []
var _site_h: float = 0.0
var _floor_h: Array = []


func set_plan(l: Dictionary, s: Dictionary) -> void:
	lot = l
	spec = LTHomes.upgrade(s)
	_lay = LTHomes.layout(lot, spec)
	_plan = LTHomes.plan(lot, spec)
	var fw: float = LTGeography.lot_frontage(lot)
	var dp: float = LTGeography.lot_depth(lot)
	var sc: float = minf((WIDTH - 20.0) / fw, 220.0 / dp)
	_site_h = dp * sc + 60.0
	_floor_h.clear()
	var total: float = _site_h
	for f in _plan:
		var fs: float = (WIDTH - 20.0) / maxf(1.0, float(f["W"]))
		var h: float = float(f["D"]) * fs + 34.0
		_floor_h.append(h)
		total += h
	custom_minimum_size = Vector2(WIDTH, total + 6.0)
	queue_redraw()


func _font() -> Font:
	return ThemeDB.fallback_font


func _text(p: Vector2, s: String, size: int = 11, c: Color = INK) -> void:
	draw_string(_font(), p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)


func _text_c(r: Rect2, s: String, size: int = 10) -> void:
	var f: Font = _font()
	var tw: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if tw > r.size.x - 2.0:
		# shorten long names to fit a small room
		var words: PackedStringArray = s.split(" ")
		s = words[words.size() - 1]
		tw = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if tw > r.size.x - 2.0:
			return
	draw_string(f, Vector2(r.position.x + (r.size.x - tw) * 0.5, r.position.y + r.size.y * 0.5 + size * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, INK)


func _draw() -> void:
	if lot.is_empty():
		return
	var fw: float = LTGeography.lot_frontage(lot)
	var dp: float = LTGeography.lot_depth(lot)
	var sc: float = minf((WIDTH - 20.0) / fw, 220.0 / dp)
	var ox: float = 10.0 + ((WIDTH - 20.0) - fw * sc) * 0.5
	var top: float = 18.0
	_text(Vector2(10, 12), "SITE PLAN  %d x %d ft lot" % [int(fw * 3.28), int(dp * 3.28)], 11, SOFT)
	# the street is at the bottom of the drawing: d = 0 is the front line
	var to_px: Callable = func(r: Array) -> Rect2:
		var x0: float = ox + (float(r[0]) + fw * 0.5) * sc
		var x1: float = ox + (float(r[2]) + fw * 0.5) * sc
		var y0: float = top + (dp - float(r[3])) * sc
		var y1: float = top + (dp - float(r[1])) * sc
		return Rect2(x0, y0, x1 - x0, y1 - y0)
	draw_rect(Rect2(ox, top, fw * sc, dp * sc), Color(0.88, 0.92, 0.8), true)
	draw_rect(Rect2(ox, top, fw * sc, dp * sc), SOFT, false, 1.0)
	for k in ["fence"]:
		if _lay.has(k):
			draw_rect(to_px.call(_lay[k]), SOFT, false, 1.0)
	var parts: Array = [["drive", Color(0.8, 0.8, 0.78), ""], ["patio", Color(0.82, 0.8, 0.75), "patio"], ["deck", Color(0.78, 0.66, 0.5), "deck"],
		["garden", Color(0.6, 0.48, 0.34), "garden"], ["pool", Color(0.6, 0.8, 0.95), "pool"], ["shed", Color(0.8, 0.68, 0.58), "shed"],
		["greenhouse", Color(0.85, 0.95, 0.95), "green\nhouse"], ["shelter", Color(0.7, 0.74, 0.66), "shelter"], ["porch", Color(0.85, 0.78, 0.66), "porch"],
		["garage", FILL, "garage"], ["house", FILL, "house"]]
	for pt in parts:
		if _lay.has(pt[0]):
			var r: Rect2 = to_px.call(_lay[pt[0]])
			draw_rect(r, pt[1], true)
			draw_rect(r, INK, false, 1.5 if pt[0] == "house" or pt[0] == "garage" else 1.0)
			if str(pt[2]) != "":
				_text_c(r, str(pt[2]).replace("\n", ""), 9)
	var sy: float = top + dp * sc
	draw_line(Vector2(ox - 6, sy + 6), Vector2(ox + fw * sc + 6, sy + 6), INK, 2.0)
	_text(Vector2(ox, sy + 20), "STREET", 10, SOFT)
	_text(Vector2(ox, sy + 34), "house set back %d ft from the street" % int(float(_lay["house"][1]) * 3.28), 10, SOFT)
	# floors
	var y: float = _site_h
	for i in _plan.size():
		var f: Dictionary = _plan[i]
		var fs: float = (WIDTH - 20.0) / maxf(1.0, float(f["W"]))
		var D: float = float(f["D"])
		_text(Vector2(10, y + 12), str(f["name"]).to_upper(), 11, SOFT)
		var fy: float = y + 18.0
		draw_rect(Rect2(10, fy, float(f["W"]) * fs, D * fs), FILL, true)
		for r in f["rects"]:
			# front of the house at the bottom, like the site plan
			var rr: Rect2 = Rect2(10.0 + float(r[0]) * fs, fy + (D - float(r[3])) * fs, (float(r[2]) - float(r[0])) * fs, (float(r[3]) - float(r[1])) * fs)
			draw_rect(rr, INK, false, 1.0)
			_text_c(rr, LTHomes.room_label(str(r[4])), 10)
		draw_rect(Rect2(10, fy, float(f["W"]) * fs, D * fs), INK, false, 2.0)
		y += float(_floor_h[i])
