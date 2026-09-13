extends Control
## 游戏主界面：桌面、地点环、手牌、行动条、故事情节、日志、弹窗层。
##
## 模块结构（新增内容 / 修 bug 时按模块定位）：
##  - UiKit        共享 UI 工厂（标签/按钮/面板样式）
##  - PopupLayer   弹窗层（CanvasLayer=100，所有对话框/结算覆盖层，永远在最上，
##                 主界面动态重建的角色图标不可能遮挡弹窗）
##  - LocationView 地点卡视图（卡面/民暴槽位/危机/威胁/爪牙）
##  - MissionView  任务卡视图（卡图/指示物/进度）
##  - Board        桌面布局与刷新调度（反派/故事情节/手牌/行动/日志/角色图标层）
## 新增英雄/反派/地图/任务/模式 = 加 data/*.json + 素材图即可，UI 由数据驱动。

# 布局：地图区在屏幕右半边（约 3/5），日志在左侧中部，手牌在左下角
const LOC_CENTER := Vector2(1344, 508)
const LOC_RADIUS := 350.0
const LOC_CARD_SIZE := 230.0

var _popup: PopupLayer
var _zoom_layer: CanvasLayer
var _card_anim_layer: CanvasLayer   # 卡片动画层（layer 60）：出牌移动/抽牌翻面/反派牌弹窗的临时宿主
var _card_anim_root: Control   # 卡片动画层的全屏容器（放动画中的卡片，用全局坐标定位）

var _villain_panel: TextureRect
var _villain_deck_label: Label
var _villain_deck_info: Control
var _villain_deck_icon: TextureRect
var _villain_deck_num: Label
var _hp_label: Label
var _hp_icon: TextureRect
var _fear_bar: ProgressBar
var _fear_label: Label
var _ko_icon: TextureRect   # 罗南：KO 指示物图标（放在反派进度条旁）
var _goblin_civ_box: HBoxContainer   # 绿魔：绑架到反派面板的平民指示物（按顺序显示）
var _phase_label: Label
var _turn_label: Label
var _campaign_label: Label
var _villain_deck_hint: Label   # 无限战争：反派牌堆顶是宝石时的提示
var _villain_top_card: TextureRect   # 裁定③：阿戈摩托之球把"反派牌堆顶那张行动牌"贴卡图公开（悬停放大）
var _energy_done_box: HBoxContainer  # Bug4：右侧 已完成能量卡图标区
var _gauntlet: Control
var _gauntlet_base: TextureRect
var _gem_nodes: Dictionary = {}   # stone index -> TextureRect (无限战争手套宝石图标)
var _gauntlet_pos: Dictionary = {} # stone index -> Vector2 (相对手套容器)
var _energy_box: HBoxContainer
var _energy_buttons: Array = []   # 能量卡填充按钮（战役模式 hero_actions 阶段显示）
var _mission_box: HBoxContainer
var _loc_views: Array = []
var _story_box: HBoxContainer
var _hand_box: HBoxContainer
var _hand_panel: PanelContainer
var _hand_tween: Tween   # 手牌卡悬停果冻/摇晃动画（同一时刻只对一张卡播放）
var _hover_card: Control = null   # 当前被悬停放大的手牌卡（抽牌翻牌结束时需要清掉它的放大/晃动）
var _hand_disp_ctx: String = ""     # 上次刷新手牌的显示上下文（"h:<hid>" / "shield"），抽牌动画检测用
var _hand_disp_combos: Array = []   # 上次刷新手牌的卡组合（普通=h[i]索引；神盾=hero/idx），抽牌动画检测用
var _revealing_villain: bool = false   # 动画4：反派出牌弹窗展示中（防重复触发）
var _hand_label: Label
var _hand_random: ColorRect   # 乌木侯控制时叠在手牌区的暗色遮罩
var _hand_random_btn: Button  # 手牌区中央的"随机出牌"按钮
var _action_box: HBoxContainer
var _token_box: HBoxContainer
var _log_box: VBoxContainer
var hand_hero_id := ""     # 手牌区当前显示哪位英雄的牌（联机时固定为自己的英雄）
var _mp_peers_box: VBoxContainer = null   # 联机：右下角"队友手牌张数"
var _log_scroll: ScrollContainer
var _icon_nodes: Array = []
var _prev_icon_locs: Dictionary = {}   # 上次刷新时的角色位置（英雄id/villain -> 地点）
var _animating_icons := false          # 角色移动动画进行中（期间跳过图标重建）
var _anim_pending := 0                 # 进行中的角色动画计数
var _hero_icons: Dictionary = {}
var _villain_icons: Dictionary = {}
var _fear_marker: ColorRect
var _show_coords := false
var _coord_label: Label
var _setup: Dictionary = {}
var _start_button: Button
var _story_scroll: ScrollContainer
var _zoom_panel: TextureRect
var _peek_hero: String = ""
var _eliminated_box: HBoxContainer   # 灭霸：阵亡英雄图标区（灭霸面板生命值下方）
var _eliminated_label: Label          # 灭霸：已阵亡英雄计数文字
var _energy_stack_box: Control      # 灭霸非IW：激活能量卡 背面叠加区（任务牌下方）
var _endangered_side_box: HBoxContainer  # 濒危地点：手牌区右侧 牌组旁指示物
var _peek_prev: Button
var _peek_next: Button
var _deck_info: Control
var _token_info_box: HBoxContainer
var _mission_textures: Dictionary = {}

# 指示物图标缓存
var _icon_civ: Texture2D
var _icon_thug: Texture2D
var _icon_crisis: Texture2D
var _icon_threat: Texture2D
var _icon_move: Texture2D
var _icon_attack: Texture2D
var _icon_heroic: Texture2D
var _icon_wild: Texture2D

func _ready() -> void:
	_icon_civ = load("res://assets/tokens/civ_token.png")
	_icon_thug = load("res://assets/tokens/thug_token.png")
	_icon_crisis = load("res://assets/tokens/crisis_token.png")
	_icon_threat = load("res://assets/tokens/threat_token.png")
	_icon_move = load("res://assets/tokens/token_move.png")
	_icon_attack = load("res://assets/tokens/token_attack.png")
	_icon_heroic = load("res://assets/tokens/token_heroic.png")
	_icon_wild = load("res://assets/tokens/token_wild.png")
	_mission_textures = {
		"rescue": load("res://assets/tokens/mission_rescue.png"),
		"defeat": load("res://assets/tokens/mission_defeat.png"),
		"clear": load("res://assets/tokens/mission_clear.png"),
	}
	# 英雄/反派图标：使用卡牌背面图（英雄=英雄卡背，反派=反派行动牌背）。
	# ⚠️ 这里以前是**写死的 id 列表**，每加一批英雄都得手改；第三批 13 位就漏改了，
	#    结果地点上的英雄图标全是黑的（贴图加载为空 → 露出深色底板）。
	#    现在直接遍历 DB 的全部键，新增英雄/反派自动生效，不会再漏。
	for hid in DB.heroes.keys():
		_hero_icons[String(hid)] = load(DB.hero_back(String(hid)))
	for vid in DB.villains.keys():
		_villain_icons[String(vid)] = load(DB.villain(String(vid))["back"])
	_build_ui()
	# 弹窗/提示信号 → 弹窗层模块（CanvasLayer=100，永不被主界面内容遮挡）
	Events.state_changed.connect(_refresh_all)
	Events.log_line.connect(_on_log)
	Events.prompt_choice.connect(_popup.show_prompt)
	Events.prompt_confirm.connect(_popup.show_confirm)
	Events.prompt_action.connect(_popup.show_action_prompt)
	Events.prompt_hand_card.connect(_popup.show_hand_pick)
	Events.prompt_story_card.connect(_popup.show_story_pick)
	Events.prompt_villain_card.connect(_popup.show_villain_card)
	Events.prompt_deck_card.connect(_popup.show_deck_pick)
	Events.prompt_hero_pick.connect(_popup.show_hero_pick)
	Events.prompt_reorder.connect(_popup.show_reorder_prompt)
	# 联机：不是本人的弹窗置为只读（只展示、点不动）
	Events.popup_readonly_changed.connect(_popup.set_readonly)
	# 联机：主机告知"这个弹窗已经处理完了" → 收起本机弹窗
	# （bug4：别人已经选完，自己这边还挂着弹窗；以前也不关）
	Net._popup_cmd.connect(func(cmd: String) -> void:
		if cmd == "hide":
			_popup.hide_all_prompts())
	Events.toast.connect(_popup.show_toast)
	Events.mission_completed.connect(_popup.show_mission_completed)
	Events.game_over.connect(_on_game_over)
	_setup = Game.pending_setup
	if _setup.is_empty():
		_setup = {"villain": "redskull", "heroes": ["cap"], "challenge": "none"}
	Game.setup(_setup["villain"], _setup["heroes"], _setup["challenge"], _setup.get("mode", "base"), _setup.get("expansions", []))
	# 调试：填满所有地点槽位（查看槽位位置）
	if _setup.get("debug_full_slots", false):
		_fill_all_slots()
	_refresh_all()
	_build_mp_peers()
	# 联机：房主的 Board 就绪后自动开始第一个反派回合（客户端只等主机快照）
	if Game.net_auto_start and Net.is_host:
		Game.net_auto_start = false
		await Game.start_game()

## 调试用：把所有地点的槽位填满（平民/暴徒交替）
func _fill_all_slots() -> void:
	for l in Game.state["locations"]:
		var total: int = int(DB.location(l["id"])["slots"])
		var civ := 0
		var thug := 0
		for i in range(total):
			if i % 2 == 0:
				civ += 1
			else:
				thug += 1
		l["civ"] = civ
		l["thug"] = thug
	Game.state["missions_completed"] = 0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F11:
		_toggle_fullscreen()
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_show_coords = not _show_coords
		_coord_label.visible = _show_coords
	# 悬停放大预览：滚轮放大/缩小（仅在放大图显示时生效，不影响地图缩放）
	if event is InputEventMouseButton and event.pressed and _zoom_panel != null and _zoom_panel.visible:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_mul = clampf(_zoom_mul * 1.15, 0.25, 4.0)
			_apply_zoom_size()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_mul = clampf(_zoom_mul / 1.15, 0.25, 4.0)
			_apply_zoom_size()
			get_viewport().set_input_as_handled()

## 按当前滚轮倍率重新设置放大预览的尺寸（并保持贴着鼠标）；
## 上限：任何情况下都不超出屏幕（宽/高各留 40px 边距），超出则回收倍率
func _apply_zoom_size() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var max_w: float = maxf(vp.x - 80.0, 120.0)
	var max_h: float = maxf(vp.y - 80.0, 120.0)
	var zs: Vector2 = _zoom_base_size * _zoom_mul
	var f := 1.0
	if zs.x > max_w:
		f = minf(f, max_w / zs.x)
	if zs.y > max_h:
		f = minf(f, max_h / zs.y)
	if f < 1.0:
		_zoom_mul = clampf(_zoom_mul * f, 0.25, 4.0)   # 收到上限，滚轮再放大也不会溢出屏幕
		zs = _zoom_base_size * _zoom_mul
	_zoom_panel.custom_minimum_size = zs
	_zoom_panel.size = zs
	_zoom_panel.pivot_offset = zs / 2.0
	_update_zoom_position()

func _toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

