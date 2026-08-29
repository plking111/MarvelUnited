extends Control
## 设置界面（三步向导）：1选择模式 → 2选择英雄/人数 → 3选择反派/挑战。

var _step := 1
var _mode := "base"  # base / shield
var _hero_count := 3
var _selected_heroes: Array = []   # 紧凑列表（按槽位顺序，供开局使用）
var _hero_slots: Array = []        # 稳定槽位数组：长度=人数上限，元素为英雄id或""（空槽）
var _selected_villain := "redskull"
var _selected_challenge := "none"
var _selected_expansions: Array = ["基础盒"]  # 地点扩展选择

var _villain_buttons: Dictionary = {}
var _hero_buttons: Dictionary = {}
var _hero_count_label: Label
var _mode_buttons: Dictionary = {}
var _count_row: Control
var _hero_icons: Dictionary = {}
var _villain_icons: Dictionary = {}
var _sort_mode := "alpha"  # alpha（首字母）/ expansion（扩展）
var _sort_buttons: Dictionary = {}
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

# 排序数据：拼音首字母 + 所属扩展盒（目前全部为基础盒）
const VILLAIN_SORT := {"redskull": "H", "ultron": "A", "taskmaster": "M"}
const HERO_SORT := {"cap": "M", "ironman": "G", "cmarvel": "J", "hulk": "L", "widow": "H"}
const VILLAIN_EXP := {"redskull": "基础盒", "ultron": "基础盒", "taskmaster": "基础盒"}
const HERO_EXP := {"cap": "基础盒", "ironman": "基础盒", "cmarvel": "基础盒", "hulk": "基础盒", "widow": "基础盒"}

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

# 27 个模式按钮：编号对应 assets/ui/modes/mode_N.png
const MODE_DATA := {
	1: {"name": "基础模式", "mode": "base", "challenge": "none", "impl": true},
	2: {"name": "中等挑战模式", "mode": "base", "challenge": "moderate", "impl": true},
	3: {"name": "困难挑战模式", "mode": "base", "challenge": "hard", "impl": true},
	4: {"name": "英雄挑战模式", "mode": "base", "challenge": "heroic", "impl": true},
	5: {"name": "神盾局&泽维尔单人模式", "mode": "shield", "challenge": "none", "impl": true},
	6: {"name": "无限战争模式", "impl": false},
	7: {"name": "超级反派模式", "impl": false},
	8: {"name": "濒危场景模式", "impl": false},
	9: {"name": "叛徒挑战模式", "impl": false},
	10: {"name": "B计划挑战", "impl": false},
	11: {"name": "秘密身份挑战", "impl": false},
	12: {"name": "邪恶六人组模式", "impl": false},
	13: {"name": "金队VS蓝队模式", "impl": false},
	14: {"name": "危险房间挑战模式", "impl": false},
	15: {"name": "威胁地点挑战模式", "impl": false},
	16: {"name": "凤凰五人组模式", "impl": false},
	17: {"name": "哨兵挑战模式", "impl": false},
	18: {"name": "死侍混乱挑战模式", "impl": false},
	19: {"name": "接管挑战模式", "impl": false},
	20: {"name": "新邪恶六人组模式", "impl": false},
	21: {"name": "内战·英雄对决模式", "impl": false},
	22: {"name": "内战·注册法案", "impl": false},
	23: {"name": "屠杀来袭挑战模式", "impl": false},
	24: {"name": "行星吞噬者降临模式", "impl": false},
	25: {"name": "高级训练模式", "impl": false},
	26: {"name": "困境挑战模式", "impl": false},
	27: {"name": "非凡龙挑战模式", "impl": false},
}

