extends Control
## 局域网大厅 + 联机四阶段选择（模式 → 英雄 → 反派 → 地点）。
##
## 流程（与需求一致）：
##  1) 创建房间（房间名/密码/人数上限）/ 搜索局域网房间 / 手动输 IP 加入
##  2) 房间内自由挑座位号（1~上限，空的别人可占），顺位 = 座位号；房主可开始（≥2 人）
##  3) 模式：房主选（基础盒类 5 个模式）
##  4) 英雄：每人只能选自己的英雄，选择实时同步（他人选的用 P 标签显示，且不可重复选）
##  5) 反派：每人最多勾 1 个，全部同步；开局从汇总里随机抽 1 个
##  6) 地点：每人勾若干，全部同步；开局从汇总里随机抽 6 张
##  7) 房主点"开始游戏"→ 所有端进入对局（主机权威，快照同步）

const SEAT_COLORS := [
	Color(0.95, 0.30, 0.30), Color(0.95, 0.62, 0.18), Color(0.92, 0.88, 0.20),
	Color(0.35, 0.80, 0.42), Color(0.30, 0.72, 0.92), Color(0.42, 0.45, 0.95),
]

var _page: VBoxContainer
var _rname: LineEdit
var _rpw: LineEdit
var _rmax: OptionButton
var _ip: LineEdit
var _join_pw: LineEdit
var _pname: LineEdit
var _hint: Label
var _room_list: VBoxContainer
var _hands_off := false     # 已经交棒给本地 Setup 向导（避免重复跳场景）

func _ready() -> void:
	# 背景：和本地 Setup 页一致（纯色），不用封面图 —— 用户要求"把背景去掉，和别的一样就行"
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	_page = VBoxContainer.new()
	_page.add_theme_constant_override("separation", 12)
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_page)

	Net.lobby_changed.connect(_refresh)
	Net.phase_changed.connect(func(_p: String) -> void: _refresh())
	Net.rooms_found.connect(_on_rooms_found)
	Net.net_error.connect(func(m: String) -> void: _set_hint(m))
	Net.phase_changed.connect(_on_phase)
	# 自检入口：-- lobby-host 进大厅后立刻建房（导出后用它验证"创建房间"这条路）
	# 统一去掉前导 "-"：`-- lobby-host` 与 `-- --lobby-host` 两种写法都认（见 MainMenu 的说明）
	var uflags: Array = []
	for a in OS.get_cmdline_user_args():
		uflags.append(String(a).lstrip("-"))
	if uflags.has("lobby-host"):
		Net.host_room("自检房", "", 4, "自检")
	_refresh()
	if uflags.has("lobby") or uflags.has("lobby-host"):
		await get_tree().process_frame
		await get_tree().process_frame
		print("[自检] 联机大厅：根尺寸=%s 页面尺寸=%s 页面节点=%d 座位数=%d 我的座位=%d 房间=%s 错误=%s"
			% [str(size), str(_page.size), _page.get_child_count(), Net.seats.size(), Net.my_seat(), str(Net.room), Net.last_error])

func _set_hint(t: String) -> void:
	if is_instance_valid(_hint):
		_hint.text = t

# ================================================================ 页面构建

func _clear_page() -> void:
	for c in _page.get_children():
		_page.remove_child(c)
		c.queue_free()

func _refresh() -> void:
	_clear_page()
	var title := UiKit.label(_title_text(), 46, Color(1, 0.92, 0.7))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page.add_child(title)
	_hint = UiKit.label("", 22, Color(0.85, 0.9, 1))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page.add_child(_hint)
	if not Net.active:
		_build_home()
	else:
		_build_room()

func _title_text() -> String:
	if not Net.active:
		return "创建房间" if Net.lobby_entry == "create" else ("加入房间" if Net.lobby_entry == "join" else "局域网联机")
	var rm: Dictionary = Net.room
	return "房间：%s（%d/%d 人）" % [String(rm.get("name", "")), Net.player_count(), int(rm.get("max", 4))]

## 房主点了「开始游戏」→ 所有人离开大厅，进本地的模式/英雄/反派/地点向导（Setup.tscn）
func _on_phase(p: String) -> void:
	if not _should_handoff(p) or _hands_off:
		return
	_hands_off = true
	UiKit.goto_scene("res://src/ui/Setup.tscn")

