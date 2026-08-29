extends Node
## 营救平民/击败暴徒即时刷新测试：操作后状态应立即变化（无需其他操作触发刷新）。

func _ready() -> void:
	Game.autopilot = false
	Game.setup("redskull", ["cap"], "none")
	Game.autopilot = true
	await Game.start_game()
	Game.autopilot = false
	var hid := "cap"
	Game.state["phase"] = "hero_actions"
	Game.state["action_symbols"] = ["heroic", "attack"]
	var loc: int = Game.state["heroes"][hid]["location"]
	Game.state["locations"][loc]["civ"] = 2
	Game.state["locations"][loc]["thug"] = 2
	Game.state["locations"][loc]["threat"] = null
	var civ_before: int = Game.state["locations"][loc]["civ"]
	var thug_before: int = Game.state["locations"][loc]["thug"]
	var res_tok_before: int = Game.state["missions"][0]["tokens"]
	var def_tok_before: int = Game.state["missions"][1]["tokens"]
	# 应答英勇行动选择（0=营救平民）
	var conn := func(opts: Array, title: String, cb: Callable) -> void:
		await get_tree().process_frame
		Game._on_answer(0)
	Events.prompt_choice.connect(conn)
	Game.use_symbol("heroic")
	for i in range(5):
		await get_tree().process_frame
	Events.prompt_choice.disconnect(conn)
	var civ_after: int = Game.state["locations"][loc]["civ"]
	var res_tok_after: int = Game.state["missions"][0]["tokens"]
	var ok1: bool = civ_after == civ_before - 1 and res_tok_after == res_tok_before + 1
	print("营救: civ %d->%d 任务 %d->%d %s" % [civ_before, civ_after, res_tok_before, res_tok_after, "OK" if ok1 else "FAIL"])
	# 应答攻击目标选择（0=暴徒）
	var conn2 := func(opts: Array, title: String, cb: Callable) -> void:
		await get_tree().process_frame
		Game._on_answer(0)
	Events.prompt_choice.connect(conn2)
	Game.use_symbol("attack")
	for i in range(5):
		await get_tree().process_frame
	Events.prompt_choice.disconnect(conn2)
	var thug_after: int = Game.state["locations"][loc]["thug"]
	var def_tok_after: int = Game.state["missions"][1]["tokens"]
	var ok2: bool = thug_after == thug_before - 1 and def_tok_after == def_tok_before + 1
	print("击败: thug %d->%d 任务 %d->%d %s" % [thug_before, thug_after, def_tok_before, def_tok_after, "OK" if ok2 else "FAIL"])
	if ok1 and ok2:
		print("=== RESCUE/DEFEAT REFRESH PASSED ===")
		get_tree().quit(0)
	else:
		print("=== RESCUE/DEFEAT REFRESH FAILED ===")
		get_tree().quit(1)
