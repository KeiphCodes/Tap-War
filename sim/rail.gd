class_name LTRail
extends RefCounted
## The railroad as it really works in South Dakota.
##
## - The track belongs to a private railroad. Nobody in town can start one. Some
##   maps have no railroad at all: the town has to talk a railroad into building
##   a branch line, and usually pay part of it.
## - Passenger trains run on the freight railroad's tracks, as Amtrak and state
##   supported trains do. A town gets a stop by asking the passenger service, which
##   decides on likely riders, and then building its own station.
## - A business that ships in bulk (grain, flour, lumber, stone, factory goods,
##   ore) can pay for its own spur track off the line, if the railroad agrees it
##   will ship enough. Rail costs about a third of trucking per ton.
## - The city can build a public loading track (a team track with a transload
##   dock) where any business can load a car, the real way: the town must be
##   incorporated, the mayor asks the railroad for an industry track agreement,
##   may apply for state rail aid, the town board approves the money, and the
##   job goes out to bid. Shippers pay the city a fee for every car they load.
## - Some maps have a light branch line. If too few cars move on it, the railroad
##   files to abandon it; the mayor can ask the state to buy the line, as South
##   Dakota did with hundreds of miles of track in the 1980s, and lease it to a
##   short line railroad. If nobody saves it, the rails come up.

const RAILROAD: String = "Dakota and Western Railroad"
const SHORT_LINE: String = "Prairie Short Line"
const REACH: float = 45.0           # a spur needs a lot right beside the right of way
const SPUR_PER_M: int = 98000        # $980 a meter of track, ties and ballast
const SWITCH_COST: int = 15000000    # $150,000 for the turnout and signals
const DEPOT_COST: int = 65000000     # team track, loading dock and scale
const CAR_VALUE: int = 2500000       # about $25,000 of goods in a loaded car
const CARS_FOR_AGREEMENT: float = 25.0
const CARS_TO_KEEP_BRANCH: int = 1000
const LOADING_FEE: float = 0.012     # the city's fee on what goes out through its track
const SHIPPERS: Dictionary = {
	"farm": "grain", "mill": "flour and feed", "sawmill": "lumber", "quarry": "crushed stone",
	"factory": "factory goods", "gold_mine": "ore concentrate",
}


## The railroad's record: who owns the line, how busy it is, and where the
## town's requests stand. Made from the map seed the first time it is needed.
static func r(w: LTWorld) -> Dictionary:
	if not w.city.has("rail"):
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = int(LTTerrain.t(w).get("seed", w.seed_value)) * 31 + 5
		var branch: bool = rng.randf() < 0.35
		w.city["rail"] = {
			"owner": RAILROAD, "branch": branch, "base_cars": rng.randi_range(500, 1100) if branch else rng.randi_range(4000, 12000),
			"cars_ytd": 0.0, "cars_last": 0, "removed": false, "agreement": "", "request": {}, "grant": {}, "grant_amt": 0,
			"abandon_day": -1, "state_request": {}, "history": [],
			"new_line": {}, "pax": {}, "pax_ok": false, "riders_year": 0,
		}
	return w.city["rail"]


static func _note(w: LTWorld, text: String, big: bool = true) -> void:
	var rr: Dictionary = r(w)
	rr["history"].append({"day": w.day, "text": text})
	if rr["history"].size() > 40:
		rr["history"].pop_front()
	w.chronicle_add(text, "city", big, [])


static func line_z(w: LTWorld) -> float:
	return LTTerrain.rail_z(w)


static func has_line(w: LTWorld) -> bool:
	return LTTerrain.has(w, "rail") and not bool(r(w).get("removed", false))


static func operator(w: LTWorld) -> String:
	return SHORT_LINE if str(r(w)["owner"]) != RAILROAD else RAILROAD


## Meters from a lot's nearest edge to the track.
static func distance(w: LTWorld, l: Dictionary) -> float:
	if LTTerrain.t(w).is_empty() or l.is_empty():
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


static func has_station(w: LTWorld) -> bool:
	return LTCivic.has_service(w, "station")


