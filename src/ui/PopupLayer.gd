class_name PopupLayer
extends CanvasLayer
## 弹窗层模块：独立 CanvasLayer（layer=100），永远绘制在主界面之上，
## 主界面动态重建的角色图标/卡片永远不会遮挡任何弹窗（修复"弹窗被地图英雄图标覆盖"）。
##
## 集中管理全部对话框：
##  - 选择框（prompt_choice）
##  - 确认框（prompt_confirm）
##  - 手牌选择（prompt_hand_card，可多选）
##  - 故事情节选卡（prompt_story_card）
##  - 牌库选牌（prompt_deck_card）
##  - 反派行动牌确认（prompt_villain_card，黑寡妇审讯）
##  - 信息弹窗（地点详情等）
##  - Toast 提示
##  - 游戏结算覆盖层（game_over）

var prompt_panel: PanelContainer
var prompt_label: Label
var prompt_buttons: HBoxContainer
var _prompt_callback: Callable

var confirm_panel: PanelContainer
var confirm_label: Label
var _confirm_callback: Callable

var hand_pick_panel: PanelContainer
var hand_pick_label: Label
var hand_pick_box: HBoxContainer
var hand_pick_confirm: Button
var hand_pick_selected: Array = []
var _hand_pick_callback: Callable
var _hand_pick_hero: String = ""
var hand_pick_count: int = 1
var _hand_pick_title := ""

var story_pick_panel: PanelContainer
var story_pick_label: Label
var story_pick_box: FlowContainer
var story_pick_btns: HBoxContainer
var _story_pick_callback: Callable
var _villain_card_callback: Callable = Callable()

# 英雄选择（灭霸替换英雄）
var hero_pick_panel: PanelContainer
var hero_pick_label: Label
var hero_pick_box: FlowContainer
var hero_pick_search: LineEdit
var hero_pick_sort_alpha: Button
var hero_pick_sort_exp: Button
var _hero_pick_callback: Callable = Callable()
var _hero_pick_options: Array = []
var _hero_pick_sort: String = "alpha"

var info_panel: PanelContainer
var _info_text: RichTextLabel

var toast_label: Label

var overlay: ColorRect
var overlay_label: Label
var overlay_sub: Label
var overlay_button: Button
var overlay_icon: HBoxContainer   # 结算：胜利=所有英雄图标，失败=反派图标

var _hand_pick_block: ColorRect
var mission_panel: PanelContainer
var mission_icon: TextureRect
var mission_title: Label
var mission_sub: Label
var mission_block: ColorRect

# 弹窗内英雄牌悬停放大（独立 CanvasLayer，层号 > 弹窗自身，永远盖在弹窗之上）
var _zoom_layer: CanvasLayer
var _zoom_panel: TextureRect
var _zoom_host: Control = null          # 当前触发放大的宿主控件（用于自愈判定）
var _zoom_mouse_override := Vector2.INF # 测试用：固定鼠标位置（Vector2.INF = 用真实鼠标）

func _init() -> void:
	layer = 100
	_build()

