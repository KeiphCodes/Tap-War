extends SceneTree
## Measures how often things happen in the game and compares each rate with real
## figures for the United States and South Dakota.
##
## The world is held to reality: weather, storms, blizzards, tornadoes, fires,
## workplace accidents, the county economy and the starting population. A rate
## outside its band fails. The Sims are not people and do not think like people,
## so what they choose (marrying, divorcing, stealing, starting and closing
## businesses, filing for bankruptcy) comes from their own traits and needs; those
## rates are listed next to the human figures for reference only.
## Run: godot --headless --script tests/realism.gd   (writes reports/realism_summary.txt)

var rows: Array = []
var ok_all: bool = true


func _row(name: String, value: float, lo: float, hi: float, real: String) -> void:
	var ok: bool = value >= lo and value <= hi
	ok_all = ok_all and ok
	rows.append("[%s] %s: %.2f  (allowed %.2f to %.2f; real: %s)" % ["PASS" if ok else "FAIL", name, value, lo, hi, real])


func _info(name: String, value: float, real: String) -> void:
	rows.append("[INFO] %s: %.2f  (people: %s)" % [name, value, real])


func _init() -> void:
	_weather()
	_county()
	_town()
	var text: String = "LIVING TOWN REALISM CHECK\nGenerated %s by tests/realism.gd.\n\n%s\n\nRESULT: %s" % [Time.get_datetime_string_from_system(), "\n".join(rows), "ALL RATES REALISTIC" if ok_all else "SOME RATES OUT OF RANGE"]
	print(text)
	var f: FileAccess = FileAccess.open("res://reports/realism_summary.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(text + "\n")
		f.close()
	quit(0 if ok_all else 1)


func _weather() -> void:
	# weather alone for 200 years
	var w: LTWorld = LTWorld.new()
	w.new_town(11, {}, {"start": "founder"})
	var years: int = 200
	var thunder: int = 0
	var snow: int = 0
	var precip: int = 0
	var severe: int = 0
	var tornado: int = 0
	var bliz: int = 0
	var winter_thunder: int = 0
	for d in years * 365:
		w.day += 1
		LTHazards.roll_weather(w)
		var m: int = LTCalendar.month_index(w.day)
		match w.weather:
			"Storm":
				thunder += 1
				precip += 1
				if m == 0 or m == 1 or m == 11:
					winter_thunder += 1
			"Rain":
				precip += 1
			"Snow":
				snow += 1
				precip += 1
		match LTHazards.event_today(w):
			"severe_storm":
				severe += 1
			"tornado":
				tornado += 1
				severe += 1
			"blizzard":
				bliz += 1
	var y: float = float(years)
	rows.append("Weather, %d simulated years:" % years)
	_row("Thunderstorm days a year", float(thunder) / y, 30.0, 50.0, "about 40 in Sioux Falls")
	_row("Days with snow a year", float(snow) / y, 25.0, 45.0, "about 34")
	_row("Days with rain, thunder or snow a year", float(precip) / y, 85.0, 120.0, "about 100")
	_row("Thunderstorm days in Dec to Feb a year", float(winter_thunder) / y, 0.0, 0.5, "almost none")
	_row("Severe thunderstorms hitting town a year", float(severe) / y, 1.0, 2.0, "1 to 2")
	_row("Blizzards a year", float(bliz) / y, 1.0, 2.0, "1 to 2 in eastern South Dakota")
	_row("Tornadoes hitting town per century", float(tornado) / y * 100.0, 0.0, 1.0, "well under 1")
	rows.append("")


func _county() -> void:
	# the county economy alone for 100 years: how often a big employer fails
	var w: LTWorld = LTWorld.new()
	w.new_town(12, {}, {})
	var years: int = 100
	for d in years * 365:
		w.day += 1
		LTRegion.daily(w)
	var n: float = float(w.region["employers"].size())
	rows.append("County economy, %d simulated years:" % years)
	_row("Major county employers that close, per employer per year (%%)" % [], float(w.counters.get("employer_failures", 0)) / n / float(years) * 100.0, 0.5, 4.0, "about 1 to 3% of large plants a year")
	rows.append("")


func _town() -> void:
	var w: LTWorld = LTWorld.new()
	w.new_town(77, {"lot_cols": 14, "lot_rows": 12, "target_households": 330, "target_population": 1000, "house_lots": 34, "apartment_lots": 50, "apartment_units": 6, "city_start_cash": LTMoney.dollars(1500000.0)})
	var ages: Array = [0, 0, 0]
	for cz in w.citizens:
		if w.is_present(cz):
			var ag: int = w.age_years(cz)
			ages[0 if ag < 10 else (2 if ag >= 60 else 1)] += 1
	var tot: float = float(ages[0] + ages[1] + ages[2])
	# a year to settle first: the test town starts with almost no businesses, so the
	# first year is a founding boom that no real town is in
	for d in 365:
		w.tick_day()
	var base_counters: Dictionary = w.counters.duplicate()
	var years: int = 3
	var pop: float = 0.0
	var adults: float = 0.0
	var workers: float = 0.0
	var homes: float = 0.0
	var renters: float = 0.0
	var bizn: float = 0.0
	var samples: int = 0
	for d in years * 365:
		w.tick_day()
		if d % 30 == 0:
			samples += 1
			for c in w.citizens:
				if not w.is_present(c):
					continue
				pop += 1.0
				if w.age_years(c) >= 18:
					adults += 1.0
				if str(c["job"]["kind"]) != "none":
					workers += 1.0
			for h in w.households:
				if int(h["lot"]) >= 0 and w.household_members(h).size() > 0:
					homes += 1.0
					if str(h["tenure"]) == "rent":
						renters += 1.0
			bizn += float(w.open_businesses().size())
	var s: float = float(samples)
	pop /= s
	adults /= s
	workers /= s
	homes /= s
	renters /= s
	bizn /= s
	var y: float = float(years)
	var c: Dictionary = {}
	for k in w.counters:
		c[k] = int(w.counters[k]) - int(base_counters.get(k, 0))
	var per: Callable = func(key: String, base: float, scale: float) -> float: return float(c.get(key, 0)) / base / y * scale
	rows.append("A town of about %d people (%d adults, %d workers, %d homes, %d renting, %d businesses), %d simulated years:" % [int(pop), int(adults), int(workers), int(homes), int(renters), int(bizn), years])
	rows.append("Starting population: %d people." % int(tot))
	_row("Share of people under 10 (%)", float(ages[0]) / tot * 100.0, 9.0, 16.0, "about 13 in rural South Dakota")
	_row("Share of people 60 and over (%)", float(ages[2]) / tot * 100.0, 17.0, 32.0, "about 25 in rural South Dakota")
	_info("Births per 1,000 people a year", per.call("births", pop, 1000.0), "12.4 in South Dakota")
	_info("Deaths per 1,000 people a year", per.call("deaths", pop, 1000.0), "9.5 in South Dakota")
	_info("Marriages per 1,000 people a year", per.call("marriages", pop, 1000.0), "6.1")
	_info("Divorces per 1,000 people a year", per.call("divorces", pop, 1000.0), "2.4")
	_info("Property crimes per 1,000 people a year", per.call("thefts", pop, 1000.0), "about 18 in South Dakota, less in small towns")
	_info("Burglaries per 1,000 people a year", per.call("burglaries", pop, 1000.0), "about 3")
	_info("Assaults with injury per 1,000 people a year", per.call("assaults", pop, 1000.0), "about 2 to 4")
	_row("Work injuries per 100 workers a year", per.call("injuries", workers, 100.0), 1.0, 5.0, "2.7 (BLS)")
	_info("New depression cases per 100 adults a year", per.call("depression", adults, 100.0), "about 3")
	_info("Bankruptcies per 1,000 adults a year", per.call("bankruptcies", adults, 1000.0), "about 1 in South Dakota")
	_info("Foreclosures per 1,000 homes a year", per.call("foreclosures", homes, 1000.0), "about 2 to 3")
	_info("Evictions per 100 renting households a year", per.call("evictions", maxf(renters, 1.0), 100.0), "about 3 to 4 filings")
	_row("Building fires per 1,000 homes a year", per.call("fires", homes, 1000.0), 0.5, 6.0, "about 2.5 home fires plus some businesses")
	_info("Layoffs per 100 workers a year", per.call("layoffs", workers, 100.0), "about 13 (all layoffs and discharges, JOLTS)")
	if bizn > 0.0:
		_info("Business closures per 100 businesses a year", per.call("businesses_closed", bizn, 100.0), "about 8 to 10")
