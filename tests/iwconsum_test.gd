extends Node
## 验证：bug1 使用行动填充能量卡时行动被消耗；bug2 iw模式三手下置前+灭霸置暗。

var _fails: Array = []
var _seen_options: Array = []

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("OK: " + msg)
	else:
		_fails.append(msg)
		print("FAIL: " + msg)

func _ready() -> void:
	Game.autopilot = false
	# 能量卡0（英勇×4）为本局卡
	Game.pending_campaign = {"game": 1, "order": ["cull", "proxima", "ebony"], "stones_collected": [], "energy_unlocked": [], "removed_energy": 6}
	Game.setup("cull", ["cap"], "none", "iw", ["无限战争"])
	Game.state["table_energy"] = 0
	Game.state["hidden_energy"] = -1
	Game.state["campaign"]["table_energy"] = 0
	Game.state["energy_tokens"] = {"0": []}
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	Game.state["action_symbols"] = ["heroic", "heroic"]
	Game.state["prev_hero_symbols"] = []
	Game.state["used_tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
	# 拦截弹窗：自动选择"填充能量卡 1"
	Events.prompt_choice.connect(func(opts: Array, _t: String, cb: Callable) -> void:
		_seen_options = opts.duplicate()
		var fill_idx := -1
		for i in range(opts.size()):
			if str(opts[i]).contains("填充能量卡"):
				fill_idx = i
				break
		cb.call_deferred(fill_idx if fill_idx >= 0 else 0))
	# 使用英勇行动（应弹窗 → 选填充能量卡）
	var before: int = Game.state["action_symbols"].size()
	await Game.use_symbol("heroic")
	await get_tree().process_frame
	var after: int = Game.state["action_symbols"].size()
	_check(after == before - 1, "使用英勇填充能量卡后行动消耗（%d→%d）" % [before, after])
	_check(Game.energy_filled(0) == 1, "能量卡填 1 槽")
	# 第二次：选择"返回"应归还行动
	Events.prompt_choice.disconnect(Events.prompt_choice.get_connections()[-1]["callable"])
	Events.prompt_choice.connect(func(opts: Array, _t2: String, cb: Callable) -> void:
		_seen_options = opts.duplicate()
		cb.call_deferred(opts.size() - 1))  # 选"返回"
	before = Game.state["action_symbols"].size()
	await Game.use_symbol("heroic")
	await get_tree().process_frame
	after = Game.state["action_symbols"].size()
	_check(after == before, "选择'返回'后行动归还（%d→%d）" % [before, after])
	_check(Game.energy_filled(0) == 1, "返回后能量卡仍 1 槽")

	# ===== bug2：iw 模式排序与灭霸置暗 =====
	var setup_scene: PackedScene = load("res://src/ui/Setup.tscn")
	var inst := setup_scene.instantiate()
	add_child(inst)
	for i in range(30):
		await get_tree().process_frame
	inst._on_mode_selected(7)
	await get_tree().process_frame
	inst._render_villains()
	await get_tree().process_frame
	# 三手下按钮应排在灭霸之前（按 y/x 位置）
	var p: Vector2 = inst._villain_buttons["proxima"].position
	var c: Vector2 = inst._villain_buttons["cull"].position
	var e: Vector2 = inst._villain_buttons["ebony"].position
	var t: Vector2 = inst._villain_buttons["thanos"].position
	_check(p.y <= t.y and c.y <= t.y and e.y <= t.y, "三手下在灭霸之前（proxima y=%.0f cull y=%.0f ebony y=%.0f thanos y=%.0f）" % [p.y, c.y, e.y, t.y])
	_check(inst._villain_buttons["thanos"].modulate != Color.WHITE, "灭霸置暗（modulate=%s）" % str(inst._villain_buttons["thanos"].modulate))

	if _fails.size() == 0:
		print("=== ENERGY CONSUME & IW ORDER TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== ENERGY CONSUME & IW ORDER TEST FAILED (%d) ===" % _fails.size())
		get_tree().quit(1)
