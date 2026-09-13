extends Node
## 神秘客（邪恶六人组）回归：数据 + 开局背面威胁 + 幻像免疫 + 翻牌揭示效果 + BAM/溢出 + 全息投影/虚假英雄行径
var _fail := 0
func _check(n: String, ok: bool, d: String) -> void:
	if ok: print("PASS: " + n)
	else: _fail += 1; print("FAIL: " + n + " — " + d)

func _ready() -> void:
	Game.autopilot = false
	Events.prompt_confirm.connect(func(_t: String, cb: Callable) -> void:
		await get_tree().process_frame
		cb.call(false))
	Events.prompt_choice.connect(func(_o: Array, _t: String, cb: Callable) -> void:
		await get_tree().process_frame
		cb.call(0))
	Events.prompt_action.connect(func(_r: Array, _t: String, cb: Callable) -> void:
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

	# ---------- 1. 数据 ----------
	var v: Dictionary = DB.villain("mysterio")
	_check("神秘客存在", not v.is_empty(), "")
	_check("生命 3/6/8", int(v["health"]["2"]) == 3 and int(v["health"]["3"]) == 6 and int(v["health"]["4"]) == 8, str(v["health"]))
	_check("12 张行动卡", v["actions"].size() == 12, "%d" % v["actions"].size())
	_check("6 张威胁卡", v["threats"].size() == 6, "%d" % v["threats"].size())
	var n_illusion := 0
	var n_clear := 0
	for t in v["threats"]:
		if t["name"] == "破碎幻像":
			n_illusion += 1
		if t.has("clear"):
			n_clear += 1
	_check("两张破碎幻像", n_illusion == 2, "%d" % n_illusion)
	var n_unclear := 0
	for t in v["threats"]:
		if t["name"] == "破碎幻像" and t.get("unclearable", false):
			n_unclear += 1
	_check("两张破碎幻像永不可清除(unclearable)", n_unclear == 2, "%d" % n_unclear)
	_check("两张clear型(战斗无人机)", n_clear == 2, "%d" % n_clear)
	_check("无战利品轨道/plot none", String(v.get("plot_track", "")) == "none", String(v.get("plot_track", "")))

	# ---------- 2. 开局：威胁全部背面朝上 ----------
	Game.setup("mysterio", ["cap", "ironman", "hulk"], "none", "base")
	var all_fd := true
	var n_threat := 0
	for l in Game.state["locations"]:
		if l["threat"] != null:
			n_threat += 1
			if not l["threat"].get("_face_down", false):
				all_fd = false
	_check("开局威胁背面朝上", all_fd and n_threat > 0, "威胁数=%d" % n_threat)
	_check("无已揭示幻像时不可受伤", not Game._mysterio_illusion_present(), "")

	# ---------- 3. 幻像免疫 / 揭示后可受伤 ----------
	Game.state["missions_completed"] = 2
	Game.state["villain_hp"] = 6
	var vloc: int = Game.state["villain_pos"]
	# 保证秃鹫所在地点没有"电磁飞翼"之类干扰：直接攻击反派
	await Game._perform_attack_at(vloc, "villain", "cap")
	_check("无幻像时攻击无效", int(Game.state["villain_hp"]) == 6, "hp=%d" % int(Game.state["villain_hp"]))
	# 揭露出一张破碎幻像（把某地点威胁换成幻像并翻开）
	var iloc := (vloc + 1) % Game.LOCATION_COUNT
	Game.state["locations"][iloc]["threat"] = {"name": "破碎幻像", "text": "", "hp": 0, "heroic_tokens": 0, "arrival": false, "bam": false, "constant": true, "_face_down": true, "reveal": "enable_damage", "_tidx": 1}
	var deck_b: int = Game.state["master_deck"].size()
	await Game._reveal_threat_at(iloc, "cap")
	_check("揭示幻像后场上有幻像", Game._mysterio_illusion_present(), "")
	await Game._perform_attack_at(vloc, "villain", "cap")
	_check("有幻像时可受伤", int(Game.state["villain_hp"]) == 5, "hp=%d" % int(Game.state["villain_hp"]))

	# ---------- 4. 揭示效果：战斗无人机 / 镜花水月 ----------
	var dloc := (vloc + 2) % Game.LOCATION_COUNT
	Game.state["locations"][dloc]["threat"] = {"name": "战斗无人机", "text": "", "hp": 0, "heroic_tokens": 0, "arrival": false, "bam": false, "constant": false, "_face_down": true, "clear": ["attack", "attack", "attack"], "clear_progress": [], "reveal": "damage1", "_tidx": 0}
	Game.state["heroes"]["cap"]["hand"] = [0, 1, 2, 3, 4]
	var hand_b: int = Game.state["heroes"]["cap"]["hand"].size()
	await Game._reveal_threat_at(dloc, "cap")
	_check("战斗无人机揭示扣1点(弃1张)", Game.state["heroes"]["cap"]["hand"].size() == hand_b - 1,
		"hand %d->%d" % [hand_b, Game.state["heroes"]["cap"]["hand"].size()])
	var mloc := (vloc + 3) % Game.LOCATION_COUNT
	Game.state["locations"][mloc]["civ"] = 0
	Game.state["locations"][mloc]["thug"] = 0
	Game.state["locations"][mloc]["threat"] = {"name": "镜花水月", "text": "", "hp": 0, "heroic_tokens": 0, "arrival": false, "bam": false, "constant": false, "_face_down": true, "reveal": "add_thug", "_tidx": 2}
	await Game._reveal_threat_at(mloc, "cap")
	_check("镜花水月(暴徒)揭示加1暴徒", int(Game.state["locations"][mloc]["thug"]) == 1, "thug=%d" % int(Game.state["locations"][mloc]["thug"]))
	Game.state["locations"][mloc]["threat"] = {"name": "镜花水月", "text": "", "hp": 0, "heroic_tokens": 0, "arrival": false, "bam": false, "constant": false, "_face_down": true, "reveal": "add_civ", "_tidx": 4}
	await Game._reveal_threat_at(mloc, "cap")
	_check("镜花水月(平民)揭示加1平民", int(Game.state["locations"][mloc]["civ"]) == 1, "civ=%d" % int(Game.state["locations"][mloc]["civ"]))

	# ---------- 5. BAM：平民暴徒互换 + 放置1平民 ----------
	Game.state["locations"][0]["civ"] = 2
	Game.state["locations"][0]["thug"] = 1
	Game.state["locations"][1]["civ"] = 0
	Game.state["locations"][1]["thug"] = 3
	Game.state["villain_pos"] = 5
	Game.state["locations"][5]["civ"] = 0
	Game.state["locations"][5]["thug"] = 0
	Game.state["locations"][5]["threat"] = null
	await VillainRules._mysterio_bam(Game)
	_check("BAM 平民暴徒互换", int(Game.state["locations"][0]["civ"]) == 1 and int(Game.state["locations"][0]["thug"]) == 2
		and int(Game.state["locations"][1]["civ"]) == 3 and int(Game.state["locations"][1]["thug"]) == 0,
		"loc0 civ/thug=%d/%d, loc1=%d/%d" % [int(Game.state["locations"][0]["civ"]), int(Game.state["locations"][0]["thug"]), int(Game.state["locations"][1]["civ"]), int(Game.state["locations"][1]["thug"])])
	_check("BAM 在神秘客地点放1平民", int(Game.state["locations"][5]["civ"]) == 1, "civ=%d" % int(Game.state["locations"][5]["civ"]))

	# ---------- 6. 溢出：抽一张行动卡背面朝上入故事 ----------
	var deck_before: int = Game.state["master_deck"].size()
	var story_before: int = Game.state["story"].size()
	await VillainRules._mysterio_overflow(Game, 2)
	var last: Dictionary = Game.state["story"].back()
	_check("溢出抽牌入故事(背面朝上)", Game.state["master_deck"].size() == deck_before - 1 and Game.state["story"].size() == story_before + 1 and last.get("face_down", false) == true,
		"deck %d->%d, story %d->%d" % [deck_before, Game.state["master_deck"].size(), story_before, Game.state["story"].size()])

	# ---------- 7. 全息投影：威胁重洗并重新背面朝上 ----------
	var before_n := 0
	for l in Game.state["locations"]:
		if l["threat"] != null:
			before_n += 1
	await VillainRules._mysterio_hologram(Game)
	var after_n := 0
	var after_fd := true
	for l in Game.state["locations"]:
		if l["threat"] != null:
			after_n += 1
			if not l["threat"].get("_face_down", false):
				after_fd = false
	_check("全息投影后威胁仍背面朝上", after_fd and after_n == before_n, "before=%d after=%d" % [before_n, after_n])

	# ---------- 8. 虚假英雄行径 ----------
	Game.state["locations"][3]["civ"] = 4
	Game.state["locations"][3]["thug"] = 2
	Game.state["villain_pos"] = 0
	var deck_b2: int = Game.state["master_deck"].size()
	await VillainRules._mysterio_false_hero(Game)
	_check("虚假英雄行径移动到平民最多处", int(Game.state["villain_pos"]) == 3, "pos=%d" % int(Game.state["villain_pos"]))
	_check("虚假英雄行径清空该地点民/暴", int(Game.state["locations"][3]["civ"]) == 0 and int(Game.state["locations"][3]["thug"]) == 0,
		"civ=%d thug=%d" % [int(Game.state["locations"][3]["civ"]), int(Game.state["locations"][3]["thug"])])
	_check("虚假英雄行径抽1张背面牌", Game.state["master_deck"].size() == deck_b2 - 1, "deck %d->%d" % [deck_b2, Game.state["master_deck"].size()])

	if _fail == 0:
		print("=== MYSTERIO TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== MYSTERIO FAILED (%d) ===" % _fail)
		get_tree().quit(1)
