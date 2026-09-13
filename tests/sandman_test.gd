extends Node
## 沙人（邪恶六人组）回归：数据 / BAM 加生命 / 溢出加生命 / 更难（免伤直到沙尘暴清完）/
## 更好 / 更快 / 更强 / 流沙（离开需 2 移动）/ 生命值 20 判负 / KO 特殊规则 / 威胁 BAM
var _fail := 0
func _check(n: String, ok: bool, d: String) -> void:
	if ok: print("PASS: " + n)
	else: _fail += 1; print("FAIL: " + n + " — " + d)

func _ready() -> void:
	Game.autopilot = true

	# ---------- 1. 数据 ----------
	var v: Dictionary = DB.villain("sandman")
	_check("沙人存在", not v.is_empty(), "")
	_check("生命 4/6/8", int(v["health"]["2"]) == 4 and int(v["health"]["3"]) == 6 and int(v["health"]["4"]) == 8, str(v["health"]))
	_check("12 张行动卡", v["actions"].size() == 12, "%d" % v["actions"].size())
	_check("6 张威胁卡", v["threats"].size() == 6, "%d" % v["threats"].size())
	var n_qs := 0
	var n_ss := 0
	var n_oc := 0
	var n_el := 0
	for t in v["threats"]:
		match String(t["name"]):
			"流沙": n_qs += 1
			"沙尘暴": n_ss += 1
			"章鱼博士": n_oc += 1
			"电光人": n_el += 1
	_check("2 流沙 / 2 沙尘暴 / 章鱼博士 / 电光人", n_qs == 2 and n_ss == 2 and n_oc == 1 and n_el == 1,
		"流沙%d 沙尘暴%d 章鱼%d 电光%d" % [n_qs, n_ss, n_oc, n_el])
	_check("沙尘暴用移动×3 清除", v["threats"][2].has("clear") and (v["threats"][2]["clear"] as Array).size() == 3, str(v["threats"][2].get("clear", [])))
	_check("邪恶计划 hp 轨道 20", String(v.get("plot_track", "")) == "hp" and int(v.get("fear_track_max", 0)) == 20,
		"%s/%d" % [String(v.get("plot_track", "")), int(v.get("fear_track_max", 0))])

	# ---------- 2. BAM：+2 生命，所在地点每个英雄 1 伤 ----------
	Game.setup("sandman", ["cap", "ironman"], "none", "base")
	Game.state["villain_pos"] = 0
	Game.state["villain_hp"] = 4
	Game.state["villain_hp_max"] = 4
	for hid in ["cap", "ironman"]:
		Game.state["heroes"][hid]["location"] = 0
		Game.state["heroes"][hid]["hand"] = [0, 1, 2, 3]
	await VillainRules.on_bam(Game, "sandman")
	_check("BAM：沙人获得 2 点生命值", int(Game.state["villain_hp"]) == 6, "hp=%d" % int(Game.state["villain_hp"]))
	_check("BAM：所在地点每个英雄各 1 伤", Game.state["heroes"]["cap"]["hand"].size() == 3 and Game.state["heroes"]["ironman"]["hand"].size() == 3,
		"cap=%d iron=%d" % [Game.state["heroes"]["cap"]["hand"].size(), Game.state["heroes"]["ironman"]["hand"].size()])
	_check("生命值可超过上限", int(Game.state["villain_hp"]) > int(Game.state["villain_hp_max"]),
		"%d/%d" % [int(Game.state["villain_hp"]), int(Game.state["villain_hp_max"])])

	# ---------- 3. 溢出：沙人获得 2 点生命值 ----------
	await VillainRules.on_overflow(Game, "sandman", "thug", 1)
	_check("溢出：沙人 +2 生命值", int(Game.state["villain_hp"]) == 8, "hp=%d" % int(Game.state["villain_hp"]))

	# ---------- 4. 更难：未清完沙尘暴前沙人不受伤害 ----------
	Game.setup("sandman", ["cap", "ironman"], "none", "base")
	Game.state["villain_pos"] = 3
	Game.state["missions_completed"] = 2
	Game.state["villain_hp"] = 6
	Game.state["villain_hp_max"] = 6
	await VillainRules.resolve_effect(Game, v["actions"][3]["effect"])
	_check("更难：已进入免伤状态", bool(Game.state.get("sandman_hard", false)), "未生效")
	await Game._perform_attack_at(3, "villain", "cap")
	_check("更难：攻击无效", int(Game.state["villain_hp"]) == 6, "hp=%d" % int(Game.state["villain_hp"]))
	# 清掉一张沙尘暴：仍免伤
	var ss_locs: Array = []
	for i in range(Game.LOCATION_COUNT):
		var t: Variant = Game.state["locations"][i]["threat"]
		if t != null and t["name"] == "沙尘暴":
			ss_locs.append(i)
	_check("开局有 2 张沙尘暴在场", ss_locs.size() == 2, "%d" % ss_locs.size())
	Game._clear_threat(int(ss_locs[0]))
	await Game._perform_attack_at(3, "villain", "cap")
	_check("更难：还有 1 张沙尘暴时仍免伤", int(Game.state["villain_hp"]) == 6 and bool(Game.state.get("sandman_hard", true)),
		"hp=%d hard=%s" % [int(Game.state["villain_hp"]), str(Game.state.get("sandman_hard", true))])
	Game._clear_threat(int(ss_locs[1]))
	_check("两张沙尘暴都清除后解除免伤", not bool(Game.state.get("sandman_hard", true)), "仍然免伤")
	await Game._perform_attack_at(3, "villain", "cap")
	_check("更难解除后攻击正常扣血", int(Game.state["villain_hp"]) == 5, "hp=%d" % int(Game.state["villain_hp"]))

	# ---------- 5. 更好 / 更快 ----------
	Game.setup("sandman", ["cap", "ironman"], "none", "base")
	Game.state["villain_pos"] = 2
	for hid in ["cap", "ironman"]:
		Game.state["heroes"][hid]["hand"] = [0, 1, 2, 3, 4]
	Game.state["heroes"]["cap"]["location"] = (2 + 1) % Game.LOCATION_COUNT
	Game.state["heroes"]["ironman"]["location"] = (2 - 1 + Game.LOCATION_COUNT) % Game.LOCATION_COUNT
	await VillainRules.resolve_effect(Game, v["actions"][4]["effect"])
	_check("更好：两个相邻地点的英雄各受 1 伤", Game.state["heroes"]["cap"]["hand"].size() == 4 and Game.state["heroes"]["ironman"]["hand"].size() == 4,
		"cap=%d iron=%d" % [Game.state["heroes"]["cap"]["hand"].size(), Game.state["heroes"]["ironman"]["hand"].size()])
	Game.state["heroes"]["cap"]["location"] = 2
	await VillainRules.resolve_effect(Game, v["actions"][5]["effect"])
	_check("更快：沙人所在地点英雄受 1 伤", Game.state["heroes"]["cap"]["hand"].size() == 3,
		"cap=%d" % Game.state["heroes"]["cap"]["hand"].size())

	# ---------- 6. 更强：丢弃所在地点威胁卡上的指示物，每个每英雄 1 伤 ----------
	Game.setup("sandman", ["cap", "ironman"], "none", "base")
	Game.state["villain_pos"] = 1
	for hid in ["cap", "ironman"]:
		Game.state["heroes"][hid]["hand"] = [0, 1, 2, 3, 4, 5, 6]
	Game.state["locations"][1]["threat"] = {"name": "沙尘暴", "text": "", "hp": 0, "heroic_tokens": 2, "arrival": false, "bam": false, "constant": true, "clear": ["move", "move", "move"], "clear_progress": []}
	await VillainRules.resolve_effect(Game, v["actions"][6]["effect"])
	_check("更强：威胁卡上的 2 个指示物被丢弃", int(Game.state["locations"][1]["threat"]["heroic_tokens"]) == 0,
		"tokens=%d" % int(Game.state["locations"][1]["threat"]["heroic_tokens"]))
	_check("更强：每个英雄各受 2 伤", Game.state["heroes"]["cap"]["hand"].size() == 5 and Game.state["heroes"]["ironman"]["hand"].size() == 5,
		"cap=%d iron=%d" % [Game.state["heroes"]["cap"]["hand"].size(), Game.state["heroes"]["ironman"]["hand"].size()])

	# ---------- 7. 流沙：离开该地点需要 2 个移动行动 ----------
	Game.setup("sandman", ["cap", "ironman"], "none", "base")
	Game.state["current_hero"] = 0
	Game.state["phase"] = "hero_actions"
	Game.state["locations"][2]["threat"] = {"name": "流沙", "text": "", "hp": 0, "heroic_tokens": 0, "arrival": false, "bam": false, "constant": true}
	Game.state["locations"][2]["civ"] = 0
	Game.state["locations"][2]["thug"] = 0
	Game.state["heroes"]["cap"]["location"] = 2
	# 模拟"只用掉最后一个移动行动"：消耗后场上已无移动可用（还剩 1 个才是 2 个移动）
	Game.state["action_symbols"] = []
	Game.state["heroes"]["cap"]["tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
	await Game._execute_move("cap", "move")
	_check("流沙：只有 1 个移动时无法离开（原地）", int(Game.state["heroes"]["cap"]["location"]) == 2,
		"loc=%d" % int(Game.state["heroes"]["cap"]["location"]))
	# 对照：没有流沙时可以移动
	Game.state["locations"][2]["threat"] = null
	Game.state["action_symbols"] = ["move"]
	await Game._execute_move("cap", "move")
	_check("对照：无流沙时可正常移动离开", int(Game.state["heroes"]["cap"]["location"]) != 2,
		"loc=%d" % int(Game.state["heroes"]["cap"]["location"]))

	# ---------- 8. 邪恶计划：生命值 20 → 失败 ----------
	Game.setup("sandman", ["cap", "ironman"], "none", "base")
	Game.state["villain_hp"] = 20
	var lost: bool = Game._check_lose()
	_check("生命值达到 20 → 英雄失败", lost and Game.state["phase"] == "game_over",
		"lost=%s phase=%s" % [str(lost), String(Game.state["phase"])])

	# ---------- 9. KO 特殊规则：不触发 BAM，改打另一张行动卡 ----------
	Game.setup("sandman", ["cap", "ironman"], "none", "base")
	Game.state["extra_villain_card"] = 0
	Game.state["heroes"]["cap"]["hand"] = [0, 1]
	await Game._ko_hero("cap")
	_check("KO：沙人不触发 BAM，改打另一张行动卡", int(Game.state["extra_villain_card"]) == 1 and Game.state["phase"] != "game_over",
		"extra=%d" % int(Game.state["extra_villain_card"]))

	# ---------- 10. 威胁 BAM：章鱼博士 / 电光人 ----------
	Game.setup("sandman", ["cap", "ironman"], "none", "base")
	for i in range(Game.LOCATION_COUNT):
		Game.state["locations"][i]["threat"] = null
	for hid in ["cap", "ironman"]:
		Game.state["heroes"][hid]["hand"] = [0, 1, 2, 3, 4]
		Game.state["heroes"][hid]["location"] = 5
	Game.state["locations"][0]["threat"] = {"name": "章鱼博士", "text": "", "hp": 4, "henchman_hp": 4, "heroic_tokens": 0, "arrival": false, "bam": true, "constant": false}
	Game.state["heroes"]["cap"]["location"] = 0
	Game.state["heroes"]["ironman"]["location"] = 5
	await Game._trigger_all_threat_bam()
	_check("章鱼博士威胁 BAM：该地点 1 名英雄 1 伤", Game.state["heroes"]["cap"]["hand"].size() == 4,
		"cap=%d" % Game.state["heroes"]["cap"]["hand"].size())
	# 电光人威胁：该地点有英雄 → 该地点每英雄 1 伤
	Game.state["locations"][0]["threat"] = {"name": "电光人", "text": "", "hp": 4, "henchman_hp": 4, "heroic_tokens": 0, "arrival": false, "bam": true, "constant": false}
	Game.state["heroes"]["cap"]["location"] = 0
	Game.state["heroes"]["ironman"]["location"] = 0
	for hid in ["cap", "ironman"]:
		Game.state["heroes"][hid]["hand"] = [0, 1, 2, 3, 4]
	await Game._trigger_all_threat_bam()
	_check("电光人威胁 BAM：该地点每英雄 1 伤", Game.state["heroes"]["cap"]["hand"].size() == 4 and Game.state["heroes"]["ironman"]["hand"].size() == 4,
		"cap=%d iron=%d" % [Game.state["heroes"]["cap"]["hand"].size(), Game.state["heroes"]["ironman"]["hand"].size()])
	# 该地点无英雄 → 相邻地点英雄 1 伤
	Game.state["heroes"]["cap"]["location"] = 5
	Game.state["heroes"]["ironman"]["location"] = (0 + 1) % Game.LOCATION_COUNT
	for hid in ["cap", "ironman"]:
		Game.state["heroes"][hid]["hand"] = [0, 1, 2, 3, 4]
	await Game._trigger_all_threat_bam()
	_check("电光人威胁 BAM：无英雄时相邻地点英雄 1 伤", Game.state["heroes"]["ironman"]["hand"].size() == 4,
		"iron=%d" % Game.state["heroes"]["ironman"]["hand"].size())

	if _fail == 0:
		print("=== SANDMAN TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== SANDMAN FAILED (%d) ===" % _fail)
		get_tree().quit(1)
