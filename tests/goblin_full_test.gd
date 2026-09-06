extends Node
## 绿魔 setup + 完整对局验证：确认威胁牌堆机制、BAM抽威胁卡、放置、判负都不崩溃。

func _ready() -> void:
	print("=== GOBLIN FULL TEST START ===")
	Game.autopilot = true
	var err := await _play_full_game("goblin")
	print("### goblin -> %s" % err)
	if err.begins_with("结束") or err == "":
		print("=== GOBLIN FULL TEST OK ===")
		get_tree().quit(0)
	else:
		print("=== GOBLIN FULL TEST FAIL: %s ===" % err)
		get_tree().quit(1)

func _play_full_game(villain: String) -> String:
	Game.setup(villain, ["cap", "ironman", "hulk"], "none")
	var guard := 0
	while Game.state["phase"] != "game_over" and guard < 900:
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
	return "结束(turns=%d,win=%s,lose=%s)" % [Game.state["turn_count"], str(Game.state["victory"]), Game.state["lose_reason"]]
