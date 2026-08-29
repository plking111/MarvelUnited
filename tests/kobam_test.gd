extends Node
## 验证：英雄被 KO 时触发反派面板 BAM（底层规则）。

func _ready() -> void:
	Game.pending_setup = {"villain": "ultron", "heroes": ["cap", "ironman", "hulk"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	var st: Dictionary = Game.state
	var vpos: int = st["villain_pos"]
	# 绿巨人 1 张手牌，受 2 点伤害 → 弃 1 张后手牌不足 → KO → 奥创 BAM
	st["heroes"]["hulk"]["hand"] = [0]
	st["heroes"]["hulk"]["deck"] = []
	st["heroes"]["hulk"]["ko"] = false
	# 记录 BAM 前后状态
	var thug_before: int = st["locations"][vpos]["thug"]
	# 其他英雄给手牌避免被 BAM 伤到 KO（干扰）
	for hid in ["cap", "ironman"]:
		st["heroes"][hid]["hand"] = [0, 1, 2]
	Game.autopilot = true
	# 手动触发伤害：绿巨人受 2 伤（弃 1 后 KO）
	await Game._deal_damage_to_hero("hulk", 2)
	var log_has_bam: bool = false
	for entry in st["log"]:
		if str(entry["t"]).contains("BAM"):
			log_has_bam = true
	var ok1: bool = st["heroes"]["hulk"]["ko"] == true
	var ok2: bool = log_has_bam
	var ok3: bool = st["locations"][vpos]["thug"] > thug_before  # 奥创BAM放暴徒（可能有溢出）
	print("hulk KO=", st["heroes"]["hulk"]["ko"], " 日志含BAM=", log_has_bam, " 暴徒=", st["locations"][vpos]["thug"], " 之前=", thug_before)
	# 再验证红骷髅：KO → BAM 恐惧+2
	Game.pending_setup = {"villain": "redskull", "heroes": ["cap", "ironman", "hulk"], "challenge": "none"}
	var board2: PackedScene = load("res://src/ui/Board.tscn")
	var inst2: Control = board2.instantiate()
	add_child(inst2)
	for i in range(10):
		await get_tree().process_frame
	var st2: Dictionary = Game.state
	st2["heroes"]["hulk"]["hand"] = [0]
	st2["heroes"]["hulk"]["deck"] = []
	st2["heroes"]["hulk"]["ko"] = false
	for hid in ["cap", "ironman"]:
		st2["heroes"][hid]["hand"] = [0, 1, 2]
	var fear_before: int = st2["fear"]
	Game.autopilot = true
	await Game._deal_damage_to_hero("hulk", 2)
	var log_bam2: bool = false
	for entry in st2["log"]:
		if str(entry["t"]).contains("BAM"):
			log_bam2 = true
	var ok4: bool = st2["heroes"]["hulk"]["ko"] and log_bam2 and st2["fear"] == fear_before + 2
	print("红骷髅: KO=", st2["heroes"]["hulk"]["ko"], " 日志BAM=", log_bam2, " 恐惧=", st2["fear"], " 之前=", fear_before)
	# 模仿大师：KO → BAM 危机+1
	Game.pending_setup = {"villain": "taskmaster", "heroes": ["cap", "ironman", "hulk"], "challenge": "none"}
	var board3: PackedScene = load("res://src/ui/Board.tscn")
	var inst3: Control = board3.instantiate()
	add_child(inst3)
	for i in range(10):
		await get_tree().process_frame
	var st3: Dictionary = Game.state
	var vpos3: int = st3["villain_pos"]
	st3["heroes"]["hulk"]["hand"] = [0]
	st3["heroes"]["hulk"]["deck"] = []
	st3["heroes"]["hulk"]["ko"] = false
	for hid in ["cap", "ironman"]:
		st3["heroes"][hid]["hand"] = [0, 1, 2]
	var crisis_before: int = st3["locations"][vpos3]["crisis"]
	Game.autopilot = true
	await Game._deal_damage_to_hero("hulk", 2)
	var log_bam3: bool = false
	for entry in st3["log"]:
		if str(entry["t"]).contains("BAM"):
			log_bam3 = true
	var ok5: bool = st3["heroes"]["hulk"]["ko"] and log_bam3 and st3["locations"][vpos3]["crisis"] == crisis_before + 1
	print("模仿大师: KO=", st3["heroes"]["hulk"]["ko"], " 日志BAM=", log_bam3, " 危机=", st3["locations"][vpos3]["crisis"], " 之前=", crisis_before)
	# 场景4：绿巨人手牌打空结束回合 → KO → 奥创 BAM
	Game.pending_setup = {"villain": "ultron", "heroes": ["cap", "ironman", "hulk"], "challenge": "none"}
	var board4: PackedScene = load("res://src/ui/Board.tscn")
	var inst4: Control = board4.instantiate()
	add_child(inst4)
	for i in range(10):
		await get_tree().process_frame
	var st4: Dictionary = Game.state
	var vpos4: int = st4["villain_pos"]
	st4["heroes"]["hulk"]["hand"] = []  # 手牌打空
	st4["heroes"]["hulk"]["deck"] = []
	st4["heroes"]["hulk"]["ko"] = false
	st4["phase"] = "hero_end"
	st4["current_hero"] = st4["hero_ids"].find("hulk")
	st4["hero_cards_played"] = 0
	# 其他英雄给手牌，防止 BAM 造成二次 KO 干扰
	for hid in ["cap", "ironman"]:
		st4["heroes"][hid]["hand"] = [0, 1, 2]
	var thug_b4: int = st4["locations"][vpos4]["thug"]
	Game.autopilot = true
	await Game.end_turn()
	var log_bam4: bool = false
	for entry in st4["log"]:
		if str(entry["t"]).contains("BAM"):
			log_bam4 = true
	var ok6: bool = st4["heroes"]["hulk"]["ko"] and log_bam4
	var ok7: bool = st4["locations"][vpos4]["thug"] == thug_b4 + 3 or st4["locations"][vpos4]["thug"] > thug_b4
	print("场景4(手牌打空KO): KO=", st4["heroes"]["hulk"]["ko"], " BAM=", log_bam4, " 暴徒=", st4["locations"][vpos4]["thug"], " 之前=", thug_b4)
	# 场景5：绿巨人 1 张手牌受 1 伤（刚好弃光）→ 立即 KO → BAM（新规则：弃空即KO）
	Game.pending_setup = {"villain": "ultron", "heroes": ["cap", "ironman", "hulk"], "challenge": "none"}
	var board5: PackedScene = load("res://src/ui/Board.tscn")
	var inst5: Control = board5.instantiate()
	add_child(inst5)
	for i in range(10):
		await get_tree().process_frame
	var st5: Dictionary = Game.state
	var vpos5: int = st5["villain_pos"]
	st5["heroes"]["hulk"]["hand"] = [0]  # 1 张手牌
	st5["heroes"]["hulk"]["deck"] = []
	st5["heroes"]["hulk"]["ko"] = false
	for hid in ["cap", "ironman"]:
		st5["heroes"][hid]["hand"] = [0, 1, 2]
	var thug_b5: int = st5["locations"][vpos5]["thug"]
	Game.autopilot = true
	await Game._deal_damage_to_hero("hulk", 1)  # 弃 1 张刚好弃光
	var log_bam5: bool = false
	for entry in st5["log"]:
		if str(entry["t"]).contains("BAM"):
			log_bam5 = true
	var ok8: bool = st5["heroes"]["hulk"]["ko"] and log_bam5
	print("场景5(弃空即KO): KO=", st5["heroes"]["hulk"]["ko"], " BAM=", log_bam5, " 手牌=", st5["heroes"]["hulk"]["hand"].size())
	if ok1 and ok2 and ok3 and ok4 and ok5 and ok6 and ok7 and ok8:
		print("=== KO BAM TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== KO BAM TEST FAILED ===", [ok1, ok2, ok3, ok4, ok5, ok6, ok7, ok8])
		get_tree().quit(1)
