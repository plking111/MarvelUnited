extends Node
## Net：局域网联机（主机权威 / host-authoritative）。
##
## 思路：只有主机跑 Game 逻辑；客户端把操作作为"意图"发给主机，主机结算后把裁剪过的
## 状态快照广播回去；客户端把快照写回 Game.state 再 emit_state_changed()，
## 因为 Board/地点/反派/日志 全部读 state 渲染，这些 UI 不需要改动就同步了。
##
## 隐私：按接收者裁剪 —— 其他玩家的 hand/deck 一律清空，只保留张数（用户裁定）。
##
## 阶段：lobby（房间/座位）→ mode（房主选模式）→ hero（各自选自己）
##      → villain（每人最多勾 1 个）→ location（各自勾若干）→ playing（对局）

signal lobby_changed                       ## 房间/座位/选择有变化 → 大厅 UI 刷新
signal phase_changed(p: String)            ## 阶段推进
signal rooms_found(list: Array)            ## 搜到的房间列表
signal net_error(msg: String)              ## 出错提示（UI 弹 toast）
signal join_ok                             ## 客户端成功进房
signal start_play(cfg: Dictionary)         ## 开始对局（所有端都会收到）：{hero_ids, villain, locations, mode, challenge, expansions}
signal prompt_sync(kind: String, payload: Variant, can_answer: bool)  ## 主机 → 客户端：弹窗同步展示

const PROTO := 1
const PORT := 27015
const DISCOVER_PORT := 27016
const MAX_PLAYERS_LIMIT := 4
const MSG_DISCOVER := "MUMARVEL_DISCOVER_V1"

var active := false            ## 是否处于联机局（含主机）
var is_host := false
var my_peer := 1
var room: Dictionary = {}      ## {name, password, max}
var seats: Array = []          ## 下标=座位号(0-based)，元素为 null 或 {peer,name,hero,villain,locs,ready}
var phase := "lobby"
var mode_cfg: Dictionary = {}  ## {mode, challenge, expansions}
var rooms: Array = []          ## 搜到的房间 [{ip, port, name, players, max, has_pw}]
var last_error := ""
## 大厅入口："create" 只显示建房、"join" 只显示加入（由 OnlinePrep 两个按钮设置）
var lobby_entry := "both"
## 本机房间实际占用的端口（默认 PORT，被占则顺延；会随房间信息广播给搜索方）
var my_port := 0
## 当前弹窗该由哪个英雄的玩家回答（空 = 按当前行动英雄判定）
var _prompt_answer_hero := ""
## 无限战争：前 3 局的反派顺序（房主排，广播给所有人）
var campaign_order: Array = []
## 收到 start_play 后是否自动进棋盘（测试进程里关掉，避免真的切场景把测试跑飞）
var auto_board_handoff := true

var _udp_host: PacketPeerUDP = null
var _udp_search: PacketPeerUDP = null
var _search_left := 0.0
var _my_name := "玩家"
var _snap_timer := 0.0     ## 快照节流（0.08s 一次，最后一次变化保证送达）
var _snap_dirty := false
var _mp_bound := false     ## multiplayer 信号只绑一次（重复绑定会报 "already connected"）

func _ready() -> void:
	prompt_sync.connect(_on_prompt_sync)
	Events.state_changed.connect(_on_state_changed)
	start_play.connect(_apply_start_play)   # 开局/下一局统一由这里进棋盘（Setup/Board 都能收到）

## 主机：状态变化 → 节流广播快照（客户端据此重绘）
func _on_state_changed() -> void:
	_watch_waiting()
	if not is_host or not active:
		return
	if _snap_timer > 0.0:
		_snap_dirty = true
		return
	_snap_timer = 0.08
	broadcast_snapshot()

## 客户端：把主机发来的弹窗用本地 UI 显示出来；只有"轮到我"时才把答案回给主机
func _on_prompt_sync(kind: String, payload: Variant, can_answer: bool) -> void:
	var p: Dictionary = payload if payload is Dictionary else {}
	match kind:
		"choice":
			var cb1 := func(v: Variant) -> void:
				if can_answer:
					send_answer("choice", v)
			Events.prompt_choice.emit(p.get("options", []), String(p.get("title", "")), cb1)
		"action":
			var cb2 := func(v: Variant) -> void:
				if can_answer:
					send_answer("action", v)
			Events.prompt_action.emit(p.get("rows", []), String(p.get("title", "")), cb2)
		"confirm":
			var cb3 := func(v: Variant) -> void:
				if can_answer:
					send_answer("confirm", v)
			Events.prompt_confirm.emit(String(p.get("text", "")), cb3)
		"hand":
			var cb4 := func(picked: Variant) -> void:
				if can_answer:
					send_answer("hand", picked)
			Events.prompt_hand_card.emit(cb4, String(p.get("title", "")), String(p.get("hid", "")), int(p.get("count", 1)))
		"story":
			var cb5 := func(idx: Variant) -> void:
				if can_answer:
					send_answer("story", idx)
			Events.prompt_story_card.emit(cb5, String(p.get("title", "")), String(p.get("filter_hero", "")))
		"deck":
			var cb6 := func(idx: Variant) -> void:
				if can_answer:
					send_answer("deck", idx)
			Events.prompt_deck_card.emit(cb6, String(p.get("title", "")), String(p.get("hid", "")))
		"hero":
			var cb7 := func(hid: Variant) -> void:
				if can_answer:
					send_answer("hero", hid)
			Events.prompt_hero_pick.emit(cb7, String(p.get("title", "")), p.get("options", []))
		"villain_card":
			var cb8 := func(ok: Variant) -> void:
				if can_answer:
					send_answer("villain_card", ok)
			Events.prompt_villain_card.emit(cb8, String(p.get("title", "")), int(p.get("card_idx", 0)))
		"reorder":
			# 拖拽排序（量子魔法）：牌面只有"该答的玩家"收得到（见 _prompt_payload_for），
			# 其他人 cards 为空，弹窗只展示只读提示，拖不动
			var cb9 := func(order: Variant) -> void:
				if can_answer:
					send_answer("reorder", order)
			Events.prompt_reorder.emit(p.get("cards", []), String(p.get("villain", "")), String(p.get("title", "")), cb9)

