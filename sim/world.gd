class_name LTWorld
extends RefCounted
## The whole town as plain data. Systems are static scripts that read and write
## these records. Nothing here is a scene node, so the town can run headless and
## grow past the starting size without changing any system.

## Version 5 is the real scale map (meters, 100 meter blocks, lots of any size);
## older saves were on the old tiny grid and are not loaded.
const SAVE_VERSION: int = 5

var seed_value: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var day: int = 0
var weather: String = "Clear"
var config: Dictionary = {}
var ledger: LTLedger = LTLedger.new()

var citizens: Array = []      # index == id, dead and departed Sims stay so history is never lost
var households: Array = []    # index == id
var lots: Array = []          # index == id
var road_nodes: Array = []    # [{"id","x","y"}]
var roads: Array = []         # segments, index == id
var streets: Array = []       # named groups of segments
var businesses: Array = []    # index == id
var debts: Array = []         # index == id
var petitions: Array = []     # index == id
var city_needs: Array = []    # published needs, index == id
var projects: Array = []      # index == id
var companies: Array = []     # outside contractors, index == id
var laws_log: Array = []      # every law change with its estimate and tracked result
var cases: Array = []         # court cases, index == id
var region: Dictionary = {}   # Tier 3: the county around town
var spend_book: Dictionary = {}  # where the town spends on each service, local or outside
var mode: Dictionary = {}     # how this town is played: start, elections, lottery, calendar
var player: Dictionary = {}   # the founder and mayor: a permanent resident with no needs, for now
var city: Dictionary = {}
var bank: Dictionary = {}
var chronicle: Array = []
var events_today: Array = []
var stats_history: Array = []
var counters: Dictionary = {}
var market: Dictionary = {}
var action_log: Array = []
var watch_list: Array = []
var _path_cache: Dictionary = {}
var dist_cache: Dictionary = {}
var debt_index: Dictionary = {}
var debt_index_dirty: bool = true


static func default_config() -> Dictionary:
	return {
		"town_blocks_x": 4,
		"town_blocks_y": 3,
		"target_households": 30,
		"target_population": 100,
		"house_lots": 22,
		"apartment_lots": 2,
		"apartment_units": 4,
		"next_town_minutes": 25,
		"city_start_cash": LTMoney.dollars(150000.0),
		"calendar": {},
		"bank_reserve": LTMoney.dollars(5000000.0),
	}


const PLAYER_COLORS: Dictionary = {
	"blue": Color(0.3, 0.45, 0.65), "red": Color(0.7, 0.2, 0.18), "green": Color(0.25, 0.55, 0.3),
	"gold": Color(0.85, 0.65, 0.15), "purple": Color(0.45, 0.3, 0.6), "black": Color(0.15, 0.15, 0.17),
	"orange": Color(0.9, 0.5, 0.15), "teal": Color(0.15, 0.55, 0.55),
}


## The player's pronoun: "subject" (they/he/she), "object" (them/him/her) or
## "possessive" (their/his/her).
func player_pronoun(form: String) -> String:
	var table: Dictionary = {
		"they": {"subject": "they", "object": "them", "possessive": "their"},
		"he": {"subject": "he", "object": "him", "possessive": "his"},
		"she": {"subject": "she", "object": "her", "possessive": "her"},
	}
	return str(table.get(str(player.get("pronouns", "they")), table["they"])[form])


## The player's age today: they age with the town's calendar.
func player_age() -> int:
	return int(player.get("age", 38)) + day / 365


func player_color() -> Color:
	return PLAYER_COLORS.get(str(player.get("color", "blue")), PLAYER_COLORS["blue"])


## The player edits who they are, and may rename the town.
func set_profile(act: Dictionary) -> Dictionary:
	var changed: Array = []
	if act.has("name"):
		var nm: String = str(act["name"]).strip_edges().left(40)
		if nm != "" and nm != str(player["name"]):
			chronicle_add("%s will now be known as %s." % [player["name"], nm], "town", false, [])
			player["name"] = nm
			changed.append("name")
	if act.has("pronouns") and ["they", "he", "she"].has(str(act["pronouns"])):
		player["pronouns"] = str(act["pronouns"])
		changed.append("pronouns")
	if act.has("age"):
		player["age"] = clampi(int(act["age"]), 18, 99) - day / 365
		changed.append("age")
	if act.has("hometown"):
		player["hometown"] = str(act["hometown"]).strip_edges().left(40)
		changed.append("hometown")
	if act.has("color") and PLAYER_COLORS.has(str(act["color"])):
		player["color"] = str(act["color"])
		changed.append("color")
	if act.has("town_name"):
		var tn: String = str(act["town_name"]).strip_edges().left(40)
		if tn != "" and tn != str(city["name"]):
			chronicle_add("The town of %s was renamed %s." % [city["name"], tn], "town", true, [])
			city["name"] = tn
			changed.append("town name")
	if changed.is_empty():
		return {"ok": true, "message": "Nothing changed."}
	return {"ok": true, "message": "Saved your %s." % ", ".join(changed)}


