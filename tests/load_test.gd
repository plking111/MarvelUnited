extends Node
## 初始指示物固定性测试：连续 setup 多次，验证每个地点的初始 civ/thug
## 在所有对局中恒定，且与 data/locations.json 的 initial 配置一致。

func _ready() -> void:
	Game.autopilot = true
	var per_loc := {}
	var all_ok := true
	for run in range(8):
		Game.setup("redskull", ["cap"], "none")
		if Game.state["phase"] != "setup":
			print("FAIL: setup 后 phase=%s（应为 setup）" % Game.state["phase"])
			all_ok = false
		for l in Game.state["locations"]:
			var key: String = l["id"]
			var pair := [l["civ"], l["thug"]]
			if per_loc.has(key):
				if per_loc[key] != pair:
					print("MISMATCH: %s 第%d次 (%d,%d) 与之前 %s 不同" % [key, run, pair[0], pair[1], str(per_loc[key])])
					all_ok = false
			else:
				per_loc[key] = pair
	for id in per_loc:
		var init: Array = DB.location(id)["initial"]
		var civ := 0
		var thug := 0
		for t in init:
			if t == "civ": civ += 1
			elif t == "thug": thug += 1
		var ok: bool = per_loc[id] == [civ, thug]
		if not ok:
			all_ok = false
		print("%s: 开局=(%d民,%d暴) json=(%d,%d) %s" % [DB.location_name(id), per_loc[id][0], per_loc[id][1], civ, thug, "OK" if ok else "MISMATCH"])
	# 开始游戏后应进入 hero_play
	await Game.start_game()
	if Game.state["phase"] != "hero_play":
		print("FAIL: start_game 后 phase=%s（应为 hero_play）" % Game.state["phase"])
		all_ok = false
	if all_ok:
		print("=== LOAD TEST ALL PASSED ===")
		get_tree().quit(0)
	else:
		print("=== LOAD TEST FAILED ===")
		get_tree().quit(1)
