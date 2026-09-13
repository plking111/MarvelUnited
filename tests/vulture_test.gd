extends Node
## 秃鹫（邪恶六人组）回归：数据 + 开局战利品 + BAM/溢出收战利品 + 电磁飞翼 + 战利品失败
var _fail := 0
func _check(n: String, ok: bool, d: String) -> void:
	if ok: print("PASS: " + n)
	else: _fail += 1; print("FAIL: " + n + " — " + d)

func _ready() -> void:
	Game.autopilot = false
	# 让"是否受2点伤害阻止BAM"默认回答"否"（走正常BAM流程）
	Events.prompt_confirm.connect(func(_t: String, cb: Callable) -> void:
		await get_tree().process_frame
		cb.call(false))
	# 选择类弹窗（选英雄受伤）默认选第一个
	Events.prompt_choice.connect(func(_opts: Array, _t: String, cb: Callable) -> void:
		await get_tree().process_frame
		cb.call(0))
	Events.prompt_action.connect(func(_rows: Array, _t: String, cb: Callable) -> void:
		await get_tree().process_frame
		cb.call(0))
	Events.prompt_hand_card.connect(func(cb: Callable, _t: String, hid: String, _c: int) -> void:
		await get_tree().process_frame
		cb.call([0] if Game.state["heroes"][hid]["hand"].size() > 0 else []))

	# ---------- 1. 数据 ----------
	var v: Dictionary = DB.villain("vulture")
	_check("秃鹫存在", not v.is_empty(), "")
	_check("生命 3/6/8", int(v["health"]["2"]) == 3 and int(v["health"]["3"]) == 6 and int(v["health"]["4"]) == 8, str(v["health"]))
	_check("12 张行动卡", v["actions"].size() == 12, "实际 %d" % v["actions"].size())
	_check("6 张威胁卡", v["threats"].size() == 6, "实际 %d" % v["threats"].size())
	_check("战利品轨道", String(v.get("plot_track", "")) == "loot", String(v.get("plot_track", "")))

	# ---------- 2. 开局：每地点 3 个战利品 ----------
	Game.setup("vulture", ["cap", "ironman", "hulk"], "none", "base")
	var all3 := true
	for l in Game.state["locations"]:
		if int(l["crisis"]) != 3:
			all3 = false
	_check("开局每地点3个战利品", all3, str(Game.state["locations"].map(func(l): return int(l["crisis"]))))
	_check("战利品计数从0开始", int(Game.state["vulture_loot"]) == 0, str(Game.state.get("vulture_loot", -1)))

	# ---------- 3. BAM：收战利品 + 英雄移到对面 ----------
	var vpos: int = Game.state["villain_pos"]
	var opp: int = (vpos + 3) % Game.LOCATION_COUNT
	Game.state["heroes"]["cap"]["location"] = vpos
	Game.state["heroes"]["cap"]["ko"] = false
	var loot_before: int = int(Game.state["vulture_loot"])
	var crisis_before: int = int(Game.state["locations"][vpos]["crisis"])
	await VillainRules.on_bam(Game, "vulture")
	_check("BAM 收走1个战利品", int(Game.state["vulture_loot"]) == loot_before + 1, "%d->%d" % [loot_before, int(Game.state["vulture_loot"])])
	_check("BAM 该地点战利品-1", int(Game.state["locations"][vpos]["crisis"]) == crisis_before - 1,
		"%d->%d" % [crisis_before, int(Game.state["locations"][vpos]["crisis"])])
	_check("BAM 英雄被移到对面", int(Game.state["heroes"]["cap"]["location"]) == opp,
		"%d->%d (对面=%d)" % [vpos, int(Game.state["heroes"]["cap"]["location"]), opp])

	# ---------- 4. 溢出：收战利品 ----------
	var l0: Dictionary = Game.state["locations"][0]
	var lb: int = int(Game.state["vulture_loot"])
	var cb2: int = int(l0["crisis"])
	await VillainRules.on_overflow(Game, "vulture", "thug", 0)
	_check("溢出收走1个战利品", int(Game.state["vulture_loot"]) == lb + 1 and int(l0["crisis"]) == cb2 - 1,
		"loot %d->%d, crisis %d->%d" % [lb, int(Game.state["vulture_loot"]), cb2, int(l0["crisis"])])

	# ---------- 5. 威胁 BAM：沙人 / 克莱文 / 手雷轰炸到达 ----------
	# 先复位：避免前面几步累计的战利品 + KO 连锁触发的 BAM 让游戏提前判负（判负后威胁 BAM 会按新规则中断）
	Game.state["vulture_loot"] = 0
	Game.state["phase"] = "hero_actions"
	for _hh in Game.state["hero_ids"]:
		Game.state["heroes"][_hh]["ko"] = false
		Game.state["heroes"][_hh]["hand"] = [0, 1, 2, 3, 4, 5, 6]
	var tloc := 2
	Game.state["locations"][tloc]["threat"] = {"name": "克莱文", "text": "", "hp": 4, "heroic_tokens": 0, "arrival": false, "bam": true, "constant": false}
	Game.state["heroes"]["ironman"]["location"] = tloc
	Game.state["heroes"]["ironman"]["hand"] = [0, 1, 2, 3, 4]
	var hp_before: int = Game.state["heroes"]["ironman"]["hand"].size()
	await Game._trigger_all_threat_bam()
	_check("克莱文 BAM 造成2点伤害(弃2张)", Game.state["heroes"]["ironman"]["hand"].size() <= hp_before,
		"hand %d->%d" % [hp_before, Game.state["heroes"]["ironman"]["hand"].size()])
	var aloc := 3
	Game.state["locations"][aloc]["threat"] = {"name": "手雷轰炸", "text": "", "hp": 0, "heroic_tokens": 0, "arrival": true, "bam": false, "constant": false, "arrival_triggered": false}
	Game.state["heroes"]["hulk"]["location"] = aloc
	Game.state["heroes"]["hulk"]["hand"] = [0, 1, 2, 3, 4]
	var hh_before: int = Game.state["heroes"]["hulk"]["hand"].size()
	await Game._trigger_threat_arrival(aloc)
	_check("手雷轰炸到达扣手牌", Game.state["heroes"]["hulk"]["hand"].size() < hh_before,
		"hand %d->%d" % [hh_before, Game.state["heroes"]["hulk"]["hand"].size()])
	# 沙人：该地点无英雄时收战利品
	var sloc := 4
	Game.state["locations"][sloc]["threat"] = {"name": "沙人", "text": "", "hp": 4, "heroic_tokens": 0, "arrival": false, "bam": true, "constant": false}
	for hid in Game.state["hero_ids"]:
		Game.state["heroes"][hid]["location"] = (sloc + 2) % Game.LOCATION_COUNT
	Game.state["locations"][sloc]["crisis"] = 2
	var lb2: int = int(Game.state["vulture_loot"])
	Game.state["vulture_loot"] = 0     # 复位后再测"沙人无人收战利品"，避免累积到阈值中断
	await Game._trigger_all_threat_bam()
	_check("沙人无人时收战利品", int(Game.state["vulture_loot"]) >= 1, "loot=%d" % int(Game.state["vulture_loot"]))

	# ---------- 6. 电磁飞翼：受击只扣1并移到对面 ----------
	Game.state["vulture_loot"] = 0
	Game.state["phase"] = "hero_actions"
	Game.state["heroes"]["cap"]["ko"] = false
	Game.state["heroes"]["cap"]["hand"] = [0, 1, 2, 3, 4, 5]
	var wloc := 5
	Game.state["locations"][wloc]["threat"] = {"name": "电磁飞翼·秃鹫", "text": "", "hp": 0, "heroic_tokens": 0, "arrival": false, "bam": false, "constant": true}
	Game.state["villain_pos"] = wloc
	Game.state["missions_completed"] = 2
	Game.state["villain_hp"] = 6
	await Game._perform_attack_at(wloc, "villain", "cap")
	_check("电磁飞翼只扣1点", int(Game.state["villain_hp"]) == 5, "hp=%d" % int(Game.state["villain_hp"]))
	_check("电磁飞翼移到对面", int(Game.state["villain_pos"]) == (wloc + 3) % Game.LOCATION_COUNT,
		"pos=%d" % int(Game.state["villain_pos"]))

	# ---------- 7. 战利品收满 → 英雄失败 ----------
	Game.state["phase"] = "hero_actions"
	Game.state["vulture_loot"] = 6           # 3人局阈值 7
	Game.state["locations"][0]["crisis"] = 1
	await VillainRules.on_overflow(Game, "vulture", "thug", 0)
	_check("收满7个战利品即失败", Game.state["phase"] == "game_over" and String(Game.state.get("lose_reason", "")).contains("战利品"),
		"loot=%d phase=%s reason=%s" % [int(Game.state["vulture_loot"]), Game.state["phase"], String(Game.state.get("lose_reason", ""))])

	# ---------- 8. 抢劫计划（行动卡 1-4）：第一张不结算，之后每个无英雄地点收 1 战利品 ----------
	Game.setup("vulture", ["cap", "ironman", "hulk"], "none", "base")
	var vd: Dictionary = DB.villain("vulture")
	var n_heist := 0
	for ci in range(4):
		var e: Variant = vd["actions"][ci].get("effect", null)
		if e != null and String(e.get("type", "")) == "vulture_heist":
			n_heist += 1
	_check("行动卡 1-4 都是抢劫计划", n_heist == 4, "%d" % n_heist)
	_game_over_reset()
	# 让 0 号地点有英雄、其余地点无人
	for hid in Game.state["hero_ids"]:
		Game.state["heroes"][hid]["location"] = 0
	Game.state["story"] = [{"type": "villain", "villain": "vulture", "idx": 0, "move": "移动3"}]
	var loot0: int = int(Game.state["vulture_loot"])
	var crisis0: int = int(Game.state["locations"][0]["crisis"])
	var crisis1: int = int(Game.state["locations"][1]["crisis"])
	await VillainRules.resolve_effect(Game, vd["actions"][0]["effect"])
	_check("第一张抢劫计划不结算", int(Game.state["vulture_loot"]) == loot0,
		"loot %d -> %d" % [loot0, int(Game.state["vulture_loot"])])
	# 故事情节里再放一张抢劫计划 → 这次要结算
	Game.state["story"].append({"type": "villain", "villain": "vulture", "idx": 2, "move": "移动3"})
	await VillainRules.resolve_effect(Game, vd["actions"][2]["effect"])
	var empty_n: int = Game.LOCATION_COUNT - 1     # 除 0 号地点外都无英雄
	_check("第二张抢劫计划：每个无英雄地点收 1 战利品",
		int(Game.state["vulture_loot"]) == loot0 + empty_n,
		"loot %d -> %d（期望 +%d）" % [loot0, int(Game.state["vulture_loot"]), empty_n])
	_check("有英雄的地点不被收走", int(Game.state["locations"][0]["crisis"]) == crisis0,
		"crisis=%d" % int(Game.state["locations"][0]["crisis"]))
	_check("无英雄的地点各少 1 个", int(Game.state["locations"][1]["crisis"]) == crisis1 - 1,
		"crisis %d -> %d" % [crisis1, int(Game.state["locations"][1]["crisis"])])

	if _fail == 0:
		print("=== VULTURE TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== VULTURE FAILED (%d) ===" % _fail)
		get_tree().quit(1)

## 把上一场景的"失败"状态清干净（抢劫计划场景需要继续游戏）
func _game_over_reset() -> void:
	Game.state["phase"] = "hero_actions"
	Game.state["lose_reason"] = ""
	Game.state["vulture_loot"] = 0
	for l in Game.state["locations"]:
		l["crisis"] = 3
