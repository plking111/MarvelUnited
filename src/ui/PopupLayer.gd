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

var info_panel: PanelContainer
var _info_text: RichTextLabel

var toast_label: Label

var overlay: ColorRect
var overlay_label: Label
var overlay_sub: Label
var overlay_button: Button

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
	overlay_label = UiKit.label("", 60, Color.WHITE)
	overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_label.position = Vector2(560, 320)
	overlay_label.size = Vector2(800, 90)
	overlay.add_child(overlay_label)
	overlay_sub = UiKit.label("", 26, Color(0.9, 0.9, 0.9))
	overlay_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_sub.position = Vector2(560, 420)
	overlay_sub.size = Vector2(800, 60)
	overlay.add_child(overlay_sub)
	overlay_button = UiKit.button("返回主菜单", Color(0.3, 0.5, 0.8))
	# 水平居中于屏幕（锚点取中心，固定宽 160；避免偏左）
	overlay_button.anchor_left = 0.5
	overlay_button.anchor_right = 0.5
	overlay_button.offset_left = -80
	overlay_button.offset_right = 80
	overlay_button.offset_top = 520
	overlay_button.offset_bottom = 564
	overlay_button.pressed.connect(func(): get_tree().change_scene_to_file("res://src/ui/MainMenu.tscn"))
	overlay.add_child(overlay_button)

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
		if hand_pick_selected.has(i):
			hand_pick_selected.erase(i)
		elif hand_pick_selected.size() < hand_pick_count:
			hand_pick_selected.append(i)
		render_hand_pick()

func confirm_hand_pick() -> void:
	var cb := _hand_pick_callback
	hand_pick_panel.visible = false
	_hand_pick_callback = Callable()
	if cb.is_valid():
		cb.call(hand_pick_selected.duplicate())

func cancel_hand_pick() -> void:
	var cb := _hand_pick_callback
	hand_pick_panel.visible = false
	_hand_pick_callback = Callable()
	if cb.is_valid():
		cb.call([])

# ================================================================ 故事卡/牌库/反派卡选择

func show_story_pick(callback: Callable, title: String) -> void:
	_story_pick_callback = callback
	story_pick_label.text = title
	_clear_children(story_pick_box)
	var st: Dictionary = Game.state
	for i in range(st["story"].size()):
		var e: Dictionary = st["story"][i]
		if e["type"] != "hero":
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

func show_toast(text: String) -> void:
	toast_label.text = text
	toast_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(toast_label, "modulate:a", 0.0, 0.6)

func show_game_over(victory: bool, reason: String) -> void:
	overlay.visible = true
	if victory:
		overlay_label.text = "🏆 英雄们胜利！"
		overlay_label.add_theme_color_override("font_color", Color(0.5, 1, 0.5))
	else:
		overlay_label.text = "💀 英雄们失败了"
		overlay_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	overlay_sub.text = reason if reason != "" else "反派被击败！"
	overlay_button.visible = true

func _clear_children(container: Node) -> void:
	for c in container.get_children():
		container.remove_child(c)
		c.queue_free()
