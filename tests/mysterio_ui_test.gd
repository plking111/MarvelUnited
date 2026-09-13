extends Node
## 神秘客 UI 回归：
## ① 背面威胁卡在地图上显示卡背；翻开后显示**正确正面**（同名卡按 _tidx 取图，不串图）
## ② 翻开流程两步：先**选择要使用的行动**（行动符号 / 行动指示物，可取消），再选翻开哪一张
## ③ 弹窗**只显示卡背**（盲翻，按地点选），不得泄露正面
## ④ 破碎幻像(unclearable) 翻开后永久留在场上：英勇/攻击/效果都不能清除；镜花水月仍可清除
var _fail := 0
var _prompts: Array = []
var _answers: Array = []

func _check(n: String, ok: bool, d: String) -> void:
	if ok: print("PASS: " + n)
	else: _fail += 1; print("FAIL: " + n + " — " + d)

func _ready() -> void:
	Game.autopilot = false
	Events.prompt_action.connect(func(rows: Array, title: String, cb: Callable) -> void:
		_prompts.append({"title": title, "rows": rows.duplicate(true)})
		var a := 0
		if _answers.size() > 0:
			a = int(_answers.pop_front())
		await get_tree().process_frame
		cb.call(a))
	Events.prompt_confirm.connect(func(_t: String, cb: Callable) -> void:
		await get_tree().process_frame
		cb.call(false))
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

	Game.pending_setup = {"villain": "mysterio", "heroes": ["cap", "ironman"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(4):
		await get_tree().process_frame

	# ---------- ① 背面 → 卡背 ----------
	var li := -1
	for i in range(Game.LOCATION_COUNT):
		var t: Variant = Game.state["locations"][i]["threat"]
		if t != null and t.get("_face_down", false):
			li = i
			break
	_check("开局存在背面威胁卡", li >= 0, "li=%d" % li)
	var lv: LocationView = inst._loc_views[li]
	var before_path: String = lv.threat.texture.resource_path if lv.threat.texture != null else "<null>"
	_check("背面朝上显示卡背", before_path.ends_with("mysterio/threat_back.png"), before_path)

	# ---------- ② 两步翻开：先选行动，再选卡；弹窗只显示卡背 ----------
	var t0: Dictionary = Game.state["locations"][li]["threat"]
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	Game.state["used_tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
	Game.state["action_symbols"] = ["move", "move"]
	_prompts = []
	_answers = [0, 0]
	await Game.reveal_threat_choice()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("翻开流程共 2 个弹窗（选行动 → 选卡）", _prompts.size() == 2, "%d" % _prompts.size())
	if _prompts.size() == 2:
		var arows: Array = _prompts[0]["rows"]
		var atexts: Array = []
		for r in arows:
			atexts.append(String(r.get("text", "")))
		_check("弹窗①列出可用行动", atexts.size() == 2 and String(atexts[0]).begins_with("移动行动"),
			str(atexts))
		_check("弹窗①有取消选项", String(atexts[-1]).contains("取消"), str(atexts))
		var all_back := true
		for r in _prompts[1]["rows"]:
			if not String(r.get("img", "")).ends_with("mysterio/threat_back.png"):
				all_back = false
		_check("弹窗②只显示卡背(盲翻)", all_back, str(_prompts[1]["rows"]))
	_check("翻开消耗 1 个所选行动(移动符号)", Game.state["action_symbols"] == ["move"], str(Game.state["action_symbols"]))
	_check("翻牌后 _face_down=false", not t0.get("_face_down", true), str(t0.get("_face_down", true)))
	var after_path: String = lv.threat.texture.resource_path if lv.threat.texture != null else "<null>"
	var want: int = int(t0.get("_tidx", 0)) + 1
	_check("翻开后显示正面且与 _tidx 一致", after_path.ends_with("threat_%02d.png" % want),
		"path=%s want=threat_%02d" % [after_path, want])
	_check("翻开后不再隐藏英勇槽", lv.heroic_slots[0].visible, "slots0.visible=%s" % str(lv.heroic_slots[0].visible))

	# ---------- ③ 可以指定用哪个行动（选第 2 项=攻击符号） ----------
	Game.state["action_symbols"] = ["move", "attack"]
	_prompts = []
	_answers = [1, 0]
	await Game.reveal_threat_choice()
	await get_tree().process_frame
	_check("选攻击符号 → 消耗攻击保留移动", Game.state["action_symbols"] == ["move"], str(Game.state["action_symbols"]))

	# ---------- ④ 取消不消耗、不翻卡 ----------
	var fd_before := Game._face_down_threat_locs().size()
	Game.state["action_symbols"] = ["move"]
	_prompts = []
	_answers = [1]   # 第 1 行之后 = "取消（不翻开）"
	await Game.reveal_threat_choice()
	await get_tree().process_frame
	_check("取消后行动未消耗", Game.state["action_symbols"] == ["move"], str(Game.state["action_symbols"]))
	_check("取消后没有翻卡", Game._face_down_threat_locs().size() == fd_before,
		"%d -> %d" % [fd_before, Game._face_down_threat_locs().size()])

	# ---------- ⑤ 也可以用行动指示物（万能）支付 ----------
	Game.state["action_symbols"] = []
	Game.state["used_tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
	Game.state["heroes"]["cap"]["tokens"] = {"move": 1, "attack": 0, "heroic": 0, "wild": 2}
	_prompts = []
	_answers = [1, 0]   # 第 1 项 = 万能指示物
	await Game.reveal_threat_choice()
	await get_tree().process_frame
	_check("可用万能指示物支付", int(Game.state["used_tokens"]["wild"]) == 1, str(Game.state["used_tokens"]))
	_check("支付的是所选指示物(移动未动)", int(Game.state["used_tokens"]["move"]) == 0, str(Game.state["used_tokens"]))

	# ---------- ⑥ 破碎幻像不可清除 ----------
	var v: Dictionary = DB.villain("mysterio")
	var n_unclear := 0
	for th in v["threats"]:
		if String(th["name"]) == "破碎幻像" and th.get("unclearable", false):
			n_unclear += 1
	_check("数据：两张破碎幻像标记 unclearable", n_unclear == 2, "%d" % n_unclear)

	var iloc: int = (li + 1) % Game.LOCATION_COUNT
	Game.state["locations"][iloc]["threat"] = {
		"name": "破碎幻像", "text": "", "hp": 0, "heroic_tokens": 0, "arrival": false, "bam": false,
		"constant": true, "_face_down": false, "reveal": "enable_damage", "unclearable": true, "_tidx": 1}
	var it: Dictionary = Game.state["locations"][iloc]["threat"]
	_check("破碎幻像不可放指示物", Game._threat_placeable_sym(it) == "", Game._threat_placeable_sym(it))
	for i in range(5):
		Game._place_threat_token("cap", iloc, "heroic", "测试")
	_check("连放 5 次英勇后威胁仍在", Game.state["locations"][iloc]["threat"] != null and int(it["heroic_tokens"]) == 0,
		"threat=%s tokens=%d" % [str(Game.state["locations"][iloc]["threat"] != null), int(it["heroic_tokens"])])
	Game._clear_threat(iloc)
	_check("_clear_threat 被拦截", Game.state["locations"][iloc]["threat"] != null, "threat=%s" % str(Game.state["locations"][iloc]["threat"] != null))
	_check("幻像仍在场 → 神秘客可受伤", Game._mysterio_illusion_present(), "")

	# ---------- ⑦ 镜花水月仍可清除 ----------
	var mloc: int = (li + 2) % Game.LOCATION_COUNT
	Game.state["locations"][mloc]["threat"] = {
		"name": "镜花水月", "text": "", "hp": 0, "heroic_tokens": 0, "arrival": false, "bam": false,
		"constant": false, "_face_down": false, "reveal": "add_civ", "_tidx": 4}
	var mt: Dictionary = Game.state["locations"][mloc]["threat"]
	_check("镜花水月仍可放英勇指示物", Game._threat_placeable_sym(mt) == "heroic", Game._threat_placeable_sym(mt))
	for i in range(3):
		Game._place_threat_token("cap", mloc, "heroic", "测试")
	_check("镜花水月 3 英勇后被清除", Game.state["locations"][mloc]["threat"] == null, "threat=%s" % str(Game.state["locations"][mloc]["threat"] != null))

	if _fail == 0:
		print("=== MYSTERIO UI PASSED ===")
		get_tree().quit(0)
	else:
		print("=== MYSTERIO UI FAILED (%d) ===" % _fail)
		get_tree().quit(1)
