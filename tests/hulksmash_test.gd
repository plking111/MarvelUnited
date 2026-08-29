extends Node
## 验证绿巨人「重击！」：对所在地点所有暴徒(击败)/爪牙/英雄/反派(需2任务)各1伤，随后丢弃全部平民。

func _ready() -> void:
	Game.pending_setup = {"villain": "redskull", "heroes": ["cap", "ironman", "hulk"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	var st: Dictionary = Game.state
	# 场景：浩克在 2 号地点；cap 也在 2 号；ironman 在别处
	var loc := 2
	st["heroes"]["hulk"]["location"] = loc
	st["heroes"]["cap"]["location"] = loc
	st["heroes"]["ironman"]["location"] = 4
	# 2 号地点：2 暴徒、3 平民、爪牙威胁(生命2)
	st["locations"][loc]["thug"] = 2
	st["locations"][loc]["civ"] = 3
	st["locations"][loc]["threat"] = {"name": "测试爪牙", "hp": 2, "henchman_hp": 2}
	# 反派在 2 号地点（红骷髅，任务未完成 <2 → 不受伤害）
	st["villain_pos"] = loc
	st["missions_completed"] = 1
	# cap 有手牌避免 KO
	st["heroes"]["cap"]["hand"] = [0, 1, 2]
	st["heroes"]["ironman"]["hand"] = [0, 1, 2]
	var villain_hp_before: int = st["villain_hp"]
	# 触发 hulk_smash：设置状态后调用 trigger_effect()
	st["phase"] = "hero_actions"
	st["effect_available"] = true
	st["effect_used"] = false
	st["current_hero"] = st["hero_ids"].find("hulk")
	st["played_effect"] = {"type": "hulk_smash", "name": "重击！"}
	st["action_symbols"] = ["move"]  # 留一个符号：阻止自动结束回合推进（保持断言状态）
	Game.autopilot = true
	await Game.trigger_effect()
	# 断言 ① 暴徒全灭
	var ok1: bool = st["locations"][loc]["thug"] == 0
	# 断言 ② 爪牙受 1 伤（2→1）
	var ok2: bool = st["locations"][loc]["threat"]["hp"] == 1
	# 断言 ③ 同地点英雄 cap 受 1 伤（弃1牌：3→2）；ironman 不受
	var ok3: bool = st["heroes"]["cap"]["hand"].size() == 2 and st["heroes"]["ironman"]["hand"].size() == 3
	# 断言 ④ 任务<2，反派不受伤害
	var ok4: bool = st["villain_hp"] == villain_hp_before
	# 断言 ⑤ 平民全丢
	var ok5: bool = st["locations"][loc]["civ"] == 0
	# 断言 ⑥ 击败的 2 暴徒计入击败任务区；弃置的平民不计入营救任务区
	var defeat_tokens := 0
	var rescue_tokens := 0
	for m in st["missions"]:
		if m["id"] == "defeat":
			defeat_tokens = m["tokens"]
		if m["id"] == "rescue":
			rescue_tokens = m["tokens"]
	var ok6: bool = defeat_tokens == 2 and rescue_tokens == 0
	print("暴徒=", st["locations"][loc]["thug"], " 爪牙hp=", st["locations"][loc]["threat"]["hp"], " cap手牌=", st["heroes"]["cap"]["hand"].size(), " 平民=", st["locations"][loc]["civ"], " 反派hp=", st["villain_hp"], "/", villain_hp_before, " 击败任务=", defeat_tokens, " 营救任务=", rescue_tokens)
	# 场景2：完成任务≥2，反派在浩克地点 → 反派受 1 伤
	st["missions_completed"] = 2
	st["villain_hp"] = villain_hp_before + 1
	st["heroes"]["cap"]["hand"] = [0, 1, 2]
	st["phase"] = "hero_actions"
	st["effect_available"] = true
	st["effect_used"] = false
	st["current_hero"] = st["hero_ids"].find("hulk")
	st["played_effect"] = {"type": "hulk_smash", "name": "重击！"}
	st["action_symbols"] = ["move"]
	await Game.trigger_effect()
	var ok7: bool = st["villain_hp"] == villain_hp_before
	print("任务完成后反派hp=", st["villain_hp"], " (期望=", villain_hp_before, ")")
	if ok1 and ok2 and ok3 and ok4 and ok5 and ok6 and ok7:
		print("=== HULK SMASH TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== HULK SMASH TEST FAILED ===", [ok1, ok2, ok3, ok4, ok5, ok6, ok7])
		get_tree().quit(1)
