class_name LTCalendar
extends RefCounted
## One tick is one day. 365 days a year, 12 months of fixed length, no leap years.

const MONTH_NAMES: Array = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
const MONTH_DAYS: Array = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const WEEKDAYS: Array = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]


static func year(day: int) -> int:
	return (maxi(day, 1) - 1) / 365 + 1


static func day_of_year(day: int) -> int:
	return (maxi(day, 1) - 1) % 365 + 1


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
	return WEEKDAYS[(maxi(day, 1) - 1) % 7]


static func is_weekend(day: int) -> bool:
	return (maxi(day, 1) - 1) % 7 >= 5


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
	return "%s, %s %d, Year %d" % [weekday(day), MONTH_NAMES[month_index(day)], day_of_month(day), year(day)]


static func short(day: int) -> String:
	return "%s %d, Y%d" % [str(MONTH_NAMES[month_index(day)]).substr(0, 3), day_of_month(day), year(day)]