func _build() -> void:
	# ---- 选择框 ----
	prompt_panel = PanelContainer.new()
	prompt_panel.position = Vector2(560, 320)
	prompt_panel.custom_minimum_size = Vector2(800, 200)
	prompt_panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(0.12, 0.12, 0.2, 0.97)))
	prompt_panel.visible = false
	add_child(prompt_panel)
	var pv := VBoxContainer.new()
	prompt_panel.add_child(pv)
	prompt_label = UiKit.label("", 22, Color.WHITE)
	pv.add_child(prompt_label)
	prompt_buttons = HBoxContainer.new()
	prompt_buttons.add_theme_constant_override("separation", 10)
	prompt_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_child(prompt_buttons)

	# ---- 确认框 ----
	confirm_panel = PanelContainer.new()
	confirm_panel.position = Vector2(560, 340)
	confirm_panel.custom_minimum_size = Vector2(800, 160)
	confirm_panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(0.12, 0.12, 0.2, 0.97)))
	confirm_panel.visible = false
	add_child(confirm_panel)
	var cv := VBoxContainer.new()
	confirm_panel.add_child(cv)
	confirm_label = UiKit.label("", 22, Color.WHITE)
	cv.add_child(confirm_label)
	var cb := HBoxContainer.new()
	cb.alignment = BoxContainer.ALIGNMENT_CENTER
	cb.add_theme_constant_override("separation", 20)
	cv.add_child(cb)
	var ok := UiKit.button("确认", Color(0.3, 0.7, 0.3))
	ok.pressed.connect(func(): confirm_panel.visible = false; if _confirm_callback.is_valid(): _confirm_callback.call(true))
	cb.add_child(ok)
	var no := UiKit.button("取消", Color(0.7, 0.3, 0.3))
	no.pressed.connect(func(): confirm_panel.visible = false; if _confirm_callback.is_valid(): _confirm_callback.call(false))
	cb.add_child(no)

	# ---- 手牌选择面板（受伤弃牌 / 地点效果弃牌 / 交换手牌等）----
	hand_pick_panel = PanelContainer.new()
	hand_pick_panel.position = Vector2(560, 280)
	hand_pick_panel.custom_minimum_size = Vector2(800, 280)
	hand_pick_panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(0.12, 0.12, 0.2, 0.97)))
	hand_pick_panel.visible = false
	# 模态拦截层：铺满、在最下层（面板之下），挡住对棋盘的点击，防止误触发抽牌/出牌
	_hand_pick_block = ColorRect.new()
	_hand_pick_block.color = Color(0, 0, 0, 0.4)
	_hand_pick_block.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hand_pick_block.mouse_filter = Control.MOUSE_FILTER_STOP
	_hand_pick_block.visible = false
	add_child(_hand_pick_block)
	add_child(hand_pick_panel)
	var hpv := VBoxContainer.new()
	hpv.add_theme_constant_override("separation", 10)
	hand_pick_panel.add_child(hpv)
	hand_pick_label = UiKit.label("", 19, Color.WHITE)
	hand_pick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hpv.add_child(hand_pick_label)
	hand_pick_box = HBoxContainer.new()
	hand_pick_box.add_theme_constant_override("separation", 8)
	hand_pick_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hpv.add_child(hand_pick_box)
	var hpb := HBoxContainer.new()
	hpb.alignment = BoxContainer.ALIGNMENT_CENTER
	hpb.add_theme_constant_override("separation", 20)
	hpv.add_child(hpb)
	hand_pick_confirm = UiKit.button("确认弃牌", Color(0.3, 0.7, 0.3))
	hand_pick_confirm.pressed.connect(confirm_hand_pick)
	hpb.add_child(hand_pick_confirm)
	# 说明：弃牌为强制操作，无"取消"按钮

	# ---- 故事卡选择面板（故事情节交换用：卡牌图标 + 自动换行；复用为牌库选牌/反派卡确认）----
	story_pick_panel = PanelContainer.new()
	story_pick_panel.position = Vector2(560, 240)
	story_pick_panel.custom_minimum_size = Vector2(820, 380)
	story_pick_panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(0.12, 0.12, 0.2, 0.97)))
	story_pick_panel.visible = false
	add_child(story_pick_panel)
	var spv := VBoxContainer.new()
	spv.add_theme_constant_override("separation", 10)
	story_pick_panel.add_child(spv)
	story_pick_label = UiKit.label("", 19, Color.WHITE)
	story_pick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spv.add_child(story_pick_label)
	var sp_scroll := ScrollContainer.new()
	sp_scroll.custom_minimum_size = Vector2(780, 300)
	sp_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sp_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	spv.add_child(sp_scroll)
	story_pick_box = FlowContainer.new()
	story_pick_box.add_theme_constant_override("h_separation", 6)
	story_pick_box.add_theme_constant_override("v_separation", 6)
	story_pick_box.custom_minimum_size = Vector2(780, 0)
	sp_scroll.add_child(story_pick_box)
	var spb := HBoxContainer.new()
	spb.alignment = BoxContainer.ALIGNMENT_CENTER
	spv.add_child(spb)
	story_pick_btns = spb
	var sp_close := UiKit.button("关闭", Color(0.4, 0.4, 0.6))
	sp_close.pressed.connect(func(): story_pick_panel.visible = false; if _story_pick_callback.is_valid():
		var cb2 := _story_pick_callback
		_story_pick_callback = Callable()
		cb2.call(-1))
	spb.add_child(sp_close)

	# ---- 英雄选择面板（灭霸淘汰→替换英雄：可搜索/按首字母/按扩展筛选）----
	hero_pick_panel = PanelContainer.new()
	hero_pick_panel.position = Vector2(560, 180)
	hero_pick_panel.custom_minimum_size = Vector2(820, 520)
	hero_pick_panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(0.12, 0.12, 0.2, 0.97)))
	hero_pick_panel.visible = false
	add_child(hero_pick_panel)
	var hero_pv := VBoxContainer.new()
	hero_pv.add_theme_constant_override("separation", 8)
	hero_pick_panel.add_child(hero_pv)
	hero_pick_label = UiKit.label("", 20, Color.WHITE)
	hero_pick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_pv.add_child(hero_pick_label)
	# 搜索框
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_pv.add_child(srow)
	var sl := UiKit.label("搜索:", 18, Color(0.8, 0.8, 0.9))
	srow.add_child(sl)
	hero_pick_search = LineEdit.new()
	hero_pick_search.custom_minimum_size = Vector2(240, 34)
	hero_pick_search.placeholder_text = "按名字搜索英雄…"
	hero_pick_search.text_changed.connect(_on_hero_search_changed)
	srow.add_child(hero_pick_search)
	# 排序切换：按首字母 / 按扩展
	hero_pick_sort_alpha = UiKit.button("按首字母", Color(0.3, 0.4, 0.7))
	hero_pick_sort_alpha.pressed.connect(_on_hero_sort.bind("alpha"))
	srow.add_child(hero_pick_sort_alpha)
	hero_pick_sort_exp = UiKit.button("按扩展", Color(0.3, 0.4, 0.7))
	hero_pick_sort_exp.pressed.connect(_on_hero_sort.bind("expansion"))
	srow.add_child(hero_pick_sort_exp)
	# 英雄滚动区
	var hp_scroll := ScrollContainer.new()
	hp_scroll.custom_minimum_size = Vector2(790, 360)
	hp_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hp_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	hero_pv.add_child(hp_scroll)
	hero_pick_box = FlowContainer.new()
	hero_pick_box.add_theme_constant_override("h_separation", 10)
	hero_pick_box.add_theme_constant_override("v_separation", 10)
	hero_pick_box.custom_minimum_size = Vector2(790, 0)
	hp_scroll.add_child(hero_pick_box)
	# 底部：取消
	var hpb2 := HBoxContainer.new()
	hpb2.alignment = BoxContainer.ALIGNMENT_CENTER
	hpb2.add_theme_constant_override("separation", 20)
	hero_pv.add_child(hpb2)
	var hp_cancel := UiKit.button("取消", Color(0.4, 0.4, 0.6))
	hp_cancel.pressed.connect(cancel_hero_pick)
	hpb2.add_child(hp_cancel)

	# ---- Toast ----
	toast_label = UiKit.label("", 20, Color(1, 0.9, 0.5))
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.position = Vector2(560, 560)
	toast_label.size = Vector2(800, 40)
	add_child(toast_label)
	toast_label.modulate.a = 0.0

	# ---- 结算覆盖层 ----
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	add_child(overlay)
	# 居中排布：用一个中心锚定的 VBox 容纳 图标/标题/副标题/按钮
	var ov_center := VBoxContainer.new()
	ov_center.anchor_left = 0.5
	ov_center.anchor_right = 0.5
	ov_center.anchor_top = 0.5
	ov_center.anchor_bottom = 0.5
	ov_center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ov_center.grow_vertical = Control.GROW_DIRECTION_BOTH
	ov_center.alignment = BoxContainer.ALIGNMENT_CENTER
	ov_center.add_theme_constant_override("separation", 16)
	overlay.add_child(ov_center)
	overlay_icon = HBoxContainer.new()
	overlay_icon.add_theme_constant_override("separation", 10)
	overlay_icon.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ov_center.add_child(overlay_icon)
	overlay_label = UiKit.label("", 60, Color.WHITE)
	overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ov_center.add_child(overlay_label)
	overlay_sub = UiKit.label("", 26, Color(0.9, 0.9, 0.9))
	overlay_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ov_center.add_child(overlay_sub)
	overlay_button = UiKit.button("返回主菜单", Color(0.3, 0.5, 0.8))
	overlay_button.custom_minimum_size = Vector2(200, 48)
	overlay_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	overlay_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ov_center.add_child(overlay_button)
	# 连接在 show_game_over 时动态绑定（返回主菜单 / 进入下一局）

	# ---- 信息弹窗（点击地点查看详情）----
	info_panel = PanelContainer.new()
	info_panel.position = Vector2(610, 300)
	info_panel.custom_minimum_size = Vector2(700, 260)
	info_panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(0.12, 0.12, 0.2, 0.97)))
	info_panel.visible = false
	add_child(info_panel)
	var iv := VBoxContainer.new()
	info_panel.add_child(iv)
	_info_text = RichTextLabel.new()
	_info_text.bbcode_enabled = false
	_info_text.add_theme_font_size_override("normal_font_size", 19)
	_info_text.fit_content = true
	iv.add_child(_info_text)
	var ib := HBoxContainer.new()
	ib.alignment = BoxContainer.ALIGNMENT_CENTER
	iv.add_child(ib)
	var close_btn := UiKit.button("关闭", Color(0.4, 0.4, 0.6))
	close_btn.pressed.connect(func(): info_panel.visible = false)
	ib.add_child(close_btn)

	# ---- 任务完成提示弹窗（布满全屏；卡背图标 + 大标题 + 副标题居中；方舒体黑边；由小变大弹出）----
	# 全屏半透明遮罩：拦截点击，点任意位置关闭
	mission_block = ColorRect.new()
	mission_block.color = Color(0.02, 0.02, 0.05, 0.85)
	mission_block.set_anchors_preset(Control.PRESET_FULL_RECT)
	mission_block.mouse_filter = Control.MOUSE_FILTER_STOP
	mission_block.visible = false
	add_child(mission_block)
	# 内容面板（铺满遮罩，便于居中）
	mission_panel = PanelContainer.new()
	mission_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	mission_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mission_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	mission_panel.visible = false
	mission_block.add_child(mission_panel)
	var mv := VBoxContainer.new()
	mv.alignment = BoxContainer.ALIGNMENT_CENTER
	mv.add_theme_constant_override("separation", 22)
	mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mission_panel.add_child(mv)
	# 卡背图标（居中）
	var icon_holder := CenterContainer.new()
	mv.add_child(icon_holder)
	mission_icon = TextureRect.new()
	mission_icon.custom_minimum_size = Vector2(260, 364)
	mission_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mission_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_holder.add_child(mission_icon)
	# 大字标题（方舒体+黑描边；居中；大字号）
	mission_title = Label.new()
	mission_title.add_theme_font_size_override("font_size", 78)
	mission_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mission_title.add_theme_color_override("font_color", Color.WHITE)
	mission_title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	mission_title.add_theme_constant_override("outline_size", 22)
	var mf: Font = load("res://assets/fonts/FZShuTXSJF.ttf")
	if mf != null:
		mission_title.add_theme_font_override("font", mf)
	mv.add_child(mission_title)
	# 副标题（方舒体+黑描边；居中；大字号）
	mission_sub = Label.new()
	mission_sub.add_theme_font_size_override("font_size", 36)
	mission_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mission_sub.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	mission_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	mission_sub.add_theme_constant_override("outline_size", 12)
	if mf != null:
		mission_sub.add_theme_font_override("font", mf)
	mv.add_child(mission_sub)
	# 提示语（点击任意位置继续）
	var mhint := Label.new()
	mhint.text = "点击任意位置继续"
	mhint.add_theme_font_size_override("font_size", 24)
	mhint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mhint.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	mhint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	mhint.add_theme_constant_override("outline_size", 6)
	mv.add_child(mhint)
	# 点击任意位置关闭
	mission_block.gui_input.connect(_on_mission_block_input)

	# ---- 英雄牌悬停放大图层（必须最后添加 + 层号高于本层，否则会被弹窗遮住）----
	_zoom_layer = CanvasLayer.new()
	_zoom_layer.layer = layer + 10
	add_child(_zoom_layer)
	_zoom_panel = TextureRect.new()
	_zoom_panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_zoom_panel.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_zoom_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 不能挡住点击
	_zoom_panel.visible = false
	_zoom_layer.add_child(_zoom_panel)

