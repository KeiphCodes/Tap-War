class_name LTServices
extends RefCounted
## The rest of the business types. Every place a Sim spends money on a service
## goes through spend(): a local Sim run business gets it if one is open and the
## Sim prefers it, otherwise the money leaves town. The spend book records both,
## and founders read it to see what the town is missing.

const TYPES: Dictionary = {
	"clinic": {"display": "Clinic", "skill": "medicine", "zones": ["commercial", "mixed", "civic"], "startup": 6000000, "staff": 2, "wage": 21000, "title": "nurse", "license": 40000, "category": "medical", "supply": 0.25, "min_skill": 50},
	"pharmacy": {"display": "Pharmacy", "skill": "medicine", "zones": ["commercial", "mixed"], "startup": 2000000, "staff": 0, "wage": 13000, "title": "pharmacy tech", "license": 30000, "category": "pharmacy", "supply": 0.55, "min_skill": 40},
	"private_school": {"display": "Academy", "skill": "teaching", "zones": ["commercial", "mixed", "civic"], "startup": 4000000, "staff": 2, "wage": 15000, "title": "teacher", "license": 30000, "category": "tuition", "supply": 0.12, "min_skill": 50},
	"repair_shop": {"display": "Repair Shop", "skill": "repair", "zones": ["commercial", "industrial", "mixed"], "startup": 1400000, "staff": 1, "wage": 13000, "title": "mechanic", "license": 20000, "category": "repairs", "supply": 0.35, "min_skill": 35},
	"factory": {"display": "Works", "skill": "management", "zones": ["industrial"], "startup": 9000000, "staff": 6, "wage": 14000, "title": "factory worker", "license": 60000, "category": "", "supply": 0.0, "min_skill": 45},
	"warehouse": {"display": "Warehouse", "skill": "logistics", "zones": ["industrial", "commercial"], "startup": 3500000, "staff": 2, "wage": 12500, "title": "warehouse worker", "license": 25000, "category": "storage", "supply": 0.15, "min_skill": 35},
	"trucking": {"display": "Trucking", "skill": "logistics", "zones": ["industrial", "commercial"], "startup": 4500000, "staff": 2, "wage": 15000, "title": "truck driver", "license": 30000, "category": "freight", "supply": 0.3, "min_skill": 35},
	"hotel": {"display": "Motel", "skill": "management", "zones": ["commercial", "mixed"], "startup": 7000000, "staff": 2, "wage": 11000, "title": "desk clerk", "license": 30000, "category": "lodging", "supply": 0.2, "min_skill": 35},
	"bar": {"display": "Tavern", "skill": "retail", "zones": ["commercial", "mixed"], "startup": 1600000, "staff": 1, "wage": 10400, "title": "bartender", "license": 50000, "category": "bar", "supply": 0.35, "min_skill": 25},
	"childcare": {"display": "Child Care", "skill": "teaching", "zones": ["commercial", "mixed", "residential"], "startup": 1200000, "staff": 2, "wage": 11000, "title": "child care worker", "license": 20000, "category": "childcare", "supply": 0.1, "min_skill": 30},
	"funeral_home": {"display": "Funeral Home", "skill": "management", "zones": ["commercial", "mixed"], "startup": 1800000, "staff": 0, "wage": 13000, "title": "funeral assistant", "license": 25000, "category": "funeral", "supply": 0.4, "min_skill": 30},
	"law_office": {"display": "Law Office", "skill": "finance", "zones": ["commercial", "mixed"], "startup": 800000, "staff": 0, "wage": 14000, "title": "paralegal", "license": 25000, "category": "legal", "supply": 0.05, "min_skill": 60},
	"real_estate": {"display": "Realty", "skill": "finance", "zones": ["commercial", "mixed"], "startup": 600000, "staff": 0, "wage": 0, "title": "", "license": 20000, "category": "real_estate", "supply": 0.05, "min_skill": 40},
	"mill": {"display": "Mill", "skill": "repair", "zones": ["industrial", "agricultural"], "startup": 2400000, "staff": 1, "wage": 13000, "title": "mill hand", "license": 25000, "category": "", "supply": 0.0, "min_skill": 35},
	"bakery": {"display": "Bakery", "skill": "cooking", "zones": ["commercial", "mixed"], "startup": 1500000, "staff": 1, "wage": 11000, "title": "baker", "license": 20000, "category": "bakery", "supply": 0.0, "min_skill": 35},
	"bank": {"display": "State Bank", "skill": "finance", "zones": ["commercial", "mixed"], "startup": 6000000, "staff": 2, "wage": 16000, "title": "teller", "license": 100000, "category": "", "supply": 0.0, "min_skill": 60},
	# the outdoors: they live off the lakes, the forest and the mountain
	"outfitter": {"display": "Outfitters", "skill": "retail", "zones": ["commercial", "mixed"], "startup": 1500000, "staff": 1, "wage": 10400, "title": "outfitter clerk", "license": 20000, "category": "outdoor_gear", "supply": 0.55, "min_skill": 25},
	"marina": {"display": "Marina", "skill": "repair", "zones": ["commercial", "mixed", "park", "residential"], "startup": 2500000, "staff": 1, "wage": 11000, "title": "dock hand", "license": 25000, "category": "boating", "supply": 0.25, "min_skill": 30},
	"campground": {"display": "Campground", "skill": "management", "zones": ["commercial", "agricultural", "park", "mixed"], "startup": 2000000, "staff": 1, "wage": 10400, "title": "camp host", "license": 20000, "category": "camping", "supply": 0.15, "min_skill": 25},
	"guide_service": {"display": "Guides", "skill": "farming", "zones": ["commercial", "mixed", "residential"], "startup": 800000, "staff": 0, "wage": 13000, "title": "guide", "license": 15000, "category": "guiding", "supply": 0.1, "min_skill": 45},
	"sawmill": {"display": "Lumber", "skill": "repair", "zones": ["industrial", "agricultural"], "startup": 9000000, "staff": 3, "wage": 14000, "title": "sawmill worker", "license": 30000, "category": "", "supply": 0.0, "min_skill": 35},
	"quarry": {"display": "Quarry", "skill": "construction", "zones": ["industrial", "agricultural"], "startup": 9000000, "staff": 3, "wage": 15500, "title": "quarry worker", "license": 40000, "category": "", "supply": 0.0, "min_skill": 35},
	"gold_mine": {"display": "Mining Co", "skill": "management", "zones": ["industrial", "agricultural"], "startup": 50000000, "staff": 8, "wage": 21000, "title": "miner", "license": 100000, "category": "", "supply": 0.0, "min_skill": 50},
}
const SUFFIXES: Dictionary = {
	"clinic": ["Family Clinic", "Medical", "Health Center"], "pharmacy": ["Pharmacy", "Drug", "Apothecary"],
	"private_school": ["Academy", "Prep School", "Learning Center"], "repair_shop": ["Repair", "Auto and Repair", "Fix It Shop"],
	"factory": ["Works", "Manufacturing", "Industries"], "warehouse": ["Storage", "Warehouse", "Distribution"],
	"trucking": ["Trucking", "Freight", "Hauling"], "hotel": ["Motel", "Inn", "Lodge"], "bar": ["Tavern", "Bar", "Saloon"],
	"childcare": ["Child Care", "Little Ones", "Day Care"], "funeral_home": ["Funeral Home", "Memorial Chapel"],
	"law_office": ["Law Office", "Legal Services"], "real_estate": ["Realty", "Real Estate"], "mill": ["Mill", "Grain and Feed"],
	"bakery": ["Bakery", "Bread Co"], "bank": ["State Bank", "Savings Bank"],
	"outfitter": ["Outfitters", "Bait and Tackle", "Sporting Goods"], "marina": ["Marina", "Boat Rentals", "Boat and Dock"],
	"campground": ["Campground", "Cabins", "RV Park"], "guide_service": ["Guide Service", "Hunting and Fishing Guides"],
	"sawmill": ["Lumber", "Sawmill", "Timber Co"], "quarry": ["Quarry", "Stone and Gravel", "Aggregate"],
	"gold_mine": ["Mining Co", "Gold Mine", "Consolidated Mining"],
}
## What the same service costs, and how far, outside town. Some have no outside option.
const OUTSIDE_OPTION: Dictionary = {
	"medical": true, "pharmacy": true, "tuition": false, "repairs": true, "storage": false, "freight": true,
	"lodging": false, "bar": true, "childcare": true, "funeral": true, "legal": true, "real_estate": true, "bakery": false,
	"outdoor_gear": true, "boating": false, "camping": false, "guiding": false,
}
const GOODS_UNIT_FACTORY: int = 1250    # factory sells goods to the general store
const GOODS_EXPORT: int = 1050
const FLOUR_UNIT: int = 140              # flour for one person-day of bread
const BREAD_UNIT: int = 430              # bakery to grocery, one person-day share
## one worker-day of output: lumber, gravel and stone, and gold ore
const SAW_UNIT: int = 90000
const QUARRY_UNIT: int = 80000
const GOLD_UNIT: int = 220000


