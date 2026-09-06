extends Node
## 验证罗南 KO 相关修复：
## bug1: 罗南对局英雄被KO → 不替换英雄（仍在 hero_ids），仅 ko_tokens+1
## bug2: 万能行动弹窗 options 应含"返回"

var _fail := 0

func _ready() -> void:
	await _test_ronan_ko_no_replace()
	await _test_wild_return_option()
	if _fail == 0:
		print("=== RONAN KO FIX TEST ALL PASSED ===")
		get_tree().quit(0)
	else:
		print("=== RONAN KO FIX TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)

func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		_fail += 1
		print("FAIL: %s — %s" % [name, detail])
	else:
		print("PASS: %s — %s" % [name, detail])

func _test_ronan_ko_no_replace() -> void:
	Game.autopilot = true
	Game.setup("ronan", ["cap", "ironman", "hulk"], "none")
	await Game.start_game()
	var guard := 0
	while Game.state["phase"] != "hero_play" and guard < 300:
		guard += 1
		await get_tree().process_frame
	Game.autopilot = false
	var before_ids: Array = Game.state["hero_ids"].duplicate()
	var before_ko: int = int(Game.state.get("ko_tokens", 0))
	Game.state["heroes"]["cap"]["hand"] = []
	Game.state["phase"] = "hero_actions"
	# 用持久 conn 变量，任意弹窗应答0（BAM 选英雄、或其它）
	var conn := func(opts: Array, title: String, cb: Callable) -> void:
		await get_tree().process_frame
		cb.call(0)
	Events.prompt_choice.connect(conn)
	await Game._ko_hero("cap")
	Events.prompt_choice.disconnect(conn)
	var after_ids: Array = Game.state["hero_ids"]
	var after_ko: int = int(Game.state.get("ko_tokens", 0))
	print("KO后 hero_ids=%s (期望含cap) ko_tokens=%d->%d" % [str(after_ids), before_ko, after_ko])
	_check("罗南KO不替换英雄(英雄仍在)", after_ids.has("cap"), "hero_ids=" + str(after_ids))
	_check("罗南KO 获得KO指示物+1", after_ko == before_ko + 1, "ko %d->%d" % [before_ko, after_ko])

func _test_wild_return_option() -> void:
	Game.setup("redskull", ["cap"], "none")
	await Game.start_game()
	var guard := 0
	while Game.state["phase"] != "hero_play" and guard < 300:
		guard += 1
		await get_tree().process_frame
	Game.state["current_hero"] = Game.state["hero_ids"].find("cap")
	Game.state["phase"] = "hero_actions"
	Game.state["action_symbols"] = ["wild"]
	var con := func(opts: Array, title: String, cb: Callable) -> void:
		await get_tree().process_frame
		cb.call(opts.size() - 1)  # 选"返回"(最后一个)
	Events.prompt_choice.connect(con)
	await Game.use_symbol("wild")
	Events.prompt_choice.disconnect(con)
	# bug2 核心：选"返回"后万能未被消耗（说明弹窗有返回入口且返回逻辑生效）
	_check("万能行动含返回且选返回后万能未消耗", Game.state["action_symbols"].has("wild"), "syms=" + str(Game.state["action_symbols"]))
