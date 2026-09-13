extends Node
## 裁定③（新口径）：阿戈摩托之球"反派牌堆顶公开" = **贴卡图 + 悬停放大**（不再是文字提示）。
##
## 覆盖：
##  ① 未启用 → 卡图节点不可见、无贴图
##  ② 启用（单机/主机：本地直接算）→ 反派牌堆右侧出现卡图，贴图 == UiKit.villain_action_image(villain, idx)
##  ③ 顶牌换了 → 同一个节点贴图跟着换（不重建节点）
##  ④ 悬停 → 复用 Board._zoom_show()：放大面板出现、内容就是这张牌；移开 → 收起
##  ⑤ 失效（球离开可见区 / idx 越界 / 没有合法 idx / s6 模式）→ 卡图隐藏 + 放大面板一并收起
##  ⑥ 联机客户端：只用快照下发的 villain_top_public / villain_top_idx 渲染
##     （快照里 master_deck 已被裁成空数组 → 本地根本算不出顶牌，能画对就证明没读 master_deck）
##  ⑦ 有卡图时不再显示文字提示；文字只在"没有卡图"时兜底（无限战争分支里验一次）
##
## 无头环境的限制：这里用 mouse_entered / mouse_exited 信号直接驱动（等价于鼠标移入/移出），
## 真实鼠标轨迹、放大图的屏幕位置跟随、以及"看起来对不对"只能人工看。

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

## 阿戈摩托之球是奇异博士的第几张牌（0 基）
func _orb_card_idx() -> int:
	var cs: Array = DB.hero_cards("drstrange")
	for i in range(cs.size()):
		if String((cs[i] as Dictionary).get("effect", {}).get("type", "")) == "drstrange_orb_of_agamotto":
			return i
	return -1

## 让"球在可见区"：把这张牌放进故事情节（可见区判定见 Game._villain_top_public_now()）
func _put_orb_in_story() -> void:
	Game.state["story"].append({"type": "hero", "hero": "drstrange", "idx": _orb_card_idx()})

## 往故事情节里塞 STORY_VISIBLE+1 张无关牌 → 把球挤出可见区
func _push_orb_out_of_view() -> void:
	for i in range(Game.STORY_VISIBLE + 1):
		Game.state["story"].append({"type": "hero", "hero": "cap", "idx": 0})