static func cfg(btype: String) -> Dictionary:
	return TYPES.get(btype, {})


static func provider_type(category: String) -> String:
	for k in TYPES:
		if str(TYPES[k]["category"]) == category:
			return k
	return ""


static func book(w: LTWorld, category: String, where: String, cents: int) -> void:
	var sb: Dictionary = w.spend_book
	if not sb.has(category):
		sb[category] = {"local": 0, "outside": 0, "last_local": 0, "last_outside": 0, "latent": 0, "last_latent": 0}
	sb[category][where] = int(sb[category][where]) + cents


static func month_roll(w: LTWorld) -> void:
	# a running average over about six months, so one big month does not look like a market
	for k in w.spend_book:
		var e: Dictionary = w.spend_book[k]
		var first: bool = not e.has("rolled")
		e["rolled"] = true
		for pair in [["last_local", "local"], ["last_outside", "outside"], ["last_latent", "latent"]]:
			e[pair[0]] = int(e[pair[1]]) if first else int(float(e[pair[0]]) * 0.83 + float(e[pair[1]]) * 0.17)
			# and over about a year, for the trades where one sale makes a month
			var yk: String = pair[0].replace("last_", "year_")
			e[yk] = int(e[pair[1]]) if first else int(float(e.get(yk, e[pair[1]])) * 0.92 + float(e[pair[1]]) * 0.08)
		e["local"] = 0
		e["outside"] = 0
		e["latent"] = 0


## Lumpy trades: a house sale, a funeral or a court case makes one month look big.
const LUMPY: Array = ["real_estate", "legal", "funeral", "tuition"]


