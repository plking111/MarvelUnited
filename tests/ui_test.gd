extends Node
## UI 加载测试：加载 Board 场景，autopilot 跑若干帧，检查无脚本错误。

func _ready() -> void:
	Game.autopilot = true
	Game.pending_setup = {"villain": "redskull", "heroes": ["cap", "ironman", "hulk"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst := board.instantiate()
	add_child(inst)
	print("=== UI TEST: Board loaded ===")
	var frames := 0
	while frames < 600 and Game.state.get("phase", "") != "game_over":
		frames += 1
		await get_tree().process_frame
		if Game.state.is_empty():
			continue
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
					Game.trigger_effect()
				var syms: Array = Game.available_symbols()
				if syms.size() == 0:
					Game.end_actions()
				else:
					var progressed := false
					for s in syms:
						var before: int = Game.available_symbols().size()
						Game.use_symbol(s)
						await get_tree().process_frame
						if Game.available_symbols().size() < before:
							progressed = true
							break
					if not progressed:
						Game.end_actions()
			"hero_end":
				Game.end_turn()
			_:
				pass
	print("=== UI TEST: finished frames=%d phase=%s ===" % [frames, Game.state.get("phase", "")])
	get_tree().quit(0)
