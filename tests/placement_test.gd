extends Node
## 验证：反派 place 数据已修正为 先暴徒后平民
func _ready() -> void:
	Game.autopilot = true
	Game.setup("proxima", ["cap"], "none")
	var bad: Array = []
	# 读 proxima action6 的 place
	var place: Array = DB.villain("proxima")["actions"][6]["place"]
	print("proxima a6 place=", place)
	# 每个 slot 内：thug 应全在 civ 前
	for si in range(place.size()):
		var slot: Array = place[si]
		# 检查：所有 thug 的下标都应 < 所有 civ 的下标
		var last_thug := -1
		var first_civ := 999
		for k in range(slot.size()):
			if slot[k] == "thug": last_thug = k
			elif slot[k] == "civ": first_civ = mini(first_civ, k)
		if last_thug > first_civ:
			bad.append("slot%d 顺序错: %s" % [si, str(slot)])
	print("---- RESULT ----")
	if bad.is_empty():
		print("=== PLACE DATA ORDER PASSED ===")
		get_tree().quit(0)
	else:
		print("=== FAILED: ", bad, " ===")
		get_tree().quit(1)
