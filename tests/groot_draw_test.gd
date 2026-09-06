extends Node
## 格鲁特"我们是格鲁特"(we_are_groot) 抽牌复现测试（修正版）：
## 用 autopilot=false + 明确应答选中 cap（下一位英雄），走真实回合推进。
## 目标：验证「戈鲁特效果给 cap +1 张」且「cap 回合开始再 +1 张」，应共 +2。

var _fail := 0

func _ready() -> void:
	await _test_we_are_groot_next_hero()
	if _fail == 0:
		print("=== GROOT DRAW TEST ALL PASSED ===")
		get_tree().quit(0)
	else:
		print("=== GROOT DRAW TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)

func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		_fail += 1
		print("FAIL: %s — %s" % [name, detail])
	else:
		print("PASS: %s — %s" % [name, detail])

func _test_we_are_groot_next_hero() -> void:
	# 戈鲁特为 hero 0，下一位是 cap
	Game.autopilot = true
	Game.setup("redskull", ["groot", "cap", "ironman"], "none")
	await Game.start_game()
	# 跑到 hero_play（开局反派回合结束后的第一个英雄回合）
	var guard := 0
	while Game.state["phase"] != "hero_play" and guard < 300:
		guard += 1
		await get_tree().process_frame
	Game.autopilot = false

	# 手动设定：当前英雄 = 戈鲁特(0)，进入效果触发
	Game.state["current_hero"] = Game.state["hero_ids"].find("groot")
	Game.state["phase"] = "hero_actions"
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	Game.state["played_effect"] = {"type": "we_are_groot", "name": "我们是格鲁特"}
	Game.state["action_symbols"] = ["heroic"]

	var g_next: String = "cap"
	var b_groot: int = Game.state["heroes"]["groot"]["hand"].size()
	var b_cap: int = Game.state["heroes"][g_next]["hand"].size()
	print("效果前 hand: groot=%d cap=%d" % [b_groot, b_cap])

	# 触发效果，用 conn 应答「选择一名其他英雄」→ 选项[cap, ironman] → 选0=cap
	var conn := func(opts: Array, title: String, cb: Callable) -> void:
		await get_tree().process_frame
		cb.call(0)
	Events.prompt_choice.connect(conn)
	await Game.trigger_effect()
	Events.prompt_choice.disconnect(conn)

	var after_groot: int = Game.state["heroes"]["groot"]["hand"].size()
	var after_cap: int = Game.state["heroes"][g_next]["hand"].size()
	print("效果后 hand: groot=%d cap=%d" % [after_groot, after_cap])
	_check("戈鲁特抽到1张", after_groot == b_groot + 1,
		"groot %d->%d" % [b_groot, after_groot])
	_check("被选中英雄(cap)抽到1张", after_cap == b_cap + 1,
		"cap %d->%d" % [b_cap, after_cap])

	# 推进到 cap 回合开始：调用真实 _start_hero_turn（要求 phase 非 game_over、current_hero=cap、非KO）
	Game.state["current_hero"] = Game.state["hero_ids"].find(g_next)
	Game.state["heroes"][g_next]["ko"] = false
	Game.state["heroes"][g_next]["invulnerable"] = false
	Game.state["phase"] = "hero_draw"
	Game._start_hero_turn()
	var turnstart: int = Game.state["heroes"][g_next]["hand"].size()
	print("回合开始抽牌后 hand: cap=%d" % turnstart)
	_check("cap 回合开始抽到1张", turnstart == after_cap + 1,
		"cap %d->%d" % [after_cap, turnstart])
