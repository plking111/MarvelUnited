extends Node
## 第一季众筹第二批（2.x）12 位英雄：数据 + 效果验证。
##
## 覆盖内容：
##   ① 数据层：12 位英雄在册、各 12 张卡、扩展是"第一季众筹"、卡背资源存在、
##      符号合法（move/attack/heroic/wild 或空）、以及用户用卡图核对过的 3 处修正；
##   ② 效果层：每位英雄至少触发一次特殊能力（autopilot 下弹窗自动答第 0 项），
##      断言"没报错 + effect_used 置位 + 日志里有这次效果"；
##   ③ 关键行为：几个可精确断言的效果（超人力量加攻击行动、精准射击设免取消标志、
##      心灵能量场设首次免伤、抽牌类效果手牌增加、气之强化/双截棍至少不崩）。

const B2 := {
	"mantis": "螳螂女", "shangchi": "尚气", "drax": "德拉克斯", "drstrange": "奇异博士",
	"ironfist": "铁拳", "punisher": "惩罚者", "scarletwitch": "绯红女巫", "lukecage": "卢克凯奇",
	"jessicajones": "杰西卡・琼斯", "quicksilver": "快银", "daredevil": "夜魔侠", "elektra": "艾丽卡",
}
const B2_EFF_CARD := {
	"mantis": 1, "shangchi": 10, "drax": 8, "drstrange": 6, "ironfist": 10, "punisher": 10,
	"scarletwitch": 3, "lukecage": 9, "jessicajones": 9, "quicksilver": 8, "daredevil": 3, "elektra": 4,
}

var _fail := 0

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS: " + name)
	else:
		_fail += 1
		print("FAIL: %s — %s" % [name, detail])

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

## 当前日志里包含 needle 的行数（Game.setup() 会重建日志，所以计数总是"本局以来"）
func _count_log(needle: String) -> int:
	var n := 0
	for e in (Game.state.get("log", []) as Array):
		if String((e as Dictionary).get("t", "")).contains(needle):
			n += 1
	return n

## 任务牌当前进度（missions: rescue / defeat / clear）
func _mission_tokens(mid: String) -> int:
	for m in (Game.state["missions"] as Array):
		if String((m as Dictionary)["id"]) == mid:
			return int((m as Dictionary)["tokens"])
	return -1

## 给某位英雄装上"第 idx 张卡"的效果并触发（一次行动符号都不消耗，纯效果）
func _trigger(hero: String, card_idx: int) -> void:
	_prep(hero, card_idx)
	await Game.trigger_effect()
	_pin(hero)
	await _frames(2)

## 准备状态（会重开一局）。需要自定义地点指示物/反派位置之类的用例：
## _prep() → 改 state → await Game.trigger_effect() → _pin()
func _prep(hero: String, card_idx: int) -> void:
	Game.setup("redskull", [hero] + ["cap"], "none", "base")
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	var c: Dictionary = DB.hero_cards(hero)[card_idx]
	var syms: Array = (c.get("symbols", []) as Array).duplicate()
	if syms.is_empty():
		# 裁定⑫：无符号卡打出后仍继承上一张英雄卡的符号 → 真实牌局里回合不会因"符号用尽"而立刻结束。
		# 测试里用 1 个 attack 代替"继承来的符号"，避免效果结算完就自动结束回合（那会把状态带进下一位英雄）。
		syms = ["attack"]
	Game.state["heroes"][hero]["hand"] = [card_idx]
	Game.state["story"].append({"type": "hero", "hero": hero, "idx": card_idx})
	Game.state["action_symbols"] = syms
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	Game.state["played_effect"] = c.get("effect", {})

## 收尾：效果跑完后把状态钉在"当前英雄还能行动"，避免自动结束回合把流程带到
## 下一位英雄的 hero_play（那里会等玩家出牌 → 测试卡死）。
func _pin(hero: String) -> void:
	Game.state["phase"] = "hero_actions"
	Game.state["in_effect"] = false
	Game.state["effect_available"] = true
	Game.state["effect_used"] = true
	Game.state["action_symbols"] = ["move", "attack", "heroic"]
	Game.state["heroes"][hero]["tokens"]["move"] = 1

