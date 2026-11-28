class_name LTRail
extends RefCounted
## The railroad, the way it really works in the Dakotas: the track belongs to a
## private regional railroad (on many South Dakota lines the state owns the track
## and leases it to the operator). Nobody in town can start a railroad. What
## people really do:
##
## - A business that ships in bulk (grain, flour, lumber, stone, factory goods)
##   pays for its own spur track off the main line, and the railroad has to
##   agree that the business will ship enough to be worth stopping for.
##   Rail costs about a third of what trucks charge per ton.
## - The city builds a depot with a platform and a public "team track" siding
##   where any business can load a car.
## - Once there is a depot and enough people, the state's regional rail service
##   stops twice a day: visitors come in, and commuters ride to jobs in the city.

const RAILROAD: String = "Dakota and Western Railroad"
const REACH: float = 45.0           # a spur needs a lot right beside the right of way
const SPUR_PER_M: int = 98000        # $980 a meter of track, ties and ballast
const SWITCH_COST: int = 15000000    # $150,000 for the turnout and signals
const DEPOT_COST: int = 65000000     # depot, platform and team track
const PASSENGER_AT: int = 300        # residents before the state rail service stops
const SHIPPERS: Dictionary = {
	"farm": "grain", "mill": "flour and feed", "sawmill": "lumber", "quarry": "crushed stone",
	"factory": "factory goods", "gold_mine": "ore concentrate",
}


static func line_z(w: LTWorld) -> float:
	return LTTerrain.rail_z(w)


static func has_line(w: LTWorld) -> bool:
	return not LTTerrain.t(w).is_empty()


## Meters from a lot's nearest edge to the main line.
static func distance(w: LTWorld, l: Dictionary) -> float:
	if not has_line(w) or l.is_empty():
		return INF
	var z: float = line_z(w)
	var z0: float = float(l["z0"])
	var z1: float = float(l["z1"])
	if z >= z0 and z <= z1:
		return 0.0
	return minf(absf(z - z0), absf(z - z1))


static func spur_cost(w: LTWorld, l: Dictionary) -> int:
	return SWITCH_COST + int(maxf(20.0, distance(w, l)) * float(SPUR_PER_M))


static func has_depot(w: LTWorld) -> bool:
	return LTCivic.has_service(w, "depot")


static func passenger_service(w: LTWorld) -> bool:
	return has_depot(w) and w.residents() >= PASSENGER_AT


## How much better a business does shipping by rail: its own spur saves the most,
## loading at the city's team track a little. 1.0 is all by truck.
static func ship_factor(w: LTWorld, b: Dictionary) -> float:
	if not SHIPPERS.has(str(b.get("type", ""))):
		return 1.0
	if bool(b.get("rail_spur", false)):
		return 1.07
	if has_depot(w) and distance(w, w.lot(int(b["lot"]))) < 400.0:
		return 1.03
	return 1.0


## What a sale out of town brings home after freight.
static func export_rev(w: LTWorld, b: Dictionary, rev: int) -> int:
	return int(float(rev) * ship_factor(w, b))


## What inputs cost delivered.
static func input_cost(w: LTWorld, b: Dictionary, cost: int) -> int:
	return int(float(cost) * (2.0 - ship_factor(w, b)))


# ---------------------------------------------------------------- spurs

## Once a month a busy bulk shipper near the tracks weighs a spur of its own.
static func monthly(w: LTWorld) -> void:
	if not has_line(w):
		return
	for b in w.businesses:
		if str(b["status"]) != "open" or bool(b.get("rail_spur", false)) or not SHIPPERS.has(str(b["type"])) or bool(b.get("home_based", false)):
			continue
		if int(b.get("loss_months", 0)) > 0 or w.day - int(b.get("opened_day", 0)) < 180 or w.day - int(b.get("spur_asked", -9999)) < 365:
			continue
		var l: Dictionary = w.lot(int(b["lot"]))
		if distance(w, l) > REACH:
			continue
		consider_spur(w, b)