static func market_size(w: LTWorld, category: String) -> int:
	var e: Dictionary = w.spend_book.get(category, {})
	if e.is_empty():
		return 0
	var six: int = int(e["last_local"]) + int(e["last_outside"]) + int(e["last_latent"])
	if LUMPY.has(category) and e.has("year_local"):
		# a careful look at the whole year, not the last busy month
		return mini(six, int(e["year_local"]) + int(e["year_outside"]) + int(e["year_latent"]))
	return six


## Pays for a service. Returns the amount paid. The local option wins if it is
## fair for its price, distance and reputation; the outside option costs a drive.
static func spend(w: LTWorld, from_acct: String, category: String, amount: int, home_lot: int, chooser: Dictionary = {}) -> int:
	if amount <= 0:
		return 0
	var btype: String = provider_type(category)
	var best: Dictionary = {}
	var best_s: float = -1e9
	if btype != "":
		for b in w.open_businesses(btype):
			if not _can_serve(w, b):
				continue
			var mins: float = w.travel_minutes(maxi(0, home_lot), int(b["lot"]))
			var s: float = -float(amount) * float(b["price_level"]) / 100.0 - mins * 0.25 + (float(b["reputation"]) - 50.0) * 0.3
			if not chooser.is_empty():
				s += w.memory_weight(chooser, "good_shop", int(b["id"])) * 0.4 + w.memory_weight(chooser, "bad_shop", int(b["id"])) * 0.6
			if s > best_s:
				best_s = s
				best = b
	var outside_ok: bool = bool(OUTSIDE_OPTION.get(category, true))
	var out_s: float = -float(amount) / 100.0 - (w.minutes_to_outside(maxi(0, home_lot)) * 0.5 if home_lot >= 0 else 20.0) - 6.0
	if not best.is_empty() and (best_s >= out_s or not outside_ok):
		var price: int = int(float(amount) * float(best["price_level"]))
		var paid: int = w.ledger.pay(from_acct, w.acct_b(best), price, "local_services")
		_record_sale(w, best, paid)
		book(w, category, "local", paid)
		if not chooser.is_empty():
			var exp: float = LTEconomy._service_experience(w, best, int(best["customers_today"]) * 3)
			best["experience_avg"] = float(best["experience_avg"]) * 0.95 + exp * 0.05
			if exp > 70.0:
				w.remember(chooser, "good_shop", int(best["id"]), 2.0)
			elif exp < 40.0:
				w.remember(chooser, "bad_shop", int(best["id"]), -4.0)
		return paid
	if not outside_ok:
		book(w, category, "latent", amount)
		return 0
	var paid2: int = w.ledger.pay(from_acct, "outside", amount, "outside_services")
	book(w, category, "outside", paid2)
	return paid2


const HOME_CAP: Dictionary = {"childcare": 12.0, "repair_shop": 4.0, "bakery": 30.0, "law_office": 3.0, "real_estate": 3.0, "guide_service": 4.0, "construction": 3.0, "trucking": 2.0}


## Room for one more customer today: seats, rooms, bays, or one person's hands.
static func has_room(w: LTWorld, b: Dictionary) -> bool:
	if b.has("bplan"):
		var cap: float = LTBuildings.capacity(b["bplan"])
		return cap <= 0.0 or float(b["customers_today"]) < cap
	if bool(b.get("home_based", false)):
		return float(b["customers_today"]) < float(HOME_CAP.get(str(b["type"]), 8.0)) * (1.0 + float(b["staff"].size()) * 0.5)
	return true


static func _can_serve(w: LTWorld, b: Dictionary) -> bool:
	# a full place turns people away: every room taken, every seat and bay busy
	if b.has("bplan"):
		var cap: float = LTBuildings.capacity(b["bplan"])
		if cap > 0.0 and float(b["customers_today"]) >= cap:
			return false
	elif bool(b.get("home_based", false)):
		# one person working from home: a licensed home daycare takes 12 children,
		# a home mechanic a few jobs a day, a home office a few clients
		var hcap: float = float(HOME_CAP.get(str(b["type"]), 8.0)) * (1.0 + float(b["staff"].size()) * 0.5)
		if float(b["customers_today"]) >= hcap:
			return false
	if int(TYPES[str(b["type"])]["staff"]) == 0:
		return true
	var owner: Dictionary = w.cit(int(b["owners"][0]))
	return b["staff"].size() > 0 or (w.is_present(owner) and int(owner.get("jail_until", -1)) < w.day)


static func _record_sale(w: LTWorld, b: Dictionary, paid: int) -> void:
	b["customers_today"] = int(b["customers_today"]) + 1
	b["sales_today"] = int(b["sales_today"]) + paid
	b["month_revenue"] = int(b["month_revenue"]) + paid
	b["lifetime_revenue"] = int(b["lifetime_revenue"]) + paid
	var sup: float = float(TYPES[str(b["type"])]["supply"])
	if sup > 0.0:
		var cost: int = w.ledger.pay(w.acct_b(b), "outside", int(float(paid) * sup), "service_supplies")
		b["month_costs"] = int(b["month_costs"]) + cost


# ================================================================ founding estimates

static func estimate(w: LTWorld, btype: String) -> Dictionary:
	var key: String = "%d|%s" % [w.day, btype]
	if w.market.has("est_cache") and w.market["est_cache"].has(key):
		return w.market["est_cache"][key]
	var r: Dictionary = _estimate(w, btype)
	if not w.market.has("est_cache"):
		w.market["est_cache"] = {}
	w.market["est_cache"][key] = r
	return r


