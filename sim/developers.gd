class_name LTDevelopers
## Sims who make a living from land and houses, as real people do:
## - Land investors buy city lots and list them again for more, cutting the price
##   when nobody bites.
## - Spec builders (local construction companies) buy a lot, build a house on a
##   construction loan, and list it for sale.
## Every sale between owners pays the city its transfer tax, so the more property
## changes hands, the more the city collects.

const INVEST_MIN_CASH: int = 6000000      # $60,000 of savings before buying land to flip
const SPEC_MAX_LISTED: int = 2            # a builder keeps at most this many houses unsold


static func monthly(w: LTWorld) -> void:
	_reprice(w)
	_land_investors(w)
	_spec_builders(w)


static func _for_sale_city_lots(w: LTWorld, zones: Array) -> Array:
	var out: Array = []
	for l in w.lots:
		if str(l["use"]) == "empty" and str(l["owner_kind"]) == "city" and not bool(l.get("hold", false)) and not bool(l.get("removed", false)) and zones.has(str(l["zone"])) and LTGeography.connected(w, int(l["id"])):
			out.append(l)
	out.sort_custom(func(a, b): return LTGeography.asking_price(w, int(a["id"])) < LTGeography.asking_price(w, int(b["id"])))
	return out


## A Sim with savings, a head for money and an eye for a deal buys a city lot to
## sell on. They expect the town to grow; if it does not, they lose.
static func _land_investors(w: LTWorld) -> void:
	var lots: Array = _for_sale_city_lots(w, ["residential", "commercial", "mixed"])
	if lots.is_empty():
		return
	for c in w.citizens:
		if lots.is_empty():
			return
		if not w.is_present(c) or w.age_years(c) < 25 or w.cash(c) < INVEST_MIN_CASH:
			continue
		var t: Dictionary = c["traits"]
		var drive: float = (float(t["ambition"]) + float(t["greed"]) + float(c["skills"]["finance"])) / 3.0
		if drive < 55.0 or _held_by(w, int(c["id"])) >= 3:
			continue
		# they buy when the town is growing and land is cheap for what it is
		var growth: float = clampf(LTFounder.settler_pull(w) / 60.0, 0.2, 1.5) if bool(w.config.get("open_land", false)) else clampf(float(w.alive_count()) / 400.0, 0.3, 1.2)
		if w.rng.randf() >= (drive - 50.0) / 400.0 * growth:
			continue
		var l: Dictionary = lots.pop_front()
		var price: int = LTGeography.asking_price(w, int(l["id"]))
		if price > w.cash(c) / 2:
			continue
		LTCivic.property_sale(w, w.acct_p(c), "city", price, int(l["id"]))
		l["owner_kind"] = "sim"
		l["owner_id"] = int(c["id"])
		l["bought_for"] = price
		l["listed_day"] = w.day
		l["for_sale"] = int(float(price) * w.rng.randf_range(1.2, 1.45))
		w.counters["land_flips_bought"] = int(w.counters.get("land_flips_bought", 0)) + 1
		w.log_sim(c, "Bought %s from the city for %s and listed it for %s. Reason: the town is growing and land here should be worth more." % [LTGeography.lot_label(w, int(l["id"])), LTMoney.fmt(price), LTMoney.fmt(int(l["for_sale"]))], true)
		w.chronicle_add("%s bought %s as an investment." % [w.full_name(c), LTGeography.lot_label(w, int(l["id"]))], "housing", false, [c["id"]])


static func _held_by(w: LTWorld, cid: int) -> int:
	var n: int = 0
	for l in w.lots:
		if str(l["owner_kind"]) == "sim" and int(l["owner_id"]) == cid and str(l["use"]) == "empty":
			n += 1
	return n


## Listings that sit too long come down in price, about 4% a month after four
## months, never below what the seller paid less 15%.
static func _reprice(w: LTWorld) -> void:
	for l in w.lots:
		if not l.has("for_sale") or w.day - int(l.get("listed_day", w.day)) < 120:
			continue
		var floor_p: int = int(float(l.get("bought_for", l["value"])) * 0.85)
		var np: int = maxi(floor_p, int(float(l["for_sale"]) * 0.96))
		if np < int(l["for_sale"]):
			l["for_sale"] = np


