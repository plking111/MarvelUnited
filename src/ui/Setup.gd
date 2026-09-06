extends Control
## 设置界面（三步向导）：1选择模式 → 2选择英雄/人数 → 3选择反派/挑战。

var _step := 1
var _mode := "base"  # base / shield
var _hero_count := 3
var _selected_heroes: Array = []   # 紧凑列表（按槽位顺序，供开局使用）
var _hero_slots: Array = []        # 稳定槽位数组：长度=人数上限，元素为英雄id或""（空槽）
var _selected_villain := ""
var _selected_challenge := "none"
var _selected_expansions: Array = ["基础盒"]  # 地点扩展选择
var _campaign_slots: Array = ["", "", ""]     # 无限战争战役：前 3 局反派顺序（P1/P2/P3 槽位）
var _campaign_label: Label                    # 战役顺序提示标签

var _villain_buttons: Dictionary = {}
var _hero_buttons: Dictionary = {}
var _hero_scroll: ScrollContainer
var _hero_grid: Control
var _hero_search: LineEdit
var _villain_scroll: ScrollContainer
var _villain_grid: Control
var _villain_search: LineEdit
var _hero_count_label: Label
var _mode_buttons: Dictionary = {}
var _count_row: Control
var _hero_icons: Dictionary = {}
var _villain_icons: Dictionary = {}
var _sort_mode := "alpha"  # alpha（首字母）/ expansion（扩展）
var _sort_buttons: Dictionary = {}
var _hero_tooltip: PanelContainer   # 英雄悬停强度窗口
var _hero_tooltip_title: Label
var _hero_tooltip_body: Label
var _hero_tooltip_hid: String = ""
var _villain_panel_tooltip: PanelContainer   # 反派悬停面板背面预览
var _villain_panel_img: TextureRect
var _villain_panel_vid: String = ""
var _hero_row_labels: Array = []   # 每行图标后的数字 Label（4 行）
var _hero_row_bars: Array = []     # 每行进度条填充 ColorRect（4 行）
var _exp_labels: Array = []
var _step_pages: Dictionary = {}
var _nav_back: Button
var _nav_next: Button
var _selected_mode_id := 0  # 模式图标编号（1-27），0=未选择
var _mode_tex: Dictionary = {}   # 编号 -> 原图
var _gray_mat: ShaderMaterial    # 灰度着色器材质（未选中图标使用）
var _modal: Control              # 模态弹窗（未上架提示）
var _count_label: Label
var _count_minus: Button
var _count_plus: Button
var _mode_info_bg: Texture2D            # 模式说明窗口背景
var _mode_info_data: Dictionary = {}    # 模式编号 -> 说明文字（data/mode_info.json）
var _hand_font: Font                    # 手写体（华文行楷 → 楷体 → 默认）
var _mode_info: Control                 # 悬停说明窗口（固定尺寸与字体）
var _mode_info_title: Label
var _mode_info_desc: Label

# 排序数据：拼音首字母 + 所属扩展盒（目前全部为基础盒）
const VILLAIN_SORT := {"redskull": "H", "ultron": "A", "taskmaster": "M", "thanos": "T", "proxima": "A", "cull": "H", "ebony": "W", "kilmonger": "J", "loki": "L", "ronan": "L", "goblin": "L"}
const HERO_SORT := {"cap": "M", "ironman": "G", "cmarvel": "J", "hulk": "L", "widow": "H", "winter": "W", "shuri": "S", "blackpanther": "B", "korg": "K", "valkyrie": "N", "betaray": "M", "thor": "L", "starlord": "X", "rocket": "H", "gamora": "K", "groot": "G", "spiderman": "Z", "miles": "M", "gwenspider": "G", "spiderpig": "Z"}
const VILLAIN_EXP := {"redskull": "基础盒", "ultron": "基础盒", "taskmaster": "基础盒", "thanos": "无限战争", "proxima": "无限战争", "cull": "无限战争", "ebony": "无限战争", "kilmonger": "瓦坎达", "loki": "阿斯加德", "ronan": "银河护卫队", "goblin": "蜘蛛侠扩"}
const HERO_EXP := {"cap": "基础盒", "ironman": "基础盒", "cmarvel": "基础盒", "hulk": "基础盒", "widow": "基础盒", "winter": "瓦坎达", "shuri": "瓦坎达", "blackpanther": "瓦坎达", "korg": "阿斯加德", "valkyrie": "阿斯加德", "betaray": "阿斯加德", "thor": "阿斯加德", "starlord": "银河护卫队", "rocket": "银河护卫队", "gamora": "银河护卫队", "groot": "银河护卫队", "spiderman": "蜘蛛侠扩", "miles": "蜘蛛侠扩", "gwenspider": "蜘蛛侠扩", "spiderpig": "蜘蛛侠扩"}

# 英雄顺位框颜色：按彩虹色排列（红橙黄绿青蓝紫），第 8 位起循环（支持更多玩家）
const HERO_SLOT_COLORS := [
	Color(0.95, 0.30, 0.30),  # P1 红
	Color(0.95, 0.62, 0.18),  # P2 橙
	Color(0.92, 0.88, 0.20),  # P3 黄
	Color(0.35, 0.80, 0.42),  # P4 绿
	Color(0.30, 0.72, 0.92),  # P5 青
	Color(0.42, 0.45, 0.95),  # P6 蓝
	Color(0.72, 0.42, 0.92),  # P7 紫
]

# 28 个模式按钮：编号对应 assets/ui/modes/mode_N.png
const MODE_DATA := {
	1: {"name": "基础模式", "mode": "base", "challenge": "none", "impl": true},
	2: {"name": "中等挑战模式", "mode": "base", "challenge": "moderate", "impl": true},
	3: {"name": "困难挑战模式", "mode": "base", "challenge": "hard", "impl": true},
	4: {"name": "英雄挑战模式", "mode": "base", "challenge": "heroic", "impl": true},
	5: {"name": "神盾局&泽维尔单人模式", "mode": "shield", "challenge": "none", "impl": true},
	6: {"name": "指挥官单人模式", "impl": false},
	7: {"name": "无限战争模式", "mode": "iw", "challenge": "none", "impl": true},
	8: {"name": "超级反派模式", "impl": false},
	9: {"name": "濒危地点模式", "mode": "base", "challenge": "endangered", "impl": true},
	10: {"name": "叛徒挑战模式", "impl": false},
	11: {"name": "B计划挑战模式", "impl": false},
	12: {"name": "秘密身份挑战模式", "impl": false},
	13: {"name": "邪恶六人组模式", "impl": false},
	14: {"name": "金队VS蓝队模式", "impl": false},
	15: {"name": "危险房间挑战模式", "impl": false},
	16: {"name": "威胁地点挑战模式", "impl": false},
	17: {"name": "凤凰五人组模式", "impl": false},
	18: {"name": "哨兵挑战模式", "impl": false},
	19: {"name": "死侍混乱挑战模式", "impl": false},
	20: {"name": "接管挑战模式", "impl": false},
	21: {"name": "新邪恶六人组模式", "impl": false},
	22: {"name": "内战·英雄对决模式", "impl": false},
	23: {"name": "内战·注册法案模式", "impl": false},
	24: {"name": "屠杀来袭挑战模式", "impl": false},
	25: {"name": "行星吞噬者降临模式", "impl": false},
	26: {"name": "天启时代模式", "impl": false},
	27: {"name": "困境挑战模式", "impl": false},
	28: {"name": "非凡龙挑战模式", "impl": false},
	29: {"name": "宠物伙伴模式", "impl": false},
	30: {"name": "小队牌库模式", "impl": false},
	31: {"name": "战役模式", "impl": false},
}

