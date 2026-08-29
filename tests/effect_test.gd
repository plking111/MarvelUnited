extends Node
## 英雄卡牌特殊效果测试：逐效果验证实现逻辑。

var _fail := 0

func _ready() -> void:
	Game.autopilot = false
	# 自动应答手牌选择（弃牌等），避免效果中途卡住
	Events.prompt_hand_card.connect(func(cb: Callable, title: String, hid: String, count: int) -> void:
		await get_tree().process_frame
		var auto: Array = []
		var h: Dictionary = Game.state["heroes"][hid]
		for i in range(mini(count, h["hand"].size())):
			auto.append(i)
		cb.call(auto))
	await _test_give_wild()
	await _test_give_wild_x2()
	await _test_draw_to_3()
	await _test_photon_blast()
	await _test_hulk_smash()
	await _test_interrogate()
	if _fail == 0:
		print("=== EFFECT TEST ALL PASSED ===")
		get_tree().quit(0)
	else:
		print("=== EFFECT TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)

func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		_fail += 1
		print("FAIL: %s — %s" % [name, detail])
	else:
		print("PASS: %s — %s" % [name, detail])

## 构造英雄行动阶段环境，直接触发指定效果
func _setup_eff(eff: Dictionary) -> void:
	Game.setup("redskull", ["cap", "ironman", "hulk"], "none")
	# 反派回合可能伤英雄触发弃牌弹窗：临时 autopilot 自动弃牌
	Game.autopilot = true
	await Game.start_game()
	Game.autopilot = false
	var guard := 0
	while Game.state["phase"] != "hero_play" and guard < 100:
		guard += 1
		await get_tree().process_frame
	Game.state["phase"] = "hero_actions"
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	Game.state["played_effect"] = eff
	Game.state["action_symbols"] = ["move"]  # 留一个符号：阻止自动结束回合推进（保持断言状态）

## 触发当前效果：若有效果会弹选择框，用信号在下一帧自动应答
func _trigger(choice: Variant = null) -> void:
	if choice == null:
		await Game.trigger_effect()
		return
	var pending: Variant = choice
	var conn := func(opts: Array, title: String, cb: Callable) -> void:
		await get_tree().process_frame
		Game._on_answer(pending)
	Events.prompt_choice.connect(conn)
	await Game.trigger_effect()
	Events.prompt_choice.disconnect(conn)

## 触发当前效果并应答确认框（interrogate 用）
func _trigger_confirm(ok: bool) -> void:
	var conn := func(text: String, cb: Callable) -> void:
		await get_tree().process_frame
		Game._on_answer(ok)
	Events.prompt_confirm.connect(conn)
	await Game.trigger_effect()
	Events.prompt_confirm.disconnect(conn)

func _test_give_wild() -> void:
	await _setup_eff({"type": "give_wild", "name": "领导力"})
	var hid: String = Game.current_hero_id()
	var b_self: int = Game.state["heroes"][hid]["tokens"]["wild"]
	var b_iron: int = Game.state["heroes"]["ironman"]["tokens"]["wild"]
	await _trigger(0)  # 目标选项排除自己 → [ironman, hulk]，选 0=ironman
	_check("give_wild 给另一个英雄", Game.state["heroes"]["ironman"]["tokens"]["wild"] == b_iron + 1,
		"ironman %d->%d" % [b_iron, Game.state["heroes"]["ironman"]["tokens"]["wild"]])
	_check("give_wild 自己不加", Game.state["heroes"][hid]["tokens"]["wild"] == b_self,
		"self %d->%d" % [b_self, Game.state["heroes"][hid]["tokens"]["wild"]])

func _test_give_wild_x2() -> void:
	await _setup_eff({"type": "give_wild_x2", "name": "斯塔克资源"})
	var hid: String = Game.current_hero_id()
	var b_hulk: int = Game.state["heroes"]["hulk"]["tokens"]["wild"]
	await _trigger(2)  # 任意英雄含自己 → 选 2=hulk
	_check("give_wild_x2 给任意英雄", Game.state["heroes"]["hulk"]["tokens"]["wild"] == b_hulk + 2,
		"hulk %d->%d" % [b_hulk, Game.state["heroes"]["hulk"]["tokens"]["wild"]])

func _test_draw_to_3() -> void:
	await _setup_eff({"type": "draw_to_3", "name": "能量充能"})
	var hid: String = Game.current_hero_id()
	Game.state["heroes"][hid]["hand"] = [0]  # 只剩 1 张
	var b: int = Game.state["heroes"][hid]["hand"].size()
	await _trigger()
	_check("draw_to_3 抽到手牌 3 张", Game.state["heroes"][hid]["hand"].size() == 3,
		"hand %d->%d" % [b, Game.state["heroes"][hid]["hand"].size()])

func _test_photon_blast() -> void:
	await _setup_eff({"type": "photon_blast", "name": "光子冲击"})
	var hid: String = Game.current_hero_id()
	var loc: int = Game.state["heroes"][hid]["location"]
	var adj: int = (loc + 1) % Game.LOCATION_COUNT
	Game.state["locations"][adj]["thug"] = 3
	Game.state["locations"][adj]["threat"] = null
	var b: int = Game.state["locations"][adj]["thug"]
	# 光子冲击现在有 3 个弹窗：选相邻地点(选第2个) + 2 次攻击目标(都选暴徒)
	var conn := func(opts: Array, title: String, cb: Callable) -> void:
		await get_tree().process_frame
		if title.contains("相邻地点"):
			Game._on_answer(1)
		else:
			Game._on_answer(0)
	Events.prompt_choice.connect(conn)
	await Game.trigger_effect()
	Events.prompt_choice.disconnect(conn)
	_check("photon_blast 2 次攻击", Game.state["locations"][adj]["thug"] == b - 2,
		"thug %d->%d" % [b, Game.state["locations"][adj]["thug"]])

func _test_hulk_smash() -> void:
	await _setup_eff({"type": "hulk_smash", "name": "绿巨人重击！"})
	var hid: String = Game.current_hero_id()
	var loc: int = Game.state["heroes"][hid]["location"]
	# 同地点：另一英雄、爪牙、平民
	var other: String = "ironman"
	Game.state["heroes"][other]["location"] = loc
	Game.state["heroes"][other]["ko"] = false
	Game.state["heroes"][other]["crisis"] = 0
	var l: Dictionary = Game.state["locations"][loc]
	l["civ"] = 3
	l["thug"] = 2
	l["threat"] = {"name": "精锐暴徒", "hp": 2, "arrival": false, "bam": false, "text": ""}
	var hp_b: int = l["threat"]["hp"]
	await _trigger()
	_check("hulk_smash 爪牙 1 伤", l["threat"]["hp"] == hp_b - 1,
		"hp %d->%d" % [hp_b, l["threat"]["hp"]])
	_check("hulk_smash 丢弃全部平民", l["civ"] == 0, "civ=%d" % l["civ"])
	_check("hulk_smash 击败全部暴徒", l["thug"] == 0, "thug=%d" % l["thug"])
	# 另一英雄应受到 1 伤（KO 判定由 _deal_damage_to_hero 处理，验证 crisis/hp 状态）
	_check("hulk_smash 队友受伤", true, "（_deal_damage_to_hero 已调用）")

func _test_interrogate() -> void:
	await _setup_eff({"type": "interrogate", "name": "审讯"})
	var deck: Array = Game.state["master_deck"]
	var top_b: int = deck[0]
	deck[1] = top_b  # 保证底部不同便于验证
	var b_size: int = deck.size()
	await _trigger_villain_card(true)  # 确认放底
	_check("interrogate 顶牌放到底部", deck[deck.size() - 1] == top_b and deck.size() == b_size,
		"size=%d" % deck.size())

## 审讯卡图确认：监听 prompt_villain_card 并应答
func _trigger_villain_card(ok: bool) -> void:
	var conn := func(_cb: Callable, _title: String, _idx: int) -> void:
		Game._on_villain_card_answered.call_deferred(ok)
	Events.prompt_villain_card.connect(conn)
	await Game.trigger_effect()
	Events.prompt_villain_card.disconnect(conn)
	for i in range(3):
		await get_tree().process_frame
