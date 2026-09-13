extends Node
## 万能牌测试：打出万能牌，选择"攻击"，应正常消耗 wild 并执行攻击（同步驱动）。

func _ready() -> void:
	Game.autopilot = false
	Game.setup("redskull", ["cap"], "none")
	# 看门狗：35 秒未完成则转储状态退出，便于定位卡点（要留够反派回合的翻牌兜底时间）
	get_tree().create_timer(35.0).timeout.connect(func() -> void:
		var h: Dictionary = Game.state.get("heroes", {}).get("cap", {})
		print("WATCHDOG: phase=%s villain_pos=%d hero_loc=%s 符号=%s story=%d master=%d waiting=%s" % [
			Game.state.get("phase", "?"), Game.state.get("villain_pos", -1),
			str(h.get("location", "?")), str(Game.state.get("action_symbols", [])),
			Game.state.get("story", []).size(), Game.state.get("master_deck", []).size(),
			str(Game.state.get("waiting_input", false))])
		get_tree().quit(1))
	# 记录所有弹出的提示标题，卡住时最后一条即卡点
	Events.prompt_choice.connect(func(options: Array, title: String, cb: Callable) -> void:
		print("PROMPT_CHOICE: ", title))
	# 第一反派回合里"翻开背面威胁卡 / 选择要使用的行动"这类弹窗走行动弹窗（prompt_action）；
	# 本测试原来只接 prompt_choice/confirm，于是卡在那里、永远到不了英雄阶段。
	# 只在"开局→进英雄阶段"这段自动应答（选第 0 项）；进英雄阶段后由测试自己按索引答。
	var auto_answer: Array = [true]
	Events.prompt_action.connect(func(rows: Array, title: String, cb: Callable) -> void:
		print("PROMPT_ACTION: ", title)
		if bool(auto_answer[0]) and rows.size() > 0:
			cb.call_deferred(0))
	Events.prompt_confirm.connect(func(text: String, cb: Callable) -> void:
		print("PROMPT_CONFIRM: ", text))
	# 自动应答受伤弃牌（第一反派回合可能因威胁 BAM 伤到英雄）
	Events.prompt_hand_card.connect(func(cb: Callable, title: String, hid2: String, count: int) -> void:
		await get_tree().process_frame
		var auto: Array = []
		var h: Dictionary = Game.state["heroes"][hid2]
		for i in range(mini(count, h["hand"].size())):
			auto.append(i)
		cb.call(auto))
	await Game.start_game()
	var guard := 0
	# 注意：无 Board 的逻辑测试里没人点"翻牌确认"，_await_villain_reveal 每次会等满 4.5 秒的兜底；
	# 原来的"100 帧"（约 1.7 秒）根本不够 → 永远到不了英雄阶段。改成按时间等。
	var t0 := Time.get_ticks_msec()
	while Game.state["phase"] != "hero_play" and Time.get_ticks_msec() - t0 < 25000:
		guard += 1
		await get_tree().process_frame
	if Game.state["phase"] != "hero_play":
		print("WILD TEST FAIL: 未进入英雄阶段")
		get_tree().quit(1)
		return
	var hid := "cap"
	var wild_card := -1
	for i in range(DB.hero_cards(hid).size()):
		if DB.hero_cards(hid)[i]["symbols"] == ["wild"]:
			wild_card = i
			break
	Game.state["heroes"][hid]["hand"] = [wild_card]
	var target_loc := -1
	for i in range(Game.LOCATION_COUNT):
		var l: Dictionary = Game.state["locations"][i]
		var bad: bool = l["threat"] != null and (l["threat"]["name"] == "精锐暴徒" or l["threat"]["name"] == "九头蛇精英部队")
		if not bad:
			l["thug"] = 1
			target_loc = i
			break
	Game.state["heroes"][hid]["location"] = target_loc
	auto_answer[0] = false     # 进英雄阶段了：下面由测试自己按索引答，别再自动应答
	Game.play_card(0)
	print("符号: %s" % str(Game.state["action_symbols"]))
	Game.use_symbol("wild")
	print("弹窗1后 phase=%s 符号=%s" % [Game.state["phase"], str(Game.state["action_symbols"])])
	Game._on_answer(1)
	print("弹窗2后 phase=%s 符号=%s" % [Game.state["phase"], str(Game.state["action_symbols"])])
	Game._on_answer(0)
	var thug_now: int = Game.state["locations"][target_loc]["thug"]
	print("结果: 暴徒=%d 符号=%s phase=%s" % [thug_now, str(Game.state["action_symbols"]), Game.state["phase"]])
	if thug_now == 0 and Game.state["action_symbols"].size() == 0:
		print("=== WILD TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== WILD TEST FAILED ===")
		get_tree().quit(1)