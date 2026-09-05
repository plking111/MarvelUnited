extends Node
## 联机准备页验证：创建/加入房间禁用（功能未实现），本地游戏/返回可用。

func _ready() -> void:
	var scene: PackedScene = load("res://src/ui/OnlinePrep.tscn")
	var inst: Control = scene.instantiate()
	add_child(inst)
	for i in range(5):
		await get_tree().process_frame
	var bad: Array = []
	var buttons: Array = []
	for c in inst.get_children():
		if c is Button:
			buttons.append(c)
	print("按钮数=", buttons.size(), " 文本=", str(buttons.map(func(b): return b.text)))
	if buttons.size() != 4:
		bad.append("应有 4 个按钮: %d" % buttons.size())
	var texts: Array = buttons.map(func(b): return b.text)
	if not texts.has("创建房间") or not texts.has("加入房间") or not texts.has("本地游戏") or not texts.has("返回"):
		bad.append("按钮文本不齐全: %s" % str(texts))
	for b in buttons:
		if b.text == "创建房间" or b.text == "加入房间":
			if not b.disabled:
				bad.append("%s 应禁用（联机未实现）" % b.text)
		else:
			if b.disabled:
				bad.append("%s 不应禁用" % b.text)
	if bad.is_empty():
		print("=== ONLINE PREP TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== ONLINE PREP TEST FAILED: ", bad, " ===")
		get_tree().quit(1)
