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
var interrupt_kinds: Dictionary = {"bankruptcy": true, "death": true, "business": true, "petition": true, "city": true, "project": true, "estate": true, "protest": true, "crime": true, "region": true, "election": true, "health": true, "milestone": true}
var _pending_interrupt: Array = []
var last_fast_speed: int = 3
var catch_up_to: int = -1        # a game day to fast forward to, for matching the real date
var _catch_up_from: int = 0
var _autosaved_day: int = -1
var _dirty_t: float = -1.0       # seconds until a debounced autosave after a mayor action
var resumed: bool = false        # the game opened on an autosaved town
## Snapshots taken before each mayor action, newest last: {"day", "label", "bytes"}
var undo_stack: Array = []
## The title screen, shown at launch and from the Menu.
var title: CanvasLayer
## The save slot this town saves to: 1 to 3.
var slot: int = 1
## True while the town on screen is only the title screen's backdrop.
var demo: bool = false
const SLOTS: int = 3
const SETTINGS_PATH: String = "user://settings.cfg"
var settings: Dictionary = {"sound": true, "volume": 0.8, "graphics": 1, "stop_level": 1, "steps": true}


func _ready() -> void:
	# pick up where the player left off
	if FileAccess.file_exists(AUTOSAVE_PATH):
		var w: LTWorld = LTWorld.new()
		if w.load_from_file(AUTOSAVE_PATH) == OK:
			world = w
			resumed = true
			_autosaved_day = world.day
	if not resumed:
		# a town to look at behind the title screen until the player starts one
		world.new_town(int(Time.get_unix_time_from_system()) % 1000000)
		demo = true
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
	_load_settings()
	title = preload("res://ui/title.gd").new()
	title.name = "Title"
	add_child(title)
	title.setup(self)
	title.open(true)


# ---------------------------------------------------------------- settings

func _load_settings() -> void:
	var cf: ConfigFile = ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		for k in settings:
			settings[k] = cf.get_value("game", k, settings[k])
	apply_settings()


func save_settings() -> void:
	var cf: ConfigFile = ConfigFile.new()
	for k in settings:
		cf.set_value("game", k, settings[k])
	cf.save(SETTINGS_PATH)
	apply_settings()


## Sound, volume and how much the graphics ask of the device.
func apply_settings() -> void:
	if sound != null:
		sound.muted = not bool(settings["sound"])
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.001, float(settings["volume"]))))
	var vp: Viewport = get_viewport()
	var g: int = int(settings["graphics"])
	vp.msaa_3d = [Viewport.MSAA_4X, Viewport.MSAA_2X, Viewport.MSAA_DISABLED][g]
	vp.scaling_3d_scale = [1.0, 1.0, 0.75][g]
	if view != null and view.sun != null:
		view.sun.shadow_enabled = g < 2
	if hud != null:
		hud.steps_hidden = not bool(settings["steps"])
		hud.refresh_menu()


# ---------------------------------------------------------------- save slots

static func slot_path(n: int) -> String:
	return SAVE_PATH if n <= 1 else "user://living_town_%d.ltsave" % n


## A few words about a saved town, written beside it so the load screen is quick.
func _write_meta(path: String) -> void:
	var f: FileAccess = FileAccess.open(path + ".meta", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"town": str(world.city["name"]), "date": LTCalendar.short(world.day), "day": world.day,
		"people": world.residents(), "kind": LTTerrain.kind_name(world), "mayor": str(world.player.get("name", "")),
		"saved": Time.get_datetime_string_from_system(false, true)}))


static func slot_info(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var out: Dictionary = {"saved": Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(path), true)}
	if FileAccess.file_exists(path + ".meta"):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path + ".meta"))
		if j is Dictionary:
			out.merge(j, true)
	return out


func new_town(seed_value: int, mode: Dictionary = {}) -> void:
	demo = false
	if title != null:
		title.close()
	if not mode.has("stop_level"):
		mode["stop_level"] = int(settings["stop_level"])
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
	if demo:
		return
	if _write_save(AUTOSAVE_PATH) == OK:
		_write_meta(AUTOSAVE_PATH)
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


func save_game(n: int = -1) -> String:
	if demo:
		return "Start or load a town first."
	if n > 0:
		slot = n
	var path: String = slot_path(slot)
	var err: Error = _write_save(path)
	if err == OK:
		_write_meta(path)
		autosave()
	return "Saved to slot %d on %s." % [slot, LTCalendar.short(world.day)] if err == OK else "Save failed: %s" % error_string(err)


func load_game(n: int = -1) -> String:
	if n > 0:
		slot = n
	var path: String = AUTOSAVE_PATH if n == 0 else slot_path(slot)
	if not FileAccess.file_exists(path):
		return "No save found yet."
	var w: LTWorld = LTWorld.new()
	var err: Error = w.load_from_file(path)
	if err != OK:
		return "Could not load the save: %s" % error_string(err)
	world = w
	demo = false
	if title != null:
		title.close()
	speed = 0
	catch_up_to = -1
	undo_stack.clear()
	view.rebuild()
	hud.on_new_world()
	autosave()
	return "Loaded %s on %s." % [world.city["name"], LTCalendar.short(world.day)]


## Back to the title screen; the town is saved on the way.
func to_title() -> void:
	autosave()
	set_speed(0)
	title.open(false)


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
	if LTMayorAI.is_on(world) and not ["watch", "take_over"].has(str(a["kind"])):
		var no: Dictionary = {"ok": false, "message": "Mayor %s runs this town. Take over from the Menu to decide for yourself." % world.player["name"]}
		hud.show_toast(no["message"])
		return no
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


## How much stops Fast and Turbo: 0 only decisions waiting on the mayor, 1 those
## plus truly big events (the default), 2 everything marked important.
const STOP_LEVELS: Array = ["Stop time: decisions only", "Stop time: major events", "Stop time: everything"]


func stop_level() -> int:
	return int(world.mode.get("stop_level", 1))


func _should_interrupt(events: Array) -> bool:
	var level: int = stop_level()
	# decisions only the mayor can make; the Sim mayor makes them in autonomous mode
	var deciding: bool = not LTMayorAI.is_on(world)
	for e in events:
		var k: String = str(e["kind"])
		var t: String = str(e["text"])
		var watched: bool = world.involves_watched(e["refs"])
		if deciding:
			if k == "petition" and t.contains("on the mayor's desk"):
				return true
			if k == "project" and t.begins_with("Bids are in"):
				return true
			if k == "city" and (t.begins_with("Variance request") or t.begins_with("Plat request") or t.begins_with("City budget crisis")):
				return true
		if k == "election" and (t.contains("won") or t.contains("lost") or t.contains("recall")):
			return true
		if level == 0:
			continue
		if level == 2:
			if k in ["bankruptcy", "business", "protest", "region", "election"] or ((k in ["death", "estate", "crime", "health"]) and watched):
				return true
			continue
		# major: disasters, the county's big employers, a milestone, and the Sims you watch
		if k == "region" and (t.begins_with("A tornado cut") or t.contains("shut down in the county seat")):
			return true
		if k == "protest":
			return true
		# a business opening or closing changes the town
		if k == "business" and (t.contains(" opened ") or t.contains(" closed. Reason")):
			return true
		if k in ["death", "bankruptcy", "crime", "estate"] and watched:
			return true
		if k == "milestone":
			return true
	return false


func focus_lot(lot_id: int) -> void:
	view.focus_lot(lot_id)


func focus_sim(cid: int) -> void:
	view.focus_sim(cid, hour)
