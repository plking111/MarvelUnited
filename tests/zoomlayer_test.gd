extends Node
## 验证：悬停放大预览位于独立 CanvasLayer(50)——在主界面（含动态重建的
## 图标/卡片节点）之上、弹窗层(100)之下，任何刷新都不会遮挡它。

func _ready() -> void:
	Game.pending_setup = {"villain": "ultron", "heroes": ["cap", "ironman", "hulk"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	# 动态刷新（模拟重建图标/卡片节点）
	inst._refresh_locations()
	inst._refresh_hero_badges()
	for i in range(5):
		await get_tree().process_frame
	# 放大面板必须在独立 CanvasLayer(50)
	var zl: CanvasLayer = inst._zoom_panel.get_parent()
	var layer_ok: bool = zl is CanvasLayer and zl.layer == 50
	print("放大面板父节点=", zl.name if zl != null else "null",
		" 是CanvasLayer=", zl is CanvasLayer,
		" layer=", (zl.layer if zl is CanvasLayer else -1),
		" -> 层配置=", layer_ok)
	# 触发放大仍正常
	var zoom_tr: TextureRect = null
	for child in inst._hand_box.get_children():
		if child is TextureRect:
			zoom_tr = child
			break
	var zoom_ok := false
	if zoom_tr != null:
		inst._zoom_show(zoom_tr)
		zoom_ok = inst._zoom_panel.visible and inst._zoom_panel.texture != null
		print("触发放大 visible=", inst._zoom_panel.visible)
	if layer_ok and zoom_ok:
		print("=== ZOOM LAYER TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== ZOOM LAYER TEST FAILED ===")
		get_tree().quit(1)
