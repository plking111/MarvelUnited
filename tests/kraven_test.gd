extends Node
## 猎人克莱文（邪恶六人组）回归：数据 / BAM（危机指示物加伤）/ 顽固的狩猎 / 陷阱 / 诱饵 /
## 溢出 / 全部 KO 判负 / 特殊移动 / KO 特殊规则
var _fail := 0
func _check(n: String, ok: bool, d: String) -> void:
	if ok: print("PASS: " + n)
	else: _fail += 1; print("FAIL: " + n + " — " + d)

func _ready() -> void:
	Game.autopilot = true

	# ---------- 1. 数据 ----------
	var v: Dictionary = DB.villain("kraven")
	_check("克莱文存在", not v.is_empty(), "")
	_check("生命 4/7/10", int(v["health"]["2"]) == 4 and int(v["health"]["3"]) == 7 and int(v["health"]["4"]) == 10, str(v["health"]))
	_check("12 张行动卡", v["actions"].size() == 12, "%d" % v["actions"].size())
	_check("6 张威胁卡", v["threats"].size() == 6, "%d" % v["threats"].size())
	var n_stalk := 0
	var n_trap := 0
	var n_decoy := 0
	for a in v["actions"]:
		var e: Variant = a.get("effect", null)
		if e != null and String(e.get("type", "")) == "kraven_stalk":
			n_stalk += 1
	for t in v["threats"]:
		if t["name"] == "陷阱":
			n_trap += 1
		if t["name"] == "诱饵":
			n_decoy += 1
	_check("4 张顽固的狩猎", n_stalk == 4, "%d" % n_stalk)
	_check("3 陷阱 + 3 诱饵", n_trap == 3 and n_decoy == 3, "陷阱%d 诱饵%d" % [n_trap, n_decoy])
	_check("邪恶计划 allko", String(v.get("plot_track", "")) == "allko", String(v.get("plot_track", "")))
	_check("特殊规则：KO 打另一张卡", String(v["special"]).contains("KO"), String(v["special"]))

	# ---------- 2. BAM：在场 1 伤 + 危机持有人按危机数受伤 ----------
	Game.setup("kraven", ["cap", "ironman"], "none", "base")
	Game.state["villain_pos"] = 0
	for hid in ["cap", "ironman"]:
		Game.state["heroes"][hid]["location"] = 2
		Game.state["heroes"][hid]["hand"] = [0, 1, 2, 3, 4, 5]
		Game.state["heroes"][hid]["crisis"] = 0
	Game.state["heroes"]["cap"]["location"] = 0
	Game.state["locations"][0]["threat"] = null   # 清空威胁（避免"陷阱"额外加伤干扰 BAM 计数）
	Game.state["heroes"]["cap"]["crisis"] = 2
	await VillainRules.on_bam(Game, "kraven")
	_check("BAM：在场英雄 1 伤 + 危机 2 伤（共弃 3 张）", Game.state["heroes"]["cap"]["hand"].size() == 3,
		"hand=%d" % Game.state["heroes"]["cap"]["hand"].size())
	_check("BAM：不在场的英雄不受影响", Game.state["heroes"]["ironman"]["hand"].size() == 6,
		"hand=%d" % Game.state["heroes"]["ironman"]["hand"].size())

	# ---------- 3. 顽固的狩猎：+1 危机并触发 BAM ----------
	Game.setup("kraven", ["cap", "ironman"], "none", "base")
	Game.state["villain_pos"] = 1
	for hid in ["cap", "ironman"]:
		Game.state["heroes"][hid]["location"] = 3
		Game.state["heroes"][hid]["hand"] = [0, 1, 2, 3, 4, 5]
		Game.state["heroes"][hid]["crisis"] = 0
	Game.state["heroes"]["cap"]["location"] = 1
	Game.state["locations"][1]["threat"] = null   # 清空该地点威胁（避免"陷阱"额外加伤干扰 BAM 计数）
	var stalk: Dictionary = v["actions"][0]["effect"]
	await VillainRules.resolve_effect(Game, stalk)
	_check("顽固的狩猎：获得 1 个危机指示物", int(Game.state["heroes"]["cap"]["crisis"]) == 1,
		"crisis=%d" % int(Game.state["heroes"]["cap"]["crisis"]))
	_check("顽固的狩猎：随后触发 BAM（1+1=2 伤）", Game.state["heroes"]["cap"]["hand"].size() == 4,
		"hand=%d" % Game.state["heroes"]["cap"]["hand"].size())

	# ---------- 4. 陷阱：无民无暴时英雄受到的伤害 +1 ----------
	Game.setup("kraven", ["cap", "ironman"], "none", "base")
	Game.state["heroes"]["cap"]["location"] = 4
	Game.state["heroes"]["cap"]["hand"] = [0, 1, 2, 3, 4, 5]
	Game.state["locations"][4]["threat"] = {"name": "陷阱", "text": "", "hp": 0, "heroic_tokens": 0, "arrival": false, "bam": false, "constant": true}
	Game.state["locations"][4]["civ"] = 0
	Game.state["locations"][4]["thug"] = 0
	await Game._deal_damage_to_hero("cap", 1)
	_check("陷阱：无民无暴 → 伤害 +1（共弃 2 张）", Game.state["heroes"]["cap"]["hand"].size() == 4,
		"hand=%d" % Game.state["heroes"]["cap"]["hand"].size())
	Game.state["heroes"]["cap"]["hand"] = [0, 1, 2, 3, 4, 5]
	Game.state["locations"][4]["civ"] = 1
	await Game._deal_damage_to_hero("cap", 1)
	_check("陷阱：有平民 → 不额外加伤（弃 1 张）", Game.state["heroes"]["cap"]["hand"].size() == 5,
		"hand=%d" % Game.state["heroes"]["cap"]["hand"].size())

	# ---------- 5. 诱饵：一回合内忽略在该地点受到的第一次伤害 ----------
	Game.setup("kraven", ["cap", "ironman"], "none", "base")
	Game.state["villain_pos"] = 2
	Game.state["locations"][2]["threat"] = {"name": "诱饵", "text": "", "hp": 0, "heroic_tokens": 0, "arrival": false, "bam": false, "constant": true}
	Game.state["missions_completed"] = 2
	Game.state["villain_hp"] = 7
	Game.state["villain_hp_max"] = 7
	Game.state["kraven_decoy_used"] = false
	await Game._perform_attack_at(2, "villain", "cap")
	_check("诱饵：第一次攻击被忽略", int(Game.state["villain_hp"]) == 7, "hp=%d" % int(Game.state["villain_hp"]))
	await Game._perform_attack_at(2, "villain", "cap")
	_check("诱饵：第二次攻击正常扣血", int(Game.state["villain_hp"]) == 6, "hp=%d" % int(Game.state["villain_hp"]))

	# ---------- 6. 溢出：玩家选择一名英雄受到 1 点伤害 ----------
	# 本步只验"溢出=1 名英雄受 1 点伤害"这一条规则，必须排除威胁卡的干扰：
	# Game.setup 会随机抽 6 个地点 + 随机发 6 张威胁卡，若「陷阱」正好落在英雄所在地点
	# 且该地点没有平民/暴徒，_deal_damage_to_hero 会 +1（弃 2 张）→ 断言偶发变红（本测试曾因此 flaky）。
	# 清空所有威胁后，本步与随机抽取无关，结果确定。
	Game.setup("kraven", ["cap", "ironman"], "none", "base")
	for l in Game.state["locations"]:
		l["threat"] = null
	for hid in ["cap", "ironman"]:
		Game.state["heroes"][hid]["hand"] = [0, 1, 2, 3]
	await VillainRules.on_overflow(Game, "kraven", "thug", 0)
	_check("溢出：一名英雄受到 1 点伤害", Game.state["heroes"]["cap"]["hand"].size() == 3,
		"cap手牌=%d" % Game.state["heroes"]["cap"]["hand"].size())

	# ---------- 7. 邪恶计划：英雄同一时间全部 KO → 失败 ----------
	Game.setup("kraven", ["cap", "ironman"], "none", "base")
	Game.state["heroes"]["cap"]["ko"] = true
	Game.state["heroes"]["ironman"]["ko"] = false
	_check("仅一人 KO 不判负", not Game._check_lose(), "")
	Game.state["heroes"]["ironman"]["ko"] = true
	var lost: bool = Game._check_lose()
	_check("全部同时 KO → 英雄失败", lost and Game.state["phase"] == "game_over",
		"lost=%s phase=%s" % [str(lost), String(Game.state["phase"])])

	# ---------- 8. 顽固的狩猎卡的特殊移动：顺时针到下一个有英雄的地点 ----------
	Game.setup("kraven", ["cap", "ironman"], "none", "base")
	Game.state["villain_pos"] = 0
	for hid in ["cap", "ironman"]:
		Game.state["heroes"][hid]["location"] = 2
	Game._do_villain_move(v["actions"][0]["move"])
	_check("特殊移动：顺时针到下一个有英雄的地点", int(Game.state["villain_pos"]) == 2,
		"pos=%d" % int(Game.state["villain_pos"]))

	# ---------- 9. KO 特殊规则：不触发 BAM，改为打出另一张反派行动卡 ----------
	Game.setup("kraven", ["cap", "ironman"], "none", "base")
	Game.state["extra_villain_card"] = 0
	Game.state["heroes"]["cap"]["hand"] = [0, 1]
	await Game._ko_hero("cap")
	_check("KO：克莱文不触发 BAM，改打另一张行动卡", int(Game.state["extra_villain_card"]) == 1 and Game.state["phase"] != "game_over",
		"extra=%d phase=%s" % [int(Game.state["extra_villain_card"]), String(Game.state["phase"])])

	if _fail == 0:
		print("=== KRAVEN TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== KRAVEN FAILED (%d) ===" % _fail)
		get_tree().quit(1)
