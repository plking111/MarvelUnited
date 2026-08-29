extends Node
## 验证受伤弃牌回到该英雄牌库底（普通模式 + 神盾局模式）。

func _ready() -> void:
	Game.pending_setup = {"villain": "redskull", "heroes": ["cap", "ironman", "hulk"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	var st: Dictionary = Game.state
	# ---- 场景1：普通模式 ----
	# cap 手牌 3 张（标号 9/10/11，cap 共 12 张卡合法），牌库已有 [0,1,2]
	st["heroes"]["cap"]["hand"] = [9, 10, 11]
	st["heroes"]["cap"]["deck"] = [0, 1, 2]
	var deck_before: Array = st["heroes"]["cap"]["deck"].duplicate()
	# 自动应答弃牌：选索引 0（即手牌 9）
	var cb := func(_cb: Callable, _title: String, _hid: String, _cnt: int) -> void:
		Game._on_hand_answered.call_deferred([0])
	Events.prompt_hand_card.connect(cb)
	Game.autopilot = false
	await Game._deal_damage_to_hero("cap", 1)
	Events.prompt_hand_card.disconnect(cb)
	await get_tree().process_frame
	# 断言：手牌剩 [10,11]；牌库底多了 9 → deck == [0,1,2,9]
	var ok1: bool = st["heroes"]["cap"]["hand"].size() == 2 and not st["heroes"]["cap"]["hand"].has(9)
	var ok2: bool = st["heroes"]["cap"]["deck"].size() == deck_before.size() + 1 and st["heroes"]["cap"]["deck"][-1] == 9
	print("普通模式: 手牌=", st["heroes"]["cap"]["hand"], " 牌库=", st["heroes"]["cap"]["deck"], " (期望底=9)")
	# ---- 场景2：神盾局模式 ----
	Game.pending_setup = {"villain": "redskull", "heroes": ["cap", "ironman", "hulk"], "challenge": "none", "mode": "shield"}
	var board2: PackedScene = load("res://src/ui/Board.tscn")
	var inst2: Control = board2.instantiate()
	add_child(inst2)
	for i in range(10):
		await get_tree().process_frame
	var st2: Dictionary = Game.state
	st2["shield_hand"] = [{"hero": "cap", "idx": 9}, {"hero": "cap", "idx": 10}, {"hero": "ironman", "idx": 0}]
	st2["shield_deck"] = [{"hero": "cap", "idx": 0}, {"hero": "cap", "idx": 1}, {"hero": "cap", "idx": 2}]
	var sdeck_before: int = st2["shield_deck"].size()
	var cb2 := func(_cb: Callable, _title: String, _hid: String, _cnt: int) -> void:
		Game._on_hand_answered.call_deferred([0])
	Events.prompt_hand_card.connect(cb2)
	Game.autopilot = false
	await Game._deal_damage_to_hero("cap", 1)
	Events.prompt_hand_card.disconnect(cb2)
	await get_tree().process_frame
	var ok3: bool = st2["shield_hand"].size() == 2 and st2["shield_deck"].size() == sdeck_before + 1 and st2["shield_deck"][-1]["idx"] == 9
	print("神盾局: 共享手牌数=", st2["shield_hand"].size(), " 共享牌库数=", st2["shield_deck"].size(), " 牌库底idx=", st2["shield_deck"][-1]["idx"], " (期望9)")
	if ok1 and ok2 and ok3:
		print("=== DISCARD TO DECK TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== DISCARD TO DECK TEST FAILED ===", [ok1, ok2, ok3])
		get_tree().quit(1)