# ================================================================ 联机：只读弹窗 / 关闭

## 只读模式：联机时"不是本人在操作"的弹窗，只展示、**点不动**（用户要求：
## 非本人操作的弹窗别人不能按；以前是能按但没反应，体验很差）。
var readonly := false

func set_readonly(on: bool) -> void:
	readonly = on

func _ro_title(t: String) -> String:
	return t if not readonly else t + "　（等待其他玩家选择…）"

## 关闭所有"等待玩家选择"的弹窗（联机时主机那边已经有人答完 → 其他人跟着收起）
func hide_all_prompts() -> void:
	if is_instance_valid(_action_root):
		_action_root.queue_free()
		_action_root = null
	_action_callback = Callable()
	if is_instance_valid(_reorder_root):
		_reorder_root.queue_free()
		_reorder_root = null
	_reorder_callback = Callable()
	_reorder_slots.clear()
	_reorder_ghost = null
	_reorder_drag = -1
	_reorder_hover = -1
	prompt_panel.visible = false
	confirm_panel.visible = false
	hand_pick_panel.visible = false
	if is_instance_valid(_hand_pick_block):
		_hand_pick_block.visible = false
	story_pick_panel.visible = false
	hero_pick_panel.visible = false
	hide_card_zoom()

# ================================================================ 选择/确认

func show_prompt(options: Array, title: String, callback: Callable) -> void:
	_prompt_callback = callback
	prompt_label.text = _ro_title(title)
	_clear_children(prompt_buttons)
	for i in range(options.size()):
		var btn := UiKit.button(str(options[i]), Color(0.3, 0.4, 0.7))
		btn.pressed.connect(_on_prompt_pick.bind(i))
		btn.disabled = readonly
		prompt_buttons.add_child(btn)
	prompt_panel.visible = true

func _on_prompt_pick(idx: int) -> void:
	prompt_panel.visible = false
	var cb := _prompt_callback
	_prompt_callback = Callable()
	if cb.is_valid():
		cb.call(idx)

# ================================================================ 行动图形化选择（移动/攻击/英勇）

var _action_root: Control = null
var _action_callback: Callable = Callable()

## rows 每项：
##   {icon:"move|attack|heroic|wild|civ|thug|" (左图标), arrow:"move|attack|heroic|" (箭头颜色),
##    text:"目标文字", img:"资源路径"(右侧目标小图,可选), bottom:"资源路径"(按钮下方底部小图,可选)}
## 纯文字行可只给 text。
func show_action_prompt(rows: Array, title: String, callback: Callable) -> void:
	_action_callback = callback
	if is_instance_valid(_action_root):
		_action_root.queue_free()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	_action_root = root
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	# 用 CenterContainer 自动居中；上下 offset 各 -25 让整体上移 25px（高度不变）
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_top = -25
	center.offset_bottom = -25
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(0.12, 0.12, 0.2, 0.97)))
	center.add_child(panel)
	# 四周留白（整体缩小）
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 16)
	margin.add_child(outer)
	var t := UiKit.label(_ro_title(title), 28, Color(1, 0.92, 0.7))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(t)
	# 行按钮用 HFlowContainer：自动换行（选项多时折行，不再超出屏幕）；居中
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 14)
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.size_flags_horizontal = Control.SIZE_FILL
	# 估算单行宽度，限制面板最大宽度 → 超出就自动折行
	var est := 0.0
	for r in rows:
		var rw := 170.0
		if r.get("icon", "") != "": rw += 52.0
		if r.get("arrow", "") != "": rw += 40.0
		if r.get("img", "") != "": rw += 60.0
		if r.get("text", "") != "" and not r.get("hide_text", false): rw += 200.0
		if r.get("bottom", "") != "": rw += 88.0
		est += rw + 14.0
	est = maxf(est, 320.0)
	flow.custom_minimum_size.x = minf(est, 1150.0)
	outer.add_child(flow)
	for i in range(rows.size()):
		var r: Dictionary = rows[i]
		var row := _make_action_row(r, i)
		flow.add_child(row)

