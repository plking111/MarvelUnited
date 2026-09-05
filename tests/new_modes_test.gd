extends Node
## 验证：31个模式图标 + 滚动容器 + 3个新模式说明
func _ready() -> void:
	var setup: PackedScene = load("res://src/ui/Setup.tscn")
	var inst: Control = setup.instantiate()
	add_child(inst)
	for i in range(8):
		await get_tree().process_frame
	var bad: Array = []
	var n: int = inst._mode_buttons.size()
	print("mode buttons=", n)
	if n != 31: bad.append("应有31个模式按钮（实际%d）" % n)
	# 3 个新模式按钮存在且图标加载
	for num in [29,30,31]:
		if not inst._mode_buttons.has(num):
			bad.append("缺模式%d" % num)
		else:
			var b: Control = inst._mode_buttons[num]
			var tr: TextureRect = null
			for c in b.get_children():
				if c is TextureRect:
					tr = c
					break
			if tr == null or tr.texture == null:
				bad.append("模式%d图标未加载" % num)
			else:
				print("mode%d tex=", num, tr.texture.resource_path)
	# 新模式说明
	for num in [29,30,31]:
		var desc: String = inst._mode_info_data.get(str(num), "")
		if desc == "":
			bad.append("模式%d无说明" % num)
		else:
			print("mode%d desc len=", num, desc.length())
	print("---- RESULT ----")
	if bad.is_empty():
		print("=== 3 NEW MODES PASSED ===")
		get_tree().quit(0)
	else:
		print("=== FAILED: ", bad, " ===")
		get_tree().quit(1)