## Game modes. "classic" starts in Prairie Hollow with about 100 people; "founder"
## starts on empty prairie with only the player and their lottery money.
static func default_mode() -> Dictionary:
	return {"start": "classic", "elections": false, "lottery": LTMoney.dollars(1000000.0), "real_calendar": false, "player_name": "Sam Dakota"}


func residents() -> int:
	return alive_count() + (1 if not player.is_empty() else 0)


func new_town(p_seed: int, p_config: Dictionary = {}, p_mode: Dictionary = {}) -> void:
	mode = default_mode()
	for k in p_mode:
		mode[k] = p_mode[k]
	if bool(mode["real_calendar"]) and not p_config.has("calendar"):
		p_config = p_config.duplicate()
		p_config["calendar"] = LTCalendar.from_today()
	if str(mode["start"]) == "founder":
		p_config = p_config.duplicate()
		p_config["city_start_cash"] = 0
	seed_value = p_seed
	rng.seed = p_seed
	rng.state = 0
	rng.seed = p_seed
	day = 0
	config = default_config()
	for k in p_config:
		config[k] = p_config[k]
	LTCalendar.apply(config["calendar"])
	ledger = LTLedger.new()
	citizens.clear()
	households.clear()
	lots.clear()
	road_nodes.clear()
	roads.clear()
	streets.clear()
	businesses.clear()
	debts.clear()
	petitions.clear()
	city_needs.clear()
	projects.clear()
	companies.clear()
	laws_log.clear()
	cases.clear()
	region = {}
	spend_book = {}
	chronicle.clear()
	events_today.clear()
	stats_history.clear()
	action_log.clear()
	watch_list.clear()
	_path_cache.clear()
	dist_cache.clear()
	debt_index.clear()
	debt_index_dirty = true
	counters = {
		"births": 0, "deaths": 0, "moved_in": 0, "moved_out": 0,
		"businesses_opened": 0, "businesses_closed": 0, "founding_attempts": 0, "founding_failed": 0,
		"bankruptcies": 0, "bankruptcies_ch7": 0, "bankruptcies_ch13": 0, "estates": 0,
		"loans_made": 0, "loans_denied": 0, "debts_paid_off": 0, "debts_charged_off": 0,
		"foreclosures": 0, "repossessions": 0, "evictions": 0, "thefts": 0,
		"hires": 0, "layoffs": 0, "quits": 0, "petitions": 0, "projects_done": 0, "marriages": 0,
		"divorces": 0, "convictions": 0, "fires": 0,
	}
	ledger.open("outside")
	ledger.open("city")
	ledger.open("bank")
	ledger.pay("outside", "bank", int(config["bank_reserve"]), "bank_capital")
	ledger.pay("outside", "city", int(config["city_start_cash"]), "city_start_reserve")
	if str(mode["start"]) == "founder":
		LTGeography.build_open(self)
	else:
		LTGeography.build(self)
	LTRegion.setup(self)
	LTCivic.setup_city(self)
	LTFinance.setup_bank(self)
	LTProjects.setup_companies(self)
	player = {"name": str(mode["player_name"]), "home_lot": -1, "since": 0, "title": "founder",
		"pronouns": str(mode.get("player_pronouns", "they")), "age": int(mode.get("player_age", 38)),
		"hometown": str(mode.get("player_hometown", "Sioux Falls")), "color": str(mode.get("player_color", "blue"))}
	city["elections"] = bool(mode["elections"])
	if str(mode["start"]) == "founder":
		LTFounder.setup(self)
	else:
		LTPeople.generate_town(self)
		city["incorporated"] = true
	LTEconomy.analyze_market(self)
	ledger.tracked["city"] = {"in": {}, "out": {}}
	city["outside_at_start"] = ledger.bal("outside")
	if str(mode["start"]) == "founder":
		chronicle_add("%s won %s in the lottery and had an idea: start a town. %s bought a stretch of prairie on the county road and parked a camper on it. Population: 1." % [player["name"], LTMoney.fmt(int(mode["lottery"])), player_pronoun("subject").capitalize()], "town", true, [])
	else:
		chronicle_add("The town of %s begins. %d people in %d households, and you, the mayor. Most adults with jobs drive to work outside town. There is no grocery, no school, and no clinic." % [city["name"], alive_count(), households.size()], "town", true, [])