## 是否该交棒给本地 Setup 向导（阶段一旦离开 lobby 就该走）
func _should_handoff(p: String) -> bool:
	return p != "lobby"

# ---------------------------------------------------------------- 首页：创建/搜索/加入

func _build_home() -> void:
	# 昵称（建房/加入都要用）
	_page.add_child(UiKit.label("你的昵称", 24, Color.WHITE))
	_pname = _mk_line("玩家", 360)
	_pname.text = "玩家"
	_page.add_child(_pname)

	# 控件一律创建（便于复用/自检），但只有对应入口才放进页面：
	# 「创建房间」只显示建房，「加入房间」只显示加入（bug1：以前两个按钮进的是同一个"什么都有"的页）
	_rname = _mk_line("房间名", 420)
	_rpw = _mk_line("房间密码（可空）", 300)
	_rmax = OptionButton.new()
	_rmax.custom_minimum_size = Vector2(190, 44)
	for n in [2, 3, 4]:
		_rmax.add_item("%d 人" % n)
	_rmax.selected = 1
	_ip = _mk_line("房主 IP（也可以直接点下面列表里的房间加入）", 420)
	_join_pw = _mk_line("房间密码（没有就留空）", 300)
	_join_pw.secret = true
	_room_list = VBoxContainer.new()
	_room_list.add_theme_constant_override("separation", 8)

	if Net.lobby_entry != "join":
		_build_create_block()
	if Net.lobby_entry != "create":
		_build_join_block()
	# 最下方：返回
	_page.add_child(_sep())
	var back := UiKit.button("返回", Color(0.4, 0.4, 0.5))
	back.pressed.connect(func() -> void: UiKit.goto_scene("res://src/ui/OnlinePrep.tscn"))
	_page.add_child(back)