func _make_action_row(r: Dictionary, idx: int) -> Control:
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", UiKit.panel_style(Color(0.22, 0.24, 0.34, 0.95)))
	# 行内留白（整体缩小）
	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 20)
	inner.add_theme_constant_override("margin_right", 20)
	inner.add_theme_constant_override("margin_top", 12)
	inner.add_theme_constant_override("margin_bottom", 12)
	holder.add_child(inner)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	inner.add_child(box)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(line)
	# 左：行动图标
	var icon: String = r.get("icon", "")
	if icon != "":
		var path := _token_icon_path(icon)
		if path != "":
			var ic := TextureRect.new()
			ic.texture = load(path)
			ic.custom_minimum_size = Vector2(54, 54)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.add_child(ic)
	# 箭头（彩色）
	var arrow: String = r.get("arrow", "")
	if arrow != "":
		var a_color := Color(0.5, 1, 0.5) if arrow == "move" else (Color(1, 0.55, 0.5) if arrow == "attack" else Color(1, 0.85, 0.4))
		var al := UiKit.label("➤", 40, a_color)
		al.add_theme_constant_override("outline_size", 3)
		al.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		line.add_child(al)
	# 文字
	var text: String = r.get("text", "")
	# hide_text=true 时 UI 不显示文字（纯图标行，如"攻击暴徒"），text 仍保留供逻辑匹配
	if text != "" and not r.get("hide_text", false):
		var lb := UiKit.label(text, 26, Color.WHITE)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if r.get("icon", "") == "" and r.get("img", "") == "" and r.get("arrow", "") == "":
			lb.custom_minimum_size = Vector2(0, 0)
		else:
			lb.custom_minimum_size = Vector2(200, 0)
		lb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		line.add_child(lb)
	# 右侧目标图（威胁卡/平民/暴徒等）：统一尺寸、保持比例、居中；威胁卡转横
	var img: String = r.get("img", "")
	if img != "":
		var tex: Texture2D = load(img)
		if r.get("card", "") == "threat":
			tex = _card_tex_landscape(tex, true)
		elif r.get("rot", "") == "cw":
			tex = _rotate_texture(tex, CLOCKWISE)
		elif r.get("rot", "") == "ccw":
			tex = _rotate_texture(tex, COUNTERCLOCKWISE)
		var im := TextureRect.new()
		im.texture = tex
		im.custom_minimum_size = Vector2(60, 60)
		im.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		im.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		im.mouse_filter = Control.MOUSE_FILTER_IGNORE
		im.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		im.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(im)
		# 英雄牌（含英雄卡背）：整行悬停即放大，不用精确指到 60px 小图
		bind_card_zoom(holder, img)
	# 底部小图（整行下方，如地点缩略/威胁背面）
	var bottom: String = r.get("bottom", "")
	if bottom != "":
		var bm := TextureRect.new()
		bm.texture = load(bottom)
		bm.custom_minimum_size = Vector2(188, 106)
		bm.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bm.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		bm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 注意：TextureRect 没有 alignment 属性（Godot 4）。曾误写 bm.alignment = BoxContainer.ALIGNMENT_CENTER，
		# 该语句报错会中断整个 _make_action_row → 返回 null → add_child(null) → 该行从弹窗里消失
		# （所有"选目的地"的行都带 bottom，会导致选项全部不见）。纹理居中已由 stretch_mode 完成。
		box.add_child(bm)
		bm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.gui_input.connect(func(ev: InputEvent):
		if not readonly and ev is InputEventMouseButton and ev.pressed:
			if is_instance_valid(_action_root):
				_action_root.queue_free()
				_action_root = null
			var cb := _action_callback
			_action_callback = Callable()
			if cb.is_valid():
				cb.call(idx))
	if readonly:
		# 只读：整行不可点，并压暗，明确"这一行现在不归你点"
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.modulate = Color(0.72, 0.72, 0.78)
	# 悬停果冻放大（pivot 居中，放大 + 轻微回弹）
	holder.pivot_offset = holder.size * 0.5
	holder.resized.connect(func():
		if is_instance_valid(holder):
			holder.pivot_offset = holder.size * 0.5)
	var row_hover: Tween = null
	holder.mouse_entered.connect(func():
		if is_instance_valid(row_hover):
			row_hover.kill()
		row_hover = create_tween()
		holder.pivot_offset = holder.size * 0.5
		row_hover.tween_property(holder, "scale", Vector2(1.14, 1.14), 0.10)
		row_hover.tween_property(holder, "scale", Vector2(1.1, 1.1), 0.06))
	holder.mouse_exited.connect(func():
		if is_instance_valid(row_hover):
			row_hover.kill()
		row_hover = create_tween()
		row_hover.tween_property(holder, "scale", Vector2.ONE, 0.12))
	return holder

# ================================================================ 英雄牌悬停放大

## 悬停放大尺寸：英雄牌统一放大到 620px 高（853×1198 → 约 441×620，卡面文字可读）
const ZOOM_MAX_H := 620.0

## 让弹窗里的英雄牌图片支持"鼠标悬停 → 在光标旁放大显示"。
## host：接收鼠标的控件（整行/整张卡都行，比要求精确命中 60px 小图友好得多）；
## img_path：卡图资源路径。只有英雄牌（res://assets/cards/heroes/…）才绑定，其余（威胁卡/地点/指示物）忽略。
func bind_card_zoom(host: Control, img_path: String) -> void:
	if host == null or not String(img_path).begins_with("res://assets/cards/heroes/"):
		return
	host.mouse_entered.connect(func() -> void: show_card_zoom(host, img_path))
	host.mouse_exited.connect(hide_card_zoom)

## 立刻放大显示某张卡（也可由测试直接调用）
func show_card_zoom(host: Control, img_path: String) -> void:
	var tex: Texture2D = load(img_path)
	if tex == null or _zoom_panel == null:
		return
	_zoom_host = host
	_zoom_panel.texture = tex
	var tw: float = maxf(float(tex.get_width()), 1.0)
	var th: float = maxf(float(tex.get_height()), 1.0)
	# 不放大超过原始像素（小图不会被拉糊），大图按高度上限等比缩放
	var f: float = minf(ZOOM_MAX_H / th, 1.0)
	var zs := Vector2(tw * f, th * f)
	_zoom_panel.custom_minimum_size = zs
	_zoom_panel.size = zs
	_zoom_panel.visible = true
	_update_zoom_position()

func hide_card_zoom() -> void:
	_zoom_host = null
	if _zoom_panel != null:
		_zoom_panel.visible = false
		_zoom_panel.texture = null

func _zoom_mouse_pos() -> Vector2:
	if _zoom_mouse_override != Vector2.INF:
		return _zoom_mouse_override
	return _zoom_panel.get_global_mouse_position()

## 放大图位置：鼠标右下方 +24；贴边自动翻到左侧/上侧（与 Board 的卡牌放大同一口径）
func _update_zoom_position() -> void:
	var zw: float = _zoom_panel.size.x
	var zh: float = _zoom_panel.size.y
	var mpos: Vector2 = _zoom_mouse_pos()
	var p := mpos + Vector2(24, 24)
	if p.x + zw > 1920.0:
		p.x = mpos.x - zw - 48
		if p.x < 0.0:
			p.x = maxf(0.0, 1920.0 - zw)
	if p.y + zh > 1080.0:
		p.y = mpos.y - zh - 48
		if p.y < 0.0:
			p.y = maxf(0.0, 1080.0 - zh)
	_zoom_panel.position = p

## 每帧跟随鼠标；并做"自愈"：宿主被释放/隐藏，或鼠标已不在宿主上
## （典型情况：点了卡片 → 弹窗立即关闭，mouse_exited 不一定触发）→ 立刻收起放大图，避免留下残影。
func _process(_delta: float) -> void:
	if _zoom_panel == null or not _zoom_panel.visible:
		return
	if not is_instance_valid(_zoom_host) or not _zoom_host.is_visible_in_tree() \
			or not _zoom_host.get_global_rect().has_point(_zoom_mouse_pos()):
		hide_card_zoom()
		return
	_update_zoom_position()

func _token_icon_path(icon: String) -> String:
	match icon:
		"move": return "res://assets/tokens/token_move.png"
		"attack": return "res://assets/tokens/token_attack.png"
		"heroic": return "res://assets/tokens/token_heroic.png"
		"wild": return "res://assets/tokens/token_wild.png"
		"civ": return "res://assets/tokens/civ_token.png"
		"thug": return "res://assets/tokens/thug_token.png"
	return ""

