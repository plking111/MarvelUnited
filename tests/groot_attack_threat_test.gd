extends Node
## 格鲁特"我是格鲁特！"效果攻击能否填充罗南威胁卡（攻击符号）验证：
## 格鲁特在含罗南威胁卡的地点攻击时，目标选项应含"用攻击行动填充威胁"，选中后填入 attack。

var _fail := 0

func _ready() -> void:
	await _test_groot_get_attack_fill()
	if _fail == 0:
		print("=== GROOT ATTACK THREAT TEST ALL PASSED ===")
		get_tree().quit(0)
	else:
		print("=== GROOT ATTACK THREAT TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)

func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		_fail += 1
		print("FAIL: %s — %s" % [name, detail])
	else:
		print("PASS: %s — %s" % [name, detail])

func _test_groot_get_attack_fill() -> void:
	Game.autopilot = true
	Game.setup("ronan", ["groot", "cap", "ironman"], "none")
	await Game.start_game()
	var guard := 0
	while Game.state["phase"] != "hero_play" and guard < 300:
		guard += 1
		await get_tree().process_frame
	Game.autopilot = false

	# 手动设定当前英雄=格鲁特，进入效果触发
	Game.state["current_hero"] = Game.state["hero_ids"].find("groot")
	Game.state["phase"] = "hero_actions"
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	Game.state["played_effect"] = {"type": "get_groot", "name": "我是格鲁特！"}
	Game.state["action_symbols"] = ["attack"]

	# 把格鲁特放到一个有罗南"克里精英部队"威胁卡的地点；若无该卡，找一个 clear 含 attack 的地点
	var root_loc: int = Game.state["heroes"]["groot"]["location"]
	var found_attack_loc := -1
	for i in range(Game.state["locations"].size()):
		var t: Variant = Game.state["locations"][i]["threat"]
		if t != null and t.has("clear") and t["clear"].has("attack"):
			found_attack_loc = i
			break
	if found_attack_loc < 0:
		_check("找到含攻击符号威胁卡的位置", false, "地图上无攻击型罗南威胁卡")
		return
	Game.state["heroes"]["groot"]["location"] = found_attack_loc
	Game.state["heroes"]["cap"]["location"] = found_attack_loc
	var t0: Dictionary = Game.state["locations"][found_attack_loc]["threat"]
	var before: int = t0.get("clear_progress", []).size()
	print("格鲁特所在地点威胁卡: %s clear=%s filled_before=%d" % [t0["name"], str(t0["clear"]), before])

	# 触发效果：get_groot 先选"其他英雄"(cap)，然后格鲁特攻击。攻击目标选项需含填充威胁。
	# 用 conn 依次应答：①选其他英雄选0=cap ②攻击目标选"用攻击行动填充威胁"
	var answers: Array = []
	var step := 0
	var conn := func(opts: Array, title: String, cb: Callable) -> void:
		await get_tree().process_frame
		if title.contains("我是格鲁特！：选择一名其他英雄"):
			cb.call(0)  # 选 cap
		elif title.contains("选择攻击目标"):
			# 找填充威胁选项下标
			var fi := -1
			for i in range(opts.size()):
				if str(opts[i]).contains("填充威胁"):
					fi = i
					break
			cb.call(fi if fi >= 0 else 0)
		else:
			cb.call(0)
	Events.prompt_choice.connect(conn)
	await Game.trigger_effect()
	Events.prompt_choice.disconnect(conn)

	var t1: Dictionary = Game.state["locations"][found_attack_loc]["threat"]
	var after: int = t1.get("clear_progress", []).size()
	print("效果后 clear_progress: %d (期望 > %d)" % [after, before])
	_check("格鲁特攻击填入威胁卡", after > before, "filled %d->%d" % [before, after])
