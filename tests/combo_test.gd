extends Node
## 综合修复验证：指示物消耗、任务后节奏轮流、钢铁侠攻击指示物、洗牌堆、撤回。

var _fail := 0
var _answer_idx := 0

func _ready() -> void:
	Game.autopilot = false
	await _test_token_consume()
	await _test_rhythm()
	await _test_give_attack_x2()
	await _test_shuffle_discard()
	await _test_undo()
	if _fail == 0:
		print("=== COMBO TEST ALL PASSED ===")
		get_tree().quit(0)
	else:
		print("=== COMBO TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)

func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		_fail += 1
		print("FAIL: %s — %s" % [name, detail])
	else:
		print("PASS: %s — %s" % [name, detail])

func _wait_hero_play() -> void:
	var guard := 0
	while Game.state["phase"] != "hero_play" and guard < 100:
		guard += 1
		await get_tree().process_frame

## 问题3：行动指示物使用后消耗（不重复使用）
func _test_token_consume() -> void:
	Game.setup("redskull", ["cap"], "none")
	Game.autopilot = true
	await Game.start_game()
	await _wait_hero_play()
	Game.autopilot = false
	var hid := "cap"
	Game.state["phase"] = "hero_actions"
	Game.state["action_symbols"] = []
	Game.state["virus_ignore"] = false
	Game.state["heroes"][hid]["tokens"]["attack"] = 2
	var loc: int = Game.state["heroes"][hid]["location"]
	Game.state["locations"][loc]["thug"] = 2
	Game.state["locations"][loc]["threat"] = null
	# 使用 1 个攻击指示物
	var conn := func(opts: Array, title: String, cb: Callable) -> void:
		await get_tree().process_frame
		Game._on_answer(0)
	Events.prompt_choice.connect(conn)
	print("DEBUG 使用前 tokens=", str(Game.state["heroes"][hid]["tokens"]), " phase=", Game.state["phase"])
	Game.use_symbol("token_attack")
	print("DEBUG 调用后立刻 tokens=", str(Game.state["heroes"][hid]["tokens"]))
	for i in range(5):
		await get_tree().process_frame
	Events.prompt_choice.disconnect(conn)
	var remain: int = Game.state["heroes"][hid]["tokens"]["attack"]
	_check("攻击指示物消耗", remain == 1, "attack tokens 2->%d" % remain)

## 问题6：任务完成后（节奏2）3 英雄轮流不跳过
func _test_rhythm() -> void:
	Game.setup("redskull", ["cap", "ironman", "hulk"], "none")
	Game.autopilot = true
	await Game.start_game()
	await _wait_hero_play()
	Game.state["missions_completed"] = 1  # 节奏 2
	var seen: Array = []
	var guard := 0
	while seen.size() < 12 and guard < 200:
		guard += 1
		match Game.state["phase"]:
			"hero_play":
				seen.append(Game.current_hero_id())
				var hand: Array = Game.state["heroes"][Game.current_hero_id()]["hand"]
				if hand.size() > 0:
					Game.play_card(0)
				else:
					Game.state["phase"] = "hero_end"
			"hero_actions":
				Game.end_actions()
			"hero_end":
				await Game.end_turn()
		await get_tree().process_frame
	# 每 3 个连续英雄应恰好覆盖 cap/ironman/hulk 各一次（轮流，无跳过）
	var ok := true
	for i in range(3, seen.size() + 1, 3):
		var chunk: Array = seen.slice(i - 3, i)
		if chunk.count("cap") != 1 or chunk.count("ironman") != 1 or chunk.count("hulk") != 1:
			ok = false
			break
	_check("任务后英雄轮流不跳过", ok, "序列=%s" % str(seen.slice(0, 12)))

## 问题8：钢铁侠 give_attack_x2 —— 2 个攻击指示物任意分配
func _test_give_attack_x2() -> void:
	Game.setup("redskull", ["cap", "ironman", "hulk"], "none")
	Game.autopilot = true
	await Game.start_game()
	await _wait_hero_play()
	Game.autopilot = false
	var hid := Game.current_hero_id()
	Game.state["phase"] = "hero_actions"
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	Game.state["played_effect"] = {"type": "give_attack_x2", "name": "斯塔克资源"}
	var b_cap: int = Game.state["heroes"]["cap"]["tokens"]["attack"]
	var b_iron: int = Game.state["heroes"]["ironman"]["tokens"]["attack"]
	# 两次分配：先选 cap（index 0），再选 ironman（index 1）
	var answers := [0, 1]
	_answer_idx = 0
	var conn := func(opts: Array, title: String, cb: Callable) -> void:
		await get_tree().process_frame
		Game._on_answer(answers[_answer_idx])
		_answer_idx += 1
	Events.prompt_choice.connect(conn)
	await Game.trigger_effect()
	Events.prompt_choice.disconnect(conn)
	_check("give_attack_x2 攻击指示物", Game.state["heroes"]["cap"]["tokens"]["attack"] == b_cap + 1
		and Game.state["heroes"]["ironman"]["tokens"]["attack"] == b_iron + 1,
		"cap %d->%d ironman %d->%d" % [b_cap, Game.state["heroes"]["cap"]["tokens"]["attack"], b_iron, Game.state["heroes"]["ironman"]["tokens"]["attack"]])

## 问题7：牌库空时洗混弃牌堆
func _test_shuffle_discard() -> void:
	Game.setup("redskull", ["cap"], "none")
	Game.autopilot = true
	await Game.start_game()
	var hid := "cap"
	var h: Dictionary = Game.state["heroes"][hid]
	h["deck"] = []
	h["discard"] = [1, 2, 3, 4]
	h["hand"] = []
	var drew: bool = Game._draw_card(hid)
	_check("牌库空洗弃牌堆", drew and h["hand"].size() == 1 and h["deck"].size() == 3 and h["discard"].size() == 0,
		"hand=%d deck=%d discard=%d" % [h["hand"].size(), h["deck"].size(), h["discard"].size()])

## 问题5：撤回功能
func _test_undo() -> void:
	Game.setup("redskull", ["cap"], "none")
	Game.autopilot = true
	await Game.start_game()
	await _wait_hero_play()
	Game.autopilot = false
	Game.undo_enabled = true
	var hid := "cap"
	Game.state["phase"] = "hero_actions"
	Game.state["action_symbols"] = ["move", "move"]  # 留 1 个：阻止自动结束回合清空撤回快照
	var loc_before: int = Game.state["heroes"][hid]["location"]
	var conn := func(opts: Array, title: String, cb: Callable) -> void:
		await get_tree().process_frame
		Game._on_answer(0)
	Events.prompt_choice.connect(conn)
	Game.use_symbol("move")
	for i in range(5):
		await get_tree().process_frame
	Events.prompt_choice.disconnect(conn)
	var loc_after: int = Game.state["heroes"][hid]["location"]
	var moved: bool = loc_after != loc_before
	Game.undo_last()
	var loc_undone: int = Game.state["heroes"][hid]["location"]
	_check("撤回恢复位置", moved and loc_undone == loc_before,
		"loc %d->%d 撤回后 %d" % [loc_before, loc_after, loc_undone])
	# 抽牌后不可撤回：行动 → 抽 1 张 → 撤回应无效
	Game.state["phase"] = "hero_actions"
	Game.state["action_symbols"] = ["move", "move"]
	Game.state["virus_ignore"] = false
	var conn2 := func(opts: Array, title: String, cb: Callable) -> void:
		await get_tree().process_frame
		Game._on_answer(0)
	Events.prompt_choice.connect(conn2)
	Game.use_symbol("move")
	for i in range(5):
		await get_tree().process_frame
	Events.prompt_choice.disconnect(conn2)
	var loc_moved2: int = Game.state["heroes"][hid]["location"]
	Game._draw_card(hid)  # 抽取新牌 → 快照清空
	Game.undo_last()
	var loc_after_undo: int = Game.state["heroes"][hid]["location"]
	_check("抽牌后不可撤回", loc_after_undo == loc_moved2,
		"移动后 %d 抽牌后撤回仍 %d" % [loc_moved2, loc_after_undo])
	Game.undo_enabled = false