## 威胁卡强制横版：若卡图是竖构图（高>宽），当场旋转 90° 返回横版纹理；其余原样返回。
## 解决部分反派威胁卡背面为竖图、在弹窗里呈竖条的问题（兜底任何漏网）。
func _card_tex_landscape(tex: Texture2D, force_landscape: bool) -> Texture2D:
	if not force_landscape or tex == null:
		return tex
	var img: Image = tex.get_image()
	if img == null or img.get_height() <= img.get_width():
		return tex
	img.rotate_90(CLOCKWISE)
	return ImageTexture.create_from_image(img)

## 将纹理按指定方向旋转 90°（暴徒等指示物图标）。
func _rotate_texture(tex: Texture2D, dir: int) -> Texture2D:
	if tex == null:
		return tex
	var img: Image = tex.get_image()
	if img == null:
		return tex
	img.rotate_90(dir)
	return ImageTexture.create_from_image(img)

func show_confirm(text: String, callback: Callable) -> void:
	_confirm_callback = callback
	confirm_label.text = _ro_title(text)
	for c in confirm_panel.find_children("*", "Button", true, false):
		(c as Button).disabled = readonly
	confirm_panel.visible = true

# ================================================================ 手牌选择

func show_hand_pick(callback: Callable, title: String, hero_id: String, count: int) -> void:
	_hand_pick_callback = callback
	_hand_pick_hero = hero_id
	hand_pick_count = count
	hand_pick_selected = []
	_hand_pick_title = title
	hand_pick_label.text = _ro_title(title)
	render_hand_pick()
	hand_pick_panel.visible = true
	_hand_pick_block.visible = true

func render_hand_pick() -> void:
	_clear_children(hand_pick_box)
	var shield: bool = Game.state.get("mode", "base") == "shield"
	if shield:
		# 神盾局：从共享手牌选择（标注所属英雄）
		var shield_hand: Array = Game.state["shield_hand"]
		for i in range(shield_hand.size()):
			var card: Dictionary = shield_hand[i]
			var box := Control.new()
			box.custom_minimum_size = Vector2(78, 110)
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var tr := TextureRect.new()
			tr.custom_minimum_size = Vector2(72, 100)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.texture = load(UiKit.hero_card_image(card["hero"], card["idx"]))
			tr.position = Vector2(3, 0)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE if readonly else Control.MOUSE_FILTER_STOP
			tr.gui_input.connect(_on_hand_pick_toggle.bind(i, tr))
			bind_card_zoom(tr, UiKit.hero_card_image(card["hero"], card["idx"]))
			if hand_pick_selected.has(i):
				tr.modulate = Color(1.5, 1.5, 0.85)
				var border := ColorRect.new()
				border.color = Color(1, 0.9, 0.3, 0.9)
				border.set_anchors_preset(Control.PRESET_FULL_RECT)
				border.mouse_filter = Control.MOUSE_FILTER_IGNORE
				tr.add_child(border)
			box.add_child(tr)
			var tag := UiKit.label(DB.hero_name(card["hero"])[0], 11, DB.hero_color(card["hero"]))
			tag.add_theme_color_override("font_outline_color", Color(0, 0, 0))
			tag.add_theme_constant_override("outline_size", 3)
			tag.position = Vector2(3, 92)
			tag.custom_minimum_size = Vector2(30, 16)
			box.add_child(tag)
			hand_pick_box.add_child(box)
		var left: int = hand_pick_count - hand_pick_selected.size()
		hand_pick_confirm.disabled = readonly or left > 0
		hand_pick_confirm.text = "确认（还需选 %d 张）" % left if left > 0 else "确认"
		return
	var h: Dictionary = Game.state["heroes"][_hand_pick_hero]
	# 联机：只有"我能操作的英雄"才显示正面；别人的手牌（含主机看别人、以及别人弃牌时）一律只显示卡背 + 张数
	var mine: bool = (not Net.active) or (_hand_pick_hero == Net.controlling_hero())
	if not mine:
		# 张数：主机手里有真手牌就用真实张数；客户端手牌被裁空，用快照里的 hand_count
		var hh: Array = h["hand"]
		var n_backs: int = hh.size() if hh.size() > 0 else int(h.get("hand_count", 0))
		# 标题保持原样（不加"这是谁的手牌"之类的说明 —— 用户要求不要那行字）
		for i in range(n_backs):
			var bt := TextureRect.new()
			bt.custom_minimum_size = Vector2(72, 100)
			bt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			bt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			bt.texture = load(DB.hero_back(_hand_pick_hero))
			bt.mouse_filter = Control.MOUSE_FILTER_IGNORE     # 别人的牌不可点
			hand_pick_box.add_child(bt)
		hand_pick_confirm.disabled = true
		hand_pick_confirm.text = "等待对方选择…"
		return
	for i in range(h["hand"].size()):
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(72, 100)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture = load(UiKit.hero_card_image(_hand_pick_hero, h["hand"][i]))
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE if readonly else Control.MOUSE_FILTER_STOP
		tr.gui_input.connect(_on_hand_pick_toggle.bind(i, tr))
		bind_card_zoom(tr, UiKit.hero_card_image(_hand_pick_hero, h["hand"][i]))
		if hand_pick_selected.has(i):
			tr.modulate = Color(1.5, 1.5, 0.85)
			# 选中卡加亮边框
			var border := ColorRect.new()
			border.color = Color(1, 0.9, 0.3, 0.9)
			border.set_anchors_preset(Control.PRESET_FULL_RECT)
			border.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tr.add_child(border)
		hand_pick_box.add_child(tr)
	var left: int = hand_pick_count - hand_pick_selected.size()
	hand_pick_confirm.disabled = readonly or left > 0
	hand_pick_confirm.text = "确认（还需选 %d 张）" % left if left > 0 else "确认"

func _on_hand_pick_toggle(event: InputEvent, i: int, tr: TextureRect) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 单选（count==1）：点另一张直接切换选择，无需先取消；点已选中的则取消
		if hand_pick_count == 1:
			if hand_pick_selected.has(i):
				hand_pick_selected.erase(i)
			else:
				hand_pick_selected = [i]
		else:
			# 多选：点已选中→取消；未选中→加入（不超上限）
			if hand_pick_selected.has(i):
				hand_pick_selected.erase(i)
			elif hand_pick_selected.size() < hand_pick_count:
				hand_pick_selected.append(i)
		render_hand_pick()

func confirm_hand_pick() -> void:
	# 幂等：多重确认（如双击）只回调一次，避免对手牌选择/反派回合造成重复推进
	if not _hand_pick_callback.is_valid():
		return
	var cb := _hand_pick_callback
	var picked := hand_pick_selected.duplicate()
	hand_pick_panel.visible = false
	_hand_pick_block.visible = false
	hand_pick_selected = []
	_hand_pick_callback = Callable()
	cb.call(picked)

func cancel_hand_pick() -> void:
	var cb := _hand_pick_callback
	hand_pick_panel.visible = false
	_hand_pick_block.visible = false
	_hand_pick_callback = Callable()
	if cb.is_valid():
		cb.call([])

# ================================================================ 英雄选择（灭霸替换英雄）