static func _estimate(w: LTWorld, btype: String) -> Dictionary:
	var c: Dictionary = TYPES[btype]
	var cat: String = str(c["category"])
	var count: int = w.open_businesses(btype).size()
	var gross: float = 0.0
	var why: String = ""
	var doubt: String = "not enough customers in a town this size"
	match btype:
		"factory":
			var stores: int = w.open_businesses("general_store").size()
			gross = 30.0 * 40.0 * float(GOODS_EXPORT) + float(stores) * 30.0 * 6.0 * float(GOODS_UNIT_FACTORY)
			why = "there is industrial land, and goods can be sold to the region and to local stores"
			doubt = "a factory costs more than anyone here can raise"
			return {"gross": gross / float(count + 1), "margin": 0.35, "why": why, "doubt": doubt}
		"mill":
			var farms: int = w.open_businesses("farm").size()
			if farms == 0:
				return {"gross": 0.0, "margin": 0.0, "why": "", "doubt": "there is no local farm to buy grain from"}
			gross = float(farms) * 30.0 * 60.0 * float(FLOUR_UNIT) + 30.0 * 80.0 * float(FLOUR_UNIT) * 0.7
			why = "%d local farms grow grain that now leaves town unmilled" % farms
			return {"gross": gross / float(count + 1), "margin": 0.4, "why": why, "doubt": "milling margins are thin"}
		"bakery":
			var gro: int = w.open_businesses("grocery").size()
			if gro == 0:
				return {"gross": 0.0, "margin": 0.0, "why": "", "doubt": "there is no grocery to sell bread to"}
			gross = float(w.market.get("food_units_day", 50.0)) * 0.15 * 30.0 * float(BREAD_UNIT)
			why = "the grocery trucks in all its bread from outside"
			return {"gross": gross / float(count + 1), "margin": 0.5, "why": why, "doubt": "the grocery buys too little bread"}
		"sawmill":
			gross = 22.0 * 4.0 * float(SAW_UNIT) * LTRegion.index(w)
			return {"gross": gross / float(count + 1), "margin": 0.42, "why": "the %s is full of timber that leaves the county uncut" % LTTerrain.t(w).get("forest_name", "forest"), "doubt": "a sawmill costs more than anyone here can raise"}
		"quarry":
			if int(w.city["laws"].get("mining", 1)) < 1:
				return {"gross": 0.0, "margin": 0.0, "why": "", "doubt": "the city has banned mining"}
			gross = 22.0 * 4.0 * float(QUARRY_UNIT) * LTRegion.index(w)
			return {"gross": gross / float(count + 1), "margin": 0.45, "why": "there is good granite and gravel in the hills and the county always needs it for roads", "doubt": "a quarry costs more than anyone here can raise"}
		"gold_mine":
			if int(w.city["laws"].get("mining", 1)) < 2:
				return {"gross": 0.0, "margin": 0.0, "why": "", "doubt": "the city does not allow gold mining"}
			gross = 22.0 * 9.0 * float(GOLD_UNIT) * float(w.region.get("gold_price", 1.0))
			return {"gross": gross / float(count + 1), "margin": 0.35, "why": "prospectors found gold in the hills, as people did across the Black Hills", "doubt": "a mine takes millions and outside investors"}
		"bank":
			if not bool(w.city["laws"].get("bank_charter", 0)):
				return {"gross": 0.0, "margin": 0.0, "why": "", "doubt": "the city has not chartered a local bank"}
			var book_v: float = 0.0
			for d in w.debts:
				if LTFinance.is_active(d) and str(d["creditor"]) == "bank":
					book_v += float(d["balance"])
			gross = book_v * 0.07 / 12.0 * 0.15
			why = "the town pays %s in interest to an outside bank every year" % LTMoney.fmt(int(book_v * 0.07))
			return {"gross": gross / float(count + 1), "margin": 0.6, "why": why, "doubt": "not enough borrowers yet"}
	var size: float = float(market_size(w, cat))
	if cat == "tuition":
		size = float(_potential_tuition(w))
	elif cat == "lodging":
		size = float(_potential_lodging(w))
	elif cat == "storage":
		# local shops plus distribution work for the region
		size = float(w.open_businesses("grocery").size() + w.open_businesses("general_store").size() + w.open_businesses("cafe").size()) * 30.0 * 1800.0 + 750000.0 * LTRegion.index(w)
	elif cat == "freight":
		size += 600000.0 * LTRegion.index(w)
	elif cat == "childcare":
		size = maxf(size, float(_potential_childcare(w)))
	var share: float = 0.75 / float(count + 1)
	gross = size * share
	var e: Dictionary = w.spend_book.get(cat, {})
	var outside_part: int = int(e.get("last_outside", 0))
	if outside_part > 0:
		why = "the town spent %s last month on %s out of town" % [LTMoney.fmt(outside_part), _cat_words(cat)]
	else:
		why = "people here need %s and nobody local offers it" % _cat_words(cat)
	return {"gross": gross, "margin": 1.0 - float(c["supply"]), "why": why, "doubt": doubt}