static func passenger_service(w: LTWorld) -> bool:
	return has_line(w) and has_station(w)


## Visitors a month the train brings on top of drivers (used by the outdoor trade).
static func visitor_draw(w: LTWorld) -> float:
	return 30.0 if passenger_service(w) else 0.0


## How much better a business does shipping by rail: its own spur saves the most,
## loading at the city's track a little less. 1.0 is all by truck.
static func ship_factor(w: LTWorld, b: Dictionary) -> float:
	if not SHIPPERS.has(str(b.get("type", ""))) or not has_line(w):
		return 1.0
	if bool(b.get("rail_spur", false)):
		return 1.07
	if has_depot(w) and distance(w, w.lot(int(b["lot"]))) < 1500.0:
		return 1.04
	return 1.0


## What a sale out of town brings home after freight. Rail cars are counted for
## the railroad, and a load through the city's track pays the city its fee.
static func export_rev(w: LTWorld, b: Dictionary, rev: int) -> int:
	var f: float = ship_factor(w, b)
	if f <= 1.0:
		return rev
	var rr: Dictionary = r(w)
	rr["cars_ytd"] = float(rr["cars_ytd"]) + float(rev) / float(CAR_VALUE)
	var out: int = int(float(rev) * f)
	if not bool(b.get("rail_spur", false)):
		var fee: int = int(float(rev) * LOADING_FEE)
		w.ledger.pay("outside", "city", fee, "transload_fees")
		LTCivic.income_note(w, "transload_fees", fee)
		out -= fee
	return out


## What inputs cost delivered.
static func input_cost(w: LTWorld, b: Dictionary, cost: int) -> int:
	return int(float(cost) * (2.0 - ship_factor(w, b)))


## Cars a year the town's shippers would put on the railroad, from what they sell.
static func expected_cars(w: LTWorld) -> float:
	var cars: float = 0.0
	for b in w.businesses:
		if str(b["status"]) == "open" and SHIPPERS.has(str(b["type"])):
			cars += float(b.get("month_revenue", 0)) * 12.0 / float(CAR_VALUE)
	return cars


# ---------------------------------------------------------------- spurs

static func monthly(w: LTWorld) -> void:
	if not has_line(w):
		return
	for b in w.businesses:
		if str(b["status"]) != "open" or bool(b.get("rail_spur", false)) or not SHIPPERS.has(str(b["type"])) or bool(b.get("home_based", false)):
			continue
		if int(b.get("loss_months", 0)) > 0 or w.day - int(b.get("opened_day", 0)) < 180 or w.day - int(b.get("spur_asked", -9999)) < 365:
			continue
		if distance(w, w.lot(int(b["lot"]))) > REACH:
			continue
		consider_spur(w, b)


## The owner's decision, with the railroad's say. Returns the reason.
static func consider_spur(w: LTWorld, b: Dictionary) -> String:
	b["spur_asked"] = w.day
	var l: Dictionary = w.lot(int(b["lot"]))
	var cost: int = spur_cost(w, l)
	var owner: Dictionary = w.cit(int(b["owners"][0]))
	var rev_month: float = float(b.get("month_revenue", 0))
	# the railroad wants enough cars a year to be worth a stop
	if rev_month * 12.0 / float(CAR_VALUE) < 25.0:
		var why0: String = "%s will not switch a spur for fewer than about 25 cars a year; %s would load about %d" % [operator(w), b["name"], int(rev_month * 12.0 / float(CAR_VALUE))]
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
	var down: int = mini(w.biz_cash(b) - LTMoney.dollars(20000.0), cost)
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
	w.log_biz(b, "Built a %d meter spur track off the %s line to ship %s by the carload. Reason: %s." % [int(b["spur_m"]), operator(w), SHIPPERS[str(b["type"])], why])
	if not owner.is_empty():
		w.log_sim(owner, "Decided to put a rail spur into %s. Reason: %s." % [b["name"], why], true)
	w.chronicle_add("%s built its own rail spur. Cars now load right at the door." % b["name"], "business", true, [])
	return why


# ---------------------------------------------------------------- the city's loading track, step by step

