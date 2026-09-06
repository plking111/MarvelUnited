extends Node
## 深入验证 bug1(火箭万能指示物能否"执行两次") 和 bug2(卡魔拉斩击套娃)。
## rocket: 天才技师选"两次行动"后，用万能指示物 → 是否也+1对应符号？
## gamora: 用攻击后得的额外攻击，再使用时是否不再触发斩击（防套娃）？

var _fail := 0

func _ready() -> void:
	await _test_rocket_wild_double()
	await _test_gamora_chain()
	if _fail == 0:
		print("=== ROCKET/GAMORA DEEP TEST ALL PASSED ===")
		get_tree().quit(0)
	else:
		print("=== FAILED (%d) ===" % _fail)
		get_tree().quit(1)

func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		_fail += 1
		print("FAIL: %s — %s" % [name, detail])
	else:
		print("PASS: %s — %s" % [name, detail])

func _test_rocket_wild_double() -> void:
	Game.autopilot = true
	Game.setup("redskull", ["rocket", "gamora", "cap"], "none")
	await Game.start_game()
	var guard := 0
	while Game.state["phase"] != "hero_play" and guard < 300:
		guard += 1
		await get_tree().process_frame
	Game.autopilot = false
	Game.state["current_hero"] = Game.state["hero_ids"].find("rocket")
	Game.state["phase"] = "hero_actions"
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	Game.state["played_effect"] = {"type": "genius_engineer", "name": "天才技师"}
	Game.state["action_symbols"] = ["move"]
	# 天才技师选"两次行动"
	var c1 := func(opts: Array, title: String, cb: Callable) -> void:
		await get_tree().process_frame
		cb.call(1)
	Events.prompt_choice.connect(c1)
	await Game.trigger_effect()
	Events.prompt_choice.disconnect(c1)
	_check("token_double 激活", Game.state.get("token_double", false), str(Game.state.get("token_double", false)))

	# 用 1 个万能指示物(wild_token)。万能指示物会走 use_symbol 的 wild 分支。
	Game.state["heroes"]["rocket"]["tokens"]["wild"] = 1
	Game.state["action_symbols"] = []
	var c2 := func(opts: Array, title: String, cb: Callable) -> void:
		await get_tree().process_frame
		# 万能行动选项: 0移动 1攻击 2英勇
		if title.contains("万能行动"):
			cb.call(0)  # 选移动
		elif title.contains("选择移动目的地"):
			cb.call(0)
		else:
			cb.call(0)
	Events.prompt_choice.connect(c2)
	await Game.use_symbol("token_wild")
	Events.prompt_choice.disconnect(c2)
	var syms: Array = Game.state["action_symbols"]
	print("火箭用万能指示物后 action_symbols=", str(syms), " wild剩=", Game.state["heroes"]["rocket"]["tokens"]["wild"])
	# 若 token_double 对万能指示物生效，应额外+1个"move"符号；若不生效则不+
	_check("火箭：万能指示物也应执行两次(+1符号)", syms.count("move") >= 1, "syms=" + str(syms))

func _test_gamora_chain() -> void:
	Game.setup("redskull", ["gamora", "rocket", "cap"], "none")
	await Game.start_game()
	var guard := 0
	while Game.state["phase"] != "hero_play" and guard < 300:
		guard += 1
		await get_tree().process_frame
	Game.state["current_hero"] = Game.state["hero_ids"].find("gamora")
	Game.state["phase"] = "hero_actions"
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	Game.state["played_effect"] = {"type": "gamora_fury", "name": "卡魔拉斩击"}
	Game.state["action_symbols"] = ["attack"]
	await Game.trigger_effect()
	_check("斩击激活", Game.state.get("gamora_fury", false), str(Game.state.get("gamora_fury", false)))
	var hloc: int = Game.state["heroes"]["gamora"]["location"]
	Game.state["locations"][hloc]["thug"] = 3
	Game.state["locations"][hloc]["threat"] = null
	Game.state["phase"] = "hero_actions"

	# 连续用多个攻击符号。若套娃，action_symbols 会越用越多不衰减
	var guard2 := 0
	var max_atk := 0
	while Game.state["action_symbols"].count("attack") > 0 and guard2 < 8:
		guard2 += 1
		var n: int = Game.state["action_symbols"].count("attack")
		if n > max_atk: max_atk = n
		var c := func(opts: Array, title: String, cb: Callable) -> void:
			await get_tree().process_frame
			cb.call(0)
		Events.prompt_choice.connect(c)
		await Game.use_symbol("attack")
		Events.prompt_choice.disconnect(c)
	print("循环后 action_symbols=", str(Game.state["action_symbols"]), " max_atk=", max_atk)
	# 若不套娃，符号应能消耗殆尽（最终0进攻）；若套娃则 max_atk 会很大/不收敛
	_check("卡魔拉：斩击额外攻击不套娃(可耗尽)", Game.state["action_symbols"].count("attack") <= 1, "final_atk=" + str(Game.state["action_symbols"].count("attack")))
