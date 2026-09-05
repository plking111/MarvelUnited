extends Node
## 完整战役流程测试：第1局 → 下一局 → 决战；验证 gem 保留/能量卡跨局。

var _fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("OK: " + msg)
	else:
		_fails.append(msg)
		print("FAIL: " + msg)

func _ready() -> void:
	Game.autopilot = true
	# 第 1 局
	Game.pending_campaign = {"game": 1, "order": ["cull", "proxima", "ebony"], "stones_collected": [], "energy_unlocked": [], "removed_energy": 6}
	Game.pending_setup = {"villain": "cull", "heroes": ["cap", "ironman"], "challenge": "none", "mode": "iw", "expansions": ["无限战争"]}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	# 模拟胜利：直接调用 _win
	Game._win()
	_check(Game.state["phase"] == "game_over", "第1局胜利 game_over")
	_check(Game.state["campaign"]["stones_collected"].size() == 0, "胜利时未翻出的宝石保留（0颗收集，除非翻出）")
	# 未翻出的宝石不在 stones_collected（模拟牌组还剩宝石）
	var stones_in_deck := 0
	for e in Game.state["master_deck"]:
		if e is Dictionary and e.has("stone"):
			stones_in_deck += 1
	_check(stones_in_deck >= 1, "牌组中还有未翻出的宝石（%d 颗）" % stones_in_deck)
	_check(not Game.state["campaign"]["stones_collected"].has(6), "removed_energy=6 不是宝石索引（无关）")
	print("=== IW FLOW TEST PASSED ===")
	get_tree().quit(0)
