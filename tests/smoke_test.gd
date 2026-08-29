extends Node
## 冒烟测试：无头模式下自动运行一局游戏（autopilot 自动应答），验证规则引擎不崩溃。

func _ready() -> void:
	print("=== SMOKE TEST START ===")
	Game.autopilot = true
	var all_ok := true
	for villain in ["redskull", "ultron", "taskmaster"]:
		var err := await _play_full_game(villain)
		print("### villain=%s -> %s" % [villain, err])
		if not err.begins_with("结束"):
			all_ok = false
	# 胜利路径测试
	var win_err := await _test_win_path()
	print("### win_path -> %s" % win_err)
	if win_err != "":
		all_ok = false
	if all_ok:
		print("=== SMOKE TEST ALL PASSED ===")
		get_tree().quit(0)
	else:
		get_tree().quit(1)

func _play_full_game(villain: String) -> String:
	Game.setup(villain, ["cap", "ironman", "hulk"], "none")
	var guard := 0
	while Game.state["phase"] != "game_over" and guard < 500:
		guard += 1
		match Game.state["phase"]:
			"setup":
				await Game.start_game()
			"hero_play":
				var hid: String = Game.current_hero_id()
				var hand: Array = Game.state["heroes"][hid]["hand"]
				if hand.size() == 0:
					Game.state["phase"] = "hero_end"
				else:
					Game.play_card(0)
			"hero_actions":
				if Game.state.get("effect_available", false) and not Game.state.get("effect_used", false):
					await Game.trigger_effect()
				var syms: Array = Game.available_symbols()
				if syms.size() == 0:
					Game.end_actions()
				else:
					var progressed := false
					for s in syms:
						var before: int = Game.available_symbols().size()
						await Game.use_symbol(s)
						if Game.available_symbols().size() < before:
							progressed = true
							break
					if not progressed:
						Game.end_actions()
			"hero_end":
				await Game.end_turn()
			_:
				pass
		await get_tree().process_frame
	if Game.state["phase"] != "game_over":
		return "未结束(phase=%s guard=%d)" % [Game.state["phase"], guard]
	return "结束(turns=%d,win=%s,missions=%d,lose=%s)" % [
		Game.state["turn_count"], str(Game.state["victory"]),
		Game.state["missions_completed"], Game.state["lose_reason"]]

## 胜利路径：作弊制造"已解锁攻击+反派1血+英雄与反派同地"场景，攻击获胜
func _test_win_path() -> String:
	Game.setup("redskull", ["cap"], "none")
	# 开始游戏（进入第一个反派回合），然后等待 hero_play 阶段
	await Game.start_game()
	var guard := 0
	while Game.state["phase"] != "hero_play" and guard < 100:
		guard += 1
		await get_tree().process_frame
	if Game.state["phase"] != "hero_play":
		return "未进入英雄阶段"
	var hid := "cap"
	# 作弊
	Game.state["missions_completed"] = 2
	Game.state["villain_hp"] = 1
	var vpos: int = Game.state["villain_pos"]
	Game.state["heroes"][hid]["location"] = vpos
	Game.state["locations"][vpos]["thug"] = 0
	Game.state["locations"][vpos]["threat"] = null
	# 注入攻击卡到手牌（cap #2 是 [攻击,攻击]）
	var attack_card := -1
	for i in range(DB.hero_cards(hid).size()):
		if DB.hero_cards(hid)[i]["symbols"].has("attack"):
			attack_card = i
			break
	if attack_card == -1:
		return "英雄没有攻击卡"
	Game.state["heroes"][hid]["hand"] = [attack_card]
	Game.play_card(0)
	# 使用攻击直到胜利
	var guard2 := 0
	while Game.state["phase"] != "game_over" and guard2 < 50:
		guard2 += 1
		if Game.state["phase"] == "hero_actions":
			var syms: Array = Game.available_symbols()
			if syms.has("attack"):
				await Game.use_symbol("attack")
			elif syms.size() == 0:
				Game.end_actions()
			else:
				await Game.use_symbol(syms[0])
		elif Game.state["phase"] == "hero_end":
			await Game.end_turn()
		elif Game.state["phase"] == "villain":
			pass
		await get_tree().process_frame
	if Game.state["phase"] == "game_over" and Game.state["victory"]:
		return ""
	return "胜利路径未触发胜利"