func _ready() -> void:
	# 异步后台预加载棋盘场景与纹理（load_threaded_* 不阻塞 Setup 进入，避免卡顿）
	UiKit.precache_async()
	_mode_info_bg = load("res://assets/ui/modes/mode_info_bg.png")
	# 手写体：华文行楷（手写感强）→ 楷体 → 默认字体（系统字体路径，无需打包分发）
	_hand_font = null
	var hf := FontFile.new()
	if hf.load_dynamic_font("C:/Windows/Fonts/STXINGKA.TTF") == OK:
		_hand_font = hf
	else:
		var hf2 := FontFile.new()
		if hf2.load_dynamic_font("C:/Windows/Fonts/simkai.ttf") == OK:
			_hand_font = hf2
	var f := FileAccess.open(DB._resolve_data_path("res://data/mode_info.json"), FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			_mode_info_data = parsed
	for hid in ["cap", "ironman", "cmarvel", "hulk", "widow", "winter", "shuri", "blackpanther", "korg", "valkyrie", "betaray", "thor", "starlord", "rocket", "gamora", "groot", "spiderman", "miles", "gwenspider", "spiderpig"]:
		_hero_icons[hid] = load(DB.hero_back(hid))
	for vid in ["redskull", "ultron", "taskmaster", "thanos", "proxima", "cull", "ebony", "kilmonger", "loki", "ronan", "goblin"]:
		_villain_icons[vid] = load(DB.villain(vid)["back"])
	for num in range(1, MODE_DATA.size() + 1):
		var tex: Texture2D = load("res://assets/ui/modes/mode_%d.png" % num)
		_mode_tex[num] = tex
	# 灰度着色器：未选中图标显示黑白
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tfloat g = dot(c.rgb, vec3(0.299, 0.587, 0.114));\n\tCOLOR = vec4(vec3(g), c.a);\n}"
	_gray_mat = ShaderMaterial.new()
	_gray_mat.shader = sh
	_create_hero_tooltip()
	_create_villain_panel_tooltip()
	_build_ui()
	# 让 tooltip 移到最上层，避免被步骤页遮挡
	move_child(_hero_tooltip, get_child_count() - 1)
	move_child(_villain_panel_tooltip, get_child_count() - 1)

## 创建英雄悬停强度窗口（跟随鼠标；固定大小框，显示名字 + 4 行"图标 x 数字"）
func _create_hero_tooltip() -> void:
	_hero_tooltip = PanelContainer.new()
	_hero_tooltip.visible = false
	_hero_tooltip.z_index = 100
	_hero_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_tooltip.add_theme_stylebox_override("panel", UiKit.panel_style(Color(0.10, 0.10, 0.18, 0.96)))
	# 固定大小：所有英雄显示框一致
	_hero_tooltip.custom_minimum_size = Vector2(240, 170)
	_hero_tooltip.size = Vector2(240, 170)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_hero_tooltip.add_child(v)
	_hero_tooltip_title = UiKit.label("", 22, Color(1, 0.9, 0.4))
	_hero_tooltip_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_hero_tooltip_title)
	# 图标
	var icon_map := {
		"move": load("res://assets/tokens/token_move.png"),
		"attack": load("res://assets/tokens/token_attack.png"),
		"heroic": load("res://assets/tokens/token_heroic.png"),
		"wild": load("res://assets/tokens/token_wild.png"),
	}
	_hero_row_labels.clear()
	for key in ["move", "attack", "heroic", "wild"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		v.add_child(row)
		var ic := TextureRect.new()
		ic.texture = icon_map[key]
		ic.custom_minimum_size = Vector2(30, 30)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ic)
		var num := UiKit.label("0", 20, Color.WHITE)
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(num)
		# 进度条容器（120 宽）：背景 + 填充（按数量宽度、按数量颜色）
		var bar_holder := Control.new()
		bar_holder.custom_minimum_size = Vector2(120, 14)
		bar_holder.size = Vector2(120, 14)
		bar_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(bar_holder)
		var bar_bg := ColorRect.new()
		bar_bg.color = Color(0.3, 0.3, 0.4, 0.5)
		bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar_holder.add_child(bar_bg)
		var bar_fill := ColorRect.new()
		bar_fill.color = Color(1, 0.3, 0.3)
		bar_fill.position = Vector2(0, 0)
		bar_fill.custom_minimum_size = Vector2(0, 14)
		bar_fill.size = Vector2(0, 14)
		bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar_holder.add_child(bar_fill)
		_hero_row_bars.append(bar_fill)
		_hero_row_labels.append(num)
	add_child(_hero_tooltip)

## 反派悬停面板背面预览浮层：鼠标指向反派时显示其"面板背面"图。
func _create_villain_panel_tooltip() -> void:
	_villain_panel_tooltip = PanelContainer.new()
	_villain_panel_tooltip.visible = false
	_villain_panel_tooltip.z_index = 100
	_villain_panel_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_villain_panel_tooltip.add_theme_stylebox_override("panel", UiKit.panel_style(Color(0.08, 0.08, 0.14, 0.95)))
	_villain_panel_tooltip.custom_minimum_size = Vector2(300, 140)
	_villain_panel_tooltip.size = Vector2(300, 140)
	_villain_panel_img = TextureRect.new()
	_villain_panel_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_villain_panel_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_villain_panel_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 面板背面为 1140x525 宽屏，缩放到适合悬停浮层高度
	_villain_panel_img.custom_minimum_size = Vector2(300, 138)
	_villain_panel_tooltip.add_child(_villain_panel_img)
	add_child(_villain_panel_tooltip)

## 显示反派面板背面预览：优先用 panel_back.png；缺素材的反派回退 back.png（立绘）。
func _show_villain_panel(vid: String) -> void:
	if _villain_panel_tooltip == null:
		return
	_villain_panel_vid = vid
	var tex: Texture2D = load("res://assets/cards/villains/%s/panel_back.png" % vid)
	if tex == null:
		tex = load("res://assets/cards/villains/%s/back.png" % vid)
	_villain_panel_img.texture = tex
	_villain_panel_tooltip.visible = true

func _hide_villain_panel() -> void:
	if _villain_panel_tooltip != null:
		_villain_panel_tooltip.visible = false
		_villain_panel_vid = ""