## Where the town stands on the way to a public loading track: the next step, in words.
static func next_step(w: LTWorld) -> String:
	var rr: Dictionary = r(w)
	if not LTTerrain.has(w, "rail"):
		return "There is no railroad on this map. The town would have to get a railroad to build a branch line."
	if not has_line(w):
		return "The railroad is gone."
	if has_depot(w):
		return "The public loading track is open."
	if not bool(w.city.get("incorporated", true)):
		return "Only a city can sign with the railroad. The town has to incorporate first."
	match str(rr["agreement"]):
		"":
			if not rr["request"].is_empty():
				return "Waiting for the railroad's answer, due %s." % LTCalendar.short(int(rr["request"]["due"]))
			return "Ask the railroad for an industry track agreement."
		"declined":
			return "The railroad said no. Ask again when the town ships more."
	return "Agreement signed. Put the loading track out to bid on a lot beside the tracks."


## Step 1: the mayor asks the railroad. It answers in about 45 days.
static func request_agreement(w: LTWorld) -> Dictionary:
	var rr: Dictionary = r(w)
	if not has_line(w):
		return {"ok": false, "message": "There is no railroad any more."}
	if not bool(w.city.get("incorporated", true)):
		return {"ok": false, "message": "Only an incorporated town can sign an agreement with the railroad."}
	if str(rr["agreement"]) == "signed" or has_depot(w):
		return {"ok": false, "message": "The town already has its agreement."}
	if not rr["request"].is_empty():
		return {"ok": false, "message": "The railroad has not answered yet."}
	if str(rr["agreement"]) == "declined" and w.day - int(rr.get("declined_day", 0)) < 365:
		return {"ok": false, "message": "The railroad turned the town down less than a year ago."}
	rr["request"] = {"day": w.day, "due": w.day + 45}
	rr["agreement"] = ""
	_note(w, "The city asked the %s for an industry track agreement to build a public loading track. The railroad's answer is due %s." % [operator(w), LTCalendar.short(w.day + 45)], false)
	return {"ok": true, "message": "Sent. The railroad answers in about 45 days. It will want to know how many cars the town's shippers would load (now about %d a year; it wants %d)." % [int(expected_cars(w)), int(CARS_FOR_AGREEMENT)]}


## Step 2 (optional): state rail aid pays up to half of the job.
static func apply_grant(w: LTWorld) -> Dictionary:
	var rr: Dictionary = r(w)
	if str(rr["agreement"]) != "signed":
		return {"ok": false, "message": "The state only funds a loading track the railroad has agreed to serve."}
	if not rr["grant"].is_empty() and str(rr["grant"].get("status", "")) == "pending":
		return {"ok": false, "message": "The application is already in."}
	if int(rr["grant_amt"]) > 0:
		return {"ok": false, "message": "The state already awarded the town %s." % LTMoney.fmt(int(rr["grant_amt"]))}
	if not rr["grant"].is_empty() and w.day - int(rr["grant"].get("day", 0)) < 365:
		return {"ok": false, "message": "The state turned the town down this year. Apply again next year."}
	rr["grant"] = {"day": w.day, "due": w.day + 90, "status": "pending"}
	_note(w, "The city applied to the state's freight rail aid program to help pay for a public loading track. A decision comes in about 90 days.", false)
	return {"ok": true, "message": "Applied. The state decides in about 90 days, and likes jobs and cars."}


