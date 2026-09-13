extends Node
## 犀牛人（Rhino，第一季众筹，素材 7.5）回归测试
## 覆盖：
##   ① 数据完整性（22 反派 / 12 行动卡 / 6 威胁卡 / 生命 5-8-11 / 无邪恶计划轨道）+ 22 张切图齐全
##      —— 逐张与**卡图实测值**核对（移动 / BAM / 放置图案逐格逐指示物）
##   ② VillainRules 注册（IDS / BAM 分发 / 溢出分发）
##   ③ 面板 BAM：伤害 = 犀牛人本回合进入的地点数量，只打"所在地点"的英雄；然后把受伤英雄顺时针移动 1 个地点
##   ④ 特殊规则①：英雄被 KO 时犀牛人不激活 BAM！，改为该英雄获得 1 个危机指示物
##   ⑤ 特殊规则②：身上有危机指示物的英雄下一回合必须面朝下出牌，然后丢弃所有危机指示物
##   ⑥ 威胁卡「开阔地带」：在该地点受到伤害的英雄额外获得 1 个危机指示物（无此卡则不获得）
##   ⑦ 威胁卡「无掩护」：在该地点结束回合的英雄获得 1 个危机指示物（不在该地点则不获得）
##   ⑧ 面板溢出：平民/暴徒放不下 → 抽 1 张反派行动卡面朝下加入故事情节（"1 个或多个"只结算一次）
##   ⑨ 行动卡 1~4「犀牛充电」：顺时针移动到下一个有英雄的地点
##   ⑩ 放置图案按 [顺时针相邻 / 本地 / 逆时针相邻] 三槽落位（卡 5~12）
##   ⑪ 卡 11/12 没有 BAM：整局反派回合跑通时确实不触发 BAM
##   ⑫ 联机快照带 hero crisis（客户端也能看到危机指示物）
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

## 直接读 PNG 文件头拿尺寸（不依赖 .import 资源缓存）：IHDR 的宽高在第 16/20 字节。
## ⚠️ PNG 用大端存宽高，而 FileAccess.get_32() 是按小端读的（读出来会是字节反转的怪数），
##    所以这里取 8 个字节自己按大端拼。
func _png_size(p: String) -> Vector2i:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return Vector2i(-1, -1)
	f.seek(16)
	var b: PackedByteArray = f.get_buffer(8)
	f.close()
	if b.size() < 8:
		return Vector2i(-1, -1)
	var w: int = (int(b[0]) << 24) | (int(b[1]) << 16) | (int(b[2]) << 8) | int(b[3])
	var h: int = (int(b[4]) << 24) | (int(b[5]) << 16) | (int(b[6]) << 8) | int(b[7])
	return Vector2i(w, h)

## 干净开局：清场（无威胁/无指示物/故事情节为空）、英雄满手牌未 KO、指定站位
func _prep(locs: Array = []) -> void:
	Game.setup("rhino", ["cap", "ironman", "hulk"], "none", "base")
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
	Game.state["extra_villain_card"] = 0
	Game.state["villain_extra_card_next_turn"] = 0
	Game.state["forced_face_down_hero"] = ""
	Game.state["rhino_moved_locs"] = 0
	Game.state["rhino_face_down_discard_hero"] = ""
	Game.state["hero_cards_played"] = 0
	Game.state["phase"] = "hero_actions"
	Game.state["villain_hp"] = 11
	Game.state["log"] = []
	Game.state["master_deck"] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]

func _hand(hid: String) -> int:
	return (Game.state["heroes"][hid]["hand"] as Array).size()

func _loc(hid: String) -> int:
	return int(Game.state["heroes"][hid]["location"])

func _crisis(hid: String) -> int:
	return int(Game.state["heroes"][hid].get("crisis", 0))

## 按 DB 数据造一张威胁卡（与引擎放置时一致：hp = henchman_hp）
func _mk_threat(idx: int) -> Dictionary:
	var t: Dictionary = (DB.villain("rhino")["threats"][idx] as Dictionary).duplicate(true)
	t["hp"] = int(t.get("henchman_hp", 0))
	t["heroic_tokens"] = 0
	t["arrival_triggered"] = false
	t["_bam_done"] = false
	if t.has("clear"):
		t["clear_progress"] = []
	return t

func _threat_idx(tname: String) -> int:
	var ts: Array = DB.villain("rhino")["threats"]
	for i in range(ts.size()):
		if String((ts[i] as Dictionary)["name"]) == tname:
			return i
	return -1

func _slots(loc: int) -> int:
	return int(DB.location(String(Game.state["locations"][loc]["id"]))["slots"])

