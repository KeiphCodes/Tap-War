extends SceneTree
## Runs several seeds with no mayor input and prints one line each, for calibrating the simulation.
## Run: godot --headless --script tests/seed_scan.gd


func _init() -> void:
	for sd in [20261120, 1, 2, 3, 4, 5]:
		var w: LTWorld = LTWorld.new()
		w.new_town(sd)
		w.run_days(365)
		var late_ever: int = 0
		var caught: int = 0
		for d in w.debts:
			var missed: bool = false
			for e in d["history"]:
				if str(e["text"]).begins_with("Missed"):
					missed = true
				if str(e["text"]).begins_with("Caught up"):
					caught += 1
			if missed:
				late_ever += 1
		var c: Dictionary = w.counters
		var s: Dictionary = w.snapshot()
		print("seed %d pop %d unemp %d%% happy %d | biz open %d closed %d | late_ever %d caught %d bk %d chargeoff %d repo %d evict %d forecl %d | deaths %d estates %d births %d | city %s" % [sd, s["population"], int(s["unemployment"] * 100), int(s["happiness"]), c["businesses_opened"], c["businesses_closed"], late_ever, caught, c["bankruptcies"], c["debts_charged_off"], c["repossessions"], c["evictions"], c["foreclosures"], c["deaths"], c["estates"], c["births"], LTMoney.fmt(s["city_cash"])])
	quit(0)
