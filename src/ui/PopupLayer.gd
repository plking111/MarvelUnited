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

# ================================================================ 选择/确认

func show_prompt(options: Array, title: String, callback: Callable) -> void:
	_prompt_callback = callback
	prompt_label.text = title
	_clear_children(prompt_buttons)
	for i in range(options.size()):
		var btn := UiKit.button(str(options[i]), Color(0.3, 0.4, 0.7))
		btn.pressed.connect(_on_prompt_pick.bind(i))
		prompt_buttons.add_child(btn)
	prompt_panel.visible = true

func _on_prompt_pick(idx: int) -> void:
	prompt_panel.visible = false
	var cb := _prompt_callback
	_prompt_callback = Callable()
	if cb.is_valid():
		cb.call(idx)

func show_confirm(text: String, callback: Callable) -> void:
	_confirm_callback = callback
	confirm_label.text = text
	confirm_panel.visible = true

# ================================================================ 手牌选择

func show_hand_pick(callback: Callable, title: String, hero_id: String, count: int) -> void:
	_hand_pick_callback = callback
	_hand_pick_hero = hero_id
	hand_pick_count = count
	hand_pick_selected = []
	hand_pick_label.text = title
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
			tr.mouse_filter = Control.MOUSE_FILTER_STOP
			tr.gui_input.connect(_on_hand_pick_toggle.bind(i, tr))
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
		hand_pick_confirm.disabled = left > 0
		hand_pick_confirm.text = "确认（还需选 %d 张）" % left if left > 0 else "确认"
		return
	var h: Dictionary = Game.state["heroes"][_hand_pick_hero]
	for i in range(h["hand"].size()):
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(72, 100)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture = load(UiKit.hero_card_image(_hand_pick_hero, h["hand"][i]))
		tr.mouse_filter = Control.MOUSE_FILTER_STOP
		tr.gui_input.connect(_on_hand_pick_toggle.bind(i, tr))
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
	hand_pick_confirm.disabled = left > 0
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
		tr.mouse_filter = Control.MOUSE_FILTER_STOP
		tr.gui_input.connect(_on_hero_pick_input.bind(hid, tr))
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
		tr.mouse_filter = Control.MOUSE_FILTER_STOP
		tr.gui_input.connect(_on_story_pick_input.bind(i))
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
		tr.mouse_filter = Control.MOUSE_FILTER_STOP
		tr.gui_input.connect(_on_story_pick_input.bind(i))
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
