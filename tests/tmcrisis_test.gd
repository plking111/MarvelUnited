extends Node
## 验证模仿大师危机清除规则：
## 1) 普通攻击/英勇在无民暴+有危机时可清除（已实现）
## 2) 光子冲击效果攻击在无民暴+有危机时也应能清除（疑似缺口）
## 3) 新加地点（无限战争）与基础地点的危机清除一致性

var _fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("OK: " + msg)
	else:
		_fails.append(msg)
		print("FAIL: " + msg)

func _ready() -> void:
	Game.autopilot = true
	# 用模仿大师 + 一个基础地点和一个新加地点分别验证
	for loc_id in ["central_park", "hala"]:
		Game.setup("taskmaster", ["cap"], "none")
		# 强制某地点 = loc_id
		Game.state["locations"][0]["id"] = loc_id
		Game.state["locations"][0]["civ"] = 0
		Game.state["locations"][0]["thug"] = 0
		Game.state["locations"][0]["crisis"] = 2
		Game.state["locations"][0]["threat"] = null
		Game.state["heroes"]["cap"]["location"] = 0
		Game.state["phase"] = "hero_actions"
		Game.state["action_symbols"] = ["heroic", "attack", "heroic"]
		Game.state["prev_hero_symbols"] = []
		Game.state["used_tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
		# autopilot _ask 返回 0 → 弹窗第一个选项
		# 英勇：选项[0]=? 看 _execute_heroic：无平民无威胁 → 只有危机清除 → 选项[0]=清除危机
		Game.autopilot = true
		await Game._execute_heroic("cap", "symbol")
		_check(Game.state["locations"][0]["crisis"] == 1, "%s 英勇清除危机（剩余%d）" % [loc_id, Game.state["locations"][0]["crisis"]])
		# 攻击：_execute_attack 无民暴无爪牙 → 危机选项为唯一目标（autopilot 选0）
		Game.state["action_symbols"] = ["attack"]
		await Game._execute_attack("cap", "symbol")
		_check(Game.state["locations"][0]["crisis"] == 0, "%s 攻击清除危机（剩余%d）" % [loc_id, Game.state["locations"][0]["crisis"]])
	print("=== 基础/新加地点英勇+攻击清除危机 验证完成 ===")
	# 光子冲击清危机（已修复）：无民暴+有危机时可清除
	Game.setup("taskmaster", ["cap"], "none")
	Game.state["locations"][0]["civ"] = 0
	Game.state["locations"][0]["thug"] = 0
	Game.state["locations"][0]["crisis"] = 2
	Game.state["locations"][0]["threat"] = null
	Game.state["heroes"]["cap"]["location"] = 0
	Game.state["phase"] = "hero_actions"
	Game.autopilot = true
	await Game._attack_once_at("cap", 0, "光子冲击")
	_check(Game.state["locations"][0]["crisis"] == 1, "光子冲击清除危机（剩余%d）" % Game.state["locations"][0]["crisis"])
	# blocked：地点有危机时不能伤害模仿大师（即使能打到 villain 也不允许）
	Game.state["locations"][0]["crisis"] = 1
	Game.state["villain_pos"] = 0
	Game.state["villain_hp"] = 5
	Game.state["missions_completed"] = 3
	# 普通攻击：有危机 → villain 不应出现在目标列表
	var l0: Dictionary = Game.state["locations"][0]
	var t0 := "villain"
	# 直接走 _execute_attack 但检查 blocked 逻辑：vill_attackable 里 crisis>0 时 blocked
	Game.state["action_symbols"] = ["attack"]
	# autopilot 会选第一个目标；若 villain 被 blocked，则只有危机清除可选（清掉危机后危机=0）
	await Game._execute_attack("cap", "symbol")
	_check(Game.state["villain_hp"] == 5, "有危机时攻击不能伤害模仿大师（hp仍%d）" % Game.state["villain_hp"])
	if _fails.size() == 0:
		print("=== TASKMASTER CRISIS TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== TASKMASTER CRISIS TEST FAILED (%d) ===" % _fails.size())
		get_tree().quit(1)
