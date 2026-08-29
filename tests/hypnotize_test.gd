extends Node
## 验证奥创「催眠」：3 个目标地点（所在地+相邻）中，有英雄的地点英雄+1危机；无英雄的地点各放1暴徒。

func _ready() -> void:
	Game.pending_setup = {"villain": "ultron", "heroes": ["cap", "ironman", "hulk"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	var st: Dictionary = Game.state
	var n := 6  # 地点数
	# 场景：反派在 0 号地点。目标 = [5, 0, 1]（0 相邻 5 和 1）
	st["villain_pos"] = 0
	# 英雄布局：cap 在 0（有英雄），ironman 在 5（有英雄），hulk 在 2（不在目标内）
	st["heroes"]["cap"]["location"] = 0
	st["heroes"]["ironman"]["location"] = 5
	st["heroes"]["hulk"]["location"] = 2
	# 记录各地点暴徒数
	var thug_before: Array = []
	for l in st["locations"]:
		thug_before.append(l["thug"])
	Game.autopilot = true
	await Game._resolve_villain_effect({"type": "hypnotize", "name": "催眠", "text": ""})
	# 断言：cap(0)、ironman(5) 各 +1 危机；hulk(2) 不+（不在目标）
	var ok1: bool = st["heroes"]["cap"]["crisis"] == 1 and st["heroes"]["ironman"]["crisis"] == 1 and st["heroes"]["hulk"]["crisis"] == 0
	# 断言：目标中无英雄的地点（1 号）放 1 暴徒；有英雄的 0、5 不放
	var ok2: bool = st["locations"][1]["thug"] == thug_before[1] + 1
	var ok3: bool = st["locations"][0]["thug"] == thug_before[0] and st["locations"][5]["thug"] == thug_before[5]
	# 断言：非目标地点（2、3、4）不放暴徒
	var ok4: bool = st["locations"][2]["thug"] == thug_before[2] and st["locations"][3]["thug"] == thug_before[3] and st["locations"][4]["thug"] == thug_before[4]
	print("危机: cap=", st["heroes"]["cap"]["crisis"], " iron=", st["heroes"]["ironman"]["crisis"], " hulk=", st["heroes"]["hulk"]["crisis"])
	print("暴徒: loc0=", st["locations"][0]["thug"], " loc1=", st["locations"][1]["thug"], " loc5=", st["locations"][5]["thug"])
	# 场景2：目标全部有英雄 → 不放任何暴徒
	st["heroes"]["hulk"]["location"] = 1
	Game.autopilot = true
	await Game._resolve_villain_effect({"type": "hypnotize", "name": "催眠", "text": ""})
	var ok5: bool = st["locations"][1]["thug"] == thug_before[1] + 1  # 场景2中1号有英雄，不放
	print("场景2 loc1暴徒=", st["locations"][1]["thug"], " (应仍为", thug_before[1] + 1, ")")
	if ok1 and ok2 and ok3 and ok4 and ok5:
		print("=== HYPNOTIZE TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== HYPNOTIZE TEST FAILED ===", [ok1, ok2, ok3, ok4, ok5])
		get_tree().quit(1)