## 打开英雄选择面板。options 为可选英雄 id 数组。
func show_hero_pick(callback: Callable, title: String, options: Array) -> void:
	_hero_pick_callback = callback
	_hero_pick_options = options.duplicate()
	_hero_pick_sort = "alpha"
	hero_pick_label.text = title
	hero_pick_search.text = ""
	_update_hero_sort_highlight()
	_render_hero_pick()
	hero_pick_panel.visible = true

func _render_hero_pick() -> void:
	_clear_children(hero_pick_box)
	var search: String = hero_pick_search.text.strip_edges()
	var view: Array = []
	for hid in _hero_pick_options:
		var nm: String = DB.hero_name(hid)
		if search != "" and not nm.contains(search):
			continue
		view.append(hid)
	# 排序
	var order := view.duplicate()
	if _hero_pick_sort == "alpha":
		order.sort_custom(func(a: String, b: String) -> bool:
			return _hero_sort_key(a) < _hero_sort_key(b))
	else:
		# 按扩展分组排序：基础盒前，瓦坎达后；组内按首字母
		order.sort_custom(func(a: String, b: String) -> bool:
			var ea: String = _hero_exp(a)
			var eb: String = _hero_exp(b)
			if ea != eb:
				return ea < eb
			return _hero_sort_key(a) < _hero_sort_key(b))
	for hid in order:
		var box := Control.new()
		box.custom_minimum_size = Vector2(100, 150)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(96, 132)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture = load(DB.hero_back(hid))
		tr.position = Vector2(2, 0)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE if readonly else Control.MOUSE_FILTER_STOP
		tr.gui_input.connect(_on_hero_pick_input.bind(hid, tr))
		bind_card_zoom(tr, DB.hero_back(hid))
		box.add_child(tr)
		hero_pick_box.add_child(box)
	if order.is_empty():
		var empty := UiKit.label("没有匹配的英雄", 18, Color(0.7, 0.7, 0.8))
		hero_pick_box.add_child(empty)

func _on_hero_pick_input(event: InputEvent, hid: String, tr: TextureRect) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cb := _hero_pick_callback
		hero_pick_panel.visible = false
		_hero_pick_callback = Callable()
		if cb.is_valid():
			cb.call(hid)

func _on_hero_search_changed(_t: String) -> void:
	_render_hero_pick()

func _on_hero_sort(mode: String) -> void:
	_hero_pick_sort = mode
	_update_hero_sort_highlight()
	_render_hero_pick()

func _update_hero_sort_highlight() -> void:
	if hero_pick_sort_alpha == null:
		return
	hero_pick_sort_alpha.modulate = Color(1.6, 1.4, 1.0) if _hero_pick_sort == "alpha" else Color.WHITE
	hero_pick_sort_exp.modulate = Color(1.6, 1.4, 1.0) if _hero_pick_sort == "expansion" else Color.WHITE

func cancel_hero_pick() -> void:
	var cb := _hero_pick_callback
	hero_pick_panel.visible = false
	_hero_pick_callback = Callable()
	if cb.is_valid():
		cb.call("")

## 英雄排序键：按英文字母名排序（name_en 供首字母排序）
func _hero_sort_key(hid: String) -> String:
	return str(DB.heroes.get(hid, {}).get("name_en", hid))

## 英雄所属扩展
func _hero_exp(hid: String) -> String:
	return str(DB.heroes.get(hid, {}).get("expansion", "基础盒"))

# ================================================================ 故事卡/牌库/反派卡选择

func show_story_pick(callback: Callable, title: String, filter_hero: String = "") -> void:
	_story_pick_callback = callback
	story_pick_label.text = title
	_clear_children(story_pick_box)
	var st: Dictionary = Game.state
	for i in range(st["story"].size()):
		var e: Dictionary = st["story"][i]
		if e["type"] != "hero":
			continue
		# 过滤：仅显示指定英雄的行动牌（如斯塔克实验室仅自己英雄）；否则显示全部英雄牌
		if filter_hero != "" and e["hero"] != filter_hero:
			continue
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(76, 106)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture = load(UiKit.hero_card_image(e["hero"], e["idx"]))
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE if readonly else Control.MOUSE_FILTER_STOP
		tr.gui_input.connect(_on_story_pick_input.bind(i))
		bind_card_zoom(tr, UiKit.hero_card_image(e["hero"], e["idx"]))
		story_pick_box.add_child(tr)
	story_pick_panel.visible = true

func _on_story_pick_input(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cb := _story_pick_callback
		story_pick_panel.visible = false
		_story_pick_callback = Callable()
		if cb.is_valid():
			cb.call(i)

func show_deck_pick(callback: Callable, title: String, hero_id: String) -> void:
	_story_pick_callback = callback
	story_pick_label.text = title
	_clear_children(story_pick_box)
	var deck: Array = Game.state["heroes"][hero_id]["deck"]
	for i in range(deck.size()):
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(76, 106)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture = load(UiKit.hero_card_image(hero_id, deck[i]))
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE if readonly else Control.MOUSE_FILTER_STOP
		tr.gui_input.connect(_on_story_pick_input.bind(i))
		bind_card_zoom(tr, UiKit.hero_card_image(hero_id, deck[i]))
		story_pick_box.add_child(tr)
	story_pick_panel.visible = true

## 显示一张反派行动牌（主计划牌）并要求确认：放底部 / 保持原位（黑寡妇审讯用）
func show_villain_card(callback: Callable, title: String, card_idx: int) -> void:
	_villain_card_callback = callback
	story_pick_label.text = title
	_clear_children(story_pick_box)
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(280, 200)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = load(UiKit.villain_action_image(Game.state["villain"], card_idx))
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_pick_box.add_child(tr)
	# 清掉默认"关闭"按钮，换成两个选择按钮
	_clear_children(story_pick_btns)
	if story_pick_btns != null:
		var btn_yes := UiKit.button("放到牌组底部", Color(0.3, 0.5, 0.8))
		btn_yes.pressed.connect(func():
			story_pick_panel.visible = false
			var cb := _villain_card_callback
			_villain_card_callback = Callable()
			if cb.is_valid():
				cb.call(true))
		story_pick_btns.add_child(btn_yes)
		var btn_no := UiKit.button("保持原位", Color(0.4, 0.4, 0.6))
		btn_no.pressed.connect(func():
			story_pick_panel.visible = false
			var cb := _villain_card_callback
			_villain_card_callback = Callable()
			if cb.is_valid():
				cb.call(false))
		story_pick_btns.add_child(btn_no)
	story_pick_panel.visible = true

# ================================================================ 动画4：反派行动牌展示

## 反派出牌展示：全屏遮罩 → 中央大卡(先背面，翻面成正面) → 3 秒后或点击关闭。
## 展示完成回调 on_close（game 侧恢复 villain 回合）。autopilot 时由 game 直接跳过，不调用这里。
var _reveal_root: Control = null

func show_villain_reveal(card_idx: int, on_close: Callable) -> void:
	if is_instance_valid(_reveal_root):
		_reveal_root.queue_free()
		_reveal_root = null
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	_reveal_root = root
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	# 中央大卡（先显示反派行动牌背面）
	var card := TextureRect.new()
	card.custom_minimum_size = Vector2(360, 506)
	card.size = Vector2(360, 506)
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s6_mode: bool = Game.state.get("mode", "") == "s6"
	var back_tex: Texture2D = load("res://assets/cards/s6/action_back.png") if s6_mode else load(DB.villain(Game.state["villain"])["back"])
	card.texture = back_tex
	card.position = Vector2(960 - 180, 540 - 253)
	card.pivot_offset = Vector2(180, 253)
	root.add_child(card)
	# 翻面：0.7s 后 scale_x 压扁 → 换正面 → 复原
	var face_tex: Texture2D = load("res://assets/cards/s6/action_%02d.png" % (card_idx + 1)) if s6_mode else load(UiKit.villain_action_image(Game.state["villain"], card_idx))
	var tw := create_tween()
	tw.tween_interval(0.7)
	tw.tween_property(card, "scale", Vector2(0.02, 1.0), 0.14)
	tw.tween_callback(func():
		if is_instance_valid(card):
			card.texture = face_tex)
	tw.tween_property(card, "scale", Vector2(1.0, 1.0), 0.14)
	# 关闭计时：3 秒
	var done := false
	var finish := func():
		if done:
			return
		done = true
		if is_instance_valid(_reveal_root):
			_reveal_root.queue_free()
			_reveal_root = null
		var cb := on_close
		if cb.is_valid():
			cb.call()
	var timer := get_tree().create_timer(3.0)
	timer.timeout.connect(finish)
	# 点击任意处也可关闭
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			finish.call())

