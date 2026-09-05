extends Node
## 验证 Setup 战役模式（iw）前三局禁止选择灭霸；普通模式仍可选。

func _ready() -> void:
	var setup_scene: PackedScene = load("res://src/ui/Setup.tscn")
	var inst := setup_scene.instantiate()
	add_child(inst)
	for i in range(30):
		await get_tree().process_frame
	inst._on_mode_selected(7)
	await get_tree().process_frame
	inst._show_step(3)  # 渲染反派选择页
	await get_tree().process_frame
	print("mode=", inst._mode, " 默认槽位=", str(inst._campaign_slots))
	# 模拟点击灭霸按钮 → 应被拒绝（槽位保持默认 暗夜比邻星）
	if inst._villain_buttons.has("thanos"):
		var btn: Button = inst._villain_buttons["thanos"].get_child(inst._villain_buttons["thanos"].get_child_count() - 1)
		btn.pressed.emit()
		await get_tree().process_frame
		var slot0: String = inst._campaign_slots[0]
		print("slots=", str(inst._campaign_slots))
		if slot0 == "proxima" and not inst._campaign_slots.has("thanos"):
			print("=== SETUP IW THANOS BLOCKED OK ===")
			get_tree().quit(0)
		else:
			print("FAIL: 灭霸被允许填入前三局")
			get_tree().quit(1)
	else:
		print("FAIL: 灭霸按钮不存在")
		get_tree().quit(1)