## 显示英雄强度窗口：内容 = 名字 + 4 行行动图标总数
func _show_hero_tooltip(hid: String) -> void:
	if _hero_tooltip == null:
		return
	_hero_tooltip_hid = hid
	_hero_tooltip_title.text = DB.hero_name(hid)
	var counts := {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
	for c in DB.hero_cards(hid):
		for s in c["symbols"]:
			if counts.has(s):
				counts[s] += 1
	var keys: Array = ["move", "attack", "heroic", "wild"]
	var bar_max := 120.0   # 进度条最大宽度
	for i in range(4):
		var n: int = counts[keys[i]]
		_hero_row_labels[i].text = "x %d" % n
		# 进度条宽度 = 数量/15 * 最大宽度（临时最大 15）
		var fill: ColorRect = _hero_row_bars[i]
		fill.size = Vector2(bar_max * mini(n, 15) / 15.0, 14)
		# 颜色：<=3 红；4-6 黄；>6 绿
		var col := Color.RED
		if n > 6:
			col = Color(0.2, 0.85, 0.3)
		elif n > 3:
			col = Color(0.95, 0.75, 0.2)
		fill.color = col
	_hero_tooltip.visible = true

func _hide_hero_tooltip() -> void:
	if _hero_tooltip != null:
		_hero_tooltip.visible = false
		_hero_tooltip_hid = ""

func _process(_delta: float) -> void:
	if _hero_tooltip != null and _hero_tooltip.visible:
		var mouse: Vector2 = get_global_mouse_position()
		var ts: Vector2 = _hero_tooltip.size
		var vs: Vector2 = get_viewport().get_visible_rect().size
		# 默认显示在鼠标右下方；若右/下会超出屏幕则翻转到左/上方
		var pos := mouse + Vector2(18, 6)
		if pos.x + ts.x > vs.x:
			pos.x = mouse.x - ts.x - 18
		if pos.y + ts.y > vs.y:
			pos.y = mouse.y - ts.y - 6
		pos.x = maxf(pos.x, 0)
		pos.y = maxf(pos.y, 0)
		_hero_tooltip.global_position = pos
	if _villain_panel_tooltip != null and _villain_panel_tooltip.visible:
		var mouse: Vector2 = get_global_mouse_position()
		var ts: Vector2 = _villain_panel_tooltip.size
		var vs: Vector2 = get_viewport().get_visible_rect().size
		var pos := mouse + Vector2(18, 6)
		if pos.x + ts.x > vs.x:
			pos.x = mouse.x - ts.x - 18
		if pos.y + ts.y > vs.y:
			pos.y = mouse.y - ts.y - 6
		pos.x = maxf(pos.x, 0)
		pos.y = maxf(pos.y, 0)
		_villain_panel_tooltip.global_position = pos

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "漫威联合 — 游戏设置"
	title.add_theme_font_size_override("font_size", 40)
	title.position = Vector2(60, 30)
	add_child(title)

	# 四步页面
	_step_pages[1] = _build_step_mode()
	_step_pages[2] = _build_step_heroes()
	_step_pages[3] = _build_step_villain()
	_step_pages[4] = _build_step_locations()

	# 底部导航
	_nav_back = Button.new()
	_nav_back.text = "◀ 上一步"
	_nav_back.custom_minimum_size = Vector2(180, 56)
	_nav_back.add_theme_font_size_override("font_size", 22)
	_nav_back.add_theme_color_override("font_color", Color.WHITE)
	_nav_back.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_nav_back.add_theme_constant_override("outline_size", 3)
	_nav_back.position = Vector2(60, 940)
	_nav_back.pressed.connect(_on_back)
	_add_black_border(_nav_back, Color(0.35, 0.35, 0.5))
	add_child(_nav_back)
	_nav_next = Button.new()
	_nav_next.text = "确定"
	_nav_next.custom_minimum_size = Vector2(260, 70)
	_nav_next.add_theme_font_size_override("font_size", 26)
	_nav_next.add_theme_color_override("font_color", Color.WHITE)
	_nav_next.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_nav_next.add_theme_constant_override("outline_size", 3)
	_nav_next.position = Vector2(830, 940)
	_nav_next.pressed.connect(_on_next)
	_add_black_border(_nav_next, Color(0.3, 0.55, 0.8))
	add_child(_nav_next)
	var back_main := Button.new()
	back_main.text = "返回主菜单"
	back_main.custom_minimum_size = Vector2(160, 50)
	back_main.add_theme_font_size_override("font_size", 20)
	back_main.add_theme_color_override("font_color", Color.WHITE)
	back_main.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	back_main.add_theme_constant_override("outline_size", 3)
	back_main.position = Vector2(1700, 940)
	back_main.pressed.connect(func(): UiKit.goto_scene("res://src/ui/MainMenu.tscn"))
	_add_black_border(back_main, Color(0.5, 0.3, 0.3))
	add_child(back_main)

	# 英雄初始不预选：按稳定槽位选择（P1→P2→…），取消某顺位不影响其他顺位
	_sync_slots()
	_show_step(1)

## 给按钮加黑色描边（正常/悬停/按下统一黑边）
func _add_black_border(btn: Button, color: Color) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color
		if state == "hover":
			sb.bg_color = color.lightened(0.12)
		elif state == "pressed":
			sb.bg_color = color.darkened(0.2)
		elif state == "disabled":
			sb.bg_color = Color(0.3, 0.3, 0.35)
		sb.border_color = Color(0, 0, 0, 0.95)
		sb.set_border_width_all(3)
		sb.corner_radius_top_left = 8
		sb.corner_radius_top_right = 8
		sb.corner_radius_bottom_left = 8
		sb.corner_radius_bottom_right = 8
		btn.add_theme_stylebox_override(state, sb)
	UiKit.attach_jelly(btn)

# ================================================================ 页面 1：模式

func _build_step_mode() -> Control:
	var page := Control.new()
	page.position = Vector2(0, 0)
	page.custom_minimum_size = Vector2(1920, 900)
	add_child(page)
	var t := Label.new()
	t.text = "选择游戏模式"
	t.add_theme_font_size_override("font_size", 34)
	t.position = Vector2(60, 80)
	page.add_child(t)
	# 右上角提示：目前只支持单模式，大部分模式尚未开发
	var notice := Label.new()
	notice.text = "目前只支持一个模式，且大部分模式尚未开发，请敬请期待"
	notice.add_theme_font_size_override("font_size", 20)
	notice.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	notice.position = Vector2(1180, 40)
	notice.custom_minimum_size = Vector2(660, 32)
	page.add_child(notice)
	# 右上角第二行提示：模式图标代表扩展
	var notice2 := Label.new()
	notice2.text = "模式图标仅代表该扩展带来的模式，与主题不完全一样，别搞错了"
	notice2.add_theme_font_size_override("font_size", 18)
	notice2.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	notice2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	notice2.position = Vector2(1180, 76)
	notice2.custom_minimum_size = Vector2(660, 30)
	page.add_child(notice2)
	# 模式图标网格：可滚动（数量增多时向下滚动；6 列 × 按数量行）
	var cols := 6
	var icon_size := Vector2(160, 170)  # 图标 + 名称
	var start := Vector2(60, 6)
	var gap := Vector2(16, 18)
	var mode_count: int = MODE_DATA.size()
	var rows := (mode_count + cols - 1) / cols
	var grid_h := rows * (icon_size.y + gap.y) + 12
	# 滚动容器（模式下方面板，高度固定，内容超高时滚动）
	var mode_scroll := ScrollContainer.new()
	mode_scroll.position = Vector2(0, 140)
	mode_scroll.custom_minimum_size = Vector2(1200, 720)
	mode_scroll.set_anchors_preset(Control.PRESET_TOP_LEFT)
	mode_scroll.size = Vector2(1200, 720)
	mode_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mode_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	page.add_child(mode_scroll)
	var mode_grid := Control.new()
	mode_grid.custom_minimum_size = Vector2(1200, grid_h)
	mode_grid.position = Vector2(0, 0)
	mode_scroll.add_child(mode_grid)
	for num in range(1, mode_count + 1):
		var m: Dictionary = MODE_DATA[num]
		var col: int = (num - 1) % cols
		var row: int = (num - 1) / cols
		var box := _make_mode_button(num, m["name"], start + Vector2(col * (icon_size.x + gap.x), row * (icon_size.y + gap.y)), icon_size, mode_grid)
		_mode_buttons[num] = box
	# 模式说明窗口（固定显示在右侧空白区；尺寸 640×708、固定字体）
	_mode_info = Control.new()
	_mode_info.position = Vector2(1276, 186)
	_mode_info.size = Vector2(640, 708)
	_mode_info.custom_minimum_size = Vector2(640, 708)
	_mode_info.visible = false
	page.add_child(_mode_info)
	var mibg := TextureRect.new()
	mibg.texture = _mode_info_bg
	mibg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mibg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mibg.set_anchors_preset(Control.PRESET_FULL_RECT)
	mibg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode_info.add_child(mibg)
	_mode_info_title = Label.new()
	_mode_info_title.add_theme_font_size_override("font_size", 30)
	_mode_info_title.add_theme_color_override("font_color", Color(0.85, 0.12, 0.12))
	_mode_info_title.add_theme_color_override("font_outline_color", Color(1, 1, 1))
	_mode_info_title.add_theme_constant_override("outline_size", 3)
	if _hand_font != null:
		_mode_info_title.add_theme_font_override("font", _hand_font)
	_mode_info_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_info_title.position = Vector2(50, 188)
	_mode_info_title.custom_minimum_size = Vector2(540, 44)
	_mode_info.add_child(_mode_info_title)
	_mode_info_desc = Label.new()
	_mode_info_desc.add_theme_font_size_override("font_size", 21)
	_mode_info_desc.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05))
	_mode_info_desc.add_theme_color_override("font_outline_color", Color(1, 1, 1))
	_mode_info_desc.add_theme_constant_override("outline_size", 2)
	if _hand_font != null:
		_mode_info_desc.add_theme_font_override("font", _hand_font)
	_mode_info_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_info_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_info_desc.position = Vector2(50, 240)
	_mode_info_desc.custom_minimum_size = Vector2(540, 365)
	_mode_info.add_child(_mode_info_desc)
	_update_mode_highlight()
	return page

