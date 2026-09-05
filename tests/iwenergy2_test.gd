extends Node
## 验证能量卡新机制：万能解锁、任意顺序、行动弹窗入口、完成后不显示。

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
	# 第7张能量卡（attack/heroic/move/threat）为本局卡
	Game.pending_campaign = {"game": 1, "order": ["cull", "proxima", "ebony"], "stones_collected": [], "energy_unlocked": [], "removed_energy": 0}
	Game.setup("cull", ["cap"], "none", "iw", ["无限战争"])
	Game.state["table_energy"] = 6
	Game.state["hidden_energy"] = -1
	Game.state["campaign"]["table_energy"] = 6
	Game.state["energy_tokens"] = {"6": []}
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0

	# ===== bug6：任意顺序——先填 threat 槽（模拟清除威胁） =====
	Game.state["locations"][0]["threat"] = {"name": "复制", "hp": 0, "heroic_tokens": 0, "bam": false, "arrival": false, "constant": false}
	Game.state["locations"][0]["threat_token"] = true
	Game.autopilot = true
	await Game._clear_threat(0)
	var filled0: Array = Game.energy_filled_slots(6)
	_check(filled0.has(3), "先填威胁槽（索引3，任意顺序）filled=%s" % str(filled0))
	# 再填英勇槽（索引1）
	Game.autopilot = false
	Game.state["action_symbols"] = ["heroic"]
	Game.state["used_tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
	# 用 fill_energy_card 直接填（弹窗由 _offer_energy_or_use 处理，这里验证任意顺序）
	var ok_h: bool = await Game.fill_energy_card(6, "heroic")
	_check(ok_h, "先威胁后英勇可填充（任意顺序）")
	var filled1: Array = Game.energy_filled_slots(6)
	_check(filled1.has(3) and filled1.has(1), "槽位含威胁(3)与英勇(1)：%s" % str(filled1))

	# ===== bug4：万能指示物可解锁 =====
	Game.state["energy_tokens"] = {"6": []}
	Game.state["action_symbols"] = []
	Game.state["heroes"]["cap"]["tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 1}
	Game.state["used_tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
	# 万能指示物：energy_match_slot 应接受 wild（匹配任意非 threat 槽）
	var m: int = Game.energy_match_slot(6, "wild")
	_check(m >= 0 and m != 3, "万能可匹配普通符号槽（索引%d）" % m)
	# 通过 _offer_energy_or_use 验证弹窗出现"填充能量卡"选项
	Events.prompt_choice.connect(func(opts: Array, _t: String, cb: Callable) -> void:
		_seen_options = opts.duplicate()
		cb.call_deferred(0))
	Game.state["action_symbols"] = ["attack"]
	var ret: String = await Game._offer_energy_or_use("attack", "symbol", "cap")
	var has_energy_opt: bool = false
	for o in _seen_options:
		if o.contains("填充能量卡"):
			has_energy_opt = true
	_check(has_energy_opt, "行动弹窗包含'填充能量卡'选项（%s）" % str(_seen_options))

	# ===== bug2：能量卡完成后不显示填充选项 =====
	Game.state["energy_tokens"] = {"6": [0, 1, 2, 3]}
	_seen_options = []
	var ret2: String = await Game._offer_energy_or_use("attack", "symbol", "cap")
	var still_has: bool = false
	for o in _seen_options:
		if o.contains("填充能量卡"):
			still_has = true
	_check(not still_has, "能量卡完成后行动弹窗不再显示填充选项")

	if _fails.size() == 0:
		print("=== IW ENERGY MECHANICS TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== IW ENERGY MECHANICS TEST FAILED (%d) ===" % _fails.size())
		get_tree().quit(1)
