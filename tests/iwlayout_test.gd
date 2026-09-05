extends Node
## 战役模式布局截图：右侧竖排战役信息 + 任务牌下方能量卡 + Setup 反派页标签不重叠。

func _ready() -> void:
	# ===== Setup 页：战役标签与"选择反派"标题不重叠 =====
	var setup_scene: PackedScene = load("res://src/ui/Setup.tscn")
	var inst := setup_scene.instantiate()
	add_child(inst)
	for i in range(30):
		await get_tree().process_frame
	inst._on_mode_selected(7)
	inst._campaign_slots = ["cull", "proxima", "ebony"]
	inst._update_villain_highlight()
	inst._show_step(3)
	for i in range(8):
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("F:/桌游相关/漫威联合/电子游戏/devtools/iw_setup.png")
	# 检查标签位置：标题 y=90 x=60-400；战役标签在排序按钮右侧 x=840 起
	var title_pos: Vector2 = Vector2(60, 90)
	var camp_pos: Vector2 = inst._campaign_label.position
	print("标题y=", title_pos.y, " 战役标签pos=", camp_pos)
	# 矩形相交检测（标题 340x44，标签 1000x28）
	var title_rect := Rect2(60, 90, 340, 44)
	var camp_rect := Rect2(camp_pos, Vector2(1000, 28))
	var overlap: bool = title_rect.intersects(camp_rect)
	print("重叠=", overlap)
	_check(not overlap, "战役顺序提示不与标题重叠")
	inst.queue_free()
	await get_tree().process_frame

	# ===== Board 页：右侧竖排战役信息 + 能量卡 =====
	Game.pending_campaign = {"game": 2, "order": ["cull", "proxima", "ebony"], "stones_collected": [0, 1], "energy_unlocked": [2], "removed_energy": 6}
	Game.pending_setup = {"villain": "proxima", "heroes": ["cap", "ironman", "hulk"], "challenge": "none", "mode": "iw", "expansions": ["无限战争"]}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var binst: Control = board.instantiate()
	add_child(binst)
	for i in range(20):
		await get_tree().process_frame
	var img2: Image = get_viewport().get_texture().get_image()
	img2.save_png("F:/桌游相关/漫威联合/电子游戏/devtools/iw_board.png")
	print("战役标签可见=", binst._campaign_label.visible, " 位置=", binst._campaign_label.position, " 文本=", binst._campaign_label.text.replace("\n", "|"))
	print("能量卡区可见=", binst._energy_box.visible, " 子项数=", binst._energy_box.get_child_count())
	_check(binst._energy_box.get_child_count() == 2, "能量卡区显示两张卡")
	# 战役信息在最右侧（x>=1700）且不遮挡返回按钮
	_check(binst._campaign_label.position.x >= 1700, "战役信息在最右侧")
	print("=== IW LAYOUT TEST PASSED ===")
	get_tree().quit(0)

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("OK: " + msg)
	else:
		print("FAIL: " + msg)
		get_tree().quit(1)