## 模式图标按钮：图标 + 下方白字名称
func _make_mode_button(num: int, name: String, pos: Vector2, size: Vector2, parent: Control) -> Control:
	var box := Control.new()
	box.position = pos
	box.size = size
	box.custom_minimum_size = size
	var tr := TextureRect.new()
	tr.texture = _mode_tex[num]
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.position = Vector2(2, 0)
	tr.custom_minimum_size = Vector2(size.x - 4, size.y - 34)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tr)
	var lb := Label.new()
	lb.text = name
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.add_theme_font_size_override("font_size", 16)
	lb.add_theme_color_override("font_color", Color.WHITE)
	lb.position = Vector2(0, size.y - 30)
	lb.custom_minimum_size = Vector2(size.x, 30)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lb)
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.text = ""
	btn.pressed.connect(_on_mode_selected.bind(num))
	btn.mouse_entered.connect(_on_mode_hover.bind(num))
	btn.mouse_exited.connect(_on_mode_hover_end)
	UiKit.attach_jelly(btn)
	box.add_child(btn)
	parent.add_child(box)
	return box

## 显示指定模式的说明窗口（固定显示在右侧空白区）
func _show_mode_info(num: int) -> void:
	if _mode_info == null:
		return
	var desc: String = _mode_info_data.get(str(num), "")
	if desc == "":
		_mode_info.visible = false
		return
	_mode_info_title.text = MODE_DATA[num]["name"]
	_mode_info_desc.text = desc
	_mode_info.visible = true
	_mode_info.get_parent().move_child(_mode_info, _mode_info.get_parent().get_child_count() - 1)

## 悬停模式：右侧固定区显示该模式说明
func _on_mode_hover(num: int) -> void:
	_show_mode_info(num)

## 移出模式：显示当前选中模式说明（若有选中），否则隐藏
func _on_mode_hover_end() -> void:
	if _mode_info == null:
		return
	if _selected_mode_id != 0:
		_show_mode_info(_selected_mode_id)
	else:
		_mode_info.visible = false

func _on_mode_selected(num: int) -> void:
	_selected_mode_id = num
	var m: Dictionary = MODE_DATA[num]
	if m.get("impl", false):
		# 已实现模式：设置游戏模式与挑战
		_mode = m["mode"]
		_selected_challenge = m["challenge"]
		if _mode == "shield":
			_hero_count = 3
			_sync_slots()
		elif _mode == "iw":
			# 无限战争战役：默认前 3 局对手为 暗夜比邻星/黑矮星/乌木侯（顺序固定）
			_campaign_slots = ["proxima", "cull", "ebony"]
		else:
			# 非无限战争模式：清空战役残留（避免别的模式出现无限战争提示）
			_campaign_slots = ["", "", ""]
			if _campaign_label != null:
				_campaign_label.text = ""
	_update_mode_highlight()
	_update_hero_count_label()
	_show_mode_info(num)  # 选中后说明固定在右侧
	if _step == 1:
		_nav_next.disabled = false  # 已选模式，允许进入下一步
	_update_hero_buttons()
	# 模式变化后重新渲染反派页（iw 模式布局/排序与基础模式不同）
	_render_villains()

func _update_mode_highlight() -> void:
	for num in _mode_buttons:
		var b: Control = _mode_buttons[num]
		var tr: TextureRect = b.get_child(0)
		if _selected_mode_id == 0 or num == _selected_mode_id:
			tr.material = null
		else:
			tr.material = _gray_mat
		_set_card_selected(b, num == _selected_mode_id)

# ================================================================ 未上架模式弹窗

## 弹窗提示所选模式未上架，带「返回」键关闭
func _show_unavailable_dialog(mode_name: String) -> void:
	if _modal != null:
		_close_modal()
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	var panel := Panel.new()
	panel.position = Vector2(610, 380)
	panel.size = Vector2(700, 320)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.13, 0.21)
	sb.corner_radius_top_left = 18
	sb.corner_radius_top_right = 18
	sb.corner_radius_bottom_left = 18
	sb.corner_radius_bottom_right = 18
	sb.border_color = Color(0.35, 0.35, 0.5)
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	overlay.add_child(panel)
	var msg := Label.new()
	msg.text = "「%s」模式未上架\n请先选择别的模式" % mode_name
	msg.add_theme_font_size_override("font_size", 30)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.position = Vector2(30, 40)
	msg.size = Vector2(640, 170)
	panel.add_child(msg)
	var ok := Button.new()
	ok.text = "返 回"
	ok.custom_minimum_size = Vector2(200, 60)
	ok.add_theme_font_size_override("font_size", 24)
	ok.position = Vector2(250, 235)
	ok.size = Vector2(200, 60)
	ok.pressed.connect(_close_modal)
	panel.add_child(ok)
	add_child(overlay)
	_modal = overlay

