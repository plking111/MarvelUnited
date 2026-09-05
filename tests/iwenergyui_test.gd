extends Node
## 能量卡新 UI 验证：卡图放大、2×2 槽位图标、未解锁卡置暗+锁。

func _ready() -> void:
	Game.pending_campaign = {"game": 2, "order": ["cull", "proxima", "ebony"], "stones_collected": [0], "energy_unlocked": [], "removed_energy": 6}
	Game.pending_setup = {"villain": "proxima", "heroes": ["cap", "ironman", "hulk"], "challenge": "none", "mode": "iw", "expansions": ["无限战争"]}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(15):
		await get_tree().process_frame
	# 强制：table=6（第7张：attack/heroic/move/threat，含威胁槽），hidden=1（未解锁，置暗+锁）
	Game.state["table_energy"] = 6
	Game.state["hidden_energy"] = 1
	Game.state["campaign"]["table_energy"] = 6
	Game.state["campaign"]["hidden_energy"] = 1
	Game.state["energy_tokens"] = {"6": [], "1": []}
	Game.state["missions_completed"] = 0
	inst._refresh_phase()
	inst._refresh_energy_cards(Game.state)
	for i in range(6):
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("F:/桌游相关/漫威联合/电子游戏/devtools/iw_energy_ui.png")
	var boxes: Array = inst._energy_box.get_children()
	print("能量卡区子项数:", boxes.size())
	if boxes.size() == 2:
		var b0: Control = boxes[0]
		var b1: Control = boxes[1]
		# 卡0：可解锁，无锁；卡1：锁定（置暗+锁 label）
		var lock_count := 0
		for c in b1.get_children():
			if c is Label and c.text.contains("🔒"):
				lock_count += 1
		print("卡1 锁图标数:", lock_count)
		# 卡0 槽位图标数：3 个 38×38 + 1 个 28×28（威胁槽缩小），叠加在卡图内部
		var slot_count := 0
		var threat_small := false
		var slots_in_card := true
		for c in b0.get_children():
			if c is TextureRect and (c.custom_minimum_size.x == 38 or c.custom_minimum_size.x == 28):
				slot_count += 1
				if c.custom_minimum_size.x == 28:
					threat_small = true
				# 槽位应位于卡图区域内部（卡图 x 10-140, y 14-142）
				if c.position.y < 14 or c.position.y > 142:
					slots_in_card = false
		print("卡0 槽位图标数:", slot_count, " 威胁槽缩小:", threat_small, " 槽位在卡图内:", slots_in_card)
		# 编号标签
		var num_text := ""
		for c in b0.get_children():
			if c is Label and c.text.contains("能量卡"):
				num_text = c.text
		print("卡0 编号:", num_text)
		if lock_count == 1 and slot_count == 4 and threat_small and slots_in_card and num_text.contains("能量卡 1"):
			print("=== IW ENERGY UI PASSED ===")
			get_tree().quit(0)
		else:
			print("=== IW ENERGY UI FAILED ===")
			get_tree().quit(1)
	else:
		print("=== IW ENERGY UI FAILED (子项数) ===")
		get_tree().quit(1)
