extends Node
## 洛基完整局 autopilot：跑一整局直到 game_over，验证规则引擎不崩
func _ready() -> void:
	print("=== LOKI FULL GAME START ===")
	Game.autopilot = true
	var err: String = await _play_full_game("loki")
	print("### villain=loki -> %s" % err)
	if err.begins_with("结束"):
		print("=== LOKI FULL GAME PASSED ===")
		get_tree().quit(0)
	else:
		print("=== LOKI FULL GAME FAILED: %s ===" % err)
		get_tree().quit(1)

func _play_full_game(villain: String) -> String:
	Game.setup(villain, ["cap", "ironman", "hulk"], "none")
	var guard := 0
	while Game.state["phase"] != "game_over" and guard < 600:
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
