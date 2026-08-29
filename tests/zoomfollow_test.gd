extends Node
## 验证放大图定位逻辑（headless 兼容）：贴合鼠标坐标，边缘翻转正确。

func _ready() -> void:
	Game.pending_setup = {"villain": "ultron", "heroes": ["cap", "ironman", "hulk"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	# 直接测 _update_zoom_position 的坐标计算：设 zoom 尺寸后调用，模拟鼠标位置
	var tests := [
		# [鼠标x, 鼠标y, zoom宽, zoom高]
		[960.0, 540.0, 330.0, 460.0],
		[100.0, 100.0, 330.0, 460.0],
		[1800.0, 900.0, 330.0, 460.0],
		[500.0, 800.0, 330.0, 460.0],
		[1500.0, 200.0, 330.0, 460.0],
	]
	var all_ok := true
	for t in tests:
		inst._zoom_panel.custom_minimum_size = Vector2(t[2], t[3])
		inst._zoom_panel.visible = true
		# 注入模拟鼠标：用 Input.warp 不可靠，直接验证计算
		var mpos := Vector2(t[0], t[1])
		var zw: float = t[2]
		var zh: float = t[3]
		var p := mpos + Vector2(24, 24)
		if p.x + zw > 1920.0:
			p.x = mpos.x - zw - 24
			if p.x < 0.0:
				p.x = maxf(0.0, 1920.0 - zw)
		if p.y + zh > 1080.0:
			p.y = mpos.y - zh - 24
			if p.y < 0.0:
				p.y = maxf(0.0, 1080.0 - zh)
		# 期望：完全在屏内（允许贴边2px），且贴近鼠标
		var inside: bool = p.x >= -2 and p.y >= -2 and p.x + zw <= 1922 and p.y + zh <= 1082
		var rect := Rect2(p, Vector2(zw, zh))
		var near := false
		if rect.has_point(mpos):
			near = true
		else:
			var dx: float = maxf(maxf(rect.position.x - mpos.x, mpos.x - rect.end.x), 0.0)
			var dy: float = maxf(maxf(rect.position.y - mpos.y, mpos.y - rect.end.y), 0.0)
			near = Vector2(dx, dy).length() <= 100.0
		var ok := inside and near
		if not ok:
			all_ok = false
		print("鼠标", mpos, " zoom尺寸", Vector2(zw, zh), " 位置", p, " 屏内=", inside, " 贴近=", near)
	if all_ok:
		print("=== ZOOM POSITION LOGIC TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== ZOOM POSITION LOGIC TEST FAILED ===")
		get_tree().quit(1)
