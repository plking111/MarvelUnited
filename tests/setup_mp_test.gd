extends Node
## 联机"复用本地 Setup 向导"验证（bug1：界面要和本地一样，不要另做一套）。
##
## 做法：把房间座位 i 映射到本地已有的"顺位 P(i+1) 槽位"，所以英雄页的 P1~P4 彩框/标签、
## 搜索/排序/扩展分组/英雄面板 tooltip 全部原样可用；这里断言这条映射与阶段推进真的通了。

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

## 统计某个卡片上挂了几个 "_mp_tag" 标注（bug3 回归用）
func _count_mp_tags(box: Control) -> int:
	var n := 0
	for c in box.get_children():
		if String(c.name).begins_with("_mp_tag"):
			n += 1
	return n

func _tag_text(box: Control) -> String:
	for c in box.get_children():
		if String(c.name).begins_with("_mp_tag") and c is Label:
			return String((c as Label).text) if (c as Label).visible else ""
	return ""

## 把一个节点下所有 Label 的文字拼起来（弹窗断言用）
func _all_label_text(root: Node) -> String:
	if root == null:
		return ""
	var out := ""
	for c in root.get_children():
		if c is Label:
			out += String((c as Label).text) + " | "
		out += _all_label_text(c)
	return out

func _ready() -> void:
	Game.autopilot = true
	# 伪装联机：房主 = P1 = wasp，队友 = P2 = vision
	Net.active = true
	Net.is_host = true
	Net.my_peer = 1
	Net.room = {"name": "测试房", "password": "", "max": 2}
	Net.seats = [
		{"peer": 1, "name": "房主", "hero": "wasp", "villain": "", "locs": [], "ready": false},
		{"peer": 2, "name": "小号", "hero": "vision", "villain": "", "locs": [], "ready": false},
	]
	Net.phase = "mode"
	Net.mode_cfg = {}

	var st: Control = load("res://src/ui/Setup.tscn").instantiate()
	add_child(st)
	await _frames(4)

	# ---- 用的是本地那套界面（四个步骤页 / 英雄页要素都在）----
	_check("复用本地 Setup：四个步骤页都在（模式/英雄/反派/地点）",
		st._step_pages.size() == 4 and st._step_pages.has(1) and st._step_pages.has(4),
		"步骤页=%s" % str(st._step_pages.keys()))
	_check("复用本地 Setup：英雄卡按钮已生成（57 位英雄）", st._hero_buttons.size() == 57,
		"按钮数=%d" % st._hero_buttons.size())
	_check("复用本地 Setup：地点扩展行已生成", st._loc_rows.size() >= 5, "行数=%d" % st._loc_rows.size())
	# 大厅本身不再自建选择页，只负责"房间"；阶段一变就交棒给本地 Setup
	var lobby: Control = load("res://src/ui/Lobby.tscn").instantiate()
	add_child(lobby)
	await _frames(2)
	_check("Lobby 不再自建选择页（没有 _build_hero/_build_mode/_build_villain/_build_location）",
		not lobby.has_method("_build_hero") and not lobby.has_method("_build_mode")
		and not lobby.has_method("_build_villain") and not lobby.has_method("_build_location"), "")
	_check("Lobby 阶段一变就交棒给本地 Setup", lobby._should_handoff("mode") and not lobby._should_handoff("lobby"), "")
	lobby.queue_free()
	await _frames(2)

	# ---- 座位 i → 顺位 P(i+1)：本地 P 槽位镜像房间座位 ----
	_check("座位 i → 顺位 P(i+1)：英雄页 P1/P2 槽位镜像房间座位",
		String(st._hero_slots[0]) == "wasp" and String(st._hero_slots[1]) == "vision",
		"slots=%s" % str(st._hero_slots))
	_check("英雄数 = 房间人数上限", int(st._hero_count) == 2, "hero_count=%d" % int(st._hero_count))

	# ---- 联机：去掉"加减人数"两个按钮（人数由房间决定）；本地要保留 ----
	_check("联机英雄页：加减人数按钮已隐藏",
		not st._count_minus.visible and not st._count_plus.visible,
		"minus=%s plus=%s" % [str(st._count_minus.visible), str(st._count_plus.visible)])
	_check("联机英雄页：人数提示写明是房间人数",
		String(st._hero_count_label.text).contains("房间"), String(st._hero_count_label.text))

	# ---- 阶段 → 步骤页 ----
	st._mp_on_phase("hero")
	await _frames(2)
	_check("阶段 hero → 第 2 步（英雄页）并可见", st._step == 2 and st._step_pages[2].visible, "step=%d" % st._step)
	st._mp_on_phase("villain")
	await _frames(2)
	_check("阶段 villain → 第 3 步（反派页）", st._step == 3 and st._step_pages[3].visible, "step=%d" % st._step)
	st._mp_on_phase("location")
	await _frames(2)
	_check("阶段 location → 第 4 步（地点页），按钮变成「开始游戏！」",
		st._step == 4 and String(st._nav_next.text).contains("开始游戏"), st._nav_next.text)

	# ---- 只有房主能翻页 ----
	Net.is_host = false
	st._mp_on_phase("hero")
	await _frames(2)
	_check("非房主：『确定』被禁用（不能自己翻页）", st._nav_next.disabled, "")
	_check("非房主：没有返回按钮", not st._nav_back.visible, "")
	Net.is_host = true

	# ---- 点击英雄/反派/地点 = 提交给 Net，再由广播刷回界面 ----
	Net.phase = "hero"
	st._mp_on_phase("hero")
	await _frames(2)
	st._on_hero_toggle("hulk")          # 房主点 hulk
	await _frames(2)
	_check("房主点英雄 → 写进自己顺位（P1=hulk），界面同步刷新",
		String(Net.seats[0]["hero"]) == "hulk" and String(st._hero_slots[0]) == "hulk",
		"seats=%s slots=%s" % [str(Net.seats[0]["hero"]), str(st._hero_slots)])
	st._on_hero_toggle("hulk")          # 再点一次 = 取消
	await _frames(2)
	_check("再点同一个英雄 = 取消", String(Net.seats[0]["hero"]) == "", str(Net.seats[0]["hero"]))
	# 已被人选的英雄不能选（vision 是 P2 的）
	st._on_hero_toggle("vision")
	await _frames(2)
	_check("别人已选的英雄选不了", String(Net.seats[0]["hero"]) == "", str(Net.seats[0]["hero"]))

	Net.phase = "villain"
	st._mp_on_phase("villain")
	await _frames(2)
	st._on_villain_selected("redskull")
	await _frames(2)
	_check("点反派 → 写进自己的选择并显示为选中",
		String(Net.seats[0]["villain"]) == "redskull" and String(st._selected_villain) == "redskull", "")
	Net.seats[1]["villain"] = "ultron"     # 队友选了 ultron
	st._mp_sync()
	await _frames(2)
	_check("队友选的反派在本地也有标注",
		st._villain_buttons["ultron"].get_node_or_null("_mp_tag") != null, "")

	# ---- bug3：反复刷新 / 队友换选，标签不能翻倍或残留 ----
	for k in range(4):
		st._mp_sync()
	await _frames(2)
	_check("反复刷新后选项上只有 1 个标注（不翻倍）",
		_count_mp_tags(st._villain_buttons["ultron"]) == 1,
		"标注数=%d" % _count_mp_tags(st._villain_buttons["ultron"]))
	Net.seats[1]["villain"] = "redskull"   # 队友改选
	st._mp_sync()
	await _frames(2)
	_check("队友改选后：旧选项上的标注不再显示（隐藏或移除，且不重复）",
		_tag_text(st._villain_buttons["ultron"]) == "" and _count_mp_tags(st._villain_buttons["ultron"]) <= 1,
		"ultron 标签='%s' 节点数=%d" % [_tag_text(st._villain_buttons["ultron"]), _count_mp_tags(st._villain_buttons["ultron"])])
	_check("队友改选后：新选项有标注且只有 1 个",
		_count_mp_tags(st._villain_buttons["redskull"]) == 1,
		"redskull 标注数=%d" % _count_mp_tags(st._villain_buttons["redskull"]))

	# ---- bug2：房主一选模式就同步出去，客户端能看到房主选的 ----
	Net.mode_cfg = {}
	st._on_mode_selected(1)                # 房主选「基础模式」
	await _frames(2)
	_check("房主选模式 → 立刻写进 Net.mode_cfg 广播",
		String(Net.mode_cfg.get("challenge", "")) == "none" and String(Net.mode_cfg.get("mode", "")) == "base",
		str(Net.mode_cfg))
	# 模拟客户端：非房主本地同步房主的选择
	Net.is_host = false
	st._selected_mode_id = 0
	st._mp_sync()
	await _frames(2)
	_check("客户端能看到房主选的模式（高亮/选中同步）", int(st._selected_mode_id) == 1,
		"selected_mode_id=%d" % int(st._selected_mode_id))
	Net.is_host = true

	# ---- bug：随机选按钮只能作用于"个人"（联机时不能替别人选）----
	Net.phase = "hero"
	st._mp_on_phase("hero")
	await _frames(2)
	var other_before := String(Net.seats[1]["hero"])
	st._on_hero_random()
	await _frames(2)
	_check("随机选英雄只落在我自己的顺位（P1）",
		String(Net.seats[0]["hero"]) != "" and String(st._hero_slots[0]) == String(Net.seats[0]["hero"]),
		"P1=%s slots=%s" % [String(Net.seats[0]["hero"]), str(st._hero_slots)])
	_check("随机选英雄不会动别人的选择", String(Net.seats[1]["hero"]) == other_before,
		"P2=%s（原 %s）" % [String(Net.seats[1]["hero"]), other_before])
	_check("随机选英雄不会顺带把其他空槽填满", String(st._hero_slots[1]) == other_before,
		"slots=%s" % str(st._hero_slots))

	Net.phase = "villain"
	st._mp_on_phase("villain")
	await _frames(2)
	var v_other := String(Net.seats[1].get("villain", ""))
	st._on_villain_random()
	await _frames(2)
	_check("随机选反派只落在我自己身上",
		String(Net.seats[0]["villain"]) != "" and String(Net.seats[1].get("villain", "")) == v_other,
		"P1=%s P2=%s" % [String(Net.seats[0]["villain"]), String(Net.seats[1].get("villain", ""))])

	Net.phase = "location"
	st._mp_on_phase("location")
	await _frames(2)
	var l_other: Array = (Net.seats[1].get("locs", []) as Array).duplicate()
	st._on_loc_random()
	await _frames(2)
	_check("随机选地点扩展只勾在我自己身上",
		(Net.seats[0]["locs"] as Array).size() >= 1 and str(Net.seats[1].get("locs", [])) == str(l_other),
		"P1=%s P2=%s" % [str(Net.seats[0]["locs"]), str(Net.seats[1].get("locs", []))])

	Net.phase = "location"
	st._mp_on_phase("location")
	await _frames(2)
	Net.seats[0]["locs"] = []       # 先清空，避免"随机选地点"那步留下的勾选把这次 toggle 变成取消
	st._mp_sync()
	await _frames(2)
	st._toggle_expansion(true, "瓦坎达")
	await _frames(2)
	_check("勾选地点扩展 → 写进自己的选择", (Net.seats[0]["locs"] as Array).has("瓦坎达"),
		str(Net.seats[0]["locs"]))
	Net.seats[1]["locs"] = ["阿斯加德"]
	st._mp_sync()
	await _frames(2)
	var row: Node = st._loc_rows["阿斯加德"].get_parent()
	_check("队友勾的扩展在本地也有标注", row.get_node_or_null("_mp_tag") != null, "")

	# ---- 回归：房主推进阶段必须真的 emit phase_changed ----
	# （曾经的 bug：_push_lobby 只 rpc 给客户端，房主本机不 emit → 房主点"开始游戏"没反应，
	#   而客户端却跳进了模式选择页）
	var fired := {"v": false}
	Net.phase_changed.connect(func(_p: String) -> void: fired["v"] = true)
	Net.phase = "lobby"
	Net.set_phase("mode")
	await _frames(2)
	_check("房主 set_phase 会让房主自己的界面也收到阶段变化（不再只有客户端跳页）",
		bool(fired["v"]) and Net.phase == "mode", "phase=%s fired=%s" % [Net.phase, str(fired["v"])])
	fired["v"] = false
	Net.set_phase("mode")      # 同一个阶段重复设置：不该再触发（避免重复跳场景）
	await _frames(2)
	_check("重复设置同一阶段不会重复触发", not bool(fired["v"]), "")

	# ---- 房主推进阶段：真的改了 Net.phase（所有端会跟着翻页）----
	st._mp_on_phase("mode")
	await _frames(2)
	st._selected_mode_id = 1
	st._mode = "base"
	st._selected_challenge = "none"
	st._mp_next()
	await _frames(2)
	_check("房主点『确定』→ 广播到 hero 阶段", Net.phase == "hero", Net.phase)
	_check("模式配置随之下发", String(Net.mode_cfg.get("mode", "")) == "base", str(Net.mode_cfg))

	# ---- 回归：别人回合里行动用尽时，主机也要能自动结束回合（不需要手动点"结束回合"）----
	Net.phase = "playing"
	Net.is_host = true
	Net.my_peer = 1
	Game.setup("redskull", ["wasp", "vision"], "none", "base")
	Game.state["current_hero"] = Game.state["hero_ids"].find("vision")   # 当前是"别人"的回合
	Game.state["phase"] = "hero_actions"
	Game.state["action_symbols"] = []
	Game.state["effect_available"] = false
	Game.state["effect_used"] = true
	for hid2 in Game.state["hero_ids"]:
		for tk in ["move", "attack", "heroic", "wild"]:
			Game.state["heroes"][hid2]["tokens"][tk] = 0
	_check("测试前：主机不是当前行动者（is_my_turn=false）", not Net.is_my_turn(), "")
	await Game._maybe_auto_end_turn()
	await _frames(3)
	_check("别人回合行动用尽 → 主机自动结束回合（不再需要手动点）",
		String(Game.state["phase"]) != "hero_actions", "phase=%s" % String(Game.state["phase"]))

	# ---- 回归：有人没选英雄时，房主不能进下一步，要弹窗点名 ----
	Net.phase = "hero"
	st._mp_on_phase("hero")
	Net.seats[1]["hero"] = ""            # 队友没选
	st._mp_sync()
	await _frames(2)
	st._mp_next()
	await _frames(3)
	_check("有人没选英雄 → 房主点下一步不生效（阶段没变）", Net.phase == "hero", "phase=%s" % Net.phase)
	_check("有人没选英雄 → 弹窗出现并点名",
		Net._modal_layer != null and Net._modal_layer.visible and _all_label_text(Net._modal_layer).contains("未选择英雄"),
		_all_label_text(Net._modal_layer))
	Net.hide_modal()
	Net.seats[1]["hero"] = "vision"      # 补上
	st._mp_sync()
	await _frames(2)
	st._mp_next()
	await _frames(3)
	_check("都选完后房主点下一步生效（进入反派阶段）", Net.phase == "villain", "phase=%s" % Net.phase)

	# ---- bug2：联机下"单人模式"与"人数不够的叛徒模式"必须黑白且选不了 ----
	_check("联机：神盾局单人模式不可选（黑白）", not st._mode_selectable(5), "")
	_check("联机：指挥官单人模式不可选（黑白）", not st._mode_selectable(6), "")
	_check("联机：2 人时叛徒模式不可选（黑白）", not st._mode_selectable(10), "player_count=%d" % Net.player_count())
	_check("联机：基础/中等/困难/英雄挑战/濒危地点仍可选",
		st._mode_selectable(1) and st._mode_selectable(2) and st._mode_selectable(3)
		and st._mode_selectable(4) and st._mode_selectable(9), "")
	Net.room["max"] = 3
	Net.seats.append({"peer": 97, "name": "三号", "hero": "hulk", "villain": "", "locs": [], "ready": false})
	st._mp_sync()
	await _frames(2)
	_check("联机：3 人时叛徒模式变为可选", st._mode_selectable(10), "player_count=%d" % Net.player_count())
	# 黑白对照：先把"当前选中"清空（选中态下只有选中的那个是彩色，其他都灰，没法比较）
	st._selected_mode_id = 0
	st._update_mode_highlight()
	await _frames(2)
	_check("联机：3 人时叛徒模式不再是黑白",
		(st._mode_buttons[10].get_child(0) as TextureRect).material == null,
		"material=%s" % str((st._mode_buttons[10].get_child(0) as TextureRect).material))
	_check("联机：单人模式即使人数够也仍是黑白（不可选）",
		not st._mode_selectable(5) and (st._mode_buttons[5].get_child(0) as TextureRect).material != null, "")
	Net.seats.resize(2)
	Net.room["max"] = 2
	st._mp_sync()
	await _frames(2)
	# 叛徒模式的身份不能下发给别人
	Game.state["loyalty"] = {"wasp": "traitor", "vision": "loyal"}
	Game.state["traitor_hid"] = "wasp"
	var vis_other: Dictionary = Net.visible_state_for("vision")
	_check("叛徒身份不下发：别人拿到的快照里看不到谁是叛徒",
		(vis_other["loyalty"] as Dictionary).size() == 1 and String(vis_other["loyalty"].get("vision", "")) == "loyal"
		and String(vis_other.get("traitor_hid", "")) == "", str(vis_other["loyalty"]))
	var vis_me: Dictionary = Net.visible_state_for("wasp")
	_check("叛徒本人能看到自己的身份",
		String(vis_me["loyalty"].get("wasp", "")) == "traitor" and String(vis_me.get("traitor_hid", "")) == "wasp",
		str(vis_me["loyalty"]))

	# ---- 叛徒模式：开局每人私下看到自己的身份 ----
	Net.active = true
	Net.is_host = true
	Net.my_peer = 1
	Net.room = {"name": "t", "password": "", "max": 2}
	Net.seats = [
		{"peer": 1, "name": "房主", "hero": "wasp", "villain": "", "locs": [], "ready": false},
		{"peer": 2, "name": "小号", "hero": "vision", "villain": "", "locs": [], "ready": false},
	]
	Game.state["challenge"] = "traitor"
	Game.state["loyalty"] = {"wasp": "traitor", "vision": "loyal"}
	Net._identities_sent = false
	Net.send_identities()
	await _frames(3)
	_check("叛徒模式开局：房主看到自己的身份弹窗", Net._modal_layer != null and Net._modal_layer.visible, "")
	_check("房主身份正确显示为叛乱者", _all_label_text(Net._modal_layer).contains("叛乱者"),
		_all_label_text(Net._modal_layer))
	_check("身份弹窗带「知道了」按钮", _find_button(Net._modal_layer, "知道了") != null, "")
	Net.hide_modal()
	_check("另一个玩家的身份文案是忠诚者（各自只看到自己）",
		Net.identity_text("vision").contains("忠诚者"), Net.identity_text("vision"))
	_check("本人拿到的快照里只有自己的身份（别人的看不到）",
		(Net.visible_state_for("wasp")["loyalty"] as Dictionary).size() == 1
		and String(Net.visible_state_for("wasp")["loyalty"].get("wasp", "")) == "traitor", "")
	Net._identities_sent = true
	Net.send_identities()
	_check("身份只发一次（重复调用不再弹）", not Net._modal_layer.visible, "")

	# ---- bug1：地点勾选不能"自己反转"（渲染时必须静默设置，否则震荡成全没选）----
	Net.active = true
	Net.is_host = true
	Net.my_peer = 1
	Net.room = {"name": "t", "password": "", "max": 2}
	Net.seats = [
		{"peer": 1, "name": "房主", "hero": "wasp", "villain": "redskull", "locs": ["瓦坎达"], "ready": false},
		{"peer": 2, "name": "小号", "hero": "vision", "villain": "ultron", "locs": ["阿斯加德"], "ready": false},
	]
	Net.phase = "location"
	st._mp_on_phase("location")
	await _frames(2)
	for k2 in range(4):
		st._mp_sync()
		await _frames(1)
	_check("地点勾选稳定：多次渲染后我的勾选仍是「瓦坎达」",
		str(Net.seats[0]["locs"]) == str(["瓦坎达"]), str(Net.seats[0]["locs"]))
	_check("地点勾选稳定：队友的勾选没被改动",
		str(Net.seats[1]["locs"]) == str(["阿斯加德"]), str(Net.seats[1]["locs"]))
	_check("都勾了 → 房主下一步不再提示有人未选", st._mp_missing("location").is_empty(),
		str(st._mp_missing("location")))
	# 全选：只给自己加，不动队友
	st._on_loc_select_all()
	await _frames(2)
	_check("联机「全选」真的提交给了 Net（只作用于自己）",
		(Net.seats[0]["locs"] as Array).size() > 1 and str(Net.seats[1]["locs"]) == str(["阿斯加德"]),
		"P1=%s P2=%s" % [str(Net.seats[0]["locs"]), str(Net.seats[1]["locs"])])

	# ---- bug2：玩家退出后，房主的手牌区要能切到他（否则该回合卡住）----
	var fired2 := {"v": false}
	Events.state_changed.connect(func() -> void: fired2["v"] = true)
	Net.seats[1]["disconnected"] = false
	Net.seats[1]["peer"] = 2
	Net.phase = "playing"
	Game.state["current_hero"] = Game.state["hero_ids"].find("vision")
	Net._on_peer_disconnected(2)
	await _frames(3)
	var cont := _find_button(Net._modal_layer, "继续游戏")
	_check("玩家退出时房主能选「继续游戏」", cont != null, "")
	if cont != null:
		cont.pressed.emit()
	await _frames(3)
	_check("选继续后座位标记为房主代管", bool(Net.seats[1].get("disconnected", false)), str(Net.seats[1]))
	_check("并且广播了状态变化（房主手牌区才能切到该英雄，不会卡住）", bool(fired2["v"]), "")

	# ---- 无限战争：房主排前 3 局顺序 → 广播；客户端只读跟随 ----
	Net.active = true
	Net.is_host = true
	Net.my_peer = 1
	Net.room = {"name": "t", "password": "", "max": 2}
	Net.seats = [
		{"peer": 1, "name": "房主", "hero": "wasp", "villain": "", "locs": [], "ready": false},
		{"peer": 2, "name": "小号", "hero": "vision", "villain": "", "locs": [], "ready": false},
	]
	Net.mode_cfg = {"mode": "iw", "challenge": "none", "expansions": []}
	Net.phase = "villain"
	st._mode = "iw"
	st._selected_challenge = "none"
	st._campaign_slots = ["", "", ""]
	Net.seats[0]["cs"] = []
	Net.seats[1]["cs"] = []
	st._mp_on_phase("villain")
	await _frames(2)
	st._on_villain_selected("proxima")
	st._on_villain_selected("cull")
	await _frames(2)
	_check("无限战争：点反派 → 填进自己最低的空格（红→橙→绿）",
		str(Net.my_campaign_slots()) == str(["proxima", "cull", ""]), str(Net.my_campaign_slots()))
	st._on_villain_selected("cull")
	await _frames(2)
	_check("无限战争：再点已排的反派 = 取消那一格",
		str(Net.my_campaign_slots()) == str(["proxima", "", ""]), str(Net.my_campaign_slots()))
	Net.seats[0]["cs"] = ["proxima", "cull", "ebony"]
	Net.seats[1]["cs"] = ["ultron", "cull", ""]
	_check("无限战争：第1局池子 = 所有人在第1格选的反派",
		str(Net.campaign_pool(0)) == str(["proxima", "ultron"]), str(Net.campaign_pool(0)))
	_check("无限战争：第2局池子去重", str(Net.campaign_pool(1)) == str(["cull"]), str(Net.campaign_pool(1)))
	_check("无限战争：第3局池子", str(Net.campaign_pool(2)) == str(["ebony"]), str(Net.campaign_pool(2)))
	st._mp_sync()
	await _frames(2)
	_check("无限战争：别人的选择在卡片左上角标 Px",
		_tag_text(st._villain_buttons["ultron"]).contains("P2"), _tag_text(st._villain_buttons["ultron"]))
	Net.hide_modal()
	# 客户端侧：跟随房主的顺序（只读）
	Net.is_host = false
	st._campaign_slots = ["", "", ""]
	st._mp_sync()
	await _frames(2)
	_check("无限战争：客户端只读显示房主排的顺序",
		str((st._campaign_slots as Array).slice(0, 2)) == str(["proxima", "cull"]), str(st._campaign_slots))
	Net.is_host = true
	st._mode = "base"
	Net.mode_cfg = {}

	# ---- 回归：无限战争模式下"地点同步"不能被跳过（曾因提前 return 导致"选了却显示未选"）----
	Net.active = true
	Net.is_host = true
	Net.my_peer = 1
	Net.room = {"name": "t", "password": "", "max": 2}
	Net.seats = [
		{"peer": 1, "name": "房主", "hero": "wasp", "villain": "", "locs": ["瓦坎达"], "ready": false},
		{"peer": 2, "name": "小号", "hero": "vision", "villain": "", "locs": ["阿斯加德"], "ready": false},
	]
	Net.mode_cfg = {"mode": "iw", "challenge": "none", "expansions": []}
	Net.seats[0]["cs"] = ["proxima", "cull", "ebony"]
	Net.phase = "location"
	st._mode = "iw"
	st._mp_on_phase("location")
	await _frames(2)
	_check("无限战争：地点勾选同步没被跳过（我的勾选同步进来了）",
		str(st._selected_expansions) == str(["瓦坎达"]), str(st._selected_expansions))
	_check("无限战争：人人都有勾选 → 不再提示有人未选地点",
		st._mp_missing("location").is_empty(), str(st._mp_missing("location")))
	_check("无限战争：我的三格（红/橙/绿）同步到界面",
		str(st._campaign_slots) == str(["proxima", "cull", "ebony"]), str(st._campaign_slots))
	st._mode = "base"
	Net.seats[0]["cs"] = []
	Net.seats[1]["cs"] = []
	Net.mode_cfg = {}

	# ---- 无限战争 + 首字母排序：必须显示"当前全部反派"（以前只显示 7 个）----
	st._mode = "iw"
	st._sort_mode = "alpha"
	if st._villain_search != null:
		st._villain_search.text = ""
	st._render_villains()
	await _frames(2)
	_check("无限战争+首字母排序：显示全部反派（与 DB 一致）",
		st._villain_buttons.size() == DB.villains.size(), "只显示了 %d 个" % st._villain_buttons.size())
	_check("无限战争+首字母：灭霸在（决战要用）", st._villain_buttons.has("thanos"), "")
	_check("无限战争+首字母：其他扩展的反派也在（如洛基/金钱豹）",
		st._villain_buttons.has("loki") and st._villain_buttons.has("kilmonger"), "")
	st._mode = "base"

	# ---- 真实点击路径：勾选框发出的 toggled 必须真的写进 Net（模拟玩家点鼠标）----
	Net.active = true
	Net.is_host = true
	Net.my_peer = 1
	Net.room = {"name": "t", "password": "", "max": 2}
	Net.seats = [
		{"peer": 1, "name": "房主", "hero": "wasp", "villain": "", "locs": [], "ready": false},
		{"peer": 2, "name": "小号", "hero": "vision", "villain": "", "locs": [], "ready": false},
	]
	Net.mode_cfg = {"mode": "base", "challenge": "none", "expansions": []}
	Net.phase = "location"
	st._mode = "base"
	st._sort_mode = "alpha"
	st._mp_on_phase("location")
	await _frames(2)
	var cb_wk: CheckButton = st._loc_rows.get("瓦坎达", null)
	_check("地点页有可点的勾选框", cb_wk != null, "行数=%d" % st._loc_rows.size())
	if cb_wk != null:
		cb_wk.toggled.emit(true)          # ← 和玩家点鼠标完全一样的信号
		await _frames(3)
		_check("点勾选框后：真的写进了 Net（房主自己这一份）",
			(Net.seats[0]["locs"] as Array).has("瓦坎达"), str(Net.seats[0]["locs"]))
		_check("点勾选框后：界面同步显示已勾选",
			(st._selected_expansions as Array).has("瓦坎达"), str(st._selected_expansions))
		_check("点勾选框后：只报没勾的那个人（主机自己这份已生效）",
			st._mp_missing("location").size() == 1 and String(st._mp_missing("location")[0]).contains("P2"),
			str(st._mp_missing("location")))

	# 清理
	st.queue_free()
	await _frames(2)
	# 本地模式：加减人数按钮必须还在（不然本地没法选人数）
	Net.active = false
	var st_local: Control = load("res://src/ui/Setup.tscn").instantiate()
	add_child(st_local)
	await _frames(4)
	_check("本地英雄页：加减人数按钮保留",
		st_local._count_minus.visible and st_local._count_plus.visible,
		"minus=%s plus=%s" % [str(st_local._count_minus.visible), str(st_local._count_plus.visible)])
	st_local.queue_free()
	await _frames(2)
	Net.seats = []
	Net.active = false
	Net.is_host = true
	Net.my_peer = 1
	Net.phase = "lobby"
	Net.mode_cfg = {}

	if _fail == 0:
		print("=== SETUP MP TEST ALL PASSED ===")
		get_tree().quit(0)
	else:
		print("=== SETUP MP TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)

## 按文字找按钮（弹窗断言用）
func _find_button(root: Node, text: String) -> Button:
	if root == null:
		return null
	for c in root.get_children():
		if c is Button and String((c as Button).text).contains(text):
			return c
		var r := _find_button(c, text)
		if r != null:
			return r
	return null
