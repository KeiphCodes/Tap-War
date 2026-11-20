class_name LTMoney
extends RefCounted
## Money is stored as whole cents (int) everywhere so the ledger never drifts.


static func dollars(d: float) -> int:
	return int(round(d * 100.0))


static func fmt(cents: int) -> String:
	var neg: bool = cents < 0
	var whole: int = absi(cents) / 100
	var s: String = str(whole)
	var out: String = ""
	var count: int = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-$" if neg else "$") + out


static func fmt_exact(cents: int) -> String:
	var neg: bool = cents < 0
	var c: int = absi(cents)
	return ("-$" if neg else "$") + str(c / 100) + "." + ("%02d" % (c % 100))
