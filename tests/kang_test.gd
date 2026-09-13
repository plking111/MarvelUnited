extends Node
## 康（Kang，第一季众筹）回归测试
## 覆盖：
##   ① 数据完整性（21 反派 / 12 行动卡 / 6 威胁卡 / 生命 4-7-10 / 无邪恶计划轨道）+ 22 张切图齐全
##      —— 逐张与**卡图实测值**核对（移动/BAM/放置图案逐槽逐指示物）
##   ② VillainRules 注册（IDS / BAM / 溢出 / 效果分发）+ Setup/db 登记
##   ③ 面板 BAM 的两种情形：康在场上（所在地点每个英雄 2 伤、**其他位置**每个英雄 1 伤）
##      / 康不在场上（每个地点添加 1 个暴徒、不结算行动卡的放置图案）
##   ④ 溢出：无法添加指示物 → 该地点 +1 个危机指示物；有危机的地点失去回合结束效果
##   ⑤ 行动卡 1~6「时间大师」：康在场上 → 移出游戏；康不在场上 → 放英雄最多的地点上场（平手玩家选择）+ BAM
##   ⑥ 不在场上的连带效果：不能被攻击 / 不移动 / 行动卡放置图案不结算 / 不触发威胁到达效果
##   ⑦ 面板特别规则：英雄被 KO 时康不激活 BAM，改为打出另一张反派行动牌
##   ⑧ 3 张威胁卡：时间藏匿处（康所在地点或相邻 → 免伤）、时间悖论（满血登场）、
##      时间军队（英雄在有暴徒的地点结束回合受 1 点伤害）
##   ⑨ 联机快照带 villain_off_field
var _fail: int = 0
var _confirm_log: Array = []
var _pick_answer: int = 0
var _action_asked: int = 0

func _check(n: String, ok: bool, d: String = "") -> void:
	if ok:
		print("PASS: " + n)
	else:
		_fail += 1
		print("FAIL: %s — %s" % [n, d])

