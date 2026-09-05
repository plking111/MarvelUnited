extends Control

var _settings_panel: PanelContainer
var _debug_check: CheckButton
var _peek_check: CheckButton
var _undo_check: CheckButton
var _fullscreen_btn: Button
var _rules_panel: PanelContainer
var _rules_list: VBoxContainer
var _rules_scroll: ScrollContainer
var _rules_data: Dictionary = {}
var _rule_view_panel: PanelContainer
var _rule_view_title: Label
var _rule_view_img: TextureRect
var _rule_view_page: Label
var _rule_view_prev: Button
var _rule_view_next: Button
var _rules_overlay: ColorRect
var _rules_tip: Label
var _rule_pages: Array = []
var _rule_page_idx: int = 0

func _ready() -> void:
	UiKit.preload_scene("res://src/ui/OnlinePrep.tscn")
	_build_menu()
	_build_settings_panel()
	_build_rules_ui()
	_load_rules_data()

func _load_rules_data() -> void:
	var f := FileAccess.open(DB._resolve_data_path("res://data/rules.json"), FileAccess.READ)
	if f != null:
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			_rules_data = parsed

func _build_menu() -> void:
	# 背景：主菜单图铺满（保持比例裁剪），标题已在图中
	var bg := TextureRect.new()
	bg.texture = load("res://assets/ui/cover.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var btn_path := "res://assets/ui/buttons/"
	# 按钮按素材比例 ~3.40:1（保留图案+外围黑色描边）等比例显示：宽 360 × 高 ~106
	# 四枚纵排居中，整体下移（中心 x≈960，上缘 y≈535）
	var bw := 360.0
	var bh := bw / 3.404
	var gap := 20.0
	var top := 535.0

	var start := UiKit.image_button("开始游戏", btn_path + "menu_1.png")
	start.position = Vector2((1920.0 - bw) / 2.0, top)
	start.custom_minimum_size = Vector2(bw, bh)
	start.size = Vector2(bw, bh)
	start.pressed.connect(func(): UiKit.goto_scene("res://src/ui/OnlinePrep.tscn"))
	add_child(start)
	UiKit.slide_in(start, 60, 0.0)

	var rules := UiKit.image_button("规则详情", btn_path + "menu_2.png")
	rules.position = Vector2((1920.0 - bw) / 2.0, top + (bh + gap))
	rules.custom_minimum_size = Vector2(bw, bh)
	rules.size = Vector2(bw, bh)
	rules.pressed.connect(_open_rules)
	add_child(rules)
	UiKit.slide_in(rules, 60, 0.06)

	var settings := UiKit.image_button("设置", btn_path + "menu_3.png")
	settings.position = Vector2((1920.0 - bw) / 2.0, top + (bh + gap) * 2)
	settings.custom_minimum_size = Vector2(bw, bh)
	settings.size = Vector2(bw, bh)
	settings.pressed.connect(_toggle_settings)
	add_child(settings)
	UiKit.slide_in(settings, 60, 0.12)

	var quit := UiKit.image_button("退出游戏", btn_path + "menu_4.png")
	quit.position = Vector2((1920.0 - bw) / 2.0, top + (bh + gap) * 3)
	quit.custom_minimum_size = Vector2(bw, bh)
	quit.size = Vector2(bw, bh)
	quit.pressed.connect(func(): get_tree().quit())
	add_child(quit)
	UiKit.slide_in(quit, 60, 0.18)

func _build_settings_panel() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	overlay.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_toggle_settings(false))
	add_child(overlay)
	_overlay = overlay

	_settings_panel = PanelContainer.new()
	_settings_panel.position = Vector2(710, 330)
	_settings_panel.custom_minimum_size = Vector2(500, 400)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.2, 0.97)
	sb.border_color = Color(0.5, 0.5, 0.7, 0.9)
	sb.set_border_width_all(2)
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	_settings_panel.add_theme_stylebox_override("panel", sb)
	_settings_panel.visible = false
	add_child(_settings_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_settings_panel.add_child(v)

	var title := Label.new()
	title.text = "设置"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	_fullscreen_btn = Button.new()
	_fullscreen_btn.text = "全屏 / 退出全屏（F11）"
	_fullscreen_btn.add_theme_font_size_override("font_size", 20)
	_fullscreen_btn.custom_minimum_size = Vector2(0, 48)
	_fullscreen_btn.pressed.connect(_toggle_fullscreen)
	v.add_child(_fullscreen_btn)

	_debug_check = CheckButton.new()
	_debug_check.text = "填满地点指示物（查看槽位位置）"
	_debug_check.add_theme_font_size_override("font_size", 18)
	_debug_check.button_pressed = Game.debug_full_slots
	_debug_check.toggled.connect(func(on: bool): Game.debug_full_slots = on)
	v.add_child(_debug_check)

	_peek_check = CheckButton.new()
	_peek_check.text = "查看其他英雄手牌（非官方功能）"
	_peek_check.add_theme_font_size_override("font_size", 18)
	_peek_check.button_pressed = Game.peek_hands
	_peek_check.toggled.connect(func(on: bool): Game.peek_hands = on)
	v.add_child(_peek_check)

	_undo_check = CheckButton.new()
	_undo_check.text = "启用撤回功能（非官方）"
	_undo_check.add_theme_font_size_override("font_size", 18)
	_undo_check.button_pressed = Game.undo_enabled
	_undo_check.toggled.connect(func(on: bool): Game.undo_enabled = on)
	v.add_child(_undo_check)

	var close := Button.new()
	close.text = "关闭"
	close.add_theme_font_size_override("font_size", 20)
	close.custom_minimum_size = Vector2(0, 44)
	close.pressed.connect(func(): _toggle_settings(false))
	v.add_child(close)

func _toggle_settings(show: bool = true) -> void:
	if show and _settings_panel.visible:
		show = false
	_settings_panel.visible = show
	_overlay.visible = show

func _mk_btn(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	b.add_theme_constant_override("outline_size", 3)
	b.custom_minimum_size = Vector2(260, 60)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = Color(0, 0, 0, 0.95)  # 黑色描边
	sb.set_border_width_all(3)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	b.add_theme_stylebox_override("normal", sb)
	# 按下/悬停保持黑边
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

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F11:
		_toggle_fullscreen()

func _toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

# ================================================================ 规则详情

func _build_rules_ui() -> void:
	# 遮罩（点击关闭）
	_rules_overlay = ColorRect.new()
	_rules_overlay.color = Color(0, 0, 0, 0.6)
	_rules_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rules_overlay.visible = false
	_rules_overlay.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_close_rules())
	add_child(_rules_overlay)

	# 规则书选择面板
	_rules_panel = PanelContainer.new()
	_rules_panel.position = Vector2(660, 140)
	_rules_panel.custom_minimum_size = Vector2(600, 720)
	_rules_panel.add_theme_stylebox_override("panel", _panel_style())
	_rules_panel.visible = false
	add_child(_rules_panel)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 12)
	_rules_panel.add_child(rv)
	var rt := Label.new()
	rt.text = "规则详情"
	rt.add_theme_font_size_override("font_size", 28)
	rt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(rt)
	_rules_scroll = ScrollContainer.new()
	_rules_scroll.custom_minimum_size = Vector2(560, 560)
	_rules_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(_rules_scroll)
	_rules_list = VBoxContainer.new()
	_rules_list.add_theme_constant_override("separation", 8)
	_rules_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rules_scroll.add_child(_rules_list)
	_rules_tip = Label.new()
	_rules_tip.text = ""
	_rules_tip.add_theme_font_size_override("font_size", 16)
	_rules_tip.add_theme_color_override("font_color", Color(1, 0.8, 0.4))
	_rules_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(_rules_tip)
	var rc := _mk_btn("关闭", Color(0.4, 0.4, 0.6))
	rc.custom_minimum_size = Vector2(200, 50)
	rc.position = Vector2(200, 0)
	rc.pressed.connect(_close_rules)
	var rc_row := HBoxContainer.new()
	rc_row.alignment = BoxContainer.ALIGNMENT_CENTER
	rc_row.add_child(rc)
	rv.add_child(rc_row)

	# 规则书页面查看面板（PDF 转图翻页显示）
	_rule_view_panel = PanelContainer.new()
	_rule_view_panel.position = Vector2(360, 60)
	_rule_view_panel.custom_minimum_size = Vector2(1200, 930)
	_rule_view_panel.add_theme_stylebox_override("panel", _panel_style())
	_rule_view_panel.visible = false
	add_child(_rule_view_panel)
	var vv := VBoxContainer.new()
	vv.add_theme_constant_override("separation", 8)
	_rule_view_panel.add_child(vv)
	_rule_view_title = Label.new()
	_rule_view_title.add_theme_font_size_override("font_size", 24)
	_rule_view_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vv.add_child(_rule_view_title)
	# 页面显示区（保持比例居中）
	var img_holder := Control.new()
	img_holder.custom_minimum_size = Vector2(1160, 780)
	vv.add_child(img_holder)
	_rule_view_img = TextureRect.new()
	_rule_view_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rule_view_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rule_view_img.set_anchors_preset(Control.PRESET_FULL_RECT)
	img_holder.add_child(_rule_view_img)
	# 翻页控制
	var page_row := HBoxContainer.new()
	page_row.alignment = BoxContainer.ALIGNMENT_CENTER
	page_row.add_theme_constant_override("separation", 30)
	vv.add_child(page_row)
	_rule_view_prev = _mk_btn("◀ 上一页", Color(0.4, 0.4, 0.6))
	_rule_view_prev.custom_minimum_size = Vector2(160, 46)
	_rule_view_prev.pressed.connect(_rule_prev_page)
	page_row.add_child(_rule_view_prev)
	_rule_view_page = Label.new()
	_rule_view_page.add_theme_font_size_override("font_size", 20)
	_rule_view_page.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	page_row.add_child(_rule_view_page)
	_rule_view_next = _mk_btn("下一页 ▶", Color(0.4, 0.4, 0.6))
	_rule_view_next.custom_minimum_size = Vector2(160, 46)
	_rule_view_next.pressed.connect(_rule_next_page)
	page_row.add_child(_rule_view_next)
	var back_row := HBoxContainer.new()
	back_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vv.add_child(back_row)
	var vc := _mk_btn("返回", Color(0.4, 0.4, 0.6))
	vc.custom_minimum_size = Vector2(200, 46)
	vc.pressed.connect(func(): _rule_view_panel.visible = false)
	back_row.add_child(vc)

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.2, 0.97)
	sb.border_color = Color(0.5, 0.5, 0.7, 0.9)
	sb.set_border_width_all(2)
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	return sb