# ================================================================ 叛徒模式：秘密身份牌

var _identity_root: Control = null

## 展示某玩家的身份牌。review=false 为开局发牌（点按后发 identity_confirmed 信号，供 Board 逐个继续）；
## review=true 为游戏中随时复查（点"知道了"关闭，不发送信号）。
func show_identity(hero_id: String, is_traitor: bool, review: bool = false) -> void:
	if is_instance_valid(_identity_root):
		_identity_root.queue_free()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	_identity_root = root
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.9)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(0.12, 0.12, 0.2, 0.97)))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)
	var t := UiKit.label("「%s」%s" % [DB.hero_name(hero_id), "点击身份牌翻开查看" if review else "请点击身份牌，翻开查看你的身份"], 30, Color(1, 0.92, 0.7))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	# 先显示牌背，点击后翻面揭示（避免直接亮出身份被别人看到）
	var face_path := ("res://assets/cards/modes/traitor/traitor.jpg" if is_traitor else "res://assets/cards/modes/traitor/loyal.jpg")
	var img := TextureRect.new()
	img.texture = load("res://assets/cards/modes/traitor/back.jpg")
	img.custom_minimum_size = Vector2(320, 450)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.mouse_filter = Control.MOUSE_FILTER_STOP
	img.pivot_offset = Vector2(160, 225)
	var flipped := false
	img.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and not flipped:
			flipped = true
			img.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 翻一次后不可再点击，避免重复动画
			var tw := img.create_tween()
			tw.tween_property(img, "scale:x", 0.02, 0.12)
			tw.tween_callback(func():
				if is_instance_valid(img):
					img.texture = load(face_path))
			tw.tween_property(img, "scale:x", 1.0, 0.12))
	v.add_child(img)
	var btn := UiKit.button("我记住了，藏起来" if not review else "知道了", Color(0.5, 0.3, 0.3))
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.custom_minimum_size = Vector2(240, 52)
	btn.pressed.connect(func():
		if is_instance_valid(_identity_root):
			_identity_root.queue_free()
			_identity_root = null
		if not review:
			Events.identity_confirmed.emit(hero_id))
	v.add_child(btn)

# ================================================================ 信息 / Toast / 结算

func show_info(text: String) -> void:
	_info_text.text = text
	info_panel.visible = true

## 任务完成弹窗：按第几个任务显示不同文案；上方为完成该任务的英雄卡背图标（第1个任务用反派行动牌背）。
func show_mission_completed(count: int, hero_id: String) -> void:
	var title := ""
	var sub := ""
	match count:
		1:
			title = "反派感受到了压力"
			sub = "此后反派将在两个英雄回合后行动"
			# 第1个任务：该反派的行动牌背面图标
			var vill_back: String = DB.villain(Game.state["villain"])["back"]
			mission_icon.texture = load(vill_back)
		2:
			title = "英雄们发现了反派阴谋"
			sub = "英雄们可以对反派造成伤害了"
			mission_icon.texture = load(DB.hero_back(hero_id))
		3:
			title = "英雄们无所不能，所向披靡"
			sub = "所有英雄回复一点生命（抽一张牌）"
			mission_icon.texture = load(DB.hero_back(hero_id))
		_:
			return
	mission_title.text = title
	mission_sub.text = sub
	mission_block.modulate.a = 1.0
	mission_block.visible = true
	mission_panel.visible = true   # 关键：内容面板需随遮罩一起显示（否则文字不显示）
	# 由小变大（以屏幕中心为锚），停下旧动画
	if mission_block.has_meta("mission_tw"):
		var old: Tween = mission_block.get_meta("mission_tw")
		if old != null and old.is_valid():
			old.kill()
	mission_block.pivot_offset = Vector2(960, 540)
	mission_block.scale = Vector2(0.82, 0.82)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(mission_block, "scale", Vector2(1, 1), 0.5)
	# 3 秒后自动返回；若玩家点击任意位置则立即关闭
	tw.tween_interval(3.0)
	tw.tween_callback(_hide_mission)
	mission_block.set_meta("mission_tw", tw)

func _on_mission_block_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_hide_mission()

func _hide_mission() -> void:
	if not mission_block.visible:
		return
	if mission_block.has_meta("mission_tw"):
		var old: Tween = mission_block.get_meta("mission_tw")
		if old != null and old.is_valid():
			old.kill()
	mission_block.visible = false
	mission_panel.visible = false
	mission_block.scale = Vector2(1, 1)

func show_toast(text: String) -> void:
	toast_label.text = text
	toast_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(toast_label, "modulate:a", 0.0, 0.6)

func show_game_over(victory: bool, reason: String, continue_cb: Callable = Callable()) -> void:
	overlay.visible = true
	if victory:
		overlay_label.text = "🏆 英雄们胜利！"
		overlay_label.add_theme_color_override("font_color", Color(0.5, 1, 0.5))
	else:
		if Game.state.get("campaign_lost", false):
			overlay_label.text = "英雄失败"
		else:
			overlay_label.text = "💀 英雄们失败了"
		overlay_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	_clear_children(overlay_icon)
	if victory:
		# 胜利：显示所有英雄图标
		var hids: Array = Game.state.get("hero_ids", [])
		for hid in hids:
			overlay_icon.add_child(_make_game_over_icon(DB.hero_back(hid)))
	else:
		# 失败：显示反派图标
		var vid: String = Game.state.get("villain", "")
		if vid != "":
			overlay_icon.add_child(_make_game_over_icon(DB.villain(vid)["back"]))
	overlay_sub.text = reason if reason != "" else "反派被击败！"
	overlay_button.visible = true
	# 断开旧连接（构建时或上次结算时连过），重新绑定
	for conn in overlay_button.pressed.get_connections():
		overlay_button.pressed.disconnect(conn["callable"])
	if continue_cb.is_valid():
		overlay_button.text = "进入下一局 ▶"
		overlay_button.pressed.connect(func(): continue_cb.call())
	else:
		overlay_button.text = "返回主菜单"
		overlay_button.pressed.connect(func(): UiKit.goto_scene("res://src/ui/MainMenu.tscn"))
	# 由小变大弹出（以屏幕中心为锚；文字大标题等随遮罩一起放大）
	if overlay.has_meta("overlay_tw"):
		var ok: Tween = overlay.get_meta("overlay_tw")
		if ok != null and ok.is_valid():
			ok.kill()
	overlay.pivot_offset = Vector2(960, 540)
	overlay.scale = Vector2(0.7, 0.7)
	overlay.modulate.a = 0.0
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK)
	tw.set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(overlay, "scale", Vector2(1, 1), 0.55)
	tw.parallel().tween_property(overlay, "modulate:a", 1.0, 0.4)
	overlay.set_meta("overlay_tw", tw)