# ================================================================ 建/加/离开房间

func host_room(rname: String, password: String, max_players: int, player_name: String) -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	# 端口被占（同机再开一个房间、或上一次的残留）就往后顺延；实际端口会随房间信息广播出去
	var bound := -1
	for p in range(PORT, PORT + 8):
		if peer.create_server(p, MAX_PLAYERS_LIMIT) == OK:
			bound = p
			break
	if bound < 0:
		_fail("创建房间失败：%d~%d 端口都被占用" % [PORT, PORT + 7])
		return false
	my_port = bound
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = true
	my_peer = 1
	_my_name = player_name if player_name != "" else "房主"
	var mp: int = clampi(max_players, 2, MAX_PLAYERS_LIMIT)
	room = {"name": rname if rname != "" else "%s 的房间" % _my_name,
		"password": password, "max": mp}
	seats = []
	seats.resize(mp)
	for i in range(mp):
		seats[i] = null
	seats[0] = _new_seat(1, _my_name)
	phase = "lobby"
	mode_cfg = {}
	_bind_multiplayer()
	_start_discovery_host()
	_start_poll()
	_push_lobby()
	return true

func join_room(ip: String, password: String, player_name: String, port: int = PORT) -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_client(ip, port)
	if err != OK:
		_fail("连接失败（%s:%d，错误码 %d）" % [ip, port, err])
		return false
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = false
	my_peer = 0            ## 连接成功后由 connected_to_server 回调更新
	_my_name = player_name if player_name != "" else "玩家"
	room = {"name": "（连接中…）", "password": password, "max": 4}
	seats = []
	phase = "lobby"
	_bind_multiplayer()
	_start_poll()
	return true

func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_stop_discovery()
	active = false
	is_host = false
	my_peer = 1
	room = {}
	seats = []
	phase = "lobby"
	mode_cfg = {}
	_last_waiting = false
	my_port = 0
	Events.popup_readonly_changed.emit(false)
	set_process(false)

func is_active() -> bool:
	return active

func my_seat() -> int:
	for i in range(seats.size()):
		var s: Variant = seats[i]
		if s != null and int(s.get("peer", -1)) == my_peer:
			return i
	return -1

func my_seat_data() -> Dictionary:
	var i := my_seat()
	return seats[i] if i >= 0 else {}

func my_hero() -> String:
	return String(my_seat_data().get("hero", ""))

func player_count() -> int:
	var n := 0
	for s in seats:
		if s != null:
			n += 1
	return n

## 本机当前能操作的英雄：
##  1) 就是自己的英雄；
##  2) 或者"当前行动英雄"的玩家已退出、且房主选了"继续游戏"→ 该英雄由房主代管（操作与本地一致）。
func controlling_hero() -> String:
	var cur := Game.current_hero_id()
	if cur == "":
		return my_hero()
	if my_hero() == cur:
		return cur
	if is_host:
		for s in seats:
			if s == null:
				continue
			if String(s.get("hero", "")) == cur and (bool(s.get("disconnected", false)) or int(s.get("peer", 0)) < 0):
				return cur
	return my_hero()

## 是否轮到我操作（对局中只有当前英雄的所属玩家、或其代管房主能操作）
func is_my_turn() -> bool:
	if not active:
		return true
	if phase != "playing":
		return false
	return controlling_hero() != "" and controlling_hero() == Game.current_hero_id()

func _new_seat(peer: int, pname: String) -> Dictionary:
	return {"peer": peer, "name": pname, "hero": "", "villain": "", "locs": [], "ready": false}

func _fail(msg: String) -> void:
	last_error = msg
	push_warning("[Net] " + msg)
	net_error.emit(msg)

# ================================================================ multiplayer 信号

func _bind_multiplayer() -> void:
	if _mp_bound:
		return
	_mp_bound = true
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_conn_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _on_peer_connected(id: int) -> void:
	if is_host:
		# 新客户端：等它发 join 请求（带名字/密码）
		pass

