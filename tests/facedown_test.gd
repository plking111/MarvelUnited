extends Node
## 面朝下规则回归：英雄行动牌面朝下时，下一个英雄不得从它获得行动；
## 洛基反派牌面朝下 idx=-1 时显示应为背面（不因 action_00 崩溃）。
var _bad: Array = []
func _check(cond: bool, msg: String) -> void:
	if cond: print("OK: " + msg)
	else: _bad.append(msg); print("FAIL: " + msg)

func _ready() -> void:
	Game.autopilot = true
	Game.setup("redskull", ["cap", "ironman"], "none", "base", ["基础盒"])

	# ---- 1. _last_hero_card_symbols 跳过 face_down 英雄卡 ----
	# 模拟：story=[...更早, ironman#0(正面), cap#0(面朝下,size-2), 当前英雄卡(size-1)]
	# _last_hero_card_symbols 从 size-2 起往前找，遇到 cap(face_down) 跳过，取 ironman#0
	Game.state["story"] = [
		{"type": "villain", "villain": "redskull", "idx": 0, "move": 0},
		{"type": "hero", "hero": "ironman", "idx": 0},
		{"type": "hero", "hero": "cap", "idx": 0, "face_down": true},
		{"type": "hero", "hero": "blackpanther", "idx": 0},
	]
	var syms: Array = Game._last_hero_card_symbols()
	var expect_syms: Array = DB.hero_cards("ironman")[0]["symbols"]
	_check(syms == expect_syms, "跳过 size-2 的面朝下卡，取更早正面卡符号 (实际 %s)" % str(syms))

	# ---- 2. 若紧邻上一张是 face_down 且前面无可见卡，返回空 ----
	Game.state["story"] = [
		{"type": "hero", "hero": "cap", "idx": 0, "face_down": true},
		{"type": "hero", "hero": "blackpanther", "idx": 0},
	]
	_check(Game._last_hero_card_symbols().size() == 0, "紧邻上一张为面朝下且前无可见卡 → 无行动")

	# ---- 3. _count_last_hero_symbols 跳过面朝下 ----
	Game.state["story"] = [
		{"type": "hero", "hero": "cap", "idx": 0, "face_down": true},
		{"type": "hero", "hero": "ironman", "idx": 0},
	]
	var n: int = Game._count_last_hero_symbols("attack")
	var expect_n := 0
	for s in expect_syms:
		if s == "attack": expect_n += 1
	_check(n == expect_n, "_count_last_hero_symbols 跳过面朝下 (attack=%d 期望 %d)" % [n, expect_n])

	# ---- 4. 洛基面朝下反派牌 idx=-1：显示应为背面路径（不崩）----
	var back_path: String = DB.villain("loki")["back"]
	_check(back_path.begins_with("res://assets/cards/villains/loki/"), "洛基面朝下用 back 路径: %s" % back_path)

	print("---- RESULT ----")
	if _bad.is_empty():
		print("=== FACE DOWN RULE PASSED ===")
		get_tree().quit(0)
	else:
		print("=== FAILED: ", _bad, " ===")
		get_tree().quit(1)
