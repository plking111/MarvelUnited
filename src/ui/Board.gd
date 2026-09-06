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
var _hand_label: Label
var _hand_random: ColorRect   # 乌木侯控制时叠在手牌区的暗色遮罩
var _hand_random_btn: Button  # 手牌区中央的"随机出牌"按钮
var _action_box: HBoxContainer
var _token_box: HBoxContainer
var _log_box: VBoxContainer
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
	# 英雄/反派图标：使用卡牌背面图（英雄=英雄卡背，反派=反派行动牌背）
	for hid in ["cap", "ironman", "cmarvel", "hulk", "widow", "winter", "shuri", "blackpanther", "korg", "valkyrie", "betaray", "thor", "starlord", "rocket", "gamora", "groot", "spiderman", "miles", "gwenspider", "spiderpig"]:
		_hero_icons[hid] = load(DB.hero_back(hid))
	for vid in ["redskull", "ultron", "taskmaster", "thanos", "proxima", "cull", "ebony", "kilmonger", "loki", "ronan", "goblin"]:
		_villain_icons[vid] = load(DB.villain(vid)["back"])
	_build_ui()
	# 弹窗/提示信号 → 弹窗层模块（CanvasLayer=100，永不被主界面内容遮挡）
	Events.state_changed.connect(_refresh_all)
	Events.log_line.connect(_on_log)
	Events.prompt_choice.connect(_popup.show_prompt)
	Events.prompt_confirm.connect(_popup.show_confirm)
	Events.prompt_hand_card.connect(_popup.show_hand_pick)
	Events.prompt_story_card.connect(_popup.show_story_pick)
	Events.prompt_villain_card.connect(_popup.show_villain_card)
	Events.prompt_deck_card.connect(_popup.show_deck_pick)
	Events.prompt_hero_pick.connect(_popup.show_hero_pick)
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
	_refresh_villain()
	_refresh_missions()
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

func _refresh_villain() -> void:
	var st: Dictionary = Game.state
	var vid: String = st["villain"]
	_villain_panel.texture = load(DB.villain_image(vid))
	# 反派牌堆数量（与英雄牌库显示一致：背面图标 + 数字）
	if _villain_deck_icon != null:
		_villain_deck_icon.texture = load(DB.villain(vid)["back"])
		_villain_deck_num.text = "%d" % st["master_deck"].size()
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
	elif track == "ko":
		# 罗南 KO 指示物计数：累计 4 个英雄失败
		_fear_bar.visible = true
		_fear_bar.max_value = 4
		_fear_bar.value = st.get("ko_tokens", 0)
		_fear_label.visible = true
		_fear_label.text = "KO 指示物：%d / 4" % st.get("ko_tokens", 0)
		_ko_icon.visible = true
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
		_popup.show_game_over(victory, extra, Callable(self, "_start_next_campaign_game"))
		return
	_popup.show_game_over(victory, reason)

## 开始下一局战役：更新 campaign 局数并重新 setup
func _start_next_campaign_game() -> void:
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
		if e["type"] == "hero":
			if e.get("face_down", false):
				# 英雄行动牌面朝下：显示卡背面（下一个英雄无法从它获得行动）
				tr.texture = load(DB.hero_back(e["hero"]))
			else:
				tr.texture = load(UiKit.hero_card_image(e["hero"], e["idx"]))
		else:
			# 反派行动牌：面朝下显示行动牌背面（英雄看不到是哪张）；否则显示正面
			if e.get("face_down", false) or e.get("idx", -1) < 0:
				tr.texture = load(DB.villain(Game.state["villain"])["back"])
			else:
				tr.texture = load(UiKit.villain_action_image(Game.state["villain"], e["idx"]))
		_bind_zoom(tr)
		_story_box.add_child(tr)
	# 故事情节在下一帧布局后才更新内容宽度；延迟一帧再滚到最右（最新），避免被钳制后回升
	if is_instance_valid(_story_scroll):
		_scroll_story_to_latest()

func _scroll_story_to_latest() -> void:
	await get_tree().process_frame
	_story_scroll.scroll_horizontal = _story_scroll.get_h_scroll_bar().max_value

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
	# 新英雄回合开始时，预览自动回到当前行动英雄
	if phase == "hero_play" and _peek_hero != "" and _peek_hero != cur_hid:
		_peek_hero = ""
	var hid: String = cur_hid
	if _peek_hero != "" and Game.state["heroes"].has(_peek_hero):
		hid = _peek_hero
	var h: Dictionary = Game.state["heroes"][hid]
	var previewing: bool = hid != cur_hid
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
		if playable and not controlled:
			tr.gui_input.connect(_on_hand_card_input.bind(i, tr))
		tr.mouse_filter = Control.MOUSE_FILTER_STOP if (playable and not controlled) else Control.MOUSE_FILTER_PASS
		_hand_box.add_child(tr)

func _on_hand_card_input(event: InputEvent, hand_idx: int, tr: TextureRect) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Game.play_card(hand_idx)

## 乌木侯控制：点击"随机出牌"按钮 → 随机打出一张手牌
func _on_random_play_pressed() -> void:
	Game.play_card(0)

## 绑定悬停放大：鼠标移入显示大图，移出隐藏（故事情节/手牌卡通用）
func _bind_zoom(tr: TextureRect) -> void:
	tr.mouse_entered.connect(_zoom_show.bind(tr))
	tr.mouse_exited.connect(_zoom_hide)