func _on_peer_disconnected(id: int) -> void:
	if is_host:
		var idx := -1
		for i in range(seats.size()):
			var s: Variant = seats[i]
			if s != null and int(s["peer"]) == id:
				idx = i
		if idx < 0:
			return
		var nm := String(seats[idx]["name"])
		if phase == "playing":
			# 对局中有人退出（bug3）：问房主要不要继续；继续 = 这个英雄改由房主代管（操作与本地一致）
			show_modal("玩家「%s」退出游戏" % nm, [
				{"key": "continue", "label": "继续游戏"},
				{"key": "quit", "label": "退出游戏"},
			])
			var key: String = await modal_choice
			if key == "quit":
				leave()
				UiKit.goto_scene("res://src/ui/MainMenu.tscn")
				return
			seats[idx]["disconnected"] = true
			seats[idx]["peer"] = -1
			Events.state_changed.emit()   # 让棋盘立刻重绘：轮到该玩家时房主手牌区要切到他的英雄
			_log_modal("玩家「%s」的英雄由房主代管（轮到他的回合时房主来操作）" % nm)
		else:
			seats[idx] = null
		_push_lobby()
	else:
		# 客户端：房主没了（bug2）→ 弹窗提示"房间已丢失"，带返回按钮回主菜单
		show_modal("房间已丢失：房主已退出游戏", [{"key": "back", "label": "返回主菜单"}])
		await modal_choice
		leave()
		UiKit.goto_scene("res://src/ui/MainMenu.tscn")

func _on_connected() -> void:
	my_peer = multiplayer.get_unique_id()
	rpc_id(1, "rpc_join_request", _my_name, String(room.get("password", "")))
	join_ok.emit()

func _on_conn_failed() -> void:
	_fail("无法连接到房主（IP/端口或防火墙）")
	leave()

func _on_server_disconnected() -> void:
	# 客户端：与房主断开（bug2）
	show_modal("房间已丢失：房主已退出游戏", [{"key": "back", "label": "返回主菜单"}])
	await modal_choice
	leave()
	UiKit.goto_scene("res://src/ui/MainMenu.tscn")

# ================================================================ 全局弹窗（任何场景都能弹）

signal modal_choice(key: String)

var _modal_layer: CanvasLayer = null
var _modal_text: Label = null
var _modal_btns: HBoxContainer = null

func _ensure_modal() -> void:
	if _modal_layer != null:
		return
	_modal_layer = CanvasLayer.new()
	_modal_layer.layer = 200      # 高于棋盘/弹窗层，任何界面都能盖住
	add_child(_modal_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(0.12, 0.12, 0.2, 0.98)))
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 22)
	margin.add_child(vb)
	_modal_text = UiKit.label("", 30, Color(1, 0.92, 0.75))
	_modal_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modal_text.custom_minimum_size = Vector2(520, 0)
	_modal_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_modal_text)
	_modal_btns = HBoxContainer.new()
	_modal_btns.add_theme_constant_override("separation", 20)
	_modal_btns.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(_modal_btns)
	_modal_layer.visible = false

func show_modal(text: String, buttons: Array) -> void:
	_ensure_modal()
	_modal_text.text = text
	for c in _modal_btns.get_children():
		_modal_btns.remove_child(c)
		c.queue_free()
	for b in buttons:
		var btn := UiKit.button(String(b.get("label", "确定")), Color(0.35, 0.55, 0.75))
		btn.custom_minimum_size = Vector2(200, 56)
		var key := String(b.get("key", "ok"))
		btn.pressed.connect(func() -> void:
			_modal_layer.visible = false
			modal_choice.emit(key))
		_modal_btns.add_child(btn)
	_modal_layer.visible = true

func hide_modal() -> void:
	if _modal_layer != null:
		_modal_layer.visible = false

## 日志（联机提示也写进对战日志，方便回看）
func _log_modal(text: String) -> void:
	if not Game.state.is_empty():
		Game._log("🌐 " + text, Color(0.8, 0.9, 1))
	else:
		print("[Net] " + text)

# ================================================================ 房间同步（RPC）

@rpc("any_peer", "call_remote", "reliable")
func rpc_join_request(pname: String, password: String) -> void:
	if not is_host:
		return
	var peer := multiplayer.get_remote_sender_id()
	if String(room.get("password", "")) != password:
		rpc_id(peer, "rpc_join_denied", "房间密码错误")
		return
	var free := -1
	for i in range(seats.size()):
		if seats[i] == null:
			free = i
			break
	if free < 0:
		rpc_id(peer, "rpc_join_denied", "房间已满")
		return
	seats[free] = _new_seat(peer, pname if pname != "" else "玩家%d" % peer)
	_push_lobby()
	rpc_id(peer, "rpc_join_accepted", room, seats, phase, mode_cfg)

@rpc("authority", "call_remote", "reliable")
func rpc_join_denied(reason: String) -> void:
	_fail(reason)
	leave()

@rpc("authority", "call_remote", "reliable")
func rpc_join_accepted(room_data: Dictionary, seats_data: Array, ph: String, mc: Dictionary) -> void:
	room = room_data
	seats = seats_data
	phase = ph
	mode_cfg = mc
	my_peer = multiplayer.get_unique_id()
	lobby_changed.emit()
	phase_changed.emit(phase)
	Events.state_changed.emit()   # 座位变化可能影响我可不可以操作，让棋盘重绘

## 主机 → 所有人：房间/座位/阶段权威状态
@rpc("authority", "call_remote", "reliable")
func rpc_lobby(room_data: Dictionary, seats_data: Array, ph: String, mc: Dictionary) -> void:
	room = room_data
	seats = seats_data
	phase = ph
	mode_cfg = mc
	lobby_changed.emit()
	phase_changed.emit(phase)
	Events.state_changed.emit()   # 座位变化可能影响我可不可以操作，让棋盘重绘

