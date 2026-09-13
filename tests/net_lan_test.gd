extends Node
## 局域网联机端到端测试（需要两个进程）。
##   & godot --headless --path MarvelUnitedGame res://tests/net_lan_test.tscn -- host
##   & godot --headless --path MarvelUnitedGame res://tests/net_lan_test.tscn -- client
## 不带参数运行时直接跳过（保持全量回归为绿），真正的跑法见 devtools/run_net_test.ps1。
##
## 覆盖：建房 → 进房 → 自由挑座位号（顺位）→ 模式/英雄/反派/地点四阶段选择同步
##      → 开局聚合（英雄按顺位、反派从勾选里随机抽、地点随机取 6）→ 手牌隐私裁剪。

var _fail := 0
var _role := "skip"
var _start_cfg: Dictionary = {}
var _started := false

func _check(n: String, ok: bool, d: String = "") -> void:
	if ok:
		print("PASS: " + n)
	else:
		_fail += 1
		print("FAIL: " + n + " — " + d)

func _ready() -> void:
	# 测试进程：别让 start_play 真的切到棋盘（否则对局会跑起来并等弹窗，测试卡死）
	Net.auto_board_handoff = false
	var ua := OS.get_cmdline_user_args()
	_role = String(ua[0]) if ua.size() > 0 else "skip"
	if _role == "skip":
		print("=== NET LAN TEST SKIPPED（需要双进程，见 devtools/run_net_test.ps1）===")
		get_tree().quit(0)
		return
	Game.autopilot = true
	Net.start_play.connect(func(cfg: Dictionary) -> void:
		_start_cfg = cfg
		_started = true)
	if _role == "host":
		await _run_host()
	else:
		await _run_client()
	if _fail == 0:
		print("=== NET LAN TEST [%s] PASSED ===" % _role)
		get_tree().quit(0)
	else:
		print("=== NET LAN TEST [%s] FAILED (%d) ===" % [_role, _fail])
		get_tree().quit(1)

## 等条件成立（每帧查一次，最多 sec 秒）
func _wait_until(cond: Callable, sec: float, what: String) -> bool:
	var t := 0.0
	while t < sec:
		if bool(cond.call()):
			return true
		await get_tree().process_frame
		t += get_process_delta_time()
	return false

func _all_label_text(root: Node) -> String:
	if root == null:
		return ""
	var out := ""
	for c in root.get_children():
		if c is Label:
			out += String((c as Label).text) + " | "
		out += _all_label_text(c)
	return out

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

# ================================================================ 主机

