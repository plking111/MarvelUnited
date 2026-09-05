extends Node
## 瓦坎达+阿斯加德地点初始指示物回归：slots 与 initial 的 civ/thug 数量必须与地点卡一致
var _bad: Array = []

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("OK: " + msg)
	else:
		_bad.append(msg)
		print("FAIL: " + msg)

func _ready() -> void:
	# 期望：地点id -> [slots, civ数, thug数]
	var expect := {
		"warrior_falls": [5, 1, 2],
		"great_mound": [4, 1, 1],
		"golden_city": [4, 1, 1],
		"jabari_village": [4, 1, 1],
		"shuris_lab": [4, 1, 1],
		"royal_palace": [5, 2, 0],
		"throne_room": [5, 1, 1],
		"asgardian_palace": [4, 1, 1],
		"odins_vault": [2, 0, 0],
		"bifrost_bridge": [3, 0, 1],
		"heimdall_observatory": [4, 1, 0],
		"valhalla": [4, 1, 1],
	}
	for id in expect:
		var loc: Dictionary = DB.location(id)
		var slots: int = int(loc.get("slots", -1))
		var civ := 0
		var thug := 0
		for t in loc.get("initial", []):
			if t == "civ": civ += 1
			elif t == "thug": thug += 1
		var e: Array = expect[id]
		_check(slots == e[0], "%s slots=%d (期望 %d)" % [id, slots, e[0]])
		_check(civ == e[1], "%s civ=%d (期望 %d)" % [id, civ, e[1]])
		_check(thug == e[2], "%s thug=%d (期望 %d)" % [id, thug, e[2]])
		_check(slots >= civ + thug, "%s slots(%d) 应>= civ+thug(%d)" % [id, slots, civ + thug])

	print("---- RESULT ----")
	if _bad.is_empty():
		print("=== LOCATION INITIALS PASSED ===")
		get_tree().quit(0)
	else:
		print("=== FAILED: ", _bad, " ===")
		get_tree().quit(1)
