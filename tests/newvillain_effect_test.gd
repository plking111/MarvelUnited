extends Node
## 新反派（秃鹫/神秘客/章鱼博士）与英雄"牵制反派 / 威胁卡"类效果的兼容性审计：
## A. 迈尔斯·蛛网（若在反派所在地点结束回合 → 推迟反派下一个回合）× 4 个反派（含控制组）
## B. 蜘猪侠·卡通蛛网（取消下一次反派移动）× 4 个反派
## C. 格温蛛·蛛网交织者（交换两张威胁卡）对神秘客的**背面**威胁卡：不泄露卡名/正面，且交换仍生效
## D. 迈尔斯·毒液突袭 打神秘客：无破碎幻像时免疫；翻开后能造成伤害
## E. 背面朝上的威胁卡不能被选为攻击目标；F. 背面朝上的威胁卡不能被清除
var _fail := 0
var _prompts: Array = []
var _answers: Array = []

func _check(n: String, ok: bool, d: String) -> void:
	if ok: print("PASS: " + n)
	else: _fail += 1; print("FAIL: " + n + " — " + d)

func _ready() -> void:
	Game.autopilot = true
	Events.prompt_action.connect(func(rows: Array, _t: String, cb: Callable) -> void:
		_prompts.append(rows.duplicate(true))
		var a := 0
		if _answers.size() > 0:
			a = int(_answers.pop_front())
		await get_tree().process_frame
		cb.call(a))
	Events.prompt_confirm.connect(func(_t: String, cb: Callable) -> void:
		await get_tree().process_frame
		cb.call(true))
	Events.prompt_choice.connect(func(_o: Array, _t: String, cb: Callable) -> void:
		await get_tree().process_frame
		cb.call(0))
	Events.prompt_hand_card.connect(func(cb: Callable, _t: String, hid: String, c: int) -> void:
		await get_tree().process_frame
		var h: Array = Game.state["heroes"][hid]["hand"]
		var out: Array = []
		for i in range(mini(c, h.size())):
			out.append(i)
		cb.call(out))
	Events.prompt_story_card.connect(func(cb: Callable, _t: String, _f: String) -> void:
		await get_tree().process_frame
		cb.call(0))
	Events.prompt_deck_card.connect(func(cb: Callable, _t: String, _h: String) -> void:
		await get_tree().process_frame
		cb.call(0))

	for vid in ["redskull", "vulture", "mysterio", "docock"]:
		await _test_miles_web(vid)
		await _test_cartoon_web(vid)
	await _test_web_weaver_face_down()
	await _test_miles_web_off_location()
	await _test_venom_strike_mysterio()
	await _test_face_down_not_target()
	await _test_face_down_not_clearable()

	if _fail == 0:
		print("=== NEWVILLAIN EFFECT PASSED ===")
		get_tree().quit(0)
	else:
		print("=== NEWVILLAIN EFFECT FAILED (%d) ===" % _fail)
		get_tree().quit(1)

# ---------------------------------------------------------------- helpers

func _find_card(hid: String, etype: String) -> int:
	var cards: Array = DB.hero_cards(hid)
	for i in range(cards.size()):
		var e: Variant = cards[i].get("effect", null)
		if e != null and String(e.get("type", "")) == etype:
			return i
	return -1

## 打出一张带指定效果的英雄卡（hand[0]=该卡），返回是否成功
func _play_effect_card(hid: String, etype: String) -> bool:
	var ci := _find_card(hid, etype)
	if ci < 0:
		_check("%s 有 %s 卡" % [hid, etype], false, "找不到该效果卡")
		return false
	Game.state["current_hero"] = Game.state["hero_ids"].find(hid)
	var h: Dictionary = Game.state["heroes"][hid]
	h["hand"] = [ci, 0]      # 留 1 张底牌，避免回合结束被判无手牌 KO
	h["deck"] = [1, 2, 3, 4]
	Game.state["action_symbols"] = []
	Game.state["phase"] = "hero_play"
	await Game.play_card(0)
	return true

# ---------------------------------------------------------------- A. 迈尔斯蛛网