static func _cat_words(cat: String) -> String:
	return {"outdoor_gear": "fishing, hunting and hiking gear", "boating": "boat rentals and docking", "camping": "campsites for visitors", "guiding": "hunting and fishing guides", "medical": "doctor visits", "pharmacy": "prescriptions", "tuition": "private schooling", "repairs": "car and home repairs", "storage": "storage for shop deliveries", "freight": "freight", "lodging": "rooms for visiting crews and travelers", "bar": "a night out", "childcare": "child care", "funeral": "funerals", "legal": "lawyers", "real_estate": "help buying and selling houses"}.get(cat, cat)


static func _potential_tuition(w: LTWorld) -> int:
	var kids: int = 0
	for c in w.citizens:
		if w.is_present(c) and w.age_years(c) >= 5 and w.age_years(c) < 18:
			var h: Dictionary = w.hh(int(c["household"]))
			if w.household_cash(h) > LTMoney.dollars(25000.0):
				kids += 1
	var pull: float = clampf(1.2 - LTCivic.school_quality(w), 0.1, 1.0)
	return int(float(kids) * float(LTMoney.dollars(380.0)) * pull)


static func _potential_lodging(w: LTWorld) -> int:
	var crews: int = 0
	for p in w.projects:
		if str(p["status"]) == "building" and str(p["winner"].get("kind", "")) == "outside":
			crews += 6
	return int(float(crews) * 30.0 * 7000.0 + (1.0 + float(w.alive_count()) * 0.003) * 30.0 * 8500.0 * LTRegion.index(w))


static func _potential_childcare(w: LTWorld) -> int:
	var n: int = 0
	for h in w.households:
		if _needs_childcare(w, h):
			for m in w.household_members(h):
				if w.age_years(m) < 5:
					n += 1
	return n * LTMoney.dollars(620.0)


static func _needs_childcare(w: LTWorld, h: Dictionary) -> bool:
	var adults: Array = w.household_adults(h)
	if adults.is_empty():
		return false
	var small: bool = false
	for m in w.household_members(h):
		if w.age_years(m) < 5:
			small = true
	if not small:
		return false
	for a in adults:
		if str(a["job"]["kind"]) == "none" or bool(a["retired"]):
			return false
	return true


# ================================================================ daily and monthly demand

static func daily(w: LTWorld) -> void:
	_bar_visits(w)
	_lodging(w)
	_outdoor_visitors(w)
	if not LTCalendar.is_weekend(w.day):
		for b in w.open_businesses("trucking"):
			if b["staff"].size() > 0:
				spend(w, "outside", "freight", int(20000.0 * LTRegion.index(w)), int(b["lot"]))
		for b2 in w.open_businesses("warehouse"):
			if b2["staff"].size() > 0:
				spend(w, "outside", "storage", int(25000.0 * LTRegion.index(w)), int(b2["lot"]))
	for b in w.businesses:
		if str(b["status"]) != "open":
			continue
		match str(b["type"]):
			"factory":
				_factory_day(w, b)
			"mill":
				_mill_day(w, b)
			"bakery":
				_bakery_day(w, b)
			"sawmill":
				_land_industry_day(w, b, SAW_UNIT, 0.38, "timber from the state forest", 0.0)
			"quarry":
				_land_industry_day(w, b, QUARRY_UNIT, 0.3, "fuel and blasting", 0.4)
			"gold_mine":
				_land_industry_day(w, b, GOLD_UNIT, 0.5, "fuel, reagents and power", 1.0)
		if TYPES.has(str(b["type"])) and int(b["owners"][0]) % 7 == w.day % 7:
			_service_price(w, b)


static func _service_price(w: LTWorld, b: Dictionary) -> void:
	var owner: Dictionary = w.cit(int(b["owners"][0]))
	if owner.is_empty():
		return
	var t: Dictionary = owner["traits"]
	var rivals: int = w.open_businesses(str(b["type"])).size() - 1
	var target: float = 1.0 + float(t["greed"] - 50) / 300.0
	if rivals == 0 and int(t["greed"]) > 65 and int(t["honesty"]) < 40:
		target += 0.15
	if int(b["loss_months"]) > 0:
		target += 0.05
	b["price_level"] = clampf(float(b["price_level"]) + clampf(target - float(b["price_level"]), -0.03, 0.03), 0.8, 1.5)
	var rep: float = float(b["reputation"]) + (float(b["experience_avg"]) - 55.0) * 0.01
	if float(b["price_level"]) > 1.25:
		rep -= 0.2
	b["reputation"] = clampf(rep, 0.0, 100.0)


