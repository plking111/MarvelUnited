extends Node
## 能量卡激活：2个移动 → 突袭(3,→攻击)+疾行(1,→英勇) 各激活
func _ready() -> void:
	Game.autopilot = true
	Game.setup("thanos", ["cap"], "none")
	Game.state["phase"] = "hero_actions"
	Game.state["action_symbols"] = ["move", "move"]
	Game.state["prev_hero_symbols"] = []
	Game.state["campaign"]["energy_unlocked"] = [0, 1, 2, 3, 4, 5, 6]  # 7张全激活
	var bad: Array = []
	Game._resolve_energy_activation()
	# 应得到：突袭(3,move,move→attack) + 疾行(1,move,move→heroic)
	var got: Array = Game.state["action_symbols"]
	print("action_symbols=", got)
	var gained: Array = []
	for s in got:
		if s == "attack" or s == "heroic" or s == "move" or s == "wild":
			gained.append(s)
	# 从2个move出发，卡3突袭(→attack) + 卡1疾行(→heroic)
	# 期望在原有2个move基础上，额外 +1 attack +1 heroic
	var extra := got.slice(2)   # 去头2个move
	print("extra gains=", extra)
	var has_attack := extra.has("attack")
	var has_heroic := extra.has("heroic")
	print("has_attack=", has_attack, " has_heroic=", has_heroic)
	if not has_attack: bad.append("应获得1个攻击（突袭）")
	if not has_heroic: bad.append("应获得1个英勇（疾行）")
	# 不应有 wild
	if extra.has("wild"): bad.append("全能cost需攻击+英勇+移动，这里不应激活")
	print("---- RESULT ----")
	if bad.is_empty():
		print("=== ENERGY ACTIVATION PASSED ===")
		get_tree().quit(0)
	else:
		print("=== FAILED: ", bad, " ===")
		get_tree().quit(1)
