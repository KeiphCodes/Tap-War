extends Node3D
## Game controller: owns the world, runs time at the chosen speed, connects the 3D
## view and the mayor UI. The daily truth always runs a full tick per day; speed only
## changes how much of it the player watches.

const SPEEDS: Array = [
	{"name": "Pause", "days": 0, "seconds": 0.0},
	{"name": "Live", "days": 1, "seconds": 86400.0},
	{"name": "Watch", "days": 1, "seconds": 120.0},
	{"name": "Normal", "days": 1, "seconds": 3.0},
	{"name": "Fast", "days": 7, "seconds": 1.6},
	{"name": "Turbo", "days": 30, "seconds": 2.0},
]
const SAVE_PATH: String = "user://living_town.ltsave"
## The game saves itself here every few game days, after the mayor changes
## something, and whenever the app is closed or sent to the background.
const AUTOSAVE_PATH: String = "user://living_town_auto.ltsave"
const AUTOSAVE_DAYS: int = 3
const UNDO_STEPS: int = 10

var world: LTWorld = LTWorld.new()
var speed: int = 0
var hour: float = 9.0
var _accum: float = 0.0
var view: Node3D
var hud: CanvasLayer
var sound: Node
var interrupt_kinds: Dictionary = {"bankruptcy": true, "death": true, "business": true, "petition": true, "city": true, "project": true, "estate": true, "protest": true, "crime": true, "region": true, "election": true, "health": true}
var _pending_interrupt: Array = []
var last_fast_speed: int = 3
var catch_up_to: int = -1        # a game day to fast forward to, for matching the real date
var _catch_up_from: int = 0
var _autosaved_day: int = -1
var _dirty_t: float = -1.0       # seconds until a debounced autosave after a mayor action
var resumed: bool = false        # the game opened on an autosaved town
## Snapshots taken before each mayor action, newest last: {"day", "label", "bytes"}
var undo_stack: Array = []


func _ready() -> void:
	# pick up where the player left off
	if FileAccess.file_exists(AUTOSAVE_PATH):
		var w: LTWorld = LTWorld.new()
		if w.load_from_file(AUTOSAVE_PATH) == OK:
			world = w
			resumed = true
			_autosaved_day = world.day
	if not resumed:
		world.new_town(int(Time.get_unix_time_from_system()) % 1000000)
	get_tree().set_auto_accept_quit(false)
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


func new_town(seed_value: int, mode: Dictionary = {}) -> void:
	world = LTWorld.new()
	world.new_town(seed_value, {}, mode)
	catch_up_to = -1
	speed = 0
	hour = 9.0
	undo_stack.clear()
	view.rebuild()
	hud.on_new_world()
	autosave()


## Writes to a temporary file first, so a save cut off half way never ruins the last good one.
func _write_save(path: String) -> Error:
	var tmp: String = path + ".tmp"
	var err: Error = world.save_to_file(tmp)
	if err != OK:
		return err
	var d: DirAccess = DirAccess.open("user://")
	if d == null:
		return ERR_CANT_OPEN
	if FileAccess.file_exists(path):
		d.remove(path.get_file())
	return d.rename(tmp.get_file(), path.get_file())


func autosave() -> void:
	if _write_save(AUTOSAVE_PATH) == OK:
		_autosaved_day = world.day
	_dirty_t = -1.0


func _notification(what: int) -> void:
	# phones close apps in the background without warning: save on the way out
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			if world != null and view != null:
				autosave()
			get_tree().quit()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_GO_BACK_REQUEST:
			if world != null and view != null:
				autosave()


func save_game() -> String:
	var err: Error = _write_save(SAVE_PATH)
	if err == OK:
		autosave()
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
	catch_up_to = -1
	undo_stack.clear()
	view.rebuild()
	hud.on_new_world()
	autosave()
	return "Loaded the town on %s." % LTCalendar.short(world.day)


func set_speed(i: int) -> void:
	speed = clampi(i, 0, SPEEDS.size() - 1)
	_accum = 0.0
	if speed == 0:
		catch_up_to = -1
	hud.refresh_top()


func is_hourly() -> bool:
	return speed == 1 or speed == 2


## Live speed runs one game second per real second. Matching the real date fast
## forwards the town (only forward) until its calendar reads today, then sets the
## clock to the real time of day and keeps going live.
func match_real_time() -> String:
	var t: Dictionary = Time.get_time_dict_from_system()
	var real_hour: float = float(t["hour"]) + float(t["minute"]) / 60.0 + float(t["second"]) / 3600.0
	if not LTCalendar.real:
		hour = real_hour
		set_speed(1)
		return "Your town keeps its own calendar, so only the clock was matched. Now running live."
	var target: int = LTCalendar.game_day_for_today()
	var cur: int = maxi(world.day, 1)
	if target < cur:
		hour = real_hour
		set_speed(1)
		return "Your town is %d %s ahead of today. It keeps its date and runs live from here." % [cur - target, "day" if cur - target == 1 else "days"]
	if target == cur:
		hour = real_hour
		set_speed(1)
		return "Already on today's date. The clock is set and the town is running live."
	catch_up_to = target
	_catch_up_from = world.day
	speed = 0
	return "Fast forwarding %d %s to today. Press Pause to stop." % [target - world.day, "day" if target - world.day == 1 else "days"]