# ---------------------------------------------------------------- the daily tick

func tick_day() -> void:
	day += 1
	events_today.clear()
	_path_cache.clear()
	if day % 7 == 0:
		dist_cache.clear()
	debt_index_dirty = true
	LTHazards.roll_weather(self)
	LTRegion.daily(self)
	LTHazards.daily(self)
	if LTCalendar.is_month_start(day):
		LTServices.month_roll(self)
		LTHazards.monthly_insurance(self)
	LTPeople.morning(self)
	LTHealth.daily(self)
	LTEconomy.daily(self)
	LTPeople.evening(self)
	LTFinance.daily(self)
	LTCivic.daily(self)
	LTJustice.daily(self)
	LTChoices.daily(self)
	if LTCalendar.day_of_month(day) == 18:
		LTChoices.monthly(self)
	if LTCalendar.day_of_month(day) == 22:
		LTDevelopers.monthly(self)
	LTProjects.daily(self)
	LTPeople.life_events(self)
	if LTCalendar.day_of_month(day) == 25:
		LTFamily.monthly(self)
	if LTCalendar.weekday(day) == "Sunday":
		LTCivic.newspaper(self)
	LTCivic.elections_daily(self)
	LTFounder.daily(self)
	LTEconomy.analyze_market(self)
	if LTCalendar.day_of_month(day) == LTCalendar.MONTH_DAYS[LTCalendar.month_index(day)]:
		stats_history.append(snapshot())
		if stats_history.size() > 600:
			stats_history.remove_at(0)


func run_days(n: int) -> void:
	for i in n:
		tick_day()


# ---------------------------------------------------------------- player actions
## Every mayor verb goes through here so a run can be replayed from seed plus this log.

func apply_action(a: Dictionary) -> Dictionary:
	var act: Dictionary = a.duplicate(true)
	act["day"] = day
	var result: Dictionary = {"ok": false, "message": "Unknown action."}
	match str(act.get("kind", "")):
		"set_law":
			result = LTCivic.set_law(self, str(act["law"]), act["value"])
		"zone_lot":
			result = LTCivic.zone_lot(self, int(act["lot"]), str(act["zone"]))
		"edit_lots":
			result = LTGeography.edit_lots(self, act["lots"], act["changes"].duplicate())
		"edit_project":
			result = LTProjects.edit(self, int(act["project_id"]), act["changes"].duplicate())
		"publish_need":
			result = LTCivic.publish_need(self, str(act["need"]), int(act.get("lot", -1)), act.get("incentives", {}), int(act.get("petition_id", -1)))
		"respond_petition":
			result = LTCivic.respond_petition(self, int(act["petition_id"]), str(act["response"]), act)
		"define_project":
			result = LTProjects.define_project(self, str(act["ptype"]), int(act.get("target", -1)), int(act.get("ceiling", 0)), int(act.get("petition_id", -1)), not bool(act.get("live", false)))
		"set_profile":
			result = set_profile(act)
		"go_live":
			result = LTProjects.go_live(self, int(act["project_id"]))
		"award_bid":
			result = LTProjects.award(self, int(act["project_id"]), int(act["bid_index"]))
		"cancel_project":
			result = LTProjects.cancel(self, int(act["project_id"]))
		"city_borrow":
			result = LTFinance.city_borrow(self, int(act["amount"]), str(act.get("purpose", "general")))
		"issue_bond":
			result = LTCivic.issue_bond(self, int(act["amount"]), str(act.get("purpose", "city projects")))
		"annex":
			if bool(config.get("open_land", false)):
				result = {"ok": false, "message": "This town has open land: draw roads and plot lots wherever you like."}
			else:
				result = LTGeography.annex_row(self)
		"plan_road":
			result = LTGeography.plan_road(self, int(act["a"]), int(act["b"]), not bool(act.get("live", false)), str(act.get("road_kind", "street")))
		"plot_lots":
			result = LTGeography.plot_lots(self, float(act["x0"]), float(act["z0"]), float(act["x1"]), float(act["z1"]), str(act.get("zone", "residential")), float(act.get("width", 0.0)))
		"unplot":
			result = LTGeography.unplot(self, int(act["lot"]))
		"elections":
			city["elections"] = bool(act["on"])
			if bool(act["on"]) and int(city["next_election_day"]) <= day:
				city["next_election_day"] = day + 365
			result = {"ok": true, "message": "Elections are %s. %s" % ["on" if bool(act["on"]) else "off", "The next one is %s." % LTCalendar.short(int(city["next_election_day"])) if bool(act["on"]) else "You stay mayor for as long as you like."]}
		"watch":
			var cid: int = int(act["citizen_id"])
			if watch_list.has(cid):
				watch_list.erase(cid)
				result = {"ok": true, "message": "Stopped watching."}
			else:
				watch_list.append(cid)
				result = {"ok": true, "message": "Now watching."}
	if bool(result.get("ok", false)) and str(act.get("kind", "")) != "watch":
		action_log.append(act)
	return result