func _push_lobby(phase_changed_now: bool = false) -> void:
	lobby_changed.emit()
	if phase_changed_now:
		# 关键：本机（房主）也要收到阶段变化，否则"房主点开始游戏没反应、只有客户端跳页"
		phase_changed.emit(phase)
	if not is_host:
		return
	if multiplayer.multiplayer_peer == null:
		return
	for i in range(seats.size()):
		var s: Variant = seats[i]
		if s != null and int(s["peer"]) > 1:
			rpc_id(int(s["peer"]), "rpc_lobby", room, seats, phase, mode_cfg)

# ================================================================ 座位 / 选择

## 自由挑座位号（1~人数上限，空的别人可占）；顺位 = 座位号
func request_seat(seat: int) -> void:
	if not active:
		return
	if is_host:
		_apply_seat(my_peer, seat)
	else:
		rpc_id(1, "rpc_seat", seat)

@rpc("any_peer", "call_remote", "reliable")
func rpc_seat(seat: int) -> void:
	if not is_host:
		return
	_apply_seat(multiplayer.get_remote_sender_id(), seat)

func _apply_seat(peer: int, seat: int) -> void:
	if seat < 0 or seat >= seats.size():
		return
	var cur := -1
	for i in range(seats.size()):
		var s: Variant = seats[i]
		if s != null and int(s["peer"]) == peer:
			cur = i
	if seats[seat] != null and int(seats[seat]["peer"]) != peer:
		return   # 座位已被别人占了
	var data: Dictionary = seats[cur] if cur >= 0 else _new_seat(peer, "玩家%d" % peer)
	seats[seat] = data
	if cur >= 0 and cur != seat:
		seats[cur] = null
	_push_lobby()

## 阶段选择：hero（英雄id）/ villain（反派id，每人最多 1 个）/ location（地点id，可多选）
func request_pick(ph: String, id: String) -> void:
	if not active:
		return
	if is_host:
		_apply_pick(my_peer, ph, id)
	else:
		rpc_id(1, "rpc_pick", ph, id)

@rpc("any_peer", "call_remote", "reliable")
func rpc_pick(ph: String, id: String) -> void:
	if not is_host:
		return
	_apply_pick(multiplayer.get_remote_sender_id(), ph, id)

func _apply_pick(peer: int, ph: String, id: String) -> void:
	var seat := -1
	for i in range(seats.size()):
		var s: Variant = seats[i]
		if s != null and int(s["peer"]) == peer:
			seat = i
	if seat < 0:
		return
	var d: Dictionary = seats[seat]
	match ph:
		"hero":
			# 英雄不可重复：别人已选的英雄不能再选
			for i in range(seats.size()):
				var s2: Variant = seats[i]
				if s2 != null and i != seat and String(s2.get("hero", "")) == id:
					return
			d["hero"] = "" if String(d.get("hero", "")) == id else id
		"villain":
			# 每人最多勾 1 个反派（再点同一个 = 取消）
			d["villain"] = "" if String(d.get("villain", "")) == id else id
		"campaign":
			# 无限战争：填进我自己最低的空格（红→橙→绿）；点已选中的 = 取消那一格
			var cs: Array = _seat_cs(d)
			var at: int = cs.find(id)
			if at != -1:
				cs[at] = ""
			else:
				var empty: int = cs.find("")
				if empty == -1:
					return
				cs[empty] = id
			d["cs"] = cs
		"location":
			var locs: Array = d.get("locs", [])
			if locs.has(id):
				locs.erase(id)
			else:
				locs.append(id)
			d["locs"] = locs
		"ready":
			d["ready"] = not bool(d.get("ready", false))
	seats[seat] = d
	_push_lobby()

## 主机推进阶段（mode 由房主选，之后逐阶段推进）
func set_phase(ph: String) -> void:
	if not is_host:
		return
	if phase == ph:
		return
	phase = ph
	_push_lobby(true)

## 房主选模式
func set_mode(mode: String, challenge: String, expansions: Array) -> void:
	if not is_host:
		return
	mode_cfg = {"mode": mode, "challenge": challenge, "expansions": expansions}
	# 无限战争：给每位玩家铺好默认三格（暗夜比邻星/黑矮星/乌木侯），之后可自行切换
	if mode == "iw":
		init_campaign_defaults()
	_push_lobby()

# ================================================================ 开局

## 只有房主能开始；至少 2 名玩家、且每人必须选了英雄
func can_start() -> bool:
	if not is_host:
		return false
	if player_count() < 2:
		return false
	for s in seats:
		if s != null and String(s.get("hero", "")) == "":
			return false
	return true