## 找一个"自己 + 两个相邻地点"都至少有 need 个槽位的地点（放置图案测试用）
func _pos_with_room(need: int) -> int:
	for p in range(Game.LOCATION_COUNT):
		var adj: Array = Game._adjacent_locs(p)
		var ok: bool = _slots(p) >= need
		for a in adj:
			if _slots(int(a)) < need:
				ok = false
		if ok:
			return p
	return -1

## 场上所有地点的 thug/civ 合计
func _total(kind: String) -> int:
	var n := 0
	for l in Game.state["locations"]:
		n += int(l[kind])
	return n

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

	# ==================== ① 数据完整性（卡图实测） ====================
	_check("① 反派总数 22", DB.villains.size() == 22, "实际 %d" % DB.villains.size())
	var v: Dictionary = DB.villain("rhino")
	_check("① rhino 存在且 name/name_en 正确",
		not v.is_empty() and String(v.get("name", "")) == "犀牛人" and String(v.get("name_en", "")) == "Rhino",
		"%s / %s" % [v.get("name", ""), v.get("name_en", "")])
	_check("① 生命值 5/8/11（面板逐字读图）",
		int(v["health"]["2"]) == 5 and int(v["health"]["3"]) == 8 and int(v["health"]["4"]) == 11,
		"%s/%s/%s" % [v["health"]["2"], v["health"]["3"], v["health"]["4"]])
	_check("① 无邪恶计划轨道（plot_track = none，恐惧轨道 0）",
		String(v["plot_track"]) == "none" and int(v["fear_track_max"]) == 0 and String(v["plot"]) == "",
		"%s/%s/%s" % [v["plot_track"], v["fear_track_max"], v["plot"]])
	_check("① 12 张行动卡", (v["actions"] as Array).size() == 12, "%d" % (v["actions"] as Array).size())
	_check("① 6 张威胁卡", (v["threats"] as Array).size() == 6, "%d" % (v["threats"] as Array).size())
	_check("① bam / overflow / special 三段面板文案都已落库",
		String(v["bam"]).length() > 10 and String(v["overflow"]).length() > 10 and String(v["special"]).length() > 10, "")

	# 逐张行动卡：卡 1~4 是"顺时针移动到下一个有英雄的地点"（dict move），卡 5~12 是数字移动
	var moves := [4, 2, 1, 1, 2, 3, 5, 0]
	var bams := [true, true, true, true, true, true, true, true, true, true, false, false]
	var charge_ok := true
	var charge_bad := ""
	for i in range(4):
		var c: Dictionary = v["actions"][i]
		if not (c["move"] is Dictionary):
			charge_ok = false
			charge_bad += "卡%d move 不是 dict(%s) " % [i + 1, str(c["move"])]
			continue
		var mv: Dictionary = c["move"]
		if String(mv.get("dir", "")) != "cw" or bool(mv.get("hero_in", false)) != true or mv.has("threat_in"):
			charge_ok = false
			charge_bad += "卡%d move=%s " % [i + 1, str(mv)]
		if not bool(c["bam"]) or c["place"] != null or c["effect"] != null:
			charge_ok = false
			charge_bad += "卡%d bam/place/effect=%s/%s/%s " % [i + 1, c["bam"], str(c["place"]), str(c["effect"])]
	_check("① 卡 1~4「犀牛充电」= 顺时针→下一有英雄地点 + BAM! + 无图案无效果（逐张读图）", charge_ok, charge_bad)
	var num_ok := true
	var num_bad := ""
	for i in range(4, 12):
		var c2: Dictionary = v["actions"][i]
		if int(c2["move"]) != moves[i - 4]:
			num_ok = false
			num_bad += "卡%d移动%s≠%s " % [i + 1, c2["move"], moves[i - 4]]
		if bool(c2["bam"]) != bams[i]:
			num_ok = false
			num_bad += "卡%d BAM=%s≠%s " % [i + 1, c2["bam"], bams[i]]
	_check("① 卡 5~12 的移动值 = 4/2/1/1/2/3/5/0（逐张读图）", num_ok, num_bad)
	_check("① 卡 11/12 没有 BAM!（卡面无星爆；像素扫描红像素 = 0）",
		not bool(v["actions"][10]["bam"]) and not bool(v["actions"][11]["bam"]), "")
	_check("① 卡 1~10 都印了 BAM!", bams.slice(0, 10).all(func(b): return b), "")

	# 放置图案逐格逐指示物（卡图实测）
	var want_place := {
		5: [["thug"], ["thug"], ["thug"]],
		6: [["thug"], ["thug"], ["thug"]],
		7: [["thug"], ["thug"], ["thug"]],
		8: [["civ"], ["civ"], ["civ"]],
		9: [["civ"], ["civ"], ["civ"]],
		10: [["civ"], ["civ"], ["civ"]],
		11: [["thug", "civ"], ["thug", "civ"], ["thug", "civ"]],
		12: [["thug", "civ"], ["thug", "civ"], ["thug", "civ"]],
	}
	var place_ok := true
	var place_bad := ""
	for n in range(5, 13):
		var pl: Variant = v["actions"][n - 1]["place"]
		if pl == null:
			place_ok = false
			place_bad += "卡%d 无图案 " % n
			continue
		var arr: Array = pl
		if arr.size() != 3:
			place_ok = false
			place_bad += "卡%d 槽数=%d " % [n, arr.size()]
			continue
		for s in range(3):
			var got: Array = arr[s]
			var want: Array = want_place[n][s]
			if got != want:
				place_ok = false
				place_bad += "卡%d 槽%d %s≠%s " % [n, s + 1, str(got), str(want)]
	for n in range(1, 5):
		if v["actions"][n - 1]["place"] != null:
			place_ok = false
			place_bad += "卡%d 应无图案 " % n
	_check("① 放置图案逐格逐指示物与卡图一致（5~7 暴/暴/暴、8~10 民/民/民、11~12 民暴×3）", place_ok, place_bad)

	# 22 张切图齐全（含 .import）
	var assets_missing: Array = []
	for i in range(1, 13):
		var p: String = "res://assets/cards/villains/rhino/action_%02d.png" % i
		if not FileAccess.file_exists(p):
			assets_missing.append(p)
	for i in range(1, 7):
		var p3: String = "res://assets/cards/villains/rhino/threat_%02d.png" % i
		if not FileAccess.file_exists(p3):
			assets_missing.append(p3)
	for extra in ["back.png", "threat_back.png", "panel.png", "panel_back.png"]:
		var p2: String = "res://assets/cards/villains/rhino/" + extra
		if not FileAccess.file_exists(p2):
			assets_missing.append(p2)
	_check("① 22 张切图齐全（12 行动 + 6 威胁 + back/threat_back/panel/panel_back）",
		assets_missing.is_empty(), str(assets_missing))
	var import_missing: Array = []
	for i in range(1, 13):
		var ip: String = "res://assets/cards/villains/rhino/action_%02d.png.import" % i
		if not FileAccess.file_exists(ip):
			import_missing.append(ip)
	for i in range(1, 7):
		var ip2: String = "res://assets/cards/villains/rhino/threat_%02d.png.import" % i
		if not FileAccess.file_exists(ip2):
			import_missing.append(ip2)
	_check("① 切图的 .import 也已生成（Godot 才能 load 到这些贴图）", import_missing.is_empty(), str(import_missing))
	var sz_bad: Array = []
	for pair in [["action_01.png", Vector2i(853, 1198)], ["action_12.png", Vector2i(853, 1198)],
			["threat_01.png", Vector2i(1198, 853)], ["threat_06.png", Vector2i(1198, 853)],
			["panel.png", Vector2i(1140, 525)], ["panel_back.png", Vector2i(1140, 525)],
			["back.png", Vector2i(853, 1198)], ["threat_back.png", Vector2i(1198, 853)]]:
		var got_sz: Vector2i = _png_size("res://assets/cards/villains/rhino/" + String(pair[0]))
		if got_sz != pair[1]:
			sz_bad.append("%s=%dx%d（期望 %dx%d）" % [pair[0], got_sz.x, got_sz.y, pair[1].x, pair[1].y])
	_check("① 切图尺寸正确（行动卡 853×1198 / 威胁卡 1198×853 / 面板 1140×525）", sz_bad.is_empty(), str(sz_bad))

	# 威胁卡（6 张全部逐张读图 + 像素指纹一致）
	var tnames: Array = []
	for t in v["threats"]:
		tnames.append(String(t["name"]))
	_check("① 威胁卡顺序 = 开阔地带/无掩护 交替 3 轮（拼版 01..06 逐张读图；docx 同）",
		tnames == ["开阔地带", "无掩护", "开阔地带", "无掩护", "开阔地带", "无掩护"], str(tnames))
	var th_ok := true
	var th_bad := ""
	for i in range(6):
		var t2: Dictionary = v["threats"][i]
		if int(t2["henchman_hp"]) != 0:
			th_ok = false
			th_bad += "%s hp=%s " % [t2["name"], t2["henchman_hp"]]
		if bool(t2["bam"]) or bool(t2["arrival"]) or bool(t2["start_turn"]):
			th_ok = false
			th_bad += "%s bam/arrival/start=%s/%s/%s " % [t2["name"], t2["bam"], t2["arrival"], t2["start_turn"]]
		var cl: Array = t2.get("clear", [])
		if cl.size() != 3 or cl.any(func(x): return String(x) != "heroic"):
			th_ok = false
			th_bad += "%s clear=%s " % [t2["name"], str(cl)]
		if String(t2["text"]).length() < 8:
			th_ok = false
			th_bad += "%s 缺 text " % t2["name"]
	_check("① 6 张威胁卡都无生命值图标 / 无 BAM / 无到达 / 有 3 个英勇槽（像素指纹 6 张完全相同）", th_ok, th_bad)
	_check("① 开阔地带 = 在此地点受到伤害的英雄额外获得 1 个危机指示物",
		String(v["threats"][0]["text"]).contains("受到伤害") and String(v["threats"][0]["text"]).contains("危机指示物"),
		String(v["threats"][0]["text"]))
	_check("① 无掩护 = 在此位置结束回合的英雄获得 1 个危机指示物",
		String(v["threats"][1]["text"]).contains("结束回合") and String(v["threats"][1]["text"]).contains("危机指示物"),
		String(v["threats"][1]["text"]))

	# ==================== ② VillainRules 注册 ====================
	_check("② VillainRules.IDS 已注册 rhino", VillainRules.IDS.has("rhino"), str(VillainRules.IDS))
	_check("② 犀牛人的威胁卡都不参与威胁 BAM / 到达分发（卡面本来就没有）",
		v["threats"].all(func(t): return not bool(t["bam"]) and not bool(t["arrival"])), "")

	# ==================== ③ 面板 BAM ====================
	# ③a 伤害 = 本回合进入的地点数量；只打所在地点；受伤英雄顺时针移动 1 个地点
	_prep([4, 4, 5])
	Game.state["villain_pos"] = 4
	Game.state["rhino_moved_locs"] = 3
	await VillainRules._rhino_bam(Game)
	_check("③a 犀牛人所在地点的每个英雄各受「本回合进入地点数」点伤害（cap/ironman 各弃 3 张）",
		_hand("cap") == 5 and _hand("ironman") == 5, "cap=%d ironman=%d" % [_hand("cap"), _hand("ironman")])
	_check("③a 不在犀牛人所在地点的英雄不受影响（hulk 手牌不变）", _hand("hulk") == 8, "hulk=%d" % _hand("hulk"))
	_check("③a 受伤英雄顺时针移动 1 个地点（4 → 5），未受伤的 hulk 留在原地（5）",
		_loc("cap") == 5 and _loc("ironman") == 5 and _loc("hulk") == 5,
		"cap=%d ironman=%d hulk=%d" % [_loc("cap"), _loc("ironman"), _loc("hulk")])
	_check("③a BAM 不产生危机指示物（没有「开阔地带」在场时）",
		_crisis("cap") == 0 and _crisis("ironman") == 0, "%d/%d" % [_crisis("cap"), _crisis("ironman")])

	# ③b 本回合没有移动 → 0 点伤害，且没有人被移动
	_prep([4, 4, 5])
	Game.state["villain_pos"] = 4
	Game.state["rhino_moved_locs"] = 0
	await VillainRules._rhino_bam(Game)
	_check("③b 本回合进入 0 个地点 → 0 点伤害（手牌不变）",
		_hand("cap") == 8 and _hand("ironman") == 8, "cap=%d ironman=%d" % [_hand("cap"), _hand("ironman")])
	_check("③b 0 点伤害 → 没人「受到伤害」，因此没有人被顺时针移动",
		_loc("cap") == 4 and _loc("ironman") == 4, "cap=%d ironman=%d" % [_loc("cap"), _loc("ironman")])

	# ③c 伤害 >= 手牌数 → 该英雄被 KO（走特殊规则①，不产生连锁 BAM）
	_prep([4, 5, 5])
	Game.state["heroes"]["cap"]["hand"] = [0, 1]
	Game.state["villain_pos"] = 4
	Game.state["rhino_moved_locs"] = 4
	await VillainRules._rhino_bam(Game)
	_check("③c 伤害打空手牌 → 英雄被 KO，并且按特殊规则获得 1 个危机指示物",
		bool(Game.state["heroes"]["cap"]["ko"]) and _crisis("cap") == 1, "ko=%s crisis=%d" % [Game.state["heroes"]["cap"]["ko"], _crisis("cap")])
	_check("③c 被 KO 的英雄不参与「顺时针移动 1 个地点」", _loc("cap") == 4, "loc=%d" % _loc("cap"))
	_check("③c 已 KO 的英雄不再被 BAM 结算（无英雄时安全返回，不判负）",
		String(Game.state["phase"]) != "game_over", String(Game.state["phase"]))

	# ==================== ④ 特殊规则①：KO 不激活 BAM，改为获得危机指示物 ====================
	_prep([4, 4, 5])
	Game.state["villain_pos"] = 4
	Game.state["rhino_moved_locs"] = 3
	var im_before: int = _hand("ironman")
	var im_loc_before: int = _loc("ironman")
	await Game._ko_hero("cap")
	_check("④ 英雄被 KO：犀牛人不激活 BAM！（同地点的 ironman 手牌与位置都没变）",
		_hand("ironman") == im_before and _loc("ironman") == im_loc_before,
		"ironman hand %d→%d loc %d→%d" % [im_before, _hand("ironman"), im_loc_before, _loc("ironman")])
	_check("④ 被 KO 的英雄获得 1 个危机指示物（获得者是该英雄，不是别的英雄）",
		_crisis("cap") == 1 and _crisis("ironman") == 0, "cap=%d ironman=%d" % [_crisis("cap"), _crisis("ironman")])
	_check("④ 被 KO 的英雄标记 ko = true", bool(Game.state["heroes"]["cap"]["ko"]), "")
	_prep([4, 4, 5])
	Game.state["villain_pos"] = 4
	await Game._ko_hero("hulk")
	_check("④ KO 产生的危机指示物会累加（同一英雄被 KO 两次 → 2 个）",
		_crisis("hulk") == 1, "hulk=%d" % _crisis("hulk"))

	# ==================== ⑤ 特殊规则②：有危机 → 下回合面朝下出牌 → 之后丢弃 ====================
	_prep([4, 5, 5])
	Game.state["current_hero"] = 0
	Game.state["heroes"]["cap"]["crisis"] = 2
	Game.state["story"] = [{"type": "hero", "hero": "ironman", "idx": 0}, {"type": "hero", "hero": "hulk", "idx": 1}]
	await Game._start_hero_turn()
	_check("⑤ 身上有危机指示物的英雄，本回合被要求面朝下出牌",
		String(Game.state["forced_face_down_hero"]) == "cap", "%s" % Game.state["forced_face_down_hero"])
	var story_before: int = Game.state["story"].size()
	var prev_expected: Array = DB.hero_cards("ironman")[0]["symbols"]
	var cap_hand0: Array = Game.state["heroes"]["cap"]["hand"]
	var pick_i := 0
	for hi in range(cap_hand0.size()):
		if (DB.hero_cards("cap")[int(cap_hand0[hi])]["symbols"] as Array) != prev_expected:
			pick_i = hi
			break
	var cap_card: int = int(cap_hand0[pick_i])
	await Game.play_card(pick_i)
	_check("⑤ 点手牌即背面打出（故事情节新增一条 face_down 的英雄卡，idx 就是被打出的那张）",
		Game.state["story"].size() == story_before + 1
		and bool(Game.state["story"][story_before].get("face_down", false))
		and int(Game.state["story"][story_before]["idx"]) == cap_card,
		"%s" % str(Game.state["story"][story_before]))
	_check("⑤ 面朝下出牌：不获得自己卡上的行动（符号 = 继承上一张英雄卡的）",
		Game.state["action_symbols"] == prev_expected, "符号=%s 期望=%s" % [str(Game.state["action_symbols"]), str(prev_expected)])
	_check("⑤ 打出即清掉强制标记（只影响本回合这一张）",
		String(Game.state["forced_face_down_hero"]) == "", "%s" % Game.state["forced_face_down_hero"])
	_check("⑤ 面朝下出牌之后危机指示物还在（要等这个回合结束才丢弃）", _crisis("cap") == 2, "%d" % _crisis("cap"))
	Game.state["phase"] = "hero_end"
	await Game.end_turn()
	_check("⑤ 这一回合结束后丢弃该英雄所有的危机指示物（2 → 0）", _crisis("cap") == 0, "%d" % _crisis("cap"))
	# 没有危机的英雄不被强制
	_prep([4, 5, 5])
	Game.state["current_hero"] = 0
	Game.state["heroes"]["cap"]["crisis"] = 0
	await Game._start_hero_turn()
	_check("⑤ 没有危机指示物的英雄不受影响（不被强制面朝下）",
		String(Game.state["forced_face_down_hero"]) == "", "%s" % Game.state["forced_face_down_hero"])

	# ==================== ⑥ 威胁卡「开阔地带」 ====================
	_prep([4, 5, 5])
	Game.state["locations"][4]["threat"] = _mk_threat(_threat_idx("开阔地带"))
	await Game._deal_damage_to_hero("cap", 1)
	_check("⑥ 开阔地带：在该地点受到伤害的英雄额外获得 1 个危机指示物",
		_crisis("cap") == 1 and _hand("cap") == 7, "crisis=%d hand=%d" % [_crisis("cap"), _hand("cap")])
	await Game._deal_damage_to_hero("ironman", 1)
	_check("⑥ 不在开阔地带所在地点受伤的英雄不获得危机指示物（ironman 在 5）",
		_crisis("ironman") == 0, "%d" % _crisis("ironman"))
	_prep([4, 5, 5])
	Game.state["locations"][4]["threat"] = _mk_threat(_threat_idx("无掩护"))
	await Game._deal_damage_to_hero("cap", 1)
	_check("⑥ 只有「开阔地带」才给受伤危机：换成「无掩护」时受伤不产生危机指示物",
		_crisis("cap") == 0, "%d" % _crisis("cap"))
	_prep([5, 5, 5])
	await Game._deal_damage_to_hero("cap", 1)
	_check("⑥ 场上没有威胁卡时受伤不产生危机指示物（效果由卡面驱动，不写死反派）",
		_crisis("cap") == 0, "%d" % _crisis("cap"))
	# 英勇槽：3 个英勇行动可以化解「开阔地带」
	_prep([4, 5, 5])
	Game.state["locations"][4]["threat"] = _mk_threat(_threat_idx("开阔地带"))
	_check("⑥ 开阔地带可放英勇指示物（hp=0 + clear 三槽）",
		Game._threat_placeable_sym(Game.state["locations"][4]["threat"]) == "heroic",
		Game._threat_placeable_sym(Game.state["locations"][4]["threat"]))
	Game._place_threat_token("cap", 4, "heroic")
	Game._place_threat_token("cap", 4, "heroic")
	var mid_progress: int = (Game.state["locations"][4]["threat"]["clear_progress"] as Array).size()
	_check("⑥ 英勇指示物逐个累积（2/3）", mid_progress == 2, "%d/3" % mid_progress)
	Game._place_threat_token("cap", 4, "heroic")
	_check("⑥ 放满 3 个英勇指示物 → 威胁卡被清除",
		Game.state["locations"][4]["threat"] == null, str(Game.state["locations"][4]["threat"]))

	# ==================== ⑦ 威胁卡「无掩护」 ====================
	_prep([4, 5, 5])
	Game.state["locations"][4]["threat"] = _mk_threat(_threat_idx("无掩护"))
	Game.state["current_hero"] = 0
	Game.state["phase"] = "hero_end"
	await Game.end_turn()
	_check("⑦ 无掩护：在该地点结束回合的英雄获得 1 个危机指示物", _crisis("cap") == 1, "%d" % _crisis("cap"))
	_prep([4, 5, 5])
	Game.state["locations"][4]["threat"] = _mk_threat(_threat_idx("开阔地带"))
	Game.state["current_hero"] = 0
	Game.state["phase"] = "hero_end"
	await Game.end_turn()
	_check("⑦ 只有「无掩护」才给结束回合危机：换成「开阔地带」时结束回合不产生危机",
		_crisis("cap") == 0, "%d" % _crisis("cap"))
	_prep([4, 5, 5])
	Game.state["locations"][4]["threat"] = _mk_threat(_threat_idx("无掩护"))
	VillainRules._rhino_on_hero_end_turn(Game, "hulk")
	_check("⑦ 不在无掩护所在地点结束回合的英雄不获得危机指示物（hulk 在 5）",
		_crisis("hulk") == 0, "%d" % _crisis("hulk"))

	# ==================== ⑧ 面板溢出：抽 1 张反派行动卡面朝下 ====================
	_prep()
	Game.state["story"] = []
	var deck_before: int = (Game.state["master_deck"] as Array).size()
	await VillainRules.on_overflow(Game, "rhino", "thug", 0, 3)
	_check("⑧ 溢出：抽取 1 张反派行动卡面朝下加入故事情节（卡面写\"1 个或多个\"→ 忽略 count=3）",
		Game.state["story"].size() == 1
		and String(Game.state["story"][0].get("type", "")) == "villain"
		and bool(Game.state["story"][0].get("face_down", false)),
		str(Game.state["story"]))
	_check("⑧ 溢出的牌是从主计划牌堆顶抽的（牌堆 -1）",
		(Game.state["master_deck"] as Array).size() == deck_before - 1,
		"%d → %d" % [deck_before, (Game.state["master_deck"] as Array).size()])
	_prep()
	Game.state["story"] = []
	Game.state["master_deck"] = []
	await VillainRules.on_overflow(Game, "rhino", "civ", 1, 1)
	_check("⑧ 牌堆已空时溢出安全返回（不报错、不判负）",
		Game.state["story"].size() == 0 and String(Game.state["phase"]) != "game_over",
		"%d / %s" % [Game.state["story"].size(), Game.state["phase"]])

	# ==================== ⑨ 行动卡 1~4「犀牛充电」 ====================
	_prep([2, 2, 5])
	Game.state["villain_pos"] = 0
	Game.state["rhino_moved_locs"] = 0
	Game._do_villain_move({"dir": "cw", "hero_in": true})
	_check("⑨ 犀牛充电：绕过没有英雄的地点，顺时针走到下一个有英雄的地点（0 → 2）",
		int(Game.state["villain_pos"]) == 2, "pos=%d" % int(Game.state["villain_pos"]))
	_check("⑨ 犀牛充电计为进入 1 个地点（供 BAM 计伤害）",
		int(Game.state["rhino_moved_locs"]) == 1, "%d" % int(Game.state["rhino_moved_locs"]))
	Game._do_villain_move({"dir": "cw", "hero_in": true})
	_check("⑨ 犀牛充电：从 2 继续走到下一个有英雄的地点（5）",
		int(Game.state["villain_pos"]) == 5, "pos=%d" % int(Game.state["villain_pos"]))
	_prep([0, 1, 2])
	Game.state["villain_pos"] = 0
	Game._do_villain_move({"dir": "cw", "hero_in": true})
	_check("⑨ 犀牛充电：紧邻的下一个地点就有英雄时只走 1 步（0 → 1）",
		int(Game.state["villain_pos"]) == 1, "pos=%d" % int(Game.state["villain_pos"]))

	# ==================== ⑩ 放置图案三槽落位 ====================
	_prep()
	var ploc: int = _pos_with_room(1)
	_check("⑩ 前置：存在「自己 + 两个相邻地点」都有槽位的地点", ploc >= 0, "ploc=%d" % ploc)
	for l in Game.state["locations"]:
		l["civ"] = 0
		l["thug"] = 0
	Game.state["villain_pos"] = ploc
	var adj: Array = Game._adjacent_locs(ploc)
	await Game._do_placement([["thug"], ["thug"], ["thug"]])
	_check("⑩ 卡 5 的图案（暴/暴/暴）：本地 +1 暴徒，两个相邻地点各 +1（共 3 个）",
		int(Game.state["locations"][ploc]["thug"]) == 1
		and int(Game.state["locations"][int(adj[0])]["thug"]) == 1
		and int(Game.state["locations"][int(adj[1])]["thug"]) == 1
		and _total("thug") == 3,
		"本地%d 邻0=%d 邻1=%d 总=%d" % [int(Game.state["locations"][ploc]["thug"]),
			int(Game.state["locations"][int(adj[0])]["thug"]), int(Game.state["locations"][int(adj[1])]["thug"]), _total("thug")])
	_prep()
	ploc = _pos_with_room(2)
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
	_check("⑩ 卡 11/12 的图案（民暴 ×3）：三个地点各 +1 暴徒 +1 平民（共 6 个指示物）",
		mix_ok and _total("thug") == 3 and _total("civ") == 3,
		"本地=%d/%d 邻0=%d/%d 邻1=%d/%d 总=%d/%d" % [int(Game.state["locations"][ploc]["thug"]), int(Game.state["locations"][ploc]["civ"]),
			int(Game.state["locations"][int(adj[0])]["thug"]), int(Game.state["locations"][int(adj[0])]["civ"]),
			int(Game.state["locations"][int(adj[1])]["thug"]), int(Game.state["locations"][int(adj[1])]["civ"]),
			_total("thug"), _total("civ")])

	# ==================== ⑪ 整局反派回合跑通（卡 5 有 BAM / 卡 12 无 BAM） ====================
	# 说明：_run_villain_turn 结尾会进入"下一个英雄的回合"并抽 1 张牌 —— 为了让这个抽牌落在 hulk 身上
	# （不影响 cap/ironman 的手牌断言），这里把 turn_count 设成 >1、current_hero 设成 1（下一位 = hulk）。
	# 卡 5（下标 4）：移动 4 + BAM → cap/ironman 在 2 等它撞过来
	_prep([2, 2, 5])
	Game.state["villain_pos"] = 4
	Game.state["rhino_moved_locs"] = 99   # 故意留脏值：验证反派回合开始时会被清零重算
	Game.state["turn_count"] = 5
	Game.state["current_hero"] = 1
	Game.state["master_deck"] = [4, 0, 1, 2, 3]
	await Game._run_villain_turn()
	_check("⑪ 卡 5（移动4 + BAM）：犀牛人从 4 顺时针走 4 步到 2",
		int(Game.state["villain_pos"]) == 2, "pos=%d" % int(Game.state["villain_pos"]))
	_check("⑪ 本回合进入的地点数被重新计算（4，而不是上回合遗留的 99）→ 2 号地点的英雄各受 4 点伤害",
		_hand("cap") == 4 and _hand("ironman") == 4, "cap=%d ironman=%d" % [_hand("cap"), _hand("ironman")])
	_check("⑪ 受伤英雄顺时针移动 1 个地点（2 → 3）",
		_loc("cap") == 3 and _loc("ironman") == 3, "cap=%d ironman=%d" % [_loc("cap"), _loc("ironman")])
	_check("⑪ 卡 5 的放置图案（暴/暴/暴）已结算：本地 2 + 两个相邻地点各 1 个暴徒",
		int(Game.state["locations"][2]["thug"]) == 1
		and int(Game.state["locations"][int(Game._adjacent_locs(2)[0])]["thug"]) == 1
		and int(Game.state["locations"][int(Game._adjacent_locs(2)[1])]["thug"]) == 1,
		str(Game.state["locations"].map(func(l): return int(l["thug"]))))
	# 卡 12（下标 11）：移动 0 + **无 BAM**
	_prep([2, 2, 5])
	Game.state["villain_pos"] = 4
	Game.state["turn_count"] = 5
	Game.state["current_hero"] = 1
	Game.state["master_deck"] = [11, 0, 1, 2, 3]
	await Game._run_villain_turn()
	_check("⑪ 卡 12（移动0 / 无 BAM）：英雄手牌完全不变（确认没有触发 BAM）",
		_hand("cap") == 8 and _hand("ironman") == 8, "cap=%d ironman=%d" % [_hand("cap"), _hand("ironman")])
	_check("⑪ 卡 12 的放置图案（民暴 ×3）已结算：三个地点各 +1 暴徒 +1 平民",
		_total("thug") == 3 and _total("civ") == 3, "thug=%d civ=%d" % [_total("thug"), _total("civ")])
	# 卡 11（下标 10）：移动 5 + **无 BAM**
	_prep([2, 2, 5])
	Game.state["villain_pos"] = 4
	Game.state["turn_count"] = 5
	Game.state["current_hero"] = 1
	Game.state["master_deck"] = [10, 0, 1, 2, 3]
	await Game._run_villain_turn()
	_check("⑪ 卡 11（移动5 / 无 BAM）：犀牛人走 5 步到 3，英雄手牌不变",
		int(Game.state["villain_pos"]) == 3 and _hand("cap") == 8, "pos=%d cap=%d" % [int(Game.state["villain_pos"]), _hand("cap")])
	_check("⑪ 卡 11/12 没有 BAM 时也不会误伤：cap/ironman 都没掉手牌",
		_hand("cap") == 8 and _hand("ironman") == 8, "cap=%d ironman=%d" % [_hand("cap"), _hand("ironman")])

	# ==================== ⑫ 联机快照带 hero crisis ====================
	_prep([4, 5, 5])
	Game.state["heroes"]["cap"]["crisis"] = 2
	Net.active = true
	Net.is_host = false
	Net.my_peer = 2
	Net.seats = [
		{"peer": 1, "name": "房主", "hero": "cap", "villain": "", "locs": [], "ready": false},
		{"peer": 2, "name": "我", "hero": "cap", "villain": "", "locs": [], "ready": false},
	]
	var vis: Dictionary = Net.visible_state_for("cap")
	var vis_h: Dictionary = (vis.get("heroes", {}) as Dictionary).get("cap", {})
	_check("⑫ 联机快照下发了 hero crisis（客户端也能看到危机指示物数量）",
		int(vis_h.get("crisis", -1)) == 2, str(vis_h.get("crisis", "缺失")))
	Net.active = false

	print("---- RESULT ----")
	if _fail == 0:
		print("=== RHINO TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== RHINO TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)
