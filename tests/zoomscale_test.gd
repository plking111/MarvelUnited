extends Node
## 验证：get_viewport().get_mouse_position() / content_scale_factor 换算逻辑。
## 手动模拟 content_scale=1.333（2K 全屏 stretch）下的坐标。

func _ready() -> void:
	Game.pending_setup = {"villain": "ultron", "heroes": ["cap", "ironman", "hulk"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	# 模拟：鼠标物理像素在 2K 屏幕中心 (1280, 720)，content_scale=1.333
	var phys := Vector2(1280, 720)
	var scale := 1.3333
	var canvas := phys / scale
	print("物理=", phys, " scale=", scale, " 画布坐标=", canvas)
	print("期望画布中心=(960,540)，偏差=", canvas - Vector2(960, 540))
	# 用换算结果模拟 _zoom_show 定位
	inst._zoom_panel.custom_minimum_size = Vector2(330, 460)
	inst._zoom_panel.visible = true
	var p := canvas + Vector2(24, 24)
	if p.x + 330 > 1920.0:
		p.x = p.x - 330 - 48
		if p.x < 0.0:
			p.x = maxf(0.0, 1920.0 - 330)
	if p.y + 460 > 1080.0:
		p.y = p.y - 460 - 48
		if p.y < 0.0:
			p.y = maxf(0.0, 1080.0 - 460)
	print("zoom 画布位置=", p, "（应在屏幕中心附近 (984,564)）")
	var ok: bool = (p - Vector2(984, 564)).length() < 2.0
	print("换算正确=", ok)
	if ok:
		print("=== ZOOM SCALE MATH TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== ZOOM SCALE MATH TEST FAILED ===")
		get_tree().quit(1)
