extends Node
## 4 步设置向导测试：页面切换 + 地点扩展选择。

func _ready() -> void:
	var setup: PackedScene = load("res://src/ui/Setup.tscn")
	var inst: Control = setup.instantiate()
	add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	var s1: bool = inst._step_pages[1].visible
	print("初始 step1=", s1)
	# 模式图标网格：28 个按钮 + 名称白字
	var mode_count: int = inst._mode_buttons.size()
	print("模式按钮数=", mode_count)
	var gray_mat_ok: bool = inst._gray_mat != null
	print("灰度材质=", gray_mat_ok)
	# 默认未选择 → 全部彩色（无灰度材质）；选择后选中彩色、其余灰度
	var all_color_default: bool = true
	for num in inst._mode_buttons:
		var tr: TextureRect = inst._mode_buttons[num].get_child(0)
		if tr.material != null:
			all_color_default = false
	print("初始全彩色=", all_color_default)
	# 未选模式时确定按钮应禁用
	var next_disabled_init: bool = inst._nav_next.disabled
	print("未选模式时确定禁用=", next_disabled_init)
	inst._on_mode_selected(1)
	var next_disabled_after: bool = inst._nav_next.disabled
	print("选中模式后确定禁用=", next_disabled_after)
	var gray_ok: bool = true
	for num in inst._mode_buttons:
		var tr: TextureRect = inst._mode_buttons[num].get_child(0)
		var want: bool = num == 1
		if (tr.material == null) != want:
			gray_ok = false
	print("选中后其余灰度=", gray_ok)
	# 未上架模式：选择后点确定 → 弹窗提示；点返回关闭
	var nav_text_ok: bool = inst._nav_next.text == "确定"
	print("确定按钮文本=", inst._nav_next.text)
	inst._on_mode_selected(6)  # 6=无限战争模式（未上架）
	var modal_shown: bool = false
	inst._on_next()
	for i in range(5):
		await get_tree().process_frame
	modal_shown = inst._modal != null and inst._modal.visible
	print("未上架弹窗显示=", modal_shown)
	var still_step1: bool = inst._step_pages[1].visible and not inst._step_pages[2].visible
	print("弹窗时仍在第1步=", still_step1)
	inst._close_modal()
	for i in range(5):
		await get_tree().process_frame
	print("返回后弹窗关闭=", inst._modal == null)
	# 截图（headless 下无渲染缓冲，跳过）：设置页 1（模式图标网格，已选 1 基础模式）
	if DisplayServer.get_name() != "headless":
		var img1: Image = get_viewport().get_texture().get_image()
		if img1 != null:
			img1.save_png("F:/桌游相关/漫威联合/电子游戏/devtools/v49_modes.png")
	# 回到已上架模式 1，正常前进 2→3→4
	inst._on_mode_selected(1)
	inst._on_next()
	for i in range(5):
		await get_tree().process_frame
	var s2: bool = inst._step_pages[2].visible
	# 英雄页：初始无选中，需按顺位选择 3 名英雄后才能前进（点击顺序 = P1→P2→P3）
	inst._on_hero_toggle("cap")
	inst._on_hero_toggle("ironman")
	inst._on_hero_toggle("hulk")
	print("英雄顺位=", str(inst._selected_heroes))
	inst._on_next()
	for i in range(5):
		await get_tree().process_frame
	var s3: bool = inst._step_pages[3].visible
	print("反派页可见=", s3)
	# 反派页：基础模式需先选反派才能到地点页
	inst._on_villain_selected("redskull")
	inst._on_next()
	for i in range(5):
		await get_tree().process_frame
	var s4: bool = inst._step_pages[4].visible
	print("地点页可见=", s4)
	# 地点扩展：默认勾选基础盒；取消后再次勾选
	print("扩展选择=", str(inst._selected_expansions))
	inst._toggle_expansion(false, "基础盒")
	var after_uncheck: Array = inst._selected_expansions.duplicate()
	print("取消后=", str(after_uncheck))
	inst._toggle_expansion(true, "基础盒")
	print("重新勾选后=", str(inst._selected_expansions))
	if DisplayServer.get_name() != "headless":
		var img: Image = get_viewport().get_texture().get_image()
		if img != null:
			img.save_png("F:/桌游相关/漫威联合/电子游戏/devtools/v48_locations.png")
	var ok: bool = s1 and s2 and s3 and s4 and after_uncheck.size() == 0 and inst._selected_expansions.has("基础盒") \
		and mode_count == 28 and gray_mat_ok and all_color_default and gray_ok \
		and nav_text_ok and modal_shown and still_step1 and inst._modal == null \
		and next_disabled_init and not next_disabled_after
	if ok:
		print("=== 4STEP TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== 4STEP TEST FAILED ===")
		get_tree().quit(1)