static func daily(w: LTWorld) -> void:
	if LTTerrain.t(w).is_empty():
		return
	var rr: Dictionary = r(w)
	_new_line_day(w)
	_passenger_day(w)
	if not rr["request"].is_empty() and w.day >= int(rr["request"]["due"]):
		rr["request"] = {}
		var cars: float = expected_cars(w)
		if cars >= CARS_FOR_AGREEMENT:
			rr["agreement"] = "signed"
			_note(w, "The %s signed an industry track agreement with %s: it will switch cars at a public loading track. The town's shippers expect about %d cars a year." % [operator(w), w.city["name"], int(cars)])
		else:
			rr["agreement"] = "declined"
			rr["declined_day"] = w.day
			_note(w, "The %s turned down the city's request. Reason: it wants about %d cars a year to stop, and the town's shippers would load about %d." % [operator(w), int(CARS_FOR_AGREEMENT), int(cars)])
	var gr: Dictionary = rr["grant"]
	if not gr.is_empty() and str(gr.get("status", "")) == "pending" and w.day >= int(gr["due"]):
		var cars2: float = expected_cars(w)
		var chance: float = clampf(0.3 + cars2 / 200.0, 0.3, 0.85)
		if w.rng.randf() < chance:
			var amt: int = DEPOT_COST / 2
			rr["grant_amt"] = amt
			gr["status"] = "awarded"
			w.ledger.pay("outside", "city", amt, "state_rail_grant")
			LTCivic.income_note(w, "state_rail_grant", amt)
			_note(w, "The state awarded %s in freight rail aid for the town's public loading track." % LTMoney.fmt(amt))
		else:
			gr["status"] = "denied"
			_note(w, "The state passed on the town's rail aid application this year. Reason: other towns ship more.", false)
	if not rr["state_request"].is_empty() and w.day >= int(rr["state_request"]["due"]):
		_state_answer(w)
	if int(LTCalendar.day_of_year(w.day)) == 1 and w.day > 1:
		_year_end(w)
	if int(rr["abandon_day"]) >= 0 and w.day >= int(rr["abandon_day"]):
		_abandon(w)


# ---------------------------------------------------------------- a light branch line

static func _year_end(w: LTWorld) -> void:
	var rr: Dictionary = r(w)
	rr["cars_last"] = int(rr["base_cars"]) + int(rr["cars_ytd"])
	rr["cars_ytd"] = 0.0
	if not bool(rr["branch"]) or bool(rr["removed"]) or str(rr["owner"]) != RAILROAD or int(rr["abandon_day"]) >= 0:
		return
	if int(rr["cars_last"]) < CARS_TO_KEEP_BRANCH and w.rng.randf() < 0.25:
		rr["abandon_day"] = w.day + 365
		_note(w, "The %s filed with the federal Surface Transportation Board to abandon its branch line through %s. Only %d cars moved on it last year. Unless someone buys the line, the rails come up %s." % [RAILROAD, w.city["name"], int(rr["cars_last"]), LTCalendar.short(w.day + 365)])


## The mayor asks the state rail authority to buy the line and lease it out.
static func ask_state_to_buy(w: LTWorld) -> Dictionary:
	var rr: Dictionary = r(w)
	if int(rr["abandon_day"]) < 0:
		return {"ok": false, "message": "The line is not up for abandonment."}
	if not rr["state_request"].is_empty():
		return {"ok": false, "message": "The state is already looking at it."}
	rr["state_request"] = {"day": w.day, "due": w.day + 90}
	_note(w, "The city asked the state to buy the branch line before the rails come up. The state rail board decides in about 90 days.", false)
	return {"ok": true, "message": "Asked. The state weighs how many cars the line carries and the jobs on it."}


static func _state_answer(w: LTWorld) -> void:
	var rr: Dictionary = r(w)
	rr["state_request"] = {}
	var cars: int = int(rr["base_cars"]) + int(expected_cars(w))
	var shippers: int = 0
	for b in w.businesses:
		if str(b["status"]) == "open" and SHIPPERS.has(str(b["type"])):
			shippers += 1
	if cars >= 450 and (shippers > 0 or w.residents() >= 150) and w.rng.randf() < 0.7:
		rr["owner"] = "State of South Dakota"
		rr["abandon_day"] = -1
		_note(w, "The state bought the branch line and leased it to the %s. The trains keep running through %s." % [SHORT_LINE, w.city["name"]])
	else:
		_note(w, "The state rail board will not buy the line. Reason: about %d cars a year is too little traffic to keep it." % cars)


static func _abandon(w: LTWorld) -> void:
	var rr: Dictionary = r(w)
	rr["abandon_day"] = -1
	rr["removed"] = true
	for b in w.businesses:
		if bool(b.get("rail_spur", false)):
			b["rail_spur"] = false
			w.log_biz(b, "The railroad pulled up its track. The spur is useless now; everything ships by truck.")
	_note(w, "The rails came up on the old branch line through %s. Everything ships by truck now, and the old grade is left as a trail." % w.city["name"])