func start_game() -> void:
	if not is_host or not can_start():
		return
	var heroes: Array = []
	for s in seats:
		if s != null:
			heroes.append(String(s["hero"]))
	# 反派：汇总所有玩家勾选（每人最多 1 个）→ 随机抽 1 个；没人勾则随机一个
	var vpool: Array = []
	for s in seats:
		if s != null and String(s.get("villain", "")) != "" and not vpool.has(String(s["villain"])):
			vpool.append(String(s["villain"]))
	if vpool.is_empty():
		vpool = DB.villains.keys()
	var md: String = String(mode_cfg.get("mode", "base"))
	var villain := ""
	var campaign_cfg: Dictionary = {}
	if md == "iw":
		# 无限战争：第 1 局用房主排的顺序第 1 个；战役进度（局数/宝石/能量卡）随开局下发
		# 每一局单独从"该局池子"里随机抽 1 个（池=所有玩家在该格选的反派）
		var defs: Array = ["proxima", "cull", "ebony"]
		var drawn: Array = []
		for sl in range(3):
			var pool_sl: Array = campaign_pool(sl)
			if pool_sl.is_empty():
				drawn.append(String(defs[sl]))
			else:
				drawn.append(String(pool_sl[randi_range(0, pool_sl.size() - 1)]))
		campaign_order = drawn.duplicate()
		campaign_cfg = {"game": 1, "order": drawn, "stones_collected": [], "energy_unlocked": []}
		villain = String(drawn[0])
	elif md == "s6":
		villain = "vulture"    # 占位：邪恶六人组不使用这个字段（6 个反派同时在场，本地也这么标）
	else:
		villain = String(vpool[randi_range(0, vpool.size() - 1)])
	# 地点：汇总各玩家勾选的**地点扩展**（本地地点页就是勾扩展）→ 从这些扩展的 44 张里随机取 6 张
	var exps: Array = []
	for s in seats:
		if s != null:
			for e in (s.get("locs", []) as Array):
				if not exps.has(String(e)):
					exps.append(String(e))
	var lpool: Array = []
	for lid in DB.locations.keys():
		var le: String = String(DB.location(String(lid)).get("expansion", "基础盒"))
		if exps.is_empty() or exps.has(le):
			lpool.append(String(lid))
	if lpool.is_empty():
		for lid in DB.locations.keys():
			lpool.append(String(lid))
	var locations: Array = []
	while locations.size() < 6 and not lpool.is_empty():
		var pick: int = randi_range(0, lpool.size() - 1)
		locations.append(String(lpool[pick]))
		lpool.remove_at(pick)
	phase = "playing"
	_identities_sent = false
	var cfg := {
		"hero_ids": heroes, "villain": villain, "locations": locations,
		"mode": String(mode_cfg.get("mode", "base")),
		"challenge": String(mode_cfg.get("challenge", "none")),
		"expansions": mode_cfg.get("expansions", []),
	}
	if not campaign_cfg.is_empty():
		cfg["campaign"] = campaign_cfg
	_push_lobby()
	for s in seats:
		if s != null and int(s["peer"]) > 1:
			rpc_id(int(s["peer"]), "rpc_start_play", cfg)
	start_play.emit(cfg)
	send_identities()   # 叛徒模式：开局把身份私下发给本人

@rpc("authority", "call_remote", "reliable")
func rpc_start_play(cfg: Dictionary) -> void:
	phase = "playing"
	start_play.emit(cfg)   # → _apply_start_play（进棋盘）

# ================================================================ 局域网发现（UDP 广播）

func _start_discovery_host() -> void:
	_stop_discovery()
	_udp_host = PacketPeerUDP.new()
	var err: int = _udp_host.bind(DISCOVER_PORT)
	if err != OK:
		# 端口被占（可能开了多个房间）→ 不影响联机，只是不能被自动搜到
		_udp_host = null
		return
	_udp_host.set_broadcast_enabled(true)

func _stop_discovery() -> void:
	if _udp_host != null:
		_udp_host.close()
		_udp_host = null
	if _udp_search != null:
		_udp_search.close()
		_udp_search = null
	_search_left = 0.0

## 搜索局域网房间：广播查询 → 收集 1.2 秒内的应答
func search_rooms() -> void:
	rooms = []
	if _udp_search != null:
		_udp_search.close()
	_udp_search = PacketPeerUDP.new()
	var err: int = _udp_search.bind(0)
	if err != OK:
		_fail("搜索失败：无法打开 UDP 端口")
		return
	_udp_search.set_broadcast_enabled(true)
	_udp_search.set_dest_address("255.255.255.255", DISCOVER_PORT)
	_udp_search.put_packet(MSG_DISCOVER.to_utf8_buffer())
	_search_left = 1.2
	set_process(true)

func _process(delta: float) -> void:
	# 快照节流：到点就把最后一次变化补发出去（保证客户端最终一致）
	if _snap_timer > 0.0:
		_snap_timer = maxf(_snap_timer - delta, 0.0)
		if _snap_timer <= 0.0 and _snap_dirty:
			_snap_dirty = false
			_snap_timer = 0.08
			broadcast_snapshot()
	# 主机：回答搜索请求
	if _udp_host != null and _udp_host.get_available_packet_count() > 0:
		while _udp_host.get_available_packet_count() > 0:
			var pkt := _udp_host.get_packet()
			if pkt.get_string_from_utf8().begins_with(MSG_DISCOVER):
				var info := JSON.stringify({
					"proto": PROTO, "name": String(room.get("name", "")),
					"players": player_count(), "max": int(room.get("max", 4)),
					"has_pw": String(room.get("password", "")) != "", "port": my_port,
				})
				_udp_host.set_dest_address(_udp_host.get_packet_ip(), _udp_host.get_packet_port())
				_udp_host.put_packet(info.to_utf8_buffer())
	# 客户端：收集搜索结果
	if _search_left > 0.0:
		_search_left -= delta
		if _udp_search != null:
			while _udp_search.get_available_packet_count() > 0:
				var pkt2 := _udp_search.get_packet()
				var d: Variant = JSON.parse_string(pkt2.get_string_from_utf8())
				if d is Dictionary and int(d.get("proto", 0)) == PROTO:
					var entry := {
						"ip": _udp_search.get_packet_ip(), "port": int(d.get("port", PORT)),
						"name": String(d.get("name", "房间")), "players": int(d.get("players", 0)),
						"max": int(d.get("max", 4)), "has_pw": bool(d.get("has_pw", false)),
					}
					var dup := false
					for r in rooms:
						if String(r["ip"]) == String(entry["ip"]) and int(r["port"]) == int(entry["port"]):
							dup = true
					if not dup:
						rooms.append(entry)
		if _search_left <= 0.0:
			rooms_found.emit(rooms)

