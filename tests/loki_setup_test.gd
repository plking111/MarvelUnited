extends Node
## 验证 Setup 选择反派页能列出洛基，且图标已加载（非 null）
var setup: Node
func _ready() -> void:
	var scene := load("res://src/ui/Setup.tscn")
	setup = scene.instantiate()
	add_child(setup)
	await get_tree().process_frame
	await get_tree().process_frame
	# 切到第 3 步（选择反派）
	setup._show_step(3)
	await get_tree().process_frame
	await get_tree().process_frame
	var bad: Array = []
	# 洛基图标已加载？
	if not setup._villain_icons.has("loki"):
		bad.append("洛基图标未加载")
	elif setup._villain_icons["loki"] == null:
		bad.append("洛基图标为 null（素材缺失）")
	# 洛基在按钮列表？
	# 注意：_render_villains 在 _show_step 时不一定重绘，这里触发一次渲染
	setup._render_villains()
	await get_tree().process_frame
	print("展示洛基前 _villain_buttons 含 loki: ", setup._villain_buttons.has("loki"))
	if setup._villain_buttons.has("loki") and setup._villain_buttons["loki"].get_child_count() > 0:
		print("洛基卡片已渲染")
	else:
		bad.append("洛基按钮未渲染（检查 _render_villains id 列表）")
	print("---- RESULT ----")
	if bad.is_empty():
		print("=== LOKI SETUP PASSED ===")
		get_tree().quit(0)
	else:
		print("=== FAILED: ", bad, " ===")
		get_tree().quit(1)
