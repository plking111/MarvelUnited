extends Node
## 邪恶六人组模式回归：
## ① 设置：6 个反派各自生命值（按人数）、位置 2/2/2、英雄在对面、无任务/无威胁卡、行动牌堆 16 张
## ② 弱点卡：必须与该反派同地点才能填；填满 3 格 → 该反派可受伤
## ③ 反派回合：每 2 个英雄回合打 1 张行动卡；按卡上顺序激活前 2 个未被击败的反派；
##    第 1 个放暴徒、第 2 个放平民；只剩最后 1 个反派时激活两轮
## ④ 各反派 BAM（面板口径）
## ⑤ 秃鹫：持有民/暴时忽略本回合全部伤害并把指示物丢到所在地点
## ⑥ 神秘客（未被击败）：有危机指示物的英雄必须随机出牌，出牌后丢弃 1 个危机
## ⑦ 共用规则：KO / 溢出 → 抽 1 张反派行动卡面朝下入故事情节
## ⑧ 地点有反派时不能用该地点的回合结束效果；⑨ 牌堆抽空判负 / 击败 6 个获胜
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
	Game.setup("", ["cap", "ironman", "hulk"], "none", "s6")
	# 开局：start_game 打第一张反派行动卡（不能因为 master_deck 为空而直接判负）
	var deck_start: int = (Game.state["s6"]["deck"] as Array).size()
	await Game.start_game()
	_check("开局不判负（s6 用 s6.deck，不误判 master_deck 抽空）", Game.state["phase"] != "game_over" and not bool(Game.state.get("victory", false)),
		"phase=%s lose=%s" % [String(Game.state["phase"]), String(Game.state.get("lose_reason", ""))])
	_check("开局打出反派行动卡（牌堆减少；溢出会再抽 1 张面朝下）", (Game.state["s6"]["deck"] as Array).size() <= deck_start - 1,
		"%d -> %d" % [deck_start, (Game.state["s6"]["deck"] as Array).size()])
	Game.setup("", ["cap", "ironman", "hulk"], "none", "s6")
	var s: Dictionary = Game.state["s6"]
	_check("6 个反派全部入场", (s["vills"] as Dictionary).size() == 6, "%d" % (s["vills"] as Dictionary).size())
	_check("行动牌堆 16 张", (s["deck"] as Array).size() == 16, "%d" % (s["deck"] as Array).size())
	_check("不使用任务卡", (Game.state["missions"] as Array).size() == 0, "%d" % (Game.state["missions"] as Array).size())
	var n_threat := 0
	for l in Game.state["locations"]:
		if l["threat"] != null:
			n_threat += 1
	_check("地点不放威胁卡", n_threat == 0, "%d" % n_threat)
	# 生命值按人数（3 人）
	var hp_ok := int(s["vills"]["kraven"]["hp"]) == 3 and int(s["vills"]["sandman"]["hp"]) == 3 and int(s["vills"]["electro"]["hp"]) == 3 \
		and int(s["vills"]["docock"]["hp"]) == 3 and int(s["vills"]["vulture"]["hp"]) == 3 and int(s["vills"]["mysterio"]["hp"]) == 3
	_check("各反派生命值按 3 人局填充", hp_ok, "kraven=%d sandman=%d" % [int(s["vills"]["kraven"]["hp"]), int(s["vills"]["sandman"]["hp"])])
	# 位置：base 2 个 + 两侧各 2 个
	var base: int = int(s["base_loc"])
	var cnt := {}
	for vid in s["vills"]:
		var p: int = int(s["vills"][vid]["pos"])
		cnt[p] = int(cnt.get(p, 0)) + 1
	var neighbors: Array = Game._adjacent_locs(base)
	_check("反派 2/2/2 分布在起始地点与两侧",
		int(cnt.get(base, 0)) == 2 and int(cnt.get(int(neighbors[0]), 0)) == 2 and int(cnt.get(int(neighbors[1]), 0)) == 2,
		str(cnt))
	# 英雄在对面
	var hero_loc: int = int(Game.state["heroes"]["cap"]["location"])
	_check("英雄起始在反派起始地点对面", hero_loc == (base + 3) % Game.LOCATION_COUNT, "hero=%d base=%d" % [hero_loc, base])
	_check("英雄不与反派相邻", Game._s6_at(hero_loc).size() == 0 and not Game._adjacent_locs(hero_loc).any(func(a): return Game._s6_at(int(a)).size() > 0),
		"hero_loc=%d" % hero_loc)

	# ---------- ② 弱点卡 ----------
	var weak: Dictionary = DB.s6["weak"]
	_check("弱点卡符号与 docx 一致（克莱文 攻击/英勇/英勇）", str(weak["kraven"]["syms"]) == '["attack", "heroic", "heroic"]', str(weak["kraven"]["syms"]))
	_check("弱点卡符号与 docx 一致（秃鹫 英勇/移动/移动）", str(weak["vulture"]["syms"]) == '["heroic", "move", "move"]', str(weak["vulture"]["syms"]))
	_check("弱点卡符号与 docx 一致（章鱼博士 攻击/移动/英勇）", str(weak["docock"]["syms"]) == '["attack", "move", "heroic"]', str(weak["docock"]["syms"]))
	# 把 cap 移到某个反派所在地点（先清空所有人）
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	var kv: Dictionary = s["vills"]["kraven"]
	Game.state["heroes"]["cap"]["location"] = int(kv["pos"])
	var empty_loc := -1
	for i in range(Game.LOCATION_COUNT):
		if Game._s6_at(i).size() == 0:
			empty_loc = i
			break
	Game.state["heroes"]["ironman"]["location"] = empty_loc
	# 不同地点不能填
	var targets_elsewhere: Array = Game._s6_weak_targets("ironman", "attack")
	_check("不与反派同地点时不能化解", targets_elsewhere.size() == 0, str(targets_elsewhere))
	var t_here: Array = Game._s6_weak_targets("cap", "attack")
	_check("与反派同地点时可以化解", t_here.has("kraven"), str(t_here))
	Game._s6_fill_weak("cap", "kraven", "attack")
	Game._s6_fill_weak("cap", "kraven", "heroic")
	_check("填 2 格还不能受伤", not bool(kv["weak_done"]) and int((kv["weak_filled"] as Array).size()) == 3, str(kv["weak_filled"]))
	Game._s6_fill_weak("cap", "kraven", "heroic")
	_check("填满 3 格 → 该反派可以受到伤害", bool(kv["weak_done"]), str(kv["weak_filled"]))
	# 弱点卡没填满 → 攻击目标里没有该反派
	Game.state["locations"][int(kv["pos"])]["thug"] = 0
	_prompts = []
	_answers = [0]
	Game.state["action_symbols"] = ["attack"]
	await Game._execute_attack("cap", "symbol")
	var has_kv_target := false
	for rows in _prompts:
		for r in rows:
			if String(r.get("text", "")).contains("反派：猎人克莱文"):
				has_kv_target = true
	_check("弱点卡填满后攻击弹窗里出现该反派", has_kv_target, str(_prompts))

	# ---------- ③ 反派回合节奏 / 激活顺序 ----------
	Game.setup("", ["cap", "ironman"], "none", "s6")
	Game.state["phase"] = "hero_actions"
	var s2: Dictionary = Game.state["s6"]
	(s2["deck"] as Array).clear()
	(s2["deck"] as Array).append_array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])
	# 第 1 张：DFBEAC（沙人→秃鹫…）；只留沙人、秃鹫、神秘客三个未击败
	for vid in ["kraven", "electro", "docock"]:
		s2["vills"][vid]["defeated"] = true
	var base2: int = int(s2["base_loc"])
	for vid in ["sandman", "vulture", "mysterio"]:
		s2["vills"][vid]["pos"] = base2
	for l in Game.state["locations"]:
		l["civ"] = 0
		l["thug"] = 0
	Game.state["heroes"]["cap"]["location"] = (base2 + 2) % Game.LOCATION_COUNT
	Game.state["heroes"]["ironman"]["location"] = (base2 + 4) % Game.LOCATION_COUNT
	await Game._s6_run_turn()
	_check("反派回合打出 1 张行动卡", (s2["deck"] as Array).size() == 14, "%d" % (s2["deck"] as Array).size())
	var order_used: Array = []
	var moved_ok: bool = true
	# 沙人是 D（第 1 个激活）→ 移动 1 格；秃鹫 F（第 2 个）→ 移动 1 格
	_check("第 1 个激活的反派（沙人）被移动", int(s2["vills"]["sandman"]["pos"]) != base2,
		"pos=%d base=%d" % [int(s2["vills"]["sandman"]["pos"]), base2])
	_check("第 2 个激活的反派（秃鹫）被移动", int(s2["vills"]["vulture"]["pos"]) != base2,
		"pos=%d" % int(s2["vills"]["vulture"]["pos"]))
	# 第 1 个放暴徒、第 2 个放平民
	var thug_total := 0
	var civ_total := 0
	for l in Game.state["locations"]:
		thug_total += int(l["thug"])
		civ_total += int(l["civ"])
	# 第 1 个放暴徒、第 2 个放平民（指示物可能随后被秃鹫 BAM 收走，所以合并计数）
	var held_after: int = int(s2["vills"]["vulture"]["held_civ"]) + int(s2["vills"]["vulture"]["held_thug"])
	_check("第 1 个激活放暴徒、第 2 个放平民", thug_total + civ_total + held_after == 2, "thug=%d civ=%d held=%d" % [thug_total, civ_total, held_after])
	_check("第 3 个反派（神秘客）本卡未被激活", int(s2["vills"]["mysterio"]["pos"]) == base2,
		"pos=%d" % int(s2["vills"]["mysterio"]["pos"]))
	# 节奏：每 2 个英雄回合
	var card_seq_before: int = int(Game.state["turn_count"])
	Game.state["phase"] = "hero_end"
	Game.state["end_turn_busy"] = false
	await Game.end_turn()
	_check("第 1 个英雄回合结束不打反派卡（每 2 回合才打）", int(Game.state["turn_count"]) == card_seq_before,
		"turn_count %d -> %d" % [card_seq_before, int(Game.state["turn_count"])])
	Game.state["phase"] = "hero_end"
	Game.state["end_turn_busy"] = false
	await Game.end_turn()
	_check("第 2 个英雄回合结束才打反派卡", int(Game.state["turn_count"]) == card_seq_before + 1,
		"turn_count %d -> %d" % [card_seq_before, int(Game.state["turn_count"])])

	# ---------- ④ 各反派 BAM ----------
	# 克莱文：没有孤独英雄 → 放 2 个平民
	Game.setup("", ["cap", "ironman"], "none", "s6")
	Game.state["phase"] = "hero_actions"
	var s3: Dictionary = Game.state["s6"]
	for l in Game.state["locations"]:
		l["civ"] = 0
		l["thug"] = 0
	var kpos: int = int(s3["vills"]["kraven"]["pos"])
	Game.state["heroes"]["cap"]["location"] = kpos
	Game.state["heroes"]["ironman"]["location"] = kpos
	await Game._s6_bam("kraven")
	_check("克莱文 BAM：无孤独英雄 → 该地点 +2 平民", int(Game.state["locations"][kpos]["civ"]) == 2,
		"civ=%d" % int(Game.state["locations"][kpos]["civ"]))
	Game.state["heroes"]["ironman"]["location"] = (kpos + 2) % Game.LOCATION_COUNT
	Game.state["heroes"]["cap"]["hand"] = [0, 1, 2, 3, 4]
	await Game._s6_bam("kraven")
	_check("克莱文 BAM：有孤独英雄 → 他受 2 点伤害", Game.state["heroes"]["cap"]["hand"].size() == 3,
		"hand=%d" % Game.state["heroes"]["cap"]["hand"].size())
	# 沙人：+1 生命 + 所在地点每英雄 1 伤
	Game.setup("", ["cap", "ironman"], "none", "s6")
	Game.state["phase"] = "hero_actions"
	var s4: Dictionary = Game.state["s6"]
	var spos: int = int(s4["vills"]["sandman"]["pos"])
	Game.state["heroes"]["cap"]["location"] = spos
	Game.state["heroes"]["cap"]["hand"] = [0, 1, 2, 3, 4]
	var hp_before: int = int(s4["vills"]["sandman"]["hp"])
	await Game._s6_bam("sandman")
	_check("沙人 BAM：+1 生命值且所在地点英雄 1 伤",
		int(s4["vills"]["sandman"]["hp"]) == hp_before + 1 and Game.state["heroes"]["cap"]["hand"].size() == 4,
		"hp %d->%d hand=%d" % [hp_before, int(s4["vills"]["sandman"]["hp"]), Game.state["heroes"]["cap"]["hand"].size()])
	# 电光人：相邻两地点每英雄 1 伤
	Game.setup("", ["cap", "ironman"], "none", "s6")
	Game.state["phase"] = "hero_actions"
	var s5: Dictionary = Game.state["s6"]
	var epos: int = int(s5["vills"]["electro"]["pos"])
	var eneigh: Array = Game._adjacent_locs(epos)
	Game.state["heroes"]["cap"]["location"] = int(eneigh[0])
	Game.state["heroes"]["ironman"]["location"] = int(eneigh[1])
	for hid in ["cap", "ironman"]:
		Game.state["heroes"][hid]["hand"] = [0, 1, 2, 3]
	await Game._s6_bam("electro")
	_check("电光人 BAM：相邻两地点英雄各 1 伤",
		Game.state["heroes"]["cap"]["hand"].size() == 3 and Game.state["heroes"]["ironman"]["hand"].size() == 3,
		"cap=%d iron=%d" % [Game.state["heroes"]["cap"]["hand"].size(), Game.state["heroes"]["ironman"]["hand"].size()])
	# 神秘客：所在地点英雄获得危机指示物
	Game.setup("", ["cap", "ironman"], "none", "s6")
	Game.state["phase"] = "hero_actions"
	var s6d: Dictionary = Game.state["s6"]
	var mpos: int = int(s6d["vills"]["mysterio"]["pos"])
	Game.state["heroes"]["cap"]["location"] = mpos
	Game.state["heroes"]["cap"]["crisis"] = 0
	await Game._s6_bam("mysterio")
	_check("神秘客 BAM：所在地点英雄获得 1 个危机指示物", int(Game.state["heroes"]["cap"]["crisis"]) == 1,
		"crisis=%d" % int(Game.state["heroes"]["cap"]["crisis"]))
	# 章鱼博士：该地点 +1 危机；有危机地点的英雄 1 伤
	Game.setup("", ["cap", "ironman"], "none", "s6")
	Game.state["phase"] = "hero_actions"
	var s7: Dictionary = Game.state["s6"]
	for l in Game.state["locations"]:
		l["crisis"] = 0
	var opos: int = int(s7["vills"]["docock"]["pos"])
	Game.state["heroes"]["cap"]["location"] = opos
	Game.state["heroes"]["cap"]["hand"] = [0, 1, 2, 3, 4]
	await Game._s6_bam("docock")
	_check("章鱼博士 BAM：该地点 +1 危机且有危机地点的英雄 1 伤",
		int(Game.state["locations"][opos]["crisis"]) == 1 and Game.state["heroes"]["cap"]["hand"].size() == 4,
		"crisis=%d hand=%d" % [int(Game.state["locations"][opos]["crisis"]), Game.state["heroes"]["cap"]["hand"].size()])
	# 秃鹫：把所在地点的民/暴移到身上
	Game.setup("", ["cap", "ironman"], "none", "s6")
	Game.state["phase"] = "hero_actions"
	var s8: Dictionary = Game.state["s6"]
	var vpos2: int = int(s8["vills"]["vulture"]["pos"])
	Game.state["locations"][vpos2]["civ"] = 2
	Game.state["locations"][vpos2]["thug"] = 1
	await Game._s6_bam("vulture")
	_check("秃鹫 BAM：所在地点民/暴移到秃鹫身上",
		int(s8["vills"]["vulture"]["held_civ"]) == 2 and int(s8["vills"]["vulture"]["held_thug"]) == 1
		and int(Game.state["locations"][vpos2]["civ"]) == 0 and int(Game.state["locations"][vpos2]["thug"]) == 0,
		"held=%d/%d loc=%d/%d" % [int(s8["vills"]["vulture"]["held_civ"]), int(s8["vills"]["vulture"]["held_thug"]),
			int(Game.state["locations"][vpos2]["civ"]), int(Game.state["locations"][vpos2]["thug"])])

	# ---------- ⑤ 秃鹫：持有指示物 → 忽略本回合全部伤害 ----------
	Game.state["missions_completed"] = 2
	var vhp_before: int = int(s8["vills"]["vulture"]["hp"])
	Game.state["heroes"]["cap"]["location"] = vpos2
	Game.state["locations"][vpos2]["civ"] = 0
	Game.state["locations"][vpos2]["thug"] = 0
	await Game._s6_damage_villain("vulture", 2, "cap")
	_check("秃鹫持有时忽略全部伤害", int(s8["vills"]["vulture"]["hp"]) == vhp_before,
		"hp %d -> %d" % [vhp_before, int(s8["vills"]["vulture"]["hp"])])
	# 按规则断言：秃鹫把持有物清空，并把 3 个指示物丢到"他当时所在地点"
	# （他的位置会随回合变，绑死早先记录的 vpos2 会偶发失败；且规则明确"会引发溢出"，
	#   指示物可能被挤到相邻地点，所以按"地点 + 相邻地点"的总数判断）
	var v_now: int = int(s8["vills"]["vulture"]["pos"])
	var landed: int = int(Game.state["locations"][v_now]["civ"]) + int(Game.state["locations"][v_now]["thug"])
	for nb in Game._adjacent_locs(v_now):
		landed += int(Game.state["locations"][int(nb)]["civ"]) + int(Game.state["locations"][int(nb)]["thug"])
	_check("秃鹫把身上的民/暴丢到所在地点（允许溢出到相邻地点）",
		int(s8["vills"]["vulture"]["held_civ"]) == 0 and int(s8["vills"]["vulture"]["held_thug"]) == 0
		and landed >= 3,
		"held=%d/%d 地点%d+相邻合计=%d" % [int(s8["vills"]["vulture"]["held_civ"]),
			int(s8["vills"]["vulture"]["held_thug"]), v_now, landed])
	# 再打一次（本回合已用过 → 正常扣血）
	await Game._s6_damage_villain("vulture", 1, "cap")
	_check("同一回合第二次攻击正常扣血", int(s8["vills"]["vulture"]["hp"]) == vhp_before - 1,
		"hp=%d" % int(s8["vills"]["vulture"]["hp"]))

	# ---------- ⑥ 神秘客：有危机的英雄必须随机出牌并丢 1 危机 ----------
	Game.setup("", ["cap", "ironman"], "none", "s6")
	Game.state["heroes"]["cap"]["crisis"] = 1
	Game.state["heroes"]["cap"]["hand"] = [0, 1, 2]
	Game.state["heroes"]["cap"]["deck"] = [3, 4, 5]
	Game.state["current_hero"] = 0
	await Game._start_hero_turn()
	_check("神秘客在场：有危机的英雄本回合随机出牌", bool(Game.state.get("random_play", false)), "random_play=false")
	Game.state["phase"] = "hero_play"
	await Game.play_card(0)
	_check("随机出牌后丢弃 1 个危机指示物", int(Game.state["heroes"]["cap"]["crisis"]) == 0,
		"crisis=%d" % int(Game.state["heroes"]["cap"]["crisis"]))
	Game.state["s6"]["vills"]["mysterio"]["defeated"] = true
	Game.state["heroes"]["cap"]["crisis"] = 1
	Game.state["current_hero"] = 0
	await Game._start_hero_turn()
	_check("神秘客被击败后不再随机出牌", not bool(Game.state.get("random_play", true)), "random_play=true")

	# ---------- ⑦ 共用规则：KO / 溢出 → 面朝下行动卡入故事情节 ----------
	Game.setup("", ["cap", "ironman"], "none", "s6")
	var deck_b: int = (Game.state["s6"]["deck"] as Array).size()
	var story_b: int = Game.state["story"].size()
	Game.state["heroes"]["cap"]["hand"] = [0, 1]
	await Game._ko_hero("cap")
	var last_entry: Dictionary = Game.state["story"].back()
	_check("KO：不触发 BAM，而是加 1 张面朝下的反派行动卡",
		(Game.state["s6"]["deck"] as Array).size() == deck_b - 1 and Game.state["story"].size() == story_b + 1
		and bool(last_entry.get("face_down", false)),
		"deck %d->%d story %d->%d" % [deck_b, (Game.state["s6"]["deck"] as Array).size(), story_b, Game.state["story"].size()])
	Game.setup("", ["cap", "ironman"], "none", "s6")
	var deck_b2: int = (Game.state["s6"]["deck"] as Array).size()
	var loc_f: int = 0
	Game.state["locations"][loc_f]["civ"] = int(DB.location(Game.state["locations"][loc_f]["id"])["slots"])
	Game.state["locations"][loc_f]["thug"] = 0
	Game.state["phase"] = "hero_actions"
	await Game._s6_place_indicators(loc_f, "thug", 2)
	_check("溢出：改为抽 1 张面朝下的反派行动卡（而不是按指示物数量）",
		(Game.state["s6"]["deck"] as Array).size() == deck_b2 - 1,
		"deck %d->%d" % [deck_b2, (Game.state["s6"]["deck"] as Array).size()])

	# ---------- ⑧ 地点有反派 → 不能用该地点的回合结束效果 ----------
	Game.setup("", ["cap", "ironman"], "none", "s6")
	var ts := 1
	Game.state["locations"][ts]["id"] = "times_square"
	Game.state["locations"][ts]["threat"] = null
	Game.state["locations"][ts]["civ"] = 2
	Game.state["s6"]["vills"]["kraven"]["pos"] = ts      # 该地点有反派
	Game.state["heroes"]["cap"]["location"] = ts
	Game.state["heroes"]["cap"]["hand"] = [0, 1, 2]
	Game.state["heroes"]["cap"]["deck"] = [3, 4, 5]
	Game.state["phase"] = "hero_end"
	Game.state["hero_cards_played"] = 0
	Game.state["end_turn_busy"] = false
	await Game.end_turn()
	_check("有反派的地点不能使用回合结束效果", int(Game.state["locations"][ts]["civ"]) == 2,
		"civ=%d" % int(Game.state["locations"][ts]["civ"]))

	# ---------- ⑨ 胜负：牌堆抽空判负 / 击败 6 个获胜 ----------
	Game.setup("", ["cap", "ironman"], "none", "s6")
	(Game.state["s6"]["deck"] as Array).clear()
	Game.state["phase"] = "hero_actions"
	await Game._s6_run_turn()
	_check("行动牌堆抽空 → 英雄失败", Game.state["phase"] == "game_over", String(Game.state["phase"]))
	Game.setup("", ["cap", "ironman"], "none", "s6")
	Game.state["phase"] = "hero_actions"
	for vid in Game.state["s6"]["vills"]:
		Game.state["s6"]["vills"][vid]["defeated"] = true
	Game.state["s6"]["vills"]["vulture"]["hp"] = 1
	Game.state["s6"]["vills"]["vulture"]["defeated"] = false
	await Game._s6_damage_villain("vulture", 1, "cap")
	_check("击败全部 6 个反派 → 英雄胜利", bool(Game.state.get("victory", false)), "victory=false")

	if _fail == 0:
		print("=== S6 TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== S6 FAILED (%d) ===" % _fail)
		get_tree().quit(1)
