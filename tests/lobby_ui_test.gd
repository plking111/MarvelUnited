extends Node
## 大厅/联机 UI 冒烟测试。
##
## 起因：Lobby.gd 里把未创建的成员变量（_ip/_rname/_rpw/_join_pw）当控件用，
## 点了"创建房间/加入房间"直接闪退 —— 只做 --import 语法检查抓不到这种错。
## 这个测试实例化真场景、走完六种页面，断言控件都真的建出来了。

var _fail := 0

func _check(n: String, ok: bool, d: String = "") -> void:
	if ok:
		print("PASS: " + n)
	else:
		_fail += 1
		print("FAIL: " + n + " — " + d)

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _ready() -> void:
	Game.autopilot = true

	# ---- OnlinePrep：创建/加入房间按钮必须是可点的（以前是 disabled 占位）----
	var op: Control = load("res://src/ui/OnlinePrep.tscn").instantiate()
	add_child(op)
	await _frames(3)
	var cb := _find_button(op, "创建房间")
	var jb := _find_button(op, "加入房间")
	_check("联机准备页有「创建房间」按钮", cb != null, "")
	_check("联机准备页有「加入房间」按钮", jb != null, "")
	if cb != null:
		_check("「创建房间」已启用（不再是占位禁用）", not cb.disabled, "")
		_check("「创建房间」已接跳转", cb.get_signal_connection_list("pressed").size() > 0, "")
	if jb != null:
		_check("「加入房间」已启用", not jb.disabled, "")
		_check("「加入房间」已接跳转", jb.get_signal_connection_list("pressed").size() > 0, "")
	op.queue_free()
	await _frames(2)

	# ---- Lobby：首页（创建/加入两块的输入框都必须真的建出来）----
	_check("Lobby.tscn 存在", ResourceLoader.exists("res://src/ui/Lobby.tscn"), "")
	var lobby: Control = load("res://src/ui/Lobby.tscn").instantiate()
	add_child(lobby)
	await _frames(3)
	# 根节点必须铺满屏幕：手写 .tscn 时漏掉 anchors_preset/anchor_right/anchor_bottom 会让根 Control
	# 变成 0×0，里面所有 FULL_RECT 节点也全 0 尺寸 —— 表现就是"点进去一片灰、什么都没有"。
	_check("根 Control 铺满屏幕（anchors 全展开）",
		lobby.anchor_right == 1.0 and lobby.anchor_bottom == 1.0, "anchor_right=%s anchor_bottom=%s" % [str(lobby.anchor_right), str(lobby.anchor_bottom)])
	_check("根 Control 实际尺寸非 0（不是灰屏）", lobby.size.x > 800.0 and lobby.size.y > 400.0, "size=%s" % str(lobby.size))
	_check("页面容器实际尺寸非 0", lobby._page.size.x > 100.0 and lobby._page.size.y > 50.0, "_page.size=%s" % str(lobby._page.size))
	_check("大厅首页构建成功（有内容）", lobby._page.get_child_count() > 0,
		"子节点数=%d" % lobby._page.get_child_count())
	_check("首页控件非空：昵称输入", lobby._pname != null, "")
	_check("首页控件非空：创建房间的 房间名/密码/人数", lobby._rname != null and lobby._rpw != null and lobby._rmax != null,
		"rname=%s rpw=%s rmax=%s" % [str(lobby._rname), str(lobby._rpw), str(lobby._rmax)])
	_check("首页控件非空：加入房间的 IP/密码", lobby._ip != null and lobby._join_pw != null,
		"ip=%s join_pw=%s" % [str(lobby._ip), str(lobby._join_pw)])
	_check("首页有「创建房间」「搜索局域网房间」按钮",
		_find_button(lobby, "创建房间") != null and _find_button(lobby, "搜索局域网房间") != null, "")

	# ---- 建房 → 房间页（座位行 / 开始按钮 / 离开按钮）----
	_check("主机建房成功", Net.host_room("冒烟房", "pw", 4, "房主"), Net.last_error)
	await _frames(3)
	_check("房间页构建成功", lobby._page.get_child_count() > 0, "")
	_check("房间页有「离开房间」按钮", _find_button(lobby, "离开房间") != null, "")
	var start_btn := _find_button(lobby, "开始游戏（进入模式选择）")
	_check("房间页有「开始游戏」按钮（房主视角）", start_btn != null, "")
	_check("只有 1 人时「开始游戏」被禁用", start_btn != null and start_btn.disabled, "")
	_check("座位数与人数上限一致", Net.seats.size() == 4, "seats=%d" % Net.seats.size())

	# ---- 假队友（含英雄）→ 各阶段页面都要能建出来 ----
	Net.seats[1] = {"peer": 99, "name": "假队友", "hero": "vision", "villain": "", "locs": [], "ready": false}
	Net.request_pick("hero", "wasp")
	Net._push_lobby()
	await _frames(3)
	_check("两人且都有英雄 → 可以开始", Net.can_start(), "")
	start_btn = _find_button(lobby, "开始游戏（进入模式选择）")
	_check("两人时「开始游戏」解禁", start_btn != null and not start_btn.disabled, "")

	# ---- bug1：两个入口必须是两个不同的页面（建房页只有建房，加入页只有加入）----
	Net.leave()          # 先退出房间，回到"建房/加入"首页
	await _frames(3)
	Net.lobby_entry = "create"
	var lobby_c: Control = load("res://src/ui/Lobby.tscn").instantiate()
	add_child(lobby_c)
	await _frames(3)
	_check("「创建房间」入口：有「创建房间」按钮", _find_button(lobby_c, "创建房间") != null, "")
	_check("「创建房间」入口：没有「搜索局域网房间」按钮", _find_button(lobby_c, "搜索局域网房间") == null, "")
	_check("「创建房间」入口：没有「按 IP 加入」按钮", _find_button(lobby_c, "按 IP 加入") == null, "")
	_check("「创建房间」入口标题正确", String(lobby_c._title_text()) == "创建房间", String(lobby_c._title_text()))
	lobby_c.queue_free()
	await _frames(2)
	Net.lobby_entry = "join"
	var lobby_j: Control = load("res://src/ui/Lobby.tscn").instantiate()
	add_child(lobby_j)
	await _frames(3)
	_check("「加入房间」入口：有「搜索局域网房间」按钮", _find_button(lobby_j, "搜索局域网房间") != null, "")
	_check("「加入房间」入口：有「按 IP 加入」按钮", _find_button(lobby_j, "按 IP 加入") != null, "")
	_check("「加入房间」入口：没有「创建房间」按钮", _find_button(lobby_j, "创建房间") == null, "")
	_check("「加入房间」入口标题正确", String(lobby_j._title_text()) == "加入房间", String(lobby_j._title_text()))
	lobby_j.queue_free()
	await _frames(2)
	Net.lobby_entry = "both"

	# ---- 联机不再自建选择页：大厅只管房间，选完进本地 Setup 向导 ----
	_check("Lobby 不再自建四阶段选择页", not lobby.has_method("_build_hero") and not lobby.has_method("_build_mode")
		and not lobby.has_method("_build_villain") and not lobby.has_method("_build_location"), "")
	_check("本地 Setup 场景存在（联机复用它）", ResourceLoader.exists("res://src/ui/Setup.tscn"), "")
	_check("阶段一变就交棒给本地 Setup", lobby._should_handoff("mode") and not lobby._should_handoff("lobby"), "")
	_check("大厅已连 Net.phase_changed（收到阶段变化就能跳）",
		Net.phase_changed.get_connections().size() > 0, "")

	# 清理：先放掉 UI（否则 Net 的信号还连着已释放节点），再离开房间
	lobby.queue_free()
	await _frames(2)
	Net.leave()
	_check("离开房间后 Net 复位", not Net.active and Net.seats.is_empty(), "")

	if _fail == 0:
		print("=== LOBBY UI TEST ALL PASSED ===")
		get_tree().quit(0)
	else:
		print("=== LOBBY UI TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)

func _find_button(root: Node, text: String) -> Button:
	for c in root.get_children():
		if c is Button and String(c.text).contains(text):
			return c
		var r := _find_button(c, text)
		if r != null:
			return r
	return null

func _find_label(root: Node, text: String) -> bool:
	for c in root.get_children():
		if c is Label and String(c.text).contains(text):
			return true
		if _find_label(c, text):
			return true
	return false

func _count_texture_rects(root: Node) -> int:
	var n := 0
	for c in root.get_children():
		if c is TextureRect:
			n += 1
		n += _count_texture_rects(c)
	return n
