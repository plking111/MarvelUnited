extends Node
## 验证反派悬停面板背面预览浮层功能。

func _ready() -> void:
	Game.autopilot = true
	var setup: Control = load("res://src/ui/Setup.tscn").instantiate()
	add_child(setup)
	for i in range(6):
		await get_tree().process_frame
	var bad: Array = []
	# 浮层变量应已创建
	if setup._villain_panel_tooltip == null:
		bad.append("_villain_panel_tooltip 未创建")
	else:
		print("_villain_panel_tooltip 存在")
	# 悬停显示罗南（有面板背面素材）
	setup._show_villain_panel("ronan")
	await get_tree().process_frame
	if not setup._villain_panel_tooltip.visible:
		bad.append("悬停未显示浮层")
	if setup._villain_panel_img.texture == null:
		bad.append("面板背面图未加载(Ronan)")
	else:
		print("Ronan 面板背面图已加载, 尺寸=", setup._villain_panel_img.texture.get_size())
	# 隐藏
	setup._hide_villain_panel()
	await get_tree().process_frame
	if setup._villain_panel_tooltip.visible:
		bad.append("隐藏后仍显示")
	# 缺素材的反派(红骷髅)回退 back.png 立绘
	setup._show_villain_panel("redskull")
	await get_tree().process_frame
	if setup._villain_panel_img.texture == null:
		bad.append("redskull 回退图未加载")
	else:
		print("redskull 回退图已加载")
	setup._hide_villain_panel()
	if bad.is_empty():
		print("=== VILLAIN PANEL TOOLTIP TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== VILLAIN PANEL TOOLTIP FAILED: ", bad, " ===")
		get_tree().quit(1)