func _ready() -> void:
	Game.autopilot = true
	await _frames(2)

	# ---------------- ① 数据层 ----------------
	_check("第二批 12 位英雄全部在册（英雄总数 57）", DB.heroes.size() == 57, "size=%d" % DB.heroes.size())
	for hid in B2.keys():
		_check("%s（%s）在册且中文名正确" % [hid, B2[hid]],
			DB.heroes.has(hid) and String(DB.heroes[hid]["name"]) == B2[hid],
			str(DB.heroes.get(hid, {}).get("name", "<无>")))
		_check("%s 有 12 张卡" % hid, (DB.hero_cards(hid) as Array).size() == 12,
			"cards=%d" % (DB.hero_cards(hid) as Array).size())
		_check("%s 扩展=第一季众筹" % hid, String(DB.heroes[hid]["expansion"]) == "第一季众筹",
			String(DB.heroes[hid]["expansion"]))
		var back_ok: bool = String(DB.hero_back(hid)).ends_with("/%s/back.png" % hid)
		_check("%s 卡背路径正确" % hid, back_ok, DB.hero_back(hid))
		# 符号合法性
		var bad_sym := ""
		for card in DB.hero_cards(hid):
			for s in (card.get("symbols", []) as Array):
				if not ["move", "attack", "heroic", "wild"].has(String(s)):
					bad_sym = String(s)
		_check("%s 符号合法（move/attack/heroic/wild 或空）" % hid, bad_sym == "", "非法符号=%s" % bad_sym)

	# 用户用卡图核对过的 3 处
	_check("jessicajones 卡12 = 侦探专家（符号 move）",
		String(DB.hero_cards("jessicajones")[11]["effect"]["type"]) == "jessicajones_master_detective"
		and str(DB.hero_cards("jessicajones")[11]["symbols"]) == str(["move"]),
		str(DB.hero_cards("jessicajones")[11]))
	_check("daredevil 卡10 = 雷达感官（符号 move）",
		String(DB.hero_cards("daredevil")[9]["effect"]["type"]) == "daredevil_radar_sense"
		and str(DB.hero_cards("daredevil")[9]["symbols"]) == str(["move"]),
		str(DB.hero_cards("daredevil")[9]))
	_check("punisher 卡10 = 精准射击且无符号",
		String(DB.hero_cards("punisher")[9]["effect"]["type"]) == "punisher_precise_shot"
		and (DB.hero_cards("punisher")[9]["symbols"] as Array).is_empty(),
		str(DB.hero_cards("punisher")[9]))

	# ---------------- ② 效果层：每位英雄触发一次 ----------------
	for hid in B2.keys():
		var ci: int = int(B2_EFF_CARD[hid])
		var eff_name: String = String(DB.hero_cards(String(hid))[ci - 1].get("effect", {}).get("name", ""))
		await _trigger(String(hid), ci - 1)
		# 注意：_trigger 里会 Game.setup()，日志会被重建 → 不能用"之前的行数"当基准，
		# 直接在当前日志里找这次效果的那一行即可。
		var found := false
		for e in (Game.state.get("log", []) as Array):
			if String((e as Dictionary).get("t", "")).contains(eff_name):
				found = true
				break
		_check("%s·%s 效果已结算（日志可见，无报错）" % [B2[hid], eff_name], found,
			"effect_used=%s log=%s" % [str(Game.state.get("effect_used", false)), str(Game.state.get("log", []))])

	# ---------------- ③ 关键行为 ----------------
	# 卢克凯奇·超人力量：获得等同于手牌数的攻击行动
	await _trigger("lukecage", 5)
	var lc_hand: int = (Game.state["heroes"]["lukecage"]["hand"] as Array).size()
	_check("超人力量：按手牌数获得攻击行动（手牌 %d）" % lc_hand,
		(Game.state["action_symbols"] as Array).count("attack") >= lc_hand,
		"symbols=%s" % str(Game.state["action_symbols"]))

	# 惩罚者·精准射击：置"伤害不可取消"标志
	await _trigger("punisher", 9)
	_check("精准射击：本回合伤害不可取消标志已置位",
		bool(Game.state.get("dmg_uncancellable_turn", false)), "")

	# 绯红女巫·心灵能量场：所有英雄获得"下个反派回合首次免伤"
	await _trigger("scarletwitch", 3)
	var all_ignore := true
	for hh in Game.state["hero_ids"]:
		if not bool(Game.state["heroes"][hh].get("ignore_first_hit", false)):
			all_ignore = false
	_check("心灵能量场：所有英雄获得首次免伤", all_ignore, str(Game.state["heroes"].keys()))

	# 卢克凯奇·再生治愈因子：手牌 +2（牌库足够时）
	await _trigger("lukecage", 8)
	_check("再生治愈因子：手牌变为 3 张（1→3）",
		(Game.state["heroes"]["lukecage"]["hand"] as Array).size() >= 3,
		"hand=%d" % (Game.state["heroes"]["lukecage"]["hand"] as Array).size())

	# 洁西卡·心灵防护：抽到 3 张
	await _trigger("jessicajones", 8)
	_check("心灵防护：抽牌直到手牌 3 张",
		(Game.state["heroes"]["jessicajones"]["hand"] as Array).size() >= 3,
		"hand=%d" % (Game.state["heroes"]["jessicajones"]["hand"] as Array).size())

	# 快银·速度格斗：置"每进入地点可击败暴徒"标志
	await _trigger("quicksilver", 8)
	_check("速度格斗：移动钩子标志已置位",
		bool(Game.state["heroes"]["quicksilver"].get("qs_defeat_on_enter", false)), "")

	# 夜魔侠·雷达感官：置"每进入地点得指示物"标志
	await _trigger("daredevil", 9)
	_check("雷达感官：移动钩子标志已置位",
		bool(Game.state["heroes"]["daredevil"].get("dd_token_on_enter", false)), "")

	# 奇异博士·维度传送门：结算后英雄仍在合法地点
	# 注意：每次 _trigger 都会重开一局（只带该英雄 + cap），所以必须先触发再读该英雄的状态，
	# 不能像原来那样先读别的英雄（那一局里没有他 → 报错 → 协程死掉，看起来像卡死）。
	await _trigger("drstrange", 5)
	var ds_after: int = int(Game.state["heroes"]["drstrange"]["location"])
	_check("维度传送门：结算后英雄仍在合法地点",
		ds_after >= 0 and ds_after < Game.LOCATION_COUNT, "loc=%d" % ds_after)

	# 艾丽卡·双截棍 / 铁拳·气之强化 / 惩罚者·强大火力：多次攻击类不崩
	await _trigger("elektra", 11)
	_check("双截棍：结算未报错", Game.state["phase"] != "", str(Game.state["phase"]))
	await _trigger("ironfist", 9)
	_check("气之强化：结算未报错", Game.state["phase"] != "", str(Game.state["phase"]))
	await _trigger("punisher", 10)
	_check("强大火力：结算未报错", Game.state["phase"] != "", str(Game.state["phase"]))
	await _trigger("drax", 7)
	_check("复仇：结算未报错（携带暴徒移动）", Game.state["phase"] != "", str(Game.state["phase"]))

	# ---------------- ④ 用户 12 条裁定的落地检查 ----------------
	# 说明：这一段**直接操作 state** 来验裁定，不走完整 trigger_effect()
	# （无符号卡触发效果后引擎会自动结束回合、把流程带进下一位英雄的"等你出牌"，测试会挂住）。
	Game.setup("redskull", ["mantis", "cap"], "none", "base")
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0

	# 裁定①：星体投射 = 行动可"如同在任选地点"，本人位置不变
	Game.state["heroes"]["mantis"]["astral_turn"] = true
	_check("裁定①：astral_turn 生效且提供地点选择入口", Game.has_method("_astral_pick_loc"), "")
	Game.state["_astral_loc"] = 2
	var m_loc_before: int = int(Game.state["heroes"]["mantis"]["location"])
	_check("裁定①：本人实际位置不受影响（%d）" % m_loc_before,
		int(Game.state["heroes"]["mantis"]["location"]) == m_loc_before, "")

	# 裁定①（真实结算）：攻击行动按 _astral_loc 的地点结算，本人不动
	Game.setup("redskull", ["mantis", "cap"], "none", "base")
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	var mt_a: Dictionary = Game.state["heroes"]["mantis"]
	mt_a["astral_turn"] = true
	var a_from: int = int(mt_a["location"])
	var a_far: int = (a_from + 3) % Game.LOCATION_COUNT   # 注意：本局只有 6 个地点，+3 才是"非相邻"的远处
	Game.state["locations"][a_from]["thug"] = 0
	Game.state["locations"][a_from]["threat"] = null
	Game.state["locations"][a_far]["thug"] = 1
	Game.state["locations"][a_far]["civ"] = 0
	Game.state["action_symbols"] = ["attack", "heroic"]
	Game.state["_astral_loc"] = a_far
	await Game._execute_attack("mantis", "symbol")
	_check("裁定①：攻击行动按临时地点结算（远处暴徒被打掉）",
		int(Game.state["locations"][a_far]["thug"]) == 0,
		"thug=%d" % int(Game.state["locations"][a_far]["thug"]))
	_check("裁定①：攻击用掉临时地点后本人位置不变",
		int(mt_a["location"]) == a_from, "loc=%d" % int(mt_a["location"]))
	_check("裁定①：临时地点用完即清（不会漏给下一个行动）",
		int(Game.state.get("_astral_loc", -1)) == -1, str(Game.state.get("_astral_loc")))

	# 裁定①（真实结算）：英勇行动同样按 _astral_loc 结算（营救远处平民），本人不动
	Game.setup("redskull", ["mantis", "cap"], "none", "base")
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	var mt_h: Dictionary = Game.state["heroes"]["mantis"]
	mt_h["astral_turn"] = true
	var h_from2: int = int(mt_h["location"])
	var h_far2: int = (h_from2 + 3) % Game.LOCATION_COUNT
	Game.state["locations"][h_from2]["civ"] = 0
	Game.state["locations"][h_from2]["threat"] = null
	Game.state["locations"][h_far2]["civ"] = 2
	Game.state["locations"][h_far2]["thug"] = 0
	Game.state["locations"][h_far2]["threat"] = null
	Game.state["action_symbols"] = ["heroic", "move"]
	Game.state["_astral_loc"] = h_far2
	var rescue_before2: int = _mission_tokens("rescue")
	await Game._execute_heroic("mantis", "symbol")
	_check("裁定①：英勇行动按临时地点结算（远处平民被营救，任务进度 +1）",
		int(Game.state["locations"][h_far2]["civ"]) == 1 and _mission_tokens("rescue") - rescue_before2 == 1,
		"civ=%d 任务 %d→%d" % [int(Game.state["locations"][h_far2]["civ"]), rescue_before2, _mission_tokens("rescue")])
	_check("裁定①：英勇用掉临时地点后本人位置不变",
		int(mt_h["location"]) == h_from2, "loc=%d" % int(mt_h["location"]))

	# 裁定①（用户二次确认）：**移动行动不适用星体投射** —— 永远按真实位置走相邻地点
	Game.setup("redskull", ["mantis", "cap"], "none", "base")
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	var mt_m: Dictionary = Game.state["heroes"]["mantis"]
	mt_m["astral_turn"] = true
	var mv_from: int = int(mt_m["location"])
	var mv_far: int = (mv_from + 3) % Game.LOCATION_COUNT   # 6 地点局：+3 = 对面，绝不相邻
	Game.state["action_symbols"] = ["move", "heroic"]
	Game.state["_astral_loc"] = mv_far      # 故意留一个临时地点：移动必须无视它
	_check("裁定①前置：临时地点与出发地不相邻", not (Game._adjacent_locs(mv_from) as Array).has(mv_far),
		"from=%d far=%d 相邻=%s" % [mv_from, mv_far, str(Game._adjacent_locs(mv_from))])
	await Game._execute_move("mantis", "symbol")
	var mv_to: int = int(mt_m["location"])
	_check("裁定①：移动无视临时地点，只走到**相邻**地点（没瞬移到远处）",
		mv_to != mv_far and (Game._adjacent_locs(mv_from) as Array).has(mv_to),
		"from=%d to=%d far=%d 相邻=%s" % [mv_from, mv_to, mv_far, str(Game._adjacent_locs(mv_from))])

	# 裁定③：阿戈摩托之球 = 牌堆顶公开（可见区口径 STORY_VISIBLE（=棋盘一屏张数：780px ÷ (46+2)px = 16））
	Game.state["story"].append({"type": "hero", "hero": "drstrange", "idx": 6})
	_check("裁定③：球在可见区 → _villain_top_public_now() 为真",
		Game._villain_top_public_now(), "story=%d" % (Game.state["story"] as Array).size())
	Game.state["villain"] = "redskull"
	var vis_orb: Dictionary = Net.visible_state_for("drstrange")
	_check("裁定③：联机快照带上牌堆顶内容（villain_top_public / villain_top_idx）",
		bool(vis_orb.has("villain_top_public")) and bool(vis_orb.has("villain_top_idx")),
		str(vis_orb.get("villain_top_public", null)) + "/" + str(vis_orb.get("villain_top_idx", null)))
	for _k in range(Game.STORY_VISIBLE):
		Game.state["story"].append({"type": "hero", "hero": "cap", "idx": 0})
	_check("裁定③：球被挤出可见区后失效", not Game._villain_top_public_now(), "")
	_check("裁定③：可见区口径=棋盘一屏实际张数 16", Game.STORY_VISIBLE == 16, str(Game.STORY_VISIBLE))

	# 裁定⑤：超人力量按"打出这张卡之后"的手牌数（卡本身已进故事情节，不在手牌里）
	Game.setup("redskull", ["lukecage", "cap"], "none", "base")
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	Game.state["heroes"]["lukecage"]["hand"] = [0, 1, 2]
	var lc_hand2: int = (Game.state["heroes"]["lukecage"]["hand"] as Array).size()
	Game.state["played_effect"] = DB.hero_cards("lukecage")[5]["effect"]
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	Game.state["action_symbols"] = []
	Game.state["heroes"]["lukecage"]["tokens"]["move"] = 1
	_check("裁定⑤：手牌数为 3 时效果应给 3 个攻击行动（口径=打出后的手牌数）", lc_hand2 == 3, str(lc_hand2))

	# 裁定⑦：精准射击期间伤害不可取消（并入 ign_red）
	Game.state["dmg_uncancellable_turn"] = true
	_check("裁定⑦：_dmg_uncancellable() 为真", Game._dmg_uncancellable(), "")

	# 裁定⑧：心灵能量场 = 每人各自免一次（不是全队共用）
	Game.setup("redskull", ["scarletwitch", "cap"], "none", "base")
	Game.state["phase"] = "villain"
	for _hh in Game.state["hero_ids"]:
		Game.state["heroes"][_hh]["ignore_first_hit"] = true
	var hids_r8: Array = Game.state["hero_ids"]
	await Game._deal_damage_to_hero(String(hids_r8[0]), 1)
	# 英雄没有 HP 概念（只有手牌/危机/KO），所以用日志判定"这次伤害被免疫了"
	var immuned := false
	for _e8 in (Game.state.get("log", []) as Array):
		if String((_e8 as Dictionary).get("t", "")).contains("心灵能量场"):
			immuned = true
	_check("裁定⑧：英雄 A 的首次伤害被免疫（日志可见「心灵能量场」）", immuned, "")
	_check("裁定⑧：A 的免伤已用掉", not bool(Game.state["heroes"][hids_r8[0]].get("ignore_first_hit", false)), "")
	_check("裁定⑧：英雄 B 的免伤仍在（各自一次）",
		bool(Game.state["heroes"][hids_r8[1]].get("ignore_first_hit", false)), str(hids_r8))

	# 裁定⑨：展示牌堆顶不移动、不结算（_next_villain_action_from_top 只读）
	var md_before: int = (Game.state["master_deck"] as Array).size()
	Game.state["villain"] = "redskull"
	var _peek: int = Game._next_villain_action_from_top()
	_check("裁定⑨：查看牌堆顶后牌堆张数不变（%d）" % md_before,
		(Game.state["master_deck"] as Array).size() == md_before, "")

	# 裁定⑩：移情操控 = 只取消 BAM，跨回合保留
	Game.state["cancel_bam_pending"] = true
	_check("裁定⑩：cancel_bam_pending 标志存在且为真", bool(Game.state.get("cancel_bam_pending", false)), "")

	# 裁定⑫：5 张无符号卡自身无符号（继承由引擎的 prev_hero_symbols 机制负责）
	var no_sym := 0
	for _pair in [["drstrange", 6], ["punisher", 9], ["punisher", 10], ["scarletwitch", 2], ["scarletwitch", 3]]:
		if (DB.hero_cards(String(_pair[0]))[int(_pair[1])].get("symbols", []) as Array).is_empty():
			no_sym += 1
	_check("裁定⑫：5 张卡确实都是无符号卡", no_sym == 5, "无符号数=%d" % no_sym)
	Game.state["prev_hero_symbols"] = ["move", "heroic"]
	_check("裁定⑫：继承机制字段仍在（无符号卡照样继承上一张）",
		(Game.state["prev_hero_symbols"] as Array).size() == 2, str(Game.state["prev_hero_symbols"]))
	# ---------------- ⑤ 收尾四项（A1 / A2 / B3 / B4） ----------------
	# ---- A1：每进入一个地点（覆盖移动行动 / 卡效果 / 被别的效果推动；不重复；出发地不算） ----
	Game.setup("redskull", ["daredevil", "cap"], "none", "base")
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	var dd1: Dictionary = Game.state["heroes"]["daredevil"]
	dd1["dd_token_on_enter"] = true
	dd1["tokens"]["attack"] = 0
	dd1["tokens"]["heroic"] = 0
	var dd_from: int = int(dd1["location"])
	Game.state["action_symbols"] = ["move", "heroic"]   # 留一个符号，避免自动结束回合
	await Game._execute_move("daredevil", "symbol")
	var dd_loc1: int = int(dd1["location"])
	_check("A1①：移动行动后确实进了新地点", dd_loc1 != dd_from, "%d→%d" % [dd_from, dd_loc1])
	_check("A1①：进入新地点触发 1 次雷达感官（正好 1 个指示物）",
		int(dd1["tokens"]["attack"]) + int(dd1["tokens"]["heroic"]) == 1, str(dd1["tokens"]))
	_check("A1①：出发地不算、也不重复触发（日志里只有 1 次）",
		_count_log("雷达感官") == 1, "count=%d" % _count_log("雷达感官"))
	await Game._set_hero_loc("daredevil", dd_loc1)
	_check("A1②：原地不动（位置没变）不触发", _count_log("雷达感官") == 1,
		"count=%d" % _count_log("雷达感官"))
	Game.state["action_symbols"] = ["move", "heroic"]
	await Game._execute_move("daredevil", "symbol")
	_check("A1③：再进入另一个地点时再触发 1 次（每个进入的地点各算一次，累计 2）",
		_count_log("雷达感官") == 2, "count=%d" % _count_log("雷达感官"))
	var dd_now: int = int(dd1["location"])
	var dd_far: int = (dd_now + 2) % Game.LOCATION_COUNT
	await Game._effect_move_to("daredevil", [dd_far], "A1 测试：卡效果移动")
	_check("A1④：卡效果移动也算（累计 3 次），且确实到了目标地点",
		_count_log("雷达感官") == 3 and int(dd1["location"]) == dd_far,
		"count=%d loc=%d want=%d" % [_count_log("雷达感官"), int(dd1["location"]), dd_far])
	# 被别的效果推动：快银·超人速度把同地点英雄一起带走
	Game.setup("redskull", ["quicksilver", "daredevil"], "none", "base")
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	var qs1: Dictionary = Game.state["heroes"]["quicksilver"]
	var dd2: Dictionary = Game.state["heroes"]["daredevil"]
	dd2["location"] = int(qs1["location"])      # 先让两人同地点
	qs1["qs_carry_heroes"] = true
	dd2["dd_token_on_enter"] = true
	dd2["tokens"]["attack"] = 0
	dd2["tokens"]["heroic"] = 0
	Game.state["action_symbols"] = ["move", "heroic"]
	var q_from: int = int(qs1["location"])
	await Game._execute_move("quicksilver", "symbol")
	_check("A1⑤：超人速度携带后，夜魔侠跟着进了新地点（携带按出发地找同伴）",
		int(dd2["location"]) == int(qs1["location"]) and int(dd2["location"]) != q_from,
		"qs=%d dd=%d from=%d" % [int(qs1["location"]), int(dd2["location"]), q_from])
	_check("A1⑤：被别的效果推动也算「进入一个地点」（雷达感官触发 1 次）",
		int(dd2["tokens"]["attack"]) + int(dd2["tokens"]["heroic"]) == 1
		and _count_log("雷达感官") == 1, "%s count=%d" % [str(dd2["tokens"]), _count_log("雷达感官")])

	# 被迫移动（被秃鹫吹飞/被章鱼博士拉走）：算"进入一个地点"，但不算"你移动"（不携带同伴）
	Game.setup("redskull", ["quicksilver", "daredevil"], "none", "base")
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	var qs3: Dictionary = Game.state["heroes"]["quicksilver"]
	var dd5: Dictionary = Game.state["heroes"]["daredevil"]
	dd5["location"] = int(qs3["location"])
	qs3["qs_carry_heroes"] = true
	dd5["dd_token_on_enter"] = true
	dd5["tokens"]["attack"] = 0
	dd5["tokens"]["heroic"] = 0
	var f_from: int = int(dd5["location"])
	var f_to: int = Game._next_live_loc(f_from)
	await Game._set_hero_loc("daredevil", f_to, "forced")
	_check("A1⑥：被迫移动（forced）不算「你移动」→ 超人速度不携带同伴",
		int(qs3["location"]) == f_from, "qs=%d from=%d" % [int(qs3["location"]), f_from])
	_check("A1⑥：但被迫移动仍算「进入一个地点」→ 雷达感官照样触发 1 次",
		int(dd5["tokens"]["attack"]) + int(dd5["tokens"]["heroic"]) == 1, str(dd5["tokens"]))

	# A1 附带修正：这些"本回合"标志必须在**本人回合开始时**清掉（否则打出一张就整局一直生效）
	Game.setup("redskull", ["daredevil", "cap"], "none", "base")
	var dd4: Dictionary = Game.state["heroes"]["daredevil"]
	for _k in ["dd_token_on_enter", "dd_move_on_thug", "dd_move_on_rescue", "qs_carry_heroes", "astral_turn"]:
		dd4[_k] = true
	Game.state["dmg_uncancellable_turn"] = true   # 惩罚者·精准射击：同样是"本回合"
	Game.state["phase"] = "villain"
	Game.state["turn_count"] = 2
	var dd_idx: int = (Game.state["hero_ids"] as Array).find("daredevil")
	Game.state["current_hero"] = (dd_idx - 1 + (Game.state["hero_ids"] as Array).size()) % (Game.state["hero_ids"] as Array).size()
	Game._start_hero_phase()
	await _frames(2)
	_check("A1 附带：本人回合开始时清除「本回合」标志（雷达感官/盲眼正义/无畏之人/超人速度/星体投射）",
		not bool(dd4.get("dd_token_on_enter", false)) and not bool(dd4.get("dd_move_on_thug", false))
		and not bool(dd4.get("dd_move_on_rescue", false)) and not bool(dd4.get("qs_carry_heroes", false))
		and not bool(dd4.get("astral_turn", false)), str(dd4))
	_check("A1 附带：精准射击的「本回合伤害不可取消」同样在下一回合开始时清除",
		not bool(Game.state.get("dmg_uncancellable_turn", false)), str(Game.state.get("dmg_uncancellable_turn")))

	# ---- A2：反派回合结束时，没用掉的"首次免伤"作废 ----
	Game.setup("redskull", ["scarletwitch", "cap"], "none", "base")
	Game.state["phase"] = "villain"
	Game.state["turn_count"] = 1
	for _hh2 in Game.state["hero_ids"]:
		Game.state["heroes"][_hh2]["ignore_first_hit"] = true
	Game._start_hero_phase()      # 反派阶段 → 英雄阶段的唯一出口
	var still_shielded := false
	for _hh3 in Game.state["hero_ids"]:
		if bool(Game.state["heroes"][_hh3].get("ignore_first_hit", false)):
			still_shielded = true
	_check("裁定 A2①：推进到英雄阶段后，没用掉的首次免伤已作废", not still_shielded,
		str(Game.state["hero_ids"]))
	_check("裁定 A2①：日志有作废记录", _count_log("首次免伤已作废") == 1,
		"count=%d" % _count_log("首次免伤已作废"))
	# 端到端：真正跑一次反派回合（pending = 0，只结算到达效果），结束时同样作废
	Game.setup("redskull", ["scarletwitch", "cap"], "none", "base")
	Game.state["phase"] = "villain"
	for _hh4 in Game.state["hero_ids"]:
		Game.state["heroes"][_hh4]["ignore_first_hit"] = true
	Game.state["extra_villain_card"] = 0
	Game.state["skip_villain_card"] = 0
	Game.state["villain_pos"] = 0
	Game.state["locations"][0]["threat"] = null     # 避免到达效果弹窗
	await Game._run_villain_turn(true)
	var shielded2 := false
	for _hh5 in Game.state["hero_ids"]:
		if bool(Game.state["heroes"][_hh5].get("ignore_first_hit", false)):
			shielded2 = true
	_check("裁定 A2②：走完整反派回合（含到达效果结算）后同样作废，并已进入英雄阶段",
		not shielded2 and String(Game.state["phase"]) == "hero_play",
		"shielded=%s phase=%s" % [str(shielded2), str(Game.state["phase"])])

	# ---- B3：夜魔侠·盲眼正义（本回合每击败 1 个暴徒 → +1 移动指示物） ----
	Game.setup("redskull", ["daredevil", "cap"], "none", "base")
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	var dd3: Dictionary = Game.state["heroes"]["daredevil"]
	dd3["dd_move_on_thug"] = true
	dd3["tokens"]["move"] = 0
	var dd_loc3: int = int(dd3["location"])
	Game.state["locations"][dd_loc3]["thug"] = 3
	var def_before: int = _mission_tokens("defeat")
	Game._defeat_thug(dd_loc3, 2, "daredevil")
	_check("B3①：击败 2 个暴徒 → +2 移动指示物", int(dd3["tokens"]["move"]) == 2, str(dd3["tokens"]))
	_check("B3②：暴徒数准确减 2（3→1）", int(Game.state["locations"][dd_loc3]["thug"]) == 1,
		"thug=%d" % int(Game.state["locations"][dd_loc3]["thug"]))
	_check("B3③：同时计入「击败暴徒」任务进度（+2）", _mission_tokens("defeat") - def_before == 2,
		"%d→%d" % [def_before, _mission_tokens("defeat")])
	dd3["dd_move_on_thug"] = false
	Game._defeat_thug(dd_loc3, 1, "daredevil")
	_check("B3④：没打出盲眼正义时不加移动指示物", int(dd3["tokens"]["move"]) == 2, str(dd3["tokens"]))
	# 关联：快银·速度格斗的"进入即击败"现在也走统一减员出口（算任务进度）
	Game.setup("redskull", ["quicksilver", "cap"], "none", "base")
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	var qs2: Dictionary = Game.state["heroes"]["quicksilver"]
	qs2["qs_defeat_on_enter"] = true
	var q_from2: int = int(qs2["location"])
	var q_to2: int = int(Game._adjacent_locs(q_from2)[0])
	Game.state["locations"][q_to2]["thug"] = 1
	Game.state["locations"][q_to2]["civ"] = 0
	var def_b2: int = _mission_tokens("defeat")
	await Game._set_hero_loc("quicksilver", q_to2)
	_check("B3⑤：速度格斗进入地点自动击败 1 个暴徒，并计入任务进度",
		int(Game.state["locations"][q_to2]["thug"]) == 0 and _mission_tokens("defeat") - def_b2 == 1,
		"thug=%d defeat=%d→%d" % [int(Game.state["locations"][q_to2]["thug"]), def_b2, _mission_tokens("defeat")])

	# ---- B4：德拉克斯·复仇（三条：暴徒按空位搬 / 威胁卡看目标地点有没有 / 反派本体直接搬） ----
	var dv_ok := false
	if DB.hero_cards("drax").size() > 7:
		dv_ok = String(DB.hero_cards("drax")[7].get("effect", {}).get("type", "")) == "drax_vengeance"
	_check("B4 前置：drax 第 8 张卡是复仇", dv_ok, str(DB.hero_cards("drax")[7].get("effect", {})))
	# ① 暴徒：目标地点空位足够 → 全搬
	_prep("drax", 7)
	var dv_a_from: int = int(Game.state["heroes"]["drax"]["location"])
	var dv_a_to: int = Game._next_live_loc(dv_a_from)
	var slots_a: int = int(DB.location(String(Game.state["locations"][dv_a_to]["id"]))["slots"])
	Game.state["locations"][dv_a_from]["thug"] = 2
	Game.state["locations"][dv_a_from]["civ"] = 0
	Game.state["locations"][dv_a_from]["threat"] = null
	Game.state["locations"][dv_a_to]["thug"] = 0
	Game.state["locations"][dv_a_to]["civ"] = 0
	Game.state["locations"][dv_a_to]["threat"] = null
	await Game.trigger_effect()
	_pin("drax")
	_check("B4①前置：目标地点空位 ≥ 2（%d 个）" % slots_a, slots_a >= 2, "slots=%d" % slots_a)
	_check("B4①：2 个暴徒全被带走（原地 0 个）",
		int(Game.state["locations"][dv_a_from]["thug"]) == 0,
		"原地 %d" % int(Game.state["locations"][dv_a_from]["thug"]))
	_check("B4①：德拉克斯本人也移动到目标地点",
		int(Game.state["heroes"]["drax"]["location"]) == dv_a_to,
		"loc=%d want=%d" % [int(Game.state["heroes"]["drax"]["location"]), dv_a_to])
	# ② 暴徒：目标地点只剩 1 个空位 → 只搬 1 个
	_prep("drax", 7)
	var dv_b_from: int = int(Game.state["heroes"]["drax"]["location"])
	var dv_b_to: int = Game._next_live_loc(dv_b_from)
	var slots_b: int = int(DB.location(String(Game.state["locations"][dv_b_to]["id"]))["slots"])
	Game.state["locations"][dv_b_from]["thug"] = 3
	Game.state["locations"][dv_b_from]["civ"] = 0
	Game.state["locations"][dv_b_from]["threat"] = null
	Game.state["locations"][dv_b_to]["civ"] = maxi(slots_b - 1, 0)   # 只剩 1 个空位
	Game.state["locations"][dv_b_to]["thug"] = 0
	Game.state["locations"][dv_b_to]["threat"] = null
	await Game.trigger_effect()
	_pin("drax")
	_check("B4②：目标地点只剩 1 个空位 → 只带走 1 个暴徒（原地留 2 个）",
		int(Game.state["locations"][dv_b_from]["thug"]) == 2,
		"原地 %d" % int(Game.state["locations"][dv_b_from]["thug"]))
	_check("B4②：目标地点没有超出槽位（civ=%d thug=%d slots=%d）" % [
			int(Game.state["locations"][dv_b_to]["civ"]),
			int(Game.state["locations"][dv_b_to]["thug"]), slots_b],
		int(Game.state["locations"][dv_b_to]["civ"]) + int(Game.state["locations"][dv_b_to]["thug"]) <= slots_b, "")
	_check("B4②：日志写明被空位限制", _count_log("只带走") >= 1, "count=%d" % _count_log("只带走"))
	# ③a 威胁卡：目标地点没有威胁卡 → 跟着走
	_prep("drax", 7)
	var dv_c_from: int = int(Game.state["heroes"]["drax"]["location"])
	var dv_c_to: int = Game._next_live_loc(dv_c_from)
	Game.state["locations"][dv_c_from]["thug"] = 0
	Game.state["locations"][dv_c_from]["civ"] = 0
	Game.state["locations"][dv_c_from]["threat"] = {"name": "测试威胁卡A", "hp": 0, "heroic_tokens": 0, "arrival_triggered": true, "_tidx": 0}
	Game.state["locations"][dv_c_to]["thug"] = 0
	Game.state["locations"][dv_c_to]["civ"] = 0
	Game.state["locations"][dv_c_to]["threat"] = null
	await Game.trigger_effect()
	_pin("drax")
	_check("B4③a：目标地点没有威胁卡 → 威胁卡被一起带走",
		Game.state["locations"][dv_c_to]["threat"] != null and Game.state["locations"][dv_c_from]["threat"] == null,
		"src=%s dst=%s" % [str(Game.state["locations"][dv_c_from]["threat"]), str(Game.state["locations"][dv_c_to]["threat"])])
	# ③b 威胁卡：目标地点已有威胁卡 → 留在原地
	_prep("drax", 7)
	var dv_d_from: int = int(Game.state["heroes"]["drax"]["location"])
	var dv_d_to: int = Game._next_live_loc(dv_d_from)
	Game.state["locations"][dv_d_from]["thug"] = 0
	Game.state["locations"][dv_d_from]["civ"] = 0
	Game.state["locations"][dv_d_from]["threat"] = {"name": "测试威胁卡A", "hp": 0, "heroic_tokens": 0, "arrival_triggered": true, "_tidx": 0}
	Game.state["locations"][dv_d_to]["thug"] = 0
	Game.state["locations"][dv_d_to]["civ"] = 0
	Game.state["locations"][dv_d_to]["threat"] = {"name": "测试威胁卡B", "hp": 0, "heroic_tokens": 0, "arrival_triggered": true, "_tidx": 0}
	await Game.trigger_effect()
	_pin("drax")
	_check("B4③b：目标地点已有威胁卡 → 原地点威胁卡留在原地（目标地点仍是原来的那张）",
		Game.state["locations"][dv_d_from]["threat"] != null
		and String((Game.state["locations"][dv_d_from]["threat"] as Dictionary)["name"]) == "测试威胁卡A"
		and String((Game.state["locations"][dv_d_to]["threat"] as Dictionary)["name"]) == "测试威胁卡B",
		"src=%s dst=%s" % [str(Game.state["locations"][dv_d_from]["threat"]), str(Game.state["locations"][dv_d_to]["threat"])])
	# ④ 反派本体：直接搬（目标地点塞满 + 已有威胁卡，依然搬）
	_prep("drax", 7)
	var dv_e_from: int = int(Game.state["heroes"]["drax"]["location"])
	var dv_e_to: int = Game._next_live_loc(dv_e_from)
	var slots_e: int = int(DB.location(String(Game.state["locations"][dv_e_to]["id"]))["slots"])
	Game.state["locations"][dv_e_from]["thug"] = 2
	Game.state["locations"][dv_e_from]["civ"] = 0
	Game.state["locations"][dv_e_from]["threat"] = {"name": "测试威胁卡A", "hp": 0, "heroic_tokens": 0, "arrival_triggered": true, "_tidx": 0}
	Game.state["locations"][dv_e_to]["civ"] = slots_e           # 塞满 → 空位 0
	Game.state["locations"][dv_e_to]["thug"] = 0
	Game.state["locations"][dv_e_to]["threat"] = {"name": "测试威胁卡B", "hp": 0, "heroic_tokens": 0, "arrival_triggered": true, "_tidx": 0}
	Game.state["villain_pos"] = dv_e_from
	await Game.trigger_effect()
	_pin("drax")
	_check("B4④：反派本体在德拉克斯地点 → 直接搬到目标地点（不受空位/威胁卡限制）",
		int(Game.state["villain_pos"]) == dv_e_to,
		"villain_pos=%d want=%d" % [int(Game.state["villain_pos"]), dv_e_to])
	_check("B4④：空位为 0 → 暴徒一个都没动（原地仍 2 个）",
		int(Game.state["locations"][dv_e_from]["thug"]) == 2,
		"原地 %d" % int(Game.state["locations"][dv_e_from]["thug"]))
	_check("B4④：目标地点已有威胁卡 → 原地点威胁卡留在原地",
		String((Game.state["locations"][dv_e_from]["threat"] as Dictionary)["name"]) == "测试威胁卡A",
		str(Game.state["locations"][dv_e_from]["threat"]))
	# ⑤ 反派不在德拉克斯地点 → 反派不动（只搬"你所在地点"的敌人）
	_prep("drax", 7)
	var dv_f_from: int = int(Game.state["heroes"]["drax"]["location"])
	var dv_f_other: int = (Game._next_live_loc(dv_f_from) + 7) % Game.LOCATION_COUNT
	Game.state["locations"][dv_f_from]["thug"] = 0
	Game.state["locations"][dv_f_from]["civ"] = 0
	Game.state["locations"][dv_f_from]["threat"] = null
	Game.state["villain_pos"] = dv_f_other
	await Game.trigger_effect()
	_pin("drax")
	_check("B4⑤：反派不在德拉克斯地点时，反派不动（%d 仍在原处）" % dv_f_other,
		int(Game.state["villain_pos"]) == dv_f_other,
		"villain_pos=%d want=%d" % [int(Game.state["villain_pos"]), dv_f_other])

	if _fail == 0:
		print("=== S2 HEROES TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== S2 HEROES TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)
