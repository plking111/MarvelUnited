extends Node
## 摩多克（M.O.D.O.K.，第一季众筹）回归测试
## 覆盖：
##   ① 数据完整性（20 反派 / 12 行动卡 / 6 威胁卡 / 生命 4-7-10 / 无邪恶计划轨道）+ 22 张切图齐全
##      —— 逐张与**卡图实测值**核对（移动/BAM/放置图案分组/威胁卡生命与槽位）
##   ② VillainRules 注册（IDS / BAM / 溢出 / 效果分发）
##   ③ 面板 BAM：翻转 1 张英雄卡 = 把**最接近故事情节开始**的正面朝上英雄卡翻为正面朝下
##   ④ 行动卡 10/11「意识转移」：正面朝上在故事情节中 → BAM 之后额外翻转（每张各 1 张）
##   ⑤ 面板溢出：1 个或多个放不下 → 翻转 1 张（一次结算只结算一次，忽略 count）
##   ⑥ 行动卡 1「制备」+ 特殊设置：必定是第一张行动卡；效果把摩多克移到英雄起始地点
##   ⑦ 行动卡 12「超级天才智能」：下一个反派回合多打出 1 张行动卡
##   ⑧ 6 张威胁卡：到达效果（能量投射/科技共情）、BAM（活体激光/变色龙/斑点）、
##      持续效果（心灵异能：在此地点开始回合的英雄必须面朝下出牌）
##   ⑨ 面板恶毒的阴谋：故事情节中所有英雄卡都面朝下 → 英雄失败
##   ⑩ 放置图案按 [顺时针相邻 / 本地 / 逆时针相邻] 三槽落位（卡 3~9）
##   ⑪ 面朝下的英雄卡不给下一位英雄行动（继承被跳过）
##   ⑫ 联机快照带 face_down（客户端也能看到被翻面的卡）
var _fail: int = 0
var _confirm_log: Array = []
var _confirm_answer: bool = true

func _check(n: String, ok: bool, d: String = "") -> void:
	if ok:
		print("PASS: " + n)
	else:
		_fail += 1
		print("FAIL: %s — %s" % [n, d])

func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

## 干净开局：清场（无威胁/无指示物/故事情节为空）、英雄满手牌未 KO、指定站位
func _prep(locs: Array = []) -> void:
	Game.setup("modok", ["cap", "ironman", "hulk"], "none", "base")
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
	Game.state["villain_extra_card_next_turn"] = 0
	Game.state["extra_villain_card"] = 0
	Game.state["forced_face_down_hero"] = ""
	Game.state["phase"] = "hero_actions"
	Game.state["villain_hp"] = 10
	Game.state["log"] = []

## 所有英雄卡都面朝上、且都不是面朝下的"填充"故事情节（用于判负/翻转类断言）
func _seed_story(n: int) -> void:
	var ids: Array = Game.state["hero_ids"]
	for i in range(n):
		Game.state["story"].append({"type": "hero", "hero": String(ids[i % ids.size()]), "idx": i % 8})

func _faceup_count() -> int:
	var n := 0
	for e in Game.state["story"]:
		if String(e.get("type", "")) == "hero" and not bool(e.get("face_down", false)):
			n += 1
	return n

func _facedown_count() -> int:
	var n := 0
	for e in Game.state["story"]:
		if String(e.get("type", "")) == "hero" and bool(e.get("face_down", false)):
			n += 1
	return n

## 按 DB 数据造一张威胁卡（与引擎放置时一致：hp = henchman_hp）
func _mk_threat(idx: int) -> Dictionary:
	var t: Dictionary = (DB.villain("modok")["threats"][idx] as Dictionary).duplicate(true)
	t["hp"] = int(t.get("henchman_hp", 0))
	t["heroic_tokens"] = 0
	t["arrival_triggered"] = false
	t["_bam_done"] = false
	if t.has("clear"):
		t["clear_progress"] = []
	return t

func _threat_idx(tname: String) -> int:
	var ts: Array = DB.villain("modok")["threats"]
	for i in range(ts.size()):
		if String((ts[i] as Dictionary)["name"]) == tname:
			return i
	return -1

## 找一张底部正好有 n 个 sym 符号的英雄卡（找不到返回 -1）
func _card_with_symbol_count(hid: String, sym: String, n: int) -> int:
	var cs: Array = DB.hero_cards(hid)
	for i in range(cs.size()):
		var k := 0
		for s in (cs[i]["symbols"] as Array):
			if String(s) == sym:
				k += 1
		if k == n:
			return i
	return -1

func _loc_with_slots(n: int) -> int:
	for i in range(Game.LOCATION_COUNT):
		var l: Dictionary = Game.state["locations"][i]
		if bool(l.get("destroyed", false)):
			continue
		if int(DB.location(String(l["id"]))["slots"]) >= n:
			return i
	return 0