# ---------------------------------------------------------------- the lot

static func depot_lot_ok(w: LTWorld, l: Dictionary) -> String:
	if not has_line(w):
		return "There is no railroad here."
	if str(r(w)["agreement"]) != "signed":
		return "The railroad has to agree to serve it first (Mayor tab, Railroad)."
	if distance(w, l) > 60.0:
		return "A loading track has to sit beside the main line: this lot is %d meters away. Pick a lot within 60 meters of the track." % int(distance(w, l))
	if has_depot(w):
		return "The town already has a public loading track."
	return ""



# ---------------------------------------------------------------- a map with no railroad

const NEW_LINE_COST: int = 350000000     # about a mile of new branch line, $3.5 million
const CARS_RAILROAD_PAYS: float = 600.0  # enough traffic that the railroad builds on its own dime
const CARS_SHARED: float = 150.0         # enough that it builds if the town pays part


## The mayor asks a railroad to build a branch line to town. It answers in about four months.
static func request_new_line(w: LTWorld) -> Dictionary:
	var rr: Dictionary = r(w)
	if LTTerrain.has(w, "rail"):
		return {"ok": false, "message": "The town already has a railroad."}
	if not bool(w.city.get("incorporated", true)):
		return {"ok": false, "message": "Only an incorporated town can deal with a railroad."}
	var nl: Dictionary = rr["new_line"]
	if not nl.is_empty() and ["asked", "share", "building"].has(str(nl.get("status", ""))):
		return {"ok": false, "message": "That is already under way."}
	if not nl.is_empty() and str(nl.get("status", "")) == "declined" and w.day - int(nl.get("day", 0)) < 365:
		return {"ok": false, "message": "The railroad said no less than a year ago."}
	rr["new_line"] = {"status": "asked", "day": w.day, "due": w.day + 120}
	_note(w, "The city asked the %s to build a branch line to %s. The railroad will study the traffic and answer by %s." % [RAILROAD, w.city["name"], LTCalendar.short(w.day + 120)], false)
	return {"ok": true, "message": "Asked. The railroad weighs how many cars a year the town would ship (now about %d). It builds on its own at about %d, and asks the town to pay part at about %d." % [int(expected_cars(w)), int(CARS_RAILROAD_PAYS), int(CARS_SHARED)]}


## The city agrees to pay its share; the town board votes on it first.
static func pay_share(w: LTWorld) -> Dictionary:
	var rr: Dictionary = r(w)
	var nl: Dictionary = rr["new_line"]
	if str(nl.get("status", "")) != "share":
		return {"ok": false, "message": "The railroad has not asked the town to pay a share."}
	var share: int = int(nl["share"])
	if LTGov.board_seated(w) and not LTGov.by_decree(w):
		var v: Array = LTGov.vote(w, "paying %s toward a new branch line" % LTMoney.fmt(share), "property_tax", true)
		if not bool(v[0]):
			return {"ok": false, "message": str(v[3])}
	if w.ledger.bal("city") < share:
		return {"ok": false, "message": "The city has %s and its share is %s. Borrow or sell bonds first." % [LTMoney.fmt(w.ledger.bal("city")), LTMoney.fmt(share)]}
	w.ledger.pay("city", "outside", share, "rail_line_share")
	_start_building(w, "the city paid %s of the cost" % LTMoney.fmt(share))
	return {"ok": true, "message": "Paid. The railroad starts building; trains in about a year."}


static func _start_building(w: LTWorld, why: String) -> void:
	var rr: Dictionary = r(w)
	var z: float = _free_corridor(w)
	rr["new_line"] = {"status": "building", "day": w.day, "done": w.day + 365, "z": z}
	_note(w, "The %s is building a branch line to %s. Reason: %s. Trains should run by %s." % [RAILROAD, w.city["name"], why, LTCalendar.short(w.day + 365)])


