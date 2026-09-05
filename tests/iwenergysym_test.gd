extends Node
## 复现：能量卡要求英勇时，用移动填充必须被拒绝（用户报告的 bug 验证）。

func _ready() -> void:
	Game.autopilot = false
	# 强制本局能量卡 = 0（第1张，要求 英勇×4）
	Game.pending_campaign = {"game": 1, "order": ["cull", "proxima", "ebony"], "stones_collected": [], "energy_unlocked": [], "removed_energy": 6}
	Game.setup("cull", ["cap", "ironman"], "none", "iw", ["无限战争"])
	Game.state["table_energy"] = 0
	Game.state["hidden_energy"] = -1
	Game.state["campaign"]["table_energy"] = 0
	Game.state["energy_tokens"] = {"0": []}
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	Game.state["action_symbols"] = ["move", "move"]
	Game.state["prev_hero_symbols"] = []
	Game.state["used_tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
	var need: Array = Game.energy_required_syms(0)
	print("能量卡0 要求:", need)
	# 用 move 填充（错误符号）
	var ok: bool = await Game.fill_energy_card(0, "move")
	print("用 move 填充结果:", ok, "（期望 false）")
	if ok:
		print("=== BUG REPRODUCED: 移动可解锁英勇能量卡 ===")
		get_tree().quit(1)
	# 验证带 sym 参数直接调用时也校验
	Game.state["action_symbols"] = ["move"]
	var ok2: bool = await Game.fill_energy_card(0, "move")
	print("再次用 move 填充:", ok2, "（期望 false）")
	if ok2:
		print("=== BUG REPRODUCED: 再次确认 ===")
		get_tree().quit(1)
	print("=== ENERGY SYM CHECK PASSED ===")
	get_tree().quit(0)