# ---------------------------------------------------------------- lookups

func cit(id: int) -> Dictionary:
	if id < 0 or id >= citizens.size():
		return {}
	return citizens[id]


func biz(id: int) -> Dictionary:
	if id < 0 or id >= businesses.size():
		return {}
	return businesses[id]


func hh(id: int) -> Dictionary:
	if id < 0 or id >= households.size():
		return {}
	return households[id]


func debt(id: int) -> Dictionary:
	if id < 0 or id >= debts.size():
		return {}
	return debts[id]


func lot(id: int) -> Dictionary:
	if id < 0 or id >= lots.size():
		return {}
	return lots[id]


func is_present(c: Dictionary) -> bool:
	return not c.is_empty() and bool(c["alive"]) and not bool(c["left_town"])


func present_citizens() -> Array:
	var out: Array = []
	for c in citizens:
		if bool(c["alive"]) and not bool(c["left_town"]):
			out.append(c)
	return out


func alive_count() -> int:
	var n: int = 0
	for c in citizens:
		if bool(c["alive"]) and not bool(c["left_town"]):
			n += 1
	return n


func open_businesses(btype: String = "") -> Array:
	var out: Array = []
	for b in businesses:
		if str(b["status"]) == "open" and (btype == "" or str(b["type"]) == btype):
			out.append(b)
	return out


func full_name(c: Dictionary) -> String:
	if c.is_empty():
		return "nobody"
	return "%s %s" % [c["first_name"], c["last_name"]]


func age_years(c: Dictionary) -> int:
	return int(c["age_days"]) / 365


func acct_p(c: Dictionary) -> String:
	return "p:%d" % int(c["id"])


func acct_b(b: Dictionary) -> String:
	return "b:%d" % int(b["id"])


func cash(c: Dictionary) -> int:
	return ledger.bal("p:%d" % int(c["id"]))


func biz_cash(b: Dictionary) -> int:
	return ledger.bal("b:%d" % int(b["id"]))


func household_adults(h: Dictionary) -> Array:
	var out: Array = []
	for mid in h["members"]:
		var m: Dictionary = cit(int(mid))
		if is_present(m) and age_years(m) >= 18:
			out.append(m)
	return out


func household_members(h: Dictionary) -> Array:
	var out: Array = []
	for mid in h["members"]:
		var m: Dictionary = cit(int(mid))
		if is_present(m):
			out.append(m)
	return out


func household_cash(h: Dictionary) -> int:
	var t: int = 0
	for m in household_adults(h):
		t += cash(m)
	return t


## Pays a household bill from the adults, richest first. Returns amount paid.
func household_pay(h: Dictionary, to_acct: String, cents: int, category: String) -> int:
	if cents <= 0:
		return 0
	var adults: Array = household_adults(h)
	adults.sort_custom(func(a, b): return cash(a) > cash(b))
	var left: int = cents
	for m in adults:
		if left <= 0:
			break
		left -= ledger.pay(acct_p(m), to_acct, left, category)
	return cents - left


# ---------------------------------------------------------------- logs