const _NO_UNDO: Array = ["watch"]


func act(a: Dictionary) -> Dictionary:
	var snap: PackedByteArray = PackedByteArray() if _NO_UNDO.has(str(a["kind"])) else world.to_bytes()
	var r: Dictionary = world.apply_action(a)
	if bool(r.get("ok", false)) and not snap.is_empty():
		undo_stack.append({"day": world.day, "label": _action_label(a), "bytes": snap})
		if undo_stack.size() > UNDO_STEPS:
			undo_stack.remove_at(0)
		_dirty_t = 2.0
	view._rebuild_road_mesh()
	view.refresh_all()
	hud.refresh_all()
	return r


func _action_label(a: Dictionary) -> String:
	return {
		"plan_road": "drawing the road", "plot_lots": "plotting lots", "unplot": "removing the lot",
		"edit_project": "the contract change", "edit_lots": "the lot change", "go_live": "sending it live",
		"define_project": "drafting the project", "cancel_project": "cancelling the project",
		"award_bid": "awarding the bid", "set_law": "the law change", "zone_lot": "the rezoning",
		"set_profile": "the profile change", "respond_petition": "the petition answer",
		"publish_need": "publishing the need", "city_borrow": "the loan", "issue_bond": "the bond",
	}.get(str(a["kind"]), "the last change")


func can_undo() -> bool:
	return not undo_stack.is_empty() and int(undo_stack[undo_stack.size() - 1]["day"]) == world.day


## Puts the town back the way it was before the mayor's last action. Only on the
## same day: once a day has passed, the Sims have already lived with the change.
func undo() -> String:
	if undo_stack.is_empty():
		return "Nothing to undo."
	var top: Dictionary = undo_stack[undo_stack.size() - 1]
	if int(top["day"]) != world.day:
		undo_stack.clear()
		return "Too late to undo: a day has passed and the town has lived with it."
	undo_stack.pop_back()
	var w: LTWorld = LTWorld.new()
	if w.from_bytes(top["bytes"]) != OK:
		return "Could not undo."
	world = w
	view.rebuild(true)
	view.set_tool(view.tool)
	hud.refresh_all()
	_dirty_t = 2.0
	return "Undid %s." % str(top["label"])


func _process(delta: float) -> void:
	if _dirty_t > 0.0:
		_dirty_t -= delta
		if _dirty_t <= 0.0:
			autosave()
	sound.weather = world.weather
	sound.daytime = hour > 6.0 and hour < 20.0
	sound.season = LTCalendar.season(world.day)
	sound.ambience = view.street_level()
	sound.city = view.audio
	if catch_up_to > world.day:
		# a few days per frame keeps the screen responsive while catching up
		var n: int = mini(4, catch_up_to - world.day)
		_advance(n, true)
		hud.show_toast("Catching up to today: %d of %d days." % [world.day - _catch_up_from, catch_up_to - _catch_up_from])
		view.animate(delta, hour, false)
		if world.day >= catch_up_to:
			catch_up_to = -1
			var t: Dictionary = Time.get_time_dict_from_system()
			hour = float(t["hour"]) + float(t["minute"]) / 60.0 + float(t["second"]) / 3600.0
			set_speed(1)
			hud.show_toast("Your town now matches today's date and time, and is running live.")
		return
	var sp: Dictionary = SPEEDS[speed]
	if int(sp["days"]) == 0:
		# paused: everyone stays exactly where they are at this moment
		view.time_scale = 0.0
		view.animate(delta, hour, true)
		return
	_accum += delta
	view.time_scale = 86400.0 / float(sp["seconds"]) if is_hourly() else 0.0
	if is_hourly():
		# live and watch: hours pass visibly; live is one game second per real second
		hour += delta / float(sp["seconds"]) * 24.0
		if hour >= 24.0:
			hour -= 24.0
			_advance(1)
		view.animate(delta, hour, true)
		hud.refresh_clock()
		return
	hour = view.FREEZE_HOUR
	view.animate(delta, hour, false)
	if _accum >= float(sp["seconds"]):
		# on a slow machine, catch up a little instead of falling behind
		var steps: int = mini(3, int(_accum / float(sp["seconds"])))
		_accum = 0.0
		_advance(int(sp["days"]) * steps)


func _advance(days: int, quiet: bool = false) -> void:
	var important: Array = []
	for i in days:
		world.tick_day()
		for e in world.events_today:
			if bool(e["important"]) and interrupt_kinds.get(str(e["kind"]), false):
				important.append(e)
		hud.feed(world.events_today)
		if not quiet:
			_sounds(world.events_today)
		# turbo and fast stop on events the player marked as important
		if speed >= 4 and not important.is_empty() and _should_interrupt(important):
			break
	view.refresh_all()
	if not quiet or world.day % 10 == 0:
		hud.refresh_all()
	if world.day - _autosaved_day >= AUTOSAVE_DAYS and catch_up_to < 0:
		autosave()
	if speed >= 4 and not important.is_empty() and _should_interrupt(important):
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