func _ready() -> void:
	for hid in ["cap", "ironman", "cmarvel", "hulk", "widow"]:
		_hero_icons[hid] = load(DB.hero_back(hid))
	for vid in ["redskull", "ultron", "taskmaster"]:
		_villain_icons[vid] = load(DB.villain(vid)["back"])
	for num in range(1, 28):
		var tex: Texture2D = load("res://assets/ui/modes/mode_%d.png" % num)
		_mode_tex[num] = tex
	# 灰度着色器：未选中图标显示黑白
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tfloat g = dot(c.rgb, vec3(0.299, 0.587, 0.114));\n\tCOLOR = vec4(vec3(g), c.a);\n}"
	_gray_mat = ShaderMaterial.new()
	_gray_mat.shader = sh
	_build_ui()

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
	_nav_back.position = Vector2(60, 940)
	_nav_back.pressed.connect(_on_back)
	add_child(_nav_back)
	_nav_next = Button.new()
	_nav_next.text = "确定"
	_nav_next.custom_minimum_size = Vector2(260, 70)
	_nav_next.add_theme_font_size_override("font_size", 26)
	_nav_next.position = Vector2(830, 940)
	_nav_next.pressed.connect(_on_next)
	add_child(_nav_next)
	var back_main := Button.new()
	back_main.text = "返回主菜单"
	back_main.custom_minimum_size = Vector2(160, 50)
	back_main.add_theme_font_size_override("font_size", 20)
	back_main.position = Vector2(1700, 940)
	back_main.pressed.connect(func(): get_tree().change_scene_to_file("res://src/ui/MainMenu.tscn"))
	add_child(back_main)

	# 英雄初始不预选：按稳定槽位选择（P1→P2→…），取消某顺位不影响其他顺位
	_sync_slots()
	_show_step(1)

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
	notice.text = "目前只支持单模式，且大部分模式尚未开发，请敬请期待"
	notice.add_theme_font_size_override("font_size", 20)
	notice.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	notice.position = Vector2(1180, 40)
	notice.custom_minimum_size = Vector2(660, 32)
	page.add_child(notice)
	# 27 个模式图标：9 列 × 3 行
	var cols := 9
	var icon_size := Vector2(180, 190)  # 图标 + 名称
	var start := Vector2(60, 150)
	var gap := Vector2(16, 20)
	for num in range(1, 28):
		var m: Dictionary = MODE_DATA[num]
		var col: int = (num - 1) % cols
		var row: int = (num - 1) / cols
		var box := _make_mode_button(num, m["name"], start + Vector2(col * (icon_size.x + gap.x), row * (icon_size.y + gap.y)), icon_size, page)
		_mode_buttons[num] = box
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
	box.add_child(btn)
	parent.add_child(box)
	return box

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
	_update_mode_highlight()
	_update_hero_count_label()
	_update_hero_buttons()

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

	# 人数（基础模式显示；神盾局固定 3，不显示加减）
	_count_row = Control.new()
	_count_row.position = Vector2(60, 160)
	page.add_child(_count_row)
	_count_label = Label.new()
	_count_label.text = "英雄人数（热座 1-4 人）"
	_count_label.add_theme_font_size_override("font_size", 24)
	_count_label.position = Vector2(0, 0)
	_count_row.add_child(_count_label)
	_hero_count_label = Label.new()
	_hero_count_label.add_theme_font_size_override("font_size", 22)
	_hero_count_label.position = Vector2(0, 36)
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

	# 英雄卡片
	_render_heroes(page)
	return page

# ================================================================ 页面 3：地点

func _build_step_locations() -> Control:
	var page := Control.new()
	page.position = Vector2(0, 0)
	page.custom_minimum_size = Vector2(1920, 900)
	add_child(page)
	var t := Label.new()
	t.text = "选择地点扩展"
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

	_render_villains(page)
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
	if _step_pages.has(3):
		_render_villains(_step_pages[3])
	if _step_pages.has(2):
		_render_heroes(_step_pages[2])

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

func _render_villains(parent: Control) -> void:
	for vid in _villain_buttons:
		_free_card(_villain_buttons[vid])
	_villain_buttons.clear()
	_clear_exp_labels(parent)
	var groups := _group_ids(["redskull", "ultron", "taskmaster"], VILLAIN_EXP, VILLAIN_SORT)
	var y := 160.0
	for g in groups:
		if _sort_mode == "expansion":
			_mk_group_label(g["name"], Vector2(60, y), parent)
			y += 30
		var x := 60.0
		for vid in g["ids"]:
			var box := _make_card_button(_villain_icons[vid], DB.villain_name(vid), Vector2(x, y), Vector2(140, 180), parent)
			var bbtn: Button = box.get_child(box.get_child_count() - 1)
			bbtn.pressed.connect(_on_villain_selected.bind(vid))
			_villain_buttons[vid] = box
			x += 160
		y += 190
	_update_villain_highlight()

func _render_heroes(parent: Control) -> void:
	for hid in _hero_buttons:
		_free_card(_hero_buttons[hid])
	_hero_buttons.clear()
	_clear_exp_labels(parent)
	var groups := _group_ids(["cap", "ironman", "cmarvel", "hulk", "widow"], HERO_EXP, HERO_SORT)
	var y := 260.0
	for g in groups:
		if _sort_mode == "expansion":
			_mk_group_label(g["name"], Vector2(60, y), parent)
			y += 28
		var x := 60.0
		for hid in g["ids"]:
			var box := _make_card_button(_hero_icons[hid], DB.hero_name(hid), Vector2(x, y), Vector2(130, 160), parent)
			var bbtn: Button = box.get_child(box.get_child_count() - 1)
			bbtn.pressed.connect(_on_hero_toggle.bind(hid))
			_hero_buttons[hid] = box
			x += 150
		y += 165
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

func _on_back() -> void:
	if _step > 1:
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
		_show_step(4)
	elif _step == 4:
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
	get_tree().change_scene_to_file("res://src/ui/Board.tscn")