func _run_host() -> void:
	_check("主机建房成功", Net.host_room("测试房", "pw123", 4, "房主"), Net.last_error)
	_check("房主自动坐 0 号位（顺位=1）", Net.my_seat() == 0, "seat=%d" % Net.my_seat())
	# 客户端用错误密码应被拒（用同一台机的第二个 peer 不好模拟，这里只验证主机侧密码字段）
	_check("房间信息含密码标记", String(Net.room.get("password", "")) == "pw123", "")

	var joined: bool = await _wait_until(func() -> bool: return Net.player_count() >= 2, 20.0, "客户端加入")
	_check("客户端已加入（人数=2）", joined, "player_count=%d" % Net.player_count())
	if not joined:
		return
	_check("客户端落座为 1 号位（顺位=2）",
		Net.seats.size() > 1 and Net.seats[1] != null and String(Net.seats[1]["name"]) == "小号",
		str(Net.seats))

	# 模式：房主决定
	Net.set_phase("mode")
	Net.set_mode("base", "none", [])
	Net.set_phase("hero")
	# 英雄：各自选自己的；房主选 wasp
	Net.request_pick("hero", "wasp")
	var got_hero: bool = await _wait_until(func() -> bool:
		return Net.seats.size() > 1 and Net.seats[1] != null and String(Net.seats[1]["hero"]) != "", 15.0, "客户端选英雄")
	_check("客户端选的英雄同步到主机（vision）",
		got_hero and String(Net.seats[1]["hero"]) == "vision", str(Net.seats[1]) if Net.seats.size() > 1 else "")
	# 英雄不可重复：房主再选客户端已选的 vision 应无效
	Net.request_pick("hero", "vision")
	_check("英雄不可重复选（选别人已选的无效）", String(Net.seats[0]["hero"]) == "wasp", String(Net.seats[0]["hero"]))

	# 反派：每人最多 1 个（再点同一个 = 取消）
	Net.set_phase("villain")
	Net.request_pick("villain", "redskull")
	Net.request_pick("villain", "ultron")
	_check("反派每人最多勾 1 个（后选的顶掉先选的）", String(Net.seats[0]["villain"]) == "ultron", String(Net.seats[0]["villain"]))
	Net.request_pick("villain", "ultron")
	_check("再点同一个 = 取消勾选", String(Net.seats[0]["villain"]) == "", String(Net.seats[0]["villain"]))
	Net.request_pick("villain", "redskull")
	var got_v: bool = await _wait_until(func() -> bool:
		return Net.seats.size() > 1 and String(Net.seats[1].get("villain", "")) != "", 15.0, "客户端选反派")
	_check("客户端选的反派同步到主机（ultron）",
		got_v and String(Net.seats[1]["villain"]) == "ultron", str(Net.seats[1]) if Net.seats.size() > 1 else "")

	# 地点：各自勾若干
	Net.set_phase("location")
	Net.request_pick("location", "基础盒")
	Net.request_pick("location", "瓦坎达")
	var got_l: bool = await _wait_until(func() -> bool:
		return Net.seats.size() > 1 and (Net.seats[1].get("locs", []) as Array).size() > 0, 15.0, "客户端选地点")
	_check("客户端勾的地点扩展同步到主机", got_l and (Net.seats[1]["locs"] as Array).has("阿斯加德"),
		str(Net.seats[1]) if Net.seats.size() > 1 else "")
	_check("可以开始（≥2 人且人人有英雄）", Net.can_start(), "")

	# 手牌隐私：裁剪后的状态里，别人手牌为空但保留张数
	Game.setup("redskull", ["wasp", "vision"], "none", "base")
	var vis: Dictionary = Net.visible_state_for("wasp")
	var vh: Dictionary = vis["heroes"]["vision"]
	var wh: Dictionary = vis["heroes"]["wasp"]
	_check("隐私：给 wasp 的快照里 vision 手牌为空", (vh["hand"] as Array).is_empty(), str(vh["hand"]))
	_check("隐私：给 wasp 的快照里 vision 保留手牌张数", int(vh.get("hand_count", -1)) >= 0, "")
	_check("隐私：自己的手牌照常可见", (wh["hand"] as Array).size() == (Game.state["heroes"]["wasp"]["hand"] as Array).size(), "")
	_check("隐私：裁剪后的快照仍是合法字典（可回读）", JSON.parse_string(JSON.stringify(vis)) != null, "")

	# 开局聚合
	Net.start_game()
	_check("开局事件已发出", _started, "")
	if _started:
		var heroes: Array = _start_cfg["hero_ids"]
		_check("英雄按顺位排列（P1=wasp, P2=vision）", str(heroes) == str(["wasp", "vision"]), str(heroes))
		_check("反派从勾选里随机抽出（redskull / ultron 之一）",
			["redskull", "ultron"].has(String(_start_cfg["villain"])), String(_start_cfg["villain"]))
		var locs: Array = _start_cfg["locations"]
		_check("地点取 6 张", locs.size() == 6, str(locs))
		var pool := ["基础盒", "瓦坎达", "阿斯加德"]
		var bad: Array = []
		var seen: Array = []
		var dup := false
		for l in locs:
			var ex: String = String(DB.location(String(l)).get("expansion", "基础盒"))
			if not pool.has(ex):
				bad.append(String(l))
			if seen.has(String(l)):
				dup = true
			seen.append(String(l))
		_check("地点只在大家勾的扩展里抽（基础盒/瓦坎达/阿斯加德）", bad.is_empty(), "越界=%s 全部=%s" % [str(bad), str(locs)])
		_check("地点不重复", not dup, str(locs))
		_check("地点 id 都合法", locs.all(func(l): return DB.locations.has(String(l))), str(locs))
		_check("模式配置随开局下发", String(_start_cfg["mode"]) == "base" and String(_start_cfg["challenge"]) == "none", str(_start_cfg))
	# 关键：start_game 之后要留时间让 reliable RPC 送达客户端，否则主机进程一退包就丢了
	# （客户端那两条断言会变成"没收到开始游戏/没收到快照"的假失败）
	await get_tree().create_timer(2.0).timeout

	# ---------- bug3：客户端进程退出 → 房主要弹窗询问「继续游戏 / 退出游戏」----------
	var modal_up: bool = await _wait_until(func() -> bool:
		return Net._modal_layer != null and Net._modal_layer.visible, 25.0, "退出弹窗")
	_check("客户端退出时房主弹出提示", modal_up, "")
	if modal_up:
		var mtxt := _all_label_text(Net._modal_layer)
		_check("弹窗文字含玩家名与「退出游戏」", mtxt.contains("退出游戏") and mtxt.contains("小号"), mtxt)
		var cbtn := _find_button(Net._modal_layer, "继续游戏")
		_check("弹窗有「继续游戏」按钮", cbtn != null, "")
		_check("弹窗有「退出游戏」按钮", _find_button(Net._modal_layer, "退出游戏") != null, "")
		if cbtn != null:
			cbtn.pressed.emit()
		var marked: bool = await _wait_until(func() -> bool:
			return Net.seats.size() > 1 and Net.seats[1] != null and bool(Net.seats[1].get("disconnected", false)), 10.0, "标记代管")
		_check("选「继续游戏」后该座位标记为房主代管", marked, str(Net.seats[1]) if Net.seats.size() > 1 else "")
		# 轮到已退出玩家的英雄时，房主可以替他操作（控制功能与本地一致）
		Game.state["current_hero"] = Game.state["hero_ids"].find("vision")
		Net.phase = "playing"
		_check("轮到他时房主接手操作（controlling_hero=vision）",
			Net.controlling_hero() == "vision" and Net.is_my_turn(), Net.controlling_hero())

