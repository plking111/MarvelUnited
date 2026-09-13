extends Node
## 联机对局表现层验证（单进程，用假身份模拟）：
##  bug2：手牌区必须固定显示"我自己的英雄"（不能因为轮到别人就显示/看不到牌）
##  bug3：日志以 Game.state["log"] 为准 → 客户端靠快照也能完整同步（不再只靠 log_line 事件）
##  bug4：非本人操作的弹窗必须只读（点不动）；主机那边答完 → 本机弹窗自动收起

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

	# ---------- 造一个"我是 vision、房主是 wasp"的假联机身份 ----------
	Game.pending_setup = {"villain": "redskull", "heroes": ["wasp", "vision"], "challenge": "none", "mode": "base"}
	Net.active = true
	Net.is_host = true          # 先以主机身份建 Board（Board._ready 会 Game.setup）
	Net.my_peer = 1
	Net.seats = [
		{"peer": 1, "name": "房主", "hero": "wasp", "villain": "", "locs": [], "ready": false},
		{"peer": 2, "name": "小号", "hero": "vision", "villain": "", "locs": [], "ready": false},
	]
	var board: Control = load("res://src/ui/Board.tscn").instantiate()
	add_child(board)
	await _frames(8)
	_check("Board 起来了（state 非空）", not Game.state.is_empty(), "")

	# ---------- bug2：手牌固定显示自己的英雄 ----------
	# 房主身份（我的英雄 = wasp），把"当前英雄"设成 vision（模拟轮到客户端）
	Game.state["current_hero"] = Game.state["hero_ids"].find("vision")
	Events.state_changed.emit()
	await _frames(3)
	_check("bug2：轮到别人时，手牌区仍显示自己的英雄（wasp）",
		board.hand_hero_id == "wasp", "hand_hero_id=%s（当前英雄=%s）" % [board.hand_hero_id, Game.current_hero_id()])
	# 换成客户端身份（我的英雄 = vision）→ 应显示 vision
	Net.my_peer = 2
	Net.is_host = false
	Game.state["current_hero"] = Game.state["hero_ids"].find("wasp")
	Events.state_changed.emit()
	await _frames(3)
	_check("bug2：客户端看到的也是自己的英雄（vision），不是当前行动英雄",
		board.hand_hero_id == "vision", "hand_hero_id=%s" % board.hand_hero_id)

	# ---------- bug3：日志由 state["log"] 驱动（客户端也能同步）----------
	board._clear_children(board._log_box)
	board._log_shown = 0
	Game.state["log"] = []
	Events.state_changed.emit()
	await _frames(2)
	var before: int = board._log_box.get_child_count()
	# 模拟"主机产生的日志随快照到达客户端"：直接往 state["log"] 里追加，再发 state_changed
	(Game.state["log"] as Array).append({"t": "【联机】反派行动牌：移动1", "c": "#ff9999"})
	(Game.state["log"] as Array).append({"t": "【联机】美国队长 打出卡牌：攻击", "c": "#ccffff"})
	Events.state_changed.emit()
	await _frames(3)
	_check("bug3：state[\"log\"] 新增的行会补进日志框（客户端靠快照即可同步）",
		board._log_box.get_child_count() == before + 2,
		"before=%d after=%d" % [before, board._log_box.get_child_count()])
	Events.state_changed.emit()
	await _frames(2)
	_check("bug3：重复刷新不会重复追加日志", board._log_box.get_child_count() == before + 2,
		"after=%d" % board._log_box.get_child_count())
	# 开新局日志清空 → 视图重建
	Game.state["log"] = [{"t": "新一局", "c": "#ffffff"}]
	Events.state_changed.emit()
	await _frames(3)
	_check("bug3：日志被清空后视图重建（不残留旧行）", board._log_box.get_child_count() == 1,
		"count=%d" % board._log_box.get_child_count())

	# ---------- bug4：弹窗只读 / 答完自动收起 ----------
	var popup: CanvasLayer = load("res://src/ui/PopupLayer.gd").new()
	add_child(popup)
	# 按 Board 的真实接线：弹窗挂到 Events 的 prompt_* 上 + 只读信号 + 关闭指令
	Events.prompt_action.connect(popup.show_action_prompt)
	Events.prompt_confirm.connect(popup.show_confirm)
	Events.prompt_hand_card.connect(popup.show_hand_pick)
	Events.popup_readonly_changed.connect(popup.set_readonly)
	Net._popup_cmd.connect(func(cmd: String) -> void:
		if cmd == "hide":
			popup.hide_all_prompts())
	# 非本人操作的弹窗 → 只读（走客户端的真实入口 rpc_prompt：它会发只读信号 + prompt_sync）
	Net.my_peer = 2
	Net.is_host = false
	Game.state["current_hero"] = Game.state["hero_ids"].find("wasp")   # 当前是房主的回合
	Net.rpc_prompt("action", {"title": "选择攻击目标", "rows": [{"text": "暴徒", "hide_text": true}]}, false)
	await _frames(2)
	_check("bug4：非本人操作的弹窗 → 只读", popup.readonly == true, "")
	var row := _first_action_row(popup)
	_check("bug4：只读时选项行不可点（mouse_filter=IGNORE）",
		row != null and row.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"row=%s filter=%s" % [str(row), str(row.mouse_filter) if row != null else "-"])
	_check("bug4：只读弹窗标题标注「等待其他玩家选择…」",
		_find_label_text(popup, "等待其他玩家选择"), "")
	# 主机答完 → 本机弹窗收起 + 只读复位
	Net.rpc_prompt_closed()
	await _frames(2)
	_check("bug4：收到关闭指令后弹窗全部收起",
		not is_instance_valid(popup._action_root) and not popup.prompt_panel.visible, "")
	_check("bug4：关闭后只读状态复位", popup.readonly == false, "")
	# 轮到我 → 可点
	Game.state["current_hero"] = Game.state["hero_ids"].find("vision")
	Net.rpc_prompt("action", {"title": "选择攻击目标", "rows": [{"text": "暴徒", "hide_text": true}]}, true)
	await _frames(2)
	_check("bug4：轮到我时弹窗可操作（非只读）", popup.readonly == false, "")
	row = _first_action_row(popup)
	_check("bug4：本人操作时选项行可点（mouse_filter=STOP）",
		row != null and row.mouse_filter == Control.MOUSE_FILTER_STOP, "")

	# ---------- bug4：弹窗答完必须"所有端"都收起（含主机自己那把只读弹窗）----------
	Game.state["current_hero"] = Game.state["hero_ids"].find("wasp")
	Net.my_peer = 1
	Net.is_host = true
	Net.rpc_prompt("action", {"title": "选择攻击目标", "rows": [{"text": "暴徒", "hide_text": true}]}, false)
	await _frames(2)
	_check("bug4：主机侧也显示弹窗（只读）", is_instance_valid(popup._action_root) and popup.readonly, "")
	Game._begin_wait()
	Game._end_wait()          # 模拟"客户端答完 → 主机这边的等待结束"
	await _frames(3)
	_check("bug4：答完后主机自己的弹窗也收起（以前会一直挂着挡住操作）",
		not is_instance_valid(popup._action_root), "")
	_check("bug4：收起后只读状态复位", popup.readonly == false, "")

	# ---------- bug5：右下角显示队友手牌张数 ----------
	Net.my_peer = 1
	Net.is_host = true
	Game.state["heroes"]["wasp"]["hand"] = [0, 1, 2]
	Game.state["heroes"]["vision"]["hand"] = [3, 4]
	Events.state_changed.emit()
	await _frames(3)
	_check("bug5：棋盘右下角有「队友手牌」面板", board._mp_peers_box != null, "")
	var txt := _all_label_text(board._mp_peers_box)
	_check("bug5：显示队友（P2）的手牌张数 2 张", txt.contains("2 张"), txt)
	_check("bug5：不显示自己的张数（只列队友）", not txt.contains("P1 "), txt)
	# 客户端视角：别人的手牌被裁掉，只有 hand_count
	Net.my_peer = 2
	Net.is_host = false
	var vis: Dictionary = Net.visible_state_for("vision")
	Game.state = vis
	Events.state_changed.emit()
	await _frames(3)
	txt = _all_label_text(board._mp_peers_box)
	_check("bug5：客户端靠 hand_count 也能显示队友张数（3 张）", txt.contains("3 张"), txt)

	# ---------- bug1：队友手牌面板要带英雄图标 ----------
	_check("bug1：队友手牌面板每行有英雄图标（TextureRect）",
		_count_texture_rects(board._mp_peers_box) >= 1,
		"图标数=%d" % _count_texture_rects(board._mp_peers_box))

	# ---------- bug2：房主掉线 → 全局弹窗「房间已丢失」+ 返回按钮 ----------
	var picked := {"k": ""}
	Net.modal_choice.connect(func(k: String) -> void: picked["k"] = k)
	Net.show_modal("房间已丢失：房主已退出游戏", [{"key": "back", "label": "返回主菜单"}])
	await _frames(2)
	_check("bug2：弹窗出现（盖在任何界面之上）", Net._modal_layer != null and Net._modal_layer.visible, "")
	_check("bug2：弹窗文字是「房间已丢失」", _all_label_text(Net._modal_layer).contains("房间已丢失"),
		_all_label_text(Net._modal_layer))
	_check("bug2：弹窗有「返回主菜单」按钮", _find_button_text(Net._modal_layer, "返回主菜单") != null, "")
	var mb := _find_button_text(Net._modal_layer, "返回主菜单")
	if mb != null:
		mb.pressed.emit()
	await _frames(2)
	_check("bug2：点返回后弹窗关闭并回传 back", not Net._modal_layer.visible and String(picked["k"]) == "back", str(picked))

	# ---------- bug3：玩家退出后由房主代管（轮到他的回合房主能操作，界面和本地一致）----------
	Net.my_peer = 1
	Net.is_host = true
	Net.phase = "playing"
	Net.seats[1]["disconnected"] = true
	Net.seats[1]["peer"] = -1
	Net.seats[1]["hero"] = "vision"
	Game.state["current_hero"] = Game.state["hero_ids"].find("vision")   # 轮到已退出的玩家
	Events.state_changed.emit()
	await _frames(3)
	_check("bug3：房主代管已退出玩家的英雄（controlling_hero = vision）",
		Net.controlling_hero() == "vision", Net.controlling_hero())
	_check("bug3：房主的 is_my_turn 为真（可以替他操作）", Net.is_my_turn(), "")
	_check("bug3：手牌区显示被代管英雄的手牌（和本地一致）", board.hand_hero_id == "vision",
		"hand_hero_id=%s" % board.hand_hero_id)
	_check("bug3：队友面板标注「已退出·房主代管」",
		_all_label_text(board._mp_peers_box).contains("房主代管"), _all_label_text(board._mp_peers_box))

	# ---------- 别人的手牌只显示卡背（含"主机看别人受伤弃牌"）----------
	Net.my_peer = 1
	Net.is_host = true
	Net.phase = "playing"
	Net.seats[1]["disconnected"] = false      # 撤销上面的"代管"设定，回到正常两人局
	Net.seats[1]["peer"] = 2
	Game.state["current_hero"] = Game.state["hero_ids"].find("wasp")   # 当前轮到我（wasp）
	Game.state["heroes"]["vision"]["hand"] = [3, 4, 5]
	Events.prompt_hand_card.emit(func(_p: Variant) -> void: pass, "受到伤害：选择要弃掉的手牌", "vision", 1)
	await _frames(3)
	_check("别人（vision）的手牌只显示卡背，不泄露正面",
		_count_tex(popup.hand_pick_box, DB.hero_back("vision")) == 3
		and _count_tex(popup.hand_pick_box, UiKit.hero_card_image("vision", 3)) == 0,
		"卡背=%d 正面=%d" % [_count_tex(popup.hand_pick_box, DB.hero_back("vision")),
			_count_tex(popup.hand_pick_box, UiKit.hero_card_image("vision", 3))])
	_check("卡背弹窗标题就是原提示（不再加「谁的手牌」那种说明文字）",
		String(popup.hand_pick_label.text) == "受到伤害：选择要弃掉的手牌",
		String(popup.hand_pick_label.text))
	_check("看别人的牌时确认按钮不可用", popup.hand_pick_confirm.disabled, "")
	popup.cancel_hand_pick()
	await _frames(2)
	# 自己的（我能操作的）英雄仍然显示正面
	Game.state["heroes"]["wasp"]["hand"] = [0, 1, 2]
	Events.prompt_hand_card.emit(func(_p: Variant) -> void: pass, "受到伤害：选择要弃掉的手牌", "wasp", 1)
	await _frames(3)
	_check("自己的手牌显示正面（不是卡背）",
		_count_tex(popup.hand_pick_box, DB.hero_back("wasp")) == 0
		and _count_tex(popup.hand_pick_box, UiKit.hero_card_image("wasp", 0)) == 1,
		"卡背=%d 正面=%d" % [_count_tex(popup.hand_pick_box, DB.hero_back("wasp")),
			_count_tex(popup.hand_pick_box, UiKit.hero_card_image("wasp", 0))])
	popup.cancel_hand_pick()
	await _frames(2)

	# ---------- bug3：弹窗"该谁答"按目标英雄算，不按当前行动英雄 ----------
	# 场景：别人行动时我被伤害要弃牌（当前行动英雄 = 别人）→ 我必须能选，否则卡死
	Net.my_peer = 1
	Net.is_host = true
	Net.phase = "playing"
	Net.seats[1]["disconnected"] = false
	Net.seats[1]["peer"] = 2
	Game.state["current_hero"] = Game.state["hero_ids"].find("vision")
	Game.state["heroes"]["wasp"]["hand"] = [0, 1, 2]
	Net.broadcast_prompt("hand", {"title": "受到伤害：选择要弃掉的手牌", "hid": "wasp", "count": 1}, "wasp")
	await _frames(3)
	_check("bug3：目标是我自己的弃牌弹窗 → 我这边不是只读（否则卡死）", popup.readonly == false, "")
	_check("bug3：并且显示的是我的正面牌", _count_tex(popup.hand_pick_box, DB.hero_back("wasp")) == 0
		and _count_tex(popup.hand_pick_box, UiKit.hero_card_image("wasp", 0)) == 1, "")
	popup.cancel_hand_pick()
	await _frames(2)
	# 注：主机本机的弹窗是 _ask_* 直接弹出的，broadcast_prompt 只负责转发给客户端，
	# 所以"目标是别人 → 只读 + 卡背"用 Events 直接弹来验（上面那一段已覆盖）。

	# ---------- 濒危地点：手牌区旁边的指示物只显示自己的 ----------
	Net.my_peer = 1
	Net.is_host = true
	Net.phase = "playing"
	Game.state["challenge"] = "endangered"
	Game.state["endangered"] = {"wasp": 1, "vision": 3, "setup_done": true}
	Game.state["current_hero"] = Game.state["hero_ids"].find("vision")   # 当前行动者是别人
	Events.state_changed.emit()
	await _frames(3)
	_check("濒危：轮到我时，指示物跟我的手牌走（wasp 的编号 1）",
		board._endangered_side_box.visible and board._endangered_side_box.get_child_count() == 1
		and (board._endangered_side_box.get_child(0) as TextureRect).texture == load("res://assets/tokens/endangered_1.png"),
		"visible=%s children=%d" % [str(board._endangered_side_box.visible), board._endangered_side_box.get_child_count()])
	Net.my_peer = 2                                   # 换成客户端（我的英雄 = vision）
	Net.is_host = false
	Game.state["current_hero"] = Game.state["hero_ids"].find("wasp")
	Events.state_changed.emit()
	await _frames(3)
	_check("濒危：客户端看到的是自己（vision 的编号 2），不是当前行动英雄的",
		board._endangered_side_box.get_child_count() == 1
		and (board._endangered_side_box.get_child(0) as TextureRect).texture == load("res://assets/tokens/endangered_2.png"),
		"children=%d" % board._endangered_side_box.get_child_count())

	# ---------- "真背面"：玩家本来看不到的数据不下发 ----------
	Game.state["master_deck"] = [0, 1, {"stone": 2}, 3]
	Game.state["stones_inserted"] = [2]
	Game.state["hidden_energy"] = 5
	Game.state["s6"] = {"deck": [1, 2, 3], "discard": [], "vills": {}}
	(Game.state["story"] as Array).append({"type": "villain", "villain": "s6", "idx": 7, "move": 0, "face_down": true})
	var vis3: Dictionary = Net.visible_state_for("wasp")
	_check("真背面：反派牌堆顺序不下发（只给张数）",
		(vis3["master_deck"] as Array).is_empty() and int(vis3["master_deck_count"]) == 4,
		"deck=%s count=%s" % [str(vis3["master_deck"]), str(vis3.get("master_deck_count"))])
	_check("真背面：牌堆顶是不是宝石这个公开提示保留",
		bool(vis3.get("master_deck_top_is_stone", false)) == false, "顶牌是数字 0，应为 false")
	_check("真背面：宝石插在哪几张不下发", (vis3["stones_inserted"] as Array).is_empty(), str(vis3["stones_inserted"]))
	# 未解锁能量卡在主机界面上是"整卡置暗 + 盖锁图标"——主机自己看得见是哪张，
	# 所以它不是秘密：要照原样下发，客户端才能画出和主机一样的卡（用户要求）
	_check("未解锁能量卡：照原样下发（客户端要和主机显示一样）", int(vis3["hidden_energy"]) == 5, str(vis3["hidden_energy"]))
	_check("真背面：六人组行动牌堆顺序不下发（只给张数）",
		(vis3["s6"]["deck"] as Array).is_empty() and int(vis3["s6"]["deck_count"]) == 3,
		"deck=%s" % str(vis3["s6"]["deck"]))
	_check("真背面：扣在故事情节里的牌不告诉是哪张",
		int((vis3["story"] as Array)[(vis3["story"] as Array).size() - 1]["idx"]) == -1, "")
	_check("只裁客户端的副本：主机自己仍有完整牌堆", (Game.state["master_deck"] as Array).size() == 4, "")

	# ---------- 联机：JSON 快照后的能量卡填充数据必须仍能点亮槽位图标 ----------
	Game.state["mode"] = "iw"
	Game.state["table_energy"] = 0
	Game.state["hidden_energy"] = 1
	Game.state["energy_tokens"] = {"0": [0.0, 2.0]}   # 模拟 JSON 快照（浮点）
	_check("能量卡：JSON 浮点填充数据被归一化成 int",
		str(Game.energy_filled_slots(0)) == str([0, 2]) and Game.energy_filled(0) == 2,
		str(Game.energy_filled_slots(0)))
	_check("能量卡：槽位图标判定能对上（has(0)/has(2)）",
		(Game.energy_filled_slots(0) as Array).has(0) and (Game.energy_filled_slots(0) as Array).has(2),
		str(Game.energy_filled_slots(0)))

	# 清理
	popup.queue_free()
	board.queue_free()
	await _frames(2)
	Net.seats = []
	Net.active = false
	Net.is_host = true
	Net.my_peer = 1

	if _fail == 0:
		print("=== MP VIEW SYNC TEST ALL PASSED ===")
		get_tree().quit(0)
	else:
		print("=== MP VIEW SYNC TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)

## 找到弹窗里第一个"选项行"控件（HFlowContainer 里的 PanelContainer）
func _first_action_row(popup: CanvasLayer) -> Control:
	if not is_instance_valid(popup._action_root):
		return null
	var flow := _find_flow(popup._action_root)
	if flow == null:
		return null
	for c in flow.get_children():
		if c is PanelContainer:
			return c
	return null

func _find_flow(node: Node) -> Node:
	if node is HFlowContainer:
		return node
	for c in node.get_children():
		var r: Node = _find_flow(c)
		if r != null:
			return r
	return null

func _find_label_text(root: Node, needle: String) -> bool:
	for c in root.get_children():
		if c is Label and String(c.text).contains(needle):
			return true
		if _find_label_text(c, needle):
			return true
	return false

## 把一个节点下所有 Label 的文字拼起来（断言面板内容用）
func _all_label_text(root: Node) -> String:
	if root == null:
		return ""
	var out := ""
	for c in root.get_children():
		if c is Label:
			out += String((c as Label).text) + " | "
		out += _all_label_text(c)
	return out

## 统计节点树里的 TextureRect 数量（图标断言用）
func _count_texture_rects(root: Node) -> int:
	if root == null:
		return 0
	var n := 0
	for c in root.get_children():
		if c is TextureRect:
			n += 1
		n += _count_texture_rects(c)
	return n

## 统计显示某张图的 TextureRect 个数（卡背/正面断言用）
func _count_tex(root: Node, path: String) -> int:
	if root == null:
		return 0
	var target: Texture2D = load(path)
	var n := 0
	for c in root.get_children():
		if c is TextureRect and (c as TextureRect).texture == target:
			n += 1
		n += _count_tex(c, path)
	return n

## 按文字找按钮（弹窗断言用）
func _find_button_text(root: Node, text: String) -> Button:
	if root == null:
		return null
	for c in root.get_children():
		if c is Button and String((c as Button).text).contains(text):
			return c
		var r := _find_button_text(c, text)
		if r != null:
			return r
	return null