## 创建房间块：房间名 / 密码 / 人数上限 / 创建
func _build_create_block() -> void:
	_page.add_child(UiKit.label("① 建一个房间，把房间名和密码告诉朋友（局域网会自动被发现）", 22, Color(0.85, 0.9, 1)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_page.add_child(row)
	row.add_child(_rname)
	row.add_child(_rpw)
	row.add_child(_rmax)
	var create_btn := UiKit.button("创建房间", Color(0.3, 0.7, 0.3))
	create_btn.pressed.connect(func() -> void:
		var mp: int = [2, 3, 4][maxi(_rmax.selected, 0)]
		if not Net.host_room(_rname.text, _rpw.text, mp, _pname.text):
			_set_hint(Net.last_error))
	row.add_child(create_btn)

## 加入房间块：自动搜索局域网房间 / 列表加入 / 手动 IP 加入
func _build_join_block() -> void:
	_page.add_child(UiKit.label("① 搜索同一个局域网里的房间，或直接填房主 IP 加入", 22, Color(0.85, 0.9, 1)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_page.add_child(row)
	row.add_child(_ip)
	row.add_child(_join_pw)
	var join_btn := UiKit.button("按 IP 加入", Color(0.3, 0.5, 0.8))
	join_btn.pressed.connect(func() -> void:
		if String(_ip.text).strip_edges() == "":
			_set_hint("请先填写房主 IP")
			return
		if not Net.join_room(String(_ip.text).strip_edges(), _join_pw.text, _pname.text):
			_set_hint(Net.last_error))
	row.add_child(join_btn)
	var search_btn := UiKit.button("搜索局域网房间", Color(0.35, 0.55, 0.85))
	search_btn.pressed.connect(func() -> void:
		Net.search_rooms()
		_set_hint("搜索中…（约 1.2 秒）"))
	row.add_child(search_btn)
	_page.add_child(_sep())
	_page.add_child(_room_list)
	_on_rooms_found(Net.rooms)

func _on_rooms_found(list: Array) -> void:
	if not is_instance_valid(_room_list):
		return
	for c in _room_list.get_children():
		_room_list.remove_child(c)
		c.queue_free()
	if list.is_empty():
		_room_list.add_child(UiKit.label("（未发现房间：可让房主点上面的「创建房间」，或手动填 IP 加入）", 22, Color(0.8, 0.8, 0.9)))
		return
	for r in list:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		_room_list.add_child(row)
		var locked: String = "🔒" if bool(r.get("has_pw", false)) else ""
		row.add_child(UiKit.label("%s %s  %d/%d  %s:%d" % [locked, String(r["name"]),
			int(r["players"]), int(r["max"]), String(r["ip"]), int(r["port"])], 24, Color.WHITE))
		var jb := UiKit.button("加入", Color(0.3, 0.7, 0.4))
		jb.pressed.connect(func() -> void:
			_ip.text = String(r["ip"])
			if not Net.join_room(String(r["ip"]), _join_pw.text, _pname.text, int(r.get("port", 27015))):
				_set_hint(Net.last_error))
		row.add_child(jb)

# ---------------------------------------------------------------- 房间内：座位/开始

func _build_room() -> void:
	var my := Net.my_seat()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_page.add_child(row)
	var mx: int = int(Net.room.get("max", 4))
	for i in range(mx):
		var s: Variant = Net.seats[i] if i < Net.seats.size() else null
		var taken: bool = s != null
		var mine: bool = taken and int(s["peer"]) == Net.my_peer
		var txt := "%d 号位：%s" % [i + 1, String(s["name"]) if taken else "空位"]
		var b := UiKit.button(txt, SEAT_COLORS[i % SEAT_COLORS.size()] if taken else Color(0.3, 0.3, 0.36))
		b.custom_minimum_size = Vector2(240, 60)
		b.disabled = mine
		b.pressed.connect(func() -> void: Net.request_seat(i))
		row.add_child(b)
	_page.add_child(UiKit.label("你当前是 %s（顺位 = 座位号：1 号位先手）" % ("%d 号位" % (my + 1) if my >= 0 else "未入座"),
		24, Color(0.9, 0.9, 0.7)))
	_page.add_child(_sep())
	for s in Net.seats:
		if s == null:
			continue
		var hh: String = String(s.get("hero", ""))
		_page.add_child(UiKit.label("· %s%s：%s" % [String(s["name"]),
			"（房主）" if int(s["peer"]) == 1 else "",
			DB.hero_name(hh) if hh != "" else "还没选英雄"], 24, Color.WHITE))
	_page.add_child(_sep())
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 16)
	_page.add_child(row2)
	if Net.is_host:
		var start := UiKit.button("开始游戏（进入模式选择）", Color(0.3, 0.7, 0.35))
		start.disabled = Net.player_count() < 2
		start.pressed.connect(func() -> void:
			if Net.player_count() < 2:
				_set_hint("至少需要 2 名玩家才能开始")
				return
			Net.set_phase("mode"))
		row2.add_child(start)
		if Net.player_count() < 2:
			row2.add_child(UiKit.label("（只有你一个人，等其他人加入）", 22, Color(1, 0.8, 0.5)))
	else:
		row2.add_child(UiKit.label("等待房主开始游戏…", 24, Color(0.9, 0.9, 0.6)))
	var leave := UiKit.button("离开房间", Color(0.6, 0.35, 0.35))
	leave.pressed.connect(func() -> void:
		Net.leave()
		UiKit.goto_scene("res://src/ui/OnlinePrep.tscn"))
	row2.add_child(leave)


func _sep() -> Control:
	var s := HSeparator.new()
	s.custom_minimum_size = Vector2(0, 8)
	return s

func _style_line(le: LineEdit, ph: String = "") -> void:
	if le == null:
		return
	le.placeholder_text = ph
	le.custom_minimum_size = Vector2(360, 44)
	le.add_theme_font_size_override("font_size", 22)

## 造一个统一样式的输入框。
## 注意：以前写成 _style_line(_ip, "…") 直接给未创建的成员赋值 —— GDScript 传的是引用副本，
## 在函数里 new 出来的控件回不到成员变量，结果是 _ip/_rname/_rpw/_join_pw 全为 null，
## add_child(null) 连环报错 → 点"创建房间/加入房间"直接闪退。改成"工厂返回"避免再犯。
func _mk_line(ph: String, width: float = 360.0) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = ph
	le.custom_minimum_size = Vector2(width, 44)
	le.add_theme_font_size_override("font_size", 22)
	return le

