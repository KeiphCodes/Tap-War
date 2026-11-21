class_name LTCalendar
extends RefCounted
## One tick is one day. 365 days a year, 12 months of fixed length, no leap years.
## A town can run on "Year 1" or on the real calendar, starting on the real date it
## was founded. The offsets are set by the world when it is created or loaded.

static var start_doy: int = 0      # day of year (0 based) that game day 1 falls on
static var start_year: int = 1     # the year game day 1 falls in
static var start_wd: int = 0       # weekday of game day 1, 0 is Monday
static var real: bool = false      # show real years instead of "Year N"


static func apply(cal: Dictionary) -> void:
	start_doy = int(cal.get("start_doy", 0))
	start_year = int(cal.get("start_year", 1))
	start_wd = int(cal.get("start_wd", 0))
	real = bool(cal.get("real", false))


## A calendar that starts today, the way the player's own calendar reads.
static func from_today() -> Dictionary:
	var d: Dictionary = Time.get_date_dict_from_system()
	return {"start_doy": noleap_doy(int(d["year"]), int(d["month"]), int(d["day"])) - 1, "start_year": int(d["year"]), "start_wd": (int(d["weekday"]) + 6) % 7, "real": true}


## Day of year in a 365 day year: February 29 counts as February 28.
static func noleap_doy(y: int, m: int, dd: int) -> int:
	var doy: int = 0
	for i in m - 1:
		doy += int(MONTH_DAYS[i])
	if m == 2 and dd == 29:
		dd = 28
	return doy + dd


## The game day that falls on today's real date, for "match real date and time".
static func game_day_for_today() -> int:
	var d: Dictionary = Time.get_date_dict_from_system()
	var doy: int = noleap_doy(int(d["year"]), int(d["month"]), int(d["day"])) - 1
	return (int(d["year"]) - start_year) * 365 + doy - start_doy + 1


static func _abs(day: int) -> int:
	return maxi(day, 1) - 1 + start_doy

const MONTH_NAMES: Array = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
const MONTH_DAYS: Array = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const WEEKDAYS: Array = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]


static func year(day: int) -> int:
	return _abs(day) / 365 + start_year


static func day_of_year(day: int) -> int:
	return _abs(day) % 365 + 1


static func month_index(day: int) -> int:
	var d: int = day_of_year(day)
	for m in 12:
		if d <= int(MONTH_DAYS[m]):
			return m
		d -= int(MONTH_DAYS[m])
	return 11


static func day_of_month(day: int) -> int:
	var d: int = day_of_year(day)
	for m in 12:
		if d <= int(MONTH_DAYS[m]):
			return d
		d -= int(MONTH_DAYS[m])
	return d


static func is_month_start(day: int) -> bool:
	return day_of_month(day) == 1


static func weekday(day: int) -> String:
	return WEEKDAYS[(maxi(day, 1) - 1 + start_wd) % 7]


static func is_weekend(day: int) -> bool:
	return (maxi(day, 1) - 1 + start_wd) % 7 >= 5


static func season(day: int) -> String:
	var m: int = month_index(day)
	if m <= 1 or m == 11:
		return "Winter"
	if m <= 4:
		return "Spring"
	if m <= 7:
		return "Summer"
	return "Fall"


static func text(day: int) -> String:
	if real:
		return "%s, %s %d, %d" % [weekday(day), MONTH_NAMES[month_index(day)], day_of_month(day), year(day)]
	return "%s, %s %d, Year %d" % [weekday(day), MONTH_NAMES[month_index(day)], day_of_month(day), year(day)]


static func short(day: int) -> String:
	if real:
		return "%s %d, %d" % [str(MONTH_NAMES[month_index(day)]).substr(0, 3), day_of_month(day), year(day)]
	return "%s %d, Y%d" % [str(MONTH_NAMES[month_index(day)]).substr(0, 3), day_of_month(day), year(day)]
