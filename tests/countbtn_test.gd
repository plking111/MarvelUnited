extends Node
## 验证：神盾局模式英雄页隐藏人数加减按钮，基础模式显示。

func _ready() -> void:
	var setup: PackedScene = load("res://src/ui/Setup.tscn")
	var inst: Control = setup.instantiate()
	add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	# 初始基础模式（默认 _mode="base"）：加减按钮应可见
	var base_visible: bool = inst._count_minus.visible and inst._count_plus.visible and inst._count_label.visible
	print("基础模式: 减=", inst._count_minus.visible, " 加=", inst._count_plus.visible, " 标题=", inst._count_label.visible)
	# 切到神盾局模式（5号图标）
	inst._on_mode_selected(5)
	var shield_hidden: bool = not inst._count_minus.visible and not inst._count_plus.visible and not inst._count_label.visible
	print("神盾局: 减=", inst._count_minus.visible, " 加=", inst._count_plus.visible, " 标题=", inst._count_label.visible, " 提示=", inst._hero_count_label.text)
	# 切回基础模式（1号图标）→ 恢复显示
	inst._on_mode_selected(1)
	var back_visible: bool = inst._count_minus.visible and inst._count_plus.visible and inst._count_label.visible
	print("切回基础: 减=", inst._count_minus.visible, " 加=", inst._count_plus.visible)
	if base_visible and shield_hidden and back_visible:
		print("=== COUNT BTN MODE TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== COUNT BTN MODE TEST FAILED ===", [base_visible, shield_hidden, back_visible])
		get_tree().quit(1)
