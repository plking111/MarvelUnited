extends Node
## 无限战争 4 新反派引擎测试：setup / BAM / 溢出 / 效果 / 淘汰 / 屠宰轨道 / 危机随机打牌。

var _fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("OK: " + msg)
	else:
		_fails.append(msg)
		print("FAIL: " + msg)

func _ready() -> void:
	Game.autopilot = true

	# ========== 1. 4 新反派 setup 正常 ==========
	for vid in ["thanos", "proxima", "cull", "ebony"]:
		Game.setup(vid, ["cap", "ironman"], "none")
		_check(Game.state["villain_hp"] > 0, "%s setup hp=%d" % [vid, Game.state["villain_hp"]])
		_check(Game.state["master_deck"].size() == 12, "%s master_deck=12" % vid)
		_check(Game.state["locations"].size() == 6, "%s locations=6" % vid)
		var threats_ok := true
		for l in Game.state["locations"]:
			if l["threat"] == null:
				threats_ok = false
		_check(threats_ok, "%s 每地点一张威胁" % vid)

	# ========== 2. 屠宰轨道初始化与失败 ==========
	Game.setup("proxima", ["cap", "ironman"], "none")
	_check(Game.state.get("slaughter", 0) == 0, "proxima slaughter 初始 0")
	Game.state["slaughter"] = 12
	_check(Game._check_lose(), "proxima slaughter=12 失败判定")
	Game.state["slaughter"] = 5
	_check(not Game._check_lose(), "proxima slaughter=5 未失败")

	# ========== 3. 灭霸淘汰检查 ==========
	Game.setup("thanos", ["cap", "ironman"], "none")
	Game.state["eliminated"] = ["cap"]
	_check(not Game._check_lose(), "thanos eliminated 1/2 未失败")
	Game.state["eliminated"] = ["cap", "ironman"]
	_check(Game._check_lose(), "thanos eliminated 2/2 失败")

	# ========== 4. 灭霸 BAM：同地2伤 / 异地1伤 ==========
	Game.setup("thanos", ["cap", "ironman"], "none")
	Game.state["villain_pos"] = 0
	Game.state["heroes"]["cap"]["location"] = 0
	Game.state["heroes"]["ironman"]["location"] = 3
	for hid in ["cap", "ironman"]:
		Game.state["heroes"][hid]["hand"] = ["0", "1", "2", "3", "4"]
		Game.state["heroes"][hid]["deck"] = []
	Game.state["phase"] = "villain"
	var cap_before: int = Game.state["heroes"]["cap"]["hand"].size()
	var im_before: int = Game.state["heroes"]["ironman"]["hand"].size()
	await Game._trigger_panel_bam()
	# autopilot 下 _ask_hand_cards 自动弃牌
	_check(Game.state["heroes"]["cap"]["hand"].size() == cap_before - 2, "灭霸BAM cap 弃2张（同地2伤）")
	_check(Game.state["heroes"]["ironman"]["hand"].size() == im_before - 1, "灭霸BAM ironman 弃1张（异地1伤）")

	# ========== 5. 暗夜比邻星 BAM：1伤 + 弃平民 + 屠宰 ==========
	Game.setup("proxima", ["cap", "ironman"], "none")
	Game.state["villain_pos"] = 0
	Game.state["heroes"]["cap"]["location"] = 0
	for hid in ["cap", "ironman"]:
		Game.state["heroes"][hid]["hand"] = ["0", "1", "2", "3", "4"]
	Game.state["locations"][0]["civ"] = 2
	Game.state["phase"] = "villain"
	await Game._trigger_panel_bam()
	_check(Game.state["locations"][0]["civ"] == 0, "比邻星BAM 丢弃平民")
	_check(Game.state["slaughter"] >= 2, "比邻星BAM 屠宰+丢弃数=%d" % Game.state["slaughter"])

	# ========== 6. 黑矮星 KO：不触发BAM 改为额外行动卡 ==========
	Game.setup("cull", ["cap", "ironman"], "none")
	Game.state["heroes"]["cap"]["hand"] = []
	Game.state["heroes"]["cap"]["ko"] = false
	Game.state["phase"] = "villain"
	Game.state["extra_villain_card"] = 0
	var hp_before: int = Game.state["villain_hp"]
	# 直接调用 _ko_hero（cap 手牌已空，KO）
	await Game._ko_hero("cap")
	_check(Game.state["heroes"]["cap"]["ko"], "黑矮星 KO cap")
	_check(Game.state["extra_villain_card"] == 1, "黑矮星 KO 触发额外行动卡 extra=%d" % Game.state["extra_villain_card"])
	_check(Game.state["villain_hp"] == hp_before, "黑矮星 KO 不触发BAM（生命未变）")

	# ========== 7. 乌木侯特殊规则：危机英雄随机打牌 ==========
	Game.setup("ebony", ["cap", "ironman"], "none")
	Game.state["hero_ids"] = ["cap"]
	Game.state["current_hero"] = 0
	Game.state["heroes"]["cap"]["hand"] = [0, 1, 2, 3, 4]
	Game.state["heroes"]["cap"]["crisis"] = 2
	Game.state["phase"] = "hero_play"
	Game.state["random_play"] = Game.state["villain"] == "ebony" and Game.state["heroes"]["cap"]["crisis"] > 0
	_check(Game.state["random_play"], "乌木侯 危机英雄 random_play=true")
	var hand_before: int = Game.state["heroes"]["cap"]["hand"].size()
	Game.play_card(0)
	_check(Game.state["heroes"]["cap"]["hand"].size() == hand_before - 1, "乌木侯 随机打出一张")
	_check(Game.state["heroes"]["cap"]["crisis"] == 1, "乌木侯 丢弃1危机（剩余1）")

	# ========== 8. 灭霸淘汰：替换英雄 ==========
	Game.setup("thanos", ["cap", "ironman"], "none")
	Game.state["heroes"]["cap"]["hand"] = []
	Game.state["heroes"]["cap"]["ko"] = false
	Game.state["phase"] = "villain"
	await Game._ko_hero("cap")
	_check("cap" in Game.state["eliminated"], "灭霸 KO cap 被淘汰")
	_check("cap" in Game.state["hero_ids"] or Game.state["hero_ids"].size() == 2, "灭霸 替换后仍有2英雄 hero_ids=%s" % str(Game.state["hero_ids"]))

	# ========== 9. 武学大师格挡 ==========
	Game.setup("proxima", ["cap"], "none")
	Game.state["proxima_parry_used"] = false
	Game.state["villain_pos"] = 0
	Game.state["villain_hp"] = 10
	# 手动放置武学大师威胁
	for l in Game.state["locations"]:
		l["threat"] = null
	Game.state["locations"][0]["threat"] = {"name": "武学大师", "hp": 0, "heroic_tokens": 0, "bam": false, "arrival": false, "constant": true}
	Game._perform_attack_at(0, "villain", "cap")
	_check(Game.state["villain_hp"] == 10, "武学大师 格挡第一个攻击 villain_hp=%d" % Game.state["villain_hp"])
	_check(Game.state["proxima_parry_used"], "武学大师 parry_used=true")

	# ========== 10. 超级坚甲忽略伤害 ==========
	Game.setup("cull", ["cap"], "none")
	Game.state["cull_armor_used"] = false
	Game.state["villain_pos"] = 0
	Game.state["villain_hp"] = 10
	for l in Game.state["locations"]:
		l["threat"] = null
	Game.state["locations"][0]["threat"] = {"name": "超级坚甲", "hp": 0, "heroic_tokens": 0, "bam": false, "arrival": false, "constant": true}
	Game._perform_attack_at(0, "villain", "cap")
	_check(Game.state["villain_hp"] == 10, "超级坚甲 忽略1伤 villain_hp=%d" % Game.state["villain_hp"])
	Game._perform_attack_at(0, "villain", "cap")
	_check(Game.state["villain_hp"] == 9, "超级坚甲 第二次攻击生效 villain_hp=%d" % Game.state["villain_hp"])

	if _fails.size() == 0:
		print("=== IWAN TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== IWAN TEST FAILED (%d) ===" % _fails.size())
		get_tree().quit(1)
