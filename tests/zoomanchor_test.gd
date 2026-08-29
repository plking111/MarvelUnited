extends Node
## 验证：放大图位置只由卡牌位置决定，指向反派面板前后其他卡牌放大位置一致。

func _ready() -> void:
	Game.pending_setup = {"villain": "ultron", "heroes": ["cap", "ironman", "hulk"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	# 找两张手牌卡
	var cards: Array = []
	for child in inst._hand_box.get_children():
		if child is TextureRect:
			cards.append(child)
	if cards.size() < 2:
		print("手牌卡不足: ", cards.size())
		get_tree().quit(1)
		return
	var card_a: TextureRect = cards[0]
	var card_b: TextureRect = cards[1]
	# 场景1：先指向卡A（未指向面板）
	inst._zoom_show(card_a)
	var z_a_before: Vector2 = inst._zoom_panel.get_global_position()
	inst._zoom_hide()
	# 场景2：指向反派面板
	inst._zoom_show(inst._villain_panel)
	inst._zoom_hide()
	# 场景3：再指向卡A → 位置必须与场景1一致
	inst._zoom_show(card_a)
	var z_a_after: Vector2 = inst._zoom_panel.get_global_position()
	print("卡A放大位置（指向面板前）=", z_a_before)
	print("卡A放大位置（指向面板后）=", z_a_after)
	var ok1: bool = z_a_before.distance_to(z_a_after) < 1.0
	# 场景4：卡B（指向面板前后一致）
	inst._zoom_hide()
	inst._zoom_show(card_b)
	var z_b_before: Vector2 = inst._zoom_panel.get_global_position()
	inst._zoom_hide()
	inst._zoom_show(inst._villain_panel)
	inst._zoom_hide()
	inst._zoom_show(card_b)
	var z_b_after: Vector2 = inst._zoom_panel.get_global_position()
	print("卡B放大位置（指向面板前）=", z_b_before)
	print("卡B放大位置（指向面板后）=", z_b_after)
	var ok2: bool = z_b_before.distance_to(z_b_after) < 1.0
	# 验证放大图在卡牌旁（屏幕内）
	var zs: Vector2 = inst._zoom_panel.custom_minimum_size
	var inside: bool = z_b_after.x >= 0 and z_b_after.y >= 0 and z_b_after.x + zs.x <= 1920 and z_b_after.y + zs.y <= 1080
	print("放大图屏内=", inside)
	if ok1 and ok2 and inside:
		print("=== ZOOM CONSISTENT TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== ZOOM CONSISTENT TEST FAILED ===", [ok1, ok2, inside])
		get_tree().quit(1)