func _ready() -> void:
	Game.autopilot = true
	Game.pending_setup = {"villain": "redskull", "heroes": ["drstrange", "cap"], "challenge": "none", "mode": "base"}
	var board: Control = load("res://src/ui/Board.tscn").instantiate()
	add_child(board)
	await _frames(6)
	_check("Board 起来了", not Game.state.is_empty(), "")
	_check("前置：奇异博士确实有「阿戈摩托之球」这张牌", _orb_card_idx() >= 0, "idx=%d" % _orb_card_idx())
	var deck_right: float = board._villain_deck_info.position.x + board._villain_deck_info.custom_minimum_size.x

	# ---------------- ① 未启用 ----------------
	_check("① 未启用：卡图节点存在但不可见", board._villain_top_card != null and not board._villain_top_card.visible, "")
	_check("① 未启用：卡图无贴图", board._villain_top_card.texture == null, "")

	# ---------------- ② 启用（单机/主机本地计算）----------------
	_put_orb_in_story()
	Game.state["master_deck"] = [3, 5, 7]      # 顶牌 = 行动卡 3
	Events.state_changed.emit()
	await _frames(3)
	_check("② 前置：球在可见区（_villain_top_public_now 为真）", Game._villain_top_public_now(), "")
	_check("② 前置：牌堆顶行动牌 idx = 3", Game._next_villain_action_from_top() == 3,
		"idx=%d" % Game._next_villain_action_from_top())
	_check("② 启用：卡图可见", board._villain_top_card.visible, "")
	var want3: Texture2D = load(UiKit.villain_action_image("redskull", 3))
	_check("② 启用：贴图 = 反派牌堆顶那张行动牌的卡图（action_04.png）",
		want3 != null and board._villain_top_card.texture == want3,
		"tex=%s" % str(board._villain_top_card.texture))
	_check("② 位置：卡图在反派牌堆右侧（x=%.0f ≥ 牌堆右缘 %.0f）" % [board._villain_top_card.position.x, deck_right],
		board._villain_top_card.position.x >= deck_right,
		"card.x=%.0f deck_right=%.0f" % [board._villain_top_card.position.x, deck_right])
	_check("② 卡图可接收鼠标（mouse_filter != IGNORE，否则悬停不了）",
		board._villain_top_card.mouse_filter != Control.MOUSE_FILTER_IGNORE,
		"filter=%d" % board._villain_top_card.mouse_filter)
	_check("② 有卡图时不再显示文字提示（基础模式）", not board._villain_deck_hint.visible,
		"hint=%s" % board._villain_deck_hint.text)

	# ---------------- ②b 用户实测场景：连翻多张牌，顶牌卡图必须一直跟着换 ----------------
	# 用户报告的症状：球卡打出后，顶牌卡图"显示了 3 张后就不再显示了"。
	# 根因：可见区口径当时写死 STORY_VISIBLE = 6，球卡被后续牌挤出那个窗口 → 显示条件失效。
	# 本用例连续推 8 张故事情节牌（球卡仍应落在"一屏 16 张"的窗口内），
	# 每一步都要求卡图可见、且贴图等于当前牌堆顶那张。
	var deck_seq: Array = [1, 2, 4, 6, 8, 9, 10, 11]
	var persist_ok := true
	var persist_detail := ""
	for k in range(deck_seq.size()):
		Game.state["story"].append({"type": "villain", "villain": "redskull",
			"idx": int(deck_seq[k]), "move": 0, "face_down": false})
		Game.state["master_deck"] = [int(deck_seq[k]), 3, 5]
		Events.state_changed.emit()
		await _frames(3)
		var want_tex: Texture2D = load(UiKit.villain_action_image("redskull", int(deck_seq[k])))
		if not board._villain_top_card.visible or board._villain_top_card.texture != want_tex:
			persist_ok = false
			persist_detail = "第 %d 张(idx=%d) visible=%s tex_ok=%s" % [k + 1, int(deck_seq[k]),
				str(board._villain_top_card.visible), str(board._villain_top_card.texture == want_tex)]
			break
	_check("②b 连翻 8 张牌：顶牌卡图一直跟着换、没有提前停掉（球仍在窗口内）", persist_ok, persist_detail)
	_check("②b 此时球仍被判为在可见区（story=%d 张）" % Game.state["story"].size(),
		Game._villain_top_public_now(), "story=%d" % Game.state["story"].size())

	# ---------------- ③ 顶牌换了 → 卡图跟着换 ----------------
	var node_before: Object = board._villain_top_card
	Game.state["master_deck"] = [7, 3, 5]      # 顶牌换成 7
	Events.state_changed.emit()
	await _frames(3)
	var want7: Texture2D = load(UiKit.villain_action_image("redskull", 7))
	_check("③ 顶牌换成 idx=7 → 卡图跟着换（action_08.png）",
		want7 != null and want7 != want3 and board._villain_top_card.texture == want7,
		"tex=%s" % str(board._villain_top_card.texture))
	_check("③ 复用同一个节点（不重建）", board._villain_top_card == node_before, "")

	# ---------------- ④ 悬停放大 / 移开收起 ----------------
	_check("④ 悬停前：放大面板不可见", not board._zoom_panel.visible, "")
	board._villain_top_card.mouse_entered.emit()
	_check("④ 悬停 → 放大面板出现", board._zoom_panel.visible, "")
	_check("④ 放大内容就是这张顶牌（且非空贴图）",
		board._zoom_panel.texture != null and board._zoom_panel.texture == board._villain_top_card.texture, "")
	var zs: Vector2 = board._zoom_panel.size
	_check("④ 放大尺寸按卡面比例（反派行动牌 248×346 = %.3f）" % (248.0 / 346.0),
		zs.y > 0.0 and absf(zs.x / zs.y - 248.0 / 346.0) < 0.02, "size=%s" % str(zs))
	board._villain_top_card.mouse_exited.emit()
	_check("④ 移开 → 放大面板收起（贴图一并清空）",
		not board._zoom_panel.visible and board._zoom_panel.texture == null, "")

	# ---------------- ⑤ 失效条件 ----------------
	_push_orb_out_of_view()
	Events.state_changed.emit()
	await _frames(3)
	_check("⑤ 球被挤出可见区 → 卡图隐藏、贴图清空",
		not board._villain_top_card.visible and board._villain_top_card.texture == null, "")
	var fake: Dictionary = Game.state.duplicate(true)
	fake["villain_top_public"] = true
	fake["villain_top_idx"] = -1
	_check("⑤b public 但没有合法 idx → 不显示卡图（交给文字兜底）",
		board._refresh_villain_top_card(fake) == false, "")
	fake["villain_top_idx"] = 99
	_check("⑤b idx 越界 → 不显示卡图", board._refresh_villain_top_card(fake) == false, "")
	fake["villain_top_idx"] = 1
	fake["mode"] = "s6"
	_check("⑤b 邪恶六人组模式（没有主计划牌堆）→ 不显示卡图",
		board._refresh_villain_top_card(fake) == false, "")
	# ⑤c 放大中失效 → 放大面板一并收起
	_put_orb_in_story()
	Game.state["master_deck"] = [3, 5, 7]
	Events.state_changed.emit()
	await _frames(3)
	board._villain_top_card.mouse_entered.emit()
	_check("⑤c 前置：放大面板已打开", board._zoom_panel.visible, "")
	_push_orb_out_of_view()
	Events.state_changed.emit()
	await _frames(3)
	_check("⑤c 失效时放大面板一并收起（不留残影）", not board._zoom_panel.visible, "")

	# ---------------- ⑥ 联机客户端（只用下发的 idx）----------------
	_put_orb_in_story()
	Game.state["master_deck"] = [5, 9, 1]      # 顶牌 = 行动卡 5
	Net.active = true
	Net.is_host = false
	Net.my_peer = 2
	Net.seats = [
		{"peer": 1, "name": "房主", "hero": "drstrange", "villain": "", "locs": [], "ready": false},
		{"peer": 2, "name": "我", "hero": "cap", "villain": "", "locs": [], "ready": false},
	]
	var vis: Dictionary = Net.visible_state_for("cap")
	_check("⑥ 快照里 master_deck 被裁成空数组（客户端读不到牌堆本体）",
		(vis.get("master_deck", [null]) as Array).is_empty(), str(vis.get("master_deck", "缺字段")))
	_check("⑥ 快照下发了 villain_top_public / villain_top_idx（= 5）",
		bool(vis.get("villain_top_public", false)) and int(vis.get("villain_top_idx", -1)) == 5,
		"%s / %s" % [str(vis.get("villain_top_public", null)), str(vis.get("villain_top_idx", null))])
	Net.rpc_snapshot(vis)      # 模拟主机快照到达客户端
	await _frames(3)
	_check("⑥ 前置：客户端本地算不出顶牌（master_deck 为空 → -1）",
		Game._next_villain_action_from_top() == -1, "idx=%d" % Game._next_villain_action_from_top())
	var want5: Texture2D = load(UiKit.villain_action_image("redskull", 5))
	_check("⑥ 客户端仍画出正确卡图（用 villain_top_idx，没读 master_deck）",
		board._villain_top_card.visible and want5 != null and board._villain_top_card.texture == want5,
		"tex=%s" % str(board._villain_top_card.texture))
	board._villain_top_card.mouse_entered.emit()
	_check("⑥b 客户端悬停也能放大，内容是这张牌",
		board._zoom_panel.visible and board._zoom_panel.texture == want5, "")
	board._villain_top_card.mouse_exited.emit()
	_check("⑥b 客户端移开后收起", not board._zoom_panel.visible, "")

	# ---------------- ⑦ 有卡图时文字不出现；没有卡图才用文字兜底 ----------------
	# 只把 mode 改成 iw 走一遍"无限战争分支"的刷新（文字提示那段就在里面），
	# 不开新局（开新局会覆盖掉 ⑥ 的快照状态）。
	Game.state["mode"] = "iw"
	Events.state_changed.emit()
	await _frames(3)
	_check("⑦ 无限战争分支：有卡图时也不显示文字提示", not board._villain_deck_hint.visible,
		"hint=%s" % board._villain_deck_hint.text)
	# ⑦b 卡图缺失（public 为真、idx 合法，但那张 action_XX.png 不存在）→ 文字兜底
	#    做法：临时把 redskull 的 actions 补到 20 张（前 12 张不动），用 idx=15 → 没有 action_16.png
	var real_actions: Array = DB.villain("redskull")["actions"]
	var padded: Array = real_actions.duplicate()
	while padded.size() < 20:
		padded.append({})
	DB.villains["redskull"]["actions"] = padded
	Game.state["villain_top_idx"] = 15
	Events.state_changed.emit()
	await _frames(3)
	_check("⑦b 卡图缺失（idx=15 没有 action_16.png）→ 卡图隐藏", not board._villain_top_card.visible, "")
	_check("⑦b 卡图缺失时才用文字兜底（且卡图不显示）",
		board._villain_deck_hint.visible and board._villain_deck_hint.text.contains("牌堆顶公开"),
		"hint=%s card_visible=%s" % [board._villain_deck_hint.text, str(board._villain_top_card.visible)])
	DB.villains["redskull"]["actions"] = real_actions   # 还原
	# ⑦c idx 越界（不存在那张牌）→ 卡图与文字都不显示，且不能崩
	Game.state["villain_top_idx"] = 99
	Events.state_changed.emit()
	await _frames(3)
	_check("⑦c idx 越界 → 卡图与文字都不显示（不崩）",
		not board._villain_top_card.visible and not board._villain_deck_hint.visible,
		"hint=%s" % board._villain_deck_hint.text)
	Net.active = false

	if _fail == 0:
		print("=== ORB TOP CARD TEST ALL PASSED ===")
		get_tree().quit(0)
	else:
		print("=== ORB TOP CARD TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)