func _zoom_show(tr: TextureRect) -> void:
	if tr.texture == null:
		return
	var tw: float = tr.texture.get_width()
	var th: float = tr.texture.get_height()
	var scale_f := 2.6
	if th * scale_f > 460.0:
		scale_f = 460.0 / th
	_zoom_panel.texture = tr.texture
	var zs := Vector2(tw * scale_f, th * scale_f)
	_zoom_panel.custom_minimum_size = zs
	_zoom_panel.size = zs
	_zoom_panel.visible = true
	_update_zoom_position()
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
		var end := UiKit.button("结束行动", Color(0.5, 0.3, 0.3))
		end.pressed.connect(Game.end_actions)
		_action_box.add_child(end)
		if Game.undo_enabled:
			var ubtn := UiKit.button("↩ 撤回", Color(0.45, 0.45, 0.3))
			ubtn.pressed.connect(Game.undo_last)
			_action_box.add_child(ubtn)
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
			tr.modulate = Color(1, 1, 1, 1.0) if filled_slots.has(si) else Color(1, 1, 1, 0.2)
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
	# 只显示当前行动英雄自己的濒危指示物（玩家据此知道该英雄守护哪个地点）
	var cur: String = Game.current_hero_id()
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
		var deck_top: Variant = st.get("master_deck", []).front() if st.get("master_deck", []).size() > 0 else null
		if not st.get("final_battle", false) and deck_top is Dictionary and deck_top.has("stone"):
			hint = "灭霸即将收集到宝石"
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
		if st["villain_pos"] == i:
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
		if icons.size() == 0:
			continue
		# 横向排布（叠放在地点卡中央：槽位下方、威胁卡上方，不遮挡民/暴指示物）
		var icon_h := 56.0
		var gap := 3.0
		var widths: Array = []
		var total_w := 0.0
		for ic in icons:
			var tex: Texture2D = ic["tex"]
			var tw: float = 56.0
			if tex != null and tex.get_height() > 0:
				tw = icon_h * tex.get_width() / float(tex.get_height())
			widths.append(tw)
			total_w += tw + gap
		total_w -= gap
		var x := pos.x - total_w / 2.0
		var y := pos.y - LOC_CARD_SIZE / 2.0 + 87.0
		for k in range(icons.size()):
			var ic: Dictionary = icons[k]
			var box := Control.new()
			box.set_meta("role", ic.get("role", ""))
			box.position = Vector2(x, y)
			box.custom_minimum_size = Vector2(widths[k], icon_h)
			add_child(box)
			# 黑色描边边框（与地图画面区分）
			var border := ColorRect.new()
			border.color = Color(0, 0, 0, 1)
			border.position = Vector2(-2, -2)
			border.size = Vector2(widths[k] + 4, icon_h + 4)
			border.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(border)
			var tr := TextureRect.new()
			tr.texture = ic["tex"]
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.set_anchors_preset(Control.PRESET_FULL_RECT)
			tr.modulate = Color(0.55, 0.55, 0.55) if ic.get("ko", false) else Color.WHITE
			box.add_child(tr)
			# 罗南 KO 指示物：只要该英雄累计过 KO 指示物（ko_count>0），就固定在英雄图标左下角显示
			# KO 图标 + 数量（不限当前是否 KO；不与右下角危机徽章重叠）
			if st.get("villain", "") == "ronan" and int(ic.get("ko_count", 0)) > 0:
				var ko_icon := TextureRect.new()
				ko_icon.texture = load("res://assets/cards/villains/ronan/ko_token.png")
				ko_icon.custom_minimum_size = Vector2(20, 20)
				ko_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				ko_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				ko_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
				ko_icon.position = Vector2(0, icon_h - 22)
				box.add_child(ko_icon)
				var ko_num := UiKit.label("%d" % int(ic.get("ko_count", 0)), 12, Color(1, 0.4, 0.4))
				ko_num.add_theme_color_override("font_outline_color", Color(0, 0, 0))
				ko_num.add_theme_constant_override("outline_size", 3)
				ko_num.position = Vector2(18, icon_h - 20)
				ko_num.custom_minimum_size = Vector2(18, 16)
				ko_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
				box.add_child(ko_num)
			if ic["badge"] != "":
				var lb: Label = UiKit.label(ic["badge"], 14, ic["bc"])
				lb.add_theme_color_override("font_outline_color", Color(0, 0, 0))
				lb.add_theme_constant_override("outline_size", 4)
				lb.position = Vector2(widths[k] - 30, icon_h - 20)
				lb.custom_minimum_size = Vector2(28, 18)
				lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				box.add_child(lb)
			_icon_nodes.append(box)
			x += widths[k] + gap

# ================================================================ 日志

func _on_log(text: String, color: Color) -> void:
	var l := UiKit.label(text, 15, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(450, 0)
	_log_box.add_child(l)
	# 日志在下一帧布局后才更新内容高度；延迟一帧再滚到底，避免滚动条被旧内容钳制后回升
	await _scroll_log_to_bottom()

func _scroll_log_to_bottom() -> void:
	await get_tree().process_frame
	# 确保布局已完成后再取最新 max_value 并滚到底
	var bar: ScrollBar = _log_scroll.get_v_scroll_bar()
	await get_tree().process_frame
	_log_scroll.scroll_vertical = bar.max_value
	_log_scroll.scroll_vertical = _log_scroll.get_v_scroll_bar().max_value
