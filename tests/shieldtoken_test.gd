extends Node
## 神盾局单人模式共享行动指示物验证：
## 1) 手牌区显示共享指示物数量；
## 2) 效果"给英雄指示物"→ 给玩家共享池（任意英雄都能用）；
## 3) 消耗共享指示物正常扣减。

func _ready() -> void:
	Game.setup("redskull", ["cap", "ironman", "hulk"], "none", "shield")
	var bad: Array = []
	# 1) 共享池存在且初始为 0
	var stk: Dictionary = Game.state.get("shield_tokens", {})
	print("shield_tokens=", str(stk))
	if stk.size() != 4:
		bad.append("缺少共享指示物池")
	# 2) 效果给移动指示物 → 共享池 +2（钢铁侠卡10效果 give_move_x2）
	var hid := "cap"
	Game.state["heroes"][hid]["hand"] = [0, 1, 2]
	Game.state["phase"] = "hero_actions"
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	Game.state["action_symbols"] = ["move"]  # 留符号阻止自动结束
	Game.state["played_effect"] = DB.hero_cards("ironman")[9]["effect"]  # 基础=攻击 → give_move_x2
	await Game.trigger_effect()
	print("效果后 shield_tokens=", str(Game.state["shield_tokens"]))
	if int(Game.state["shield_tokens"]["move"]) != 2:
		bad.append("效果应给玩家共享池 +2 移动指示物")
	if not Game.available_symbols().has("token_move"):
		bad.append("共享移动指示物应出现在可用行动中")
	# 3) 消耗共享移动指示物
	Events.prompt_choice.connect(func(options: Array, title: String, cb: Callable) -> void:
		Game._on_answer.call_deferred(0))
	Game.use_symbol("token_move")
	for i in range(8):
		await get_tree().process_frame
	print("消耗后 shield_tokens=", str(Game.state["shield_tokens"]))
	if int(Game.state["shield_tokens"]["move"]) != 1:
		bad.append("消耗共享指示物应扣减")
	# 4) Board 手牌区显示共享指示物（4 组数量）
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	var groups: int = inst._token_info_box.get_child_count()
	print("手牌区指示物数量组=", groups)
	if groups != 4:
		bad.append("神盾局手牌区应显示共享行动指示物（4 组）")
	if bad.is_empty():
		print("=== SHIELD TOKENS TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== SHIELD TOKENS TEST FAILED: ", bad, " ===")
		get_tree().quit(1)