static func monthly_household(w: LTWorld, h: Dictionary) -> void:
	var adults: Array = w.household_adults(h)
	if adults.is_empty():
		return
	var payer: Dictionary = adults[0]
	for a in adults:
		if w.cash(a) > w.cash(payer):
			payer = a
	var home: int = int(h["lot"])
	# car and home repairs come up now and then
	if w.rng.randf() < 0.35:
		var amt: int = LTMoney.dollars(w.rng.randf_range(60.0, 420.0))
		spend(w, w.acct_p(payer), "repairs", amt, home, payer)
	# prescriptions for chronic conditions
	for m in w.household_members(h):
		if bool(m["chronic"]) or w.age_years(m) >= 70:
			spend(w, w.acct_p(payer), "pharmacy", LTMoney.dollars(70.0), home, payer)
	# child care when every adult works
	if _needs_childcare(w, h):
		for m in w.household_members(h):
			if w.age_years(m) < 5:
				var paid: int = spend(w, w.acct_p(payer), "childcare", LTMoney.dollars(620.0), home, payer)
				if paid > 0 and not w.open_businesses("childcare").is_empty():
					m["needs"]["social"] = float(m["needs"]["social"]) + 10.0
	# private school, if a family can pay and thinks the public school is weak
	var school: Array = w.open_businesses("private_school")
	if not school.is_empty():
		for m in w.household_members(h):
			var age: int = w.age_years(m)
			if age < 5 or age >= 18 or str(m["student"]) == "dropout":
				continue
			var rich: bool = w.household_cash(h) > LTMoney.dollars(25000.0)
			var want: float = (1.0 - LTCivic.school_quality(w)) * 60.0 + float(payer["traits"]["ambition"]) * 0.3
			if str(m["student"]) == "private school" or (rich and want > 45.0):
				var p: int = spend(w, w.acct_p(payer), "tuition", LTMoney.dollars(380.0), home, payer)
				if p > 0:
					if str(m["student"]) != "private school":
						w.log_sim(payer, "Enrolled %s at %s. Reason: the public school felt weak and the family could pay." % [m["first_name"], school[0]["name"]], true)
					m["student"] = "private school"
				elif str(m["student"]) == "private school":
					m["student"] = "town school" if LTCivic.has_service(w, "school") else "outside school"
					w.log_sim(payer, "Took %s out of private school. Reason: could not pay the tuition." % m["first_name"], true)


static func _bar_visits(w: LTWorld) -> void:
	var bars: Array = w.open_businesses("bar")
	var night_out: bool = LTCalendar.weekday(w.day) == "Friday" or LTCalendar.weekday(w.day) == "Saturday"
	for c in w.citizens:
		if not w.is_present(c) or w.age_years(c) < 21 or int(c.get("jail_until", -1)) >= w.day:
			continue
		var n: Dictionary = c["needs"]
		var habit: float = float(c.get("addiction", {}).get("alcohol", 0.0))
		var want: float = (100.0 - float(n["fun"])) * 0.002 + (100.0 - float(n["social"])) * 0.002 + float(c["traits"]["sociability"]) * 0.0008 + habit * 0.006
		if night_out:
			want *= 2.0
		if w.cash(c) < LTMoney.dollars(60.0) and habit < 40.0:
			continue
		if w.rng.randf() > want * 0.35:
			continue
		var tab: int = LTMoney.dollars(14.0 + habit * 0.4)
		var hl: int = int(w.hh(int(c["household"]))["lot"])
		var paid: int = spend(w, w.acct_p(c), "bar", tab, hl, c)
		if paid > 0:
			n["fun"] = float(n["fun"]) + 10.0
			n["social"] = float(n["social"]) + 12.0
			LTHealth.drink(w, c, paid)
			if not bars.is_empty():
				for other in bars[0]["staff"]:
					if w.rng.randf() < 0.1 and w.is_present(w.cit(int(other))):
						LTPeople.relate_event(w, c, w.cit(int(other)), "acquaintance", 1.0, 2.0)


static func _lodging(w: LTWorld) -> void:
	var hotels: Array = w.open_businesses("hotel")
	for p in w.projects:
		if str(p["status"]) != "building" or str(p["winner"].get("kind", "")) != "outside":
			continue
		# most outside crews drive home each night; about a third of them stay over,
		# a room each
		var crew: int = int(w.companies[int(p["winner"]["id"])]["crew"])
		for k in crew:
			if w.rng.randf() >= 0.33:
				continue
			if hotels.is_empty():
				book(w, "lodging", "latent", LTMoney.dollars(70.0))
			else:
				spend(w, "outside", "lodging", LTMoney.dollars(70.0), -1)
	# travelers passing through, more when the region is doing well
	var travelers: float = (1.0 + float(w.alive_count()) * 0.003) * LTRegion.index(w)
	var n: int = int(travelers)
	if w.rng.randf() < travelers - float(n):
		n += 1
	for i in n:
		if hotels.is_empty():
			book(w, "lodging", "latent", LTMoney.dollars(85.0))
		else:
			spend(w, "outside", "lodging", LTMoney.dollars(85.0), -1)


## Visitors who come for the outdoors: summer at the lake and on the trails, fall for
## hunting, a few ice fishermen in winter. They spend on campsites, gear, guides and
## boats; with no local business to take it, the demand is noted and goes unmet.
static func _outdoor_visitors(w: LTWorld) -> void:
	var tt: Dictionary = LTTerrain.t(w)
	if tt.is_empty():
		return
	var m: int = LTCalendar.month_index(w.day)
	var season: float = 1.8 if m >= 5 and m <= 7 else (1.3 if m >= 8 and m <= 10 else (0.8 if m >= 2 and m <= 4 else 0.5))
	if m >= 9 and m <= 11 and int(w.city["laws"].get("hunting_season", 1)) == 0:
		season *= 0.6
	var monthly: float = (25.0 * float(tt["lakes"].size()) + (40.0 if LTTerrain.has(w, "forest") else 8.0) + (25.0 if LTTerrain.has(w, "mountain") else 0.0) + LTRail.visitor_draw(w)) * season * LTRegion.index(w)
	var day_n: float = monthly / 30.0
	var n: int = int(day_n)
	if w.rng.randf() < day_n - float(n):
		n += 1
	for i in n:
		_visitor_spend(w, "camping", LTMoney.dollars(45.0))
		_visitor_spend(w, "outdoor_gear", LTMoney.dollars(30.0))
		if w.rng.randf() < 0.15:
			_visitor_spend(w, "guiding", LTMoney.dollars(90.0))
		if w.rng.randf() < 0.3:
			_visitor_spend(w, "boating", LTMoney.dollars(50.0))


