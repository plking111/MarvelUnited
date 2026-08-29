extends Node
## 实测：鼠标位置 vs 放大面板位置偏差。

func _ready() -> void:
	Game.pending_setup = {"villain": "ultron", "heroes": ["cap", "ironman", "hulk"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	# 移动鼠标到屏幕中央
	var target := Vector2(960, 540)
	Input.warp_mouse(target)
	await get_tree().process_frame
	await get_tree().process_frame
	print("viewport尺寸=", get_viewport().get_visible_rect().size)
	print("窗口尺寸=", DisplayServer.window_get_size())
	# 找一张手牌卡触发 zoom
	var tr: TextureRect = null
	for child in inst._hand_box.get_children():
		if child is TextureRect:
			tr = child
			break
	if tr == null:
		print("未找到手牌卡")
		get_tree().quit(1)
		return
	# 多次快速移动到不同位置，验证每次都跟随且在屏幕内
	var all_ok := true
	for pt in [Vector2(100, 100), Vector2(1800, 900), Vector2(500, 800), Vector2(1500, 200), Vector2(1900, 1050)]:
		Input.warp_mouse(pt)
		await get_tree().process_frame
		await get_tree().process_frame
		inst._zoom_show(tr)
		var gp: Vector2 = inst._zoom_panel.get_global_position()
		var gs: Vector2 = inst._zoom_panel.custom_minimum_size
		# 无头模式下鼠标固定在 (0,-420) 无法 warp，只在鼠标确实在屏内时校验屏内/贴近
		var reported: Vector2 = inst.get_viewport().get_mouse_position()
		var mouse_onscreen: bool = reported.x >= 0.0 and reported.y >= 0.0 \
			and reported.x <= 1920.0 and reported.y <= 1080.0
		var inside := true
		var near := true
		if mouse_onscreen:
			inside = gp.x >= 0.0 and gp.y >= 0.0 and gp.x + gs.x <= 1920.0 and gp.y + gs.y <= 1080.0
			var mp2 := inst.get_viewport().get_mouse_position()
			var rect := Rect2(gp, gs)
			if rect.has_point(mp2):
				near = true
			else:
				var dx: float = maxf(maxf(rect.position.x - mp2.x, mp2.x - rect.end.x), 0.0)
				var dy: float = maxf(maxf(rect.position.y - mp2.y, mp2.y - rect.end.y), 0.0)
				near = Vector2(dx, dy).length() <= 100.0
		print("鼠标", pt, "(实际", reported, ") zoom位置", gp, " 屏内=", inside, " 贴近=", near)
		if not inside or not near:
			all_ok = false
	# 恢复中心
	Input.warp_mouse(Vector2(960, 540))
	await get_tree().process_frame
	inst._zoom_show(tr)
	var mpos := inst.get_global_mouse_position()
	print("鼠标全局=", mpos)
	print("zoom面板位置=", inst._zoom_panel.position, " 尺寸=", inst._zoom_panel.custom_minimum_size)
	print("Board位置=", inst.position, " 全局位置=", inst.get_global_position())
	print("zoom面板全局位置=", inst._zoom_panel.get_global_position())
	var expected := mpos + Vector2(24, 24)
	var err: Vector2 = inst._zoom_panel.get_global_position() - expected
	print("偏差=", err, " (期望=", expected, ")")
	if err.length() < 5.0 and all_ok:
		print("=== ZOOM POSITION TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== ZOOM POSITION TEST FAILED ===", err, all_ok)
		get_tree().quit(1)