func _close_modal() -> void:
	if _modal != null:
		_modal.queue_free()
		_modal = null

# ================================================================ 页面 2：英雄

func _build_step_heroes() -> Control:
	var page := Control.new()
	page.position = Vector2(0, 0)
	page.custom_minimum_size = Vector2(1920, 900)
	add_child(page)
	var t := Label.new()
	t.text = "选择英雄与人数"
	t.add_theme_font_size_override("font_size", 34)
	t.position = Vector2(60, 90)
	page.add_child(t)
	_make_sort_buttons(Vector2(560, 95), page)
	# 搜索框
	_hero_search = LineEdit.new()
	_hero_search.position = Vector2(840, 95)
	_hero_search.custom_minimum_size = Vector2(380, 40)
	_hero_search.placeholder_text = "搜索英雄名字…"
	_hero_search.add_theme_font_size_override("font_size", 20)
	_hero_search.text_changed.connect(_on_hero_search)
	page.add_child(_hero_search)

	# 人数（基础模式显示；神盾局固定 3，不显示加减）
	_count_row = Control.new()
	_count_row.position = Vector2(60, 140)
	page.add_child(_count_row)
	_count_label = Label.new()
	_count_label.text = "英雄人数（热座 1-4 人）"
	_count_label.add_theme_font_size_override("font_size", 24)
	_count_label.position = Vector2(0, 0)
	_count_row.add_child(_count_label)
	_hero_count_label = Label.new()
	_hero_count_label.add_theme_font_size_override("font_size", 22)
	_hero_count_label.position = Vector2(0, 32)
	_count_row.add_child(_hero_count_label)
	# 白色圆形加减按钮样式
	var white_sb := StyleBoxFlat.new()
	white_sb.bg_color = Color.WHITE
	white_sb.set_corner_radius_all(24)
	var white_sb_pressed := StyleBoxFlat.new()
	white_sb_pressed.bg_color = Color(0.8, 0.8, 0.8)
	white_sb_pressed.set_corner_radius_all(24)
	_count_minus = Button.new()
	_count_minus.text = "-"
	_count_minus.add_theme_font_size_override("font_size", 28)
	_count_minus.add_theme_color_override("font_color", Color(0.1, 0.1, 0.15))
	_count_minus.add_theme_stylebox_override("normal", white_sb)
	_count_minus.add_theme_stylebox_override("pressed", white_sb_pressed)
	_count_minus.add_theme_stylebox_override("hover", white_sb)
	_count_minus.custom_minimum_size = Vector2(48, 48)
	_count_minus.position = Vector2(300, 0)
	_count_minus.pressed.connect(func(): _set_hero_count(_hero_count - 1))
	_count_row.add_child(_count_minus)
	_count_plus = Button.new()
	_count_plus.text = "+"
	_count_plus.add_theme_font_size_override("font_size", 28)
	_count_plus.add_theme_color_override("font_color", Color(0.1, 0.1, 0.15))
	_count_plus.add_theme_stylebox_override("normal", white_sb)
	_count_plus.add_theme_stylebox_override("pressed", white_sb_pressed)
	_count_plus.add_theme_stylebox_override("hover", white_sb)
	_count_plus.custom_minimum_size = Vector2(48, 48)
	_count_plus.position = Vector2(360, 0)
	_count_plus.pressed.connect(func(): _set_hero_count(_hero_count + 1))
	_count_row.add_child(_count_plus)
	_update_hero_count_label()

	# 英雄卡片（滚动容器，限高避免遮挡下方按钮）
	_hero_scroll = ScrollContainer.new()
	_hero_scroll.position = Vector2(0, 210)
	_hero_scroll.size = Vector2(1920, 690)
	_hero_scroll.custom_minimum_size = Vector2(1920, 690)
	_hero_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_hero_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	page.add_child(_hero_scroll)
	_hero_grid = Control.new()
	_hero_grid.position = Vector2(0, 0)
	_hero_grid.custom_minimum_size = Vector2(1920, 1400)
	_hero_scroll.add_child(_hero_grid)
	_render_heroes()
	return page

## 英雄搜索：过滤并重排匹配的英雄到左上角（限定在滚动内容区内）
func _on_hero_search(_t: String) -> void:
	_render_heroes()

# ================================================================ 页面 3：地点

func _build_step_locations() -> Control:
	var page := Control.new()
	page.position = Vector2(0, 0)
	page.custom_minimum_size = Vector2(1920, 900)
	add_child(page)
	var t := Label.new()
	t.text = "选择扩展包地点"
	t.add_theme_font_size_override("font_size", 34)
	t.position = Vector2(60, 100)
	page.add_child(t)
	var tip := Label.new()
	tip.text = "勾选要加入本局随机池的地点扩展（每局随机取 6 张地点）"
	tip.add_theme_font_size_override("font_size", 20)
	tip.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	tip.position = Vector2(60, 150)
	page.add_child(tip)
	# 列出所有地点扩展（去重），checkbox 勾选
	var exps: Array = []
	var exp_count := {}
	for id in DB.locations.keys():
		var e: String = DB.location(id).get("expansion", "基础盒")
		if not exps.has(e):
			exps.append(e)
			exp_count[e] = 0
		exp_count[e] = int(exp_count[e]) + 1
	var y := 220
	for e in exps:
		# 决战专属地点：仅无限战争战役第 4 局（决战）自动使用，设置页不提供勾选
		if e == "无限战争决战":
			continue
		var box := Control.new()
		box.position = Vector2(60, y)
		box.size = Vector2(700, 70)
		var pnl := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.15, 0.15, 0.24)
		sb.corner_radius_top_left = 10
		sb.corner_radius_top_right = 10
		sb.corner_radius_bottom_left = 10
		sb.corner_radius_bottom_right = 10
		pnl.add_theme_stylebox_override("panel", sb)
		pnl.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.add_child(pnl)
		var cb := CheckButton.new()
		cb.text = "%s（%d 张地点）" % [e, exp_count[e]]
		cb.add_theme_font_size_override("font_size", 24)
		cb.position = Vector2(20, 12)
		cb.custom_minimum_size = Vector2(400, 46)
		cb.button_pressed = _selected_expansions.has(e)
		cb.toggled.connect(_toggle_expansion.bind(e))
		box.add_child(cb)
		page.add_child(box)
		y += 90
	return page

func _toggle_expansion(on: bool, e: String) -> void:
	if on:
		if not _selected_expansions.has(e):
			_selected_expansions.append(e)
	else:
		_selected_expansions.erase(e)

# ================================================================ 页面 4：反派

