extends Node
## 秘密身份挑战模式回归：
## ① 设置：英雄起始点相邻地点 + 反派起始地点各 1 个记者指示物
## ② 曝光：在"有记者"的地点执行非移动行动（攻击/英勇/英雄特殊能力）各获得 1 个曝光；移动不获得；
##    每人每回合最多 1 个；地点回合结束效果不算
## ③ 身份暴露（3 个）：立刻受 1 点伤害；之后不再获得曝光；下回合强制背面出牌（无效果但继承上一张卡符号）
## ④ 移动记者：消耗 1 个任意行动把记者挪到相邻地点，且不产生曝光
## ⑤ UI：记者指示物在地点卡左上角；曝光数量在英雄图标上半部分
var _fail := 0
var _prompts: Array = []
var _answers: Array = []

func _check(n: String, ok: bool, d: String) -> void:
	if ok: print("PASS: " + n)
	else: _fail += 1; print("FAIL: " + n + " — " + d)

func _ready() -> void:
	Game.autopilot = false
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

	# ---------- ① 设置 ----------
	Game.setup("redskull", ["cap", "ironman"], "secretid", "base")
	Game.state["phase"] = "hero_actions"
	var hero_start: int = int(Game.state["heroes"]["cap"]["location"])
	var rep_locs: Array = []
	for i in range(Game.LOCATION_COUNT):
		if Game.state["locations"][i].get("reporter", false):
			rep_locs.append(i)
	var adj_start: Array = Game._adjacent_locs(hero_start)
	_check("记者指示物放在英雄起始点的相邻地点", adj_start.all(func(a): return rep_locs.has(int(a))), "reporters=%s adj=%s" % [str(rep_locs), str(adj_start)])
	_check("反派起始地点额外有 1 个记者", rep_locs.has(int(Game.state["villain_pos"])), "reporters=%s vpos=%d" % [str(rep_locs), int(Game.state["villain_pos"])])
	_check("记者总量 = 相邻 2 个 + 反派地点 1 个", rep_locs.size() == 3, "%d 个：%s" % [rep_locs.size(), str(rep_locs)])

	# ---------- ② 曝光获取 ----------
	Game.setup("redskull", ["cap", "ironman"], "secretid", "base")
	var rloc: int = -1
	for i in range(Game.LOCATION_COUNT):
		if Game.state["locations"][i].get("reporter", false):
			rloc = i
			break
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	Game.state["hero_turn_seq"] = 1
	Game.state["heroes"]["cap"]["location"] = rloc
	Game.state["heroes"]["cap"]["exposure"] = 0
	Game.state["heroes"]["cap"]["exposure_turn"] = -1
	Game.state["locations"][rloc]["civ"] = 2
	Game.state["locations"][rloc]["thug"] = 2
	Game.state["action_symbols"] = ["attack", "attack", "heroic", "move"]
	_prompts = []
	_answers = [0, 0, 0]
	await Game._execute_attack("cap", "symbol")
	_check("在有记者的地点用攻击行动 → +1 曝光", int(Game.state["heroes"]["cap"]["exposure"]) == 1,
		"exposure=%d" % int(Game.state["heroes"]["cap"]["exposure"]))
	# 同一回合再做一次非移动行动 → 不再获得（每人每回合最多 1 个）
	await Game._execute_heroic("cap", "symbol")
	_check("同一回合第二次非移动行动不再获得曝光", int(Game.state["heroes"]["cap"]["exposure"]) == 1,
		"exposure=%d" % int(Game.state["heroes"]["cap"]["exposure"]))
	# 新回合（hero_turn_seq +1）→ 可以再获得
	Game.state["hero_turn_seq"] = 2
	await Game._execute_heroic("cap", "symbol")
	_check("新回合再执行非移动行动 → 再 +1（累计 2）", int(Game.state["heroes"]["cap"]["exposure"]) == 2,
		"exposure=%d" % int(Game.state["heroes"]["cap"]["exposure"]))
	# 移动行动不获得曝光
	Game.state["hero_turn_seq"] = 3
	Game.state["action_symbols"] = ["move"]
	_prompts = []
	_answers = [0]
	await Game._execute_move("cap", "symbol")
	_check("使用移动行动不获得曝光", int(Game.state["heroes"]["cap"]["exposure"]) == 2,
		"exposure=%d（loc=%d）" % [int(Game.state["heroes"]["cap"]["exposure"]), int(Game.state["heroes"]["cap"]["location"])])
	# 不在有记者的地点 → 不获得
	Game.state["hero_turn_seq"] = 4
	var no_rep := -1
	for i in range(Game.LOCATION_COUNT):
		if not Game.state["locations"][i].get("reporter", false):
			no_rep = i
			break
	Game.state["heroes"]["cap"]["location"] = no_rep
	Game.state["action_symbols"] = ["attack"]
	_prompts = []
	_answers = [0]
	await Game._execute_attack("cap", "symbol")
	_check("在没有记者的地点行动不获得曝光", int(Game.state["heroes"]["cap"]["exposure"]) == 2,
		"exposure=%d" % int(Game.state["heroes"]["cap"]["exposure"]))

	# ---------- ③ 身份暴露：3 个 → 受伤 + 不再获得曝光 + 下回合背面出牌 ----------
	Game.setup("redskull", ["cap", "ironman"], "secretid", "base")
	rloc = -1
	for i in range(Game.LOCATION_COUNT):
		if Game.state["locations"][i].get("reporter", false):
			rloc = i
			break
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	Game.state["hero_turn_seq"] = 10
	Game.state["heroes"]["cap"]["location"] = rloc
	Game.state["heroes"]["cap"]["exposure"] = 2
	Game.state["heroes"]["cap"]["exposure_turn"] = -1
	Game.state["heroes"]["cap"]["hand"] = [0, 1, 2, 3]
	Game.state["locations"][rloc]["civ"] = 2
	Game.state["locations"][rloc]["thug"] = 2
	Game.state["action_symbols"] = ["heroic"]
	_prompts = []
	_answers = [0]
	await Game._execute_heroic("cap", "symbol")
	_check("第 3 个曝光 → 身份暴露", bool(Game.state["heroes"]["cap"].get("exposed", false)), "未暴露")
	_check("身份暴露立刻受到 1 点伤害（弃 1 张）", Game.state["heroes"]["cap"]["hand"].size() == 3,
		"hand=%d" % Game.state["heroes"]["cap"]["hand"].size())
	_check("暴露后不会再获得曝光", int(Game.state["heroes"]["cap"]["exposure"]) == 3,
		"exposure=%d" % int(Game.state["heroes"]["cap"]["exposure"]))
	# 下个回合开始 → 强制背面出牌
	var hcap: Dictionary = Game.state["heroes"]["cap"]
	hcap["deck"] = [0, 1, 2, 3, 4, 5]
	hcap["hand"] = [0, 1]
	Game.state["story"].append({"type": "hero", "hero": "ironman", "idx": 0})
	Game.state["current_hero"] = 0
	await Game._start_hero_turn()
	_check("暴露后下回合被标记为强制背面出牌", String(Game.state.get("forced_face_down_hero", "")) == "cap",
		"forced=%s" % String(Game.state.get("forced_face_down_hero", "")))
	var story_before: int = Game.state["story"].size()
	Game.state["phase"] = "hero_play"
	await Game.play_card(0)
	var last_entry: Dictionary = Game.state["story"].back()
	_check("背面出牌：故事情节记录为面朝下", Game.state["story"].size() == story_before + 1 and bool(last_entry.get("face_down", false)),
		"story %d->%d face_down=%s" % [story_before, Game.state["story"].size(), str(last_entry.get("face_down", false))])
	_check("背面出牌：无卡牌效果（effect_available=false）", not bool(Game.state.get("effect_available", true)),
		"effect_available=%s" % str(Game.state.get("effect_available", true)))
	_check("背面出牌：仍继承上一张英雄卡的符号",
		Game.state["action_symbols"].size() == Game.state.get("prev_hero_symbols", []).size(),
		"symbols=%s prev=%s" % [str(Game.state["action_symbols"]), str(Game.state.get("prev_hero_symbols", []))])
	_check("背面出牌后清除强制标记", String(Game.state.get("forced_face_down_hero", "")) == "",
		"forced=%s" % String(Game.state.get("forced_face_down_hero", "")))

	# ---------- ④ 移动记者：消耗 1 个行动，且不产生曝光 ----------
	Game.setup("redskull", ["cap", "ironman"], "secretid", "base")
	rloc = -1
	for i in range(Game.LOCATION_COUNT):
		if Game.state["locations"][i].get("reporter", false):
			rloc = i
			break
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	Game.state["hero_turn_seq"] = 20
	Game.state["heroes"]["cap"]["location"] = rloc      # 英雄就在记者所在地点（按规则移走也不产生曝光）
	Game.state["heroes"]["cap"]["exposure"] = 0
	Game.state["heroes"]["cap"]["exposure_turn"] = -1
	Game.state["action_symbols"] = ["heroic"]
	Game.state["used_tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
	var dest: int = int(Game._adjacent_locs(rloc)[0])
	_prompts = []
	_answers = [0, 0, 0]      # 选记者 → 选目的地 → 选花费的行动
	await Game.move_reporter_choice()
	_check("移动记者：记者已移到相邻地点",
		not bool(Game.state["locations"][rloc].get("reporter", true)) and bool(Game.state["locations"][dest].get("reporter", false)),
		"from=%d to=%d" % [rloc, dest])
	_check("移动记者：消耗了 1 个行动符号", Game.state["action_symbols"].size() == 0,
		"symbols=%s" % str(Game.state["action_symbols"]))
	_check("移动记者：不产生曝光指示物", int(Game.state["heroes"]["cap"]["exposure"]) == 0,
		"exposure=%d" % int(Game.state["heroes"]["cap"]["exposure"]))
	# 取消分支：不消耗行动
	Game.setup("redskull", ["cap", "ironman"], "secretid", "base")
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	Game.state["action_symbols"] = ["heroic"]
	_prompts = []
	_answers = [9]            # 最后一行 = 取消
	await Game.move_reporter_choice()
	_check("移动记者：取消不消耗行动", Game.state["action_symbols"].size() == 1,
		"symbols=%s" % str(Game.state["action_symbols"]))

	# ---------- ⑤ UI：记者在左上角、曝光在英雄图标上半部分 ----------
	Game.pending_setup = {"villain": "redskull", "heroes": ["cap", "ironman"], "challenge": "secretid"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(4):
		await get_tree().process_frame
	var rep_i := -1
	for i in range(Game.LOCATION_COUNT):
		if Game.state["locations"][i].get("reporter", false):
			rep_i = i
			break
	var lv: LocationView = inst._loc_views[rep_i]
	var tl: Vector2 = lv._pos - Vector2(LocationView.LOC_CARD_SIZE / 2.0, LocationView.LOC_CARD_SIZE / 2.0)
	var found_reporter := false
	for n in inst._icon_nodes:
		if n is TextureRect and (n as TextureRect).texture != null \
			and String((n as TextureRect).texture.resource_path).ends_with("reporter_token.png"):
			var d: float = (n.position - (tl + Vector2(4, 4))).length()
			if d < 2.0:
				found_reporter = true
	_check("UI：记者指示物在地点卡左上角", found_reporter, "未找到左上角记者图标")
	# 曝光数量在英雄图标上半部分
	Game.state["heroes"]["cap"]["location"] = rep_i
	Game.state["heroes"]["cap"]["exposure"] = 2
	inst._rebuild_icons(Game.state)
	await get_tree().process_frame
	var found_expo := false
	var upper := false
	var big_enough := false
	for n in inst._icon_nodes:
		var top_half := false
		var has_expo := false
		for c in n.get_children():
			if c is TextureRect and (c as TextureRect).texture != null \
				and String((c as TextureRect).texture.resource_path).ends_with("exposure_token.png"):
				has_expo = true
				if c.position.y < 28.0:
					top_half = true
				if c.custom_minimum_size.x >= 26.0:
					big_enough = true
		if has_expo:
			found_expo = true
			upper = top_half
	_check("UI：曝光指示物显示在英雄图标上半部分", found_expo and upper,
		"found=%s upper=%s" % [str(found_expo), str(upper)])
	_check("UI：曝光指示物尺寸已放大（>=26px）", big_enough, "尺寸过小")

	if _fail == 0:
		print("=== SECRETID TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== SECRETID FAILED (%d) ===" % _fail)
		get_tree().quit(1)