# ================================================================ UI 构建

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.10, 0.16)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 反派区域背景框（左上，含面板/生命/恐惧轨道）
	var villain_bg := Panel.new()
	villain_bg.position = Vector2(15, 5)
	villain_bg.size = Vector2(410, 272)
	villain_bg.add_theme_stylebox_override("panel", UiKit.box_style(Color(0.16, 0.16, 0.24, 0.85), Color(0.55, 0.45, 0.75, 0.9)))
	add_child(villain_bg)
	_villain_bg = villain_bg
	# 反派面板（子节点相对 villain_bg 定位）
	_villain_panel = TextureRect.new()
	_villain_panel.position = Vector2(5, 5)
	_villain_panel.custom_minimum_size = Vector2(380, 169)
	_villain_panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_villain_panel.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	villain_bg.add_child(_villain_panel)
	_bind_zoom(_villain_panel)
	# 红骷髅恐惧轨道：蓝色位置指示方块（盖在轨道对应格上，小一号）
	_fear_marker = ColorRect.new()
	_fear_marker.color = Color(0.2, 0.5, 1.0, 0.95)
	_fear_marker.custom_minimum_size = Vector2(9, 9)
	_fear_marker.visible = false
	_fear_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_villain_panel.add_child(_fear_marker)
	_hp_icon = TextureRect.new()
	_hp_icon.texture = load("res://assets/tokens/hp_icon.png")
	_hp_icon.custom_minimum_size = Vector2(26, 26)
	_hp_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hp_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hp_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_icon.position = Vector2(5, 182)
	villain_bg.add_child(_hp_icon)
	_hp_label = UiKit.label("", 24, Color(1, 0.9, 0.4))
	_hp_label.position = Vector2(38, 180)
	villain_bg.add_child(_hp_label)
	_fear_bar = ProgressBar.new()
	_fear_bar.position = Vector2(5, 213)
	_fear_bar.custom_minimum_size = Vector2(380, 20)
	_fear_bar.show_percentage = false
	villain_bg.add_child(_fear_bar)
	_fear_label = UiKit.label("", 16, Color(0.9, 0.6, 0.6))
	_fear_label.position = Vector2(5, 238)
	villain_bg.add_child(_fear_label)
	# 绿魔：绑架到反派面板的平民指示物（按顺序显示在反派面板下方空白处）
	_goblin_civ_box = HBoxContainer.new()
	_goblin_civ_box.position = Vector2(5, 225)
	_goblin_civ_box.add_theme_constant_override("separation", 4)
	_goblin_civ_box.visible = false
	villain_bg.add_child(_goblin_civ_box)
	# 罗南 KO 指示物图标（放在进度条标签左侧；仅罗南显示）
	_ko_icon = TextureRect.new()
	_ko_icon.texture = load("res://assets/cards/villains/ronan/ko_token.png")
	_ko_icon.custom_minimum_size = Vector2(20, 20)
	_ko_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ko_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ko_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ko_icon.position = Vector2(360, 238)
	_ko_icon.visible = false
	villain_bg.add_child(_ko_icon)
	# 灭霸：已阵亡英雄计数（生命值右侧，x/y，y=初始玩家数）+ 图标（下方，缩小到不超面板）
	_eliminated_label = UiKit.label("已阵亡 0/0", 17, Color(1, 0.75, 0.4))
	_eliminated_label.position = Vector2(250, 182)
	_eliminated_label.custom_minimum_size = Vector2(150, 24)
	_eliminated_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_eliminated_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_eliminated_label.add_theme_constant_override("outline_size", 3)
	_eliminated_label.visible = false
	villain_bg.add_child(_eliminated_label)
	_eliminated_box = HBoxContainer.new()
	_eliminated_box.position = Vector2(250, 210)
	_eliminated_box.add_theme_constant_override("separation", 4)
	_eliminated_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_eliminated_box.visible = false
	villain_bg.add_child(_eliminated_box)

	# 反派牌堆数量显示（样式与英雄牌库一致：背面图标 + 数字叠加）
	_villain_deck_label = UiKit.label("反派牌堆", 14, Color(0.8, 0.8, 0.9))
	_villain_deck_label.position = Vector2(432, 178)
	add_child(_villain_deck_label)
	# 无限战争：反派牌堆顶是宝石时的提示（在反派牌堆右侧）
	_villain_deck_hint = UiKit.label("", 16, Color(1, 0.6, 1))
	_villain_deck_hint.position = Vector2(520, 186)
	_villain_deck_hint.custom_minimum_size = Vector2(200, 40)
	_villain_deck_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_villain_deck_hint.add_theme_constant_override("outline_size", 3)
	_villain_deck_hint.visible = false
	add_child(_villain_deck_hint)
	# 裁定③（新口径）：阿戈摩托之球生效期间，反派牌堆顶那张行动牌**贴卡图**放在反派牌堆右侧。
	# 悬停放大复用 Board 自己的 _zoom_show()/_zoom_hide()（与手牌/故事情节同一套放大机制）。
	# 贴图来源每帧只认 state 里的 villain_top_public / villain_top_idx（联机时由主机下发，
	# 客户端**读不到也不允许读** master_deck）。
	_villain_top_card = TextureRect.new()
	_villain_top_card.position = Vector2(518, 176)
	_villain_top_card.custom_minimum_size = Vector2(86, 120)
	_villain_top_card.size = Vector2(86, 120)
	_villain_top_card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_villain_top_card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_villain_top_card.mouse_filter = Control.MOUSE_FILTER_STOP   # 需要收到鼠标悬停才能放大
	_villain_top_card.visible = false
	add_child(_villain_top_card)
	_bind_zoom(_villain_top_card)
	_villain_deck_info = Control.new()
	_villain_deck_info.position = Vector2(432, 200)
	_villain_deck_info.custom_minimum_size = Vector2(38, 52)
	add_child(_villain_deck_info)
	_villain_deck_icon = TextureRect.new()
	_villain_deck_icon.custom_minimum_size = Vector2(38, 52)
	_villain_deck_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_villain_deck_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_villain_deck_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_villain_deck_info.add_child(_villain_deck_icon)
	_villain_deck_num = UiKit.label("", 17, Color.WHITE)
	_villain_deck_num.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_villain_deck_num.add_theme_constant_override("outline_size", 4)
	_villain_deck_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_villain_deck_num.position = Vector2(0, 30)
	_villain_deck_num.custom_minimum_size = Vector2(36, 20)
	_villain_deck_info.add_child(_villain_deck_num)

	# 阶段横幅（顶部）
	_phase_label = UiKit.label("", 25, Color.WHITE)
	_phase_label.position = Vector2(430, 6)
	_phase_label.size = Vector2(700, 32)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_phase_label)
	_turn_label = UiKit.label("", 15, Color(0.8, 0.8, 0.8))
	_turn_label.position = Vector2(430, 40)
	_turn_label.size = Vector2(700, 24)
	add_child(_turn_label)

	# 无限战争战役信息（右侧竖排：局数/宝石/能量卡解锁；避开右上角返回按钮与地点环）
	_campaign_label = UiKit.label("", 15, Color(1, 0.8, 0.5))
	_campaign_label.position = Vector2(1755, 100)
	_campaign_label.size = Vector2(160, 240)
	_campaign_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_campaign_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_campaign_label.add_theme_constant_override("outline_size", 4)
	_campaign_label.visible = false
	add_child(_campaign_label)
	# Bug4：无限战争 已完成能量卡图标区（战役信息下方，横向）
	_energy_done_box = HBoxContainer.new()
	_energy_done_box.position = Vector2(1660, 340)
	_energy_done_box.add_theme_constant_override("separation", 6)
	_energy_done_box.visible = false
	add_child(_energy_done_box)

	# 无限战争：灭霸无限手套（地图环与日志之间的空隙），随收集进度点亮对应宝石
	_build_gauntlet()

	# 无限战争能量卡区（任务牌下方略近处，两张：开局可解锁 / 需三任务解锁）
	_energy_box = HBoxContainer.new()
	_energy_box.position = Vector2(1344 - 162, 534)
	_energy_box.add_theme_constant_override("separation", 8)
	_energy_box.visible = false
	add_child(_energy_box)

	# 灭霸(非无限战争Boss) 激活能量卡 背面叠加区（任务牌下方，横置背面卡相互叠加）
	_energy_stack_box = Control.new()
	# 原点 = 任务牌中心(x≈1340)，卡片用相对中心坐标；位于任务牌下方
	_energy_stack_box.position = Vector2(1340, 520)
	_energy_stack_box.custom_minimum_size = Vector2(120, 180)
	_energy_stack_box.visible = false
	add_child(_energy_stack_box)

	# 故事情节（横幅下方横向，带滚动条可查看全部历史卡）
	var s_label := UiKit.label("故事情节", 14, Color(0.8, 0.9, 1))
	s_label.position = Vector2(430, 68)
	add_child(s_label)
	_story_scroll = ScrollContainer.new()
	_story_scroll.position = Vector2(430, 84)
	_story_scroll.custom_minimum_size = Vector2(780, 92)
	_story_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_story_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_story_scroll)
	_story_box = HBoxContainer.new()
	_story_box.add_theme_constant_override("separation", 2)
	_story_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_story_scroll.add_child(_story_box)

	# 返回主菜单（右上角）
	var back_btn := UiKit.button_bordered("返回主菜单", Color(0.4, 0.3, 0.5))
	back_btn.position = Vector2(1760, 12)
	back_btn.pressed.connect(func(): UiKit.goto_scene("res://src/ui/MainMenu.tscn"))
	add_child(back_btn)

	# 开始游戏按钮（准备阶段显示：初始指示物已放置，点击进入第一个反派回合）
	# 位置：画面最上方中央（不遮挡地图），准备阶段时阶段横幅文字清空
	_start_button = UiKit.button("▶ 开始游戏（进入第一个反派回合）", Color(0.3, 0.65, 0.35))
	_start_button.position = Vector2(760, 6)
	_start_button.custom_minimum_size = Vector2(400, 62)
	_start_button.add_theme_font_size_override("font_size", 24)
	_start_button.pressed.connect(_on_start_pressed)
	_start_button.visible = false
	add_child(_start_button)

	# 任务卡（地点环正中心；含指示物行，整体略上移；下方留能量卡文字区）
	_mission_box = HBoxContainer.new()
	_mission_box.position = Vector2(1344 - 162, 508 - 160)
	_mission_box.add_theme_constant_override("separation", 6)
	add_child(_mission_box)

	# 地点环（右半边，约 3/5 屏幕）——每个地点一个 LocationView 模块
	var loc_bank := {
		"civ": _icon_civ, "thug": _icon_thug, "crisis": _icon_crisis,
		"threat": _icon_threat, "heroic": _icon_heroic,
	}
	for i in range(Game.LOCATION_COUNT):
		var ang: float = TAU * i / Game.LOCATION_COUNT - PI / 2
		var pos := LOC_CENTER + Vector2(cos(ang), sin(ang)) * LOC_RADIUS
		var lv := LocationView.new()
		lv.setup(i, pos, loc_bank, _on_location_clicked.bind(i))
		add_child(lv)
		_loc_views.append(lv)

	# 手牌区（左下角，约半屏宽）
	_hand_panel = PanelContainer.new()
	_hand_panel.position = Vector2(20, 870)
	_hand_panel.custom_minimum_size = Vector2(940, 165)
	_hand_panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(0.15, 0.15, 0.22, 0.92)))
	add_child(_hand_panel)
	var hv := VBoxContainer.new()
	_hand_panel.add_child(hv)
	var htop := HBoxContainer.new()
	hv.add_child(htop)
	_hand_label = UiKit.label("", 17, Color.WHITE)
	htop.add_child(_hand_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	htop.add_child(spacer)
	# 切换英雄手牌按钮（非官方功能，设置中开启后可用）
	_peek_prev = UiKit.button("◀ 上一英雄", Color(0.35, 0.35, 0.5))
	_peek_prev.custom_minimum_size = Vector2(110, 34)
	_peek_prev.add_theme_font_size_override("font_size", 15)
	_peek_prev.pressed.connect(_on_peek_prev)
	_peek_prev.visible = false
	htop.add_child(_peek_prev)
	_peek_next = UiKit.button("下一英雄 ▶", Color(0.35, 0.35, 0.5))
	_peek_next.custom_minimum_size = Vector2(110, 34)
	_peek_next.add_theme_font_size_override("font_size", 15)
	_peek_next.pressed.connect(_on_peek_next)
	_peek_next.visible = false
	htop.add_child(_peek_next)
	# 当前英雄行动指示物数量（手牌区右侧）
	_token_info_box = HBoxContainer.new()
	_token_info_box.add_theme_constant_override("separation", 8)
	htop.add_child(_token_info_box)
	# 牌堆剩余数量（行动牌背面图标 + 数字叠加，手牌区最右侧）
	_deck_info = Control.new()
	_deck_info.custom_minimum_size = Vector2(38, 52)
	_deck_info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	htop.add_child(_deck_info)
	_hand_box = HBoxContainer.new()
	_hand_box.add_theme_constant_override("separation", 6)
	hv.add_child(_hand_box)

	# 乌木侯控制：暗色遮罩 + 顶部中心"随机出牌"按钮（叠在手牌区之上）
	_hand_random = ColorRect.new()
	_hand_random.color = Color(0, 0, 0, 0.55)
	_hand_random.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hand_random.mouse_filter = Control.MOUSE_FILTER_STOP
	_hand_random.visible = false
	_hand_panel.add_child(_hand_random)
	_hand_random_btn = UiKit.button("随机出牌", Color(0.5, 0.3, 0.7))
	_hand_random_btn.custom_minimum_size = Vector2(220, 60)
	_hand_random_btn.add_theme_font_size_override("font_size", 26)
	_hand_random_btn.anchor_left = 0.5
	_hand_random_btn.anchor_right = 0.5
	_hand_random_btn.anchor_top = 0.5
	_hand_random_btn.anchor_bottom = 0.5
	_hand_random_btn.offset_left = -110
	_hand_random_btn.offset_right = 110
	_hand_random_btn.offset_top = -30
	_hand_random_btn.offset_bottom = 30
	_hand_random_btn.pressed.connect(_on_random_play_pressed)
	_hand_random.add_child(_hand_random_btn)

	# 行动条（手牌区上方，左对齐；避免被地图/地点卡遮挡）
	_action_box = HBoxContainer.new()
	_action_box.position = Vector2(20, 760)
	_action_box.add_theme_constant_override("separation", 8)
	add_child(_action_box)
	_token_box = HBoxContainer.new()
	_token_box.position = Vector2(20, 808)
	_token_box.add_theme_constant_override("separation", 6)
	add_child(_token_box)

	# 濒危地点：手牌区右侧 玩家牌组旁指示物区
	_endangered_side_box = HBoxContainer.new()
	_endangered_side_box.position = Vector2(980, 884)
	_endangered_side_box.add_theme_constant_override("separation", 8)
	_endangered_side_box.visible = false
	add_child(_endangered_side_box)

	# 日志区域背景框（左侧中部，反派框下方）
	var log_bg := Panel.new()
	log_bg.position = Vector2(15, 292)
	log_bg.size = Vector2(490, 440)
	log_bg.add_theme_stylebox_override("panel", UiKit.box_style(Color(0.14, 0.14, 0.2, 0.85), Color(0.45, 0.55, 0.7, 0.8)))
	add_child(log_bg)
	var l_label := UiKit.label("行动日志", 17, Color(0.8, 0.9, 1))
	l_label.position = Vector2(7, 8)
	log_bg.add_child(l_label)
	_log_scroll = ScrollContainer.new()
	_log_scroll.position = Vector2(5, 36)
	_log_scroll.custom_minimum_size = Vector2(470, 390)
	log_bg.add_child(_log_scroll)
	_log_box = VBoxContainer.new()
	_log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_box.add_theme_constant_override("separation", 2)
	_log_scroll.add_child(_log_box)

	# 弹窗层（CanvasLayer=100：所有对话框永远在主界面之上）
	_popup = PopupLayer.new()
	add_child(_popup)

	# 放大预览层（CanvasLayer=50：在主界面之上、弹窗之下；动态重建的图标不会盖住它）
	_zoom_layer = CanvasLayer.new()
	_zoom_layer.layer = 50
	add_child(_zoom_layer)
	# 卡片动画层：放在主场景根下（与手牌/故事情节处于同一坐标系，坐标才不会错乱），z_index 置顶显示
	_card_anim_root = Control.new()
	_card_anim_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_anim_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_anim_root.z_index = 100
	add_child(_card_anim_root)
	_zoom_panel = TextureRect.new()
	_zoom_panel.anchor_left = 0.0
	_zoom_panel.anchor_top = 0.0
	_zoom_panel.anchor_right = 0.0
	_zoom_panel.anchor_bottom = 0.0
	_zoom_panel.offset_left = 0.0
	_zoom_panel.offset_top = 0.0
	_zoom_panel.offset_right = 0.0
	_zoom_panel.offset_bottom = 0.0
	_zoom_panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_zoom_panel.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_zoom_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zoom_panel.visible = false
	_zoom_layer.add_child(_zoom_panel)

	# 坐标显示（F3 切换，调试用：查看鼠标位置与面板相对比例）
	_coord_label = UiKit.label("", 16, Color(1, 1, 0.5))
	_coord_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_coord_label.add_theme_constant_override("outline_size", 3)
	_coord_label.position = Vector2(20, 20)
	_coord_label.visible = false
	add_child(_coord_label)

func _process(_delta: float) -> void:
	# 动画4：检测反派出牌展示请求（game 阻塞等待中）→ 弹窗展示 → 完成后恢复回合
	var pend_rv: int = int(Game.state.get("pending_villain_reveal", -1))
	if pend_rv >= 0 and not _revealing_villain:
		_revealing_villain = true
		_popup.show_villain_reveal(pend_rv, func():
			_revealing_villain = false
			Game._villain_reveal_done())
	# 放大预览跟随鼠标（画布坐标，实时贴合）
	if _zoom_panel != null and _zoom_panel.visible:
		_update_zoom_position()
	# 坐标显示（F3）
	if _show_coords:
		var mp := get_global_mouse_position()
		var txt := "鼠标: (%.0f, %.0f)" % [mp.x, mp.y]
		if _villain_panel != null:
			var lp := _villain_panel.get_global_rect()
			if lp.has_point(mp):
				var rel := (mp - lp.position) / lp.size
				txt += " ｜ 面板比例: (%.2f, %.2f)" % [rel.x, rel.y]
		_coord_label.text = txt
		_coord_label.visible = true

# ================================================================ 地点详情

## 点击地点 → 显示地点详情（含回合结束效果/威胁效果）
func _on_location_clicked(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_show_location_info(i)

func _show_location_info(i: int) -> void:
	var l: Dictionary = Game.state["locations"][i]
	var lines: Array = ["【%s】" % DB.location_name(l["id"])]
	var parts: Array = []
	if l["civ"] > 0:
		parts.append("平民 ×%d" % l["civ"])
	if l["thug"] > 0:
		parts.append("暴徒 ×%d" % l["thug"])
	if l["crisis"] > 0:
		parts.append("危机 ×%d" % l["crisis"])
	if parts.size() > 0:
		lines.append("指示物：" + "  ".join(parts))
	else:
		lines.append("指示物：无")
	lines.append("")
	lines.append("【地点回合结束效果】")
	lines.append(DB.location(l["id"])["end_turn"]["text"])
	lines.append("（英雄回合结束停留在此处且无威胁卡时触发）")
	if l["threat"] != null:
		var t: Dictionary = l["threat"]
		lines.append("")
		lines.append("【威胁卡：%s】" % t["name"])
		lines.append(t["text"])
		if t["hp"] > 0:
			lines.append("爪牙生命：%d" % t["hp"])
		elif t.has("clear"):
			var filled: Array = t.get("clear_progress", [])
			lines.append("清除符号进度：%d / %d" % [filled.size(), t["clear"].size()])
		elif t.get("heroic_tokens", 0) > 0:
			lines.append("英勇指示物：%d / 3" % t["heroic_tokens"])
		lines.append("（清除威胁后才能使用此地点效果）")
	_popup.show_info("\n".join(lines))

# ================================================================ 刷新

func _refresh_all() -> void:
	if Game.state.is_empty():
		return
	_sync_log()          # 日志以 state["log"] 为准（联机时客户端靠快照同步）
	_refresh_mp_peers()  # 联机：右下角队友手牌张数
	# 无限战争：能量卡是全场公共资源（大家一起填），联机时客户端必须每次都按
	# 快照重绘——以前只在 _refresh_villain 的某条分支里刷新，客户端常常刷不到。
	if String(Game.state.get("mode", "")) == "iw":
		_refresh_energy_cards(Game.state)
		_refresh_energy_done(Game.state)
		# 联机诊断：客户端把它"实际收到的"公共能量卡填充状态写进游戏日志（内容变化时才写），
		# 便于一眼看出是"没收到"还是"收到了但没画出来"。
		if Net.active and not Net.is_host:
			var et: String = str(Game.state.get("energy_tokens", {}))
			if et != _dbg_energy_last:
				_dbg_energy_last = et
				print("[诊断] 客户端能量卡填充状态：%s" % et)
	_refresh_villain()
	if String(Game.state.get("mode", "")) == "s6":
		_refresh_missions()          # s6 不用任务卡：下面会隐藏任务栏
		if _mission_box != null:
			_mission_box.visible = false
		_refresh_s6_center(Game.state)
	else:
		_refresh_missions()
		if _mission_box != null:
			_mission_box.visible = true
		_hide_s6_center()
	_refresh_locations()
	_refresh_story()
	_refresh_hand()
	_refresh_actions()
	_refresh_phase()
	_refresh_hero_badges()
	_refresh_eliminated()
	_refresh_energy_stack(Game.state)
	_refresh_endangered_side()

func _clear_children(container: Node) -> void:
	for c in container.get_children():
		container.remove_child(c)
		c.queue_free()

# ================================================================ 联机：队友手牌张数（屏幕右下角）

## 联机时在右下角挂一个小面板。用户要求：队友的手牌看不见，但要看得到"有几张"。
func _build_mp_peers() -> void:
	if not Net.active or _mp_peers_box != null:
		return
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(0.10, 0.10, 0.16, 0.90)))
	panel.anchor_left = 1.0
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -320.0
	panel.offset_top = -160.0
	panel.offset_right = -18.0
	panel.offset_bottom = -18.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_mp_peers_box = VBoxContainer.new()
	_mp_peers_box.add_theme_constant_override("separation", 6)
	panel.add_child(_mp_peers_box)