func log_sim(c: Dictionary, text: String, major: bool = true) -> void:
	if c.is_empty():
		return
	var h: Array = c["history"]
	h.append({"day": day, "text": text, "major": major})
	if h.size() > 160:
		# keep the oldest major events, drop the oldest minor ones first
		var dropped: bool = false
		for i in h.size():
			if not bool(h[i]["major"]):
				h.remove_at(i)
				dropped = true
				break
		if not dropped:
			h.remove_at(0)


func log_biz(b: Dictionary, text: String) -> void:
	var h: Array = b["history"]
	h.append({"day": day, "text": text})
	if h.size() > 160:
		h.remove_at(0)


func remember(c: Dictionary, kind: String, about: int, weight: float) -> void:
	var mem: Array = c["memory"]
	mem.append({"day": day, "kind": kind, "about": about, "weight": weight})
	if mem.size() > 24:
		var weakest: int = 0
		for i in mem.size():
			if absf(float(mem[i]["weight"])) < absf(float(mem[weakest]["weight"])):
				weakest = i
		mem.remove_at(weakest)


func memory_weight(c: Dictionary, kind: String, about: int = -1) -> float:
	var t: float = 0.0
	for m in c["memory"]:
		if str(m["kind"]) == kind and (about < 0 or int(m["about"]) == about):
			var age: float = float(day - int(m["day"]))
			t += float(m["weight"]) * exp(-age / 365.0)
	return t


func chronicle_add(text: String, kind: String, important: bool, refs: Array) -> void:
	var e: Dictionary = {"day": day, "text": text, "kind": kind, "important": important, "refs": refs}
	chronicle.append(e)
	if chronicle.size() > 2000:
		chronicle.remove_at(0)
	events_today.append(e)


func involves_watched(refs: Array) -> bool:
	for r in refs:
		if watch_list.has(int(r)):
			return true
	return false


# ---------------------------------------------------------------- stats

func snapshot() -> Dictionary:
	var pop: int = 0
	var adults: int = 0
	var employed: int = 0
	var local_jobs: int = 0
	var income_sum: int = 0
	var happy_sum: float = 0.0
	var trust_sum: float = 0.0
	var homeless: int = 0
	for c in citizens:
		if not is_present(c):
			continue
		pop += 1
		happy_sum += LTPeople.happiness(c)
		trust_sum += float(c["trust_city"])
		if c["homeless"]:
			homeless += 1
		var a: int = age_years(c)
		if a >= 18 and a < 65:
			adults += 1
			if str(c["job"]["kind"]) != "none":
				employed += 1
				income_sum += int(c["job"]["daily_wage"])
				if str(c["job"]["kind"]) != "outside":
					local_jobs += 1
	var debt_total: int = 0
	var debts_late: int = 0
	for d in debts:
		if LTFinance.is_active(d):
			debt_total += int(d["balance"])
			if str(d["status"]) != "current":
				debts_late += 1
	return {
		"day": day,
		"population": pop,
		"adults": adults,
		"employed": employed,
		"local_jobs": local_jobs,
		"unemployment": 0.0 if adults == 0 else 1.0 - float(employed) / float(adults),
		"avg_daily_wage": 0 if employed == 0 else income_sum / employed,
		"happiness": 0.0 if pop == 0 else happy_sum / float(pop),
		"approval": LTCivic.approval(self),
		"homeless": homeless,
		"businesses_open": open_businesses().size(),
		"city_cash": ledger.bal("city"),
		"debt_total": debt_total,
		"debts_late": debts_late,
		"outside_net": -ledger.bal("outside"),
		"counters": counters.duplicate(),
	}


func state_hash() -> int:
	var parts: Array = [day, ledger.balances.hash(), citizens.size(), businesses.size(), debts.size(), counters.hash()]
	for c in citizens:
		parts.append(int(c["age_days"]))
		parts.append(str(c["job"]["kind"]))
	return str(parts).hash()


# ---------------------------------------------------------------- save and load
## Chunked by system and versioned from the first save.

func to_save() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"world": {"seed": seed_value, "rng_state": rng.state, "day": day, "weather": weather, "config": config, "counters": counters, "stats_history": stats_history, "chronicle": chronicle, "action_log": action_log, "watch_list": watch_list},
		"geography": {"lots": lots, "road_nodes": road_nodes, "roads": roads, "streets": streets},
		"citizens": {"citizens": citizens, "households": households},
		"businesses": {"businesses": businesses},
		"finance": {"ledger": ledger.to_dict(), "debts": debts, "bank": bank},
		"city": {"city": city, "petitions": petitions, "city_needs": city_needs, "projects": projects, "companies": companies, "laws_log": laws_log},
		"justice": {"cases": cases},
		"region": {"region": region, "spend_book": spend_book},
		"player": {"mode": mode, "player": player},
	}


