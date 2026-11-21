extends Node3D
## Game controller: owns the world, runs time at the chosen speed, connects the 3D
## view and the mayor UI. The daily truth always runs a full tick per day; speed only
## changes how much of it the player watches.

const SPEEDS: Array = [
	{"name": "Pause", "days": 0, "seconds": 0.0},
	{"name": "Watch", "days": 1, "seconds": 120.0},
	{"name": "Normal", "days": 1, "seconds": 3.0},
	{"name": "Fast", "days": 7, "seconds": 1.6},
	{"name": "Turbo", "days": 30, "seconds": 2.0},
]
const SAVE_PATH: String = "user://living_town.ltsave"

var world: LTWorld = LTWorld.new()
var speed: int = 0
var hour: float = 9.0
var _accum: float = 0.0
var view: Node3D
var hud: CanvasLayer
var sound: Node
var interrupt_kinds: Dictionary = {"bankruptcy": true, "death": true, "business": true, "petition": true, "city": true, "project": true, "estate": true, "protest": true, "crime": true, "region": true, "election": true, "health": true}
var _pending_interrupt: Array = []
var last_fast_speed: int = 2


func _ready() -> void:
	world.new_town(int(Time.get_unix_time_from_system()) % 1000000)
	view = preload("res://town/view.gd").new()
	view.name = "TownView"
	add_child(view)
	view.setup(self)
	sound = preload("res://ui/sound.gd").new()
	add_child(sound)
	hud = preload("res://ui/hud.gd").new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(self)
	view.refresh_all()
	hud.refresh_all()


func new_town(seed_value: int) -> void:
	world = LTWorld.new()
	world.new_town(seed_value)
	speed = 0
	hour = 9.0
	view.rebuild()
	hud.on_new_world()


func save_game() -> String:
	var err: Error = world.save_to_file(SAVE_PATH)
	return "Saved on %s." % LTCalendar.short(world.day) if err == OK else "Save failed: %s" % error_string(err)


func load_game() -> String:
	if not FileAccess.file_exists(SAVE_PATH):
		return "No save found yet."
	var w: LTWorld = LTWorld.new()
	var err: Error = w.load_from_file(SAVE_PATH)
	if err != OK:
		return "Could not load the save: %s" % error_string(err)
	world = w
	speed = 0
	view.rebuild()
	hud.on_new_world()
	return "Loaded the town on %s." % LTCalendar.short(world.day)


func set_speed(i: int) -> void:
	speed = clampi(i, 0, SPEEDS.size() - 1)
	_accum = 0.0
	hud.refresh_top()


func act(a: Dictionary) -> Dictionary:
	var r: Dictionary = world.apply_action(a)
	view.refresh_all()
	hud.refresh_all()
	return r


func _process(delta: float) -> void:
	sound.weather = world.weather
	sound.daytime = hour > 6.0 and hour < 20.0
	var sp: Dictionary = SPEEDS[speed]
	if int(sp["days"]) == 0:
		view.animate(delta, hour, false)
		return
	_accum += delta
	if speed == 1:
		# watch: hours pass visibly, one day in about two minutes
		hour += delta / float(sp["seconds"]) * 24.0
		if hour >= 24.0:
			hour -= 24.0
			_advance(1)
		view.animate(delta, hour, true)
		hud.refresh_clock()
		return
	hour = 13.0
	view.animate(delta, hour, false)
	if _accum >= float(sp["seconds"]):
		# on a slow machine, catch up a little instead of falling behind
		var steps: int = mini(3, int(_accum / float(sp["seconds"])))
		_accum = 0.0
		_advance(int(sp["days"]) * steps)


func _advance(days: int) -> void:
	var important: Array = []
	for i in days:
		world.tick_day()
		for e in world.events_today:
			if bool(e["important"]) and interrupt_kinds.get(str(e["kind"]), false):
				important.append(e)
		hud.feed(world.events_today)
		_sounds(world.events_today)
		# turbo and fast stop on events the player marked as important
		if speed >= 3 and not important.is_empty() and _should_interrupt(important):
			break
	view.refresh_all()
	hud.refresh_all()
	if speed >= 3 and not important.is_empty() and _should_interrupt(important):
		last_fast_speed = speed
		speed = 0
		hud.show_interrupt(important)


func _sounds(events: Array) -> void:
	for e in events:
		if not bool(e["important"]):
			continue
		var t: String = str(e["text"])
		var k: String = str(e["kind"])
		if k in ["bankruptcy", "death", "crime", "protest"] or t.contains("closed") or t.contains("lost"):
			sound.chime("bad")
		elif k in ["business", "birth", "project"] and not t.contains("closed"):
			sound.chime("good")
		else:
			sound.chime("note")
		return


func _should_interrupt(events: Array) -> bool:
	for e in events:
		var k: String = str(e["kind"])
		if k == "bankruptcy" or k == "death" or k == "estate":
			if world.involves_watched(e["refs"]) or k == "bankruptcy":
				return true
		elif k == "business" or k == "protest":
			return true
		elif k == "petition" and str(e["text"]).contains("on the mayor's desk"):
			return true
		elif k == "city" and str(e["text"]).begins_with("City budget crisis"):
			return true
		elif k == "project" and str(e["text"]).begins_with("Bids are in"):
			return true
		elif k == "election" or k == "region":
			return true
		elif (k == "crime" or k == "health") and world.involves_watched(e["refs"]):
			return true
	return false


func focus_lot(lot_id: int) -> void:
	view.focus_lot(lot_id)


func focus_sim(cid: int) -> void:
	view.focus_sim(cid, hour)