## A straight corridor across the map with no lots on it, near the planned one.
static func _free_corridor(w: LTWorld) -> float:
	var base: float = LTTerrain.rail_z(w)
	for k in 60:
		for sgn in [1.0, -1.0]:
			var z: float = base + sgn * float(k) * 10.0
			if z < 60.0 or z > LTTerrain.MAP_H - 60.0 or absf(z - LTTerrain.road_z()) < 60.0:
				continue
			var clear: bool = true
			for l in w.lots:
				if not bool(l.get("removed", false)) and float(l["z0"]) < z + 15.0 and float(l["z1"]) > z - 15.0:
					clear = false
					break
			if clear:
				return z
	return base


static func _new_line_day(w: LTWorld) -> void:
	var rr: Dictionary = r(w)
	var nl: Dictionary = rr["new_line"]
	if nl.is_empty():
		return
	match str(nl.get("status", "")):
		"asked":
			if w.day < int(nl["due"]):
				return
			var cars: float = expected_cars(w)
			if cars >= CARS_RAILROAD_PAYS:
				_start_building(w, "the town's shippers would load about %d cars a year" % int(cars))
			elif cars >= CARS_SHARED:
				var share: int = int(float(NEW_LINE_COST) * 0.4)
				rr["new_line"] = {"status": "share", "day": w.day, "share": share}
				_note(w, "The %s will build a branch line to %s if the town pays %s, about 40%% of the cost. Reason: about %d cars a year is not quite enough to pay for it alone." % [RAILROAD, w.city["name"], LTMoney.fmt(share), int(cars)])
			else:
				rr["new_line"] = {"status": "declined", "day": w.day}
				_note(w, "The %s will not build a branch line to %s. Reason: the town would ship about %d cars a year; it would need about %d before it could share the cost." % [RAILROAD, w.city["name"], int(cars), int(CARS_SHARED)])
		"building":
			if w.day < int(nl["done"]):
				return
			LTTerrain.t(w)["rail_z"] = float(nl["z"])
			LTTerrain.t(w)["rail_present"] = true
			rr["new_line"] = {"status": "open", "day": w.day}
			rr["branch"] = true
			rr["base_cars"] = 300
			rr["owner"] = RAILROAD
			_note(w, "The first train ran on the new branch line to %s." % w.city["name"])


# ---------------------------------------------------------------- passenger trains

const PAX_SERVICE: String = "Prairie Rail passenger service"
const STATION_COST: int = 150000000      # platform, shelter, ramps and parking, $1.5 million
const RIDERS_NEEDED: int = 3000


## Riders a year the passenger service would expect here: townspeople plus the
## visitors the lake, the woods, the mountain, a hotel and a campground draw.
static func expected_riders(w: LTWorld) -> int:
	var n: float = float(w.residents()) * 4.0
	n += 1200.0 * float(LTTerrain.t(w).get("lakes", []).size())
	n += 1500.0 if LTTerrain.has(w, "mountain") else 0.0
	n += 900.0 if LTTerrain.has(w, "forest") else 0.0
	n += 600.0 * float(w.open_businesses("hotel").size() + w.open_businesses("campground").size() + w.open_businesses("guide_service").size())
	return int(n)


static func request_stop(w: LTWorld) -> Dictionary:
	var rr: Dictionary = r(w)
	if not has_line(w):
		return {"ok": false, "message": "There is no railroad for a passenger train to run on."}
	if not bool(w.city.get("incorporated", true)):
		return {"ok": false, "message": "Only an incorporated town can ask for a stop."}
	if bool(rr["pax_ok"]):
		return {"ok": false, "message": "The passenger service already agreed to stop here."}
	var px: Dictionary = rr["pax"]
	if str(px.get("status", "")) == "asked":
		return {"ok": false, "message": "The passenger service has not answered yet."}
	if str(px.get("status", "")) == "declined" and w.day - int(px.get("day", 0)) < 365:
		return {"ok": false, "message": "The passenger service said no less than a year ago."}
	rr["pax"] = {"status": "asked", "day": w.day, "due": w.day + 90}
	_note(w, "The city asked the %s to stop its trains at %s. The answer is due %s." % [PAX_SERVICE, w.city["name"], LTCalendar.short(w.day + 90)], false)
	return {"ok": true, "message": "Asked. The service expects about %d riders a year here and wants about %d." % [expected_riders(w), RIDERS_NEEDED]}