func _build_step_villain() -> Control:
	var page := Control.new()
	page.position = Vector2(0, 0)
	page.custom_minimum_size = Vector2(1920, 900)
	add_child(page)
	var t := Label.new()
	t.text = "选择反派"
	t.add_theme_font_size_override("font_size", 34)
	t.position = Vector2(60, 90)
	page.add_child(t)
	_make_sort_buttons(Vector2(560, 95), page)
	# 搜索框（对齐英雄页：排序按钮右侧）
	_villain_search = LineEdit.new()
	_villain_search.position = Vector2(840, 95)
	_villain_search.custom_minimum_size = Vector2(380, 40)
	_villain_search.placeholder_text = "搜索反派名字…"
	_villain_search.add_theme_font_size_override("font_size", 20)
	_villain_search.text_changed.connect(_on_villain_search)
	page.add_child(_villain_search)
	# 无限战争战役：前 3 局反派顺序（P1/P2/P3 槽位；放在搜索框右侧，不遮挡标题与卡片）
	_campaign_label = Label.new()
	_campaign_label.text = ""
	_campaign_label.add_theme_font_size_override("font_size", 20)
	_campaign_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_campaign_label.position = Vector2(1240, 100)
	_campaign_label.custom_minimum_size = Vector2(600, 28)
	_campaign_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_campaign_label)

	# 反派卡片（滚动容器，限高避免遮挡上方控件与下方按钮，对齐英雄页）
	_villain_scroll = ScrollContainer.new()
	_villain_scroll.position = Vector2(0, 210)
	_villain_scroll.size = Vector2(1920, 690)
	_villain_scroll.custom_minimum_size = Vector2(1920, 690)
	_villain_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_villain_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	page.add_child(_villain_scroll)
	_villain_grid = Control.new()
	_villain_grid.position = Vector2(0, 0)
	_villain_grid.custom_minimum_size = Vector2(1920, 900)
	_villain_scroll.add_child(_villain_grid)
	_render_villains()
	return page

# ================================================================ 排序

func _make_sort_buttons(pos: Vector2, parent: Control) -> void:
	var x := pos.x
	for sm in [["alpha", "按首字母"], ["expansion", "按扩展"]]:
		var b := Button.new()
		b.text = sm[1]
		b.custom_minimum_size = Vector2(130, 40)
		b.add_theme_font_size_override("font_size", 18)
		b.position = Vector2(x, pos.y)
		b.pressed.connect(_on_sort_mode.bind(sm[0]))
		parent.add_child(b)
		_sort_buttons[sm[0]] = b
		x += 140
	_update_sort_highlight()

func _on_sort_mode(mode: String) -> void:
	_sort_mode = mode
	_update_sort_highlight()
	# 反派始终渲染进滚动内容区 _villain_grid，限定在上方控件与下方按钮之间的范围内
	_render_villains()
	# 英雄始终渲染进滚动内容区 _hero_grid，限定在上方控件与下方按钮之间的范围内
	_render_heroes()

## 反派搜索：过滤并重排匹配的反派到左上角（限定在滚动内容区内）
func _on_villain_search(_t: String) -> void:
	_render_villains()

func _update_sort_highlight() -> void:
	for sm in _sort_buttons:
		var b: Button = _sort_buttons[sm]
		b.modulate = Color(1.6, 1.4, 1.0) if sm == _sort_mode else Color.WHITE

func _group_ids(ids: Array, exp_map: Dictionary, sort_map: Dictionary) -> Array:
	if _sort_mode == "alpha":
		var sorted := ids.duplicate()
		sorted.sort_custom(func(a: String, b: String) -> bool: return str(sort_map[a]) < str(sort_map[b]))
		return [{"name": "", "ids": sorted}]
	var groups := {}
	var order: Array = []
	for id in ids:
		var ename: String = exp_map[id]
		if not groups.has(ename):
			groups[ename] = []
			order.append(ename)
		groups[ename].append(id)
	var out: Array = []
	for ename in order:
		var gids: Array = groups[ename]
		gids.sort_custom(func(a: String, b: String) -> bool: return str(sort_map[a]) < str(sort_map[b]))
		out.append({"name": ename, "ids": gids})
	return out

func _render_villains() -> void:
	var parent: Control = _villain_grid
	if parent == null:
		return
	for vid in _villain_buttons:
		_free_card(_villain_buttons[vid])
	_villain_buttons.clear()
	_clear_exp_labels(parent)
	# 搜索词：非空时只显示匹配反派，并从左上角重排（过滤后不保留空位）
	var q: String = _villain_search.text.strip_edges() if _villain_search != null else ""
	var groups: Array
	if _mode == "iw" and _sort_mode == "alpha" and q == "":
		# 无限战争战役（按首字母）：三手下置前（暗夜比邻星/黑矮星/乌木侯），
		# 剩余按拼音排列，灭霸置暗放最后
		var rest_ids: Array = ["redskull", "ultron", "taskmaster", "thanos"]
		rest_ids.sort_custom(func(a: String, b: String) -> bool: return str(VILLAIN_SORT[a]) < str(VILLAIN_SORT[b]))
		groups = [
			{"name": "无限战争（前3局默认反派，向换反派先取消选择）", "ids": ["proxima", "cull", "ebony"]},
			{"name": "其他反派", "ids": rest_ids},
		]
	else:
		var all_ids: Array = ["redskull", "ultron", "taskmaster", "thanos", "proxima", "cull", "ebony", "kilmonger", "loki", "ronan", "goblin"]
		if q != "":
			# 搜索过滤：所有匹配反派合并成一个列表，按拼音重排，左上角紧凑排列
			var matched: Array = []
			for vid in all_ids:
				if DB.villain_name(vid).contains(q) or String(vid).to_lower().contains(q.to_lower()):
					matched.append(vid)
			matched.sort_custom(func(a: String, b: String) -> bool: return str(VILLAIN_SORT[a]) < str(VILLAIN_SORT[b]))
			groups = [{"name": "", "ids": matched}]
		else:
			groups = _group_ids(all_ids, VILLAIN_EXP, VILLAIN_SORT)
	var y := 0.0
	for g in groups:
		if g["ids"].is_empty():
			continue
		if _sort_mode == "expansion" or (_mode == "iw" and q == ""):
			_mk_group_label(g["name"], Vector2(60, y), parent)
			y += 28
		var x := 60.0
		var col := 0
		for vid in g["ids"]:
			# 每行最多 11 个，超出换行
			if col >= 11:
				col = 0
				x = 60.0
				y += 180
			var box := _make_card_button(_villain_icons[vid], DB.villain_name(vid), Vector2(x, y), Vector2(140, 180), parent)
			# 无限战争战役：灭霸仅决战可用，前 3 局置暗显示
			if _mode == "iw" and vid == "thanos":
				box.modulate = Color(0.35, 0.35, 0.4)
			var bbtn: Button = box.get_child(box.get_child_count() - 1)
			bbtn.pressed.connect(_on_villain_selected.bind(vid))
			bbtn.mouse_entered.connect(_show_villain_panel.bind(vid))
			bbtn.mouse_exited.connect(_hide_villain_panel)
			_villain_buttons[vid] = box
			x += 160
			col += 1
		# 分组末尾 y 递增（保证下一组从新行开始）
		y += 190
	# 网格高度跟随内容（超出滚动区才出现滚动条；内容少时填满可视区，避免图标顶格）
	parent.custom_minimum_size = Vector2(1920, maxf(y, 690))
	_update_villain_highlight()

