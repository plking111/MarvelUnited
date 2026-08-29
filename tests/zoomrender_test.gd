extends Node
## 截图验证：指向面板前后，放大图实际渲染像素位置应一致。

func _ready() -> void:
	Game.pending_setup = {"villain": "ultron", "heroes": ["cap", "ironman", "hulk"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	var cards: Array = []
	for child in inst._hand_box.get_children():
		if child is TextureRect:
			cards.append(child)
	if cards.size() == 0:
		get_tree().quit(1)
		return
	var hand: TextureRect = cards[0]
	var hand_center: Vector2 = hand.get_global_rect().get_center()
	# 场景1：指向英雄牌 → 截图
	Input.warp_mouse(hand_center)
	for i in range(8):
		await get_tree().process_frame
	var img1: Image = get_viewport().get_texture().get_image()
	img1.save_png("F:/桌游相关/漫威联合/电子游戏/devtools/zoom_before.png")
	print("场景1 zoom rect=", Rect2(inst._zoom_panel.position, inst._zoom_panel.size))
	# 场景2：指向反派面板
	var panel_center: Vector2 = inst._villain_panel.get_global_rect().get_center()
	Input.warp_mouse(panel_center)
	for i in range(8):
		await get_tree().process_frame
	# 场景3：再指向英雄牌 → 截图
	Input.warp_mouse(hand_center)
	for i in range(8):
		await get_tree().process_frame
	var img3: Image = get_viewport().get_texture().get_image()
	img3.save_png("F:/桌游相关/漫威联合/电子游戏/devtools/zoom_after.png")
	print("场景3 zoom rect=", Rect2(inst._zoom_panel.position, inst._zoom_panel.size))
	# 对比两张截图在 zoom 区域的像素
	var zr: Rect2 = Rect2(inst._zoom_panel.position, inst._zoom_panel.size)
	var diff := 0
	for y in range(int(zr.position.y), int(zr.end.y), 3):
		for x in range(int(zr.position.x), int(zr.end.x), 3):
			if img1.get_pixel(x, y) != img3.get_pixel(x, y):
				diff += 1
	print("zoom 区域像素差异=", diff)
	if diff < 20:
		print("=== ZOOM RENDER CONSISTENT TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== ZOOM RENDER DIFFERS ===")
		get_tree().quit(1)