## The owner's decision, with the railroad's say. Returns a reason.
static func consider_spur(w: LTWorld, b: Dictionary) -> String:
	b["spur_asked"] = w.day
	var l: Dictionary = w.lot(int(b["lot"]))
	var cost: int = spur_cost(w, l)
	var owner: Dictionary = w.cit(int(b["owners"][0]))
	var hist: Array = b.get("month_profit_hist", [])
	var rev_month: float = float(b.get("month_revenue", 0))
	# the railroad wants enough cars a year to be worth a stop: about $40,000 a month shipped
	if rev_month < float(LTMoney.dollars(40000.0)):
		var why0: String = "%s will not stop for less than about a car a week; %s ships too little" % [RAILROAD, b["name"]]
		w.log_biz(b, "Asked about a rail spur. Reason it did not happen: %s." % why0)
		return why0
	var saves_year: float = rev_month * 12.0 * 0.07
	var payback: float = float(cost) / maxf(1.0, saves_year)
	var t: Dictionary = owner.get("traits", {}) if not owner.is_empty() else {}
	var patience: float = 6.0 + (float(t.get("discipline", 50)) - 50.0) / 10.0 + (float(t.get("intelligence", 50)) - 50.0) / 12.0
	if payback > patience:
		var why1: String = "a %s spur would take %.0f years to pay for itself in freight savings" % [LTMoney.fmt(cost), payback]
		w.log_biz(b, "Priced a rail spur and passed. Reason: %s." % why1)
		return why1
	var acct: String = w.acct_b(b)
	var cash: int = w.biz_cash(b)
	var down: int = mini(cash - LTMoney.dollars(20000.0), cost)
	if down < int(float(cost) * 0.25):
		var why2: String = "not enough cash for the bank's 25%% down on a %s spur" % LTMoney.fmt(cost)
		w.log_biz(b, "Wanted a rail spur. Reason it waits: %s." % why2)
		return why2
	w.ledger.pay(acct, "outside", down, "rail_spur")
	if down < cost:
		var d: Dictionary = LTFinance.new_debt(w, "b", int(b["id"]), "bank", -1, "business_loan", cost - down, 0.075, 120, "rail spur", int(l["id"]), [])
		LTFinance.fund_loan(w, d, "outside", cost - down)
	b["rail_spur"] = true
	b["spur_day"] = w.day
	b["spur_m"] = int(maxf(20.0, distance(w, l)))
	l["value"] = int(l["value"]) + int(float(cost) * 0.6)
	var why: String = "rail costs about a third of trucking per ton; the %s spur pays for itself in about %.0f years" % [LTMoney.fmt(cost), payback]
	w.log_biz(b, "Built a %d meter spur track off the %s main line to ship %s by the carload. Reason: %s." % [int(b["spur_m"]), RAILROAD, SHIPPERS[str(b["type"])], why])
	if not owner.is_empty():
		w.log_sim(owner, "Decided to put a rail spur into %s. Reason: %s." % [b["name"], why], true)
	w.chronicle_add("%s built its own rail spur. %s cars will now load right at the door." % [b["name"], RAILROAD], "business", true, [])
	return why


# ---------------------------------------------------------------- the depot

static func depot_lot_ok(w: LTWorld, l: Dictionary) -> String:
	if not has_line(w):
		return "There is no railroad here."
	if distance(w, l) > 60.0:
		return "A depot has to sit beside the tracks: this lot is %d meters away. Pick a lot within 60 meters of the line." % int(distance(w, l))
	if has_depot(w):
		return "The town already has a depot."
	return ""


## Daily: the passenger train brings visitors when the depot is open.
static func daily(w: LTWorld) -> void:
	if not passenger_service(w):
		return
	if not bool(w.city.get("rail_service_started", false)):
		w.city["rail_service_started"] = true
		w.chronicle_add("The state's regional rail service now stops at the %s depot twice a day. Visitors can come by train, and people can ride to jobs in the city." % w.city["name"], "city", true, [])
	# the railroad leases the depot from the city
	if LTCalendar.is_month_start(w.day):
		w.ledger.pay("outside", "city", LTMoney.dollars(1200.0), "depot_lease")
		LTCivic.income_note(w, "depot_lease", LTMoney.dollars(1200.0))
	var riders: int = int(6.0 * LTRegion.index(w) * w.rng.randf_range(0.6, 1.4))
	w.city["riders_today"] = riders
	var cafes: Array = w.open_businesses("cafe") + w.open_businesses("bar")
	for i in riders:
		if cafes.is_empty():
			break
		var cafe: Dictionary = cafes[w.rng.randi_range(0, cafes.size() - 1)]
		if float(cafe["stock"]) < 1.0 or not LTServices.has_room(w, cafe):
			continue
		var price: int = int(float(LTEconomy.MEAL_PRICE) * float(cafe["price_level"]))
		w.ledger.pay("outside", w.acct_b(cafe), price, "retail_sales")
		cafe["stock"] = float(cafe["stock"]) - 1.0
		cafe["customers_today"] = int(cafe["customers_today"]) + 1
		cafe["sales_today"] = int(cafe["sales_today"]) + price
		cafe["month_revenue"] = int(cafe["month_revenue"]) + price
		cafe["lifetime_revenue"] = int(cafe["lifetime_revenue"]) + price


## A commuter who can take the train pays a fare instead of gas.
static func commute_cost(w: LTWorld, gas: int) -> int:
	return int(float(gas) * 0.55) if passenger_service(w) else gas
