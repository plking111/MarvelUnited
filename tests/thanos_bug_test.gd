extends Node
## Bug1+2 验证：灭霸 乌木侯到达打出额外行动卡；灭霸非IW Boss 获得2张激活能量卡
var board: Node
func _ready() -> void:
	Game.pending_setup = {
		"villain": "thanos", "heroes": ["cap", "ironman"], "challenge": "none",
		"mode": "base", "expansions": [], "debug_full_slots": false, "peek_hands": false,
	}
	var scene = load("res://src/ui/Board.tscn")
	board = scene.instantiate()
	add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame
	print("READY heroes=", Game.state["hero_ids"])
	var bad: Array = []

	# ---- Bug2: 非IW灭霸 Boss 应获得 2 张激活能量卡 ----
	var camp: Variant = Game.state.get("campaign", {})
	var unlocked: Array = camp.get("energy_unlocked", []) if camp.size() > 0 else []
	print("energy_unlocked=", unlocked, " table=", Game.state.get("table_energy", -1), " hidden=", Game.state.get("hidden_energy", -1))
	if unlocked.size() != 2:
		bad.append("非IW灭霸应获得2张激活能量卡")
	if Game.state.get("table_energy", -1) < 0 or Game.state.get("hidden_energy", -1) < 0:
		bad.append("应设置 table/hidden 能量卡")

	# ---- Bug1: 乌木侯到达 → 额外打出一张并结算 ----
	# 把反派牌堆固定为"移动0、BAM"的行动卡(索引0)，让反派停驻原地 → 到达效果必触发
	Game.state["master_deck"] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	# 把乌木侯威胁放到反派当前位置
	var vpos: int = Game.state["villain_pos"]
	Game.state["villain_pos"] = vpos
	Game.state["locations"][vpos]["threat"] = {
		"name": "乌木侯", "text": "灭霸抵达该地点效果：立即打出另一张反派行动牌",
		"hp": 4, "henchman_hp": 4, "heroic_tokens": 0, "arrival_triggered": false,
		"bam": false, "arrival": true, "start_turn": false, "constant": false,
	}
	# 记录反派牌堆数量
	var deck_before: int = Game.state["master_deck"].size()
	call_deferred("_begin")
	# 注意：乌木侯的"到达效果"是在**反派回合结束时**（反派最终停驻在该地点）才触发的，
	# 所以必须等整个反派回合跑完（phase 不再是 villain）再量牌堆；
	# 原来固定 80 帧、且"phase==hero_play 且 i>20"就跳出，实测跳出时 phase 仍是 villain → 量早了。
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 25000:
		await get_tree().process_frame
		var pop = board._popup
		if pop.hand_pick_panel.visible:
			pop.confirm_hand_pick()
		elif pop.prompt_panel.visible and pop.prompt_buttons.get_child_count() > 0:
			pop._on_prompt_pick(0)
		if String(Game.state["phase"]) != "villain" and Time.get_ticks_msec() - t0 > 1500:
			break
	await get_tree().create_timer(0.6).timeout   # 留一点时间让"额外打出的一张"结算完
	print("after villain turn: phase=", Game.state["phase"], " deck_before=", deck_before, " deck_after=", Game.state["master_deck"].size(), " villain_pos=", Game.state["villain_pos"])
	# 乌木侯到达应额外打出一张行动牌：牌堆消耗≥2
	var consumed: int = deck_before - Game.state["master_deck"].size()
	print("consumed cards=", consumed)
	if consumed < 2:
		bad.append("乌木侯到达未额外打出行动卡（消耗 %d/%d）" % [consumed, deck_before])
	print("---- RESULT ----")
	if bad.is_empty():
		print("=== BUG1+2 PASSED ===")
		get_tree().quit(0)
	else:
		print("=== FAILED: ", bad, " ===")
		get_tree().quit(1)

func _begin() -> void:
	await Game.start_game()
