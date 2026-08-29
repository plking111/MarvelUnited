extends Node
## 真实鼠标测试：完整复现「指向英雄牌→指向反派面板→再指向英雄牌」，用真实 mouse_entered 事件。

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
		print("无手牌")
		get_tree().quit(1)
		return
	var hand: TextureRect = cards[0]
	# 1) 真实鼠标移到英雄牌
	var hand_center: Vector2 = hand.get_global_rect().get_center()
	Input.warp_mouse(hand_center)
	for i in range(8):
		await get_tree().process_frame
	var z1: Vector2 = inst._zoom_panel.get_global_position()
	var z1vis: bool = inst._zoom_panel.visible
	print("[1]指向英雄牌: zoom=", z1, " vis=", z1vis, " 卡牌=", hand.get_global_rect())
	# 2) 真实鼠标移到反派面板
	var panel_center: Vector2 = inst._villain_panel.get_global_rect().get_center()
	Input.warp_mouse(panel_center)
	for i in range(8):
		await get_tree().process_frame
	var z2: Vector2 = inst._zoom_panel.get_global_position()
	print("[2]指向反派面板: zoom=", z2, " vis=", inst._zoom_panel.visible, " 面板=", inst._villain_panel.get_global_rect())
	# 3) 真实鼠标再移回英雄牌
	Input.warp_mouse(hand_center)
	for i in range(8):
		await get_tree().process_frame
	var z3: Vector2 = inst._zoom_panel.get_global_position()
	print("[3]再指向英雄牌: zoom=", z3, " vis=", inst._zoom_panel.visible)
	print("英雄牌放大位置 前后对比: ", z1, " vs ", z3, " 差=", z1.distance_to(z3))
	var ok: bool = z1.distance_to(z3) < 1.0 and z1vis
	if ok:
		print("=== REAL MOUSE ZOOM CONSISTENT TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== REAL MOUSE ZOOM CONSISTENT TEST FAILED ===")
		get_tree().quit(1)
