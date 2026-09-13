extends Node
## 泽莫男爵（Baron Zemo，第一季众筹）回归测试
## 覆盖：
##   ① 数据完整性（20 反派 / 12 行动卡 / 6 威胁卡 / 生命 3-5-8 / 无邪恶计划轨道）+ 切图齐全
##   ② VillainRules 注册（IDS / BAM / 溢出 / 效果分发）
##   ③ BAM：泽莫所在地点 1 名英雄 1 伤 + 顺时针最近英雄 1 危机（含所在地点自身；平手由玩家选择）
##   ④ 溢出：放不下 → 离该地点最近的英雄 1 危机，且一次结算事件只结算一次
##   ⑤ 行动卡「雷电！」：所在地点 +3 暴徒，然后完整 BAM
##   ⑥ 行动卡「公民五」：顺时针移动到平民最多的地点，再丢弃该地点所有平民+暴徒
##   ⑦ 6 张威胁卡：修理师/甲虫/尖叫咪咪/月石/歌利亚 的 BAM；邪恶大师常量免伤
##   ⑧ 裁定③：威胁卡的"N 个英勇"必须同一（英雄）回合内凑够，否则清空重来
##   ⑨ 裁定⑤：邪恶大师在场 → 其它爪牙不受任何伤害；它被打掉后恢复正常
##   ⑩ 裁定①②⑥：英雄回合结束时逐个危机指示物弹窗盖符号、上限=该卡符号数、多余的留下、
##      被盖住的符号永久失效（下一位英雄不能继承、其它效果不能引用）、快照带 covered、UI 画在卡上
var _fail: int = 0

func _check(n: String, ok: bool, d: String = "") -> void:
	if ok:
		print("PASS: " + n)
	else:
		_fail += 1
		print("FAIL: %s — %s" % [n, d])

func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

## 干净开局：清场（无威胁/无指示物）、英雄满手牌未 KO、指定站位
func _prep(locs: Array = []) -> void:
	Game.setup("zemo", ["cap", "ironman", "hulk"], "none", "base")
	for l in Game.state["locations"]:
		l["civ"] = 0
		l["thug"] = 0
		l["crisis"] = 0
		l["threat"] = null
		l["destroyed"] = false
	for i in range(Game.state["hero_ids"].size()):
		var hid: String = String(Game.state["hero_ids"][i])
		var h: Dictionary = Game.state["heroes"][hid]
		h["ko"] = false
		h["crisis"] = 0
		h["hand"] = [0, 1, 2, 3]
		h["location"] = int(locs[i]) if i < locs.size() else 0
	Game.state["ko_tokens"] = 0
	Game.state["phase"] = "hero_actions"

## 找一个槽位 >= n 且未被摧毁的地点（放置类测试用；地点槽位最少 2）
func _loc_with_slots(n: int) -> int:
	for i in range(Game.LOCATION_COUNT):
		var l: Dictionary = Game.state["locations"][i]
		if bool(l.get("destroyed", false)):
			continue
		if int(DB.location(String(l["id"]))["slots"]) >= n:
			return i
	return 0

## 按 DB 数据造一张威胁卡（与引擎放置时一致：hp = henchman_hp）
func _mk_threat(idx: int) -> Dictionary:
	var t: Dictionary = (DB.villain("zemo")["threats"][idx] as Dictionary).duplicate(true)
	t["hp"] = int(t.get("henchman_hp", 0))
	t["heroic_tokens"] = 0
	t["arrival_triggered"] = false
	t["_bam_done"] = false
	return t

func _threat_idx(name: String) -> int:
	var ts: Array = DB.villain("zemo")["threats"]
	for i in range(ts.size()):
		if String((ts[i] as Dictionary)["name"]) == name:
			return i
	return -1

func _card_with_syms(hid: String, n: int, exact: bool) -> int:
	var cs: Array = DB.hero_cards(hid)
	for i in range(cs.size()):
		var k: int = (cs[i]["symbols"] as Array).size()
		if (exact and k == n) or (not exact and k >= n):
			return i
	return -1

func _card_with_effect(hid: String, etype: String) -> int:
	var cs: Array = DB.hero_cards(hid)
	for i in range(cs.size()):
		var e: Variant = (cs[i] as Dictionary).get("effect", null)
		if e != null and String((e as Dictionary).get("type", "")) == etype:
			return i
	return -1

## 让 hid 打出"符号数 == n"的卡；返回该卡的符号
func _play_card_with_syms(hid: String, n: int) -> Array:
	var pick: int = _card_with_syms(hid, n, true)
	if pick < 0:
		return []
	Game.state["heroes"][hid]["hand"] = [pick]
	Game.state["phase"] = "hero_play"
	await Game.play_card(0)
	return (DB.hero_cards(hid)[pick]["symbols"] as Array).duplicate()