static func _visitor_spend(w: LTWorld, cat: String, amount: int) -> void:
	if provider_type(cat) != "" and not w.open_businesses(provider_type(cat)).is_empty():
		spend(w, "outside", cat, amount, -1)
	else:
		book(w, cat, "latent", amount)


# ================================================================ production chains

static func _crew_output(w: LTWorld, b: Dictionary, per_worker: float) -> float:
	var out: float = 0.0
	var skill: String = str(TYPES[str(b["type"])]["skill"])
	for sid in b["staff"]:
		var s: Dictionary = w.cit(int(sid))
		if w.is_present(s) and int(s["sick_days"]) == 0 and int(s.get("jail_until", -1)) < w.day:
			out += per_worker * (0.6 + float(s["skills"][skill]) / 200.0)
	var owner: Dictionary = w.cit(int(b["owners"][0]))
	if w.is_present(owner):
		out += per_worker * 0.5
	return out * float(b["equipment"])


static func _factory_day(w: LTWorld, b: Dictionary) -> void:
	if LTCalendar.is_weekend(w.day):
		return
	var units: float = _crew_output(w, b, 7.0) * LTRegion.index(w)
	var input_cost: int = int(units * float(GOODS_EXPORT) * 0.45)
	# pollution rules raise the cost of running clean
	var rule: float = float(w.city["laws"].get("pollution_rule", 0.5))
	input_cost += int(units * 40.0 * rule)
	input_cost = LTRail.input_cost(w, b, input_cost)
	var paid: int = w.ledger.pay(w.acct_b(b), "outside", input_cost, "factory_inputs")
	b["month_costs"] = int(b["month_costs"]) + paid
	if paid < input_cost:
		units *= float(paid) / float(maxi(1, input_cost))
	b["stock"] = float(b["stock"]) + units
	b["pollution"] = maxf(0.0, (1.0 - rule) * units * 0.02)
	if float(b["stock"]) > 60.0 and LTCalendar.weekday(w.day) == "Thursday":
		var sold: float = float(b["stock"]) - 20.0
		var rev: int = LTRail.export_rev(w, b, int(sold * float(GOODS_EXPORT) * LTRegion.index(w)))
		w.ledger.pay("outside", w.acct_b(b), rev, "exports")
		b["stock"] = 20.0
		b["month_revenue"] = int(b["month_revenue"]) + rev
		b["lifetime_revenue"] = int(b["lifetime_revenue"]) + rev
	# pollution reaches nearby homes
	if float(b["pollution"]) > 0.05:
		for l in w.lots:
			var d: int = absi(int(l["col"]) - int(w.lot(int(b["lot"]))["col"])) + absi(int(l["row"]) - int(w.lot(int(b["lot"]))["row"]))
			if d <= 2:
				for u in l["units"]:
					if int(u) >= 0:
						for m in w.household_members(w.hh(int(u))):
							m["needs"]["health"] = float(m["needs"]["health"]) - float(b["pollution"]) * (0.3 if d == 1 else 0.15)


static func _mill_day(w: LTWorld, b: Dictionary) -> void:
	var cap: float = _crew_output(w, b, 40.0)
	var got: float = 0.0
	for f in w.open_businesses("farm"):
		var take: float = floorf(minf(cap - got, float(f["produce"]) * 0.3))
		if take < 1.0:
			continue
		var cost: int = int(take * float(LTEconomy.PRODUCE_EXPORT_PRICE) * 0.45)
		var paid: int = w.ledger.pay(w.acct_b(b), w.acct_b(f), cost, "local_grain")
		if paid <= 0:
			break
		take = take * float(paid) / float(cost)
		f["produce"] = float(f["produce"]) - take
		f["month_revenue"] = int(f["month_revenue"]) + paid
		f["lifetime_revenue"] = int(f["lifetime_revenue"]) + paid
		b["month_costs"] = int(b["month_costs"]) + paid
		got += take
	b["stock"] = float(b["stock"]) + got * 0.9
	if float(b["stock"]) > 300.0 and LTCalendar.weekday(w.day) == "Tuesday":
		var sold: float = float(b["stock"]) - 100.0
		var rev: int = LTRail.export_rev(w, b, int(sold * float(FLOUR_UNIT) * 0.7))
		w.ledger.pay("outside", w.acct_b(b), rev, "exports")
		b["stock"] = 100.0
		b["month_revenue"] = int(b["month_revenue"]) + rev
		b["lifetime_revenue"] = int(b["lifetime_revenue"]) + rev


