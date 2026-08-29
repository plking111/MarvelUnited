extends Node
## 验证黑寡妇审讯：显示主计划牌卡图（prompt_villain_card 信号）并应答。

var _got_idx := -1

func _ready() -> void:
	Game.pending_setup = {"villain": "redskull", "heroes": ["cap", "ironman", "widow"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	var st: Dictionary = Game.state
	# 触发审讯效果（widow 当前英雄）
	st["master_deck"] = [3]  # 顶牌索引 3
	st["phase"] = "hero_actions"
	st["effect_available"] = true
	st["effect_used"] = false
	st["current_hero"] = st["hero_ids"].find("widow")
	st["played_effect"] = {"type": "interrogate", "name": "审讯"}
	# 监听 prompt_villain_card：记录卡索引并应答"保持原位"(false)
	var cb := func(_cb: Callable, _title: String, idx: int) -> void:
		_got_idx = idx
		Game._on_villain_card_answered.call_deferred(false)
	Events.prompt_villain_card.connect(cb)
	Game.autopilot = false
	await Game.trigger_effect()
	Events.prompt_villain_card.disconnect(cb)
	await get_tree().process_frame
	var ok1: bool = _got_idx == 3  # 顶牌被传给信号（卡图显示）
	var ok2: bool = st["master_deck"][0] == 3  # 保持原位
	print("信号收到卡索引=", _got_idx, " (期望3) 顶牌=", st["master_deck"][0])
	# 再次触发，应答"放到底部"(true)
	st["phase"] = "hero_actions"
	st["effect_available"] = true
	st["effect_used"] = false
	st["current_hero"] = st["hero_ids"].find("widow")
	st["played_effect"] = {"type": "interrogate", "name": "审讯"}
	var cb2 := func(_cb: Callable, _title: String, idx: int) -> void:
		Game._on_villain_card_answered.call_deferred(true)
	Events.prompt_villain_card.connect(cb2)
	Game.autopilot = false
	await Game.trigger_effect()
	Events.prompt_villain_card.disconnect(cb2)
	await get_tree().process_frame
	var ok3: bool = st["master_deck"][-1] == 3  # 放到底部
	print("放到底部后顶牌=", st["master_deck"][0], " 底部=", st["master_deck"][-1])
	if ok1 and ok2 and ok3:
		print("=== INTERROGATE CARD TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== INTERROGATE CARD TEST FAILED ===", [ok1, ok2, ok3])
		get_tree().quit(1)