func _ready() -> void:
	Game.autopilot = true
	# 弹窗统一接管：confirm 按 _confirm_answer 回答；手牌伤害弃最前 n 张
	Events.prompt_confirm.connect(func(t: String, cb: Callable) -> void:
		_confirm_log.append(t)
		await get_tree().process_frame
		cb.call(_confirm_answer))
	Events.prompt_hand_card.connect(func(cb: Callable, _t: String, _hid: String, c: int) -> void:
		await get_tree().process_frame
		var out: Array = []
		for i in range(c):
			out.append(i)
		cb.call(out))
	Events.prompt_action.connect(func(rows: Array, _t: String, cb: Callable) -> void:
		await get_tree().process_frame
		cb.call(0))
	Events.prompt_choice.connect(func(_o: Array, _t: String, cb: Callable) -> void:
		await get_tree().process_frame
		cb.call(0))

	# ==================== ① 数据完整性 ====================
	_check("① 反派总数 20", DB.villains.size() == 20, "实际 %d" % DB.villains.size())
	var v: Dictionary = DB.villain("modok")
	_check("① modok 存在且 name/name_en 正确",
		not v.is_empty() and String(v.get("name", "")) == "摩多克" and String(v.get("name_en", "")) == "M.O.D.O.K.",
		"%s / %s" % [v.get("name", ""), v.get("name_en", "")])
	_check("① 生命值 4/7/10（卡图面板实测）",
		int(v["health"]["2"]) == 4 and int(v["health"]["3"]) == 7 and int(v["health"]["4"]) == 10,
		"%s/%s/%s" % [v["health"]["2"], v["health"]["3"], v["health"]["4"]])
	_check("① 无邪恶计划轨道（plot_track = none，恐惧轨道 0；失败条件由 special 描述）",
		String(v["plot_track"]) == "none" and int(v["fear_track_max"]) == 0,
		"%s/%s" % [v["plot_track"], v["fear_track_max"]])
	_check("① 12 张行动卡", (v["actions"] as Array).size() == 12, "%d" % (v["actions"] as Array).size())
	_check("① 6 张威胁卡", (v["threats"] as Array).size() == 6, "%d" % (v["threats"] as Array).size())

	# 逐张行动卡：移动值 / BAM / 是否有图案（全部来自卡图实测）
	var moves := [0, 0, 1, 2, 4, 3, 2, 1, 5, 3, 3, 0]
	var bams := [false, true, false, true, true, true, true, false, false, true, true, true]
	var has_place := [false, false, true, true, true, true, true, true, true, false, false, false]
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
	_check("① 12 张行动卡的 移动/BAM/有无图案 与卡图逐张一致（卡 3/8/9 无 BAM）", all_card_ok, card_bad)
	_check("① 卡 1 = 移动0 + 无BAM + 效果「制备」（卡面万能符号，移动写在本卡文字里）",
		int(v["actions"][0]["move"]) == 0 and not bool(v["actions"][0]["bam"])
		and v["actions"][0]["effect"] != null
		and String(v["actions"][0]["effect"]["type"]) == "modok_preparation", str(v["actions"][0]["effect"]))
	_check("① 卡 10/11 = 移动3 + BAM + 「意识转移」",
		int(v["actions"][9]["move"]) == 3 and bool(v["actions"][9]["bam"])
		and String(v["actions"][9]["effect"]["type"]) == "modok_mind_transfer"
		and int(v["actions"][10]["move"]) == 3 and String(v["actions"][10]["effect"]["type"]) == "modok_mind_transfer", "")
	_check("① 卡 12 = 移动0 + BAM + 「超级天才智能」",
		int(v["actions"][11]["move"]) == 0 and bool(v["actions"][11]["bam"])
		and String(v["actions"][11]["effect"]["type"]) == "modok_superior_intellect", "")
	# 放置图案逐格核对：3/4/5 = 暴暴1-2-1；6/7/8 = 民民1-2-1；9 = 民+暴 ×3
	var want_place := {
		3: [["thug"], ["thug", "thug"], ["thug"]],
		4: [["thug"], ["thug", "thug"], ["thug"]],
		5: [["thug"], ["thug", "thug"], ["thug"]],
		6: [["civ"], ["civ", "civ"], ["civ"]],
		7: [["civ"], ["civ", "civ"], ["civ"]],
		8: [["civ"], ["civ", "civ"], ["civ"]],
		9: [["thug", "civ"], ["thug", "civ"], ["thug", "civ"]]
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
					place_bad += "卡%d格%d第%d个 " % [n, s + 1, t + 1]
	_check("① 有图案的 7 张卡（3~9）逐格指示物种类与数量与卡图一致", place_ok, place_bad)
	var kinds_ok := true
	for n in want_place.keys():
		for slot in (v["actions"][int(n) - 1]["place"] as Array):
			for k in (slot as Array):
				if String(k) != "civ" and String(k) != "thug":
					kinds_ok = false
	_check("① 放置图案里只出现 civ / thug 两种指示物", kinds_ok, "")

	# 威胁卡逐张
	var t_exp := {
		"能量投射": {"hp": 0, "bam": false, "arrival": true, "start": false, "clear": 3},
		"活体激光": {"hp": 4, "bam": true, "arrival": false, "start": false, "clear": 0},
		"科技共情": {"hp": 0, "bam": false, "arrival": true, "start": false, "clear": 3},
		"变色龙": {"hp": 4, "bam": true, "arrival": false, "start": false, "clear": 0},
		"心灵异能": {"hp": 0, "bam": false, "arrival": false, "start": true, "clear": 3},
		"斑点": {"hp": 4, "bam": true, "arrival": false, "start": false, "clear": 0}
	}
	var t_ok := true
	var t_bad := ""
	for tname in t_exp.keys():
		var idx: int = _threat_idx(tname)
		if idx < 0:
			t_ok = false
			t_bad += "缺%s " % tname
			continue
		var t: Dictionary = v["threats"][idx]
		var e: Dictionary = t_exp[tname]
		var clear_n := 0
		if t.has("clear"):
			clear_n = (t["clear"] as Array).size()
		if int(t["henchman_hp"]) != int(e["hp"]) or bool(t["bam"]) != bool(e["bam"]) \
				or bool(t["arrival"]) != bool(e["arrival"]) or bool(t["start_turn"]) != bool(e["start"]) \
				or clear_n != int(e["clear"]):
			t_ok = false
			t_bad += "%s(hp%s/%s bam%s/%s arr%s/%s start%s/%s clear%s/%s) " % [tname,
				t["henchman_hp"], e["hp"], t["bam"], e["bam"], t["arrival"], e["arrival"],
				t["start_turn"], e["start"], clear_n, e["clear"]]
		if String(t.get("text", "")).strip_edges() == "":
			t_ok = false
			t_bad += "%s无text " % tname
	_check("① 6 张威胁卡的生命值/BAM/到达/开始回合/英勇槽数 与卡图逐张一致", t_ok, t_bad)
	_check("① 心灵异能 = start_turn + constant=false（与既有 6 张 start_turn 威胁卡同型：奥创病毒/折磨摧残/太空伏击；constant=true 只用于\"只要…\"被动卡）",
		bool(v["threats"][_threat_idx("心灵异能")]["start_turn"])
		and not bool(v["threats"][_threat_idx("心灵异能")]["constant"]), str(v["threats"][_threat_idx("心灵异能")]["constant"]))
	var st_ok := true
	var st_bad := ""
	for vid in DB.villains.keys():
		var ts: Array = (DB.villains[vid] as Dictionary).get("threats", [])
		for t in ts:
			if bool((t as Dictionary).get("start_turn", false)) and bool((t as Dictionary).get("constant", false)):
				st_ok = false
				st_bad += "%s/%s " % [vid, (t as Dictionary).get("name", "")]
	_check("① 全库口径：没有威胁卡同时是 start_turn 与 constant（那两种是互斥的卡面排版）", st_ok, st_bad)
	_check("① 无生命值的 3 张威胁卡都带 clear=[heroic×3]（卡面底部 3 个英勇槽）",
		(v["threats"][_threat_idx("能量投射")]["clear"] as Array) == ["heroic", "heroic", "heroic"]
		and (v["threats"][_threat_idx("科技共情")]["clear"] as Array) == ["heroic", "heroic", "heroic"]
		and (v["threats"][_threat_idx("心灵异能")]["clear"] as Array) == ["heroic", "heroic", "heroic"], "")

	# 切图齐全（22 张）
	var miss: Array = []
	for i in range(1, 13):
		var p1 := "res://assets/cards/villains/modok/action_%02d.png" % i
		if not FileAccess.file_exists(p1):
			miss.append(p1)
	for i in range(1, 7):
		var p2 := "res://assets/cards/villains/modok/threat_%02d.png" % i
		if not FileAccess.file_exists(p2):
			miss.append(p2)
	for extra in ["back.png", "panel.png", "panel_back.png", "threat_back.png"]:
		var p3: String = "res://assets/cards/villains/modok/" + String(extra)
		if not FileAccess.file_exists(p3):
			miss.append(p3)
	_check("① 22 张切图齐全（12 行动 + 6 威胁 + back/panel/panel_back/threat_back）", miss.is_empty(), str(miss))

	# ==================== ② 注册 ====================
	_check("② VillainRules.IDS 含 modok 且数量与 DB.villains 一致",
		VillainRules.IDS.has("modok") and VillainRules.IDS.size() == DB.villains.size(),
		"IDS=%d DB=%d" % [VillainRules.IDS.size(), DB.villains.size()])

	# ==================== ③ 面板 BAM：翻转最靠前的正面朝上英雄卡 ====================
	_prep()
	_seed_story(3)
	Game.state["villain_pos"] = 2
	await VillainRules.on_bam(Game, "modok")
	_check("③ BAM 只翻转 1 张英雄卡", _facedown_count() == 1, "翻面=%d" % _facedown_count())
	_check("③ BAM 翻的是**最接近故事情节开始**的那张（story[0]）",
		bool(Game.state["story"][0].get("face_down", false))
		and not bool(Game.state["story"][1].get("face_down", false))
		and not bool(Game.state["story"][2].get("face_down", false)), "")
	var syms_after: Array = Game._last_hero_card_symbols()
	# _last_hero_card_symbols() 从 story[size-2] 往前找（最后一张视为"当前英雄刚打出的"），
	# 所以 3 张英雄卡时应返回 story[1]（ironman idx1）的符号
	var expect_syms: Array = DB.hero_cards("ironman")[1]["symbols"]
	_check("③ 未被翻面的英雄卡照常提供行动符号",
		syms_after == expect_syms, "%s vs %s" % [syms_after, expect_syms])
	# 依次翻转：每次都推进到"下一个最靠前的正面朝上"
	await VillainRules.on_bam(Game, "modok")
	await VillainRules.on_bam(Game, "modok")
	_check("③ 连续 3 次 BAM 后 3 张英雄卡全部面朝下（翻转从最早往后推进）",
		_facedown_count() == 3, "翻面=%d" % _facedown_count())
	Game.state["phase"] = "hero_actions"
	var n_flip_empty: int = VillainRules._modok_flip_hero_cards(Game, 2, "测试")
	_check("③ 故事情节已无正面朝上英雄卡时翻转数为 0（不会报错/不会越界）", n_flip_empty == 0, "%d" % n_flip_empty)

	# ⑪ 面朝下 = 空白：只剩"最后一张 + 它前面那张已被翻面"时，继承符号为空
	_prep()
	_seed_story(2)
	var syms_before: Array = Game._last_hero_card_symbols()
	await VillainRules.on_bam(Game, "modok")
	var syms_blank: Array = Game._last_hero_card_symbols()
	_check("⑪ 面朝下的英雄卡不给任何行动符号（被翻面后继承变为空数组）",
		syms_before.size() > 0 and syms_blank.is_empty(),
		"翻面前=%s 翻面后=%s" % [syms_before, syms_blank])

	# ==================== ④ 意识转移（行动卡 10/11） ====================
	_prep()
	_seed_story(2)
	Game.state["story"].append({"type": "villain", "villain": "modok", "idx": 9, "move": 0})
	await VillainRules.on_bam(Game, "modok")
	_check("④ 意识转移正面朝上：BAM 之后额外翻转 → 共 2 张", _facedown_count() == 2, "翻面=%d" % _facedown_count())
	_prep()
	_seed_story(3)
	Game.state["story"].append({"type": "villain", "villain": "modok", "idx": 9, "move": 0})
	Game.state["story"].append({"type": "villain", "villain": "modok", "idx": 10, "move": 0})
	await VillainRules.on_bam(Game, "modok")
	_check("④ 两张意识转移都在场：共翻转 3 张（每张各额外 1 张）", _facedown_count() == 3, "翻面=%d" % _facedown_count())
	_prep()
	_seed_story(3)
	Game.state["story"].append({"type": "villain", "villain": "modok", "idx": 9, "move": 0, "face_down": true})
	await VillainRules.on_bam(Game, "modok")
	_check("④ 意识转移被翻成面朝下后不再额外生效（只翻转 BAM 的 1 张）", _facedown_count() == 1, "翻面=%d" % _facedown_count())
	_check("④ 意识转移的效果类型可被故事情节扫描识别",
		VillainRules._modok_faceup_effect_count(Game, "modok_mind_transfer") == 0
		and VillainRules._modok_faceup_effect_count(Game, "modok_superior_intellect") == 0, "")

	# ==================== ⑤ 溢出：翻 1 张，且一次结算只结算一次 ====================
	_prep()
	_seed_story(3)
	await VillainRules.on_overflow(Game, "modok", "thug", 0, 5)
	_check("⑤ 溢出翻转 1 张英雄卡（面板写\"1 个或多个\"→ 忽略 count=5）", _facedown_count() == 1, "翻面=%d" % _facedown_count())
	_prep()
	_seed_story(6)
	var vloc: int = _loc_with_slots(4)
	Game.state["villain_pos"] = vloc
	for l in Game.state["locations"]:
		l["civ"] = 0
		l["thug"] = 0
	var big: int = int(DB.location(String(Game.state["locations"][vloc]["id"]))["slots"])
	Game.state["locations"][vloc]["thug"] = big   # 挤满 → 卡 5 的 3 处放置全部溢出
	await Game._do_placement([["thug"], ["thug", "thug"], ["thug"]])
	_check("⑤ 一次放置结算里多处溢出只翻转 1 张（同一次结算事件只结算一次）",
		_facedown_count() == 1, "翻面=%d" % _facedown_count())

	# ==================== ⑥ 制备 + 特殊设置 ====================
	_prep()
	_check("⑥ 特殊设置：主计划牌堆顶 = 行动卡 1「制备」（下标 0）",
		Game.state["master_deck"].size() == 12 and int(Game.state["master_deck"][0]) == 0,
		str(Game.state["master_deck"].slice(0, 3)))
	_check("⑥ setup 记录了英雄起始地点 = 反派初始地点的正对面",
		int(Game.state["hero_start_loc"]) == (int(Game.state["villain_pos"]) + 3) % Game.LOCATION_COUNT,
		"start=%s vpos=%s" % [Game.state["hero_start_loc"], Game.state["villain_pos"]])
	_check("⑥ 英雄都落在该起始地点",
		int(Game.state["heroes"]["cap"]["location"]) == int(Game.state["hero_start_loc"]), "")
	var before_pos: int = int(Game.state["villain_pos"])
	await VillainRules.resolve_effect(Game, {"type": "modok_preparation", "name": "制备", "text": ""})
	_check("⑥ 制备：摩多克移动到英雄起始地点",
		int(Game.state["villain_pos"]) == int(Game.state["hero_start_loc"])
		and int(Game.state["villain_pos"]) != before_pos, "%s → %s" % [before_pos, Game.state["villain_pos"]])

	# ==================== ⑦ 超级天才智能（下个反派回合 +1 张） ====================
	_prep()
	_seed_story(8)
	Game.state["phase"] = "hero_actions"
	await VillainRules.resolve_effect(Game, {"type": "modok_superior_intellect", "name": "超级天才智能", "text": ""})
	_check("⑦ 超级天才智能：设置\"下一个反派回合 +1 张\"标记",
		int(Game.state["villain_extra_card_next_turn"]) == 1, "%s" % Game.state["villain_extra_card_next_turn"])
	var disc_before: int = (Game.state["master_discard"] as Array).size()
	await Game._run_villain_turn()
	var played: int = (Game.state["master_discard"] as Array).size() - disc_before
	_check("⑦ 下一个反派回合真的多打出 1 张行动卡（共 2 张）", played == 2, "实际 %d 张" % played)
	_check("⑦ 标记已消费清零（不会跨回合持续叠加）",
		int(Game.state["villain_extra_card_next_turn"]) == 0, "%s" % Game.state["villain_extra_card_next_turn"])

	# ==================== ⑧ 威胁卡 ====================
	# ⑧a 活体激光：本地点每个英雄 1 伤
	_prep([4, 4, 5])
	Game.state["locations"][4]["threat"] = _mk_threat(_threat_idx("活体激光"))
	var hp_before: int = (Game.state["heroes"]["cap"]["hand"] as Array).size()
	var hulk_before: int = (Game.state["heroes"]["hulk"]["hand"] as Array).size()
	await Game._trigger_all_threat_bam()
	_check("⑧a 活体激光 BAM：本地点（cap/ironman）各受 1 点伤害（弃 1 张手牌），别处英雄不受伤",
		(Game.state["heroes"]["cap"]["hand"] as Array).size() == hp_before - 1
		and (Game.state["heroes"]["ironman"]["hand"] as Array).size() == hp_before - 1
		and (Game.state["heroes"]["hulk"]["hand"] as Array).size() == hulk_before,
		"cap=%d ironman=%d hulk=%d（原 %d/%d）" % [(Game.state["heroes"]["cap"]["hand"] as Array).size(),
			(Game.state["heroes"]["ironman"]["hand"] as Array).size(),
			(Game.state["heroes"]["hulk"]["hand"] as Array).size(), hp_before, hulk_before])
	_prep([5, 5, 5])
	_seed_story(3)
	Game.state["locations"][4]["threat"] = _mk_threat(_threat_idx("活体激光"))
	await Game._trigger_all_threat_bam()
	_check("⑧b 活体激光 BAM：本地点没有英雄 → 翻转 1 张英雄卡", _facedown_count() == 1, "翻面=%d" % _facedown_count())

	# ⑧c 变色龙：伤害 = 最后 2 张英雄卡底部的攻击图标数
	_prep([4, 4, 5])
	var c1: int = _card_with_symbol_count("cap", "attack", 2)
	var c2: int = _card_with_symbol_count("ironman", "attack", 1)
	_check("⑧c 前置：库里有 2 攻击 / 1 攻击的英雄卡", c1 >= 0 and c2 >= 0, "c1=%d c2=%d" % [c1, c2])
	Game.state["story"] = [
		{"type": "hero", "hero": "hulk", "idx": 0},
		{"type": "villain", "villain": "modok", "idx": 5, "move": 0},
		{"type": "hero", "hero": "cap", "idx": c1},
		{"type": "hero", "hero": "ironman", "idx": c2},
	]
	Game.state["locations"][4]["threat"] = _mk_threat(_threat_idx("变色龙"))
	var cap_hand: int = (Game.state["heroes"]["cap"]["hand"] as Array).size()
	await Game._trigger_all_threat_bam()
	_check("⑧c 变色龙 BAM：2 攻击 + 1 攻击 = 3 点伤害（弃 3 张手牌）",
		(Game.state["heroes"]["cap"]["hand"] as Array).size() == cap_hand - 3,
		"%d → %d" % [cap_hand, (Game.state["heroes"]["cap"]["hand"] as Array).size()])
	# 面朝下的卡视为空白：占"最后 2 张"的名额但不贡献图标
	var c3: int = _card_with_symbol_count("cap", "attack", 3)
	_prep([4, 4, 5])
	Game.state["story"] = [
		{"type": "hero", "hero": "cap", "idx": c3},
		{"type": "hero", "hero": "hulk", "idx": 0, "face_down": true},
		{"type": "hero", "hero": "ironman", "idx": c2},
	]
	Game.state["locations"][4]["threat"] = _mk_threat(_threat_idx("变色龙"))
	cap_hand = (Game.state["heroes"]["cap"]["hand"] as Array).size()
	await Game._trigger_all_threat_bam()
	_check("⑧d 变色龙：最后 2 张里有一张面朝下 → 视为空白（只按剩下那张的 1 个攻击图标结算）",
		(Game.state["heroes"]["cap"]["hand"] as Array).size() == cap_hand - 1,
		"%d → %d" % [cap_hand, (Game.state["heroes"]["cap"]["hand"] as Array).size()])

	# ⑧e 斑点：翻转数量 = 最后 2 张英雄卡底部的英勇图标数
	_prep([4, 4, 5])
	var h1: int = _card_with_symbol_count("cap", "heroic", 1)
	var h2: int = _card_with_symbol_count("ironman", "heroic", 2)
	_check("⑧e 前置：库里有 1 英勇 / 2 英勇的英雄卡", h1 >= 0 and h2 >= 0, "h1=%d h2=%d" % [h1, h2])
	Game.state["story"] = [
		{"type": "hero", "hero": "hulk", "idx": 0},
		{"type": "hero", "hero": "hulk", "idx": 1},
		{"type": "hero", "hero": "cap", "idx": h1},
		{"type": "hero", "hero": "ironman", "idx": h2},
	]
	Game.state["locations"][4]["threat"] = _mk_threat(_threat_idx("斑点"))
	await Game._trigger_all_threat_bam()
	_check("⑧e 斑点 BAM：1 + 2 = 3 个英勇图标 → 翻转 3 张英雄卡",
		_facedown_count() == 3, "翻面=%d" % _facedown_count())
	_check("⑧e 斑点翻的是最靠前的 3 张（最后 2 张仍正面朝上）",
		bool(Game.state["story"][0].get("face_down", false))
		and bool(Game.state["story"][1].get("face_down", false))
		and bool(Game.state["story"][2].get("face_down", false))
		and not bool(Game.state["story"][3].get("face_down", false)), "")
	_prep([4, 4, 5])
	var h0: int = _card_with_symbol_count("cap", "heroic", 0)
	if h0 >= 0:
		Game.state["story"] = [
			{"type": "hero", "hero": "hulk", "idx": 0},
			{"type": "hero", "hero": "cap", "idx": h0},
			{"type": "hero", "hero": "ironman", "idx": h0},
		]
		Game.state["locations"][4]["threat"] = _mk_threat(_threat_idx("斑点"))
		await Game._trigger_all_threat_bam()
		_check("⑧f 斑点：最后 2 张没有英勇图标 → 翻转 0 张（卡面无图标时不动作）",
			_facedown_count() == 0, "翻面=%d（0 英勇卡 idx=%d）" % [_facedown_count(), h0])
	else:
		_check("⑧f 斑点：找不到 0 英勇图标的英雄卡（跳过该分支，卡组里无此卡）", true, "")

	# ⑧g 能量投射到达效果：翻转 1 张
	_prep([4, 4, 5])
	_seed_story(3)
	Game.state["villain_pos"] = 4
	Game.state["locations"][4]["threat"] = _mk_threat(_threat_idx("能量投射"))
	await Game._trigger_threat_arrival(4)
	_check("⑧g 能量投射到达效果：翻转 1 张英雄卡", _facedown_count() == 1, "翻面=%d" % _facedown_count())
	await Game._trigger_threat_arrival(4)
	_check("⑧g 到达效果只结算一次（arrival_triggered 守卫）", _facedown_count() == 1, "翻面=%d" % _facedown_count())

	# ⑧h 科技共情到达效果：可选择翻转 2 张英雄卡来保住行动指示物
	_prep([4, 4, 5])
	_seed_story(4)
	Game.state["villain_pos"] = 4
	Game.state["locations"][4]["threat"] = _mk_threat(_threat_idx("科技共情"))
	Game.state["heroes"]["cap"]["tokens"] = {"move": 2, "attack": 1, "heroic": 0, "wild": 0}
	_confirm_answer = false
	Game.autopilot = false   # autopilot 下 _ask_confirm 直接返回 true，必须关掉才能真正走弹窗分支
	await Game._trigger_threat_arrival(4)
	Game.autopilot = true
	_check("⑧h 科技共情：英雄选择不翻牌 → 失去全部行动指示物",
		int(Game.state["heroes"]["cap"]["tokens"]["move"]) == 0
		and int(Game.state["heroes"]["cap"]["tokens"]["attack"]) == 0, str(Game.state["heroes"]["cap"]["tokens"]))
	_prep([4, 4, 5])
	_seed_story(4)
	Game.state["villain_pos"] = 4
	Game.state["locations"][4]["threat"] = _mk_threat(_threat_idx("科技共情"))
	Game.state["heroes"]["cap"]["tokens"] = {"move": 2, "attack": 1, "heroic": 0, "wild": 0}
	_confirm_answer = true
	Game.autopilot = false   # 同样走真实弹窗，回答"是"
	await Game._trigger_threat_arrival(4)
	Game.autopilot = true
	_check("⑧h 科技共情：英雄选择翻转 2 张英雄卡 → 保住行动指示物且故事情节多 2 张面朝下",
		int(Game.state["heroes"]["cap"]["tokens"]["move"]) == 2 and _facedown_count() == 2,
		"tokens=%s 翻面=%d" % [str(Game.state["heroes"]["cap"]["tokens"]), _facedown_count()])
	_check("⑧h 科技共情的询问确实走的是弹窗（confirm 被调用过）",
		_confirm_log.size() >= 2, "询问 %d 次" % _confirm_log.size())
	_confirm_answer = true

	# ⑧i 心灵异能：在此地点开始回合的英雄必须面朝下出牌
	_prep([4, 5, 5])
	Game.state["locations"][4]["threat"] = _mk_threat(_threat_idx("心灵异能"))
	Game.state["story"] = [{"type": "hero", "hero": "ironman", "idx": 0}, {"type": "hero", "hero": "hulk", "idx": 1}]
	Game.state["current_hero"] = 0
	await Game._start_hero_turn()
	_check("⑧i 心灵异能：在该地点开始回合 → 标记本回合必须面朝下出牌",
		String(Game.state["forced_face_down_hero"]) == "cap", "%s" % Game.state["forced_face_down_hero"])
	var story_before: int = Game.state["story"].size()
	# 继承符号 = _last_hero_card_symbols() = story[size-2] = ironman idx0（最后一张被当作"刚打出的"）
	var prev_expected: Array = DB.hero_cards("ironman")[0]["symbols"]
	# 从手牌里挑一张"自身符号与继承符号不同"的卡，才能证明面朝下不会拿到自己卡上的行动
	var cap_hand0: Array = Game.state["heroes"]["cap"]["hand"]
	var pick_i := 0
	for hi in range(cap_hand0.size()):
		if (DB.hero_cards("cap")[int(cap_hand0[hi])]["symbols"] as Array) != prev_expected:
			pick_i = hi
			break
	var cap_card: int = int(cap_hand0[pick_i])
	var own_syms: Array = DB.hero_cards("cap")[cap_card]["symbols"]
	await Game.play_card(pick_i)
	_check("⑧i 点手牌即背面打出（故事情节新增一条 face_down 的英雄卡，且卡的 idx 就是被打出的那张）",
		Game.state["story"].size() == story_before + 1
		and bool(Game.state["story"][story_before].get("face_down", false))
		and int(Game.state["story"][story_before]["idx"]) == cap_card,
		"%s" % str(Game.state["story"][story_before]))
	var inherit: Array = Game._last_hero_card_symbols()
	var expect_after: Array = DB.hero_cards("hulk")[1]["symbols"]
	_check("⑧i 面朝下出牌：不获得自己卡上的行动，只继承上一张英雄卡的符号",
		Game.state["action_symbols"] == prev_expected and own_syms != prev_expected,
		"符号=%s 继承=%s 自己的卡=%s" % [Game.state["action_symbols"], prev_expected, own_syms])
	_check("⑧i 面朝下打出的卡被视为空白（下一位英雄继承的是它前面那张正面朝上的卡）",
		inherit == expect_after, "%s vs %s" % [inherit, expect_after])
	_check("⑧i 打完即清掉强制标记（只影响本回合这一张）",
		String(Game.state["forced_face_down_hero"]) == "", "%s" % Game.state["forced_face_down_hero"])
	# 不在该地点开始回合的英雄不被强制
	_prep([5, 5, 5])
	Game.state["locations"][4]["threat"] = _mk_threat(_threat_idx("心灵异能"))
	Game.state["current_hero"] = 0
	await Game._start_hero_turn()
	_check("⑧i 不在心灵异能地点开始回合的英雄不受影响",
		String(Game.state["forced_face_down_hero"]) == "", "%s" % Game.state["forced_face_down_hero"])

	# ==================== ⑨ 恶毒的阴谋（判负） ====================
	_prep()
	_seed_story(2)
	Game.state["phase"] = "hero_actions"
	Game.state["lose_reason"] = ""
	_check("⑨ 还有正面朝上的英雄卡时不判负",
		not VillainRules._modok_all_story_heroes_face_down(Game)
		and not Game._check_lose(), "")
	Game.state["story"][0]["face_down"] = true
	Game.state["story"][1]["face_down"] = true
	_check("⑨ 全部面朝下时判据成立", VillainRules._modok_all_story_heroes_face_down(Game), "")
	var lost: bool = Game._check_lose()
	_check("⑨ 全部面朝下 → 英雄失败（phase = game_over 且原因提到面朝下）",
		lost and String(Game.state["phase"]) == "game_over"
		and String(Game.state.get("lose_reason", "")).contains("面朝下"),
		"%s / %s" % [Game.state["phase"], Game.state.get("lose_reason", "")])
	_prep()
	Game.state["phase"] = "hero_actions"
	_check("⑨ 故事情节里一张英雄卡都没有时不判负（避免开局误判）",
		not VillainRules._modok_all_story_heroes_face_down(Game) and not Game._check_lose(), "")

	# ==================== ⑩ 放置图案落位（顺时针相邻 / 本地 / 逆时针相邻） ====================
	_prep()
	var ploc: int = _loc_with_slots(5)
	for l in Game.state["locations"]:
		l["civ"] = 0
		l["thug"] = 0
	Game.state["villain_pos"] = ploc
	var adj: Array = Game._adjacent_locs(ploc)
	await Game._do_placement([["thug"], ["thug", "thug"], ["thug"]])
	_check("⑩ 卡 3 的图案（暴/暴暴/暴）：本地 +2 暴徒，两个相邻地点各 +1",
		int(Game.state["locations"][ploc]["thug"]) == 2
		and int(Game.state["locations"][int(adj[0])]["thug"]) == 1
		and int(Game.state["locations"][int(adj[1])]["thug"]) == 1,
		"本地%d 邻0=%d 邻1=%d" % [int(Game.state["locations"][ploc]["thug"]),
			int(Game.state["locations"][int(adj[0])]["thug"]), int(Game.state["locations"][int(adj[1])]["thug"])])
	_prep()
	ploc = _loc_with_slots(5)
	for l in Game.state["locations"]:
		l["civ"] = 0
		l["thug"] = 0
	Game.state["villain_pos"] = ploc
	adj = Game._adjacent_locs(ploc)
	await Game._do_placement([["thug", "civ"], ["thug", "civ"], ["thug", "civ"]])
	var mix_ok := true
	for p in [ploc, int(adj[0]), int(adj[1])]:
		if int(Game.state["locations"][p]["thug"]) != 1 or int(Game.state["locations"][p]["civ"]) != 1:
			mix_ok = false
	_check("⑩ 卡 9 的图案（民暴 ×3）：三个地点各 +1 暴徒 +1 平民", mix_ok,
		"本地=%d/%d 邻0=%d/%d 邻1=%d/%d" % [int(Game.state["locations"][ploc]["thug"]), int(Game.state["locations"][ploc]["civ"]),
			int(Game.state["locations"][int(adj[0])]["thug"]), int(Game.state["locations"][int(adj[0])]["civ"]),
			int(Game.state["locations"][int(adj[1])]["thug"]), int(Game.state["locations"][int(adj[1])]["civ"])])

	# ==================== ⑫ 联机快照带 face_down ====================
	_prep()
	_seed_story(2)
	await VillainRules.on_bam(Game, "modok")
	Net.active = true
	Net.is_host = false
	Net.my_peer = 2
	Net.seats = [
		{"peer": 1, "name": "房主", "hero": "cap", "villain": "", "locs": [], "ready": false},
		{"peer": 2, "name": "我", "hero": "cap", "villain": "", "locs": [], "ready": false},
	]
	var vis: Dictionary = Net.visible_state_for("cap")
	var first_vis: Dictionary = (vis.get("story", []) as Array)[0]
	_check("⑫ 联机快照下发了 face_down（客户端也能看到哪张英雄卡被摩多克翻面）",
		first_vis is Dictionary and bool((first_vis as Dictionary).get("face_down", false)), str(first_vis))
	Net.active = false

	print("---- RESULT ----")
	if _fail == 0:
		print("=== MODOK TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== MODOK TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)