func _refresh_mp_peers() -> void:
	if _mp_peers_box == null:
		return
	_clear_children(_mp_peers_box)
	var t := UiKit.label("队友手牌", 18, Color(1, 0.9, 0.5))
	_mp_peers_box.add_child(t)
	var shown := 0
	for i in range(Net.seats.size()):
		var s: Variant = Net.seats[i]
		if s == null or int(s["peer"]) == Net.my_peer:
			continue
		var hero := String(s.get("hero", ""))
		if hero == "":
			continue
		var n := 0
		if (Game.state.get("heroes", {}) as Dictionary).has(hero):
			var h: Dictionary = Game.state["heroes"][hero]
			# 主机的 state 里就是真手牌；客户端拿到的是裁剪过的快照，用 hand_count
			n = int(h.get("hand_count", (h.get("hand", []) as Array).size()))
		# 一行 = 英雄图标（卡背）+ 名字 + 张数
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_mp_peers_box.add_child(row)
		var ic := TextureRect.new()
		ic.texture = load(DB.hero_back(hero))
		ic.custom_minimum_size = Vector2(34, 46)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ic)
		var gone: String = "（已退出·房主代管）" if bool(s.get("disconnected", false)) else ""
		var lb := UiKit.label("P%d %s：%d 张%s" % [i + 1, String(s.get("name", "")), n, gone], 16, Color(0.92, 0.96, 1))
		lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(lb)
		shown += 1
	if shown == 0:
		_mp_peers_box.add_child(UiKit.label("（暂无其他玩家）", 16, Color(0.8, 0.8, 0.9)))

## "现在能用的顶牌 idx"：不可公开 / 没有合法 idx / idx 越界 / s6 → -1。
## - 联机客户端只认 state 里的 villain_top_public / villain_top_idx（主机下发；快照里
##   master_deck 已被裁成空数组）——**客户端绝不读 master_deck**。
## - 单机 / 主机自己的界面：本地状态里没有这两个下发字段 → 本地直接算（同一口径）。
func _villain_top_idx_for(st: Dictionary) -> int:
	var pub := false
	var tidx := -1
	if st.has("villain_top_public"):
		pub = bool(st.get("villain_top_public", false))
		tidx = int(st.get("villain_top_idx", -1))
	elif not Net.active or Net.is_host:
		pub = Game._villain_top_public_now()
		tidx = Game._next_villain_action_from_top() if pub else -1
	if not pub:
		return -1
	# 邪恶六人组模式没有"主计划牌堆"（用它自己那套行动卡），不做顶牌公开
	if String(st.get("mode", "base")) == "s6":
		return -1
	var vid: String = String(st.get("villain", ""))
	if tidx < 0 or vid == "" or not DB.villains.has(vid):
		return -1
	if tidx >= (DB.villain(vid).get("actions", []) as Array).size():
		return -1      # 越界（数据坏了/被改了）：宁可什么都不显示，也不要崩
	return tidx

## 裁定③（新口径）：阿戈摩托之球把"反派牌堆顶那张行动牌"**贴卡图**公开在反派牌堆右侧。
## - 返回 true = 卡图已显示（调用方据此关掉文字提示，避免文字 + 卡图并存）。
## - 失效（离开可见区）与"顶牌变了"由本函数每次刷新时重算：idx 变了就换贴图，失效就隐藏。
func _refresh_villain_top_card(st: Dictionary) -> bool:
	if _villain_top_card == null:
		return false
	var tidx: int = _villain_top_idx_for(st)
	var tex: Texture2D = null
	if tidx >= 0:
		tex = load(UiKit.villain_action_image(String(st.get("villain", "")), tidx))
	if tex == null:
		# 不可公开 / 缺图 → 不显示（文字提示由调用方兜底）
		_villain_top_card.visible = false
		_villain_top_card.texture = null
		if _zoom_panel != null and _zoom_panel.visible:
			_zoom_hide()
		return false
	# 顶牌换了 → 贴图跟着换（复用同一个节点，不重建）
	if _villain_top_card.texture != tex:
		_villain_top_card.texture = tex
		if _zoom_panel != null and _zoom_panel.visible:
			_zoom_show(_villain_top_card)   # 正在放大看时顶牌变了 → 放大图同步换成新牌
	_villain_top_card.visible = true
	return true

func _refresh_villain() -> void:
	var st: Dictionary = Game.state
	if String(st.get("mode", "")) == "s6":
		_refresh_s6_panel(st)
		return
	var vid: String = st["villain"]
	_villain_bg.size = Vector2(410, 272)   # 非 s6 模式恢复原尺寸
	_villain_panel.visible = true
	_hp_label.visible = true
	_villain_panel.texture = load(DB.villain_image(vid))
	# 反派牌堆数量（与英雄牌库显示一致：背面图标 + 数字）
	if _villain_deck_icon != null:
		_villain_deck_icon.texture = load(DB.villain(vid)["back"])
		_villain_deck_num.text = "%d" % int(st.get("master_deck_count", (st.get("master_deck", []) as Array).size()))
	_hp_label.text = "%d / %d" % [st["villain_hp"], st["villain_hp_max"]]
	var track: String = DB.villain(vid).get("plot_track", "")
	if track == "fear":
		_fear_bar.visible = true
		_fear_bar.max_value = DB.villain(vid).get("fear_track_max", 20)
		_fear_bar.value = st["fear"]
		_fear_label.visible = true
		_fear_label.text = "恐惧轨道：%d / %d" % [st["fear"], DB.villain(vid).get("fear_track_max", 20)]
		_ko_icon.visible = false
	elif track == "slaughter":
		# 暗夜比邻星屠宰轨道：0 / 1-12，到达 12 英雄失败
		_fear_bar.visible = true
		_fear_bar.max_value = 12
		_fear_bar.value = st.get("slaughter", 0)
		_fear_label.visible = true
		_fear_label.text = "屠宰轨道：%d / 12" % st.get("slaughter", 0)
		_ko_icon.visible = false
	elif track == "loot":
		# 秃鹫战利品：2/3/4 人 = 9/7/5 个即英雄失败
		var loot_max: int = 5 if st["hero_ids"].size() >= 4 else (7 if st["hero_ids"].size() == 3 else 9)
		_fear_bar.visible = true
		_fear_bar.max_value = loot_max
		_fear_bar.value = st.get("vulture_loot", 0)
		_fear_label.visible = true
		_fear_label.text = "🦅 战利品：%d / %d" % [st.get("vulture_loot", 0), loot_max]
		_ko_icon.visible = false
	elif track == "destroyed":
		# 章鱼博士：地点摧毁进度（4 个及以上即英雄失败）
		var dcount := 0
		for _dl in st["locations"]:
			if _dl.get("destroyed", false):
				dcount += 1
		_fear_bar.visible = true
		_fear_bar.max_value = 4
		_fear_bar.value = dcount
		_fear_label.visible = true
		_fear_label.text = "🏚 已摧毁地点：%d / 4" % dcount
		_ko_icon.visible = false
	elif track == "ko":
		# KO 指示物计数：罗南累计 4 个失败；亡刃将军累计 == 英雄数失败
		var ko_max: int = st["hero_ids"].size() if vid == "corvus" else 4
		_fear_bar.visible = true
		_fear_bar.max_value = ko_max
		_fear_bar.value = st.get("ko_tokens", 0)
		_fear_label.visible = true
		_fear_label.text = "KO 指示物：%d / %d" % [st.get("ko_tokens", 0), ko_max]
		_ko_icon.visible = true
	elif track == "allko":
		# 猎人克莱文：英雄们"同一时间"全部被击倒即失败
		var kcount := 0
		for _hid in st["hero_ids"]:
			if st["heroes"][_hid]["ko"]:
				kcount += 1
		_fear_bar.visible = true
		_fear_bar.max_value = maxi(st["hero_ids"].size(), 1)
		_fear_bar.value = kcount
		_fear_label.visible = true
		_fear_label.text = "💀 同时 KO：%d / %d（全部同时 KO 即失败）" % [kcount, st["hero_ids"].size()]
		_ko_icon.visible = true
	elif track == "hp":
		# 沙人：生命值达到 20 即英雄失败（生命值可超过上限）
		_fear_bar.visible = true
		_fear_bar.max_value = 20
		_fear_bar.value = mini(int(st["villain_hp"]), 20)
		_fear_label.visible = true
		_fear_label.text = "🏖 沙人生命值：%d / 20（达到 20 即失败）" % int(st["villain_hp"])
		_ko_icon.visible = false
	elif track == "crisis":
		# 电光人：所有地点都有危机指示物即英雄失败
		var ccount := 0
		var ctotal := 0
		for _cl in st["locations"]:
			if _cl.get("destroyed", false):
				continue
			ctotal += 1
			if int(_cl["crisis"]) > 0:
				ccount += 1
		_fear_bar.visible = true
		_fear_bar.max_value = maxi(ctotal, 1)
		_fear_bar.value = ccount
		_fear_label.visible = true
		_fear_label.text = "⚡ 有危机的地点：%d / %d（全部都有即失败）" % [ccount, ctotal]
		_ko_icon.visible = false
	else:
		_fear_bar.visible = false
		_fear_label.visible = false
		_ko_icon.visible = false
	# 绿魔：绑架到反派面板的平民指示物（按顺序显示在反派面板下方空白处）
	if vid == "goblin":
		for c in _goblin_civ_box.get_children():
			_goblin_civ_box.remove_child(c)
			c.queue_free()
		var civ_n: int = int(st.get("goblin_panel_civ", 0))
		for k in range(civ_n):
			var tr := TextureRect.new()
			tr.texture = _icon_civ
			tr.custom_minimum_size = Vector2(22, 22)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_goblin_civ_box.add_child(tr)
		_goblin_civ_box.visible = true
	else:
		_goblin_civ_box.visible = false
	# 红骷髅：蓝色方块指示恐惧位置（面板三排轨道：0 / 1-10 / 11-20）
	if vid == "redskull":
		_fear_marker.visible = true
		var f: int = st["fear"]
		var px: float
		var py: float
		if f <= 0:
			px = REDSKULL_TRACK_X0
			py = REDSKULL_TRACK_Y0
		elif f <= 10:
			px = REDSKULL_TRACK_XS[f - 1]
			py = REDSKULL_TRACK_Y1
		else:
			px = REDSKULL_TRACK_XS[f - 11]
			py = REDSKULL_TRACK_Y2
		_fear_marker.position = Vector2(px, py) - Vector2(4.5, 4.5)
	else:
		_fear_marker.visible = false

