extends Node
## 电光人（邪恶六人组）回归：数据 / 危机指示物顺时针转移 / BAM（对面+相邻）/ 消失 /
## 停电 / 溢出 / 危机阻止地点结束效果 / 全地点危机判负 / KO 特殊规则 / 威胁到达效果
var _fail := 0
func _check(n: String, ok: bool, d: String) -> void:
	if ok: print("PASS: " + n)
	else: _fail += 1; print("FAIL: " + n + " — " + d)

func _ready() -> void:
	Game.autopilot = true

	# ---------- 1. 数据 ----------
	var v: Dictionary = DB.villain("electro")
	_check("电光人存在", not v.is_empty(), "")
	_check("生命 3/6/9", int(v["health"]["2"]) == 3 and int(v["health"]["3"]) == 6 and int(v["health"]["4"]) == 9, str(v["health"]))
	_check("12 张行动卡", v["actions"].size() == 12, "%d" % v["actions"].size())
	_check("6 张威胁卡", v["threats"].size() == 6, "%d" % v["threats"].size())
	var n_re := 0
	var n_op := 0
	var n_hv := 0
	for t in v["threats"]:
		match String(t["name"]):
			"充能": n_re += 1
			"力量过载": n_op += 1
			"高压": n_hv += 1
	_check("2 充能 / 2 力量过载 / 2 高压", n_re == 2 and n_op == 2 and n_hv == 2, "%d/%d/%d" % [n_re, n_op, n_hv])
	_check("邪恶计划 crisis 轨道", String(v.get("plot_track", "")) == "crisis", String(v.get("plot_track", "")))
	var n_vanish := 0
	var n_blackout := 0
	for a in v["actions"]:
		var e: Variant = a.get("effect", null)
		if e != null and String(e.get("type", "")) == "electro_vanish":
			n_vanish += 1
		if e != null and String(e.get("type", "")) == "electro_blackout":
			n_blackout += 1
	_check("2 消失 + 2 停电", n_vanish == 2 and n_blackout == 2, "消失%d 停电%d" % [n_vanish, n_blackout])

	# ---------- 2. 危机指示物：同地点不重复，顺时针转移到无危机地点 ----------
	Game.setup("electro", ["cap", "ironman"], "none", "base")
	for l in Game.state["locations"]:
		l["crisis"] = 0
	Game._electro_add_crisis(1)
	_check("危机：首次放在指定地点", int(Game.state["locations"][1]["crisis"]) == 1, "%d" % int(Game.state["locations"][1]["crisis"]))
	Game._electro_add_crisis(1)
	var shifted := int(Game.state["locations"][1]["crisis"]) == 1
	var got_next := int(Game.state["locations"][2]["crisis"]) == 1
	_check("危机：已有危机时转移到顺时针下一个无危机地点", shifted and got_next,
		"loc1=%d loc2=%d" % [int(Game.state["locations"][1]["crisis"]), int(Game.state["locations"][2]["crisis"])])
	_check("危机：不会放在已有危机的地点", int(Game.state["locations"][1]["crisis"]) == 1, "%d" % int(Game.state["locations"][1]["crisis"]))

	# ---------- 3. BAM：对面地点 + **电光人所在地点的**两个相邻地点 ----------
	Game.setup("electro", ["cap", "ironman", "hulk"], "none", "base")
	# 清空威胁卡，避免"高压"等威胁带来额外伤害干扰 BAM 计数
	for i in range(Game.LOCATION_COUNT):
		Game.state["locations"][i]["threat"] = null
	Game.state["villain_pos"] = 0
	var n: int = Game.LOCATION_COUNT
	var opp: int = 3 % n
	var vneigh: Array = Game._adjacent_locs(0)       # 电光人所在地点的两个邻居
	var opp_only: int = (opp + 1) % n                 # 只与"对面地点"相邻、与电光人地点不相邻
	for hid in ["cap", "ironman", "hulk"]:
		Game.state["heroes"][hid]["hand"] = [0, 1, 2, 3]
		Game.state["heroes"][hid]["location"] = 0
	Game.state["heroes"]["cap"]["location"] = opp
	Game.state["heroes"]["ironman"]["location"] = int(vneigh[0])
	Game.state["heroes"]["hulk"]["location"] = int(vneigh[1])
	await VillainRules.on_bam(Game, "electro")
	_check("BAM：对面地点英雄 1 伤", Game.state["heroes"]["cap"]["hand"].size() == 3, "cap=%d" % Game.state["heroes"]["cap"]["hand"].size())
	_check("BAM：电光人所在地点的两个相邻地点英雄各 1 伤",
		Game.state["heroes"]["ironman"]["hand"].size() == 3 and Game.state["heroes"]["hulk"]["hand"].size() == 3,
		"iron=%d hulk=%d" % [Game.state["heroes"]["ironman"]["hand"].size(), Game.state["heroes"]["hulk"]["hand"].size()])
	# 只与对面地点相邻、与电光人地点不相邻的地点 → 不受伤
	Game.state["heroes"]["cap"]["location"] = 0
	Game.state["heroes"]["ironman"]["location"] = opp_only
	Game.state["heroes"]["hulk"]["location"] = 0
	for hid in ["cap", "ironman", "hulk"]:
		Game.state["heroes"][hid]["hand"] = [0, 1, 2, 3]
	await VillainRules.on_bam(Game, "electro")
	_check("BAM：只与对面地点相邻（与电光人地点不相邻）的地点不受影响",
		Game.state["heroes"]["ironman"]["hand"].size() == 4,
		"iron=%d loc=%d" % [Game.state["heroes"]["ironman"]["hand"].size(), int(Game.state["heroes"]["ironman"]["location"])])

	# ---------- 4. 消失：全员出牌前不受伤害 ----------
	Game.setup("electro", ["cap", "ironman"], "none", "base")
	Game.state["villain_pos"] = 2
	Game.state["missions_completed"] = 2
	Game.state["villain_hp"] = 9
	Game.state["villain_hp_max"] = 9
	await VillainRules.resolve_effect(Game, v["actions"][8]["effect"])
	_check("消失：已进入免伤状态", bool(Game.state.get("electro_vanish", false)), "未生效")
	await Game._perform_attack_at(2, "villain", "cap")
	_check("消失：攻击无效", int(Game.state["villain_hp"]) == 9, "hp=%d" % int(Game.state["villain_hp"]))
	# 两名英雄各打出一张牌（故事情节在"消失"之后）→ 解除免伤
	for hid in ["cap", "ironman"]:
		Game.state["heroes"][hid]["hand"] = [0, 1, 2]
		Game.state["heroes"][hid]["deck"] = [3, 4, 5]
	Game.state["current_hero"] = 0
	Game.state["phase"] = "hero_play"
	await Game.play_card(0)
	Game.state["current_hero"] = 1
	Game.state["phase"] = "hero_play"
	await Game.play_card(0)
	_check("消失：全员出牌后解除免伤", not bool(Game.state.get("electro_vanish", true)),
		"vanish=%s" % str(Game.state.get("electro_vanish", true)))
	Game.state["villain_pos"] = 2
	await Game._perform_attack_at(2, "villain", "cap")
	_check("消失解除后攻击正常扣血", int(Game.state["villain_hp"]) == 8, "hp=%d" % int(Game.state["villain_hp"]))

	# ---------- 5. 停电：在电光人所在地点放置危机指示物 ----------
	Game.setup("electro", ["cap", "ironman"], "none", "base")
	for l in Game.state["locations"]:
		l["crisis"] = 0
	Game.state["villain_pos"] = 3
	await VillainRules.resolve_effect(Game, v["actions"][10]["effect"])
	_check("停电：在电光人所在地点放 1 个危机指示物", int(Game.state["locations"][3]["crisis"]) == 1,
		"crisis=%d" % int(Game.state["locations"][3]["crisis"]))

	# ---------- 6. 溢出：在该地点添加 1 个危机指示物 ----------
	Game.setup("electro", ["cap", "ironman"], "none", "base")
	for l in Game.state["locations"]:
		l["crisis"] = 0
	await VillainRules.on_overflow(Game, "electro", "thug", 4)
	_check("溢出：该地点添加 1 个危机指示物", int(Game.state["locations"][4]["crisis"]) == 1,
		"crisis=%d" % int(Game.state["locations"][4]["crisis"]))

	# ---------- 7. 危机阻止地点回合结束效果（时代广场=营救平民） ----------
	Game.setup("electro", ["cap", "ironman"], "none", "base")
	# 本局地点是随机的，可能没有时代广场 → 直接把 1 号地点改成时代广场来验证"危机封锁结束效果"
	var ts := 1
	Game.state["locations"][ts]["id"] = "times_square"
	_check("已把 1 号地点设为时代广场（用于验证结束效果被封锁）", String(DB.location("times_square")["end_turn"]["type"]) == "rescue_civ", "")
	if true:
		Game.state["locations"][ts]["threat"] = null
		Game.state["locations"][ts]["civ"] = 2
		Game.state["locations"][ts]["crisis"] = 1
		Game.state["heroes"]["cap"]["location"] = ts
		Game.state["heroes"]["cap"]["hand"] = [0, 1, 2]
		Game.state["heroes"]["cap"]["deck"] = [3, 4, 5]
		var civ_before: int = int(Game.state["locations"][ts]["civ"])
		await Game._resolve_location_end_effect("cap", ts)   # 直接调用：确认函数本身会营救
		_check("对照：直接结算地点结束效果会营救平民", int(Game.state["locations"][ts]["civ"]) == civ_before - 1,
			"civ %d -> %d" % [civ_before, int(Game.state["locations"][ts]["civ"])])
		# 通过 end_turn 走一遍：有危机 → 不应触发地点效果
		Game.state["locations"][ts]["civ"] = 2
		Game.state["locations"][ts]["crisis"] = 1
		Game.state["phase"] = "hero_end"
		Game.state["hero_cards_played"] = 0
		Game.state["end_turn_busy"] = false
		await Game.end_turn()
		_check("危机：地点有危机指示物时不能用该地点回合结束效果", int(Game.state["locations"][ts]["civ"]) == 2,
			"civ=%d" % int(Game.state["locations"][ts]["civ"]))

	# ---------- 8. 邪恶计划：所有地点都有危机指示物 → 失败 ----------
	Game.setup("electro", ["cap", "ironman"], "none", "base")
	for i in range(Game.LOCATION_COUNT):
		Game.state["locations"][i]["crisis"] = 1
	var lost: bool = Game._check_lose()
	_check("所有地点都有危机 → 英雄失败", lost and Game.state["phase"] == "game_over",
		"lost=%s phase=%s" % [str(lost), String(Game.state["phase"])])

	# ---------- 9. KO 特殊规则：不激活 BAM，改为在被 KO 英雄所在地点放危机 ----------
	Game.setup("electro", ["cap", "ironman"], "none", "base")
	for l in Game.state["locations"]:
		l["crisis"] = 0
	Game.state["heroes"]["cap"]["hand"] = [0, 1]
	Game.state["heroes"]["cap"]["location"] = 2
	await Game._ko_hero("cap")
	_check("KO：电光人不激活 BAM，改为在英雄所在地点放 1 个危机",
		int(Game.state["locations"][2]["crisis"]) == 1 and Game.state["phase"] != "game_over",
		"crisis=%d" % int(Game.state["locations"][2]["crisis"]))

	# ---------- 10. 威胁到达效果：充能 +3 生命 / 力量过载额外打一张 ----------
	Game.setup("electro", ["cap", "ironman"], "none", "base")
	for i in range(Game.LOCATION_COUNT):
		Game.state["locations"][i]["threat"] = null
	Game.state["villain_hp"] = 6
	Game.state["villain_hp_max"] = 6
	Game.state["extra_villain_card"] = 0
	Game.state["locations"][1]["threat"] = {"name": "充能", "text": "", "hp": 0, "heroic_tokens": 0, "arrival": true, "arrival_triggered": false, "bam": false, "constant": false}
	await Game._trigger_threat_arrival(1)
	_check("充能到达：电光人 +3 生命值", int(Game.state["villain_hp"]) == 9, "hp=%d" % int(Game.state["villain_hp"]))
	Game.state["locations"][2]["threat"] = {"name": "力量过载", "text": "", "hp": 0, "heroic_tokens": 0, "arrival": true, "arrival_triggered": false, "bam": false, "constant": false}
	await Game._trigger_threat_arrival(2)
	_check("力量过载到达：额外打出 1 张反派行动卡", int(Game.state["extra_villain_card"]) == 1,
		"extra=%d" % int(Game.state["extra_villain_card"]))
	# 高压：在该地点受到伤害 +1
	Game.state["locations"][3]["threat"] = {"name": "高压", "text": "", "hp": 0, "heroic_tokens": 0, "arrival": false, "bam": false, "constant": true}
	Game.state["heroes"]["cap"]["location"] = 3
	Game.state["heroes"]["cap"]["hand"] = [0, 1, 2, 3]
	await Game._deal_damage_to_hero("cap", 1)
	_check("高压：该地点英雄受到的伤害 +1", Game.state["heroes"]["cap"]["hand"].size() == 2,
		"hand=%d" % Game.state["heroes"]["cap"]["hand"].size())

	if _fail == 0:
		print("=== ELECTRO TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== ELECTRO FAILED (%d) ===" % _fail)
		get_tree().quit(1)
