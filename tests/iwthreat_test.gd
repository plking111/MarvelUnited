extends Node
## 验证含"威胁"槽的能量卡（第7张）：清除威胁时可把指示物放到能量卡。

var _fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("OK: " + msg)
	else:
		_fails.append(msg)
		print("FAIL: " + msg)

func _ready() -> void:
	Game.autopilot = true
	# 强制本局能量卡 = 6（第7张，含 threat 槽）
	Game.pending_campaign = {"game": 1, "order": ["cull", "proxima", "ebony"], "stones_collected": [], "energy_unlocked": [], "removed_energy": 0}
	Game.setup("cull", ["cap", "ironman"], "none", "iw", ["无限战争"])
	Game.state["table_energy"] = 6
	Game.state["hidden_energy"] = 0
	Game.state["energy_tokens"] = {"6": [], "0": []}
	Game.state["campaign"]["table_energy"] = 6
	Game.state["campaign"]["hidden_energy"] = 0
	var need: Array = Game.energy_required_syms(6)
	_check(need.has("threat"), "第7张能量卡含威胁槽（%s）" % str(need))
	# 填满前3个非威胁槽
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	var build: Array = []
	for ns in need:
		if ns != "threat":
			build.append(ns)
	Game.state["action_symbols"] = build
	Game.state["prev_hero_symbols"] = []
	Game.state["used_tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
	for i in range(3):
		if need[i] == "threat":
			break
		var ok: bool = await Game.fill_energy_card(6, need[i])
		_check(ok, "填第%d槽（%s）" % [(i + 1), need[i]])
	_check(Game.energy_filled(6) == 3, "已填3槽（含威胁槽前）")
	# 清除威胁 → 应询问把威胁指示物放能量卡
	Game.state["locations"][0]["threat"] = {"name": "复制", "hp": 0, "heroic_tokens": 0, "bam": false, "arrival": false, "constant": false}
	Game.state["locations"][0]["threat_token"] = true
	# autopilot: _ask_confirm 返回 true
	Game.autopilot = true
	await Game._clear_threat(0)
	_check(Game.energy_filled(6) == 4, "清除威胁后能量卡填满4槽")
	_check(Game.state["campaign"]["energy_unlocked"].has(6), "含威胁槽能量卡解锁")
	_check(not Game.state["missions"][2].get("done", false), "威胁指示物未放入任务卡（放能量卡了）")
	if _fails.size() == 0:
		print("=== IW THREAT ENERGY TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== IW THREAT ENERGY TEST FAILED (%d) ===" % _fails.size())
		get_tree().quit(1)