# ================================================================ 对局同步（P3）

# ================================================================ 叛徒模式：开局私下发身份

var _identities_sent := false

## 把"某个英雄的身份"拼成给本人看的文字
func identity_text(hero: String) -> String:
	var loy: Dictionary = Game.state.get("loyalty", {})
	var is_tr: bool = String(loy.get(hero, "loyal")) == "traitor"
	if is_tr:
		return "%s\n\n你的身份：叛乱者 🔴\n\n（只有你自己知道）你要暗中破坏英雄们的计划。" % DB.hero_name(hero)
	return "%s\n\n你的身份：忠诚者 🔵\n\n和其他英雄一起击败反派！" % DB.hero_name(hero)

## 本人看自己的身份（客户端收到的私有弹窗）
@rpc("authority", "call_remote", "reliable")
func rpc_show_identity(text: String) -> void:
	show_modal(text, [{"key": "ok", "label": "知道了"}])

## 主机：开局把每个人的身份**私下**发给本人（别人看不到）
func send_identities() -> void:
	if not is_host or not active or _identities_sent:
		return
	if String(Game.state.get("challenge", "")) != "traitor":
		return
	_identities_sent = true
	for i in range(seats.size()):
		var s: Variant = seats[i]
		if s == null:
			continue
		var hero := String(s.get("hero", ""))
		if hero == "":
			continue
		var txt := identity_text(hero)
		if int(s["peer"]) > 1:
			rpc_id(int(s["peer"]), "rpc_show_identity", txt)
		else:
			show_modal(txt, [{"key": "ok", "label": "知道了"}])
## 主机 → 指定客户端：裁剪过的状态快照（他人手牌/牌库清空，只留张数）
## 注意必须 reliable：一次快照约 5~8KB，远超 ENet MTU(1392)，走 unreliable 会大量丢包导致状态不同步。
@rpc("authority", "call_remote", "reliable")
func rpc_snapshot(data: Dictionary) -> void:
	Game.state = data
	Events.state_changed.emit()

@rpc("any_peer", "call_remote", "reliable")
func rpc_intent(name: String, args: Array) -> void:
	if not is_host:
		return
	var peer := multiplayer.get_remote_sender_id()
	if not _peer_may_act(peer):
		return
	Game.apply_net_intent(name, args)

@rpc("any_peer", "call_remote", "reliable")
func rpc_answer(kind: String, value: Variant) -> void:
	if not is_host:
		return
	var peer := multiplayer.get_remote_sender_id()
	if not _peer_may_act(peer):
		return
	Game.apply_net_answer(kind, value)

## 该 peer 是否是当前该操作的玩家
func _peer_may_act(peer: int) -> bool:
	if Game.state.is_empty():
		return false
	# 弹窗进行中：按"这个弹窗该谁答"判定；否则按当前行动英雄
	var cur := _prompt_answer_hero if _prompt_answer_hero != "" else Game.current_hero_id()
	for s in seats:
		if s != null and int(s["peer"]) == peer:
			return String(s.get("hero", "")) == cur
	return false

func send_intent(name: String, args: Array) -> void:
	if is_host:
		Game.apply_net_intent(name, args)
	else:
		rpc_id(1, "rpc_intent", name, args)

func send_answer(kind: String, value: Variant) -> void:
	if is_host:
		Game.apply_net_answer(kind, value)
	else:
		rpc_id(1, "rpc_answer", kind, value)

## 主机：向所有客户端广播当前状态（各自裁剪）
func broadcast_snapshot() -> void:
	if not is_host or multiplayer.multiplayer_peer == null:
		return
	for i in range(seats.size()):
		var s: Variant = seats[i]
		if s == null or int(s["peer"]) <= 1:
			continue
		rpc_id(int(s["peer"]), "rpc_snapshot", visible_state_for(String(s.get("hero", ""))))

