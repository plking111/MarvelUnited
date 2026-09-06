extends Node
## 反派选择 UI 渲染验证：Setup 页应渲染罗南按钮。

func _ready() -> void:
	var setup: Control = load("res://src/ui/Setup.tscn").instantiate()
	add_child(setup)
	for i in range(6):
		await get_tree().process_frame
	var bad: Array = []
	# Setup 构建后应已填充 _villain_icons 和渲染反派
	var icons: Dictionary = setup._villain_icons
	if not icons.has("ronan"):
		bad.append("_villain_icons 无 ronan")
	else:
		print("_villain_icons 含 ronan: ", str(icons.has("ronan")))
	var buttons: Dictionary = setup._villain_buttons
	print("_villain_buttons keys: ", str(buttons.keys()))
	if not buttons.has("ronan"):
		bad.append("_villain_buttons 无 ronan（未渲染）")
	else:
		print("_villain_buttons 含 ronan: ", str(buttons.has("ronan")))
	if bad.is_empty():
		print("=== RONAN UI TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== RONAN UI FAILED: ", bad, " ===")
		get_tree().quit(1)
