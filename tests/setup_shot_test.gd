extends Node
## v2.9 界面截图：准备阶段、任务指示物、英雄切换、图标排布、手牌选择面板。

var _picked_test: Array = []

func _ready() -> void:
	Game.pending_setup = {"villain": "redskull", "heroes": ["cap", "ironman", "hulk"], "challenge": "none", "peek_hands": true}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(14):
		await get_tree().process_frame
	print("威胁图标加载: ", inst._icon_threat != null, " 尺寸=", (inst._icon_threat.get_width() if inst._icon_threat != null else -1))
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("F:/桌游相关/漫威联合/电子游戏/devtools/v31_setup.png")
	# 全暗基线（tokens=0）
	var img_dark: Image = get_viewport().get_texture().get_image()
	img_dark.save_png("F:/桌游相关/漫威联合/电子游戏/devtools/v31_missions_dark.png")
	# 模拟任务进度（营救3/击败2/清除1），验证指示物点亮
	var ms: Array = Game.state["missions"]
	ms[0]["tokens"] = 3
	ms[1]["tokens"] = 2
	ms[2]["tokens"] = 1
	inst._refresh_missions()
	for i in range(6):
		await get_tree().process_frame
	var img2: Image = get_viewport().get_texture().get_image()
	img2.save_png("F:/桌游相关/漫威联合/电子游戏/devtools/v31_missions.png")
	# 英雄手牌切换预览（peek_hands 开启时按钮应可见）
	print("peek按钮可见: ", inst._peek_prev.visible, "/", inst._peek_next.visible)
	inst._on_peek_next()
	for i in range(6):
		await get_tree().process_frame
	var img3: Image = get_viewport().get_texture().get_image()
	img3.save_png("F:/桌游相关/漫威联合/电子游戏/devtools/v31_peek.png")
	print("预览后 label: ", inst._hand_label.text)
	print("开始按钮位置: ", inst._start_button.position, " 可见=", inst._start_button.visible)
	# 验证多图标同地点不重叠：3 英雄 + 反派放同一地点
	var st: Dictionary = Game.state
	var target := 0
	st["villain_pos"] = target
	for hid in st["hero_ids"]:
		st["heroes"][hid]["location"] = target
	inst._refresh_hero_badges()
	for i in range(6):
		await get_tree().process_frame
	var img4: Image = get_viewport().get_texture().get_image()
	img4.save_png("F:/桌游相关/漫威联合/电子游戏/devtools/v32_icons.png")
	var rects := []
	for n in inst._icon_nodes:
		rects.append(Rect2(n.position, n.size))
	var overlap := false
	var out_of_screen := false
	for a in range(rects.size()):
		var r: Rect2 = rects[a]
		if r.position.y < 0.0 or r.end.y > 1080.0 or r.position.x < 0.0 or r.end.x > 1920.0:
			out_of_screen = true
		for b in range(a + 1, rects.size()):
			if r.intersects(rects[b]):
				overlap = true
	print("同地点图标数量=", rects.size(), " 重叠=", overlap, " 超屏=", out_of_screen)
	var img4b: Image = get_viewport().get_texture().get_image()
	img4b.save_png("F:/桌游相关/漫威联合/电子游戏/devtools/v34_icons.png")
	# 手牌选择面板测试（受伤弃牌等）——弹窗现由 PopupLayer 模块管理
	var cb := func(arr: Array) -> void: _picked_test = arr
	inst._popup.show_hand_pick(cb, "测试：选择要弃掉的 2 张手牌", "cap", 2)
	for i in range(6):
		await get_tree().process_frame
	var img5: Image = get_viewport().get_texture().get_image()
	img5.save_png("F:/桌游相关/漫威联合/电子游戏/devtools/v33_handpick.png")
	print("手牌面板可见=", inst._popup.hand_pick_panel.visible, " 确认禁用(未选)=", inst._popup.hand_pick_confirm.disabled)
	inst._popup.hand_pick_selected = [0, 1]
	inst._popup.render_hand_pick()
	print("确认禁用(选2)=", inst._popup.hand_pick_confirm.disabled)
	inst._popup.confirm_hand_pick()
	print("回调收到=", str(_picked_test), " 面板可见=", inst._popup.hand_pick_panel.visible)
	# 弹窗层级验证：弹窗在独立 CanvasLayer(100) 中，永远在主界面（含角色图标）之上
	var in_layer: bool = inst._popup is CanvasLayer and inst._popup.layer >= 100
	print("弹窗层=CanvasLayer(100): ", in_layer, " 面板父节点是弹窗层: ", inst._popup.hand_pick_panel.get_parent() == inst._popup)
	# 行动按钮区：每个行动按钮带对应图标 + 手牌区右侧指示物数量
	Game.state["phase"] = "hero_actions"
	Game.state["action_symbols"] = ["move", "attack"]
	inst._refresh_actions()
	var btn_icon_count := 0
	var icon_names := []
	for c in inst._action_box.get_children():
		if c is Button and c.icon != null:
			btn_icon_count += 1
			icon_names.append(c.text)
	inst._refresh_hand()
	var token_count: int = inst._token_info_box.get_child_count()
	print("带图标的行动按钮数=", btn_icon_count, " 按钮=", str(icon_names), " 手牌指示物数量组=", token_count)
	get_tree().quit(0)