func _open_rules() -> void:
	_rules_overlay.visible = true
	_rules_panel.visible = true
	_rules_tip.text = ""
	_render_rules_list()

func _render_rules_list() -> void:
	for c in _rules_list.get_children():
		_rules_list.remove_child(c)
		c.queue_free()
	var books: Array = _rules_data.get("books", [])
	for b in books:
		var name: String = b.get("name", "未知规则书")
		var avail: bool = b.get("available", false)
		var btn := _mk_btn(name, Color(0.3, 0.55, 0.35) if avail else Color(0.35, 0.35, 0.45))
		btn.custom_minimum_size = Vector2(0, 52)
		btn.add_theme_font_size_override("font_size", 20)
		var bid: String = b.get("id", "")
		if avail:
			btn.pressed.connect(_open_rule.bind(bid))
		else:
			btn.pressed.connect(func(): _rules_tip.text = "「%s」规则书尚未收录（目前仅收录基础版）" % name)
		_rules_list.add_child(btn)

func _open_rule(book_id: String) -> void:
	var books: Array = _rules_data.get("books", [])
	var title := "规则书"
	var pages: int = 0
	for b in books:
		if b.get("id", "") == book_id:
			title = b.get("name", "规则书")
			pages = int(b.get("pages", 0))
			break
	if pages <= 0:
		_rules_tip.text = "该规则书尚未收录（目前仅收录基础版 PDF）"
		return
	_rule_pages = []
	for i in range(pages):
		_rule_pages.append("res://assets/rules/%s_rules_%02d.jpg" % [book_id, i + 1])
	_rule_page_idx = 0
	_rule_view_title.text = title
	_show_rule_page()
	_rule_view_panel.visible = true

func _show_rule_page() -> void:
	if _rule_pages.size() == 0:
		return
	_rule_view_img.texture = load(_rule_pages[_rule_page_idx])
	_rule_view_page.text = "第 %d / %d 页" % [_rule_page_idx + 1, _rule_pages.size()]
	_rule_view_prev.disabled = _rule_page_idx == 0
	_rule_view_next.disabled = _rule_page_idx >= _rule_pages.size() - 1

func _rule_prev_page() -> void:
	if _rule_page_idx > 0:
		_rule_page_idx -= 1
		_show_rule_page()

func _rule_next_page() -> void:
	if _rule_page_idx < _rule_pages.size() - 1:
		_rule_page_idx += 1
		_show_rule_page()

func _close_rules() -> void:
	_rules_overlay.visible = false
	_rules_panel.visible = false
	_rule_view_panel.visible = false

var _overlay: ColorRect
