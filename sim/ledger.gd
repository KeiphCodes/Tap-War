class_name LTLedger
extends RefCounted
## Double entry in spirit. Every cent lives in exactly one account. Money only moves
## by transfer, so the sum of all accounts is always zero. The "outside" account is
## the world beyond town: imports, outside wages, outside banks. It is the only
## account that may go negative, and its balance is the net flow across the town line.

var balances: Dictionary = {}
var flows: Dictionary = {}
var allow_negative: Dictionary = {"outside": true}
var transfer_count: int = 0
var errors: Array = []
## Per category in and out totals for accounts we report on, reset by the reader.
var tracked: Dictionary = {"city": {"in": {}, "out": {}}}


func open(acct: String) -> void:
	if not balances.has(acct):
		balances[acct] = 0


func bal(acct: String) -> int:
	return int(balances.get(acct, 0))


## Moves up to cents from a to b. If a cannot go negative, moves only what a has.
## Returns the amount actually moved.
func pay(from_acct: String, to_acct: String, cents: int, category: String) -> int:
	if cents <= 0:
		return 0
	open(from_acct)
	open(to_acct)
	var amount: int = cents
	if not allow_negative.has(from_acct):
		amount = mini(amount, int(balances[from_acct]))
	if amount <= 0:
		return 0
	balances[from_acct] = int(balances[from_acct]) - amount
	balances[to_acct] = int(balances[to_acct]) + amount
	flows[category] = int(flows.get(category, 0)) + amount
	transfer_count += 1
	if tracked.has(to_acct):
		var tin: Dictionary = tracked[to_acct]["in"]
		tin[category] = int(tin.get(category, 0)) + amount
	if tracked.has(from_acct):
		var tout: Dictionary = tracked[from_acct]["out"]
		tout[category] = int(tout.get(category, 0)) + amount
	return amount


## Moves all or nothing. Returns true if it moved.
func pay_full(from_acct: String, to_acct: String, cents: int, category: String) -> bool:
	if cents <= 0:
		return true
	if not allow_negative.has(from_acct) and bal(from_acct) < cents:
		return false
	pay(from_acct, to_acct, cents, category)
	return true


func audit() -> Dictionary:
	var total: int = 0
	var negatives: Array = []
	for k in balances:
		var v: int = int(balances[k])
		total += v
		if v < 0 and not allow_negative.has(k):
			negatives.append("%s %d" % [k, v])
	return {"ok": total == 0 and negatives.is_empty(), "sum": total, "negatives": negatives, "accounts": balances.size(), "transfers": transfer_count}


func to_dict() -> Dictionary:
	return {"balances": balances, "flows": flows, "transfer_count": transfer_count, "tracked": tracked}


func from_dict(d: Dictionary) -> void:
	balances = d.get("balances", {})
	flows = d.get("flows", {})
	transfer_count = int(d.get("transfer_count", 0))
	tracked = d.get("tracked", {"city": {"in": {}, "out": {}}})