## 生成"给某个英雄的玩家看"的状态：只保留他的手牌/牌库，其他人只留张数
func visible_state_for(hero_id: String) -> Dictionary:
	var d: Dictionary = Game.state.duplicate(true)
	var hs: Dictionary = d.get("heroes", {})
	for hid in hs.keys():
		var h: Dictionary = hs[hid]
		h["hand_count"] = (h.get("hand", []) as Array).size()
		h["deck_count"] = (h.get("deck", []) as Array).size()
		if String(hid) != hero_id:
			h["hand"] = []
			h["deck"] = []
	# ---- 真背面：玩家本来看不到的东西不下发 ----
	# ① 反派牌堆顺序（含宝石卡插在第几张）：只给张数 + "牌堆顶是不是宝石"（这个提示本来就公开给玩家看）
	var md: Array = d.get("master_deck", [])
	var top_stone := false
	if md.size() > 0 and md[0] is Dictionary and (md[0] as Dictionary).has("stone"):
		top_stone = true
	d["master_deck_count"] = md.size()
	d["master_deck_top_is_stone"] = top_stone
	d["master_deck"] = []
	d["stones_inserted"] = []
	# 裁定③/⑨：阿戈摩托之球生效时，反派牌堆顶那张要公开给所有人（牌不动、不结算）。
	# 注意：其它牌仍按"真背面"裁剪（只给张数），这里只额外放行顶牌的内容。
	d["villain_top_public"] = Game._villain_top_public_now()
	d["villain_top_idx"] = Game._next_villain_action_from_top() if bool(d["villain_top_public"]) else -1
	# ② 未解锁的第二张能量卡：它在本机界面上是"整卡置暗+盖锁图标"，本来就不是秘密
	# （主机自己看得见是哪张）→ 照原样下发给客户端，客户端才能画出和主机一样的卡。
	# 之前把它裁成 -1，导致别人屏幕上这张卡直接消失（用户报的 bug3）。
	# ③ 邪恶六人组行动牌堆顺序：只给张数
	if d.has("s6") and d["s6"] is Dictionary:
		var s6d: Dictionary = d["s6"]
		s6d["deck_count"] = (s6d.get("deck", []) as Array).size()
		s6d["deck"] = []
	# ④ 面朝下放进故事情节的牌：不告诉是哪张（UI 本来就用 idx = -1 画背面）
	for e in (d.get("story", []) as Array):
		if e is Dictionary and bool(e.get("face_down", false)):
			e["idx"] = -1
	# 叛徒模式：只下发"接收者自己"的身份；别人的身份（含谁是叛徒）绝不能下发
	if d.has("loyalty"):
		var loy: Dictionary = d["loyalty"]
		d["loyalty"] = {hero_id: loy[hero_id]} if loy.has(hero_id) else {}
	if d.has("traitor_hid") and String(d.get("traitor_hid", "")) != hero_id:
		d["traitor_hid"] = ""
	return d

## 主机：把弹窗同步给所有人（can_answer 只对当前玩家为真）
## 同时把"本地这个弹窗是不是只读"告诉本机的 PopupLayer：
##   - 主机自己也一样：轮到别人时，主机的弹窗也必须只读（否则房主能替别人点）
func broadcast_prompt(kind: String, payload: Variant, answer_hero: String = "") -> void:
	var who: String = answer_hero if answer_hero != "" else Game.current_hero_id()
	_prompt_answer_hero = who
	Events.popup_readonly_changed.emit(active and who != controlling_hero())
	if not is_host or multiplayer.multiplayer_peer == null:
		return
	for i in range(seats.size()):
		var s: Variant = seats[i]
		if s == null or int(s["peer"]) <= 1:
			continue
		var can: bool = String(s.get("hero", "")) == who
		rpc_id(int(s["peer"]), "rpc_prompt", kind, _prompt_payload_for(kind, payload, can), can)

## 私有弹窗的"给别人看"的版本：量子魔法要看的是"反派牌堆顶 3 张"，
## 具体牌面只该发给该答的玩家，其他人只收到一句提示（不然等于公开了牌堆顶）。
func _prompt_payload_for(kind: String, payload: Variant, can_answer: bool) -> Variant:
	if can_answer or kind != "reorder" or not (payload is Dictionary):
		return payload
	var d: Dictionary = (payload as Dictionary).duplicate(true)
	d.erase("cards")
	d["title"] = String(d.get("public_title", "对方正在查看反派牌堆顶并调整顺序…"))
	return d

## 一个弹窗被回答完了：本机收起所有弹窗，主机再通知所有客户端一起收起。
## 幂等，多个端各自调用不会互相影响。
func finish_prompt() -> void:
	_prompt_answer_hero = ""
	Events.popup_readonly_changed.emit(false)
	_popup_cmd.emit("hide")
	if not is_host or multiplayer.multiplayer_peer == null:
		return
	for i in range(seats.size()):
		var s: Variant = seats[i]
		if s == null or int(s["peer"]) <= 1:
			continue
		rpc_id(int(s["peer"]), "rpc_prompt_closed")

## 收到"开始这一局"的配置 → 所有端都进棋盘（主机由 Board 自动开第一个反派回合）。
## 放在 Net 里而不是 Setup 里：无限战争的"下一局"是在棋盘上点的，那时 Setup 已经销毁了。
func _apply_start_play(cfg: Dictionary) -> void:
	if not auto_board_handoff:
		return
	Game.pending_setup = {
		"villain": String(cfg.get("villain", "redskull")),
		"heroes": cfg.get("hero_ids", []),
		"challenge": String(cfg.get("challenge", "none")),
		"mode": String(cfg.get("mode", "base")),
		"expansions": cfg.get("expansions", []),
		"debug_full_slots": Game.debug_full_slots,
		"peek_hands": false,
	}
	# 无限战争战役：把战役进度也带上（客户端据此建出同一局的占位状态）
	if cfg.has("campaign"):
		Game.pending_campaign = cfg["campaign"]
	elif String(cfg.get("mode", "")) == "iw":
		Game.pending_campaign = {}
	Game.net_auto_start = is_host
	UiKit.goto_scene("res://src/ui/Board.tscn")