## 制作结算图标（卡背图标）
func _make_game_over_icon(path: String) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = load(path)
	tr.custom_minimum_size = Vector2(90, 126)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

func _clear_children(container: Node) -> void:
	for c in container.get_children():
		container.remove_child(c)
		c.queue_free()

# ================================================================ 拖拽排序弹窗（术士亚当·量子魔法）

## 裁定 2：量子魔法要"真的能用鼠标拖"（不是点两个按钮交换）。
## 做法：3 张反派行动卡横排 → 按住某张拖到另一张上松手 = 两者互换；确认后交回新顺序。
var _reorder_root: Control = null
var _reorder_cards: Array = []          # 当前顺序（反派行动卡索引）
var _reorder_villain := ""
var _reorder_callback: Callable = Callable()
var _reorder_slots: Array = []          # 每个槽位的 PanelContainer（命中检测 + 高亮）
var _reorder_ghost: TextureRect = null  # 跟鼠标走的"拖拽残影"
var _reorder_drag := -1                 # 正在拖的槽位（-1 = 没在拖）
var _reorder_hover := -1                # 当前拖到哪个槽位

## cards = 反派行动卡索引数组，顺序即"牌堆顶 → 往下"。callback 收到新顺序。
func show_reorder_prompt(cards: Array, villain: String, title: String, callback: Callable) -> void:
	_reorder_callback = callback
	_reorder_cards = cards.duplicate()
	_reorder_villain = villain
	_reorder_drag = -1
	_reorder_hover = -1
	if is_instance_valid(_reorder_root):
		_reorder_root.queue_free()
	_reorder_root = null
	_reorder_slots.clear()
	_reorder_ghost = null
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	_reorder_root = root
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(0.12, 0.12, 0.2, 0.97)))
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 16)
	margin.add_child(outer)
	var t := UiKit.label(_ro_title(title), 26, Color(1, 0.92, 0.7))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(t)
	var hint := UiKit.label("按住一张卡牌，拖到另一张上松手即可互换（最左 = 牌堆顶）", 18, Color(0.8, 0.85, 0.95))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(row)
	if _reorder_cards.is_empty():
		# 联机时"不是本人在操作"→ 主机只发提示不发牌面（私有信息），这里就只显示等待
		row.add_child(UiKit.label("（等待其他玩家调整…）", 22, Color(0.8, 0.8, 0.9)))
	for i in range(_reorder_cards.size()):
		var slot := _make_reorder_slot(i)
		row.add_child(slot)
		_reorder_slots.append(slot)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 18)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(btns)
	var ok := UiKit.button("确认顺序", Color(0.3, 0.55, 0.4))
	ok.disabled = readonly or _reorder_cards.is_empty()
	ok.pressed.connect(_reorder_finish)
	btns.add_child(ok)
	# 拖拽残影：最后加 → 画在所有卡牌上面
	var ghost := TextureRect.new()
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.visible = false
	root.add_child(ghost)
	_reorder_ghost = ghost
	_reorder_refresh()

func _make_reorder_slot(idx: int) -> Control:
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(200, 300)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.gui_input.connect(_reorder_slot_input.bind(idx))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	holder.add_child(box)
	var caption := "#%d　牌堆顶" % (idx + 1) if idx == 0 else "#%d" % (idx + 1)
	var pos := UiKit.label(caption, 18, Color(1, 0.95, 0.8))
	pos.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(pos)
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(184, 262)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tr)
	return holder

## 按当前顺序刷牌面 / 高亮（被拖的那张变暗，拖到的目标槽位高亮）
func _reorder_refresh() -> void:
	for i in range(_reorder_slots.size()):
		var slot: Control = _reorder_slots[i]
		if not is_instance_valid(slot):
			continue
		for c in slot.get_children():
			for cc in c.get_children():
				if cc is TextureRect and i < _reorder_cards.size():
					cc.texture = load(UiKit.villain_action_image(_reorder_villain, int(_reorder_cards[i])))
		var bg := Color(0.45, 0.6, 0.85, 0.98) if i == _reorder_hover else Color(0.22, 0.24, 0.34, 0.95)
		slot.add_theme_stylebox_override("panel", UiKit.panel_style(bg))
		slot.modulate = Color(0.55, 0.55, 0.55) if i == _reorder_drag else Color(1, 1, 1)

func _reorder_slot_at(global_pos: Vector2) -> int:
	for i in range(_reorder_slots.size()):
		var slot: Control = _reorder_slots[i]
		if is_instance_valid(slot) and slot.get_global_rect().has_point(global_pos):
			return i
	return -1

## 真正的拖拽：按下 → 出现残影跟手；松开 → 和松手处那张互换（真鼠标拖，不是按钮）
## 用事件自带的坐标（而不是 get_global_mouse_position）：这样合成事件/自动化截图也能真拖。
func _reorder_slot_input(event: InputEvent, idx: int) -> void:
	if readonly or _reorder_cards.is_empty() or _reorder_root == null:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_reorder_drag = idx
			_reorder_hover = idx
			if _reorder_ghost != null and idx < _reorder_cards.size():
				_reorder_ghost.texture = load(UiKit.villain_action_image(_reorder_villain, int(_reorder_cards[idx])))
				_reorder_ghost.size = Vector2(184, 262)
				_reorder_ghost.global_position = mb.global_position - Vector2(92, 131)
				_reorder_ghost.visible = true
		else:
			var to := _reorder_slot_at(mb.global_position)
			var from := _reorder_drag
			_reorder_drag = -1
			if _reorder_ghost != null:
				_reorder_ghost.visible = false
			if to >= 0 and from >= 0 and to != from and to < _reorder_cards.size() and from < _reorder_cards.size():
				var tmp: Variant = _reorder_cards[from]
				_reorder_cards[from] = _reorder_cards[to]
				_reorder_cards[to] = tmp
			_reorder_hover = -1
		_reorder_refresh()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _reorder_drag >= 0:
		_reorder_hover = _reorder_slot_at(mm.global_position)
		if _reorder_ghost != null:
			_reorder_ghost.global_position = mm.global_position - Vector2(92, 131)
		_reorder_refresh()

func _reorder_finish() -> void:
	var cb := _reorder_callback
	_reorder_callback = Callable()
	var out: Array = _reorder_cards.duplicate()
	if is_instance_valid(_reorder_root):
		_reorder_root.queue_free()
	_reorder_root = null
	_reorder_slots.clear()
	_reorder_ghost = null
	_reorder_drag = -1
	_reorder_hover = -1
	if cb.is_valid():
		cb.call(out)