func _render_heroes() -> void:
	var parent: Control = _hero_grid
	if parent == null:
		return
	for hid in _hero_buttons:
		_free_card(_hero_buttons[hid])
	_hero_buttons.clear()
	_clear_exp_labels(parent)
	# 搜索词：非空时只显示匹配英雄，并从左上角重排（过滤后不保留空位）
	var q: String = _hero_search.text.strip_edges() if _hero_search != null else ""
	var all_ids: Array = ["cap", "ironman", "cmarvel", "hulk", "widow", "winter", "shuri", "blackpanther", "korg", "valkyrie", "betaray", "thor", "starlord", "rocket", "gamora", "groot", "spiderman", "miles", "gwenspider", "spiderpig"]
	var groups: Array
	if q != "":
		# 搜索过滤：所有匹配英雄合并成一个列表，按拼音重排，左上角紧凑排列
		var matched: Array = []
		for hid in all_ids:
			if DB.hero_name(hid).contains(q) or String(hid).to_lower().contains(q.to_lower()):
				matched.append(hid)
		matched.sort_custom(func(a: String, b: String) -> bool: return str(HERO_SORT[a]) < str(HERO_SORT[b]))
		groups = [{"name": "", "ids": matched}]
	else:
		groups = _group_ids(all_ids, HERO_EXP, HERO_SORT)
	var y := 0.0
	for g in groups:
		if g["ids"].is_empty():
			continue
		if _sort_mode == "expansion" and q == "":
			_mk_group_label(g["name"], Vector2(60, y), parent)
			y += 28
		var x := 60.0
		var col := 0
		for hid in g["ids"]:
			# 每行最多 12 个，超出换行
			if col >= 12:
				col = 0
				x = 60.0
				y += 170
			var box := _make_card_button(_hero_icons[hid], DB.hero_name(hid), Vector2(x, y), Vector2(130, 160), parent)
			var bbtn: Button = box.get_child(box.get_child_count() - 1)
			bbtn.pressed.connect(_on_hero_toggle.bind(hid))
			bbtn.mouse_entered.connect(_show_hero_tooltip.bind(hid))
			bbtn.mouse_exited.connect(_hide_hero_tooltip)
			_hero_buttons[hid] = box
			x += 150
			col += 1
		# 分组末尾 y 递增（保证下一组从新行开始）
		y += 170
	# 网格高度跟随内容（超出滚动区才出现滚动条；内容少时填满可视区，避免图标顶格）
	parent.custom_minimum_size = Vector2(1920, maxf(y, 690))
	_update_hero_buttons()

func _mk_group_label(text: String, pos: Vector2, parent: Control) -> void:
	var l := Label.new()
	l.text = "■ " + text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(0.8, 0.9, 1))
	l.position = pos
	l.custom_minimum_size = Vector2(300, 26)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	_exp_labels.append(l)

func _clear_exp_labels(parent: Control) -> void:
	# 只清除属于该页面的分组标签（英雄页与反派页各有自己的标签）
	var keep: Array = []
	for l in _exp_labels:
		if is_instance_valid(l):
			if l.get_parent() == parent:
				l.queue_free()
			else:
				keep.append(l)
	_exp_labels = keep

func _free_card(box: Control) -> void:
	if box.has_meta("sel_frames"):
		for f in box.get_meta("sel_frames"):
			if is_instance_valid(f):
				f.queue_free()
		box.remove_meta("sel_frames")
	if is_instance_valid(box):
		box.queue_free()

## 卡片按钮：行动牌背面图 + 名字
func _make_card_button(tex: Texture2D, name: String, pos: Vector2, size: Vector2, parent: Control) -> Control:
	var box := Control.new()
	box.position = pos
	box.size = size
	box.custom_minimum_size = size
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.position = Vector2(12, 6)
	tr.custom_minimum_size = Vector2(size.x - 24, size.y - 46)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tr)
	var lb := Label.new()
	lb.text = name
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.add_theme_font_size_override("font_size", 20)
	lb.position = Vector2(0, size.y - 40)
	lb.custom_minimum_size = Vector2(size.x, 36)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lb)
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.text = ""
	UiKit.attach_jelly(btn)
	box.add_child(btn)
	parent.add_child(box)
	return box

# ================================================================ 导航

func _show_step(n: int) -> void:
	_step = n
	for k in _step_pages:
		_step_pages[k].visible = (int(k) == n)
	_nav_back.visible = n > 1
	_nav_next.text = "开始游戏！" if n == 4 else "确定"
	# 第 1 步：未选择模式时"确定"不可点击
	_nav_next.disabled = (n == 1 and _selected_mode_id == 0)

func _on_back() -> void:
	if _step <= 1:
		return
	# 返回上一步时重置当前页面的选择（避免残留上一次选择）
	match _step:
		2:  # 离开英雄页：清空英雄选择
			for i in range(_hero_slots.size()):
				_hero_slots[i] = ""
			_refresh_selected()
			_update_hero_buttons()
		3:  # 离开反派页：清空反派选择（含战役顺序与 iw 提示）
			_selected_villain = ""
			_campaign_slots = ["", "", ""]
			if _campaign_label != null:
				_campaign_label.text = ""
			_update_villain_highlight()
		4:  # 离开地点页：清空地点扩展
			_selected_expansions = ["基础盒"]
	_show_step(_step - 1)

func _on_next() -> void:
	if _step == 1:
		if _selected_mode_id == 0:
			Events.emit_toast("请先选择一个游戏模式")
			return
		if not MODE_DATA[_selected_mode_id].get("impl", false):
			_show_unavailable_dialog(MODE_DATA[_selected_mode_id]["name"])
			return
		_show_step(2)
	elif _step == 2:
		var limit := 3 if _mode == "shield" else _hero_count
		if _selected_heroes.size() != limit:
			Events.emit_toast("请选择 %d 名英雄" % limit)
			return
		_show_step(3)
	elif _step == 3:
		if _mode == "iw":
			for i in range(3):
				if _campaign_slots[i] == "":
					Events.emit_toast("请为战役第 %d 局选择反派（前 3 局对手顺序）" % (i + 1))
					return
		else:
			if _selected_villain == "":
				Events.emit_toast("请选择反派")
				return
		_show_step(4)
	elif _step == 4:
		# 战役模式：前 3 局建议使用「无限战争」地点，决战固定「无限战争决战」专属地点
		if _mode == "iw":
			if not _selected_expansions.has("无限战争"):
				_selected_expansions.append("无限战争")
		if _selected_expansions.size() == 0:
			Events.emit_toast("请至少勾选一个地点扩展")
			return
		_on_start()

# ================================================================ 选择逻辑

func _set_hero_count(n: int) -> void:
	_hero_count = clampi(n, 1, 4)
	_sync_slots()
	_update_hero_count_label()
	_update_hero_buttons()

## 同步槽位数组长度与人数上限（扩补空槽/截断），并重建紧凑列表
func _sync_slots() -> void:
	var limit := 3 if _mode == "shield" else _hero_count
	while _hero_slots.size() < limit:
		_hero_slots.append("")
	if _hero_slots.size() > limit:
		_hero_slots.resize(limit)
	_refresh_selected()