## Sawmill, quarry and gold mine: crews turn the land into something to sell to the
## region. A mine's ore runs thinner every year and the gold price swings; dust and
## runoff follow the pollution rule like a factory's smoke.
static func _land_industry_day(w: LTWorld, b: Dictionary, unit: int, input_share: float, inputs: String, dirt: float) -> void:
	if LTCalendar.is_weekend(w.day):
		return
	var btype: String = str(b["type"])
	if btype == "quarry" and int(w.city["laws"].get("mining", 1)) < 1 or btype == "gold_mine" and int(w.city["laws"].get("mining", 1)) < 2:
		return
	var units: float = _crew_output(w, b, 1.0)
	var price: float = LTRegion.index(w)
	if btype == "gold_mine":
		var grade: float = float(b.get("ore_grade", 1.0))
		b["ore_grade"] = maxf(0.1, grade - 0.0004)
		price = float(w.region.get("gold_price", 1.0)) * grade
	var rule: float = float(w.city["laws"].get("pollution_rule", 0.5))
	var input_cost: int = LTRail.input_cost(w, b, int(units * float(unit) * input_share + units * 4000.0 * rule * dirt))
	var paid: int = w.ledger.pay(w.acct_b(b), "outside", input_cost, inputs)
	b["month_costs"] = int(b["month_costs"]) + paid
	var rev: int = LTRail.export_rev(w, b, int(units * float(unit) * price))
	if rev > 0:
		w.ledger.pay("outside", w.acct_b(b), rev, "exports")
		b["month_revenue"] = int(b["month_revenue"]) + rev
		b["lifetime_revenue"] = int(b["lifetime_revenue"]) + rev
	b["pollution"] = maxf(0.0, (1.0 - rule) * units * 0.01 * dirt)


static func _bakery_day(w: LTWorld, b: Dictionary) -> void:
	var want: float = float(w.market.get("food_units_day", 50.0)) * 0.15 * 3.0 - float(b["stock"])
	if want <= 0.0:
		return
	var made: float = minf(want, _crew_output(w, b, 40.0))
	var flour_cost: float = 0.0
	var need: float = made
	for m in w.open_businesses("mill"):
		var take: float = floorf(minf(need, float(m["stock"])))
		if take < 1.0:
			continue
		var cost: int = int(take * float(FLOUR_UNIT))
		var paid: int = w.ledger.pay(w.acct_b(b), w.acct_b(m), cost, "local_flour")
		m["stock"] = float(m["stock"]) - take * float(paid) / float(maxi(1, cost))
		m["month_revenue"] = int(m["month_revenue"]) + paid
		m["lifetime_revenue"] = int(m["lifetime_revenue"]) + paid
		b["month_costs"] = int(b["month_costs"]) + paid
		need -= take
		if b["supplier"] == "Valley Wholesale":
			b["supplier"] = str(m["name"])
	if need > 0.0:
		flour_cost = need * float(FLOUR_UNIT) * 1.4
		var p2: int = w.ledger.pay(w.acct_b(b), "outside", int(flour_cost), "imports")
		b["month_costs"] = int(b["month_costs"]) + p2
		made -= need * (1.0 - float(p2) / maxf(1.0, flour_cost))
	b["stock"] = float(b["stock"]) + maxf(0.0, made)


## A grocery takes bread from a local bakery before importing. Returns units bought.
static func grocery_buys_bread(w: LTWorld, g: Dictionary, want: float) -> float:
	var got: float = 0.0
	for bk in w.open_businesses("bakery"):
		var take: float = floorf(minf(want - got, float(bk["stock"])))
		if take < 1.0:
			continue
		var cost: int = int(take * float(BREAD_UNIT))
		var paid: int = w.ledger.pay(w.acct_b(g), w.acct_b(bk), cost, "local_bread")
		take = take * float(paid) / float(maxi(1, cost))
		bk["stock"] = float(bk["stock"]) - take
		_record_sale(w, bk, paid)
		g["month_costs"] = int(g["month_costs"]) + paid
		got += take
	return got


## A general store takes goods from a local factory before importing. Returns units bought.
static func store_buys_goods(w: LTWorld, s: Dictionary, want: float) -> float:
	var got: float = 0.0
	for f in w.open_businesses("factory"):
		var take: float = floorf(minf(want - got, float(f["stock"])))
		if take < 1.0:
			continue
		var cost: int = int(take * float(GOODS_UNIT_FACTORY))
		var paid: int = w.ledger.pay(w.acct_b(s), w.acct_b(f), cost, "local_goods")
		take = take * float(paid) / float(maxi(1, cost))
		f["stock"] = float(f["stock"]) - take
		f["month_revenue"] = int(f["month_revenue"]) + paid
		f["lifetime_revenue"] = int(f["lifetime_revenue"]) + paid
		s["month_costs"] = int(s["month_costs"]) + paid
		got += take
	return got


## The delivery fee on an import order: a local trucking firm hauls it if there is one.
static func pay_freight(w: LTWorld, b: Dictionary) -> int:
	var fee: int = LTEconomy.IMPORT_DELIVERY_FEE
	var paid: int = spend(w, w.acct_b(b), "freight", fee, int(b["lot"]))
	b["month_costs"] = int(b["month_costs"]) + paid
	return paid


## A local warehouse holds stock close by: shorter delivery, small storage fee.
static func delivery_days(w: LTWorld, b: Dictionary, base: int) -> int:
	if w.open_businesses("warehouse").is_empty():
		return base
	var paid: int = spend(w, w.acct_b(b), "storage", LTMoney.dollars(18.0), int(b["lot"]))
	b["month_costs"] = int(b["month_costs"]) + paid
	return maxi(1, base - 1)


# ================================================================ the local bank

static func local_bank(w: LTWorld) -> Dictionary:
	for b in w.open_businesses("bank"):
		if w.biz_cash(b) > LTMoney.dollars(20000.0):
			return b
	return {}
