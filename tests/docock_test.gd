extends Node
## 章鱼博士（邪恶六人组）回归：数据 + 地点摧毁 + 相邻重构 + BAM/溢出 + 威胁BAM + 危及平民 + 特殊移动
var _fail := 0
var _pa_answer := 0
var _last_rows: Array = []
func _check(n: String, ok: bool, d: String) -> void:
	if ok: print("PASS: " + n)
	else: _fail += 1; print("FAIL: " + n + " — " + d)

func _sum(ids: Array) -> Array:
	var out: Array = []
	for i in ids:
		out.append(int(Game.state["locations"][i]["crisis"]))
	return out

func _ready() -> void:
	Game.autopilot = false
	Events.prompt_confirm.connect(func(_t: String, cb: Callable) -> void:
		await get_tree().process_frame
		cb.call(false))
	Events.prompt_choice.connect(func(_o: Array, _t: String, cb: Callable) -> void:
		await get_tree().process_frame
		cb.call(0))
	Events.prompt_action.connect(func(r: Array, _t: String, cb: Callable) -> void:
		_last_rows = r.duplicate(true)
		await get_tree().process_frame
		cb.call(int(_pa_answer)))
	Events.prompt_hand_card.connect(func(cb: Callable, _t: String, hid: String, c: int) -> void:
		await get_tree().process_frame
		var h: Array = Game.state["heroes"][hid]["hand"]
		var out: Array = []
		for i in range(mini(c, h.size())):
			out.append(i)
		cb.call(out))

	# ---------- 1. 数据 ----------
	var v: Dictionary = DB.villain("docock")
	_check("章鱼博士存在", not v.is_empty(), "")
	_check("生命 3/6/8", int(v["health"]["2"]) == 3 and int(v["health"]["3"]) == 6 and int(v["health"]["4"]) == 8, str(v["health"]))
	_check("12 张行动卡", v["actions"].size() == 12, "%d" % v["actions"].size())
	_check("6 张威胁卡", v["threats"].size() == 6, "%d" % v["threats"].size())
	_check("摧毁轨道", String(v.get("plot_track", "")) == "destroyed", String(v.get("plot_track", "")))
	var n_hench := 0
	var n_civthreat := 0
	for t in v["threats"]:
		if int(t["henchman_hp"]) > 0:
			n_hench += 1
		if t["name"] == "危及平民":
			n_civthreat += 1
	_check("3 张爪牙 + 3 张危及平民", n_hench == 3 and n_civthreat == 3, "爪牙=%d 危及平民=%d" % [n_hench, n_civthreat])
	var mv45: Variant = v["actions"][3]["move"]
	_check("卡4/5 为特殊移动（顺时针到下一个有英雄的地点）",
		mv45 is Dictionary and String(mv45.get("dir", "")) == "cw" and bool(mv45.get("hero_in", false))
			and String(v["actions"][3]["effect"]["type"]) == "docock_tentacle_grab",
		str(v["actions"][3]))

	# ---------- 2. BAM：所在地点英雄各1伤 + 该地点+1危机 ----------
	Game.setup("docock", ["cap", "ironman", "hulk"], "none", "base")
	Game.state["phase"] = "hero_actions"
	var vpos: int = Game.state["villain_pos"]
	for hid in Game.state["hero_ids"]:
		Game.state["heroes"][hid]["location"] = vpos
		Game.state["heroes"][hid]["ko"] = false
		Game.state["heroes"][hid]["hand"] = [0, 1, 2, 3, 4, 5]
	Game.state["locations"][vpos]["crisis"] = 0
	var hand_b: int = Game.state["heroes"]["cap"]["hand"].size()
	await VillainRules.on_bam(Game, "docock")
	_check("BAM 所在地英雄扣手牌", Game.state["heroes"]["cap"]["hand"].size() < hand_b,
		"hand %d->%d" % [hand_b, Game.state["heroes"]["cap"]["hand"].size()])
	_check("BAM 该地点危机+1", int(Game.state["locations"][vpos]["crisis"]) == 1, "crisis=%d" % int(Game.state["locations"][vpos]["crisis"]))

	# ---------- 3. 危机到 3 → 地点摧毁（清空指示物/威胁、英雄被挤出、相邻重构） ----------
	var loc := vpos
	var l: Dictionary = Game.state["locations"][loc]
	l["crisis"] = 3
	l["civ"] = 2
	l["thug"] = 1
	l["threat"] = {"name": "危及平民", "text": "", "hp": 0, "heroic_tokens": 0, "arrival": false, "bam": false, "constant": true}
	Game.state["heroes"]["cap"]["location"] = loc      # 让 cap 在该地点（另一名英雄挪开，避免随机）
	Game.state["heroes"]["ironman"]["location"] = (loc + 2) % Game.LOCATION_COUNT
	Game.state["heroes"]["hulk"]["location"] = (loc + 3) % Game.LOCATION_COUNT
	await Game._docock_check_destroy()
	_check("危机3→地点摧毁", Game.state["locations"][loc].get("destroyed", false) == true, "")
	_check("摧毁后清空指示物与威胁", int(l["civ"]) == 0 and int(l["thug"]) == 0 and int(l["crisis"]) == 0 and l["threat"] == null,
		"civ=%d thug=%d crisis=%d threat=%s" % [int(l["civ"]), int(l["thug"]), int(l["crisis"]), str(l["threat"])])
	_check("摧毁地点的英雄被移出", int(Game.state["heroes"]["cap"]["location"]) != loc,
		"cap loc=%d" % int(Game.state["heroes"]["cap"]["location"]))

	# ---------- 4. 相邻重构：相邻地点应跳过被摧毁地点 ----------
	var live: Array = Game._live_locs()
	_check("存活地点数=5", live.size() == 5, "%d" % live.size())
	_check("被摧毁地点不在存活环", not live.has(loc), str(live))
	var idx_in_live: int = -1
	# 找任意活地点，验证其相邻两地点都不是被摧毁地点、且相邻两地点在存活环上相邻
	var probe: int = int(live[0])
	var adj: Array = Game._adjacent_locs(probe)
	_check("相邻返回两个存活地点", adj.size() == 2 and not adj.has(loc) and live.has(int(adj[0])) and live.has(int(adj[1])),
		"probe=%d adj=%s" % [probe, str(adj)])
	# 若摧毁的地点在存活环上原本相隔 2 格的两个地点，现在应互为相邻
	var pi: int = live.find(probe)
	var expect_next: int = int(live[(pi + 1) % live.size()])
	_check("相邻=存活环上的下一格", int(adj[1]) == expect_next, "adj1=%d expect=%d" % [int(adj[1]), expect_next])

	# ---------- 5. 摧毁 4 个地点 → 英雄失败 ----------
	Game.setup("docock", ["cap", "ironman", "hulk"], "none", "base")
	Game.state["phase"] = "hero_actions"
	for i in range(3):
		Game.state["locations"][i]["crisis"] = 3
	await Game._docock_check_destroy()
	_check("摧毁3个未判负", Game.state["phase"] != "game_over" and Game._destroyed_count() == 3,
		"phase=%s destroyed=%d" % [Game.state["phase"], Game._destroyed_count()])
	Game.state["locations"][3]["crisis"] = 3
	await Game._docock_check_destroy()
	_check("摧毁4个即英雄失败", Game.state["phase"] == "game_over" and String(Game.state.get("lose_reason", "")).contains("摧毁"),
		"phase=%s reason=%s" % [Game.state["phase"], String(Game.state.get("lose_reason", ""))])

	# ---------- 6. 溢出：改加危机（进而可能摧毁） ----------
	Game.setup("docock", ["cap", "ironman", "hulk"], "none", "base")
	Game.state["phase"] = "hero_actions"
	Game.state["locations"][2]["crisis"] = 2
	await VillainRules.on_overflow(Game, "docock", "thug", 2)
	_check("溢出改为加危机并触发摧毁", int(Game.state["locations"][2]["crisis"]) == 0 and Game.state["locations"][2].get("destroyed", false) == true,
		"crisis=%d destroyed=%s" % [int(Game.state["locations"][2]["crisis"]), str(Game.state["locations"][2].get("destroyed", false))])

	# ---------- 7. 威胁 BAM：秃鹫（1伤+移卡）/ 神秘客（1伤+加民暴）/ 沙人（+1生命+群体1伤） ----------
	Game.setup("docock", ["cap", "ironman", "hulk"], "none", "base")
	Game.state["phase"] = "hero_actions"
	for _cl in Game.state["locations"]:
		_cl["threat"] = null          # 清掉开局自带的 6 张威胁，避免互相干扰
	for hid in Game.state["hero_ids"]:
		Game.state["heroes"][hid]["ko"] = false
		Game.state["heroes"][hid]["hand"] = [0, 1, 2, 3, 4, 5, 6]
	# 秃鹫：放在 0，1 号地点留空 → BAM 后卡应移到 1
	Game.state["locations"][0]["threat"] = {"name": "秃鹫", "text": "", "hp": 4, "heroic_tokens": 0, "arrival": false, "bam": true, "constant": false}
	Game.state["locations"][1]["threat"] = null
	Game.state["heroes"]["cap"]["location"] = 0
	await Game._trigger_all_threat_bam()
	_check("秃鹫BAM后移到无威胁地点", Game.state["locations"][0]["threat"] == null and Game.state["locations"][1]["threat"] != null,
		"l0=%s l1=%s" % [str(Game.state["locations"][0]["threat"]), str(Game.state["locations"][1]["threat"])])
	# 神秘客：加1平民+1暴徒
	Game.state["locations"][2]["threat"] = {"name": "神秘客", "text": "", "hp": 3, "heroic_tokens": 0, "arrival": false, "bam": true, "constant": false}
	Game.state["locations"][2]["civ"] = 0
	Game.state["locations"][2]["thug"] = 0
	var hand2: int = Game.state["heroes"]["ironman"]["hand"].size()
	await Game._trigger_all_threat_bam()
	_check("神秘客BAM加1平民1暴徒", int(Game.state["locations"][2]["civ"]) == 1 and int(Game.state["locations"][2]["thug"]) == 1,
		"civ=%d thug=%d" % [int(Game.state["locations"][2]["civ"]), int(Game.state["locations"][2]["thug"])])
	# 沙人：+1 生命 + 该地点每个英雄受 1 伤
	Game.state["locations"][3]["threat"] = {"name": "沙人", "text": "", "hp": 4, "heroic_tokens": 0, "arrival": false, "bam": true, "constant": false}
	Game.state["heroes"]["hulk"]["location"] = 3
	var hulk_hand: int = Game.state["heroes"]["hulk"]["hand"].size()
	await Game._trigger_all_threat_bam()
	_check("沙人BAM +1生命", int(Game.state["locations"][3]["threat"]["hp"]) >= 5, "hp=%d" % int(Game.state["locations"][3]["threat"]["hp"]))
	_check("沙人BAM 该地点英雄受伤", Game.state["heroes"]["hulk"]["hand"].size() < hulk_hand,
		"hand %d->%d" % [hulk_hand, Game.state["heroes"]["hulk"]["hand"].size()])

	# ---------- 8. 危及平民：营救需要额外 1 个行动（走 use_symbol 的完整消耗流程验证） ----------
	Game.setup("docock", ["cap", "ironman", "hulk"], "none", "base")
	var rloc: int = Game.state["heroes"]["cap"]["location"]
	Game.state["locations"][rloc]["threat"] = null
	Game.state["locations"][rloc]["civ"] = 2
	Game.state["heroes"]["cap"]["tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
	Game.state["action_symbols"] = ["heroic", "heroic"]
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = Game.state["hero_ids"].find("cap")
	var civ_before: int = int(Game.state["locations"][rloc]["civ"])
	await Game.use_symbol("heroic")
	for _w in range(6):
		await get_tree().process_frame      # use_symbol 里 _execute_heroic 是"不 await 的协程"，等它跑完
	_check("无危及平民：1英勇救1平民", int(Game.state["locations"][rloc]["civ"]) == civ_before - 1,
		"civ %d->%d" % [civ_before, int(Game.state["locations"][rloc]["civ"])])
	# 加上危及平民后再试：只给 1 个英勇，应救不了（需求 2）
	Game.setup("docock", ["cap", "ironman", "hulk"], "none", "base")
	rloc = Game.state["heroes"]["cap"]["location"]
	Game.state["locations"][rloc]["threat"] = {"name": "危及平民", "text": "", "hp": 0, "heroic_tokens": 0, "arrival": false, "bam": false, "constant": true}
	Game.state["locations"][rloc]["civ"] = 2
	Game.state["heroes"]["cap"]["tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
	Game.state["action_symbols"] = ["heroic"]
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = Game.state["hero_ids"].find("cap")
	var civ_b2: int = int(Game.state["locations"][rloc]["civ"])
	await Game.use_symbol("heroic")
	for _w in range(6):
		await get_tree().process_frame
	_check("危及平民：1英勇不够救(需求+1)", int(Game.state["locations"][rloc]["civ"]) == civ_b2,
		"civ %d->%d" % [civ_b2, int(Game.state["locations"][rloc]["civ"])])

	# ---------- 9. 行动卡 4/5 的特殊移动：顺时针到下一个有英雄的地点（跳过被摧毁） ----------
	Game.setup("docock", ["cap", "ironman", "hulk"], "none", "base")
	Game.state["phase"] = "hero_actions"
	for hid in Game.state["hero_ids"]:
		Game.state["heroes"][hid]["location"] = (Game.state["villain_pos"] + 2) % Game.LOCATION_COUNT
		Game.state["heroes"][hid]["ko"] = false
	Game._do_villain_move(v["actions"][3]["move"])
	_check("伸展触手到达有英雄地点", Game.state["heroes"]["cap"]["location"] == Game.state["villain_pos"],
		"vpos=%d cap=%d" % [int(Game.state["villain_pos"]), int(Game.state["heroes"]["cap"]["location"])])

	# ---------- 9b. 行动卡 2/3「总规划师」 ----------
	var mp: Dictionary = v["actions"][1]["effect"]
	_check("行动卡 2/3 是总规划师", String(mp.get("type", "")) == "docock_master_plan", str(mp.get("type", "")))
	Game.setup("docock", ["cap", "ironman"], "none", "base")
	for _ll2 in Game.state["locations"]:
		_ll2["crisis"] = 0
	Game.state["villain_pos"] = 4
	for hid in Game.state["hero_ids"]:
		Game.state["heroes"][hid]["hand"] = [0, 1, 2, 3, 4, 5]
		Game.state["heroes"][hid]["ko"] = false
	Game.state["locations"][2]["crisis"] = 1
	Game.state["locations"][2]["civ"] = 0
	Game.state["locations"][2]["thug"] = 0
	Game.state["locations"][3]["crisis"] = 0
	Game.state["heroes"]["cap"]["location"] = 2      # 该地点有危机 → 受 1 伤
	Game.state["heroes"]["ironman"]["location"] = 3  # 无危机 → 不受伤
	await VillainRules.resolve_effect(Game, mp)
	_check("总规划师：有危机地点的英雄受 1 伤", Game.state["heroes"]["cap"]["hand"].size() == 5,
		"cap=%d" % Game.state["heroes"]["cap"]["hand"].size())
	_check("总规划师：无危机地点的英雄不受影响", Game.state["heroes"]["ironman"]["hand"].size() == 6,
		"iron=%d" % Game.state["heroes"]["ironman"]["hand"].size())
	_check("总规划师：在章鱼博士所在地点 +1 危机", int(Game.state["locations"][4]["crisis"]) == 1,
		"crisis=%d" % int(Game.state["locations"][4]["crisis"]))

	# ---------- 9c. 行动卡 4/5「触手抓握」：所有英雄朝章鱼博士靠近一格，然后 BAM！ ----------
	var tg: Dictionary = v["actions"][3]["effect"]
	_check("行动卡 4/5 是触手抓握", String(tg.get("type", "")) == "docock_tentacle_grab", str(tg.get("type", "")))
	Game.setup("docock", ["cap", "ironman"], "none", "base")
	Game.state["villain_pos"] = 0
	for hid in Game.state["hero_ids"]:
		Game.state["heroes"][hid]["ko"] = false
		Game.state["heroes"][hid]["hand"] = [0, 1, 2, 3]
		Game.state["heroes"][hid]["crisis"] = 0
	Game.state["locations"][0]["civ"] = 0
	Game.state["locations"][0]["thug"] = 0
	for _ti in range(Game.LOCATION_COUNT):
		Game.state["locations"][_ti]["threat"] = null   # 清空威胁卡，只验证触手抓握自带的 BAM
	Game.state["heroes"]["cap"]["location"] = 3        # 距 0 号地点 3 格 → 就近方向是 4 或 2
	Game.state["heroes"]["ironman"]["location"] = 0    # 已在章鱼博士所在地点 → 不动
	var cap_from: int = int(Game.state["heroes"]["cap"]["location"])
	var dist_before: int = Game._live_ring_dist(cap_from, 0)
	var iron_before: int = int(Game.state["heroes"]["ironman"]["hand"].size())
	await VillainRules.resolve_effect(Game, tg)
	_check("触手抓握：英雄被拉近一格（3→2 或 3→4，两侧等距时取先算的一侧）",
		Game._live_ring_dist(int(Game.state["heroes"]["cap"]["location"]), 0) == dist_before - 1
			and [2, 4].has(int(Game.state["heroes"]["cap"]["location"])),
		"loc=%d" % int(Game.state["heroes"]["cap"]["location"]))
	_check("触手抓握：已在反派地点的英雄不移动", int(Game.state["heroes"]["ironman"]["location"]) == 0,
		"loc=%d" % int(Game.state["heroes"]["ironman"]["location"]))
	_check("触手抓握：随后 BAM（所在地点英雄 1 伤 + 放 1 危机）",
		Game.state["heroes"]["ironman"]["hand"].size() == iron_before - 1 and int(Game.state["locations"][0]["crisis"]) == 1,
		"iron=%d crisis=%d" % [Game.state["heroes"]["ironman"]["hand"].size(), int(Game.state["locations"][0]["crisis"])])

	# ---------- 10. 溢出：一张卡在一个地点只结算 1 次（无论放不下几个） ----------
	Game.setup("docock", ["cap", "ironman"], "none", "base")
	for _ll in Game.state["locations"]:
		_ll["crisis"] = 0
	Game.state["villain_pos"] = 3
	var ccw: int = int(Game._adjacent_locs(3)[0])
	var lc: Dictionary = Game.state["locations"][ccw]
	var slots_total: int = int(DB.location(lc["id"])["slots"])
	lc["civ"] = slots_total      # 该地点已满
	lc["thug"] = 0
	await Game._do_placement([["civ", "civ", "thug"], [], []])
	_check("溢出：一张卡在同一地点放不下 3 个 → 只加 1 个危机", int(lc["crisis"]) == 1,
		"crisis=%d" % int(lc["crisis"]))
	lc["crisis"] = 0
	Game._begin_overflow_event()      # 新的一次结算事件
	await Game._place_token_at("civ", ccw, 3)
	_check("溢出：一次结算内连续放置 3 个 → 仍只加 1 个危机", int(lc["crisis"]) == 1,
		"crisis=%d" % int(lc["crisis"]))
	lc["crisis"] = 0
	Game._begin_overflow_event()      # 又一次独立结算
	await Game._place_token_at("civ", ccw, 1)
	_check("溢出：只放 1 个放不下 → 加 1 个危机", int(lc["crisis"]) == 1,
		"crisis=%d" % int(lc["crisis"]))

	# ---------- 11. 被摧毁的地点不可进入；其左右两地点互为相邻 ----------
	Game.setup("docock", ["cap", "ironman"], "none", "base")
	var d := 1
	Game.state["locations"][d]["destroyed"] = true
	Game.state["locations"][d]["civ"] = 0
	Game.state["locations"][d]["thug"] = 0
	Game.state["locations"][d]["threat"] = null
	var adj0: Array = Game._adjacent_locs(0)
	_check("B 被摧毁后 A 的相邻地点跳过 B（A 与 C 相邻）",
		not adj0.has(d) and adj0.has(2) and adj0.has(Game.LOCATION_COUNT - 1), str(adj0))
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	Game.state["heroes"]["cap"]["location"] = 0
	Game.state["heroes"]["cap"]["ko"] = false
	Game.state["locations"][0]["threat"] = null
	Game.state["action_symbols"] = ["move"]
	Game.state["used_tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
	_last_rows = []
	_pa_answer = 1      # 第 2 个相邻地点（应 = C，而不是被摧毁的 B）
	await Game._execute_move("cap", "move")
	var moved: int = int(Game.state["heroes"]["cap"]["location"])
	var names: Array = []
	for r in _last_rows:
		names.append(String(r.get("text", "")))
	_check("移动选项不含被摧毁的地点", not names.has(Game._loc_name(d)), str(names))
	_check("选择第 2 项 → 移动到另一个相邻存活地点（A→C）", moved == 2, "loc=%d（期望 2）" % moved)
	_pa_answer = 0
	Game.state["heroes"]["cap"]["location"] = 0      # 回到 A 再测另一侧
	Game.state["action_symbols"] = ["move"]
	await Game._execute_move("cap", "move")
	_check("选择第 1 项 → 移动到另一侧相邻地点", int(Game.state["heroes"]["cap"]["location"]) == Game.LOCATION_COUNT - 1,
		"loc=%d（期望 %d）" % [int(Game.state["heroes"]["cap"]["location"]), Game.LOCATION_COUNT - 1])

	# ---------- 12. 被 KO 的英雄也必须离开被摧毁的地点（否则卡在已移出游戏的地点上） ----------
	Game.setup("docock", ["cap", "ironman"], "none", "base")
	var dd := 2
	for _l3 in Game.state["locations"]:
		_l3["crisis"] = 0
		_l3["destroyed"] = false
	Game.state["heroes"]["cap"]["location"] = dd
	Game.state["heroes"]["ironman"]["location"] = Game.LOCATION_COUNT - 1
	Game.state["heroes"]["cap"]["ko"] = true      # cap 被 KO 在该地点
	var adj_before: Array = Game._adjacent_locs(dd)   # 摧毁前的相邻两地点（摧毁后该点不在存活环上）
	Game.state["locations"][dd]["crisis"] = 3
	Game.state["locations"][dd]["threat"] = null
	_pa_answer = 0
	await Game._docock_check_destroy()
	var cap_loc: int = int(Game.state["heroes"]["cap"]["location"])
	_check("被 KO 的英雄在所在地点被摧毁时也能被移走（不再卡在摧毁地点）",
		cap_loc != dd and adj_before.has(cap_loc),
		"cap loc=%d（原 %d，摧毁前相邻=%s）" % [cap_loc, dd, str(adj_before)])
	_check("KO 状态保持不变", bool(Game.state["heroes"]["cap"]["ko"]), "ko 被改写")
	# 兜底：即便英雄还留在被摧毁地点，复活时也会被挪到相邻存活地点
	Game.state["heroes"]["cap"]["location"] = dd
	await Game._revive_hero("cap")
	_check("复活兜底：仍在被摧毁地点时会挪到相邻存活地点",
		int(Game.state["heroes"]["cap"]["location"]) != dd,
		"loc=%d" % int(Game.state["heroes"]["cap"]["location"]))

	if _fail == 0:
		print("=== DOCOCK TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== DOCOCK FAILED (%d) ===" % _fail)
		get_tree().quit(1)