static func station_lot_ok(w: LTWorld, l: Dictionary) -> String:
	if not has_line(w):
		return "There is no railroad here."
	if not bool(r(w)["pax_ok"]):
		return "The passenger service has to agree to stop here first (Mayor tab, Railroad)."
	if distance(w, l) > 60.0:
		return "A station has to sit beside the track: this lot is %d meters away. Pick a lot within 60 meters of the track." % int(distance(w, l))
	if has_station(w):
		return "The town already has a station."
	return ""


static func _passenger_day(w: LTWorld) -> void:
	var rr: Dictionary = r(w)
	var px: Dictionary = rr["pax"]
	if str(px.get("status", "")) == "asked" and w.day >= int(px["due"]):
		var riders: int = expected_riders(w)
		if riders >= RIDERS_NEEDED:
			rr["pax_ok"] = true
			rr["pax"] = {"status": "agreed", "day": w.day}
			_note(w, "The %s agreed to stop at %s twice a day once the town builds a station. It expects about %d riders a year." % [PAX_SERVICE, w.city["name"], riders])
		else:
			rr["pax"] = {"status": "declined", "day": w.day}
			_note(w, "The %s will not stop at %s yet. Reason: about %d riders a year expected, and a stop needs about %d. More people, a hotel, or things to see bring riders." % [PAX_SERVICE, w.city["name"], riders, RIDERS_NEEDED])
	if not passenger_service(w):
		return
	if not bool(w.city.get("rail_service_started", false)):
		w.city["rail_service_started"] = true
		_note(w, "The first %s train stopped at the new %s station. Visitors can come by train, and people can ride to jobs in the city." % [PAX_SERVICE, w.city["name"]])
	if LTCalendar.is_month_start(w.day):
		LTCivic._spend(w, "outside", LTMoney.dollars(900.0), "station_upkeep")
	# visitors off the train eat, stay and shop
	var riders_today: int = int(float(expected_riders(w)) / 365.0 * w.rng.randf_range(0.6, 1.4))
	w.city["riders_today"] = riders_today
	rr["riders_year"] = int(rr.get("riders_year", 0)) + riders_today
	var eat: Array = w.open_businesses("cafe") + w.open_businesses("bar")
	var visitors: int = riders_today / 2
	for i in visitors:
		if eat.is_empty():
			break
		var cafe: Dictionary = eat[w.rng.randi_range(0, eat.size() - 1)]
		if float(cafe["stock"]) < 1.0 or not LTServices.has_room(w, cafe):
			continue
		var price: int = int(float(LTEconomy.MEAL_PRICE) * float(cafe["price_level"]))
		w.ledger.pay("outside", w.acct_b(cafe), price, "retail_sales")
		cafe["stock"] = float(cafe["stock"]) - 1.0
		cafe["customers_today"] = int(cafe["customers_today"]) + 1
		cafe["sales_today"] = int(cafe["sales_today"]) + price
		cafe["month_revenue"] = int(cafe["month_revenue"]) + price
		cafe["lifetime_revenue"] = int(cafe["lifetime_revenue"]) + price
	var hotels: Array = w.open_businesses("hotel")
	if not hotels.is_empty() and visitors > 0:
		var h: Dictionary = hotels[w.rng.randi_range(0, hotels.size() - 1)]
		var nights: int = maxi(1, visitors / 4)
		var room: int = LTMoney.dollars(95.0) * nights
		w.ledger.pay("outside", w.acct_b(h), room, "retail_sales")
		h["month_revenue"] = int(h["month_revenue"]) + room
		h["lifetime_revenue"] = int(h["lifetime_revenue"]) + room
		h["sales_today"] = int(h["sales_today"]) + room


## A commuter who can take the train pays a fare instead of gas.
static func commute_cost(w: LTWorld, gas: int) -> int:
	return int(float(gas) * 0.6) if passenger_service(w) else gas
