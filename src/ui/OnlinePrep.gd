extends Control
## 联机准备页：本地游戏进入设置向导；创建/加入房间为联机预留（未实现，禁用）。

func _ready() -> void:
	# 背景：与主菜单一致（cover 图铺满）
	var bg := TextureRect.new()
	bg.texture = load("res://assets/ui/cover.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "选择游戏方式"
	title.add_theme_font_size_override("font_size", 70)
	# 与主菜单按钮一致的卡通字体（方正舒体）+ 加粗黑描边
	var cf: Font = load("res://assets/fonts/FZShuTXSJF.ttf")
	if cf != null:
		title.add_theme_font_override("font", cf)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(660, 350)
	title.custom_minimum_size = Vector2(600, 80)
	add_child(title)

	var btn_path := "res://assets/ui/buttons/"
	# 等比例（~3.47:1，保留图案+外围黑色描边）宽 340 × 高 ~98，整体下移纵排居中
	var bw := 340.0
	var bh := bw / 3.472
	var gap := 20.0
	var top := 555.0

	# 创建房间（联机功能未实现，禁用）
	var create := UiKit.image_button("创建房间", btn_path + "online_1.png")
	create.position = Vector2((1920.0 - bw) / 2.0, top)
	create.custom_minimum_size = Vector2(bw, bh)
	create.size = Vector2(bw, bh)
	create.disabled = true
	add_child(create)
	UiKit.slide_in(create, 60, 0.0)
	# 加入房间（联机功能未实现，禁用）
	var join := UiKit.image_button("加入房间", btn_path + "online_2.png")
	join.position = Vector2((1920.0 - bw) / 2.0, top + (bh + gap))
	join.custom_minimum_size = Vector2(bw, bh)
	join.size = Vector2(bw, bh)
	join.disabled = true
	add_child(join)
	UiKit.slide_in(join, 60, 0.06)
	# 本地游戏
	var local := UiKit.image_button("本地游戏", btn_path + "online_3.png")
	local.position = Vector2((1920.0 - bw) / 2.0, top + (bh + gap) * 2)
	local.custom_minimum_size = Vector2(bw, bh)
	local.size = Vector2(bw, bh)
	local.pressed.connect(func(): UiKit.goto_scene("res://src/ui/Setup.tscn"))
	add_child(local)
	UiKit.slide_in(local, 60, 0.12)
	# 返回主菜单
	var back := UiKit.image_button("返回", btn_path + "online_4.png")
	back.position = Vector2((1920.0 - bw) / 2.0, top + (bh + gap) * 3)
	back.custom_minimum_size = Vector2(bw, bh)
	back.size = Vector2(bw, bh)
	back.pressed.connect(func(): UiKit.goto_scene("res://src/ui/MainMenu.tscn"))
	add_child(back)
	UiKit.slide_in(back, 60, 0.18)

func _mk_btn(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 62)
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	b.add_theme_constant_override("outline_size", 3)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = Color(0, 0, 0, 0.95)  # 黑色描边
	sb.set_border_width_all(3)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	b.add_theme_stylebox_override("normal", sb)
	# 悬停/按下保持黑边
	var sb_hover := StyleBoxFlat.new()
	sb_hover.bg_color = color.lightened(0.15)
	sb_hover.border_color = Color(0, 0, 0, 0.95)
	sb_hover.set_border_width_all(3)
	sb_hover.corner_radius_top_left = 10
	sb_hover.corner_radius_top_right = 10
	sb_hover.corner_radius_bottom_left = 10
	sb_hover.corner_radius_bottom_right = 10
	b.add_theme_stylebox_override("hover", sb_hover)
	var sb_pressed := StyleBoxFlat.new()
	sb_pressed.bg_color = color.darkened(0.2)
	sb_pressed.border_color = Color(0, 0, 0, 0.95)
	sb_pressed.set_border_width_all(3)
	sb_pressed.corner_radius_top_left = 10
	sb_pressed.corner_radius_top_right = 10
	sb_pressed.corner_radius_bottom_left = 10
	sb_pressed.corner_radius_bottom_right = 10
	b.add_theme_stylebox_override("pressed", sb_pressed)
	UiKit.attach_jelly(b)
	return b
