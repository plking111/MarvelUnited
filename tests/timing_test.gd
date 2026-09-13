extends Node
## 时序专项测试：秃鹫（战利品判负后立即中断后续步骤）+ 神秘客（翻牌消耗行动/不破坏阶段）+ 反派被移走后攻击落空
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

	# ================= A. 秃鹫：BAM 收满战利品判负后，本回合后续"效果/放置"必须中断 =================
	Game.setup("vulture", ["cap", "ironman", "hulk"], "none", "base")
	Game.state["vulture_loot"] = 6                 # 3 人局阈值 7
	Game.state["villain_pos"] = 0
	Game.state["locations"][0]["crisis"] = 2
	for hid in Game.state["hero_ids"]:
		Game.state["heroes"][hid]["location"] = 3  # 英雄不在反派地点 → 不做"受2伤阻止"
	# 卡7（index 6）：move2 + BAM + place [民/民民/民]
	Game.state["master_deck"] = [6, 0, 1]
	var civ_before := 0
	for l in Game.state["locations"]:
		civ_before += int(l["civ"])
	await Game._run_villain_turn()
	var civ_after := 0
	for l in Game.state["locations"]:
		civ_after += int(l["civ"])
	_check("A1 战利品收满判负", Game.state["phase"] == "game_over" and String(Game.state.get("lose_reason", "")).contains("战利品"),
		"phase=%s loot=%d" % [Game.state["phase"], int(Game.state["vulture_loot"])])
	_check("A2 判负后跳过该卡放置", civ_after == civ_before, "civ %d->%d" % [civ_before, civ_after])

	# ================= B. 秃鹫：放置过程中溢出判负 → 剩余放置立即中断 =================
	Game.setup("vulture", ["cap", "ironman", "hulk"], "none", "base")
	Game.state["vulture_loot"] = 6
	Game.state["villain_pos"] = 0
	var full_loc := 5                                   # place[0] 落在 (vpos-1)=5
	var slots: int = int(DB.location(Game.state["locations"][full_loc]["id"])["slots"])
	Game.state["locations"][full_loc]["civ"] = slots    # 已放满 → 触发溢出
	Game.state["locations"][full_loc]["thug"] = 0
	Game.state["locations"][full_loc]["crisis"] = 1     # 溢出会收走它 → 战利品 7 → 判负
	Game.state["locations"][1]["civ"] = 0
	Game.state["locations"][0]["civ"] = 0
	await Game._do_placement([["civ"], ["civ", "civ"], ["civ"]])
	_check("B1 溢出判负", Game.state["phase"] == "game_over", "phase=%s loot=%d" % [Game.state["phase"], int(Game.state["vulture_loot"])])
	_check("B2 判负后不再继续放置", int(Game.state["locations"][0]["civ"]) == 0 and int(Game.state["locations"][1]["civ"]) == 0,
		"loc0 civ=%d loc1 civ=%d" % [int(Game.state["locations"][0]["civ"]), int(Game.state["locations"][1]["civ"])])

	# ================= C. 秃鹫：电磁飞翼把秃鹫移走后，同一次行动的后续攻击落空 =================
	Game.setup("vulture", ["cap", "ironman", "hulk"], "none", "base")
	Game.state["villain_pos"] = 0
	Game.state["locations"][0]["threat"] = {"name": "电磁飞翼·秃鹫", "text": "", "hp": 0, "heroic_tokens": 0,
		"arrival": false, "bam": false, "constant": true, "_face_down": false}
	Game.state["missions_completed"] = 2
	Game.state["villain_hp"] = 6
	await Game._perform_attack_at(0, "villain", "cap")
	var hp_mid: int = int(Game.state["villain_hp"])
	var pos_mid: int = int(Game.state["villain_pos"])
	await Game._perform_attack_at(0, "villain", "cap")   # 秃鹫已移走 → 应落空
	_check("C1 首次攻击只扣1并移对面", hp_mid == 5 and pos_mid == 3, "hp=%d pos=%d" % [hp_mid, pos_mid])
	_check("C2 移走后旧地点攻击落空", int(Game.state["villain_hp"]) == 5, "hp=%d" % int(Game.state["villain_hp"]))

	# ================= D. 神秘客：翻牌消耗 1 个任意行动且不破坏行动阶段 =================
	Game.setup("mysterio", ["cap", "ironman", "hulk"], "none", "base")
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	Game.state["action_symbols"] = ["move", "attack"]
	Game.state["used_tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
	var acts_before: int = Game.state["action_symbols"].size()
	var fd_before: int = Game._face_down_threat_locs().size()
	await Game.reveal_threat_choice()
	var revealed := Game._face_down_threat_locs().size() == fd_before - 1
	_check("D1 翻牌消耗1个行动", Game.state["action_symbols"].size() == acts_before - 1,
		"actions %d->%d" % [acts_before, Game.state["action_symbols"].size()])
	_check("D2 翻牌后仍处在行动阶段", Game.state["phase"] == "hero_actions", "phase=%s" % Game.state["phase"])
	_check("D3 恰好翻开一张", revealed, "face_down %d->%d" % [fd_before, Game._face_down_threat_locs().size()])

	# ================= E. 神秘客：全息投影后全部回到背面朝上（不残留已揭示状态） =================
	Game.state["locations"][2]["threat"] = {"name": "破碎幻像", "text": "", "hp": 0, "heroic_tokens": 0,
		"arrival": false, "bam": false, "constant": true, "_face_down": false, "_tidx": 1}
	_check("E1 场上有已揭示幻像", Game._mysterio_illusion_present(), "")
	await VillainRules._mysterio_hologram(Game)
	_check("E2 全息投影后不再有已揭示幻像", not Game._mysterio_illusion_present(), "")
	var all_fd := true
	for l in Game.state["locations"]:
		if l["threat"] != null and not l["threat"].get("_face_down", false):
			all_fd = false
	_check("E3 全息投影后全部背面朝上", all_fd, "")

	if _fail == 0:
		print("=== TIMING TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== TIMING FAILED (%d) ===" % _fail)
		get_tree().quit(1)
