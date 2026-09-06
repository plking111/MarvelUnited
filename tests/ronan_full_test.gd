extends Node
## 罗南完整对局测试：autopilot 自动打一局，验证特殊移动/BAM/效果/放置/威胁卡/KO 指示物不崩溃。

func _ready() -> void:
	print("=== RONAN FULL TEST START ===")
	Game.autopilot = true
	var err := await _play_full_game("ronan")
	print("### ronan -> %s" % err)
	if err.begins_with("结束") or err == "":
		print("=== RONAN FULL TEST OK ===")
		get_tree().quit(0)
	else:
		print("=== RONAN FULL TEST FAIL: %s ===" % err)
		get_tree().quit(1)

func _play_full_game(villain: String) -> String:
	Game.setup(villain, ["cap", "ironman", "hulk"], "none")
	var guard := 0
	while Game.state["phase"] != "game_over" and guard < 800:
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
	return "结束(turns=%d,win=%s,missions=%d,lose=%s,ko=%d)" % [
		Game.state["turn_count"], str(Game.state["victory"]),
		Game.state["missions_completed"], Game.state["lose_reason"], Game.state.get("ko_tokens", 0)]
