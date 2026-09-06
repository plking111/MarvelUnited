extends Node
## 验证 bug：卡魔拉斩击，用"最后一个攻击/万能"时，斩击 +1 攻击应可用（不被 _maybe_auto_end_turn 提前结束回合）。

var _fail := 0

func _ready() -> void:
	await _test_gamora_last_attack()
	if _fail == 0:
		print("=== GAMORA LAST ATTACK TEST ALL PASSED ===")
		get_tree().quit(0)
	else:
		print("=== GAMORA LAST ATTACK TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)

func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		_fail += 1
		print("FAIL: %s — %s" % [name, detail])
	else:
		print("PASS: %s — %s" % [name, detail])

func _test_gamora_last_attack() -> void:
	Game.autopilot = true
	Game.setup("redskull", ["gamora", "rocket", "cap"], "none")
	await Game.start_game()
	var guard := 0
	while Game.state["phase"] != "hero_play" and guard < 300:
		guard += 1
		await get_tree().process_frame
	# 当前英雄=卡魔拉，触发斩击
	Game.state["current_hero"] = Game.state["hero_ids"].find("gamora")
	Game.state["phase"] = "hero_actions"
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	Game.state["played_effect"] = {"type": "gamora_fury", "name": "卡魔拉斩击"}
	Game.state["action_symbols"] = ["attack"]
	await Game.trigger_effect()
	_check("斩击已激活", Game.state.get("gamora_fury", false), str(Game.state.get("gamora_fury", false)))

	# 该地点放个暴徒做攻击目标
	var hloc: int = Game.state["heroes"]["gamora"]["location"]
	Game.state["locations"][hloc]["thug"] = 1
	Game.state["locations"][hloc]["threat"] = null
	Game.state["phase"] = "hero_actions"
	# 只有 1 个攻击符号（最后一个）。普通符号在 use_symbol 里会先扣掉再执行。
	Game.state["action_symbols"] = ["attack"]
	var conn := func(opts: Array, title: String, cb: Callable) -> void:
		await get_tree().process_frame
		cb.call(0)  # 选暴徒
	Events.prompt_choice.connect(conn)
	await Game.use_symbol("attack")
	Events.prompt_choice.disconnect(conn)
	var phase: String = Game.state["phase"]
	var syms: Array = Game.state["action_symbols"]
	print("用最后一个攻击后 phase=%s action_symbols=%s" % [phase, str(syms)])
	# 期望：斩击 +1 攻击，让回合不立即结束（phase 仍为 hero_actions），且留有1个攻击符号可用
	_check("最后一个攻击后回合未被提前结束", phase == "hero_actions", "phase=" + phase)
	_check("斩击 +1 攻击可用", syms.count("attack") >= 1, "syms=" + str(syms))