## 无限战争：房主开下一局（战役进度：局数 +1；决战固定灭霸 + 专属地点）
func host_next_campaign_game() -> void:
	if not is_host or not active:
		return
	var c: Dictionary = Game.pending_campaign
	if c.is_empty():
		c = {"game": 1, "order": campaign_order, "stones_collected": [], "energy_unlocked": []}
	c["game"] = int(c.get("game", 1)) + 1
	var game_no: int = int(c["game"])
	var order: Array = c.get("order", [])
	var vid := "thanos"                       # 第 4 局决战固定灭霸
	if game_no < 4 and order.size() >= game_no:
		vid = String(order[game_no - 1])       # 前 3 局按房主排的顺序
	var exps: Array = ["无限战争决战"] if game_no >= 4 else ["无限战争"]
	Game.pending_campaign = c
	var heroes: Array = []
	for s in seats:
		if s != null:
			heroes.append(String(s.get("hero", "")))
	heroes = heroes.filter(func(x): return String(x) != "")
	if heroes.is_empty():
		for hid in Game.state.get("hero_ids", []):
			heroes.append(String(hid))
	var cfg := {
		"hero_ids": heroes, "villain": vid, "locations": _draw_locations_from(exps, 6),
		"mode": "iw", "challenge": String(Game.state.get("challenge", "none")),
		"expansions": exps, "campaign": c,
	}
	for i in range(seats.size()):
		var s2: Variant = seats[i]
		if s2 != null and int(s2["peer"]) > 1:
			rpc_id(int(s2["peer"]), "rpc_start_play", cfg)
	start_play.emit(cfg)

## 从指定扩展里随机抽 n 张地点
func _draw_locations_from(exps: Array, n: int) -> Array:
	var pool: Array = []
	for lid in DB.locations.keys():
		if exps.has(String(DB.location(String(lid)).get("expansion", "基础盒"))):
			pool.append(String(lid))
	if pool.is_empty():
		for lid in DB.locations.keys():
			pool.append(String(lid))
	pool.shuffle()
	var out: Array = []
	for i in range(mini(n, pool.size())):
		out.append(String(pool[i]))
	return out

func _seat_cs(s: Variant) -> Array:
	var cs: Array = []
	if s is Dictionary:
		cs = (s.get("cs", []) as Array).duplicate()
	while cs.size() < 3:
		cs.append("")
	return cs

func my_campaign_slots() -> Array:
	return _seat_cs(my_seat_data())

## 第 slot 局（0..2）的候选池 = 所有玩家在该格里选的反派
func campaign_pool(slot: int) -> Array:
	var out: Array = []
	for s in seats:
		if s == null:
			continue
		var cs: Array = _seat_cs(s)
		if slot < cs.size():
			var v := String(cs[slot])
			if v != "" and not out.has(v):
				out.append(v)
	return out

## 初始默认：每人的三格 = 暗夜比邻星 / 黑矮星 / 乌木侯（之后可自行切换）
func init_campaign_defaults() -> void:
	if not is_host:
		return
	for i in range(seats.size()):
		var s: Variant = seats[i]
		if s == null:
			continue
		var cs: Array = _seat_cs(s)
		if String(cs[0]) == "" and String(cs[1]) == "" and String(cs[2]) == "":
			(s as Dictionary)["cs"] = ["proxima", "cull", "ebony"]
			seats[i] = s
## 联机：任务完成动画要在每台机器上播（游戏逻辑只在主机跑，客户端收不到这个事件）
func broadcast_mission_completed(count: int, hero: String) -> void:
	if not is_host or multiplayer.multiplayer_peer == null:
		return
	for i in range(seats.size()):
		var s: Variant = seats[i]
		if s != null and int(s["peer"]) > 1:
			rpc_id(int(s["peer"]), "rpc_mission_completed", count, hero)

@rpc("authority", "call_remote", "reliable")
func rpc_mission_completed(count: int, hero: String) -> void:
	Events.mission_completed.emit(count, hero)

## 主机 → 所有客户端：这个弹窗已经被处理掉了，把它关掉
@rpc("authority", "call_remote", "reliable")
func rpc_prompt_closed() -> void:
	Events.popup_readonly_changed.emit(false)
	_popup_cmd.emit("hide")

@rpc("authority", "call_remote", "reliable")
func rpc_prompt(kind: String, payload: Variant, can_answer: bool) -> void:
	Events.popup_readonly_changed.emit(not can_answer)
	prompt_sync.emit(kind, payload, can_answer)

## 弹窗指令（hide 等）通过这个信号转给 Board 的 PopupLayer
signal _popup_cmd(cmd: String)

## 主机：弹窗被回答后广播"关闭"。用 waiting_input 的 true→false 跳变统一检测，
## 不用在每个 _ask_* 里插代码（8 处弹窗类型都能覆盖）。
var _last_waiting := false

func _watch_waiting() -> void:
	if not is_host or not active:
		return
	var w: bool = bool(Game.state.get("waiting_input", false))
	if w == _last_waiting:
		return
	_last_waiting = w
	if not w:
		for i in range(seats.size()):
			var s: Variant = seats[i]
			if s == null or int(s["peer"]) <= 1:
				continue
			rpc_id(int(s["peer"]), "rpc_prompt_closed")

func _start_poll() -> void:
	set_process(true)