## 由槽位数组派生出紧凑的英雄列表（顺位 = 槽位顺序）
func _refresh_selected() -> void:
	_selected_heroes.clear()
	for s in _hero_slots:
		if s != "":
			_selected_heroes.append(s)

func _update_hero_count_label() -> void:
	if _hero_count_label != null:
		if _mode == "shield":
			# 神盾局单人模式：固定 3 名英雄，不显示人数标题与加减按钮
			_hero_count_label.text = "神盾局单人模式：固定 3 名英雄（牌组合并）"
			if _count_label != null:
				_count_label.visible = false
			if _count_minus != null:
				_count_minus.visible = false
			if _count_plus != null:
				_count_plus.visible = false
		else:
			_hero_count_label.text = "当前：%d 人（需选 %d 名英雄）" % [_hero_count, _hero_count]
			if _count_label != null:
				_count_label.visible = true
			if _count_minus != null:
				_count_minus.visible = true
			if _count_plus != null:
				_count_plus.visible = true

func _on_villain_selected(vid: String) -> void:
	if _mode == "iw":
		# 无限战争战役：灭霸只能在第 4 局决战出现，前三局禁止选择
		if vid == "thanos":
			Events.emit_toast("灭霸是最终决战的反派，前 3 局不能选择他")
			return
		# 填入最低的空槽位（P1 优先）；点已选反派只取消该顺位
		var slot: int = _campaign_slots.find(vid)
		if slot != -1:
			_campaign_slots[slot] = ""
		else:
			var empty: int = _campaign_slots.find("")
			if empty != -1:
				_campaign_slots[empty] = vid
			else:
				Events.emit_toast("已达 3 个反派上限（前 3 局），请先取消一个再选择")
		_update_villain_highlight()
		return
	_selected_villain = vid
	_update_villain_highlight()

func _set_card_selected(box: Control, on: bool, frame_color: Color = Color(1, 1, 1)) -> void:
	if box.has_meta("sel_frames"):
		for f in box.get_meta("sel_frames"):
			if is_instance_valid(f):
				f.queue_free()
		box.remove_meta("sel_frames")
	if not on:
		return
	var frames: Array = []
	for inset in [4, 1]:
		var alpha := 0.4 if inset == 4 else 1.0
		var w := 2
		var r := Rect2(box.position - Vector2(inset, inset), box.size + Vector2(inset * 2, inset * 2))
		for side in range(4):
			var cr := ColorRect.new()
			cr.color = Color(frame_color.r, frame_color.g, frame_color.b, alpha)
			cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			match side:
				0:
					cr.position = r.position
					cr.size = Vector2(r.size.x, w)
				1:
					cr.position = r.position + Vector2(0, r.size.y - w)
					cr.size = Vector2(r.size.x, w)
				2:
					cr.position = r.position
					cr.size = Vector2(w, r.size.y)
				3:
					cr.position = r.position + Vector2(r.size.x - w, 0)
					cr.size = Vector2(w, r.size.y)
			box.get_parent().add_child(cr)
			box.get_parent().move_child(cr, box.get_index())
			frames.append(cr)
	box.set_meta("sel_frames", frames)

func _update_villain_highlight() -> void:
	if _mode == "iw":
		# 战役模式：高亮已选反派（按顺位着不同颜色）
		var slot_colors: Array = [Color(1, 0.35, 0.35), Color(1, 0.7, 0.3), Color(0.45, 1, 0.45)]
		for vid in _villain_buttons:
			var slot: int = _campaign_slots.find(vid)
			var b: Control = _villain_buttons[vid]
			if slot != -1:
				_set_card_selected(b, true, slot_colors[slot])
			else:
				_set_card_selected(b, false)
		if _campaign_label != null:
			var parts: Array = []
			for i in range(3):
				var v: String = _campaign_slots[i]
				if v == "":
					parts.append("第%d局：未选" % (i + 1))
				else:
					parts.append("第%d局：%s" % [(i + 1), DB.villain_name(v)])
			_campaign_label.text = "前3局顺序（灭霸仅决战，不可选）：  " + "  ｜  ".join(parts)
		return
	for vid in _villain_buttons:
		var b: Control = _villain_buttons[vid]
		_set_card_selected(b, vid == _selected_villain)

## 英雄点击：填入最低的空槽位（P1 优先）；点已选英雄只取消该顺位，其他顺位不变
func _on_hero_toggle(hid: String) -> void:
	var slot: int = _hero_slots.find(hid)
	if slot != -1:
		_hero_slots[slot] = ""
	else:
		var empty: int = _hero_slots.find("")
		if empty != -1:
			_hero_slots[empty] = hid
		else:
			Events.emit_toast("已达 %d 名英雄上限，请先取消一名英雄再选择" % _hero_slots.size())
	_refresh_selected()
	_update_hero_buttons()

## 顺位对应的彩虹色（超出 7 人循环使用）
func _slot_color(idx: int) -> Color:
	return HERO_SLOT_COLORS[idx % HERO_SLOT_COLORS.size()]

func _update_hero_buttons() -> void:
	for hid in _hero_buttons:
		var b: Control = _hero_buttons[hid]
		var idx: int = _hero_slots.find(hid)
		var selected: bool = idx != -1
		if selected:
			var col: Color = _slot_color(idx)
			# 已选英雄：对应顺位的彩虹色框（与其他框颜色不同）
			_set_card_selected(b, true, col)
			_update_p_label(b, idx + 1, col)
		else:
			_set_card_selected(b, false)
			_update_p_label(b, 0, Color.WHITE)
	_update_hero_count_label()

## 顺位标签：卡片左上角显示 Px（x 为第几位玩家），颜色与框一致；未选中则隐藏
func _update_p_label(box: Control, p: int, color: Color) -> void:
	var lb: Label = null
	if box.has_meta("p_label") and is_instance_valid(box.get_meta("p_label")):
		lb = box.get_meta("p_label")
	else:
		lb = Label.new()
		lb.add_theme_font_size_override("font_size", 22)
		lb.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		lb.add_theme_constant_override("outline_size", 5)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.position = Vector2(0, 0)
		lb.custom_minimum_size = Vector2(46, 30)
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(lb)
		box.set_meta("p_label", lb)
	lb.visible = p > 0
	lb.add_theme_color_override("font_color", color)
	if p > 0:
		lb.text = "P%d" % p

func _on_start() -> void:
	Game.pending_setup = {
		"villain": _selected_villain,
		"heroes": _selected_heroes.duplicate(),
		"challenge": _selected_challenge,
		"mode": _mode,
		"expansions": _selected_expansions.duplicate(),
		"debug_full_slots": Game.debug_full_slots,
		"peek_hands": Game.peek_hands,
	}
	if _mode == "iw":
		Game.pending_setup["campaign_order"] = _campaign_slots.duplicate()
		# 战役模式：第 1 局用顺序中的第 1 个反派
		Game.pending_setup["villain"] = _campaign_slots[0]
		Game.pending_campaign = {"game": 1, "order": _campaign_slots.duplicate(), "stones_collected": [], "energy_unlocked": []}
	UiKit.goto_scene("res://src/ui/Board.tscn")