# ================================================================ 客户端

func _run_client() -> void:
	# 密码错一次，验证会被拒（再正确加入）
	var ok_bad: bool = Net.join_room("127.0.0.1", "WRONG", "小号")
	_check("发起连接（密码故意错）", ok_bad, Net.last_error)
	var denied: bool = await _wait_until(func() -> bool: return not Net.active, 8.0, "被拒")
	_check("密码错误被拒绝并断开", denied, "still active=%s" % str(Net.active))
	await get_tree().create_timer(0.3).timeout

	Net.join_room("127.0.0.1", "pw123", "小号")
	var joined: bool = await _wait_until(func() -> bool: return Net.room.size() > 0 and Net.seats.size() > 0, 15.0, "进房")
	_check("用正确密码进房成功", joined, Net.last_error)
	if not joined:
		return
	_check("收到房间名与人数上限", String(Net.room.get("name", "")) == "测试房" and int(Net.room.get("max", 0)) == 4, str(Net.room))
	# 自由挑座位号：坐 1 号位（顺位=2）
	Net.request_seat(1)
	var seated: bool = await _wait_until(func() -> bool: return Net.my_seat() == 1, 10.0, "落座")
	_check("自由挑座位号成功（坐到 1 号位）", seated, "seat=%d" % Net.my_seat())
	_check("座位信息同步（0 号位是房主）", String(Net.seats[0]["name"]) == "房主", str(Net.seats[0]))

	# 跟随房主的阶段推进，各阶段做自己的选择
	var last_phase := ""
	var t := 0.0
	while t < 45.0 and not _started:
		var ph: String = Net.phase
		if ph != last_phase:
			last_phase = ph
			match ph:
				"hero":
					Net.request_pick("hero", "vision")
				"villain":
					Net.request_pick("villain", "ultron")
				"location":
					Net.request_pick("location", "阿斯加德")
		await get_tree().process_frame
		t += get_process_delta_time()
	_check("收到了房主的「开始游戏」", _started, "phase=%s" % Net.phase)
	if _started:
		_check("开局配置下发的英雄按顺位（含房主的 wasp）", str(_start_cfg["hero_ids"]) == str(["wasp", "vision"]), str(_start_cfg["hero_ids"]))
		_check("客户端看到别人选的英雄（同步可见）", String(Net.seats[0]["hero"]) == "wasp", str(Net.seats[0]))
	# 快照隐私：主机广播后，我这边看不到别人的手牌、只看到张数
	var got_snap: bool = await _wait_until(func() -> bool:
		return not Game.state.is_empty() and (Game.state.get("heroes", {}) as Dictionary).size() > 0, 10.0, "收到快照")
	_check("收到主机状态快照", got_snap, "")
	if got_snap:
		var hs: Dictionary = Game.state["heroes"]
		_check("隐私：我（vision）的手牌正常可见", (hs["vision"]["hand"] as Array).size() > 0, str(hs["vision"]["hand"]))
		_check("隐私：看不到房主（wasp）的手牌", (hs["wasp"]["hand"] as Array).is_empty(), str(hs["wasp"]["hand"]))
		_check("隐私：能看到房主的手牌张数", int(hs["wasp"].get("hand_count", -1)) >= 0, str(hs["wasp"].get("hand_count", -1)))