func save_to_file(path: String) -> Error:
	# binary chunks keep every float exact, so a loaded town continues exactly as it would have
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var data: Dictionary = to_save()
	f.store_string("LIVINGTOWN")
	f.store_32(SAVE_VERSION)
	f.store_32(data.size())
	for chunk in data:
		f.store_pascal_string(str(chunk))
		f.store_var(data[chunk])
	f.close()
	return OK


func load_from_file(path: String) -> Error:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return FileAccess.get_open_error()
	if f.get_buffer(10).get_string_from_ascii() != "LIVINGTOWN":
		return ERR_FILE_UNRECOGNIZED
	var version: int = f.get_32()
	if version < 5 or version > SAVE_VERSION:
		return ERR_FILE_UNRECOGNIZED
	var n: int = f.get_32()
	var data: Dictionary = {}
	for i in n:
		var name: String = f.get_pascal_string()
		data[name] = f.get_var()
	f.close()
	return from_save(data, version)


## A whole town as bytes in memory, for undo. Same data as a save file.
func to_bytes() -> PackedByteArray:
	return var_to_bytes({"version": SAVE_VERSION, "data": to_save()})


func from_bytes(b: PackedByteArray) -> Error:
	var d: Variant = bytes_to_var(b)
	if typeof(d) != TYPE_DICTIONARY:
		return ERR_INVALID_DATA
	# a deep copy, so the snapshot can be restored again later
	return from_save((d["data"] as Dictionary).duplicate(true), int(d["version"]))


func from_save(data: Dictionary, _version: int) -> Error:
	var w: Dictionary = data["world"]
	seed_value = int(w["seed"])
	rng.seed = seed_value
	rng.state = int(w["rng_state"])
	day = int(w["day"])
	weather = str(w["weather"])
	config = w["config"]
	counters = w["counters"]
	stats_history = w["stats_history"]
	chronicle = w["chronicle"]
	action_log = w["action_log"]
	watch_list = w["watch_list"]
	lots = data["geography"]["lots"]
	road_nodes = data["geography"]["road_nodes"]
	roads = data["geography"]["roads"]
	streets = data["geography"]["streets"]
	citizens = data["citizens"]["citizens"]
	households = data["citizens"]["households"]
	businesses = data["businesses"]["businesses"]
	ledger = LTLedger.new()
	ledger.from_dict(data["finance"]["ledger"])
	debts = data["finance"]["debts"]
	bank = data["finance"]["bank"]
	city = data["city"]["city"]
	# a law added since the save was made starts at its usual setting
	for k in LTCivic.DEFAULT_LAWS:
		if not city["laws"].has(k):
			city["laws"][k] = LTCivic.DEFAULT_LAWS[k]
	petitions = data["city"]["petitions"]
	city_needs = data["city"]["city_needs"]
	projects = data["city"]["projects"]
	companies = data["city"]["companies"]
	laws_log = data["city"]["laws_log"]
	cases = data["justice"]["cases"]
	region = data["region"]["region"]
	spend_book = data["region"]["spend_book"]
	if data.has("player"):
		mode = data["player"]["mode"]
		player = data["player"]["player"]
	else:
		mode = default_mode()
		player = {"name": "the mayor", "home_lot": -1, "since": 0, "title": "mayor"}
	if not config.has("calendar"):
		config["calendar"] = {}
	LTCalendar.apply(config["calendar"])
	if not city.has("incorporated"):
		city["incorporated"] = true
	dist_cache.clear()
	debt_index_dirty = true
	_path_cache.clear()
	events_today.clear()
	LTEconomy.analyze_market(self)
	return OK


# ---------------------------------------------------------------- travel

func travel_minutes(from_lot: int, to_lot: int) -> float:
	var key: int = from_lot * 100003 + to_lot
	if _path_cache.has(key):
		return float(_path_cache[key])
	var m: float = LTGeography.travel_minutes(self, from_lot, to_lot)
	_path_cache[key] = m
	return m


func minutes_to_outside(from_lot: int) -> float:
	return travel_minutes(from_lot, -1)