func _ready() -> void:
	Game.autopilot = true

	# ==================== ① 数据完整性 ====================
	_check("① 反派总数 20（泽莫 19 → 加摩多克后 20）", DB.villains.size() == 20, "实际 %d" % DB.villains.size())
	var z: Dictionary = DB.villain("zemo")
	_check("① zemo 存在且 name_en = Baron Zemo",
		not z.is_empty() and String(z.get("name_en", "")) == "Baron Zemo", str(z.get("name_en", "")))
	_check("① 生命值 3/5/8",
		int(z["health"]["2"]) == 3 and int(z["health"]["3"]) == 5 and int(z["health"]["4"]) == 8,
		"%s/%s/%s" % [z["health"]["2"], z["health"]["3"], z["health"]["4"]])
	_check("① 无邪恶计划轨道（plot_track = none，恐惧轨道 0）",
		String(z["plot_track"]) == "none" and int(z["fear_track_max"]) == 0,
		"%s/%s" % [z["plot_track"], z["fear_track_max"]])
	_check("① 12 张行动卡", (z["actions"] as Array).size() == 12, "%d" % (z["actions"] as Array).size())
	_check("① 6 张威胁卡", (z["threats"] as Array).size() == 6, "%d" % (z["threats"] as Array).size())
	_check("① 行动卡 1/2 = 移动3+BAM+雷电！",
		int(z["actions"][0]["move"]) == 3 and bool(z["actions"][0]["bam"])
		and String(z["actions"][0]["effect"]["type"]) == "zemo_thunderbolt"
		and int(z["actions"][1]["move"]) == 3 and String(z["actions"][1]["effect"]["type"]) == "zemo_thunderbolt", "")
	_check("① 行动卡 3/4 = 移动0+无BAM+公民五",
		int(z["actions"][2]["move"]) == 0 and not bool(z["actions"][2]["bam"])
		and String(z["actions"][2]["effect"]["type"]) == "zemo_civil_five"
		and int(z["actions"][3]["move"]) == 0 and String(z["actions"][3]["effect"]["type"]) == "zemo_civil_five", "")
	var c12: Dictionary = z["actions"][11]
	var c12_place: Array = c12["place"]
	var c12_n: int = (c12_place[0] as Array).size() + (c12_place[1] as Array).size() + (c12_place[2] as Array).size()
	_check("① 行动卡 12 = 移动5 + 无BAM + 10 个放置指示物（以卡图为准，docx 把卡11 复制成了卡12）",
		int(c12["move"]) == 5 and not bool(c12["bam"]) and c12_place.size() == 3 and c12_n == 10,
		"move=%d bam=%s place=%d/%d" % [int(c12["move"]), str(c12["bam"]), c12_place.size(), c12_n])
	_check("① 行动卡 5 = 移动0+BAM（无放置图案）",
		int(z["actions"][4]["move"]) == 0 and bool(z["actions"][4]["bam"]) and z["actions"][4]["place"] == null, "")
	# 卡 6 按卡图 action_06.png：移动1 + BAM! + 三个白框**各 1 个暴徒**（共 3 个）
	var c6_place: Array = z["actions"][5]["place"]
	var c6_n: int = 0
	var c6_ok: bool = c6_place != null and c6_place.size() == 3
	for g in c6_place:
		c6_n += (g as Array).size()
		if (g as Array).size() != 1 or String((g as Array)[0]) != "thug":
			c6_ok = false
	_check("① 行动卡 6 = 移动1 + BAM + 三槽各 1 个暴徒（共 3 个暴徒；卡图 action_06.png）",
		int(z["actions"][5]["move"]) == 1 and bool(z["actions"][5]["bam"]) and c6_ok and c6_n == 3,
		"place=%s 共 %d 个" % [str(c6_place), c6_n])
	# 卡 9 按卡图 action_09.png：移动1 + BAM! + **平民 2/1/2 共 5 个**（不是暴徒）
	var c9_place: Array = z["actions"][8]["place"]
	var c9_n: int = 0
	var c9_civ: bool = c9_place != null and c9_place.size() == 3
	for g in c9_place:
		c9_n += (g as Array).size()
		for tk in (g as Array):
			if String(tk) != "civ":
				c9_civ = false
	_check("① 行动卡 9 = 移动1 + BAM + 平民 2/1/2 共 5 个（**全是平民**，卡图 action_09.png）",
		int(z["actions"][8]["move"]) == 1 and bool(z["actions"][8]["bam"]) and c9_civ and c9_n == 5
		and (c9_place[0] as Array).size() == 2 and (c9_place[1] as Array).size() == 1 and (c9_place[2] as Array).size() == 2,
		"place=%s 共 %d 个" % [str(c9_place), c9_n])
	# 卡 7/8 = 移动4 + 暴徒 2/1/2；卡 10/11 = 移动2/3 + 平民 2/1/2（卡图核对：类型不能互换）
	var p78_ok: bool = true
	var p78_n: int = 0
	for ci in [6, 7]:
		for g in (z["actions"][ci]["place"] as Array):
			p78_n += (g as Array).size()
			for tk in (g as Array):
				if String(tk) != "thug":
					p78_ok = false
	var p1011_ok: bool = true
	var p1011_n: int = 0
	for ci in [9, 10]:
		for g in (z["actions"][ci]["place"] as Array):
			p1011_n += (g as Array).size()
			for tk in (g as Array):
				if String(tk) != "civ":
					p1011_ok = false
	_check("① 行动卡 7/8 = 移动4+暴徒3槽共5个；卡 10 = 移动2、卡 11 = 移动3（平民3槽共5个）",
		int(z["actions"][6]["move"]) == 4 and int(z["actions"][7]["move"]) == 4
		and int(z["actions"][9]["move"]) == 2 and int(z["actions"][10]["move"]) == 3
		and p78_ok and p78_n == 10 and p1011_ok and p1011_n == 10,
		"卡7/8 暴徒=%d ok=%s；卡10/11 平民=%d ok=%s" % [p78_n, str(p78_ok), p1011_n, str(p1011_ok)])
	var hp_want: Array = [3, 4, 3, 0, 5, 5]
	var cl_want: Array = [2, 2, 2, 3, 0, 3]
	var nm_want: Array = ["修理师", "甲虫", "尖叫咪咪", "邪恶大师", "月石", "歌利亚"]
	var ok_t := true
	var det := ""
	for i in range(6):
		var t: Dictionary = z["threats"][i]
		# 月石没有 clear 字段（用户裁定：只能靠伤害打掉）→ 用 get 取，别直接索引
		var have_cl: int = (t.get("clear", []) as Array).size()
		if String(t["name"]) != nm_want[i] or int(t["henchman_hp"]) != hp_want[i] or have_cl != cl_want[i]:
			ok_t = false
			det = "第 %d 张 %s hp=%s clear=%d" % [i + 1, t["name"], str(t["henchman_hp"]), have_cl]
			break
	_check("① 6 张威胁卡：卡图核对的血量 3/4/3/0/5/5、英勇槽 2/2/2/3/0/3（月石按用户裁定不给英勇槽，只能靠伤害打掉）", ok_t, det)
	_check("① 月石：**完全没有** clear / same_turn_clear 两个字段（不是空数组，是不写）",
		not (z["threats"][4] as Dictionary).has("clear")
		and not (z["threats"][4] as Dictionary).has("same_turn_clear"),
		"keys=%s" % str((z["threats"][4] as Dictionary).keys()))
	_check("① 邪恶大师：无生命值 + 常量免伤标记 + 无 BAM",
		int(z["threats"][3]["henchman_hp"]) == 0 and bool(z["threats"][3]["immune_henchmen"])
		and not bool(z["threats"][3]["bam"]), "")
	var st_ok := true
	for i in range(6):
		var want_st: bool = i != 4   # 索引 4 = 月石：用户裁定无英勇槽，因此不带 same_turn_clear
		if bool((z["threats"][i] as Dictionary).get("same_turn_clear", false)) != want_st:
			st_ok = false
	_check("① 除月石外 5 张威胁卡带 same_turn_clear；月石无英勇槽、不带（用户裁定）", st_ok, "")
	var art_ok := true
	var art_missing := ""
	for i in range(12):
		var p := "res://assets/cards/villains/zemo/action_%02d.png" % (i + 1)
		if not FileAccess.file_exists(p):
			art_ok = false
			art_missing = p
	for i in range(6):
		var p2 := "res://assets/cards/villains/zemo/threat_%02d.png" % (i + 1)
		if not FileAccess.file_exists(p2):
			art_ok = false
			art_missing = p2
	for p3 in ["back.png", "panel.png", "panel_back.png"]:
		if not FileAccess.file_exists("res://assets/cards/villains/zemo/" + p3):
			art_ok = false
			art_missing = p3
	_check("① 切图齐全：12 行动卡图 + 6 威胁卡图 + back/panel/panel_back", art_ok, art_missing)

	# ==================== ② 注册 ====================
	_check("② VillainRules.IDS 含 zemo（数量与 DB 一致）",
		VillainRules.IDS.has("zemo") and VillainRules.IDS.size() == DB.villains.size(),
		"%d" % VillainRules.IDS.size())

	# ==================== ③ BAM ====================
	_prep([0, 0, 0])
	var vpos: int = int(Game.state["villain_pos"])
	Game.state["heroes"]["cap"]["location"] = vpos
	Game.state["heroes"]["ironman"]["location"] = (vpos + 2) % Game.LOCATION_COUNT
	Game.state["heroes"]["hulk"]["location"] = (vpos + 4) % Game.LOCATION_COUNT
	await VillainRules.on_bam(Game, "zemo")
	_check("③ BAM：泽莫所在地点的英雄受到 1 点伤害（手牌 4→3）",
		Game.state["heroes"]["cap"]["hand"].size() == 3, "hand=%d" % Game.state["heroes"]["cap"]["hand"].size())
	_check("③ BAM：离泽莫最近的英雄（所在地点的 cap）获得 1 个危机指示物",
		int(Game.state["heroes"]["cap"]["crisis"]) == 1 and int(Game.state["heroes"]["ironman"]["crisis"]) == 0,
		"cap=%d ironman=%d" % [int(Game.state["heroes"]["cap"]["crisis"]), int(Game.state["heroes"]["ironman"]["crisis"])])
	# ③b 泽莫所在地点没人 → 取顺时针第一个有英雄的地点
	_prep([0, 0, 0])
	vpos = int(Game.state["villain_pos"])
	Game.state["heroes"]["cap"]["location"] = (vpos + 5) % Game.LOCATION_COUNT
	Game.state["heroes"]["ironman"]["location"] = (vpos + 1) % Game.LOCATION_COUNT
	Game.state["heroes"]["hulk"]["location"] = (vpos + 3) % Game.LOCATION_COUNT
	await VillainRules.on_bam(Game, "zemo")
	_check("③b 顺时针最近：vpos+1 的 ironman 获得危机（vpos 本人无英雄）",
		int(Game.state["heroes"]["ironman"]["crisis"]) == 1
		and int(Game.state["heroes"]["cap"]["crisis"]) == 0 and int(Game.state["heroes"]["hulk"]["crisis"]) == 0,
		"ironman=%d cap=%d hulk=%d" % [int(Game.state["heroes"]["ironman"]["crisis"]),
			int(Game.state["heroes"]["cap"]["crisis"]), int(Game.state["heroes"]["hulk"]["crisis"])])
	# ③c 平手（同一地点多名英雄）→ 由玩家选择（autopilot 取 hero_ids 顺序第一位）
	_prep([0, 0, 0])
	vpos = int(Game.state["villain_pos"])
	Game.state["heroes"]["cap"]["location"] = (vpos + 2) % Game.LOCATION_COUNT
	Game.state["heroes"]["ironman"]["location"] = (vpos + 2) % Game.LOCATION_COUNT
	Game.state["heroes"]["hulk"]["location"] = (vpos + 4) % Game.LOCATION_COUNT
	await VillainRules.on_bam(Game, "zemo")
	var total_c: int = int(Game.state["heroes"]["cap"]["crisis"]) + int(Game.state["heroes"]["ironman"]["crisis"])
	_check("③c 平手由玩家选择：同地点两名英雄合计只发 1 个危机（不是每人 1 个）",
		total_c == 1, "合计=%d" % total_c)

	# ==================== ④ 溢出 ====================
	_prep([0, 0, 0])
	var oloc: int = 2
	var slots: int = int(DB.location(String(Game.state["locations"][oloc]["id"]))["slots"])
	Game.state["locations"][oloc]["civ"] = slots          # 已满
	Game.state["heroes"]["cap"]["location"] = oloc
	Game.state["heroes"]["ironman"]["location"] = (oloc + 3) % Game.LOCATION_COUNT
	Game.state["overflow_settled"] = 0
	Game.state["overflow_settled_locs"] = []
	Game._begin_overflow_event()
	await Game._place_token_at("civ", oloc, 2)            # 2 个都放不下 = 同一次结算事件
	_check("④ 溢出：离该地点最近的英雄获得 1 个危机指示物",
		int(Game.state["heroes"]["cap"]["crisis"]) == 1, "cap=%d" % int(Game.state["heroes"]["cap"]["crisis"]))
	_check("④ 溢出：同一次结算事件只结算 1 次（2 个放不下 ≠ 2 个危机）",
		int(Game.state["heroes"]["cap"]["crisis"]) + int(Game.state["heroes"]["ironman"]["crisis"]) == 1,
		"cap=%d ironman=%d" % [int(Game.state["heroes"]["cap"]["crisis"]), int(Game.state["heroes"]["ironman"]["crisis"])])
	_check("④ 溢出：平民指示物没有被放上去（该地点仍为满）",
		int(Game.state["locations"][oloc]["civ"]) == slots, "civ=%d" % int(Game.state["locations"][oloc]["civ"]))

	# ==================== ⑤ 雷电！ ====================
	_prep([0, 0, 0])
	vpos = _loc_with_slots(3)
	Game.state["villain_pos"] = vpos                      # 保证所在地点放得下 3 个暴徒
	Game.state["heroes"]["cap"]["location"] = vpos
	Game.state["heroes"]["ironman"]["location"] = (vpos + 3) % Game.LOCATION_COUNT
	Game.state["heroes"]["hulk"]["location"] = (vpos + 5) % Game.LOCATION_COUNT
	var thunder: Dictionary = {"type": "zemo_thunderbolt", "name": "雷电！", "text": "将三个暴徒指示物添加到泽莫男爵所在地点，然后 BAM！"}
	await VillainRules.resolve_effect(Game, thunder)
	_check("⑤ 雷电！：泽莫所在地点 +3 暴徒",
		int(Game.state["locations"][vpos]["thug"]) == 3, "thug=%d" % int(Game.state["locations"][vpos]["thug"]))
	_check("⑤ 雷电！：随后完整 BAM（所在地点英雄受到 1 点伤害）",
		Game.state["heroes"]["cap"]["hand"].size() == 3, "hand=%d" % Game.state["heroes"]["cap"]["hand"].size())
	_check("⑤ 雷电！：BAM 的最近英雄危机也结算了",
		int(Game.state["heroes"]["cap"]["crisis"]) == 1, "cap=%d" % int(Game.state["heroes"]["cap"]["crisis"]))

	# ==================== ⑥ 公民五 ====================
	var civ5: Dictionary = {"type": "zemo_civil_five", "name": "公民五",
		"text": "顺时针移动到拥有最多平民指示物的地点。丢弃泽莫男爵所在地点所有的平民和暴徒指示物。"}
	_prep([0, 0, 0])
	vpos = int(Game.state["villain_pos"])
	var far: int = (vpos + 2) % Game.LOCATION_COUNT
	var near: int = (vpos + 1) % Game.LOCATION_COUNT
	Game.state["locations"][far]["civ"] = 3
	Game.state["locations"][far]["thug"] = 2
	Game.state["locations"][near]["civ"] = 1
	Game.state["locations"][vpos]["civ"] = 1
	Game.state["locations"][vpos]["thug"] = 1
	await VillainRules.resolve_effect(Game, civ5)
	_check("⑥ 公民五：顺时针移动到平民最多的地点（vpos+2，3 个平民）",
		int(Game.state["villain_pos"]) == far, "villain_pos=%d（期望 %d）" % [int(Game.state["villain_pos"]), far])
	_check("⑥ 公民五：丢弃该地点所有平民与暴徒",
		int(Game.state["locations"][far]["civ"]) == 0 and int(Game.state["locations"][far]["thug"]) == 0,
		"civ=%d thug=%d" % [int(Game.state["locations"][far]["civ"]), int(Game.state["locations"][far]["thug"])])
	# ⑥b 平手 → 顺时针先遇到的
	_prep([0, 0, 0])
	vpos = int(Game.state["villain_pos"])
	Game.state["locations"][(vpos + 3) % Game.LOCATION_COUNT]["civ"] = 2
	Game.state["locations"][(vpos + 1) % Game.LOCATION_COUNT]["civ"] = 2
	await VillainRules.resolve_effect(Game, civ5)
	_check("⑥b 公民五：平民数平手 → 取顺时针先遇到的地点（vpos+1）",
		int(Game.state["villain_pos"]) == (vpos + 1) % Game.LOCATION_COUNT,
		"villain_pos=%d（期望 %d）" % [int(Game.state["villain_pos"]), (vpos + 1) % Game.LOCATION_COUNT])
	# ⑥c 场上没有平民 → 不移动，仍结算丢弃
	_prep([0, 0, 0])
	vpos = int(Game.state["villain_pos"])
	Game.state["locations"][vpos]["thug"] = 2
	await VillainRules.resolve_effect(Game, civ5)
	_check("⑥c 公民五：场上没有平民 → 泽莫不移动，仍丢弃所在地点暴徒",
		int(Game.state["villain_pos"]) == vpos and int(Game.state["locations"][vpos]["thug"]) == 0,
		"pos=%d thug=%d" % [int(Game.state["villain_pos"]), int(Game.state["locations"][vpos]["thug"])])

	# ==================== ⑦ 6 张威胁卡的 BAM ====================
	var tl: int = 3
	# ⑦a 修理师：从本地点丢弃 1 个平民
	_prep([0, 0, 0])
	Game.state["locations"][tl]["civ"] = 2
	Game.state["locations"][tl]["threat"] = _mk_threat(_threat_idx("修理师"))
	await Game._trigger_all_threat_bam()
	_check("⑦a 修理师 BAM：从本地点丢弃 1 个平民（2→1）",
		int(Game.state["locations"][tl]["civ"]) == 1, "civ=%d" % int(Game.state["locations"][tl]["civ"]))
	# ⑦b 甲虫：从本地点丢弃 1 个暴徒
	_prep([0, 0, 0])
	Game.state["locations"][tl]["thug"] = 2
	Game.state["locations"][tl]["threat"] = _mk_threat(_threat_idx("甲虫"))
	await Game._trigger_all_threat_bam()
	_check("⑦b 甲虫 BAM：从本地点丢弃 1 个暴徒（2→1）",
		int(Game.state["locations"][tl]["thug"]) == 1, "thug=%d" % int(Game.state["locations"][tl]["thug"]))
	# ⑦c 尖叫咪咪：对相邻地点每位英雄 1 伤
	var adj: Array = Game._adjacent_locs(tl)
	_prep([0, 0, 0])
	Game.state["heroes"]["cap"]["location"] = tl
	Game.state["heroes"]["ironman"]["location"] = int(adj[0])
	Game.state["heroes"]["hulk"]["location"] = int(adj[1])
	Game.state["locations"][tl]["threat"] = _mk_threat(_threat_idx("尖叫咪咪"))
	await Game._trigger_all_threat_bam()
	_check("⑦c 尖叫咪咪 BAM：相邻两地点英雄各 1 伤（4→3），本地点英雄无损",
		Game.state["heroes"]["ironman"]["hand"].size() == 3 and Game.state["heroes"]["hulk"]["hand"].size() == 3
		and Game.state["heroes"]["cap"]["hand"].size() == 4,
		"cap=%d ironman=%d hulk=%d" % [Game.state["heroes"]["cap"]["hand"].size(),
			Game.state["heroes"]["ironman"]["hand"].size(), Game.state["heroes"]["hulk"]["hand"].size()])
	# ⑦d 月石：本地点 2 伤 + 相邻地点 1 伤
	_prep([0, 0, 0])
	Game.state["heroes"]["cap"]["location"] = tl
	Game.state["heroes"]["ironman"]["location"] = int(adj[0])
	Game.state["heroes"]["hulk"]["location"] = int(adj[1])
	Game.state["locations"][tl]["threat"] = _mk_threat(_threat_idx("月石"))
	await Game._trigger_all_threat_bam()
	_check("⑦d 月石 BAM：本地点英雄 2 伤（4→2），相邻地点英雄各 1 伤（4→3）",
		Game.state["heroes"]["cap"]["hand"].size() == 2 and Game.state["heroes"]["ironman"]["hand"].size() == 3
		and Game.state["heroes"]["hulk"]["hand"].size() == 3,
		"cap=%d ironman=%d hulk=%d" % [Game.state["heroes"]["cap"]["hand"].size(),
			Game.state["heroes"]["ironman"]["hand"].size(), Game.state["heroes"]["hulk"]["hand"].size()])
	# ⑦e 歌利亚：对本地点 1 名英雄 2 伤
	_prep([0, 0, 0])
	Game.state["heroes"]["cap"]["location"] = tl
	Game.state["heroes"]["ironman"]["location"] = (tl + 3) % Game.LOCATION_COUNT
	Game.state["locations"][tl]["threat"] = _mk_threat(_threat_idx("歌利亚"))
	await Game._trigger_all_threat_bam()
	_check("⑦e 歌利亚 BAM：本地点 1 名英雄受 2 伤（4→2），另一地点英雄无损",
		Game.state["heroes"]["cap"]["hand"].size() == 2 and Game.state["heroes"]["ironman"]["hand"].size() == 4,
		"cap=%d ironman=%d" % [Game.state["heroes"]["cap"]["hand"].size(), Game.state["heroes"]["ironman"]["hand"].size()])
	# ⑦f 邪恶大师（常量卡）没有 BAM
	_prep([0, 0, 0])
	Game.state["locations"][tl]["civ"] = 2
	Game.state["locations"][tl]["threat"] = _mk_threat(_threat_idx("邪恶大师"))
	await Game._trigger_all_threat_bam()
	_check("⑦f 邪恶大师（常量卡）没有 BAM：不丢平民、不造成伤害",
		int(Game.state["locations"][tl]["civ"]) == 2 and Game.state["heroes"]["cap"]["hand"].size() == 4,
		"civ=%d hand=%d" % [int(Game.state["locations"][tl]["civ"]), Game.state["heroes"]["cap"]["hand"].size()])

	# ==================== ⑧ 裁定③：同回合凑英勇 ====================
	_prep([0, 0, 0])
	Game.state["locations"][tl]["threat"] = _mk_threat(_threat_idx("修理师"))   # 2 个英勇
	Game._fill_ronan_threat("cap", tl, "heroic")
	_check("⑧ 修理师（2 英勇）：同回合内放第 1 个 → 进度 1/2 且威胁还在",
		int((Game.state["locations"][tl]["threat"].get("clear_progress", []) as Array).size()) == 1
		and Game.state["locations"][tl]["threat"] != null, "")
	Game._fill_ronan_threat("cap", tl, "heroic")
	_check("⑧ 修理师：同一回合内放满第 2 个 → 被击败（威胁卡移除）",
		Game.state["locations"][tl]["threat"] == null, "仍然在场")
	# ⑧b 只凑了 1 个 → 新英雄回合开始必须清空
	_prep([0, 0, 0])
	Game.state["locations"][tl]["threat"] = _mk_threat(_threat_idx("歌利亚"))   # 3 个英勇
	Game._fill_ronan_threat("cap", tl, "heroic")
	Game._reset_same_turn_threats()
	_check("⑧b 只凑了 1/3 时新英雄回合开始 → 进度清空重来（0/3），威胁仍在场",
		Game.state["locations"][tl]["threat"] != null
		and int((Game.state["locations"][tl]["threat"].get("clear_progress", []) as Array).size()) == 0,
		"progress=%d" % int((Game.state["locations"][tl]["threat"].get("clear_progress", []) as Array).size()))
	# ⑧c 真实流程接线：英雄回合结束 → 下一个英雄回合开始 → 进度清空
	_prep([0, 0, 0])
	Game.state["locations"][tl]["threat"] = _mk_threat(_threat_idx("歌利亚"))
	Game._fill_ronan_threat("cap", tl, "heroic")
	Game.state["current_hero"] = 0
	await _play_card_with_syms("cap", 1)
	Game.state["hero_cards_played"] = 0        # 不满 3 张 → 直接进下一个英雄回合（不跑反派回合）
	Game.state["phase"] = "hero_end"
	await Game.end_turn()
	var prog_c := -1
	if Game.state["locations"][tl]["threat"] != null:
		prog_c = int((Game.state["locations"][tl]["threat"].get("clear_progress", []) as Array).size())
	_check("⑧c 真实回合流转：cap 回合结束 → 下个英雄回合开始 → 歌利亚进度被清空",
		Game.state["locations"][tl]["threat"] == null or prog_c == 0, "progress=%d" % prog_c)

	# ==================== ⑨ 裁定⑤：邪恶大师免伤 ====================
	_prep([0, 0, 0])
	var hl2: int = 4
	var master: int = (hl2 + 2) % Game.LOCATION_COUNT    # 与爪牙不同地点（地点环共 6 个）
	Game.state["locations"][hl2]["threat"] = _mk_threat(_threat_idx("修理师"))     # hp 3
	Game.state["locations"][master]["threat"] = _mk_threat(_threat_idx("邪恶大师"))
	_check("⑨ 邪恶大师在场 → _henchman_immune() 为真", Game._henchman_immune(), "")
	await Game._perform_attack_at(hl2, "henchman:修理师", "cap")
	_check("⑨ 攻击爪牙：邪恶大师在场时不受任何伤害（仍为 3 生命），且没有被误清除",
		Game.state["locations"][hl2]["threat"] != null and int(Game.state["locations"][hl2]["threat"]["hp"]) == 3,
		"hp=%s" % str(Game.state["locations"][hl2].get("threat", {}).get("hp", "已清除")))
	# ⑨b 卡牌效果（绿巨人重击）同样被挡
	_prep([0, 0, 0])
	Game.state["locations"][hl2]["threat"] = _mk_threat(_threat_idx("修理师"))
	Game.state["locations"][master]["threat"] = _mk_threat(_threat_idx("邪恶大师"))
	Game.state["heroes"]["hulk"]["location"] = hl2
	Game.state["current_hero"] = Game.state["hero_ids"].find("hulk")
	var smash: int = _card_with_effect("hulk", "hulk_smash")
	Game.state["heroes"]["hulk"]["hand"] = [smash]
	Game.state["phase"] = "hero_play"
	await Game.play_card(0)
	await Game.trigger_effect()
	_check("⑨b 绿巨人重击：邪恶大师在场时爪牙也不受伤害",
		Game.state["locations"][hl2]["threat"] != null and int(Game.state["locations"][hl2]["threat"]["hp"]) == 3,
		"hp=%s" % str(Game.state["locations"][hl2].get("threat", {}).get("hp", "已清除")))
	# ⑨c 邪恶大师被打掉（同回合 3 英勇）→ 爪牙恢复可受伤
	Game._fill_ronan_threat("cap", master, "heroic")
	Game._fill_ronan_threat("cap", master, "heroic")
	Game._fill_ronan_threat("cap", master, "heroic")
	_check("⑨c 邪恶大师可被打掉（同回合 3 个英勇 → 被击败、免伤消失）",
		Game.state["locations"][master]["threat"] == null and not Game._henchman_immune(), "")
	await Game._perform_attack_at(hl2, "henchman:修理师", "cap")
	_check("⑨c 邪恶大师离场后 → 爪牙恢复受伤（3→2）",
		int(Game.state["locations"][hl2]["threat"]["hp"]) == 2,
		"hp=%d" % int(Game.state["locations"][hl2]["threat"]["hp"]))

	# ==================== ⑩ 裁定①②⑥：危机指示物盖符号 ====================
	_prep([0, 0, 0])
	Game.state["current_hero"] = 0
	var syms: Array = await _play_card_with_syms("cap", 2)
	_check("⑩ 前置：cap 打出的是 2 符号的卡", syms.size() == 2, "syms=%d" % syms.size())
	var si: int = int(Game.state["story"].size()) - 1
	Game.state["heroes"]["cap"]["crisis"] = 3          # 3 个危机 > 2 个符号
	Game.state["hero_cards_played"] = 0
	Game.state["phase"] = "hero_end"
	await Game.end_turn()
	var entry: Dictionary = Game.state["story"][si]
	var covered: Array = entry.get("covered", [])
	_check("⑩ 回合结束逐个弹窗覆盖：上限 = 该卡印刷符号数（2 个），不是 3 个",
		covered.size() == 2, "covered=%d" % covered.size())
	_check("⑩ 被盖住的是这张卡上不同的符号（不能重复选择）",
		covered.size() == 2 and int(covered[0]) != int(covered[1]), str(covered))
	_check("⑩ 多余的危机指示物留在英雄身上（3 - 2 = 1）",
		int(Game.state["heroes"]["cap"]["crisis"]) == 1, "crisis=%d" % int(Game.state["heroes"]["cap"]["crisis"]))
	_check("⑩ 被盖住的符号永久失效：这张卡的可用符号变成 0 个",
		Game._entry_uncovered_symbols(entry).size() == 0,
		"剩下 %d" % Game._entry_uncovered_symbols(entry).size())
	# ⑩b 下一位英雄不能继承
	var keep_story: Array = Game.state["story"]
	Game.state["story"] = [
		{"type": "hero", "hero": "cap", "idx": entry["idx"], "covered": [0]},
		{"type": "villain", "villain": "zemo", "idx": 0, "move": 0, "face_down": false},
	]
	var prev: Array = Game._last_hero_card_symbols()
	_check("⑩b 下一位英雄的继承符号只剩没被盖住的那 1 个（被盖的符号不继承）",
		prev.size() == 1 and String(prev[0]) == String(syms[1]), "prev=%s" % str(prev))
	# ⑩c 其它效果不能引用被盖住的符号
	Game.state["story"] = [{"type": "hero", "hero": "cap", "idx": entry["idx"], "covered": [0, 1]}]
	var cnt_cov: int = Game._count_recent_story_symbols(String(syms[0]), 4, false)
	_check("⑩c 其它效果引用故事情节符号时也跳过被盖住的（计数 0）", cnt_cov == 0, "count=%d" % cnt_cov)
	Game.state["story"] = keep_story
	# ⑩d 覆盖是永久的（故事情节里那张卡上的 covered 一直在，不会"复原"）
	_check("⑩d 覆盖永久生效（故事情节这张卡上 covered 仍是 2）",
		(Game.state["story"][si].get("covered", []) as Array).size() == 2,
		str(Game.state["story"][si].get("covered", [])))
	# ⑩e 1 符号卡 + 3 个危机 → 只盖 1 个，剩 2 个留到以后
	_prep([0, 0, 0])
	Game.state["current_hero"] = 0
	var syms1: Array = await _play_card_with_syms("cap", 1)
	_check("⑩e 前置：cap 打出的是 1 符号的卡", syms1.size() == 1, "syms=%d" % syms1.size())
	var si1: int = int(Game.state["story"].size()) - 1
	Game.state["heroes"]["cap"]["crisis"] = 3
	Game.state["hero_cards_played"] = 0
	Game.state["phase"] = "hero_end"
	await Game.end_turn()
	_check("⑩e 1 符号卡：只盖 1 个符号，剩下 2 个危机留在身上",
		(Game.state["story"][si1].get("covered", []) as Array).size() == 1
		and int(Game.state["heroes"]["cap"]["crisis"]) == 2,
		"covered=%d crisis=%d" % [(Game.state["story"][si1].get("covered", []) as Array).size(),
			int(Game.state["heroes"]["cap"]["crisis"])])

	# ==================== ⑪ 联机快照带 covered ====================
	Net.active = true
	Net.is_host = false
	Net.my_peer = 2
	Net.seats = [
		{"peer": 1, "name": "房主", "hero": "cap", "villain": "", "locs": [], "ready": false},
		{"peer": 2, "name": "我", "hero": "cap", "villain": "", "locs": [], "ready": false},
	]
	var vis: Dictionary = Net.visible_state_for("cap")
	var vis_cov: Variant = null
	for e2 in (vis.get("story", []) as Array):
		if e2 is Dictionary and (e2 as Dictionary).has("covered"):
			vis_cov = (e2 as Dictionary)["covered"]
	_check("⑪ 联机快照下发了故事情节里的 covered（客户端也能画出被盖住的符号）",
		vis_cov != null and (vis_cov as Array).size() == 1, str(vis_cov))
	Net.active = false

	# ==================== ⑫ UI：被盖住的符号画在故事情节卡上 ====================
	Game.pending_setup = {"villain": "zemo", "heroes": ["cap", "ironman"], "challenge": "none", "mode": "base"}
	var board: Control = load("res://src/ui/Board.tscn").instantiate()
	add_child(board)
	await _frames(6)
	Game.state["story"] = [
		{"type": "hero", "hero": "cap", "idx": 1, "covered": [0, 1]},
		{"type": "hero", "hero": "ironman", "idx": 1},
	]
	Events.state_changed.emit()
	await _frames(3)
	var n_marks: int = 0
	var first_w: float = 0.0
	var first_pos := Vector2.ZERO
	var seen_first := false
	for child in board._story_box.get_children():
		if child is TextureRect and (child as TextureRect).get_child_count() > 0:
			for c2 in child.get_children():
				if c2 is TextureRect and (c2 as TextureRect).texture != null:
					n_marks += 1
					if not seen_first:
						seen_first = true
						first_w = (c2 as TextureRect).size.x
						first_pos = (c2 as TextureRect).position
	_check("⑫ 被盖 2 个符号的故事情节卡上画出 2 个小危机指示物图标（未盖的卡上没有）",
		n_marks == 2, "图标数=%d" % n_marks)
	_check("⑫ 图标是「小」图标（≤10px；卡本身 46×64）", first_w > 0.0 and first_w <= 10.0, "w=%.1f" % first_w)
	_check("⑫ 图标画在卡图底部（行动符号带位置：y ≈ 卡高 85% ≈ 54px）",
		first_pos.y > 46.0 and first_pos.y < 60.0, "y=%.1f" % first_pos.y)
	_check("⑫ 图标横向落在卡内（0 <= x <= 46）",
		first_pos.x >= 0.0 and first_pos.x <= 46.0, "x=%.1f" % first_pos.x)

	print("---- RESULT ----")
	if _fail == 0:
		print("=== ZEMO TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== ZEMO TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)