func _refresh_missions() -> void:
	_clear_children(_mission_box)
	for m in Game.state["missions"]:
		var mv := MissionView.new()
		mv.setup(m, _mission_textures, _mission_icon_tex(m["id"]))
		_mission_box.add_child(mv)

func _mission_icon_tex(mid: String) -> Texture2D:
	match mid:
		"rescue":
			return _icon_civ
		"defeat":
			return _icon_thug
		_:
			return _icon_threat

func _refresh_locations() -> void:
	for lv in _loc_views:
		lv.refresh(Game.state)

## 无限战争战役：局间过渡。胜利 → 下一局（前3局）/ 战役胜利（决战）；
## 失败 → 前3局战败宝石落入灭霸手中继续下一局 / 决战失败战役失败。
func _on_game_over(victory: bool, reason: String) -> void:
	var iw: bool = Game.state.get("mode", "base") == "iw"
	var is_final: bool = Game.state.get("final_battle", false)
	var campaign: Variant = Game.state.get("campaign", null)
	if campaign == null:
		campaign = {}
	if iw:
		var stones: int = campaign.get("stones_collected", []).size()
		var game_no: int = int(campaign.get("game", 1))
		if is_final:
			# 决战结束：战役结束
			_popup.show_game_over(victory, reason)
			return
		# 前 3 局结束：显示战役进度 + 下一局按钮
		var extra := "【战役进度】第 %d/3 局前哨战结束 ｜ 灭霸已收集宝石 %d/6 颗\n%s" % [game_no, stones, reason]
		if not victory:
			extra += "\n（本局埋入的宝石已全部落入灭霸手中）"
		# 联机：由房主决定何时开下一局，客户端不给按钮（点了也没用）
		var _next_cb := Callable(self, "_start_next_campaign_game")
		if Net.active and not Net.is_host:
			_next_cb = Callable()
		_popup.show_game_over(victory, extra, _next_cb)
		return
	_popup.show_game_over(victory, reason)

## 开始下一局战役：更新 campaign 局数并重新 setup
func _start_next_campaign_game() -> void:
	if Net.active:
		Net.host_next_campaign_game()   # 联机：房主广播下一局，全场一起重开
		return
	var c: Dictionary = Game.pending_campaign
	c["game"] = int(c.get("game", 1)) + 1
	Game.pending_campaign = c
	Game.pending_setup["campaign_order"] = c["order"]
	# 决战（第 4 局）：固定灭霸 + 专属地点；前 3 局：顺序取对应反派
	var game_no: int = int(c["game"])
	var vid: String = "thanos" if game_no >= 4 else String(c["order"][game_no - 1])
	Game.pending_setup["villain"] = vid
	if game_no >= 4:
		Game.pending_setup["expansions"] = ["无限战争决战"]
	get_tree().reload_current_scene()

# 红骷髅恐惧轨道（面板内像素坐标，实测扫描：0(133,93)、1-10排y=115、11-20排y=135、
# x 位置按面板实际方块 [134,157,183,206,231,256,280,305,329,351]）
const REDSKULL_TRACK_XS := [134.0, 157.0, 183.0, 206.0, 231.0, 256.0, 280.0, 305.0, 329.0, 351.0]
const REDSKULL_TRACK_X0 := 133.0
const REDSKULL_TRACK_Y0 := 93.0
const REDSKULL_TRACK_Y1 := 115.0
const REDSKULL_TRACK_Y2 := 135.0

func _refresh_story() -> void:
	_clear_children(_story_box)
	var entries: Array = Game.state["story"]
	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(46, 64)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# 固定为卡图本身的大小（竖直居中）——这样"卡上叠加图标"的坐标就以卡图为基准，
		# 不受故事情节条 92px 高度的影响（视觉与原先 KEEP_ASPECT_CENTERED 一致）
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if e["type"] == "hero":
			if e.get("face_down", false):
				# 英雄行动牌面朝下：显示卡背面（下一个英雄无法从它获得行动）
				tr.texture = load(DB.hero_back(e["hero"]))
			else:
				tr.texture = load(UiKit.hero_card_image(e["hero"], e["idx"]))
		else:
			# 反派行动牌：面朝下显示行动牌背面（英雄看不到是哪张）；否则显示正面
			var s6_story: bool = String(Game.state.get("mode", "")) == "s6"
			if e.get("face_down", false) or e.get("idx", -1) < 0:
				tr.texture = load("res://assets/cards/s6/action_back.png") if s6_story else load(DB.villain(Game.state["villain"])["back"])
			else:
				tr.texture = load("res://assets/cards/s6/action_%02d.png" % (int(e["idx"]) + 1)) if s6_story else load(UiKit.villain_action_image(Game.state["villain"], e["idx"]))
		_bind_zoom(tr)
		# 泽莫男爵（裁定⑥）：被危机指示物盖住的行动符号，直接把小危机指示物图标画在这张卡上
		if e["type"] == "hero" and not e.get("face_down", false) and (e.get("covered", []) as Array).size() > 0:
			_add_story_covered_marks(tr, e, e["covered"])
		_story_box.add_child(tr)
	# 故事情节在下一帧布局后才更新内容宽度；延迟一帧再滚到最右（最新），避免被钳制后回升
	if is_instance_valid(_story_scroll):
		_scroll_story_to_latest()

func _scroll_story_to_latest() -> void:
	await get_tree().process_frame
	_story_scroll.scroll_horizontal = _story_scroll.get_h_scroll_bar().max_value

## 泽莫男爵（裁定⑥）：在故事情节卡的"被危机指示物盖住"的行动符号位置上，画一个小危机指示物图标。
## 位置按卡面实测推导（英雄行动卡为竖版卡）：
##   · 底部行动符号带中心在卡高的 85% 处（卡图 853×1198 / 显示 46×64 同比例）；
##   · n 个符号以卡宽中心对称、间距 30% 卡宽（实测：1 个符号→正中；2 个→0.35 / 0.65 卡宽）。
## 卡框固定为 custom_minimum_size（_refresh_story 里已把 TextureRect 收成卡图大小），
## 因此图标坐标可直接以卡图左上角为原点。
func _add_story_covered_marks(tr: TextureRect, entry: Dictionary, covered: Array) -> void:
	var total: int = (DB.hero_cards(String(entry["hero"]))[int(entry["idx"])]["symbols"] as Array).size()
	var n: int = maxi(total, 1)
	var w: float = tr.custom_minimum_size.x
	var h: float = tr.custom_minimum_size.y
	var icon: float = 8.0
	for c in covered:
		var k: int = int(c)
		var cx: float = w * 0.5 + (float(k) - float(n - 1) * 0.5) * (w * 0.30)
		var cy: float = h * 0.85
		var mark := TextureRect.new()
		mark.texture = _icon_crisis
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.size = Vector2(icon, icon)
		mark.position = Vector2(cx - icon * 0.5, cy - icon * 0.5)
		tr.add_child(mark)

func _refresh_hand() -> void:
	_clear_children(_hand_box)
	var phase: String = Game.state["phase"]
	var shield: bool = Game.state.get("mode", "base") == "shield"
	# 切换英雄手牌按钮（非官方功能，设置中开启后可用；神盾局共享手牌无需切换）
	var peek_on: bool = _setup.get("peek_hands", false) and not shield
	_peek_prev.visible = peek_on and phase != "game_over"
	_peek_next.visible = peek_on and phase != "game_over"
	if phase == "game_over":
		_hand_label.text = ""
		return
	var cur_hid: String = Game.current_hero_id()
	# 联机（bug2）：手牌区固定显示"我自己的英雄"，不是当前行动英雄。
	# 但若当前英雄的玩家退出了、由房主代管（bug3），房主这边要显示那个英雄的手牌，操作才一致。
	if Net.active and Net.controlling_hero() != "":
		cur_hid = Net.controlling_hero()
	# 新英雄回合（含抽牌阶段）开始时，预览自动回到当前行动英雄
	if (phase == "hero_play" or phase == "hero_draw") and _peek_hero != "" and _peek_hero != cur_hid:
		_peek_hero = ""
	var hid: String = cur_hid
	if _peek_hero != "" and Game.state["heroes"].has(_peek_hero):
		hid = _peek_hero
	var h: Dictionary = Game.state["heroes"][hid]
	hand_hero_id = hid          # 供测试/联机核对：手牌区当前显示的是谁的牌
	var previewing: bool = hid != cur_hid
	# —— 抽牌翻牌动画：检测本次刷新相对上次新抽入展示手牌（非 setup / 非预览 / 非自动时播放）——
	var disp_ctx := ""
	var combos: Array = []
	if shield:
		disp_ctx = "shield"
		for cc in Game.state["shield_hand"]:
			combos.append("%s/%d" % [cc["hero"], int(cc["idx"])])
	else:
		disp_ctx = "h:" + hid
		for ci in h["hand"]:
			combos.append("%d" % int(ci))
	var newly: Array = []
	if not Game.autopilot and not previewing and phase != "setup":
		newly = _diff_draw_new(disp_ctx, combos)
	if shield:
		# 神盾局：显示共享手牌（每张标注所属英雄），牌堆=共享牌组
		var shield_hand: Array = Game.state["shield_hand"]
		_hand_label.text = "神盾局共享手牌（%d 张）— 当前英雄：%s" % [shield_hand.size(), DB.hero_name(cur_hid)]
		_hand_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1))
		_clear_children(_deck_info)
		var back := TextureRect.new()
		back.texture = _hero_icons.get(cur_hid)
		back.custom_minimum_size = Vector2(38, 52)
		back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_deck_info.add_child(back)
		var dk := UiKit.label("%d" % Game.state["shield_deck"].size(), 17, Color.WHITE)
		dk.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		dk.add_theme_constant_override("outline_size", 4)
		dk.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		dk.position = Vector2(0, 30)
		dk.custom_minimum_size = Vector2(36, 20)
		_deck_info.add_child(dk)
		_clear_children(_token_info_box)
		# 神盾局：行动指示物共享给玩家（任意英雄都能用）
		var stk: Dictionary = Game.state.get("shield_tokens", {})
		var tk_icons_s := [_icon_move, _icon_attack, _icon_heroic, _icon_wild]
		var tk_keys_s := ["move", "attack", "heroic", "wild"]
		for i in range(4):
			var vb := HBoxContainer.new()
			vb.add_theme_constant_override("separation", 3)
			vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var ic := TextureRect.new()
			ic.custom_minimum_size = Vector2(22, 22)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.texture = tk_icons_s[i]
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vb.add_child(ic)
			var lb := UiKit.label("×%d" % int(stk.get(tk_keys_s[i], 0)), 15, Color(0.95, 0.9, 0.7))
			vb.add_child(lb)
			_token_info_box.add_child(vb)
		var playable_shield := phase == "hero_play"
		var s_nodes: Array = []
		for i in range(shield_hand.size()):
			var card: Dictionary = shield_hand[i]
			var box := Control.new()
			box.custom_minimum_size = Vector2(88, 124)
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var tr := TextureRect.new()
			tr.custom_minimum_size = Vector2(82, 115)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.texture = load(UiKit.hero_card_image(card["hero"], card["idx"]))
			tr.position = Vector2(3, 0)
			_bind_zoom(tr)
			_bind_hand_card_anim(tr)
			if playable_shield:
				tr.gui_input.connect(_on_hand_card_input.bind(i, tr))
			tr.mouse_filter = Control.MOUSE_FILTER_STOP if playable_shield else Control.MOUSE_FILTER_PASS
			box.add_child(tr)
			var tag := UiKit.label(DB.hero_name(card["hero"])[0], 11, DB.hero_color(card["hero"]))
			tag.add_theme_color_override("font_outline_color", Color(0, 0, 0))
			tag.add_theme_constant_override("outline_size", 3)
			tag.position = Vector2(3, 96)
			tag.custom_minimum_size = Vector2(30, 16)
			box.add_child(tag)
			_hand_box.add_child(box)
			s_nodes.append(tr)
		if newly.size() > 0:
			_flip_drawn_cards(shield_hand, combos, newly, s_nodes,
				func(card): return load(DB.hero_back(card["hero"])),
				func(card): return load(UiKit.hero_card_image(card["hero"], int(card["idx"]))))
		_hand_disp_ctx = disp_ctx
		_hand_disp_combos = combos
		return
	_hand_label.text = "手牌：%s（%d 张）%s" % [DB.hero_name(hid), h["hand"].size(), "— 预览" if previewing else ""]
	_hand_label.add_theme_color_override("font_color", DB.hero_color(hid))
	# 牌堆剩余数量（行动牌背面图标 + 数字叠加）
	_clear_children(_deck_info)
	var back := TextureRect.new()
	back.texture = _hero_icons.get(hid)
	back.custom_minimum_size = Vector2(38, 52)
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deck_info.add_child(back)
	var dk := UiKit.label("%d" % h["deck"].size(), 17, Color.WHITE)
	dk.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	dk.add_theme_constant_override("outline_size", 4)
	dk.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dk.position = Vector2(0, 30)
	dk.custom_minimum_size = Vector2(36, 20)
	_deck_info.add_child(dk)
	# 叛徒模式：牌堆旁放一张"身份牌背面"，点击可随时（热座自己）查看该英雄的真实身份
	if Game.state.get("challenge", "") == "traitor" and is_instance_valid(_popup):
		var idt := TextureRect.new()
		idt.texture = load("res://assets/cards/modes/traitor/back.jpg")
		idt.custom_minimum_size = Vector2(44, 60)
		idt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		idt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		idt.position = Vector2(46, 0)
		idt.mouse_filter = Control.MOUSE_FILTER_STOP
		idt.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_popup.show_identity(hid, Game.state["loyalty"].get(hid, "") == "traitor", true))
		_deck_info.add_child(idt)
	# 手牌区右侧：该英雄拥有的行动指示物数量
	_clear_children(_token_info_box)
	var tk: Dictionary = h["tokens"]
	var tk_icons := [_icon_move, _icon_attack, _icon_heroic, _icon_wild]
	var tk_keys := ["move", "attack", "heroic", "wild"]
	for i in range(4):
		var vb := HBoxContainer.new()
		vb.add_theme_constant_override("separation", 3)
		vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var ic := TextureRect.new()
		ic.custom_minimum_size = Vector2(22, 22)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture = tk_icons[i]
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(ic)
		var lb := UiKit.label("×%d" % int(tk[tk_keys[i]]), 15, Color(0.95, 0.9, 0.7))
		vb.add_child(lb)
		_token_info_box.add_child(vb)
	# 叛徒模式：显示该英雄的"不信任指示物"数量
	if Game.state.get("challenge", "") == "traitor":
		var dist: int = int(h.get("distrust", 0))
		if dist > 0:
			var dvb := HBoxContainer.new()
			dvb.add_theme_constant_override("separation", 3)
			dvb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var dic := TextureRect.new()
			dic.custom_minimum_size = Vector2(22, 22)
			dic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			dic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			dic.texture = load("res://assets/tokens/distrust_token.png")
			dic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dvb.add_child(dic)
			var dlb := UiKit.label("×%d" % dist, 15, Color(0.95, 0.8, 0.9))
			dvb.add_child(dlb)
			_token_info_box.add_child(dvb)
	var playable := phase == "hero_play" and not previewing
	# 乌木侯控制：随机出牌（暗色遮罩 + 居中"随机出牌"按钮），玩家不可逐张选
	var controlled: bool = phase == "hero_play" and Game.state.get("random_play", false) and not Game.state.get("iw_mind_active", false) and not previewing
	if _hand_random != null:
		_hand_random.visible = controlled
	for i in range(h["hand"].size()):
		var card_idx: int = h["hand"][i]
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(82, 115)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture = load(UiKit.hero_card_image(hid, card_idx))
		_bind_zoom(tr)
		_bind_hand_card_anim(tr)
		if playable and not controlled:
			tr.gui_input.connect(_on_hand_card_input.bind(i, tr))
		tr.mouse_filter = Control.MOUSE_FILTER_STOP if (playable and not controlled) else Control.MOUSE_FILTER_PASS
		_hand_box.add_child(tr)
	if newly.size() > 0:
		var n_nodes: Array = []
		for i in range(combos.size()):
			n_nodes.append(_hand_box.get_child(i))
		_flip_drawn_cards(h["hand"], combos, newly, n_nodes,
			func(_ci): return load(DB.hero_back(hid)),
			func(ci): return load(UiKit.hero_card_image(hid, int(ci))))
	_hand_disp_ctx = disp_ctx
	_hand_disp_combos = combos

