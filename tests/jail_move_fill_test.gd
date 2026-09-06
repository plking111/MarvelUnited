extends Node
## 越狱威胁卡兼容性验证（调试版）：
## 直接调 _execute_move，验证"用移动填充威胁"不被"离开需2移动"拦截。

var _fail := 0

func _ready() -> void:
	await _test_jail_fill()
	if _fail == 0:
		print("=== JAIL MOVE FILL TEST ALL PASSED ===")
		get_tree().quit(0)
	else:
		print("=== JAIL MOVE FILL TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)

func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		_fail += 1
		print("FAIL: %s — %s" % [name, detail])
	else:
		print("PASS: %s — %s" % [name, detail])

func _test_jail_fill() -> void:
	Game.autopilot = true
	Game.setup("ronan", ["cap"], "none")
	await Game.start_game()
	var guard := 0
	while Game.state["phase"] != "hero_play" and guard < 300:
		guard += 1
		await get_tree().process_frame
	Game.autopilot = false

	var jail_loc := -1
	for i in range(Game.state["locations"].size()):
		var t: Variant = Game.state["locations"][i]["threat"]
		if t != null and t["name"] == "越狱":
			jail_loc = i
			break
	if jail_loc < 0:
		_check("找到越狱威胁卡位置", false, "地图上无越狱卡")
		return
	Game.state["heroes"]["cap"]["location"] = jail_loc
	Game.state["current_hero"] = Game.state["hero_ids"].find("cap")
	Game.state["phase"] = "hero_actions"
	Game.state["action_symbols"] = ["move", "move"]
	var t0: Dictionary = Game.state["locations"][jail_loc]["threat"]
	var before: int = t0.get("clear_progress", []).size()
	print("越狱卡: name=%s clear=%s filled_before=%d" % [t0["name"], str(t0["clear"]), before])
	print("can_fill(move) = %s" % str(Game._ronan_threat_can_fill(jail_loc, "move")))

	# 直接调 _execute_move，用 conn 应答"用移动行动填充威胁"
	var had_fill_option := false
	var conn := func(opts: Array, title: String, cb: Callable) -> void:
		await get_tree().process_frame
		var fi := -1
		for i in range(opts.size()):
			if str(opts[i]).contains("填充威胁"):
				fi = i
				break
		print("  弹窗选项: ", str(opts))
		cb.call(fi if fi >= 0 else 0)
	Events.prompt_choice.connect(conn)
	await Game._execute_move("cap", "symbol")
	Events.prompt_choice.disconnect(conn)

	var t1: Dictionary = Game.state["locations"][jail_loc]["threat"]
	var after: int = t1.get("clear_progress", []).size()
	print("填充后 clear_progress: %d (期望 > %d)" % [after, before])
	_check("越狱时用移动填充威胁成功", after > before, "filled %d->%d" % [before, after])