func _test_miles_web(vid: String) -> void:
	# 控制组：不打蛛网、打满节奏 → 反派回合必须正常进行
	Game.setup(vid, ["miles", "spiderman"], "none", "base")
	var mh: Dictionary = Game.state["heroes"]["miles"]
	mh["location"] = Game.state["villain_pos"]
	mh["hand"] = [0, 1]
	mh["miles_web_armed"] = false
	Game.state["hero_cards_played"] = 3
	var tc0: int = int(Game.state["turn_count"])
	Game.state["phase"] = "hero_end"
	await Game.end_turn()
	var ran := int(Game.state["turn_count"]) == tc0 + 1
	_check("[%s] 控制组：打满节奏后反派回合正常进行" % vid, ran,
		"turn_count %d -> %d" % [tc0, int(Game.state["turn_count"])])

	# 实验组：打蛛网 + 在反派所在地点结束回合 → 反派回合被推迟
	Game.setup(vid, ["miles", "spiderman"], "none", "base")
	if not await _play_effect_card("miles", "miles_web"):
		return
	mh = Game.state["heroes"]["miles"]
	_check("[%s] 蛛网：打出后已标记" % vid, bool(mh.get("miles_web_armed", false)), "未标记")
	mh["location"] = Game.state["villain_pos"]
	Game.state["hero_cards_played"] = 3
	var tc1: int = int(Game.state["turn_count"])
	Game.state["phase"] = "hero_end"
	await Game.end_turn()
	_check("[%s] 蛛网：反派回合被推迟（未发生）" % vid, int(Game.state["turn_count"]) == tc1,
		"turn_count %d -> %d" % [tc1, int(Game.state["turn_count"])])
	_check("[%s] 蛛网：推迟后游戏仍在进行（未卡死）" % vid, Game.state["phase"] != "game_over",
		String(Game.state["phase"]))

## 迈尔斯不在反派所在地点 → 蛛网不触发（反派回合照常）
func _test_miles_web_off_location() -> void:
	Game.setup("mysterio", ["miles", "spiderman"], "none", "base")
	if not await _play_effect_card("miles", "miles_web"):
		return
	var mh: Dictionary = Game.state["heroes"]["miles"]
	mh["location"] = (int(Game.state["villain_pos"]) + 1) % Game.LOCATION_COUNT
	Game.state["hero_cards_played"] = 3
	var tc: int = int(Game.state["turn_count"])
	Game.state["phase"] = "hero_end"
	await Game.end_turn()
	_check("[神秘客] 蛛网：英雄不在反派地点时不触发（反派回合照常）",
		int(Game.state["turn_count"]) == tc + 1,
		"turn_count %d -> %d" % [tc, int(Game.state["turn_count"])])

# ---------------------------------------------------------------- B. 蜘猪侠卡通蛛网

func _test_cartoon_web(vid: String) -> void:
	Game.setup(vid, ["spiderpig", "spiderman"], "none", "base")
	if not await _play_effect_card("spiderpig", "cartoon_web"):
		return
	var ph: Dictionary = Game.state["heroes"]["spiderpig"]
	_check("[%s] 卡通蛛网：打出后已标记" % vid, bool(ph.get("cartoon_web_armed", false)), "未标记")
	ph["location"] = Game.state["villain_pos"]
	Game.state["hero_cards_played"] = 0     # 先不让反派回合发生，只验证标记与移动取消
	Game.state["phase"] = "hero_end"
	await Game.end_turn()
	_check("[%s] 卡通蛛网：在反派地点结束回合 → 取消失下次移动" % vid,
		bool(Game.state.get("no_villain_move_next", false)), "未设置标记")
	var vp: int = int(Game.state["villain_pos"])
	Game._do_villain_move(2)
	_check("[%s] 卡通蛛网：反派停留原地" % vid, int(Game.state["villain_pos"]) == vp,
		"%d -> %d" % [vp, int(Game.state["villain_pos"])])
	_check("[%s] 卡通蛛网：标记已消耗" % vid, not bool(Game.state.get("no_villain_move_next", false)), "仍为 true")

# ---------------------------------------------------------------- C. 蛛网交织者 × 神秘客背面威胁卡

func _test_web_weaver_face_down() -> void:
	Game.setup("mysterio", ["gwenspider", "spiderman"], "none", "base")
	Game.autopilot = false                   # 需要真实弹窗来检查内容
	if not await _play_effect_card("gwenspider", "web_weaver"):
		return
	var locs: Array = []
	var tidx0: Array = []
	for i in range(Game.LOCATION_COUNT):
		if Game.state["locations"][i]["threat"] != null:
			locs.append(i)
			tidx0.append(int(Game.state["locations"][i]["threat"].get("_tidx", -1)))
	_check("蛛网交织者：场上有 ≥2 张背面威胁卡", locs.size() >= 2, "%d" % locs.size())
	_prompts = []
	_answers = [0, 0]
	await Game.trigger_effect()
	var leak_name := false
	var not_back := false
	var n_rows := 0
	for rows in _prompts:
		for r in rows:
			n_rows += 1
			var txt := String(r.get("text", ""))
			if txt.contains("破碎幻像") or txt.contains("镜花水月") or txt.contains("战斗无人机"):
				leak_name = true
			if not String(r.get("img", "")).ends_with("mysterio/threat_back.png"):
				not_back = true
	_check("蛛网交织者：弹窗有内容", n_rows >= 2, "%d 行" % n_rows)
	_check("蛛网交织者：未翻开不泄露卡名", not leak_name, "文本含卡名")
	_check("蛛网交织者：背面朝上只显示卡背", not not_back, "出现正面图")
	var swapped: bool = int(Game.state["locations"][locs[0]]["threat"].get("_tidx", -1)) == tidx0[1] \
		and int(Game.state["locations"][locs[1]]["threat"].get("_tidx", -1)) == tidx0[0]
	_check("蛛网交织者：两张威胁卡确实交换", swapped,
		"loc%d tidx %d->%d, loc%d tidx %d->%d" % [locs[0], tidx0[0], int(Game.state["locations"][locs[0]]["threat"].get("_tidx", -1)),
			locs[1], tidx0[1], int(Game.state["locations"][locs[1]]["threat"].get("_tidx", -1))])
	Game.autopilot = true