func _on_hand_card_input(event: InputEvent, hand_idx: int, tr: TextureRect) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Game.play_card(hand_idx)

# ================================================================ 抽牌翻牌动画

## 与上次刷新同上下文时，找出本次新出现（被抽入）的手牌组合；上下文切换/首次显示返回空
func _diff_draw_new(ctx: String, combos: Array) -> Array:
	if _hand_disp_ctx == "" or ctx != _hand_disp_ctx:
		return []
	var newly: Array = []
	for cmb in combos:
		if not _hand_disp_combos.has(cmb):
			newly.append(cmb)
	return newly

## 对新抽入的每张卡播放"背面→正面"翻牌动画：直接翻转那张落位的手牌卡本体
## （仅 x 轴翻面，尺寸不变不放大）；纯视觉、不阻塞、多张依次播放。
func _flip_drawn_cards(entries: Array, combos: Array, newly: Array, nodes: Array,
		back_for: Callable, face_for: Callable) -> void:
	var order := 0
	for i in range(entries.size()):
		if not newly.has(combos[i]):
			continue
		var anchor: TextureRect = nodes[i]
		if not is_instance_valid(anchor):
			continue
		var back_tex: Texture2D = back_for.call(entries[i])
		var face_tex: Texture2D = face_for.call(entries[i])
		if back_tex == null or face_tex == null:
			continue
		_play_card_flip(anchor, back_tex, face_tex, 0.12 + order * 0.35)
		order += 1

func _play_card_flip(anchor: TextureRect, back_tex: Texture2D, face_tex: Texture2D, delay: float) -> void:
	# 直接把这张真卡翻面：仅 x 轴翻转（宽 1→0.02→1，y 与整体尺寸完全不变，绝不放大）
	# 等一帧让容器完成本次布局（拿到落位/尺寸）再开始翻
	if _hover_card == anchor:
		_hover_card = null
		if is_instance_valid(_hand_tween):
			_hand_tween.kill()
	var orig_filter := anchor.mouse_filter
	anchor.texture = back_tex
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 翻牌期间不可点击/不可悬停
	anchor.scale = Vector2.ONE
	anchor.rotation = 0.0
	await get_tree().process_frame
	if not is_instance_valid(anchor):
		return
	anchor.pivot_offset = anchor.size * 0.5
	var tw := anchor.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(anchor, "scale:x", 0.02, 0.12)
	tw.tween_callback(func():
		if is_instance_valid(anchor):
			anchor.texture = face_tex)
	tw.tween_property(anchor, "scale:x", 1.0, 0.12)
	tw.tween_interval(0.1)
	tw.tween_callback(func():
		if is_instance_valid(anchor):
			anchor.mouse_filter = orig_filter
			anchor.scale = Vector2.ONE
			anchor.rotation = 0.0)

## 乌木侯控制：点击"随机出牌"按钮 → 随机打出一张手牌
func _on_random_play_pressed() -> void:
	Game.play_card(0)

## 绑定悬停放大：鼠标移入显示大图，移出隐藏（故事情节/手牌卡通用）
func _bind_zoom(tr: TextureRect) -> void:
	tr.mouse_entered.connect(_zoom_show.bind(tr))
	tr.mouse_exited.connect(_zoom_hide)

## 手牌卡悬停动画：卡片本体"果冻"放大 + 缓缓左右摇晃（纯视觉，不改游戏逻辑）
func _bind_hand_card_anim(tr: TextureRect) -> void:
	tr.pivot_offset = Vector2(tr.custom_minimum_size.x / 2.0, tr.custom_minimum_size.y / 2.0)
	tr.mouse_entered.connect(_hand_card_hover.bind(tr))
	tr.mouse_exited.connect(_hand_card_unhover.bind(tr))

func _hand_card_hover(tr: TextureRect) -> void:
	if is_instance_valid(_hand_tween):
		_hand_tween.kill()
	_hover_card = tr
	# 果冻放大：scale.x/y 先冲到 1.18 再回弹到 1.12（只做一次）
	_hand_tween = create_tween()
	_hand_tween.tween_property(tr, "scale", Vector2(1.18, 1.18), 0.09)
	_hand_tween.tween_property(tr, "scale", Vector2(1.12, 1.12), 0.07)
	# 缓缓左右摇晃：无限循环（用 set_loops，rotation 左→右→左… 一直往复直到鼠标离开）
	_hand_tween.tween_property(tr, "rotation", 0.05, 0.20)
	_hand_tween.tween_property(tr, "rotation", -0.05, 0.20)
	_hand_tween.set_loops()

func _hand_card_unhover(tr: TextureRect) -> void:
	if _hover_card == tr:
		_hover_card = null
	if is_instance_valid(_hand_tween):
		_hand_tween.kill()
	# 立即复位到原状（不依赖 tween 时序，保证离开一定恢复）
	tr.scale = Vector2.ONE
	tr.rotation = 0.0

func _zoom_show(tr: TextureRect) -> void:
	if tr.texture == null:
		return
	var tw: float = tr.texture.get_width()
	var th: float = tr.texture.get_height()
	var scale_f := 2.6
	var max_h := 460.0
	# 大图/方图（邪恶六人组仪表板 1100×1100 之类）给更大的预览，最多到 780px
	if minf(tw, th) >= 800.0:
		max_h = 780.0
	if th * scale_f > max_h:
		scale_f = max_h / th
	_zoom_panel.texture = tr.texture
	var zs := Vector2(tw * scale_f, th * scale_f)
	_zoom_base_size = zs          # 基准尺寸（滚轮在此基础上放大/缩小）
	_zoom_panel.visible = true
	_apply_zoom_size()            # 统一走这里：带"不超出屏幕"的上限
	# 放大预览在独立 CanvasLayer(50) 中，无需手动置顶

## 放大图位置：鼠标右下方 +24，超出屏幕自动翻转贴近鼠标
func _update_zoom_position() -> void:
	var zw: float = _zoom_panel.size.x
	var zh: float = _zoom_panel.size.y
	# 画布坐标必须用 get_global_mouse_position()（含完整画布变换）：
	# 视口坐标÷content_scale 仅在无黑边的标准 16:9 下精确，非 16:9 窗口会整体偏移。
	var mpos: Vector2 = get_global_mouse_position()
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

func _zoom_hide() -> void:
	_zoom_panel.visible = false
	_zoom_panel.texture = null

## 切换查看其他英雄手牌（非官方功能）
func _on_peek_prev() -> void:
	var ids: Array = Game.state["hero_ids"]
	var cur: int = ids.find(_peek_hero) if _peek_hero != "" else ids.find(Game.current_hero_id())
	_peek_hero = ids[wrapi(cur - 1, 0, ids.size())]
	_refresh_hand()

func _on_peek_next() -> void:
	var ids: Array = Game.state["hero_ids"]
	var cur: int = ids.find(_peek_hero) if _peek_hero != "" else ids.find(Game.current_hero_id())
	_peek_hero = ids[wrapi(cur + 1, 0, ids.size())]
	_refresh_hand()

