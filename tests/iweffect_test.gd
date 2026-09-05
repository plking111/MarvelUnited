extends Node
## 验证决战能量卡效果：每拥有 2 个攻击 → 获得 1 个英勇（可多次）；产出不参与其他卡判定。

var _fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("OK: " + msg)
	else:
		_fails.append(msg)
		print("FAIL: " + msg)

func _ready() -> void:
	Game.autopilot = true
	# 决战 setup，能量卡0（e1: cost 2攻击 → gain 1英勇）已解锁
	Game.pending_campaign = {"game": 4, "order": ["cull", "proxima", "ebony"], "stones_collected": [0], "energy_unlocked": [0], "removed_energy": 6}
	Game.setup("thanos", ["cap"], "none", "iw", ["无限战争决战"])
	_check(Game.state.get("final_battle", false), "决战状态")
	# 模拟打出卡：action_symbols 含 4 攻击
	Game.state["phase"] = "hero_actions"
	Game.state["action_symbols"] = ["attack", "attack", "attack", "attack"]
	Game.state["prev_hero_symbols"] = []
	Game._resolve_energy_activation()
	var gained_heroic := 0
	for s in Game.state["action_symbols"]:
		if s == "heroic":
			gained_heroic += 1
	_check(gained_heroic == 2, "4攻击 → 获得2英勇（实际%d）" % gained_heroic)
	_check(Game.state["action_symbols"].size() == 6, "行动池 4攻击+2英勇 = 6（实际%d）" % Game.state["action_symbols"].size())

	# 测试 2 攻击 → 1 英勇
	Game.state["action_symbols"] = ["attack", "attack"]
	Game.state["prev_hero_symbols"] = []
	Game._resolve_energy_activation()
	gained_heroic = 0
	for s in Game.state["action_symbols"]:
		if s == "heroic":
			gained_heroic += 1
	_check(gained_heroic == 1, "2攻击 → 获得1英勇（实际%d）" % gained_heroic)

	# 测试产出英勇不参与其他能量卡判定：解锁 e2（cost 2移动→1英勇）后，
	# 手牌只有攻击（无移动），不应触发 e2
	Game.state["campaign"]["energy_unlocked"] = [0, 1]
	Game.state["action_symbols"] = ["attack", "attack"]
	Game.state["prev_hero_symbols"] = []
	Game._resolve_energy_activation()
	# e1 触发：2攻击→1英勇；e2 需要移动，无移动不触发
	var heroic_count := 0
	var heroics_from_e1 := 1
	for s in Game.state["action_symbols"]:
		if s == "heroic":
			heroic_count += 1
	_check(heroic_count == 1, "e2 无移动符号不触发（英勇总数%d，期望1）" % heroic_count)

	if _fails.size() == 0:
		print("=== IW ENERGY EFFECT TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== IW ENERGY EFFECT TEST FAILED (%d) ===" % _fails.size())
		get_tree().quit(1)
