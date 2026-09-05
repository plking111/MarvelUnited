extends Node
## 洛基回归：数据完整性 + setup + 关键规则逻辑
var _bad: Array = []

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("OK: " + msg)
	else:
		_bad.append(msg)
		print("FAIL: " + msg)

func _ready() -> void:
	# ========== 1. 数据完整性 ==========
	_check(DB.villains.size() == 9, "反派总数 9 (实际 %d)" % DB.villains.size())
	var loki: Dictionary = DB.villain("loki")
	_check(not loki.is_empty(), "loki 存在")
	_check(loki["health"]["2"] == 3 and loki["health"]["3"] == 5 and loki["health"]["4"] == 7, "洛基生命 3/5/7")
	_check(loki["actions"].size() == 12, "洛基 12 张行动卡 (实际 %d)" % loki["actions"].size())
	_check(loki["threats"].size() == 6, "洛基 6 张威胁卡 (实际 %d)" % loki["threats"].size())
	# 卡1 特殊移动 + 巫术/传播不和效果
	_check(loki["actions"][0]["effect"]["type"] == "loki_reach_empty_threat", "卡1 幻象大师效果")
	_check(loki["actions"][8]["effect"]["type"] == "loki_witchcraft", "卡9 巫术效果")
	_check(loki["actions"][10]["effect"]["type"] == "loki_discord", "卡11 传播不和效果")
	_check(loki["plot_track"] == "none", "洛基无邪恶计划轨道")

	# ========== 2. setup 不崩 ==========
	Game.autopilot = true
	Game.setup("loki", ["cap", "ironman"], "none", "base", ["基础盒"])
	_check(Game.state["villain"] == "loki", "setu完 villain=loki")
	_check(Game.state["locations"].size() == Game.LOCATION_COUNT, "地点数=%d" % Game.LOCATION_COUNT)
	print("洛基 setup 后 villain_hp=", Game.state["villain_hp"], " max=", Game.state["villain_hp_max"])

	# ========== 3. 洛基 BAM：所在地点英雄各1伤 ==========
	Game.setup("loki", ["cap", "ironman"], "none", "base", ["基础盒"])
	Game.state["heroes"]["cap"]["location"] = Game.state["villain_pos"]
	Game.state["heroes"]["ironman"]["location"] = Game.state["villain_pos"]
	await VillainRules.on_bam(Game, "loki")
	print("BAM 后 cap 手牌数=", Game.state["heroes"]["cap"]["hand"].size(), " (应减少)")

	# ========== 4. 巫术：孤独英雄判定（该地点仅1未KO英雄）==========
	Game.setup("loki", ["cap", "ironman"], "none", "base", ["基础盒"])
	var vpos: int = Game.state["villain_pos"]
	Game.state["heroes"]["cap"]["location"] = vpos
	Game.state["heroes"]["ironman"]["location"] = (vpos + 1) % Game.LOCATION_COUNT
	var lonely: Array = VillainRules._lonely_heroes(Game)
	_check(lonely.size() == 2, "两英雄各在一处 → 2 个孤独 (实际 %d)" % lonely.size())

	print("---- RESULT ----")
	if _bad.is_empty():
		print("=== LOKI TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== FAILED: ", _bad, " ===")
		get_tree().quit(1)