## 干净开局：清场（无威胁/无指示物/故事情节为空）、英雄满手牌未 KO、指定站位
func _prep(locs: Array = []) -> void:
	Game.setup("kang", ["cap", "ironman", "hulk"], "none", "base")
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
		h["invulnerable"] = false
		h["hand"] = [0, 1, 2, 3, 4, 5, 6, 7]
		h["discard"] = []
		h["tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
		if locs.size() > 0:
			h["location"] = int(locs[i]) if i < locs.size() else 0
	Game.state["story"] = []
	Game.state["used_tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
	Game.state["villain_off_field"] = false
	Game.state["villain_hp"] = 10
	Game.state["villain_hp_max"] = 10
	Game.state["extra_villain_card"] = 0
	Game.state["extra_villain_card_src"] = ""
	Game.state["hero_cards_played"] = 0
	Game.state["missions_completed"] = 0
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	Game.state["log"] = []

## 按卡名造一张威胁卡（与引擎 setup 里放置时一致：hp = henchman_hp）
func _mk_threat(tname: String) -> Dictionary:
	for t in DB.villain("kang")["threats"]:
		if String((t as Dictionary)["name"]) == tname:
			var d: Dictionary = (t as Dictionary).duplicate(true)
			d["hp"] = int(d.get("henchman_hp", 0))
			d["heroic_tokens"] = 0
			d["arrival_triggered"] = false
			d["_bam_done"] = false
			if d.has("clear"):
				d["clear_progress"] = []
			return d
	return {}

func _threat_idx(tname: String) -> int:
	var ts: Array = DB.villain("kang")["threats"]
	for i in range(ts.size()):
		if String((ts[i] as Dictionary)["name"]) == tname:
			return i
	return -1

func _loc_by_id(lid: String) -> int:
	for i in range(Game.LOCATION_COUNT):
		if String(Game.state["locations"][i]["id"]) == lid:
			return i
	return -1

## 找一个回合结束效果类型为 et 的地点（地点环是随机抽的，找不到返回 -1）
func _loc_with_end_effect(et: String) -> int:
	for i in range(Game.LOCATION_COUNT):
		var def: Dictionary = DB.location(String(Game.state["locations"][i]["id"]))
		if String((def["end_turn"] as Dictionary)["type"]) == et:
			return i
	return -1

func _log_has(frag: String) -> bool:
	for e in Game.state["log"]:
		if String((e as Dictionary).get("t", "")).contains(frag):
			return true
	return false

func _hand(hid: String) -> int:
	return (Game.state["heroes"][hid]["hand"] as Array).size()

func _adjacent_of(loc: int) -> Array:
	return Game._adjacent_locs(loc)

## 与 loc 不相邻、也不是 loc 本身的地点（6 地点环上一定存在）
func _far_loc(loc: int) -> int:
	var adj: Array = _adjacent_of(loc)
	for i in range(Game.LOCATION_COUNT):
		if i != loc and not adj.has(i):
			return i
	return loc

func _ready() -> void:
	Game.autopilot = true
	# 弹窗统一接管：confirm 一律"是"；手牌伤害弃最前 n 张；行动/选择弹窗返回 _pick_answer
	Events.prompt_confirm.connect(func(t: String, cb: Callable) -> void:
		_confirm_log.append(t)
		await get_tree().process_frame
		cb.call(true))
	Events.prompt_hand_card.connect(func(cb: Callable, _t: String, _hid: String, c: int) -> void:
		await get_tree().process_frame
		var out: Array = []
		for i in range(c):
			out.append(i)
		cb.call(out))
	Events.prompt_action.connect(func(rows: Array, _t: String, cb: Callable) -> void:
		_action_asked += 1
		await get_tree().process_frame
		cb.call(_pick_answer))
	Events.prompt_choice.connect(func(_o: Array, _t: String, cb: Callable) -> void:
		await get_tree().process_frame
		cb.call(_pick_answer))

	# ==================== ① 数据完整性 ====================
	_check("① 反派总数 22", DB.villains.size() == 22, "实际 %d" % DB.villains.size())
	var v: Dictionary = DB.villain("kang")
	_check("① kang 存在且 name/name_en 正确",
		not v.is_empty() and String(v.get("name", "")) == "康" and String(v.get("name_en", "")) == "KANG",
		"%s / %s" % [v.get("name", ""), v.get("name_en", "")])
	_check("① 生命值 4/7/10（卡图面板实测）",
		int(v["health"]["2"]) == 4 and int(v["health"]["3"]) == 7 and int(v["health"]["4"]) == 10,
		"%s/%s/%s" % [v["health"]["2"], v["health"]["3"], v["health"]["4"]])
	_check("① 无邪恶计划轨道（plot_track = none，恐惧轨道 0）",
		String(v["plot_track"]) == "none" and int(v["fear_track_max"]) == 0,
		"%s/%s" % [v["plot_track"], v["fear_track_max"]])
	_check("① 面板主色 #85d8ec（KANG 蓝，读自 panel.png）",
		String(v.get("color", "")) == "#85d8ec", String(v.get("color", "")))
	_check("① 12 张行动卡", (v["actions"] as Array).size() == 12, "%d" % (v["actions"] as Array).size())
	_check("① 6 张威胁卡", (v["threats"] as Array).size() == 6, "%d" % (v["threats"] as Array).size())

	# 逐张行动卡：移动值 / BAM / 是否有图案（全部来自卡图实测）
	var moves := [0, 0, 0, 0, 0, 0, 2, 0, 1, 2, 4, 5]
	var bams := [false, false, false, false, false, false, true, true, true, true, true, true]
	var has_place := [false, false, false, false, false, false, true, true, true, true, true, true]
	var all_card_ok := true
	var card_bad := ""
	for i in range(12):
		var c: Dictionary = v["actions"][i]
		if int(c["move"]) != moves[i] or bool(c["bam"]) != bams[i]:
			all_card_ok = false
			card_bad += "卡%d(移动%s/%s BAM%s/%s) " % [i + 1, c["move"], moves[i], c["bam"], bams[i]]
		if (c["place"] != null) != has_place[i]:
			all_card_ok = false
			card_bad += "卡%d图案=%s " % [i + 1, c["place"] != null]
	_check("① 12 张行动卡的 移动/BAM/有无图案 与卡图逐张一致（1~6 是万能符号卡：无数字移动、无 BAM）", all_card_ok, card_bad)
	var tm_ok := true
	var tm_bad := ""
	for i in range(6):
		var e: Variant = v["actions"][i]["effect"]
		if e == null or String((e as Dictionary)["type"]) != "kang_time_master" or String((e as Dictionary)["name"]) != "时间大师":
			tm_ok = false
			tm_bad += "卡%d " % [i + 1]
	_check("① 卡 1~6 = 效果「时间大师」(kang_time_master)（6 张卡面完全相同，逐张读图确认）", tm_ok, tm_bad)
	var pl6_ok := true
	for i in range(6, 12):
		if v["actions"][i]["effect"] != null:
			pl6_ok = false
	_check("① 卡 7~12 卡面没有效果文字（effect 为 null）", pl6_ok, "")
	# 放置图案逐格核对（卡图 + devtools/kang_scan.ps1 像素扫描交叉验证）
	var want_place := {
		7: [["thug", "thug"], ["thug"], ["thug", "thug"]],
		8: [["thug", "thug"], ["thug", "thug"], ["thug", "thug"]],
		9: [["civ", "civ"], ["civ"], ["civ", "civ"]],
		10: [["civ", "civ"], ["civ", "civ"], ["civ", "civ"]],
		11: [["civ", "civ"], ["civ", "civ"], ["civ", "civ"]],
		12: [["thug", "civ", "civ"], ["thug", "thug", "civ"], ["thug", "civ", "civ"]]
	}
	var place_ok := true
	var place_bad := ""
	for n in want_place.keys():
		var got: Array = v["actions"][int(n) - 1]["place"]
		if got == null or got.size() != 3:
			place_ok = false
			place_bad += "卡%d槽数=%s " % [n, (got as Array).size() if got != null else -1]
			continue
		for s in range(3):
			var g: Array = got[s]
			var w: Array = want_place[n][s]
			if g.size() != w.size():
				place_ok = false
				place_bad += "卡%d格%d " % [n, s + 1]
				continue
			for t in range(w.size()):
				if String(g[t]) != String(w[t]):
					place_ok = false
					place_bad += "卡%d格%d第%d个(%s/%s) " % [n, s + 1, t + 1, g[t], w[t]]
	_check("① 6 张有图案的卡（7~12）逐格指示物种类与数量与卡图一致", place_ok, place_bad)
	var totals := {7: 5, 8: 6, 9: 5, 10: 6, 11: 6, 12: 9}
	var tot_ok := true
	var tot_bad := ""
	for n in totals.keys():
		var cnt := 0
		for slot in (v["actions"][int(n) - 1]["place"] as Array):
			cnt += (slot as Array).size()
		if cnt != int(totals[n]):
			tot_ok = false
			tot_bad += "卡%d=%d(应%d) " % [n, cnt, totals[n]]
	_check("① 逐卡指示物总数 5/6/5/6/6/9（卡 8 是 6 个暴徒——docx 写成 5 个，以卡图为准）", tot_ok, tot_bad)
	var card8: Array = v["actions"][7]["place"]
	var card8_thug := 0
	for slot in card8:
		for k in (slot as Array):
			if String(k) == "thug":
				card8_thug += 1
	_check("① 卡 8 = 三格各 2 个暴徒（共 6 个，与卡图/像素扫描一致；docx 的 2/1/2 已判为抄错）",
		card8_thug == 6, "暴徒 %d 个" % card8_thug)
	var kinds_ok := true
	for n in want_place.keys():
		for slot in (v["actions"][int(n) - 1]["place"] as Array):
			for k in (slot as Array):
				if String(k) != "civ" and String(k) != "thug":
					kinds_ok = false
	_check("① 放置图案里只出现 civ / thug 两种指示物", kinds_ok, "")

	# 威胁卡逐张（6 张 = 3 种各 2 张）
	var tnames := ["时间藏匿处", "时间悖论", "时间军队"]
	var kind_ok := true
	var kind_bad := ""
	for n in tnames:
		if _threat_idx(n) < 0:
			kind_ok = false
			kind_bad += "缺%s " % n
	_check("① 3 种威胁卡（时间藏匿处/时间悖论/时间军队）都在", kind_ok, kind_bad)
	var dup_ok := true
	var dup_bad := ""
	for n in tnames:
		var c2 := 0
		for t in (v["threats"] as Array):
			if String((t as Dictionary)["name"]) == n:
				c2 += 1
		if c2 != 2:
			dup_ok = false
			dup_bad += "%s×%d " % [n, c2]
	_check("① 每种威胁卡各 2 张（6 张 = 3 种 × 2）", dup_ok, dup_bad)
	var t_ok := true
	var t_bad := ""
	for t in (v["threats"] as Array):
		var td: Dictionary = t
		var clear_n := 0
		if td.has("clear"):
			clear_n = (td["clear"] as Array).size()
		if int(td["henchman_hp"]) != 0 or bool(td["bam"]) or bool(td["arrival"]) \
				or bool(td["start_turn"]) or not bool(td["constant"]) or clear_n != 3:
			t_ok = false
			t_bad += "%s(hp%s bam%s arr%s start%s const%s clear%s) " % [td["name"],
				td["henchman_hp"], td["bam"], td["arrival"], td["start_turn"], td["constant"], clear_n]
		if String(td.get("text", "")).strip_edges() == "":
			t_ok = false
			t_bad += "%s无text " % td["name"]
	_check("① 6 张威胁卡：无生命值/无 BAM/无到达/非开始回合/constant=true/3 个英勇槽（与卡图逐张一致）", t_ok, t_bad)
	_check("① 时间藏匿处的文本写明「这个或相邻的地点」（卡面原文）",
		String(v["threats"][_threat_idx("时间藏匿处")]["text"]).contains("这个或相邻的地点"),
		String(v["threats"][_threat_idx("时间藏匿处")]["text"]))
	_check("① 时间悖论的文本写明「以满血状态进行」",
		String(v["threats"][_threat_idx("时间悖论")]["text"]).contains("满血"),
		String(v["threats"][_threat_idx("时间悖论")]["text"]))
	_check("① 时间军队的文本写明「有暴徒的位置结束他们的回合」（卡面原文）",
		String(v["threats"][_threat_idx("时间军队")]["text"]).contains("有暴徒") and String(v["threats"][_threat_idx("时间军队")]["text"]).contains("结束"),
		String(v["threats"][_threat_idx("时间军队")]["text"]))
	var st_ok := true
	var st_bad := ""
	for vid in DB.villains.keys():
		for t in ((DB.villains[vid] as Dictionary).get("threats", []) as Array):
			if bool((t as Dictionary).get("start_turn", false)) and bool((t as Dictionary).get("constant", false)):
				st_ok = false
				st_bad += "%s/%s " % [vid, (t as Dictionary).get("name", "")]
	_check("① 全库口径：没有威胁卡同时是 start_turn 与 constant", st_ok, st_bad)
	_check("① 面板 BAM 文案写明「对其他位置的每个英雄」（卡面面板原文；docx 写「相邻两个地点」已判为不符）",
		String(v["bam"]).contains("其他位置"), String(v["bam"]))
	_check("① 面板溢出文案写明「添加 1 个危机指示物」与「失去其回合结束效果」",
		String(v["overflow"]).contains("危机指示物") and String(v["overflow"]).contains("回合结束效果"), String(v["overflow"]))
	_check("① 面板特别规则写明「英雄被 KO 时康不激活 BAM、改为打出另一张反派行动牌」",
		String(v["special"]).contains("KO") and String(v["special"]).contains("BAM"), String(v["special"]))

	# 切图齐全（22 张）
	var miss: Array = []
	for i in range(1, 13):
		if not FileAccess.file_exists("res://assets/cards/villains/kang/action_%02d.png" % i):
			miss.append("action_%02d" % i)
	for i in range(1, 7):
		if not FileAccess.file_exists("res://assets/cards/villains/kang/threat_%02d.png" % i):
			miss.append("threat_%02d" % i)
	for extra in ["back.png", "panel.png", "panel_back.png", "threat_back.png"]:
		if not FileAccess.file_exists("res://assets/cards/villains/kang/" + String(extra)):
			miss.append(extra)
	_check("① 22 张切图齐全（12 行动 + 6 威胁 + back/panel/panel_back/threat_back）", miss.is_empty(), str(miss))

	# ==================== ② 注册 ====================
	_check("② VillainRules.IDS 含 kang 且数量与 DB.villains 一致",
		VillainRules.IDS.has("kang") and VillainRules.IDS.size() == DB.villains.size(),
		"IDS=%d DB=%d" % [VillainRules.IDS.size(), DB.villains.size()])
	var setup_script: Variant = load("res://src/ui/Setup.gd")
	if setup_script != null:
		_check("② Setup.VILLAIN_SORT 含 kang（K）", String(setup_script.VILLAIN_SORT.get("kang", "")) == "K",
			String(setup_script.VILLAIN_SORT.get("kang", "<无>")))
		_check("② Setup.VILLAIN_EXP 含 kang（第一季众筹）", String(setup_script.VILLAIN_EXP.get("kang", "")) == "第一季众筹",
			String(setup_script.VILLAIN_EXP.get("kang", "<无>")))
	else:
		_check("② 加载 Setup.gd 失败（跳过排序/扩展登记断言）", false, "load 返回 null")

	# ==================== ③ 面板 BAM ====================
	# ③a 康在场上：所在地点每个英雄 2 伤、其他位置（不只是相邻）每个英雄 1 伤
	_prep([0, 0, 3])
	var far: int = _far_loc(0)
	Game.state["heroes"]["hulk"]["location"] = far
	Game.state["villain_off_field"] = false
	Game.state["villain_pos"] = 0
	await Game._trigger_panel_bam()
	_check("③a 康所在地点的每个英雄受到 2 点伤害（cap/ironman 各弃 2 张手牌）",
		_hand("cap") == 6 and _hand("ironman") == 6,
		"cap=%d ironman=%d" % [_hand("cap"), _hand("ironman")])
	_check("③a 「其他位置」的每个英雄受到 1 点伤害（不相邻的 %d 号地点也挨打）" % far,
		_hand("hulk") == 7, "hulk=%d（应 7）" % _hand("hulk"))
	_check("③a 不相邻地点确实不是康所在地点的相邻地点（口径前提）",
		not _adjacent_of(0).has(far), "相邻=%s far=%d" % [str(_adjacent_of(0)), far])

	# ③b 康不在场上：每个地点 +1 个暴徒，英雄不受伤害
	_prep([0, 0, 3])
	Game.state["villain_off_field"] = true
	Game.state["villain_pos"] = -1
	var all_one_thug := true
	await Game._trigger_panel_bam()
	for i in range(Game.LOCATION_COUNT):
		if int(Game.state["locations"][i]["thug"]) != 1:
			all_one_thug = false
	_check("③b 康不在场上：每个地点添加 1 个暴徒", all_one_thug,
		str(Game.state["locations"].map(func(l): return int(l["thug"]))))
	_check("③b 康不在场上：不对任何英雄造成伤害",
		_hand("cap") == 8 and _hand("ironman") == 8 and _hand("hulk") == 8,
		"%d/%d/%d" % [_hand("cap"), _hand("ironman"), _hand("hulk")])
	_check("③b 康不在场上：villain_pos = -1（没有地点）", int(Game.state["villain_pos"]) == -1, "%d" % int(Game.state["villain_pos"]))

	# ==================== ④ 溢出 → 危机指示物 ====================
	_prep([5, 5, 5])
	Game.state["phase"] = "villain"
	await VillainRules.on_overflow(Game, "kang", "thug", 2, 1)
	_check("④ 溢出：在放不下的地点添加 1 个危机指示物",
		int(Game.state["locations"][2]["crisis"]) == 1, "crisis=%d" % int(Game.state["locations"][2]["crisis"]))
	await VillainRules.on_overflow(Game, "kang", "thug", 2, 5)
	_check("④ 一次结算事件在同一地点只加 1 个（面板写「1 个或多个」→ 忽略 count）",
		int(Game.state["locations"][2]["crisis"]) == 2, "crisis=%d" % int(Game.state["locations"][2]["crisis"]))

	# ④b 有危机指示物的地点失去回合结束效果
	# （把 2 号地点的 id 强制设成时代广场 = 营救平民地点，避免地点环随机导致这条规则测不到）
	_prep([2, 2, 2])
	Game.state["locations"][2]["id"] = "times_square"
	Game.state["locations"][2]["civ"] = 1
	Game.state["locations"][2]["crisis"] = 1
	Game.state["phase"] = "hero_end"
	Game.state["current_hero"] = 0
	await Game.end_turn()
	_check("④b 有危机指示物的地点失去回合结束效果（时代广场的营救平民没有发生）",
		int(Game.state["locations"][2]["civ"]) == 1 and _log_has("无法使用该地点的回合结束效果"),
		"civ=%d 日志命中=%s" % [int(Game.state["locations"][2]["civ"]), str(_log_has("无法使用该地点的回合结束效果"))])
	_prep([2, 2, 2])
	Game.state["locations"][2]["id"] = "times_square"
	Game.state["locations"][2]["civ"] = 1
	Game.state["locations"][2]["crisis"] = 0
	Game.state["phase"] = "hero_end"
	Game.state["current_hero"] = 0
	await Game.end_turn()
	_check("④b 对照：没有危机指示物时该地点的回合结束效果照常执行（营救 1 名平民）",
		int(Game.state["locations"][2]["civ"]) == 0,
		"civ=%d" % int(Game.state["locations"][2]["civ"]))

	# ==================== ⑤ 时间大师（行动卡 1~6） ====================
	_prep([4, 4, 5])
	Game.state["villain_off_field"] = false
	Game.state["villain_pos"] = 1
	await VillainRules.resolve_effect(Game, v["actions"][0]["effect"])
	_check("⑤ 康在场上 → 「时间大师」把他移出游戏（villain_off_field = true）",
		VillainRules.kang_off_field(Game), str(Game.state["villain_off_field"]))
	_check("⑤ 康不在场上时没有地点（villain_pos = -1）", int(Game.state["villain_pos"]) == -1,
		"%d" % int(Game.state["villain_pos"]))

	# ⑤b 不在场上 → 放到英雄最多的地点（唯一最大，不弹窗）
	_prep([4, 4, 5])
	Game.state["villain_off_field"] = true
	Game.state["villain_pos"] = -1
	_action_asked = 0
	var before_hand: int = _hand("cap")
	await VillainRules.resolve_effect(Game, v["actions"][0]["effect"])
	_check("⑤b 康不在场上 → 回到「英雄最多」的地点 4 上场",
		not VillainRules.kang_off_field(Game) and int(Game.state["villain_pos"]) == 4,
		"off=%s pos=%d" % [str(Game.state["villain_off_field"]), int(Game.state["villain_pos"])])
	_check("⑤b 落点唯一最大时不弹窗（英雄数量没有并列）", _action_asked == 0, "弹窗 %d 次" % _action_asked)
	_check("⑤b 上场后立刻结算 BAM（所在地点英雄受 2 伤 → 弃 2 张手牌）",
		_hand("cap") == before_hand - 2, "%d → %d" % [before_hand, _hand("cap")])

	# ⑤c 平手 → 玩家选择
	_prep([1, 2, 3])
	Game.state["villain_off_field"] = true
	Game.state["villain_pos"] = -1
	_action_asked = 0
	_pick_answer = 1   # 并列候选中选第 2 个
	Game.autopilot = false   # autopilot 下 _ask_action 直接返回 0，必须关掉才能真正走弹窗
	await VillainRules.resolve_effect(Game, v["actions"][0]["effect"])
	Game.autopilot = true
	_check("⑤c 英雄数量并列时由玩家选择（回答第 2 个候选 → 落到 2 号地点）",
		_action_asked >= 1 and int(Game.state["villain_pos"]) == 2,
		"弹窗=%d pos=%d" % [_action_asked, int(Game.state["villain_pos"])])
	_pick_answer = 0

	# ⑤d 时间悖论在场 → 以满血状态登场
	_prep([4, 4, 5])
	Game.state["locations"][1]["threat"] = _mk_threat("时间悖论")
	Game.state["villain_off_field"] = true
	Game.state["villain_pos"] = -1
	Game.state["villain_hp"] = 3
	await VillainRules.resolve_effect(Game, v["actions"][0]["effect"])
	_check("⑤d 「时间悖论」在场 → 康以满血（10）进入游戏",
		int(Game.state["villain_hp"]) == 10, "hp=%d" % int(Game.state["villain_hp"]))
	_prep([4, 4, 5])
	Game.state["villain_off_field"] = true
	Game.state["villain_pos"] = -1
	Game.state["villain_hp"] = 3
	await VillainRules.resolve_effect(Game, v["actions"][0]["effect"])
	_check("⑤d 没有「时间悖论」时保持当前血量（不会自动回满）",
		int(Game.state["villain_hp"]) == 3, "hp=%d" % int(Game.state["villain_hp"]))

	# ==================== ⑥ 不在场上的连带效果 ====================
	_prep([0, 0, 3])
	Game.state["missions_completed"] = 2
	Game.state["villain_off_field"] = false
	Game.state["villain_pos"] = 0
	_check("⑥ 前置：康在场上时 0 号地点的敌人清单里有 villain",
		Game._enemy_targets_at(0).has("villain"), str(Game._enemy_targets_at(0)))
	Game.state["villain_off_field"] = true
	Game.state["villain_pos"] = -1
	_check("⑥ 康不在场上时任何地点都不能攻击到他（villain_pos = -1 → 目标清单里没有 villain）",
		not Game._enemy_targets_at(0).has("villain"), str(Game._enemy_targets_at(0)))
	# ⑥b 不移动
	var pos_before: int = int(Game.state["villain_pos"])
	await Game._do_villain_move(3)
	_check("⑥b 康不在场上时行动卡的移动不结算（位置仍是 -1，不会因此回到场上）",
		int(Game.state["villain_pos"]) == pos_before and VillainRules.kang_off_field(Game),
		"pos=%d" % int(Game.state["villain_pos"]))
	# ⑥c 行动卡的放置图案整张不结算
	for l in Game.state["locations"]:
		l["civ"] = 0
		l["thug"] = 0
	await Game._do_placement([["civ", "civ"], ["civ", "civ"], ["civ", "civ"]])
	var quiet := true
	for l in Game.state["locations"]:
		if int(l["civ"]) != 0 or int(l["thug"]) != 0:
			quiet = false
	_check("⑥c 康不在场上时行动卡所示的添加平民/暴徒不结算（面板 BAM 文字）", quiet,
		str(Game.state["locations"].map(func(l): return [int(l["civ"]), int(l["thug"])])))
	# ⑥d 一整个反派回合：只结算"每个位置 1 个暴徒"，不结算卡 11 的民民/民民/民民
	_prep([0, 0, 3])
	Game.state["villain_off_field"] = true
	Game.state["villain_pos"] = -1
	Game.state["master_deck"] = [10]   # 卡 11 = 移动4 + BAM + 民民/民民/民民
	await Game._run_villain_turn()
	var turn_ok := true
	var turn_bad := ""
	for i in range(Game.LOCATION_COUNT):
		if int(Game.state["locations"][i]["thug"]) != 1:
			turn_ok = false
			turn_bad += "%d号暴徒=%d " % [i, int(Game.state["locations"][i]["thug"])]
		if int(Game.state["locations"][i]["civ"]) != 0:
			turn_ok = false
			turn_bad += "%d号平民=%d " % [i, int(Game.state["locations"][i]["civ"])]
	_check("⑥d 康不在场时一整回合：每地点 +1 暴徒（BAM），卡 11 的 6 个平民一个都没放", turn_ok, turn_bad)
	_check("⑥d 康不在场时整回合结束后仍在场外（没有被行动卡带回场上）",
		VillainRules.kang_off_field(Game) and int(Game.state["villain_pos"]) == -1,
		"off=%s pos=%d" % [str(Game.state["villain_off_field"]), int(Game.state["villain_pos"])])

	# ==================== ⑦ 特别规则：英雄被 KO 时不激活 BAM ====================
	_prep([0, 0, 3])
	Game.state["villain_off_field"] = false
	Game.state["villain_pos"] = 0
	Game.state["extra_villain_card"] = 0
	Game.state["heroes"]["cap"]["hand"] = []
	await Game._ko_hero("cap")
	_check("⑦ 英雄被 KO：康不激活 BAM，改为打出另一张反派行动牌（extra_villain_card +1）",
		int(Game.state["extra_villain_card"]) == 1, "%d" % int(Game.state["extra_villain_card"]))
	_check("⑦ 该次 KO 没有对同地点其它英雄造成 BAM 伤害（ironman 手牌不变）",
		_hand("ironman") == 8, "ironman=%d" % _hand("ironman"))
	_check("⑦ 被 KO 的英雄标记正确", bool(Game.state["heroes"]["cap"]["ko"]), str(Game.state["heroes"]["cap"]["ko"]))

	# ==================== ⑧ 威胁卡 ====================
	# ⑧a 时间藏匿处：康在该威胁卡所在地点 → 免伤
	_prep([4, 4, 5])
	Game.state["missions_completed"] = 2
	Game.state["villain_off_field"] = false
	Game.state["villain_pos"] = 4
	Game.state["locations"][4]["threat"] = _mk_threat("时间藏匿处")
	await Game._perform_attack_at(4, "villain", "cap")
	_check("⑧a 时间藏匿处：康在该威胁卡所在地点 → 攻击不造成伤害（生命 10 不变）",
		int(Game.state["villain_hp"]) == 10, "hp=%d" % int(Game.state["villain_hp"]))
	# ⑧b 康在与该卡相邻的地点 → 免伤
	var hide_loc: int = 4
	var nb: int = int(_adjacent_of(hide_loc)[0])
	_prep([nb, nb, 5])
	Game.state["missions_completed"] = 2
	Game.state["villain_off_field"] = false
	Game.state["villain_pos"] = nb
	Game.state["locations"][hide_loc]["threat"] = _mk_threat("时间藏匿处")
	await Game._perform_attack_at(nb, "villain", "cap")
	_check("⑧b 时间藏匿处：康在与该卡相邻的地点（%d → %d）→ 免伤" % [nb, hide_loc],
		int(Game.state["villain_hp"]) == 10, "hp=%d" % int(Game.state["villain_hp"]))
	# ⑧c 康在不相邻的地点 → 正常受伤
	var hide2: int = _far_loc(nb)
	_prep([nb, nb, 5])
	Game.state["missions_completed"] = 2
	Game.state["villain_off_field"] = false
	Game.state["villain_pos"] = nb
	Game.state["locations"][hide2]["threat"] = _mk_threat("时间藏匿处")
	await Game._perform_attack_at(nb, "villain", "cap")
	_check("⑧c 时间藏匿处：康在不相邻的地点（卡在 %d，康在 %d）→ 正常受到 1 点伤害" % [hide2, nb],
		int(Game.state["villain_hp"]) == 9, "hp=%d" % int(Game.state["villain_hp"]))
	# ⑧d 时间军队：英雄在有暴徒的地点结束回合受 1 点伤害
	# （该地点放开一张威胁卡，屏蔽掉地点自身的回合结束效果，隔离出时间军队这一条的伤害）
	_prep([2, 3, 4])
	Game.state["locations"][0]["threat"] = _mk_threat("时间军队")
	Game.state["locations"][2]["threat"] = _mk_threat("时间藏匿处")
	Game.state["locations"][2]["thug"] = 1
	var hb: int = _hand("cap")
	Game.state["phase"] = "hero_end"
	Game.state["current_hero"] = 0
	await Game.end_turn()
	_check("⑧d 时间军队：英雄在有暴徒的地点结束回合 → 受 1 点伤害（弃 1 张手牌）",
		_hand("cap") == hb - 1, "%d → %d" % [hb, _hand("cap")])
	# ⑧e 没有暴徒 → 不受伤
	_prep([2, 3, 4])
	Game.state["locations"][0]["threat"] = _mk_threat("时间军队")
	Game.state["locations"][2]["threat"] = _mk_threat("时间藏匿处")
	Game.state["locations"][2]["thug"] = 0
	hb = _hand("cap")
	Game.state["phase"] = "hero_end"
	Game.state["current_hero"] = 0
	await Game.end_turn()
	_check("⑧e 时间军队：英雄在没有暴徒的地点结束回合 → 不受伤",
		_hand("cap") == hb, "%d → %d" % [hb, _hand("cap")])
	# ⑧f 两张时间军队 → 每张各 1 点
	_prep([2, 3, 4])
	Game.state["locations"][0]["threat"] = _mk_threat("时间军队")
	Game.state["locations"][1]["threat"] = _mk_threat("时间军队")
	Game.state["locations"][2]["threat"] = _mk_threat("时间藏匿处")
	Game.state["locations"][2]["thug"] = 1
	hb = _hand("cap")
	var army: int = VillainRules.kang_time_army_damage(Game)
	Game.state["phase"] = "hero_end"
	Game.state["current_hero"] = 0
	await Game.end_turn()
	_check("⑧f 时间军队 ×2 在场：伤害按生效张数累计（各 1 点 → 共 2 点）",
		army == 2 and _hand("cap") == hb - 2, "army=%d %d → %d" % [army, hb, _hand("cap")])
	# ⑧g 康不在场上时时间军队仍生效（该卡只看"有没有暴徒"）
	_prep([2, 3, 4])
	Game.state["villain_off_field"] = true
	Game.state["villain_pos"] = -1
	Game.state["locations"][0]["threat"] = _mk_threat("时间军队")
	Game.state["locations"][2]["threat"] = _mk_threat("时间藏匿处")
	Game.state["locations"][2]["thug"] = 1
	hb = _hand("cap")
	Game.state["phase"] = "hero_end"
	Game.state["current_hero"] = 0
	await Game.end_turn()
	_check("⑧g 康不在场上时「时间军队」照常生效（卡面只说「在有暴徒的位置结束回合」）",
		_hand("cap") == hb - 1, "%d → %d" % [hb, _hand("cap")])
	# ⑧h setup 时引擎给每个地点各放 1 张威胁卡（康的 6 张威胁正好铺满）
	Game.setup("kang", ["cap", "ironman", "hulk"], "none", "base")
	var setup_threats := 0
	for l in Game.state["locations"]:
		if l["threat"] != null:
			setup_threats += 1
	_check("⑧h setup 后每个地点各 1 张威胁卡（引擎通用口径，康的 6 张威胁正好铺满）",
		setup_threats == 6 and Game.state["locations"].size() == 6, "%d" % setup_threats)

	# ==================== ⑨ 联机快照 ====================
	_prep([0, 0, 3])
	Game.state["villain_off_field"] = true
	Game.state["villain_pos"] = -1
	Net.active = true
	Net.is_host = false
	Net.my_peer = 2
	Net.seats = [
		{"peer": 1, "name": "房主", "hero": "cap", "villain": "", "locs": [], "ready": false},
		{"peer": 2, "name": "我", "hero": "cap", "villain": "", "locs": [], "ready": false},
	]
	var vis: Dictionary = Net.visible_state_for("cap")
	_check("⑨ 联机快照下发 villain_off_field 与 villain_pos（客户端能看到康不在场上）",
		bool(vis.get("villain_off_field", false)) and int(vis.get("villain_pos", 0)) == -1,
		"off=%s pos=%s" % [vis.get("villain_off_field", "<无>"), vis.get("villain_pos", "<无>")])
	Net.active = false

	# ==================== ⑩ UI：康不在场上时反派面板的标注 ====================
	# （棋盘上不再画他的图标，所以必须在面板上给玩家一个"不在场上"的提示）
	Game.pending_setup = {"villain": "kang", "heroes": ["cap", "ironman"], "challenge": "none"}
	var board_scene: PackedScene = load("res://src/ui/Board.tscn")
	var board: Control = board_scene.instantiate()
	add_child(board)
	for _bi in range(4):
		await get_tree().process_frame
	Game.state["villain_off_field"] = false
	board._refresh_villain()
	_check("⑩ 康在场上时反派面板生命值后没有「不在场上」标注",
		not String(board._hp_label.text).contains("不在场上"), String(board._hp_label.text))
	Game.state["villain_off_field"] = true
	board._refresh_villain()
	_check("⑩ 康不在场上时反派面板标注「（不在场上）」",
		String(board._hp_label.text).contains("不在场上"), String(board._hp_label.text))
	board.queue_free()
	await get_tree().process_frame

	print("---- RESULT ----")
	if _fail == 0:
		print("=== KANG TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== KANG TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)