# ---------------------------------------------------------------- D. 毒液突袭 × 神秘客

func _test_venom_strike_mysterio() -> void:
	Game.setup("mysterio", ["miles", "spiderman"], "none", "base")
	Game.autopilot = true
	if not await _play_effect_card("miles", "venom_strike"):
		return
	Game.state["missions_completed"] = 2
	Game.state["villain_hp"] = 6
	Game.state["villain_hp_max"] = 6
	var mh: Dictionary = Game.state["heroes"]["miles"]
	mh["location"] = Game.state["villain_pos"]
	var vl: int = int(mh["location"])
	Game.state["locations"][vl]["thug"] = 0
	Game.state["locations"][vl]["civ"] = 0
	Game.state["effect_used"] = false
	await Game.trigger_effect()
	_check("毒液突袭：无破碎幻像时神秘客免疫", int(Game.state["villain_hp"]) == 6,
		"hp=%d" % int(Game.state["villain_hp"]))
	# 翻开一张破碎幻像（模拟已揭示）
	var iloc: int = (vl + 1) % Game.LOCATION_COUNT
	Game.state["locations"][iloc]["threat"] = {
		"name": "破碎幻像", "text": "", "hp": 0, "heroic_tokens": 0, "arrival": false, "bam": false,
		"constant": true, "_face_down": false, "reveal": "enable_damage", "unclearable": true, "_tidx": 1}
	Game.state["effect_used"] = false
	var hp_before: int = int(Game.state["villain_hp"])
	await Game.trigger_effect()
	_check("毒液突袭：有破碎幻像时可打伤神秘客", int(Game.state["villain_hp"]) < hp_before,
		"hp %d -> %d" % [hp_before, int(Game.state["villain_hp"])])

# ---------------------------------------------------------------- E. 背面威胁卡不可被攻击

func _test_face_down_not_target() -> void:
	Game.setup("mysterio", ["cap", "ironman"], "none", "base")
	Game.autopilot = false
	Game.state["current_hero"] = 0
	Game.state["phase"] = "hero_actions"
	Game.state["action_symbols"] = ["attack"]
	Game.state["missions_completed"] = 0
	Game.state["locations"][0]["thug"] = 0
	Game.state["locations"][0]["threat"] = {
		"name": "测试爪牙(背面)", "text": "", "hp": 2, "heroic_tokens": 0, "arrival": false, "bam": false,
		"constant": false, "_face_down": true, "_tidx": 0}
	Game.state["heroes"]["cap"]["location"] = 0
	_prompts = []
	_answers = [0]
	await Game._execute_attack("cap", "attack")
	await get_tree().process_frame
	var offered := false
	for rows in _prompts:
		for r in rows:
			if String(r.get("text", "")).contains("爪牙"):
				offered = true
	_check("背面朝上的威胁卡不作为攻击目标", not offered, "攻击弹窗里出现了爪牙目标")
	_check("背面朝上的威胁卡未被扣血", int(Game.state["locations"][0]["threat"]["hp"]) == 2,
		"hp=%d" % int(Game.state["locations"][0]["threat"]["hp"]))
	Game.autopilot = true

# ---------------------------------------------------------------- F. 背面威胁卡不可被清除

func _test_face_down_not_clearable() -> void:
	Game.setup("mysterio", ["cap", "ironman"], "none", "base")
	Game.state["locations"][2]["threat"] = {
		"name": "镜花水月", "text": "", "hp": 0, "heroic_tokens": 0, "arrival": false, "bam": false,
		"constant": false, "_face_down": true, "reveal": "add_civ", "_tidx": 4}
	Game._clear_threat(2)
	_check("背面朝上的威胁卡不能被清除", Game.state["locations"][2]["threat"] != null,
		"threat=%s" % str(Game.state["locations"][2]["threat"] != null))
	_check("背面朝上的威胁卡放不上指示物",
		Game._threat_placeable_sym(Game.state["locations"][2]["threat"]) == "",
		Game._threat_placeable_sym(Game.state["locations"][2]["threat"]))