## A local builder with a crew and some cash puts up a house to sell.
static func _spec_builders(w: LTWorld) -> void:
	for b in w.open_businesses("construction"):
		if bool(b.get("home_based", false)) and b["staff"].size() < 1:
			continue
		if _listed_by(w, int(b["id"])) >= SPEC_MAX_LISTED:
			continue
		var owner: Dictionary = w.cit(int(b["owners"][0]))
		if not w.is_present(owner):
			continue
		var demand: float = LTFounder.settler_pull(w) if bool(w.config.get("open_land", false)) else 25.0 + float(_renters(w)) * 0.5
		if w.rng.randf() >= clampf(demand / 400.0 * (float(owner["traits"]["ambition"]) / 60.0), 0.0, 0.25):
			continue
		var lots: Array = _for_sale_city_lots(w, ["residential", "mixed"])
		if lots.is_empty():
			return
		var l: Dictionary = lots[0]
		var land: int = LTGeography.asking_price(w, int(l["id"]))
		var spec: Dictionary = LTGeography.choose_home(w, 2, 2, LTMoney.dollars(85000.0), float(owner["traits"]["ambition"]), float(owner["traits"]["discipline"]), l)
		var cost: int = LTGeography.home_cost(spec)
		var acct: String = w.acct_b(b)
		# the bank lends about 80% of land and building; the builder puts up the rest
		var need: int = int(float(land + cost) * 0.2)
		if w.biz_cash(b) < need:
			continue
		var loan: int = int(float(land + cost) * 0.8)
		var d: Dictionary = LTFinance.new_debt(w, "b", int(b["id"]), "bank", -1, "construction_loan", loan, 0.085, 24, "house", int(l["id"]), [])
		LTFinance.fund_loan(w, d, acct, loan)
		LTCivic.property_sale(w, acct, "city", land, int(l["id"]))
		l["owner_kind"] = "business"
		l["owner_id"] = int(b["id"])
		var r: Dictionary = LTProjects.define_project(w, "house", int(l["id"]), int(float(cost) * 1.25), -1, false,
			{"kind": "spec", "id": int(b["id"]), "name": str(b["name"]), "acct": acct, "land": land}, cost, LTGeography.home_sqft(spec))
		if not bool(r.get("ok", false)):
			continue
		var pr: Dictionary = w.projects[int(r["project_id"])]
		pr["title"] = "%s: a house built to sell" % b["name"]
		pr["home"] = spec
		w.log_biz(b, "Bought %s for %s and started a house to sell (%s), on a %s construction loan." % [LTGeography.lot_label(w, int(l["id"])), LTMoney.fmt(land), LTGeography.home_text(spec), LTMoney.fmt(loan)])
		w.log_sim(owner, "Started building a house to sell on %s. Reason: families keep asking about houses in town." % LTGeography.lot_label(w, int(l["id"])), true)
		w.chronicle_add("%s is building a house to sell on %s." % [b["name"], LTGeography.lot_street(w, int(l["id"]))["name"]], "housing", false, [owner["id"]])


static func _listed_by(w: LTWorld, bid: int) -> int:
	var n: int = 0
	for l in w.lots:
		if str(l["owner_kind"]) == "business" and int(l["owner_id"]) == bid and (l.has("for_sale") or str(l["use"]) in ["site", "reserved"]):
			n += 1
	return n


static func _renters(w: LTWorld) -> int:
	var n: int = 0
	for h in w.households:
		if str(h["tenure"]) == "rent" and not h["members"].is_empty():
			n += 1
	return n


## A finished spec house goes on the market at cost plus the builder's margin.
static func list_spec_house(w: LTWorld, p: Dictionary, l: Dictionary) -> void:
	var cost: int = int(p["price"]) + int(p["change_orders"]) + int(p["developer"].get("land", 0))
	l["for_sale"] = int(float(cost) * 1.15)
	l["bought_for"] = cost
	l["listed_day"] = w.day
	l["owner_kind"] = "business"
	l["owner_id"] = int(p["developer"]["id"])
	var b: Dictionary = w.biz(int(p["developer"]["id"]))
	if not b.is_empty():
		w.log_biz(b, "Finished the house on %s and listed it for %s." % [LTGeography.lot_label(w, int(l["id"])), LTMoney.fmt(int(l["for_sale"]))])
	w.chronicle_add("A new house on %s is for sale for %s (%s)." % [LTGeography.lot_street(w, int(l["id"]))["name"], LTMoney.fmt(int(l["for_sale"])), LTGeography.home_text(l.get("home", {}))], "housing", true, [])
