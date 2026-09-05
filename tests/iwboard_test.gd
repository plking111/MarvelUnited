extends Node
## 战役模式 Board 加载测试：iw 模式 setup + Board 场景加载 + 若干帧。

func _ready() -> void:
	Game.autopilot = true
	Game.pending_campaign = {"game": 1, "order": ["cull", "proxima", "ebony"], "stones_collected": [], "energy_unlocked": []}
	Game.pending_setup = {"villain": "cull", "heroes": ["cap", "ironman", "hulk"], "challenge": "none", "mode": "iw", "expansions": ["无限战争"]}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst := board.instantiate()
	add_child(inst)
	print("=== IW BOARD TEST: loaded ===")
	var frames := 0
	while frames < 200 and Game.state.get("phase", "") != "game_over":
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
					Game.use_symbol(syms[0])
			"hero_end":
				Game.end_turn()
	print("=== IW BOARD TEST: finished frames=%d phase=%s ===" % [frames, Game.state.get("phase", "")])
	get_tree().quit(0)