func _refresh_actions() -> void:
	_clear_children(_action_box)
	_clear_children(_token_box)
	# 等待玩家输入（弹窗打开）时隐藏行动按钮：防止并发点击覆盖正在执行/待选的操作
	if Game.state.get("waiting_input", false):
		return
	var phase: String = Game.state["phase"]
	if phase != "hero_actions" and phase != "hero_play" and phase != "hero_end":
		return
	if phase == "hero_actions":
		var syms: Array = Game.available_symbols()
		var counts := {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
		var tokens := {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
		for s in syms:
			if s.begins_with("token_"):
				tokens[s.substr(6)] += 1
			else:
				counts[s] += 1
		for key in counts:
			var btn := UiKit.button("%s x%d" % [DB.symbol_name(key), counts[key]], _sym_color(key))
			btn.icon = _icon_for(key)
			btn.add_theme_constant_override("icon_max_width", 26)
			btn.disabled = counts[key] == 0
			btn.pressed.connect(Game.use_symbol.bind(key))
			_action_box.add_child(btn)
		for key in tokens:
			if tokens[key] > 0:
				var btn := UiKit.button("指示物·%s x%d" % [DB.symbol_name(key), tokens[key]], Color(0.4, 0.4, 0.6))
				btn.icon = _icon_for(key)
				btn.add_theme_constant_override("icon_max_width", 26)
				btn.pressed.connect(Game.use_symbol.bind("token_" + key))
				_token_box.add_child(btn)
		if Game.state.get("effect_available", false) and not Game.state.get("effect_used", false):
			var ebtn := UiKit.button("卡牌效果", Color(0.6, 0.5, 0.2))
			ebtn.pressed.connect(Game.trigger_effect)
			_action_box.add_child(ebtn)
		# 神秘客：可花费 1 个任意行动翻开一张背面朝上的威胁卡
		if Game.state.get("villain", "") == "mysterio":
			var any_fd := false
			for _fl in range(Game.LOCATION_COUNT):
				var _ft: Variant = Game.state["locations"][_fl]["threat"]
				if _ft != null and _ft.get("_face_down", false):
					any_fd = true
					break
			if any_fd:
				var rbtn := UiKit.button("翻开背面威胁卡", Color(0.4, 0.45, 0.7))
				rbtn.pressed.connect(Game.reveal_threat_choice)
				_action_box.add_child(rbtn)
		# 秘密身份挑战：可花费 1 个任意行动把任意记者指示物挪到相邻地点（不产生曝光）
		if Game.state.get("challenge", "") == "secretid":
			var has_reporter := false
			for _rl in range(Game.LOCATION_COUNT):
				if Game.state["locations"][_rl].get("reporter", false):
					has_reporter = true
					break
			if has_reporter:
				var mbtn := UiKit.button("移动记者指示物", Color(0.5, 0.4, 0.25))
				mbtn.icon = load("res://assets/tokens/reporter_token.png")
				mbtn.add_theme_constant_override("icon_max_width", 26)
				mbtn.pressed.connect(Game.move_reporter_choice)
				_action_box.add_child(mbtn)
		# 秘密身份挑战（身份已暴露）/ 摩多克·心灵异能（威胁卡）：提醒本回合必须背面出牌
		var cur_hid: String = Game.state["hero_ids"][Game.state["current_hero"]]
		if String(Game.state.get("forced_face_down_hero", "")) == cur_hid:
			var hint_text := "🎭 身份已暴露：本回合请直接点手牌（会背面打出，无效果但仍继承上一张卡符号）"
			if Game.state.get("challenge", "") != "secretid":
				hint_text = "🧠 心灵异能：本回合请直接点手牌（会背面打出，不会从自己的牌获得行动）"
			var hint := UiKit.label(hint_text, 16, Color(1, 0.7, 0.6))
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.custom_minimum_size = Vector2(360, 0)
			_action_box.add_child(hint)
		var end := UiKit.button("结束行动", Color(0.5, 0.3, 0.3))
		end.pressed.connect(Game.end_actions)
		_action_box.add_child(end)
		if Game.undo_enabled:
			var ubtn := UiKit.button("↩ 撤回", Color(0.45, 0.45, 0.3))
			ubtn.pressed.connect(Game.undo_last)
			_action_box.add_child(ubtn)
	elif phase == "hero_play":
		# 叛徒模式：还有不信任指示物时，可"背面出牌"丢弃（无效果，仅继承上一张牌符号）
		if Game.state.get("challenge", "") == "traitor":
			var fid: String = Game.state["hero_ids"][Game.state["current_hero"]]
			if Game.state["heroes"][fid].get("distrust", 0) > 0:
				var fbtn := UiKit.button("背面出牌（弃不信任）", Color(0.55, 0.35, 0.6))
				fbtn.pressed.connect(Game.play_face_down_choice)
				_action_box.add_child(fbtn)
	elif phase == "hero_end":
		# 行动用完后自动结束回合，不再提供"结束回合"按钮
		if Game.undo_enabled:
			var ubtn := UiKit.button("↩ 撤回", Color(0.45, 0.45, 0.3))
			ubtn.pressed.connect(Game.undo_last)
			_action_box.add_child(ubtn)

func _sym_color(sym: String) -> Color:
	match sym:
		"move": return Color(0.3, 0.5, 0.8)
		"attack": return Color(0.8, 0.3, 0.3)
		"heroic": return Color(0.3, 0.7, 0.4)
		"wild": return Color(0.7, 0.6, 0.2)
		_: return Color(0.5, 0.5, 0.5)

func _icon_for(key: String) -> Texture2D:
	match key:
		"move":
			return _icon_move
		"attack":
			return _icon_attack
		"heroic":
			return _icon_heroic
		"wild":
			return _icon_wild
		_:
			return null

## 无限战争：刷新任务牌下方的能量卡区（两张：开局可解锁 / 需三任务解锁）
## 显示：放大卡图 + 槽位图标叠加在卡图内部（2×2，已填全亮/未填半透明，像任务卡）；
## 未解锁的第二张整卡置暗并盖锁图标；标注能量卡 1/2。
func _refresh_energy_cards(st: Dictionary) -> void:
	_clear_children(_energy_box)
	# Bug8：终局之战——收藏的能量卡由 _refresh_energy_stack 叠放显示（此处不铺开）
	if st.get("final_battle", false):
		_energy_box.visible = false
		return
	var table_e: int = int(st.get("table_energy", -1))
	var hidden_e: int = int(st.get("hidden_energy", -1))
	var cards: Array = [table_e, hidden_e]
	for eidx in cards:
		if eidx < 0 or eidx >= DB.energy_cards.size():
			# 联机客户端：未解锁的那张只拿到"有这么一张"的标记（不告诉是哪张），
			# 但必须画出一个未解锁卡位，否则别人屏幕上这张卡整个消失（用户报的 bug）
			if eidx == hidden_e and bool(st.get("has_hidden_energy", false)):
				var lock_lb := UiKit.label("🂠 未解锁", 20, Color(0.85, 0.85, 0.95))
				_energy_box.add_child(lock_lb)
			continue
		var e: Dictionary = DB.energy_cards[eidx]
		var can_fill: bool = Game.energy_can_fill(eidx)
		var locked: bool = (eidx == hidden_e) and not can_fill
		var filled: int = Game.energy_filled(eidx)
		var need: Array = Game.energy_required_syms(eidx)
		var box := Control.new()
		box.custom_minimum_size = Vector2(150, 160)
		# 卡图（放大，竖版）
		var img := TextureRect.new()
		img.texture = load(e["image"])
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.position = Vector2(10, 14)
		img.custom_minimum_size = Vector2(130, 128)
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if locked:
			img.modulate = Color(0.25, 0.25, 0.3, 0.9)  # 置暗
		box.add_child(img)
		# 未解锁：锁图标盖住卡图中央
		if locked:
			var lock := UiKit.label("🔒", 52, Color(1, 0.9, 0.4))
			lock.position = Vector2(30, 42)
			lock.custom_minimum_size = Vector2(90, 70)
			lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(lock)
		# 2×2 槽位图标网格（叠加在卡图内部；已填全亮/未填半透明）
		var slot_icons := {"move": _icon_move, "attack": _icon_attack, "heroic": _icon_heroic, "threat": _icon_threat, "wild": _icon_wild}
		var slot_size := 38
		var threat_size := 28  # 威胁槽单独缩小
		# 网格以中心为锚：网格宽高 = 2*slot_size + 8
		var grid_wh: float = 2.0 * slot_size + 8.0
		var center_x := 74.0
		var center_y := 70.0
		var sx0 := center_x - grid_wh / 2.0
		var sy0 := center_y - grid_wh / 2.0
		var filled_slots: Array = Game.energy_filled_slots(eidx)
		# 再兜一层：无论数据来自主机还是 JSON 快照，都按 int 比较（否则客户端图标不亮）
		var filled_int: Array = []
		for fs in filled_slots:
			filled_int.append(int(fs))
		for si in range(mini(need.size(), 4)):
			var sym: String = need[si]
			# 每格中心按 38px 网格计算；威胁槽以该格中心为锚缩小显示
			var sz: float = threat_size if sym == "threat" else slot_size
			var cx: float = sx0 + (si % 2) * (slot_size + 8) + slot_size / 2.0
			var cy: float = sy0 + (si / 2) * (slot_size + 8) + slot_size / 2.0
			# 微调：左半边向右移一点，上半部分向下移 12px
			if si % 2 == 0:
				cx += 4.0
			if si / 2 == 0:
				cy += 12.0
			var tr := TextureRect.new()
			tr.texture = slot_icons.get(sym, _icon_wild)
			tr.custom_minimum_size = Vector2(sz, sz)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.position = Vector2(cx - sz / 2.0, cy - sz / 2.0)
			tr.modulate = Color(1, 1, 1, 1.0) if filled_int.has(si) else Color(1, 1, 1, 0.2)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(tr)
		# 名称小字（卡图下方居中）
		var lb := UiKit.label(e["name"], 13, Color(1, 0.85, 0.4) if can_fill else Color(0.6, 0.6, 0.6))
		lb.position = Vector2(6, 144)
		lb.custom_minimum_size = Vector2(140, 18)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		lb.add_theme_constant_override("outline_size", 3)
		box.add_child(lb)
		# 能量卡编号 1/2（左上角，按本局显示顺序）
		var local_no := 1
		if eidx == hidden_e and table_e >= 0:
			local_no = 2
		var num := UiKit.label("能量卡 %d" % local_no, 15, Color(1, 0.9, 0.4))
		num.position = Vector2(6, 0)
		num.custom_minimum_size = Vector2(80, 20)
		num.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		num.add_theme_constant_override("outline_size", 3)
		box.add_child(num)
		_energy_box.add_child(box)

## 制作一张简化的能量卡图标（终局之战：收集的能量卡用背面图显示）
func _make_energy_card_simple(eidx: int) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(120, 130)
	var img := TextureRect.new()
	img.texture = load("res://assets/cards/energy/back_%02d.png" % (eidx + 1))
	if img.texture == null:
		img.texture = load("res://assets/cards/energy/back_01.png")
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.position = Vector2(0, 0)
	img.custom_minimum_size = Vector2(120, 120)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(img)
	var lb := UiKit.label(DB.energy_cards[eidx]["name"], 12, Color(1, 0.85, 0.4))
	lb.position = Vector2(0, 120)
	lb.custom_minimum_size = Vector2(120, 14)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lb.add_theme_constant_override("outline_size", 3)
	box.add_child(lb)
	return box

## Bug4：右侧显示"已完成"的能量卡图标（只显示之前完成的；当局进行中/未完成的不显示）
func _refresh_energy_done(st: Dictionary) -> void:
	# 用户要求：无限战争的已完成能量卡不需要在右侧再显示一块「已完成」区
	_energy_done_box.visible = false
	return
	_clear_children(_energy_done_box)
	if st.get("final_battle", false):
		_energy_done_box.visible = false
		return
	var c: Variant = st.get("campaign", null)
	var unlocked: Array = c.get("energy_unlocked", []) if c is Dictionary else []
	var shown := 0
	for eidx in unlocked:
		if eidx is int and eidx >= 0 and eidx < DB.energy_cards.size() and Game.energy_done(eidx):
			_energy_done_box.add_child(_make_energy_card_simple(eidx))
			shown += 1
	_energy_done_box.visible = shown > 0

## 灭霸(非无限战争Boss)：激活能量卡 背面叠加显示。
## 每张显示横向背面卡；多张相互错开叠加，前面那张完整可见、后面那张只露出底部效果条。
func _refresh_energy_stack(st: Dictionary) -> void:
	_clear_children(_energy_stack_box)
	# 灭霸非IW Boss 或 无限战争终局之战：激活/收集的能量卡都叠放显示
	var base_thanos: bool = st.get("villain", "") == "thanos" and st.get("mode", "base") != "iw"
	var final_thanos: bool = st.get("mode", "base") == "iw" and st.get("final_battle", false) and st.get("villain", "") == "thanos"
	if not base_thanos and not final_thanos:
		_energy_stack_box.visible = false
		return
	var c: Variant = st.get("campaign", {})
	var unlocked: Array = c.get("energy_unlocked", []) if c is Dictionary else []
	if unlocked.size() == 0:
		_energy_stack_box.visible = false
		return
	# 横向背面卡尺寸（等比缩放，缩小显示）
	var base_w := 118.0
	var base_h := base_w * 960.0 / 1348.0   # 约84
	# 上下错开幅度：调大到效果条高度以上，让被盖的卡露出的效果条不被上一张挡住
	var overlap := 26.0
	# 两列：>4 张时分两列，列中心相对任务牌中心对称偏移
	var col_gap := 130.0                    # 两列中心间距
	var col_offset := col_gap / 2.0         # 每列中心距任务牌中心的偏移
	# 分列：>4 张分两列（左列在前填，右列填剩余）；否则单列
	var total: int = unlocked.size()
	var col_count := 1
	if total > 4:
		col_count = 2
	# 计算每列的卡数量
	var col_sizes: Array = []
	if col_count == 1:
		col_sizes = [total]
	else:
		col_sizes = [int(ceil(total / 2.0)), int(floor(total / 2.0))]
	# 每列：竖向叠加，前面卡在最上、后面的往下露出底部；列内用相对于"列中心"x的偏移
	var col_x: Array = [0.0]
	if col_count == 2:
		col_x = [-col_offset, col_offset]
	var card_i := 0
	for col in range(col_count):
		var n: int = col_sizes[col]
		for j in range(n - 1, -1, -1):
			var eidx: int = int(unlocked[card_i])
			var back_idx: int = eidx + 1
			var back_tex: Texture2D = load("res://assets/cards/energy/back_%02d.png" % back_idx)
			if back_tex == null:
				back_tex = load("res://assets/cards/energy/back_01.png")
			var tr := TextureRect.new()
			tr.texture = back_tex
			tr.custom_minimum_size = Vector2(base_w, base_h)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# 列内竖向叠加：j 越大(越靠前/最上)越靠上；前面的卡完整可见、后面的露出底部
			tr.position = Vector2(col_x[col] - base_w / 2.0, j * overlap)
			_energy_stack_box.add_child(tr)
			card_i += 1
	_energy_stack_box.visible = true

## 濒危地点：手牌区右侧显示每位玩家的牌组旁指示物（按序号 1-4）
func _refresh_endangered_side() -> void:
	if _endangered_side_box == null:
		return
	_clear_children(_endangered_side_box)
	var st: Dictionary = Game.state
	if st.get("challenge", "") != "endangered":
		_endangered_side_box.visible = false
		return
	var end: Dictionary = st.get("endangered", {})
	if not end.has("setup_done"):
		_endangered_side_box.visible = false
		return
	# 只显示"和手牌区同一个英雄"的濒危指示物：
	# 单机是当前行动英雄；联机是"我能操作的英雄"（自己 / 房主代管的已退出玩家）——
	# 这样指示物永远贴着自己那副牌，别人守护哪个地点不会显示在我这里。
	var cur: String = hand_hero_id if hand_hero_id != "" else Game.current_hero_id()
	if cur != "" and end.has(cur):
		var idx: int = st["hero_ids"].find(cur)
		var num: int = idx + 1
		var tr := TextureRect.new()
		tr.texture = load("res://assets/tokens/endangered_%d.png" % num)
		tr.custom_minimum_size = Vector2(44, 44)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_endangered_side_box.add_child(tr)
	_endangered_side_box.visible = cur != "" and end.has(cur)

## 无限战争：构建灭霸无限手套控件（地图环与日志之间的空隙）
## 尺寸与宝石位置按空手套素材(459x841)等比缩放；宝石按 DB.stones 顺序放置。
func _build_gauntlet() -> void:
	# 放置位置：日志右侧、地图环左侧的空隙（x≈505-994），垂直居中于地图中心
	var disp_h := 470.0
	var disp_w := disp_h * 459.0 / 841.0     # ≈256
	var pos := Vector2(1344 - 350 - disp_w - 118, 508 - disp_h / 2.0)
	# 空手套素材内的宝石位置(基于459x841)，缩放到显示尺寸
	var gem_pos := {
		0: Vector2(212.2, 202.1),  # mind 心灵(黄, 手背中心) -> idx0
		1: Vector2(89.3, 80.7),    # power 力量(紫, 顶排左) -> idx1
		2: Vector2(246.4, 79.7),   # reality 现实(红, 顶排) -> idx2
		3: Vector2(313.9, 81.7),   # soul 灵魂(橙, 顶排) -> idx3
		4: Vector2(161.8, 78.8),   # space 空间(蓝, 顶排) -> idx4
		5: Vector2(378.4, 181.2),  # time 时间(绿, 侧伸) -> idx5
	}
	var sx := disp_w / 459.0
	var sy := disp_h / 841.0

	_gauntlet = Control.new()
	_gauntlet.position = pos
	_gauntlet.custom_minimum_size = Vector2(disp_w, disp_h)
	_gauntlet.size = Vector2(disp_w, disp_h)
	_gauntlet.visible = false
	add_child(_gauntlet)

	# 手套底图（空手套，透明背景）
	_gauntlet_base = TextureRect.new()
	_gauntlet_base.texture = load("res://assets/ui/gauntlet/gauntlet_empty.png")
	_gauntlet_base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_gauntlet_base.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_gauntlet_base.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gauntlet_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauntlet.add_child(_gauntlet_base)

	# 六颗宝石节点（默认隐藏，收集到对应宝石才显示）
	_gem_nodes.clear()
	var gem_files := {
		0: "res://assets/ui/gauntlet/gem_mind.png",
		1: "res://assets/ui/gauntlet/gem_power.png",
		2: "res://assets/ui/gauntlet/gem_reality.png",
		3: "res://assets/ui/gauntlet/gem_soul.png",
		4: "res://assets/ui/gauntlet/gem_space.png",
		5: "res://assets/ui/gauntlet/gem_time.png",
	}
	# 每颗宝石原sprite直径(px)，按素材比例显示
	var gem_d := {
		0: 61, 1: 43, 2: 43, 3: 43, 4: 43, 5: 49,
	}
	for si in range(DB.stones.size()):
		var g := TextureRect.new()
		g.texture = load(gem_files[si])
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var gsize := Vector2(gem_d[si], gem_d[si]) * (disp_h / 841.0)
		g.position = Vector2(gem_pos[si].x * sx, gem_pos[si].y * sy) - gsize / 2.0
		g.custom_minimum_size = gsize
		g.size = gsize
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.visible = false
		_gauntlet.add_child(g)
		_gem_nodes[si] = g
	_gauntlet_pos = gem_pos

## 无限战争：按已收集宝石刷新手套点亮状态
func _update_gauntlet() -> void:
	if _gauntlet == null:
		return
	var st: Dictionary = Game.state
	var is_iw: bool = st.get("mode", "base") == "iw"
	_gauntlet.visible = is_iw
	if not is_iw:
		return
	var collected: Array = []
	var c: Variant = st.get("campaign", null)
	if c is Dictionary and not c.is_empty():
		collected = c.get("stones_collected", [])
	for si in range(DB.stones.size()):
		var nd: TextureRect = _gem_nodes.get(si)
		if nd != null:
			nd.visible = collected.has(si)

func _refresh_phase() -> void:
	var st: Dictionary = Game.state
	var phase: String = st["phase"]
	var hid: String = Game.current_hero_id()
	var shield: bool = Game.state.get("mode", "base") == "shield"
	# 无限战争战役信息（右侧竖排）
	var is_iw: bool = st.get("mode", "base") == "iw"
	_campaign_label.visible = is_iw
	# Bug8：终局之战也要显示收集的能量卡（non-final 显示当前局；final 显示收集的能量卡）
	_energy_box.visible = is_iw
	_update_gauntlet()
	# 裁定③（新口径）：阿戈摩托之球 → 反派牌堆右侧贴"牌堆顶那张行动牌"的卡图（悬停放大）。
	# 放在所有模式之前：阿戈摩托之球是基础盒英雄卡，基础/联机/无限战争局都可能用到。
	var _orb_card_shown: bool = _refresh_villain_top_card(st)
	if is_iw:
		var c: Variant = st.get("campaign", null)
		if c is Dictionary and not c.is_empty():
			var game_no: int = int(c.get("game", 1))
			var stones: int = c.get("stones_collected", []).size()
			var lines: Array = []
			if st.get("final_battle", false):
				lines.append("⚔️ 终局之战")
			else:
				lines.append("⚔️ 无限战争 %d/3" % game_no)
			# Bug3：去掉宝石进度行（💎 x/6 与 ◆◇），宝石收集逻辑保留
			var energy: Array = c.get("energy_unlocked", [])
			lines.append("⚡ 能量卡 %d 张" % energy.size())
			lines.append("（决战使用）" if st.get("final_battle", false) else "")
			_campaign_label.text = "\n".join(lines)
		else:
			_campaign_label.text = ""
		_refresh_energy_cards(st)
		_refresh_energy_done(st)
		# Bug2：反派牌堆顶是无限宝石时，在反派牌堆右侧提示
		var hint := ""
		# 客户端拿不到牌堆内容（只给张数），所以用主机下发的"牌堆顶是不是宝石"标记，
		# 保证联机时所有人看到的宝石提示一致
		var top_is_stone: bool = bool(st.get("master_deck_top_is_stone", false))
		var md_top: Array = st.get("master_deck", [])
		if md_top.size() > 0:
			top_is_stone = md_top.front() is Dictionary and (md_top.front() as Dictionary).has("stone")
		if not st.get("final_battle", false) and top_is_stone:
			hint = "灭霸即将收集到宝石"
		# 裁定③：阿戈摩托之球生效期间，把反派牌堆顶那张公开给所有人看（牌不动、不结算）。
		# 现在改成**贴卡图**（`_villain_top_card`）；只有卡图渲染失败（缺图）时才退回文字。
		if bool(st.get("villain_top_public", false)) and not _orb_card_shown:
			var _tidx: int = _villain_top_idx_for(st)
			if _tidx >= 0:
				hint = "🔮 牌堆顶公开：%s" % Game.villain_action_desc(_tidx)
		_villain_deck_hint.text = hint
		_villain_deck_hint.visible = hint != ""
	else:
		_campaign_label.text = ""
		_energy_done_box.visible = false
		_villain_deck_hint.visible = false
	match phase:
		"setup":
			# 顶部横幅让位给"开始游戏"按钮（按钮自带说明文字）
			_phase_label.text = ""
			_turn_label.text = ""
		"villain":
			_phase_label.text = "🦹 反派回合 #%d" % st["turn_count"]
		"hero_draw":
			# 抽牌阶段：只展示抽牌，不可操作手牌/行动（阶段结束时自动进入可操作的 hero_play）
			if shield:
				_phase_label.text = "🦸 神盾局回合 — 抽牌阶段…"
			else:
				_phase_label.text = "🦸 %s — 抽牌阶段…" % DB.hero_name(Game.current_hero_id())
		"hero_play":
			if shield:
				_phase_label.text = "🦸 神盾局回合 — 打出一张手牌"
			else:
				_phase_label.text = "🦸 %s 的回合 — 打出一张手牌" % DB.hero_name(hid)
		"hero_actions":
			if Game.state.get("virus_ignore", false):
				_phase_label.text = "⚠ 奥创病毒：点击任意行动按钮忽略该符号"
			elif shield:
				_phase_label.text = "🦸 神盾局回合 — 执行行动（剩余 %d）" % Game.remaining_symbols()
			else:
				_phase_label.text = "🦸 %s — 执行行动（剩余 %d）" % [DB.hero_name(hid), Game.remaining_symbols()]
		"hero_end":
			if shield:
				_phase_label.text = "🦸 神盾局回合 — 行动结束，点击结束回合"
			else:
				_phase_label.text = "🦸 %s — 行动结束，点击结束回合" % DB.hero_name(hid)
		"game_over":
			_phase_label.text = "游戏结束"
	_start_button.visible = (phase == "setup")
	if phase != "setup":
		_turn_label.text = "反派回合 %d ｜ 已完成任务 %d/3 ｜ 节奏：%s" % [
			st["turn_count"], st["missions_completed"],
			"每2张英雄牌" if st["missions_completed"] >= 1 else "每3张英雄牌"]

## 点击开始游戏：进入第一个反派回合（官方规则：游戏从反派回合开始）
func _on_start_pressed() -> void:
	# 叛徒模式：开局前让每位玩家(英雄)秘密查看自己的身份牌（热座逐个）
	if Game.state.get("challenge", "") == "traitor":
		for hid in Game.state["hero_ids"]:
			if not Game.state["loyalty"].has(hid):
				continue
			_popup.show_identity(hid, Game.state["loyalty"][hid] == "traitor")
			await Events.identity_confirmed
	await Game.start_game()

## 角色图标层（英雄/反派所在地指示）
## 位置变化时先播放逐点移动动画（英雄 1 步；反派多步也一步一步走），
## 动画全部结束后再重建图标。动画期间跳过重建，避免瞬间跳位。
func _refresh_hero_badges() -> void:
	var st: Dictionary = Game.state
	if st.is_empty() or not st.has("locations"):
		return
	if _animating_icons:
		if _anim_pending <= 0:
			_animating_icons = false  # 自愈：动画计数异常归零（tween 被意外结束）
		else:
			return
	var new_locs := {}
	for hid in st["hero_ids"]:
		new_locs[hid] = int(st["heroes"][hid]["location"])
	new_locs["villain"] = int(st["villain_pos"])
	if _prev_icon_locs.size() > 0 and _prev_icon_locs != new_locs:
		var old_locs: Dictionary = _prev_icon_locs.duplicate()
		_prev_icon_locs = new_locs.duplicate()
		_start_icon_animations(st, new_locs, old_locs)
		return
	_prev_icon_locs = new_locs.duplicate()
	_rebuild_icons(st)

## 灭霸：右下角显示阵亡英雄图标（仅图标，无文字）
func _refresh_eliminated() -> void:
	if _eliminated_box == null or _eliminated_label == null:
		return
	var st: Dictionary = Game.state
	if st.is_empty() or st.get("villain", "") != "thanos":
		_eliminated_box.visible = false
		_eliminated_label.visible = false
		return
	_eliminated_label.visible = true
	var elim: Array = st.get("eliminated", [])
	_clear_children(_eliminated_box)
	for hid in elim:
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(24, 32)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture = _hero_icons.get(hid)
		tr.modulate = Color(0.55, 0.55, 0.55)   # 暗淡表示阵亡
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_eliminated_box.add_child(tr)
	# x / y：x=已淘汰数，y=初始玩家数
	var total: int = int(st.get("player_count", st.get("hero_ids", []).size()))
	_eliminated_label.text = "已阵亡 %d/%d" % [elim.size(), total]
	_eliminated_box.visible = elim.size() > 0

## 播放角色移动动画：每个移动角色沿地点环逐点平移（每步一段动画），全部完成后重建
func _start_icon_animations(st: Dictionary, new_locs: Dictionary, old_locs: Dictionary) -> void:
	_animating_icons = true
	_anim_pending = 0
	for role in new_locs:
		var to: int = int(new_locs[role])
		var from: int = int(old_locs.get(role, to))
		if from == to:
			continue
		var box: Control = _find_icon_box(str(role))
		if box == null:
			continue
		var path: Array
		if str(role) == "villain":
			# 反派移动严格按行动牌步数顺时针走（如移动5步就走5步，不走反向近路）
			path = _ring_path(from, to, true)
		else:
			path = _ring_path(from, to)
		if path.is_empty():
			continue
		var tw := create_tween()
		for k in range(path.size()):
			tw.tween_property(box, "position", _icon_anchor_pos(int(path[k])), 0.25)
		_anim_pending += 1
		tw.finished.connect(_on_icon_anim_done)
	if _anim_pending == 0:
		_animating_icons = false
		_rebuild_icons(st)

func _on_icon_anim_done() -> void:
	_anim_pending -= 1
	if _anim_pending <= 0:
		_animating_icons = false
		_refresh_hero_badges()  # 动画完成：位置已正确，走正常重建

## 沿地点环从 from 到 to 的路径（中间地点序列，不含起点、含终点）。
## force_clockwise=true 时强制顺时针（反派移动按行动牌步数方向，不走反向近路）
func _ring_path(from: int, to: int, force_clockwise: bool = false) -> Array:
	var n := Game.LOCATION_COUNT
	if from == to:
		return []
	var fwd := (to - from + n) % n
	var back := (from - to + n) % n
	var pts: Array = []
	if force_clockwise or fwd <= back:
		for s in range(1, fwd + 1):
			pts.append((from + s) % n)
	else:
		for s in range(1, back + 1):
			pts.append((from - s + n) % n)
	return pts

## 按角色标识（英雄id / "villain"）查找图标节点
func _find_icon_box(role: String) -> Control:
	for n in _icon_nodes:
		if is_instance_valid(n) and n.get_meta("role", "") == role:
			return n
	return null

## 图标排布锚点（地点中心正下方的图标行中心）
func _icon_anchor_pos(loc: int) -> Vector2:
	var ang: float = TAU * loc / Game.LOCATION_COUNT - PI / 2
	var pos := LOC_CENTER + Vector2(cos(ang), sin(ang)) * LOC_RADIUS
	return Vector2(pos.x, pos.y - LOC_CARD_SIZE / 2.0 + 87.0)

## 重建全部角色图标（清理旧节点后按当前状态创建）
func _rebuild_icons(st: Dictionary) -> void:
	# 清理旧的图标节点
	for n in _icon_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_icon_nodes.clear()
	# 每个地点：收集反派（若在）与英雄图标，横向排开不重叠
	for i in range(Game.LOCATION_COUNT):
		var ang: float = TAU * i / Game.LOCATION_COUNT - PI / 2
		var pos := LOC_CENTER + Vector2(cos(ang), sin(ang)) * LOC_RADIUS
		var icons: Array = []  # {tex, badge, badge_color, role}
		if String(st.get("mode", "")) == "s6":
			# 邪恶六人组：6 个反派各自在自己的地点上（同地点多个则并排）
			var s6v: Dictionary = st.get("s6", {}).get("vills", {})
			for svid in DB.s6["order"]:
				var vv: Dictionary = s6v.get(svid, {})
				if vv.is_empty() or bool(vv.get("defeated", false)) or int(vv.get("pos", -1)) != i:
					continue
				icons.append({"tex": _villain_icons.get(String(svid)), "badge": "", "bc": Color(1, 0.8, 0.4), "role": "s6villain", "small": true, "vid": String(svid)})
		elif st["villain_pos"] == i:
			icons.append({"tex": _villain_icons.get(st["villain"]), "badge": "", "bc": Color.WHITE, "role": "villain"})
		for hid in st["hero_ids"]:
			var h: Dictionary = st["heroes"][hid]
			if h["location"] != i:
				continue
			var badge := ""
			if int(h["crisis"]) > 0:
				badge = "⚠%d" % h["crisis"]
			icons.append({
				"tex": _hero_icons.get(hid),
				"badge": badge,
				"bc": Color(1, 0.9, 0.3),
				"ko": h["ko"],
				"ko_count": int(h.get("ko_count", 0)),
				"role": hid,
			})
		# 秘密身份挑战：记者指示物固定在**地点卡左上角**（无论该地点有没有英雄/反派图标都要画）
		if st.get("challenge", "") == "secretid" and st["locations"][i].get("reporter", false):
			var r_icon := TextureRect.new()
			r_icon.texture = load("res://assets/tokens/reporter_token.png")
			r_icon.custom_minimum_size = Vector2(30, 30)
			r_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			r_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			r_icon.position = pos - Vector2(LOC_CARD_SIZE / 2.0, LOC_CARD_SIZE / 2.0) + Vector2(4, 4)
			add_child(r_icon)
			_icon_nodes.append(r_icon)
		if icons.size() == 0:
			continue
		# 横向排布：英雄与反派**各自成排、各自对齐地点卡中心**（两排不共用横向游标）
		var s6_mode2: bool = String(st.get("mode", "")) == "s6"
		var ordered: Array = []
		var targets: Array = []
		var heights: Array = []
		var widths: Array = []
		var gap := 3.0
		var groups: Array = []
		if s6_mode2:
			var hier: Array = icons.filter(func(x): return String(x.get("role", "")) != "s6villain")
			var vlist: Array = icons.filter(func(x): return String(x.get("role", "")) == "s6villain")
			if hier.size() > 0:
				groups.append({"list": hier, "y": pos.y - LOC_CARD_SIZE / 2.0 + 87.0, "h": 56.0})
			if vlist.size() > 0:
				var vh: float = 56.0 if vlist.size() <= 2 else (44.0 if vlist.size() == 3 else 36.0)
				groups.append({"list": vlist, "y": pos.y - LOC_CARD_SIZE / 2.0 + LOC_CARD_SIZE * 0.72, "h": vh})
		else:
			groups.append({"list": icons, "y": pos.y - LOC_CARD_SIZE / 2.0 + 87.0, "h": 56.0})
		for grp in groups:
			var glist: Array = grp["list"]
			var gh: float = float(grp["h"])
			var gy: float = float(grp["y"])
			var gw: Array = []
			var tot := 0.0
			for ic in glist:
				var tex0: Texture2D = ic["tex"]
				var tw0: float = gh
				if tex0 != null and tex0.get_height() > 0:
					tw0 = gh * tex0.get_width() / float(tex0.get_height())
				gw.append(tw0)
				tot += tw0 + gap
			tot -= gap
			var gx: float = pos.x - tot / 2.0
			for gi in range(glist.size()):
				ordered.append(glist[gi])
				widths.append(gw[gi])
				heights.append(gh)
				targets.append(Vector2(gx, gy))
				gx += gw[gi] + gap
		icons = ordered
		for k in range(icons.size()):
			var ic: Dictionary = icons[k]
			var box := Control.new()
			box.set_meta("role", ic.get("role", ""))
			var target_pos: Vector2 = targets[k]
			# 邪恶六人组：反派换地点时从旧位置滑到新位置（移动动画）
			var anim_from := Vector2.ZERO
			var do_anim := false
			if String(st.get("mode", "")) == "s6" and String(ic.get("role", "")) == "s6villain":
				var svid: String = String(ic.get("vid", ""))
				if _s6_icon_prev.has(svid):
					anim_from = _s6_icon_prev[svid]
					do_anim = anim_from.distance_to(target_pos) > 2.0
				_s6_icon_prev[svid] = target_pos
			box.position = target_pos if not do_anim else anim_from
			var this_h: float = heights[k]
			box.custom_minimum_size = Vector2(widths[k], this_h)
			add_child(box)
			# 黑色描边边框（与地图画面区分）
			var border := ColorRect.new()
			border.color = Color(0, 0, 0, 1)
			border.position = Vector2(-2, -2)
			border.size = Vector2(widths[k] + 4, this_h + 4)
			border.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(border)
			var tr := TextureRect.new()
			tr.texture = ic["tex"]
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.set_anchors_preset(Control.PRESET_FULL_RECT)
			tr.modulate = Color(0.55, 0.55, 0.55) if ic.get("ko", false) else Color.WHITE
			box.add_child(tr)
			# 罗南/亡刃将军 KO 指示物：只要该英雄累计过 KO 指示物（ko_count>0），就固定在英雄图标左下角显示
			# KO 图标 + 数量（不限当前是否 KO；不与右下角危机徽章重叠）
			var vv: String = st.get("villain", "")
			if (vv == "ronan" or vv == "corvus") and int(ic.get("ko_count", 0)) > 0:
				var ko_icon := TextureRect.new()
				ko_icon.texture = load("res://assets/cards/villains/ronan/ko_token.png")
				ko_icon.custom_minimum_size = Vector2(20, 20)
				ko_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				ko_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				ko_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
				ko_icon.position = Vector2(0, this_h - 22)
				box.add_child(ko_icon)
				var ko_num := UiKit.label("%d" % int(ic.get("ko_count", 0)), 12, Color(1, 0.4, 0.4))
				ko_num.add_theme_color_override("font_outline_color", Color(0, 0, 0))
				ko_num.add_theme_constant_override("outline_size", 3)
				ko_num.position = Vector2(18, this_h - 20)
				ko_num.custom_minimum_size = Vector2(18, 16)
				ko_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
				box.add_child(ko_num)
			if ic["badge"] != "":
				var lb: Label = UiKit.label(ic["badge"], 14, ic["bc"])
				lb.add_theme_color_override("font_outline_color", Color(0, 0, 0))
				lb.add_theme_constant_override("outline_size", 4)
				lb.position = Vector2(widths[k] - 30, this_h - 20)
				lb.custom_minimum_size = Vector2(28, 18)
				lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				box.add_child(lb)
			# 秘密身份挑战：曝光指示物数量固定在英雄图标的**上半部分**（左上角，与左下 KO、右下危机徽章不重叠）
			if st.get("challenge", "") == "secretid" and st["heroes"].has(String(ic.get("role", ""))) and int(st["heroes"][ic["role"]].get("exposure", 0)) > 0:
				var expo: int = int(st["heroes"][ic["role"]]["exposure"])
				var e_icon := TextureRect.new()
				e_icon.texture = load("res://assets/tokens/exposure_token.png")
				e_icon.custom_minimum_size = Vector2(28, 28)
				e_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				e_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				e_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
				e_icon.position = Vector2(0, -3)
				box.add_child(e_icon)
				var e_num := UiKit.label("%d" % expo, 16, Color(1, 0.85, 0.35))
				e_num.add_theme_color_override("font_outline_color", Color(0, 0, 0))
				e_num.add_theme_constant_override("outline_size", 5)
				e_num.position = Vector2(26, -3)
				e_num.custom_minimum_size = Vector2(22, 20)
				e_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
				box.add_child(e_num)
			_icon_nodes.append(box)
			if do_anim:
				var tw2 := create_tween()
				tw2.tween_property(box, "position", target_pos, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			pass

# ================================================================ 邪恶六人组模式 UI

var _s6_nodes: Array = []          # s6 专用节点（每次刷新重建）
var _s6_center_root: Control = null
var _villain_bg: Panel = null      # 左上角反派信息框（s6 模式在其上加挂仪表板等）
var _s6_icon_prev := {}            # s6：每个反派图标上一次的位置（用于移动动画）
var _zoom_base_size := Vector2.ZERO   # 放大预览的基准尺寸（滚轮倍率在此基础上生效）
var _zoom_mul := 1.0                  # 放大预览的滚轮倍率（0.25~4.0）

## 左侧：六边形仪表板（随机中心旋转）+ 右侧 6 个反派生命值列表 + 下方秃鹫身上的民/暴
func _refresh_s6_panel(st: Dictionary) -> void:
	# 单人局的面板/血条/轨道的控件全部隐藏，改用 s6 专用显示
	_villain_panel.visible = false
	_fear_bar.visible = false
	_fear_label.visible = false
	_hp_label.visible = false
	for n in _s6_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_s6_nodes.clear()
	var s: Dictionary = st.get("s6", {})
	if s.is_empty():
		return
	# 单人局的控件全部隐藏（含残留的生命值图标/KO 图标等）
	_villain_panel.visible = false
	_fear_bar.visible = false
	_fear_label.visible = false
	_hp_label.visible = false
	_hp_icon.visible = false
	_ko_icon.visible = false
	if _goblin_civ_box != null:
		_goblin_civ_box.visible = false
	# 面板图（摆正不旋转；用锚点让贴图严格填满 190×190 框）
	var clip := Control.new()
	clip.position = Vector2(8, 8)
	clip.custom_minimum_size = Vector2(250, 250)
	clip.size = Vector2(250, 250)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_villain_bg.add_child(clip)
	_s6_nodes.append(clip)
	var pan := TextureRect.new()
	pan.texture = load("res://assets/cards/s6/panel.png")
	pan.set_anchors_preset(Control.PRESET_FULL_RECT)
	pan.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pan.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pan.rotation = 0.0                     # 摆正
	pan.mouse_filter = Control.MOUSE_FILTER_STOP   # 需要接收 mouse_entered（悬停放大）
	clip.add_child(pan)
	_bind_zoom(pan)                        # 鼠标停留 → 放大预览（与单人局反派面板一致）
	# 右侧：每个反派的生命值
	var hp_box := VBoxContainer.new()
	hp_box.position = Vector2(266, 12)
	hp_box.add_theme_constant_override("separation", 6)
	_villain_bg.add_child(hp_box)
	_s6_nodes.append(hp_box)
	for vid in DB.s6["order"]:
		var v: Dictionary = s["vills"][vid]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		hp_box.add_child(row)
		# 前缀：已击败 → 奖杯；弱点卡已化解（可受伤）→ 素材生命值图标（不再有锁）；未化解 → 锁
		if bool(v["defeated"]):
			row.add_child(UiKit.label("🏆", 12, Color(0.6, 1, 0.6)))
		elif bool(v["weak_done"]):
			var hi := TextureRect.new()
			hi.texture = load("res://assets/tokens/hp_icon.png")
			hi.custom_minimum_size = Vector2(16, 16)
			hi.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			hi.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(hi)
		else:
			row.add_child(UiKit.label("🔒", 12, Color(1, 1, 1)))
		row.add_child(UiKit.label("%s %d/%d" % [DB.villain_name(String(vid)), int(v["hp"]), int(v["hp_max"])], 12,
			Color(0.6, 1, 0.6) if bool(v["defeated"]) else (Color(1, 0.75, 0.75) if bool(v["weak_done"]) else Color(1, 1, 1))))
	# 生命值列表下方：秃鹫身上的平民 / 暴徒（分两行显示）
	var vv: Dictionary = s["vills"]["vulture"]
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(266, 152)
	vbox.add_theme_constant_override("separation", 2)
	_villain_bg.add_child(vbox)
	_s6_nodes.append(vbox)
	var vl := UiKit.label("🦅 秃鹫身上", 12, Color(1, 0.9, 0.6))
	vbox.add_child(vl)
	for pair in [["civ", int(vv["held_civ"])], ["thug", int(vv["held_thug"])]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		vbox.add_child(row)
		var ic := TextureRect.new()
		ic.texture = load("res://assets/tokens/%s_token.png" % String(pair[0]))
		ic.custom_minimum_size = Vector2(20, 20)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(ic)
		var nl := UiKit.label("%s x%d" % ["平民" if String(pair[0]) == "civ" else "暴徒", int(pair[1])], 12, Color(1, 1, 1))
		row.add_child(nl)
	# 反派行动牌堆（s6 卡背 + 剩余张数）
	if _villain_deck_icon != null:
		_villain_deck_icon.texture = load("res://assets/cards/s6/action_back.png")
		_villain_deck_num.text = "%d" % (s.get("deck", []) as Array).size()

## 中央：6 张弱点卡按面板方向摆成六边形（不遮挡地点；显示 3 个槽位的填充进度）
func _refresh_s6_center(st: Dictionary) -> void:
	_hide_s6_center()
	var s: Dictionary = st.get("s6", {})
	if s.is_empty():
		return
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_s6_center_root = root
	# 面板 6 个方向的顺序与面板一致：左上=克莱文 / 上=沙人 / 右上=电光人 / 左下=神秘客 / 下=章鱼博士 / 右下=秃鹫
	var dirs := {
		"kraven": Vector2(-1, -1), "sandman": Vector2(0, -1), "electro": Vector2(1, -1),
		"mysterio": Vector2(-1, 1), "docock": Vector2(0, 1), "vulture": Vector2(1, 1),
	}
	var cw := 130.0
	var ch := 93.0
	var radius := 165.0
	for vid in DB.s6["order"]:
		var v: Dictionary = s["vills"][vid]
		var d: Vector2 = dirs[vid]
		var off: Vector2 = d.normalized() * radius
		# 四个斜角卡向中心收一点：猎人克莱文/电光人（上排）下移，神秘客/秃鹫（下排）上移
		if absf(d.x) > 0.1 and absf(d.y) > 0.1:
			off.y *= 0.70
		var cpos: Vector2 = LOC_CENTER + off - Vector2(cw / 2, ch / 2)
		var box := Control.new()
		box.position = cpos
		box.custom_minimum_size = Vector2(cw, ch)
		box.size = Vector2(cw, ch)
		box.clip_contents = true
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(box)
		# 用锚点让贴图严格填满整张卡框（否则 TextureRect 会按原始像素尺寸绘制，只露出左上角一小块）
		var cd := TextureRect.new()
		cd.texture = load("res://assets/cards/s6/weak_%02d.png" % int(DB.s6["weak"][vid]["img"]))
		cd.set_anchors_preset(Control.PRESET_FULL_RECT)
		cd.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cd.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cd.modulate = Color(1, 1, 1, 0.35) if bool(v["defeated"]) else (Color(1, 0.85, 0.85) if bool(v["weak_done"]) else Color.WHITE)
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(cd)
		# 3 个槽位进度（与卡面印刷的贴纸对齐）
		var syms: Array = v["weak_syms"]
		var filled: Array = v["weak_filled"]
		var xs := [0.195, 0.501, 0.812]
		for si in range(3):
			if si >= syms.size():
				break
			var sicon := TextureRect.new()
			var sym: String = String(syms[si])
			sicon.texture = load("res://assets/tokens/token_%s.png" % sym)
			# 填充图标按卡宽等比放大（约 30% 卡宽，正好盖住卡面印刷的符号贴纸）
			var ssz: float = cw * 0.30
			sicon.custom_minimum_size = Vector2(ssz, ssz)
			sicon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			sicon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			sicon.position = Vector2(float(xs[si]) * cw - ssz / 2.0, 0.80 * ch - ssz / 2.0)
			var done: bool = si < filled.size() and int(filled[si]) == 1
			sicon.modulate = Color(1, 1, 1, 1.0) if done else Color(1, 1, 1, 0.25)
			sicon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(sicon)
		# 名字 + 状态
		var nl := UiKit.label("%s%s" % [DB.villain_name(String(vid)), "（已击败）" if bool(v["defeated"]) else ("（可受伤）" if bool(v["weak_done"]) else "")], 13,
			Color(0.6, 1, 0.6) if bool(v["defeated"]) else (Color(1, 0.9, 0.4) if bool(v["weak_done"]) else Color(0.9, 0.9, 0.9)))
		nl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		nl.add_theme_constant_override("outline_size", 4)
		nl.position = Vector2(2, -18)
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(nl)

func _hide_s6_center() -> void:
	if is_instance_valid(_s6_center_root):
		_s6_center_root.queue_free()
	_s6_center_root = null

# ================================================================ 日志

## 日志一律以 Game.state["log"] 为准（bug3）：
## 联机时游戏逻辑只在主机跑，客户端收不到 log_line 事件，只有快照里的 state["log"]；
## 所以两边都改成"把还没显示过的 state["log"] 行补进日志框"，主机与客户端自然完全同步。
var _log_shown := 0
var _log_first_text := "\u0000"    # 视图里第一行日志的文字（用来发现"日志源头换了"）
var _dbg_energy_last := ""         # 联机诊断：上一次打印过的公共能量卡填充状态

func _sync_log() -> void:
	if _log_box == null:
		return
	var logs: Array = Game.state.get("log", [])
	# 关键：客户端会先自己跑一遍本地 setup，日志第一行（如"本局能量卡：X"）是它自己随机出来的；
	# 收到主机快照后如果还按"增量追加"，就会一直显示本地那份 → 每个玩家看到的开局日志都不一样。
	# 所以：行数变少（新局清空）或第一行内容变了（日志本源换了）都整段重建。
	var first_t := ""
	if logs.size() > 0 and logs[0] is Dictionary:
		first_t = String((logs[0] as Dictionary).get("t", ""))
	if logs.size() < _log_shown or first_t != _log_first_text:
		_clear_children(_log_box)
		_log_shown = 0
	_log_first_text = first_t
	while _log_shown < logs.size():
		var e: Dictionary = logs[_log_shown]
		_log_shown += 1
		var l := UiKit.label(String(e.get("t", "")), 15, Color(String(e.get("c", "#ffffff"))))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(450, 0)
		_log_box.add_child(l)
	# 只保留最近 300 行，长局不卡
	while _log_box.get_child_count() > 300:
		var c: Node = _log_box.get_child(0)
		_log_box.remove_child(c)
		c.queue_free()
	await _scroll_log_to_bottom()

func _on_log(_text: String, _color: Color) -> void:
	# 内容已经写进 state["log"] 了，这里只负责"补显示"
	await _sync_log()

func _scroll_log_to_bottom() -> void:
	await get_tree().process_frame
	# 确保布局已完成后再取最新 max_value 并滚到底
	var bar: ScrollBar = _log_scroll.get_v_scroll_bar()
	await get_tree().process_frame
	_log_scroll.scroll_vertical = bar.max_value
	_log_scroll.scroll_vertical = _log_scroll.get_v_scroll_bar().max_value
