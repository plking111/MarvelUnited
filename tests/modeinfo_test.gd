extends Node
## 模式说明窗口验证：悬停模式显示说明；窗口跟随鼠标且在屏内；
## 所有模式窗口尺寸/字体一致、标题红色内容黑色、内容非空。

func _ready() -> void:
	var setup: PackedScene = load("res://src/ui/Setup.tscn")
	var inst: Control = setup.instantiate()
	add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	var bad: Array = []
	# 1) 悬停 1 号模式：窗口显示、标题与内容正确
	inst._on_mode_hover(1)
	var shown: bool = inst._mode_info.visible
	var title1: String = inst._mode_info_title.text
	var desc1: String = inst._mode_info_desc.text
	print("悬停1: 显示=", shown, " 标题=", title1, " 描述长度=", desc1.length())
	if not shown:
		bad.append("悬停模式应显示说明窗口")
	if title1 != "基础模式":
		bad.append("标题应为模式名: %s" % title1)
	if desc1.length() < 10:
		bad.append("说明内容为空或过短")
	# 右上角提示存在
	var tip_found := false
	for c in inst._step_pages[1].get_children():
		if c is Label and (c.text.contains("模式图标仅代表") or c.text.contains("扩展带来的模式")):
			tip_found = true
	if not tip_found:
		bad.append("缺少右上角扩展提示")
	# 2) 颜色：标题红、内容黑
	var tcol: Color = inst._mode_info_title.get_theme_color("font_color")
	var dcol: Color = inst._mode_info_desc.get_theme_color("font_color")
	print("标题色=", str(tcol), " 内容色=", str(dcol))
	if tcol.r < 0.6 or tcol.g > 0.4 or tcol.b > 0.4:
		bad.append("标题应为红色")
	if dcol.r > 0.3 or dcol.g > 0.3 or dcol.b > 0.3:
		bad.append("内容应为黑色")
	# 3) 遍历 1-28：全部有说明，校验内容/尺寸/字体（未选中时移出悬停应隐藏）
	var size_ok := true
	var font_ok := true
	var desc_ok := true
	for num in range(1, 29):
		inst._on_mode_hover(num)
		if not inst._mode_info.visible:
			bad.append("模式 %d 应显示说明窗口" % num)
			continue
		var d: String = inst._mode_info_desc.text
		if d.length() < 10:
			desc_ok = false
		if inst._mode_info.size != Vector2(640, 708):
			size_ok = false
		if inst._mode_info_desc.get_theme_font_size("font_size") != 21:
			font_ok = false
		if inst._mode_info_title.get_theme_font_size("font_size") != 30:
			font_ok = false
		inst._on_mode_hover_end()
		if inst._mode_info.visible:
			bad.append("未选中时移出后窗口应隐藏（模式 %d）" % num)
	print("28个模式 内容非空=", desc_ok, " 尺寸一致=", size_ok, " 字体一致=", font_ok)
	if not desc_ok:
		bad.append("存在模式说明为空")
	if not size_ok:
		bad.append("窗口尺寸不一致")
	if not font_ok:
		bad.append("字体大小不一致")
	# 手写体：本机有华文行楷/楷体时，说明文字应使用手写体
	var hand_font: Font = inst._mode_info_desc.get_theme_font("font")
	print("手写体加载=", inst._hand_font != null, " 正文字体=手写体:", hand_font != null and hand_font == inst._hand_font)
	if inst._hand_font == null:
		bad.append("本机未找到手写体（华文行楷/楷体）")
	# 4) 窗口固定在右侧空白区
	inst._on_mode_hover(5)
	var wp: Vector2 = inst._mode_info.position
	print("窗口位置=", wp)
	if wp != Vector2(1276, 186):
		bad.append("窗口应固定在右侧空白区 (1276,186)")
	# 5) 选中模式后：说明固定在右侧显示；移出悬停仍显示选中模式
	inst._on_mode_selected(3)
	if not inst._mode_info.visible:
		bad.append("选中模式后应显示其说明")
	if inst._mode_info_title.text != "困难挑战模式":
		bad.append("选中后应显示选中模式的说明")
	inst._on_mode_hover_end()
	if not inst._mode_info.visible:
		bad.append("选中后移出悬停应仍显示选中模式说明")
	if inst._mode_info_title.text != "困难挑战模式":
		bad.append("移出后应显示选中模式而非其他")
	# 6) 不存在的编号（29）无说明：不显示窗口
	inst._on_mode_hover(29)
	if inst._mode_info.visible:
		bad.append("无说明的模式不应显示窗口")
	if bad.is_empty():
		print("=== MODE INFO TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== MODE INFO TEST FAILED: ", bad, " ===")
		get_tree().quit(1)
