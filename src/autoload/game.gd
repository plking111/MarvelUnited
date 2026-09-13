extends Node
## Game: 规则引擎（纯逻辑，UI 通过公开方法驱动）。
## 玩家决策通过 Events.prompt_* 信号 + await 协程完成。
## 所有状态保存在 state 字典中，支持序列化存档。

signal _answered(response)

const LOCATION_COUNT := 6
const THREAT_CLEAR_TOKENS := 3
const VILLAIN_STEP_DELAY := 0.5   # 反派回合每个步骤之间的间隔（秒），便于观察逐步结算

var state: Dictionary = {}
var autopilot: bool = false   # 无 UI 时自动选择（测试用）
var pending_setup: Dictionary = {}   # Setup 界面写入，Board 读取
## 无限战争战役跨局状态（局间保留）。
## ⚠️ 它必须独立于 state：Game.setup() 每开一局会整体重建 state，
## 战役进度（局数/已收集宝石/已解锁能量卡）不能跟着被清掉。
## 因此 state["campaign"] 是"给所有人看的同步副本"，每次改动后要立刻回写（见 _sync_campaign）。
var pending_campaign: Dictionary = {}
var debug_full_slots: bool = false   # 调试：填满地点指示物（主菜单设置面板设置）
var peek_hands: bool = false   # 调试/便利：允许查看其他英雄手牌（非官方规则，主菜单设置面板设置）
var undo_enabled: bool = false   # 可选：允许撤回上一步行动（非官方，主菜单设置面板设置）
var _undo_snapshot: Dictionary = {}   # 撤回快照（使用行动符号前保存）

var _overflow_event_locs := {}   # 本次"溢出结算事件"已结算过的地点（一次 BAM！/一次效果只算一次）

func _ready() -> void:
	# 初始化全局随机数种子，保证每次开局的洗牌（地点/反派出牌/身份牌/英雄牌堆）都不同；否则 Godot 用固定种子，叛徒每次都落同一人
	randomize()
	_start_test_watchdog()

## 测试看门狗（只在跑测试场景时生效）：
## 测试脚本一旦卡死（脚本编译失败、弹窗没人应答等）会一直挂住不退出。
## 超过 WATCHDOG_SEC 秒就打印"当前阶段 + 最近日志 + 卡住位置提示"并强制退出(1)，
## 避免"傻等"——日志里能直接看出卡在哪一步。
const WATCHDOG_SEC := 150

## 看门狗秒数：跑测试时可由运行器通过 `-- --test-timeout N` 覆盖，
## 这样 `run_tests.ps1 -LimitSec N` 才真的生效（以前它传不进来，全量跑总是拖到 10 分钟以上）。
func _watchdog_sec() -> int:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size()):
		if String(args[i]) == "--test-timeout" and i + 1 < args.size():
			return maxi(int(float(args[i + 1])), 5)   # 运行器可能传小数（如 6.7），必须按 float 解析
	return WATCHDOG_SEC

## 是否在跑测试场景（看门狗与老测试兼容垫片共用）
func _is_test_run() -> bool:
	for a in OS.get_cmdline_args():
		if String(a).begins_with("res://tests/") or String(a).contains("tests/"):
			return true
	return false

func _start_test_watchdog() -> void:
	var is_test := false
	for a in OS.get_cmdline_args():
		if String(a).begins_with("res://tests/") or String(a).contains("tests/"):
			is_test = true
			break
	if not is_test:
		return
	var timer := Timer.new()
	timer.wait_time = float(_watchdog_sec())
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(func() -> void:
		push_error("⏱ 测试看门狗：已运行 %d 秒仍未结束，判定卡死！" % _watchdog_sec())
		print("========== 看门狗诊断 ==========")
		print("已运行 %d 秒未退出 → 卡死（常见原因：脚本编译失败 / 弹窗无人应答 / await 永不返回）" % _watchdog_sec())
		if state is Dictionary and not state.is_empty():
			print("phase=%s villain=%s current_hero=%d story=%d" % [
				String(state.get("phase", "?")), String(state.get("villain", "?")),
				int(state.get("current_hero", -1)), int(state.get("story", []).size())])
			var lg: Array = state.get("log", [])
			var from := maxi(lg.size() - 8, 0)
			for i in range(from, lg.size()):
				print("  最近日志: ", str(lg[i]).substr(0, 160))
		print("=================================")
		get_tree().quit(1))
	add_child(timer)

# ---------------------------------------------------------------- setup

func setup(villain_id: String, hero_ids: Array, challenge: String = "none", mode: String = "base", expansions: Array = []) -> void:
	if mode == "s6":
		_setup_s6_full(hero_ids, expansions)
		return
	var vill: Dictionary = DB.villain(villain_id)
	# 神盾局单人模式按 3 人局血量；基础模式 1 人按 2 人血量（房规）
	var hp_key := "3" if mode == "shield" else str(maxi(hero_ids.size(), 2))
	var is_iw: bool = mode == "iw"
	state = {
		"villain": villain_id,
		"hero_ids": hero_ids.duplicate(),
		"player_count": hero_ids.size(),
		"challenge": challenge,
		"mode": mode,
		"campaign": {},
		"shield_deck": [],
		"shield_hand": [],
		"heroes": {},
		"locations": [],
		"villain_pos": 0,
		"villain_hp": int(vill["health"][hp_key]),
		"villain_hp_max": int(vill["health"][hp_key]),
		"fear": 0,
		"slaughter": 0,
		"eliminated": [],
		"cull_armor_used": false,
		"proxima_parry_used": false,
		"no_prev_symbols": false,
		"random_play": false,
		"iw_mind_active": false,
		"iw_space_active": false,
		"final_battle": false,
		"extra_villain_card": 0,
		"extra_villain_card_src": "",   # 这张额外行动卡是怎么来的（英雄被击倒 KO / 到达效果等），仅用于日志说明
		"extra_villain_turn": false,
		"ko_tokens": 0,   # 罗南：英雄被 KO 时获得 KO 指示物，累计 4 个判负
		"delay_villain_turn": false,   # 迈尔斯蛛网：反派回合推迟一个英雄回合
		"forced_face_down_hero": "",   # 秘密身份挑战：身份暴露后本回合必须背面出牌
		"hero_turn_seq": 0,            # 英雄回合序号（秘密身份挑战：每英雄每回合最多 1 个曝光）
		"sandman_hard": false,   # 沙人「更难」：未清除全部沙尘暴前不受伤害
		"electro_vanish": false,   # 电光人「消失」：全员出牌前不受伤害
		"electro_vanish_story": 0,   # 「消失」结算时的故事情节下标
		"kraven_decoy_used": false,   # 克莱文「诱饵」：本回合已忽略第一次伤害
		"no_villain_move_next": false,   # 蜘猪侠卡通蛛网：下个反派行动不移动
		"pending_villain_reveal": -1,   # 动画4：>=0 表示需要 UI 弹窗展示这张反派行动牌（card_idx），完成后置 -1
		"in_effect": false,   # 卡牌效果结算中：效果内部调用行动结算时不要提前结束回合
		"ql_busy": false,     # 蚁人·量子跃迁：防止交换后按新卡结算时再次交换（递归保护）
		"skip_villain_card": 0,   # 蜘蛛女·毒液冲击：下一个反派回合少打出的行动卡张数
		"villain_extra_card_next_turn": 0,   # 摩多克·超级天才智能：下一个反派回合多打出的行动卡张数
		"hero_start_loc": 0,      # 英雄起始地点（setup 时全部英雄的落点 = 反派初始地点的正对面；摩多克「制备」用）
		"villain_off_field": false,   # 康（第一季众筹）：被「时间大师」移出游戏 → 不在场上（villain_pos = -1）
		"rhino_moved_locs": 0,        # 犀牛人：本回合进入的地点数量（= 面板 BAM 的伤害值，反派回合开始时清零）
		"rhino_face_down_discard_hero": "",   # 犀牛人：本回合被要求面朝下出牌、回合结束要丢弃全部危机指示物的英雄
		"story": [],
		"solved_threats": [],
		"master_deck": [],
		"master_discard": [],
		"missions": [],
		"missions_completed": 0,
		"tokens": {"move": 0, "attack": 0, "heroic": 0, "wild": 0},
		"phase": "setup",
		"current_hero": 0,
		"hero_cards_played": 0,
		"turn_count": 0,
		"victory": false,
		"lose_reason": "",
		"action_symbols": [],
		"prev_hero_symbols": [],
		"used_tokens": {"move": 0, "attack": 0, "heroic": 0, "wild": 0},
		"effect_available": false,
		"effect_used": false,
		"played_effect": null,
		"virus_ignore": false,
		"waiting_input": false,
		"pending_loc_effect": {},
		"endangered": {},   # 濒危地点模式：英雄id -> 守卫地点；"setup_done"标记
		"loyalty": {},           # 叛徒模式：英雄id -> "loyal"/"traitor"
		"traitor_hid": "",
		"traitor_revealed": false,
		"traitor_active": false, # 叛徒已公开接管反派
		"accusations": {},       # 叛徒模式：指控者hid -> 被指控的hid
		"vulture_loot": 0,       # 秃鹫：已收集的战利品数量
		"log": [],
	}
	# 地点环：按选中的扩展过滤后随机取6张（决战专属地点仅在最终决战使用）
	var loc_ids: Array = []
	var is_final: bool = is_iw and int(pending_campaign.get("game", 1)) >= 4 if is_iw else false
	for id in DB.locations.keys():
		var loc_exp: String = DB.location(id).get("expansion", "基础盒")
		if loc_exp == "无限战争决战" and not is_final:
			continue
		if expansions.size() == 0 or expansions.has(loc_exp):
			loc_ids.append(id)
	loc_ids.shuffle()
	state["locations"] = []
	var loc_n: int = mini(LOCATION_COUNT, loc_ids.size())
	for i in range(loc_n):
		var loc_def: Dictionary = DB.location(loc_ids[i])
		var init: Array = loc_def.get("initial", [])
		var civ := 0
		var thug := 0
		for t in init:
			if t == "civ": civ += 1
			elif t == "thug": thug += 1
		state["locations"].append({
			"id": loc_ids[i], "civ": civ, "thug": thug, "crisis": 0,
			"threat": null, "threat_token": true, "destroyed": false, "reporter": false,
		})
	# 洗混威胁牌，每个地点1张（绿魔特殊：不预放威胁卡，威胁卡做成单独牌堆）
	var threats: Array = vill["threats"].duplicate()
	# 先给每张威胁卡记录其在数据中的序号（取正面威胁图 threat_%02d 用）
	for _ti in range(threats.size()):
		threats[_ti]["_tidx"] = _ti
	threats.shuffle()
	if state["villain"] == "goblin":
		# 绿魔特殊设置：不放置威胁卡/威胁指示物，威胁卡是单独牌堆（背面朝上放旁）
		state["goblin_threat_deck"] = []
		for t in threats:
			var td: Dictionary = t.duplicate(true)
			td["hp"] = td.get("henchman_hp", 0)
			td["heroic_tokens"] = 0
			td["arrival_triggered"] = false
			if td.has("clear"):
				td["clear_progress"] = []
			# 放置型威胁卡（企业爪牙）：放牌堆前先记默认要放的暴徒
			state["goblin_threat_deck"].append(td)
		state["goblin_panel_civ"] = 0
		state["goblin_scoundrel_bonus"] = false
		state["goblin_scoundrel_active"] = false
	else:
		for i in range(loc_n):
			var t: Dictionary = threats[i].duplicate(true)
			t["hp"] = t.get("henchman_hp", 0)
			t["heroic_tokens"] = 0
			t["arrival_triggered"] = false
			# 罗南等"符号清除"威胁卡：clear 数组 = 需填入的符号序列；filled 记录已填入的符号
			if t.has("clear"):
				t["clear_progress"] = []  # 已填入的符号列表（顺序无关，逐符号填）
			state["locations"][i]["threat"] = t
	# 反派初始位置
	state["villain_pos"] = randi_range(0, maxi(loc_n - 1, 0))
	# 秃鹫特殊设置：每个地点放 3 个危机指示物（代表"战利品"），收集满即英雄失败
	if villain_id == "vulture":
		for _vl in state["locations"]:
			_vl["crisis"] = 3
		state["vulture_loot"] = 0
	# 神秘客特殊设置：威胁卡开局随机背面朝上放在地点（英雄需花费任意行动翻开）
	if villain_id == "mysterio":
		for _ml in state["locations"]:
			if _ml["threat"] != null:
				_ml["threat"]["_face_down"] = true
	# 英雄
	for hid in hero_ids:
		var deck: Array = []
		var card_count := DB.hero_cards(hid).size()
		for i in range(card_count):
			deck.append(i)
		deck.shuffle()
		_apply_challenge(deck, hid)
		state["heroes"][hid] = {
			"id": hid, "deck": deck, "discard": [], "hand": [], "location": -1, "ko": false,
			"crisis": 0, "invulnerable": false, "ko_count": 0, "cartoon_web_armed": false, "miles_web_armed": false,
			"cat_redraw_armed": false, "dora_milaje": false, "martial_artist": false,
			"tokens": {"move": 0, "attack": 0, "heroic": 0, "wild": 0},
			"distrust": 0,   # 叛徒模式：不信任指示物
			"exposure": 0, "exposed": false, "exposure_turn": -1, "exposed_face_down": false,   # 秘密身份挑战
		}
	# 神盾局单人模式：3 英雄牌组合并成一个牌组，共享手牌；行动指示物共享给玩家
	if mode == "shield":
		state["shield_deck"] = []
		for hid in hero_ids:
			for i in range(DB.hero_cards(hid).size()):
				state["shield_deck"].append({"hero": hid, "idx": i})
		state["shield_deck"].shuffle()
		state["shield_tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
	# 叛徒挑战模式：发身份牌 + 不信任/万能指示物（需 3-4 人）
	if state["challenge"] == "traitor":
		_setup_traitor(hero_ids)
	# 英雄起始：全部放在反派初始地点的正对面（环上距离最远的点）
	var opposite: int = (int(state["villain_pos"]) + 3) % LOCATION_COUNT
	state["hero_start_loc"] = opposite   # 摩多克「制备」需要"英雄的起始地点"（此后反派位置会变）
	for i in range(hero_ids.size()):
		var hid: String = hero_ids[i]
		state["heroes"][hid]["location"] = opposite
		if mode == "shield":
			continue
		for d in range(3):
			_draw_card(hid)
	# 秘密身份挑战：英雄起始点相邻地点各放 1 记者指示物 + 反派起始地点额外 1 个
	if state["challenge"] == "secretid":
		_setup_secret_identity()
	# 神盾局：初始共享手牌 5 张
	if mode == "shield":
		for d in range(5):
			_draw_card(hero_ids[0])
	# 任务卡
	state["missions"] = []
	for m in DB.missions:
		state["missions"].append({"id": m["id"], "name": m["name"], "slots": m["slots"], "tokens": 0, "done": false})
	# B计划挑战：用 3 张更难的专属任务卡替换基础任务卡（营救12 / 击败12 / 化解威胁6）；
	# 卡图 + 槽位比例由脚本分析卡面得出；完成全部 3 张即直接获胜（见 _complete_mission）。
	if state["challenge"] == "planb":
		state["missions"] = [
			{"id": "rescue", "name": "营救平民", "slots": 12, "tokens": 0, "done": false,
				"img": "res://assets/cards/missions/planb/rescue.jpg",
				"xs": [0.228, 0.496, 0.764], "ys": [0.216, 0.406, 0.598, 0.79]},
			{"id": "defeat", "name": "击败暴徒", "slots": 12, "tokens": 0, "done": false,
				"img": "res://assets/cards/missions/planb/defeat.jpg",
				"xs": [0.229, 0.497, 0.765], "ys": [0.223, 0.413, 0.605, 0.797]},
			{"id": "clear", "name": "化解威胁", "slots": 6, "tokens": 0, "done": false,
				"img": "res://assets/cards/missions/planb/threat.jpg",
				"xs": [0.32, 0.67], "ys": [0.3, 0.507, 0.715]},
		]
	# 主计划牌组
	state["master_deck"] = []
	for i in range(vill["actions"].size()):
		state["master_deck"].append(i)
	state["master_deck"].shuffle()
	# 摩多克特殊设置（规则卡）：把「制备」放在一边，其余混洗后把「制备」放到牌堆顶
	# → 摩多克的第一回合必定打出「制备」（行动卡 1，下标 0）
	if villain_id == "modok":
		state["master_deck"].erase(0)
		state["master_deck"].insert(0, 0)
	# 无限战争战役模式：初始化战役状态（首次 setup 时），并插入无限宝石
	if is_iw:
		_setup_campaign(villain_id, hero_ids, expansions)
	elif villain_id == "thanos" and int(state.get("table_energy", -1)) < 0:
		# 灭霸作为**非无限战争**的 Boss 时，同样带 2 张能量卡（开局即激活）。
		# 代码里早就预留了这条规则的两个分支（setup 的 base_thanos 特判、_resolve_energy_activation），
		# 但一直没人给他设置 table/hidden 能量卡 → 这两张卡在界面上根本不存在（thanos_bug_test 报的就是这个）。
		var tc: Dictionary = pending_campaign
		if tc.is_empty():
			tc = {"game": 1, "order": [], "stones_collected": [], "energy_unlocked": [], "removed_energy": -1}
		var epool: Array = []
		for ei in range(DB.energy_cards.size()):
			if ei != int(tc.get("removed_energy", -1)) and not (tc.get("energy_unlocked", []) as Array).has(ei):
				epool.append(ei)
		epool.shuffle()
		var t_e: int = int(epool[0]) if epool.size() > 0 else -1
		var h_e: int = int(epool[1]) if epool.size() > 1 else -1
		state["table_energy"] = t_e
		state["hidden_energy"] = h_e
		tc["table_energy"] = t_e
		tc["hidden_energy"] = h_e
		tc["energy_unlocked"] = [t_e, h_e]
		pending_campaign = tc
		state["campaign"] = tc
		if t_e >= 0:
			_log("⚡ 灭霸（非无限战争）：本局能量卡 %s 已激活" % DB.energy_cards[t_e]["name"], Color(1, 0.8, 0.4))
	_log("—— 游戏设置完成 ——", Color(1, 0.8, 0.3))
	_log("反派：%s（%d 生命）｜英雄：%s" % [DB.villain_name(villain_id), state["villain_hp"], "、".join(hero_ids)])
	_log("初始指示物已按地点卡放置完毕，点击“开始游戏”进入第一个反派回合。", Color(0.8, 0.95, 0.8))
	state["phase"] = "setup"
	Events.emit_state_changed()
func _setup_campaign(villain_id: String, hero_ids: Array, expansions: Array) -> void:
	var c: Dictionary = pending_campaign if pending_campaign.size() > 0 else {
		"game": 1,
		"order": ["proxima", "cull", "ebony"],
		"stones_collected": [],
		"energy_unlocked": [],
		"energy_tokens": {},
	}
	# 决战（第 4 局）：反派固定灭霸，已收集宝石全部洗入牌组
	var is_final: bool = int(c["game"]) >= 4
	if is_final:
		c["final"] = true
		# 能量卡：决战中已解锁能量卡生效（此处仅记录）
		pending_campaign = c
		state["campaign"] = c
		state["final_battle"] = true
		state["table_energy"] = -1
		state["hidden_energy"] = -1
		state["energy_tokens"] = {}
		# 洗入已收集宝石
		for sidx in c["stones_collected"]:
			state["master_deck"].append({"stone": sidx})
		state["master_deck"].shuffle()
		_log("⚔️ 最终决战：灭霸！已收集宝石 %d 颗洗入牌组" % c["stones_collected"].size(), Color(1, 0.7, 0.3))
		return
	# 前 3 局：插入宝石到指定位置（本局剩余宝石数 = 3 - (game-1)）
	pending_campaign = c
	state["campaign"] = c
	state["final_battle"] = false
	var stones_left: Array = []
	for si in range(DB.stones.size()):
		if not c["stones_collected"].has(si) and not stones_left.has(si):
			stones_left.append(si)
	stones_left.shuffle()
	# 每局插入 3 颗无限宝石（从剩余未收集的宝石池取；上一局未翻出的宝石带入本局，故每局足够时都有 3 张）
	var n_stones: int = mini(3, stones_left.size())
	var positions: Array = [6, 10, 12]
	# 随机取本局要插入的宝石
	var inserted: Array = []
	# 从后往前插入，避免前面插入导致位置偏移（第6/10/12张之后）
	for pi in range(mini(n_stones, stones_left.size()) - 1, -1, -1):
		var sidx: int = stones_left[pi]
		inserted.push_front(sidx)
		var pos: int = positions[pi]
		state["master_deck"].insert(mini(pos, state["master_deck"].size()), {"stone": sidx})
	state["stones_inserted"] = inserted
	_log("战役第 %d 局：%d 颗无限宝石已插入反派牌组（位置 6/10/12）" % [int(c["game"]), inserted.size()], Color(1, 0.8, 0.5))
	# 能量卡：战役开始时随机移除 1 张（玩家不能知道是哪张）；
	# 每局从剩余未解锁能量卡中随机抽 2 张：第 1 张从游戏开始就可解锁，
	# 第 2 张需要完成三张任务卡（营救平民/击败暴徒/解决威胁）后才可解锁
	if not c.has("removed_energy"):
		var all_cards: Array = []
		for ei in range(DB.energy_cards.size()):
			all_cards.append(ei)
		all_cards.shuffle()
		c["removed_energy"] = all_cards[0]
	var pool: Array = []
	for ei in range(DB.energy_cards.size()):
		if ei == int(c.get("removed_energy", -1)):
			continue
		if not c["energy_unlocked"].has(ei):
			pool.append(ei)
	pool.shuffle()
	c["table_energy"] = pool[0] if pool.size() > 0 else -1
	c["hidden_energy"] = pool[1] if pool.size() > 1 else -1
	state["table_energy"] = c["table_energy"]
	state["hidden_energy"] = c["hidden_energy"]
	# 能量卡填充记录（每张卡 4 槽，dict: 卡索引 -> 已填槽索引数组，任意顺序）
	state["energy_tokens"] = {}
	if c["table_energy"] >= 0:
		state["energy_tokens"][str(c["table_energy"])] = []
	if c["hidden_energy"] >= 0:
		state["energy_tokens"][str(c["hidden_energy"])] = []
	if c["table_energy"] >= 0:
		_log("⚡ 本局能量卡：%s（从开局即可解锁）" % DB.energy_cards[c["table_energy"]]["name"], Color(0.9, 0.9, 0.5))
	if c["hidden_energy"] >= 0:
		_log("🔒 第二张能量卡已面朝下放置（需完成三张任务卡后才可解锁）", Color(0.9, 0.9, 0.5))
	if c.has("removed_energy"):
		_log("🔇 一张能量卡已在战役开始时被移出本战役", Color(0.7, 0.7, 0.7))

## 玩家确认初始布置后开始游戏：执行第一个反派回合（官方规则：游戏从反派回合开始）。
## 注意：setup 不再自动跑反派回合，保证开局展示的指示物数量与地点卡初始配置完全一致。
func start_game() -> void:
	if state["phase"] != "setup":
		return
	# 联机：开始游戏由房主统一决定，客户端本地点这个按钮无效（避免本地跑出另一套状态）
	if Net.active and not Net.is_host:
		return
	if state["challenge"] == "endangered":
		await _setup_endangered()
	await _run_villain_turn()

## 濒危地点模式：每位玩家按序号选一个守卫地点（不重复），记录守卫关系。
## 玩家序号即指示物数字（P1→1，P2→2...）。守卫关系用于溢出时伤害该玩家英雄。
func _setup_endangered() -> void:
	var chosen: Array = []
	for hid in state["hero_ids"]:
		var opts: Array = []
		var locs: Array = []
		for i in range(LOCATION_COUNT):
			if chosen.has(i):
				continue
			opts.append("%s（%s）" % [_loc_name(i), DB.hero_name(hid)])
			locs.append(i)
		if locs.is_empty():
			break
		var picked_idx: int = await _ask("%s：选择你要守护的地点" % DB.hero_name(hid), opts, hid)
		var loc: int = locs[wrapi(int(picked_idx), 0, locs.size())]
		chosen.append(loc)
		state["endangered"][hid] = loc
		_log("🏠 %s 守护 %s" % [DB.hero_name(hid), _loc_name(loc)], Color(0.65, 1, 0.8))
	state["endangered"]["setup_done"] = true
	Events.emit_state_changed()

func _apply_challenge(deck: Array, hid: String) -> void:
	var ch: String = state["challenge"]
	if ch == "" or ch == "none":
		return
	var remove_flags: Array = []
	for c in DB.challenges:
		if c["id"] == ch:
			remove_flags = c["remove"]
			break
	if remove_flags.size() == 0:
		return
	var cards: Array = DB.hero_cards(hid)
	var to_remove: Array = []
	for flag in remove_flags:
		for i in range(cards.size()):
			var syms: Array = cards[i]["symbols"]
			if flag == "wild" and syms == ["wild"]:
				to_remove.append(i); break
			elif flag == "wild_wild" and syms == ["wild", "wild"]:
				to_remove.append(i); break
	for i in to_remove:
		deck.erase(i)

# ---------------------------------------------------------------- 地点摧毁 / 相邻重构（章鱼博士）

## 未被摧毁的地点索引（按环序）
func _live_locs() -> Array:
	var out: Array = []
	for i in range(LOCATION_COUNT):
		if not state["locations"][i].get("destroyed", false):
			out.append(i)
	return out

## 在"未被摧毁地点构成的新环"上，loc 的两个相邻地点（被摧毁地点会被跳过）
func _adjacent_locs(loc: int) -> Array:
	var live: Array = _live_locs()
	var n: int = live.size()
	if n <= 1:
		return []
	var idx: int = live.find(loc)
	if idx == -1:
		return []
	return [int(live[(idx + n - 1) % n]), int(live[(idx + 1) % n])]

## 顺时针方向（在存活环上）从 loc 开始数的下一个地点；找不到返回 -1
func _next_live_loc(loc: int) -> int:
	var live: Array = _live_locs()
	var n: int = live.size()
	if n == 0:
		return -1
	var idx: int = live.find(loc)
	if idx == -1:
		return int(live[0])
	return int(live[(idx + 1) % n])

## 存活环上两点的最短距离（被摧毁的地点已从环上移除）
func _live_ring_dist(a: int, b: int) -> int:
	var live: Array = _live_locs()
	var n: int = live.size()
	if n <= 1:
		return 0
	var ia: int = live.find(a)
	var ib: int = live.find(b)
	if ia == -1 or ib == -1:
		return 0
	var d: int = absi(ia - ib)
	return mini(d, n - d)

func _destroyed_count() -> int:
	var c := 0
	for l in state["locations"]:
		if l.get("destroyed", false):
			c += 1
	return c

## 章鱼博士：检查并结算"地点摧毁"（危机 >= 3 的地点被移除游戏）
func _docock_check_destroy() -> void:
	if state["phase"] == "game_over":
		return
	var changed := false
	for i in range(LOCATION_COUNT):
		var l: Dictionary = state["locations"][i]
		if l.get("destroyed", false) or int(l["crisis"]) < 3:
			continue
		# 先算出"摧毁后"的相邻两地点（此时该地点仍在环上，必须提前算，否则移除后查不到）
		var adj: Array = _adjacent_locs(i)
		# 标记摧毁并清空其上所有指示物/威胁
		l["destroyed"] = true
		l["civ"] = 0
		l["thug"] = 0
		l["crisis"] = 0
		l["threat"] = null
		changed = true
		_log("💥 %s 危机达到 3 个，该地点被摧毁并移出游戏！" % _loc_name(i), Color(1, 0.4, 0.4))
		# 章鱼博士在该地点 → 顺时针移动到下一个地点（= 摧毁前的顺时针相邻地点）
		if state["villain_pos"] == i:
			var nxt: int = int(adj[1]) if adj.size() > 1 else _next_live_loc(i)
			if nxt >= 0:
				state["villain_pos"] = nxt
				_log("章鱼博士移动到下一个地点：%s" % _loc_name(nxt), Color(0.9, 0.7, 1))
		# 该地点的英雄 → 各自选择移动到（摧毁后）相邻两地点之一
		# 注意：被 KO 的英雄也必须一起移走（否则会卡在已摧毁、已移出游戏的地点上无法行动）
		for hid in _heroes_at(i):
			if adj.size() == 0:
				continue
			var ko_note: String = "（KO 中）" if state["heroes"][hid]["ko"] else ""
			if adj.size() == 1:
				await _set_hero_loc(hid, int(adj[0]), "forced")   # A1：被挤出去也算"进入一个地点"（但不是自己移动）
				_log("%s 被挤出 %s，移动到 %s%s" % [DB.hero_name(hid), _loc_name(i), _loc_name(int(adj[0])), ko_note], Color(0.8, 0.9, 1))
				continue
			var rows: Array = []
			for a in adj:
				var ld: Dictionary = DB.location(state["locations"][int(a)]["id"])
				rows.append({"icon": "move", "arrow": "move", "text": _loc_name(int(a)), "bottom": ld.get("image", "")})
			var pick: int = int(await _ask_action("%s%s：%s 被摧毁，选择移动到相邻地点" % [DB.hero_name(hid), ko_note, _loc_name(i)], rows))
			var dest: int = int(adj[wrapi(pick, 0, adj.size())])
			await _set_hero_loc(hid, dest)   # A1：统一出口
			_log("%s 移动到 %s（原地点被摧毁）%s" % [DB.hero_name(hid), _loc_name(dest), ko_note], Color(0.8, 0.9, 1))
		Events.emit_state_changed()
	if changed:
		Events.emit_state_changed()
		var dead: int = _destroyed_count()
		_log("已摧毁地点：%d / 4" % dead, Color(1, 0.5, 0.5))
		if dead >= 4:
			_lose("已有 %d 个地点被摧毁（4 个及以上），英雄们失败了！" % dead)

func _ring_dist(a: int, b: int) -> int:
	var d := absi(a - b)
	return mini(d, LOCATION_COUNT - d)

# ---------------------------------------------------------------- 叛徒挑战模式

## 叛徒挑战设置：发身份牌（3人删1忠诚牌）、给每人 1 万能 + 1 不信任指示物。需 3-4 人。
func _setup_traitor(hero_ids: Array) -> void:
	var n := hero_ids.size()
	if n < 3 or n > 4:
		_log("叛徒挑战模式只支持 3-4 名英雄/玩家（当前 %d）" % n, Color(1, 0.5, 0.5))
		state["phase"] = "setup"
		return
	var cards: Array = []
	for i in range(n - 1):
		cards.append("loyal")
	cards.append("traitor")
	cards.shuffle()
	for i in range(n):
		var hid: String = hero_ids[i]
		state["loyalty"][hid] = cards[i]
		state["heroes"][hid]["tokens"]["wild"] += 1        # 补偿：每人 1 个万能指示物
		state["heroes"][hid]["distrust"] = 1               # 每人 1 个不信任指示物
	state["traitor_hid"] = hero_ids[cards.find("traitor")]
	state["traitor_revealed"] = false
	state["traitor_active"] = false
	state["accusations"] = {}
	_log("身份牌已秘密发放（每位玩家查看自己的身份牌）", Color(0.9, 0.7, 0.9))

# ---------------------------------------------------------------- helpers

func _log(text: String, color: Color = Color.WHITE) -> void:
	state["log"].append({"t": text, "c": color.to_html()})
	Events.emit_log(text, color)

func _loc_name(idx: int) -> String:
	return DB.location_name(state["locations"][idx]["id"])

func _heroes_at(loc: int) -> Array:
	var out: Array = []
	for hid in state["hero_ids"]:
		if state["heroes"][hid]["location"] == loc:
			out.append(hid)
	return out

func _draw_card(hid: String) -> bool:
	# 神盾局单人模式：从共享牌组抽到共享手牌
	if state["mode"] == "shield":
		if state["shield_deck"].size() == 0:
			return false
		state["shield_hand"].append(state["shield_deck"].pop_front())
		return true
	var h: Dictionary = state["heroes"][hid]
	# 牌库空时：洗混弃牌堆成为新牌库（官方规则）
	if h["deck"].size() == 0 and h["discard"].size() > 0:
		h["deck"] = h["discard"].duplicate()
		h["discard"] = []
		h["deck"].shuffle()
		_log("%s 牌库耗尽，洗混弃牌堆" % DB.hero_name(hid), Color(0.8, 0.9, 1))
	if h["deck"].size() == 0:
		return false
	h["hand"].append(h["deck"].pop_front())
	# 抽取新牌后不可撤回（随机抽牌无法安全撤销）
	if undo_enabled and not _undo_snapshot.is_empty():
		_undo_snapshot = {}
	return true

var _wait_count := 0

## 标记游戏正在等待玩家输入（弹窗打开）：UI 据此隐藏行动按钮，防止并发操作覆盖行动
func _begin_wait() -> void:
	_wait_count += 1
	state["waiting_input"] = true
	Events.emit_state_changed()

func _end_wait() -> void:
	_wait_count = maxi(_wait_count - 1, 0)
	if _wait_count == 0:
		state["waiting_input"] = false
		Events.emit_state_changed()
		# 联机：这个弹窗已经有人回答了 → 主机自己也收起弹窗，并通知所有客户端收起
		# （以前只有"点弹窗的人"会收起，主机/其他人的弹窗会一直挂着，把操作挡住 → 无法行动）
		if Net.active:
			Net.finish_prompt()

## ============ 统一弹窗入口（结构优化第 2 步）============
## 以前 9 个 _ask_* 各自写一遍「广播 + begin_wait + 发事件 + await + end_wait」，
## 于是改「该谁答 / 何时关」要改 9 处，漏一处就卡死。现在全部收敛到 _prompt()。
##   kind：choice / action / confirm / villain_card / hand / story / deck / hero
##   payload：该弹窗需要的参数（title/options/rows/…），同时用于联机广播
##   answer_hero：该由哪个英雄的玩家回答（空 = 当前行动英雄）
## 各包装函数只保留「autopilot 默认值」和「前置检查」这类属于自己的语义。
func _prompt(kind: String, payload: Dictionary, answer_hero: String = "") -> Variant:
	if Net.is_host:
		Net.broadcast_prompt(kind, payload, _prompt_who(answer_hero))
	_begin_wait()
	var sig: Signal = _emit_prompt(kind, payload)
	var r: Variant = await sig
	_end_wait()
	return r

## 按 kind 发出对应 UI 事件，并返回「该等待的那个回答信号」（各 kind 的历史信号不同）
func _emit_prompt(kind: String, payload: Dictionary) -> Signal:
	match kind:
		"choice":
			Events.prompt_choice.emit(payload.get("options", []), String(payload.get("title", "")), Callable(self, "_on_answer"))
			return _answered
		"action":
			Events.prompt_action.emit(payload.get("rows", []), String(payload.get("title", "")), Callable(self, "_on_answer"))
			return _answered
		"confirm":
			Events.prompt_confirm.emit(String(payload.get("text", "")), Callable(self, "_on_answer"))
			return _answered
		"villain_card":
			Events.prompt_villain_card.emit(Callable(self, "_on_villain_card_answered"), String(payload.get("title", "")), int(payload.get("card_idx", 0)))
			return _villain_card_answered
		"hand":
			Events.prompt_hand_card.emit(Callable(self, "_on_hand_answered"), String(payload.get("title", "")), String(payload.get("hid", "")), int(payload.get("count", 1)))
			return _hand_answered
		"story":
			Events.prompt_story_card.emit(Callable(self, "_on_story_answered"), String(payload.get("title", "")), String(payload.get("filter_hero", "")))
			return _story_answered
		"deck":
			Events.prompt_deck_card.emit(Callable(self, "_on_deck_answered"), String(payload.get("title", "")), String(payload.get("hid", "")))
			return _deck_answered
		"hero":
			Events.prompt_hero_pick.emit(Callable(self, "_on_hero_answered"), String(payload.get("title", "")), payload.get("options", []))
			return _hero_answered
		"reorder":
			Events.prompt_reorder.emit(payload.get("cards", []), String(payload.get("villain", "")), String(payload.get("title", "")), Callable(self, "_on_reorder_answered"))
			return _reorder_answered
	return _answered

func _ask(title: String, options: Array, answer_hero: String = "") -> Variant:
	if autopilot:
		return 0
	return await _prompt("choice", {"title": title, "options": options}, answer_hero)

func _ask_action(title: String, rows: Array) -> Variant:
	if autopilot:
		return 0
	return await _prompt("action", {"title": title, "rows": rows})

func _ask_pick_hero(title: String, hero_ids: Array) -> int:
	var rows: Array = []
	for hh in hero_ids:
		rows.append({"text": DB.hero_name(hh), "img": DB.hero_back(hh), "hide_text": true})
	var picked: int = int(await _ask_action(title, rows))
	return wrapi(picked, 0, hero_ids.size())

func _ask_confirm(text: String) -> bool:
	if autopilot:
		return true
	return bool(await _prompt("confirm", {"text": text}))

signal _villain_card_answered(ok: bool)

## 显示一张反派行动牌（主计划牌）并要求确认（黑寡妇审讯用）
func _ask_villain_card(card_idx: int, title: String) -> bool:
	if autopilot:
		return true
	return bool(await _prompt("villain_card", {"title": title, "card_idx": card_idx}))

func _on_villain_card_answered(ok: Variant) -> void:
	_villain_card_answered.emit(bool(ok))

signal _hand_answered(picked: Array)

## 手牌选择（异步）：让玩家从指定英雄手牌（神盾局为共享手牌）中选 count 张
func _ask_hand_cards(hid: String, count: int, title: String) -> Array:
	var hand_ref: Array = state["shield_hand"] if state["mode"] == "shield" else state["heroes"][hid]["hand"]
	if autopilot:
		var auto: Array = []
		for i in range(mini(count, hand_ref.size())):
			auto.append(hand_ref.size() - 1 - i)
		return auto
	return await _prompt("hand", {"title": title, "hid": hid, "count": count}, hid)

func _on_hand_answered(picked: Variant) -> void:
	_hand_answered.emit(picked)

## 撤回上一步行动（可选功能）：恢复使用行动符号前的状态快照
func undo_last() -> void:
	if not undo_enabled:
		Events.emit_toast("撤回功能未开启（主菜单→设置）")
		return
	if _undo_snapshot.is_empty():
		Events.emit_toast("没有可撤回的操作")
		return
	state = _undo_snapshot
	_undo_snapshot = {}
	_log("↩ 已撤回上一步操作", Color(0.9, 0.9, 0.6))
	Events.emit_state_changed()

signal _story_answered(idx: int)

## 选择故事情节中的一张英雄卡牌（异步）：返回 story 索引。
## filter_hero 非空时只列出该英雄自己的卡（基础模式交换仅限自己的卡）
func _ask_story_card(title: String, filter_hero: String = "") -> int:
	var story_heroes: Array = []
	for i in range(state["story"].size()):
		if state["story"][i]["type"] == "hero" and (filter_hero == "" or state["story"][i]["hero"] == filter_hero):
			story_heroes.append(i)
	if story_heroes.size() == 0:
		return -1
	if autopilot:
		return int(story_heroes[story_heroes.size() - 1])
	return int(await _prompt("story", {"title": title, "filter_hero": filter_hero}))

func _on_story_answered(idx: Variant) -> void:
	_story_answered.emit(int(idx))

signal _deck_answered(idx: int)

## 从牌库选择一张牌（异步）：返回 deck 索引
func _ask_deck_card(hid: String, title: String) -> int:
	var deck: Array = state["heroes"][hid]["deck"]
	if deck.size() == 0:
		return -1
	if autopilot:
		return 0
	return int(await _prompt("deck", {"title": title, "hid": hid}, hid))

func _on_deck_answered(idx: Variant) -> void:
	_deck_answered.emit(int(idx))

signal _reorder_answered(order: Array)

## 拖拽排序（量子魔法）的回答入口：UI 拖完点"确认"后把新顺序交回来
func _on_reorder_answered(order: Variant) -> void:
	_reorder_answered.emit(order if order is Array else [])

func _on_answer(response: Variant) -> void:
	_answered.emit(response)

signal _hero_answered(hero_id: String)

## 从可选英雄池中选一个英雄（异步）：返回 hero_id。options 为英雄 id 数组。
func _ask_hero(title: String, options: Array) -> String:
	if options.size() == 0:
		return ""
	if autopilot:
		return options[0]
	return String(await _prompt("hero", {"title": title, "options": options}))

func _on_hero_answered(hero_id: String) -> void:
	_hero_answered.emit(hero_id)

## 无限战争：该能量卡在本局显示中的编号（1 或 2，按 table/hidden 顺序）
func energy_local_no(eidx: int) -> int:
	var no := 1
	for e2 in [int(state.get("table_energy", -1)), int(state.get("hidden_energy", -1))]:
		if e2 == eidx:
			return no
		if e2 >= 0:
			no += 1
	return eidx + 1

## 无限战争：能量卡已填槽索引数组（任意顺序，如 [0,2] 表示第1、3槽已填）
func energy_filled_slots(eidx: int) -> Array:
	var raw: Variant = state.get("energy_tokens", {}).get(str(eidx), [])
	if raw is Array:
		# 联机客户端的数据经过 JSON 快照，数字会变成浮点（0.0 而非 0）；
		# 统一归一化成 int，否则 UI 用 has(si)（int）判断会认为"没填"→ 槽位图标不亮。
		var out: Array = []
		for v in (raw as Array):
			out.append(int(v))
		return out
	return []

## 无限战争：能量卡已填槽数（0-4）
func energy_filled(eidx: int) -> int:
	return energy_filled_slots(eidx).size()

## 无限战争：该能量卡是否可填充
## 第 1 张（table_energy）从游戏开始即可解锁；第 2 张（hidden_energy）需完成三张任务卡后
func energy_can_fill(eidx: int) -> bool:
	if state.get("final_battle", false):
		return false  # 决战不填槽，直接按符号激活
	if int(state.get("campaign", {}).get("game", 1)) >= 4:
		return true
	if state.get("table_energy", -1) == eidx:
		return true
	if state.get("hidden_energy", -1) == eidx:
		return state["missions_completed"] >= 3
	return false

## 无限战争：能量卡槽位要求的符号列表（2×2 展平，如 ["heroic","heroic","heroic","heroic"]）
func energy_required_syms(eidx: int) -> Array:
	if eidx < 0 or eidx >= DB.energy_cards.size():
		return []
	var need: Array = []
	for row in DB.energy_cards[eidx]["slots"]:
		for s in row:
			need.append(s)
	return need

## 无限战争：该能量卡是否已完成（全部槽填满）
func energy_done(eidx: int) -> bool:
	return energy_filled(eidx) >= energy_required_syms(eidx).size()

## 无限战争：符号 sym 能否填入该能量卡的某个空槽（返回可填槽索引，-1 不可填）
## 万能可填任意符号空槽；普通符号需匹配空槽符号（任意顺序）
func energy_match_slot(eidx: int, sym: String) -> int:
	var need: Array = energy_required_syms(eidx)
	var filled: Array = energy_filled_slots(eidx)
	for si in range(need.size()):
		if filled.has(si):
			continue
		if need[si] == sym or sym == "wild" or need[si] == "threat":
			# threat 槽只能由威胁指示物填（普通行动不能填 threat 槽）
			if need[si] == "threat" and sym != "threat":
				continue
			return si
	return -1

## 无限战争：用对应行动填充能量卡空槽（任意顺序；万能可替代；消耗行动；填满解锁）
func fill_energy_card(eidx: int, sym: String = "") -> bool:
	if state["phase"] != "hero_actions":
		return false
	if not energy_can_fill(eidx):
		Events.emit_toast("该能量卡当前不可填充")
		return false
	if energy_done(eidx):
		return false
	var hid: String = state["hero_ids"][state["current_hero"]]
	# 未指定符号时：弹出选择（可消耗符号或指示物；万能可替代任意槽）
	if sym == "":
		var syms: Array = available_symbols()
		var options: Array = []
		var keys: Array = []
		for s in syms:
			if s.begins_with("token_"):
				var tbase: String = s.substr(6)
				if energy_match_slot(eidx, tbase) >= 0:
					options.append("指示物·%s" % DB.symbol_name(tbase))
					keys.append(s)
			else:
				if s == "wild" or energy_match_slot(eidx, s) >= 0:
					options.append("%s行动" % DB.symbol_name(s))
					keys.append(s)
		if options.size() == 0:
			Events.emit_toast("没有可用的行动能填充该能量卡（威胁槽需解决威胁时放置）")
			return false
		var pick: int = await _ask("⚡ 填充能量卡 %d（%d/%d）" % [energy_local_no(eidx), energy_filled(eidx), energy_required_syms(eidx).size()], options)
		if pick < 0 or pick >= keys.size():
			return false
		sym = keys[pick]
	# 消耗行动：优先符号，其次指示物
	var is_token := sym.begins_with("token_")
	var base: String = sym.substr(6) if is_token else sym
	# 找匹配的空槽（万能选一个符号槽；普通符号匹配对应槽；任意顺序）
	var slot_idx: int = -1
	if base == "wild":
		# 万能：从可填符号槽中任选一个（优先非 threat；纯威胁槽需威胁指示物）
		var need2: Array = energy_required_syms(eidx)
		var filled2: Array = energy_filled_slots(eidx)
		for si in range(need2.size()):
			if not filled2.has(si) and need2[si] != "threat":
				slot_idx = si
				break
		if slot_idx == -1:
			Events.emit_toast("没有可用的普通符号槽（威胁槽需解决威胁时放置）")
			return false
	else:
		slot_idx = energy_match_slot(eidx, base)
		if slot_idx == -1:
			Events.emit_toast("该能量卡没有可填的 %s 空槽" % DB.symbol_name(base))
			return false
	if not is_token:
		var idx: int = state["action_symbols"].find(base)
		if idx == -1:
			Events.emit_toast("没有可用的%s行动" % DB.symbol_name(base))
			return false
		state["action_symbols"].remove_at(idx)
	else:
		var pool: Dictionary = state["shield_tokens"] if state["mode"] == "shield" else state["heroes"][hid]["tokens"]
		if int(pool[base]) - int(state["used_tokens"][base]) <= 0:
			Events.emit_toast("没有可用的%s指示物" % DB.symbol_name(base))
			return false
		pool[base] -= 1
	var filled_slots: Array = energy_filled_slots(eidx)
	filled_slots.append(slot_idx)
	state["energy_tokens"][str(eidx)] = filled_slots
	_log("%s 用 %s 填充能量卡 %d（%d/%d）" % [DB.hero_name(hid), DB.symbol_name(base), energy_local_no(eidx), filled_slots.size(), energy_required_syms(eidx).size()], Color(0.9, 0.9, 0.5))
	if filled_slots.size() >= energy_required_syms(eidx).size():
		_unlock_energy_card(eidx)
	Events.emit_state_changed()
	await _maybe_auto_end_turn()
	return true

## 无限战争：解锁能量卡（放到灭霸卡组旁留到决战使用）
func _unlock_energy_card(eidx: int) -> void:
	var c: Dictionary = state.get("campaign", {})
	if not c.is_empty() and not c["energy_unlocked"].has(eidx):
		c["energy_unlocked"].append(eidx)
	pending_campaign = c
	_log("⚡ 能量卡解锁：%s（%s）" % [DB.energy_cards[eidx]["name"], DB.energy_cards[eidx]["effect_text"]], Color(0.9, 0.9, 0.4))
	Events.emit_state_changed()

## 无限战争决战：结算能量卡效果（在打出英雄卡后调用）
## 效果：每拥有 cost 中的行动 → 获得 gain（可多次，如 4 攻击 → 2 英勇）
## 规则：万能/特殊行动/行动指示物不参与判定；产出的行动不能用于解锁其他能量卡或触发其他能量卡
func _resolve_energy_activation() -> void:
	# 决战（无限战争第4局）或 灭霸作为非无限战争 Boss：已激活能量卡生效
	var base_thanos: bool = state["villain"] == "thanos" and state.get("mode", "base") != "iw"
	if not state.get("final_battle", false) and not base_thanos:
		return
	var c: Dictionary = state.get("campaign", {})
	var unlocked: Array = c.get("energy_unlocked", [])
	if unlocked.size() == 0:
		return
	# 只用手牌打出卡符号 + 上一张卡符号（不包含万能/指示物）
	var card_syms: Array = state["action_symbols"].duplicate()
	for s in state["prev_hero_symbols"]:
		if not card_syms.has(s):
			card_syms.append(s)
	# 去除 wild（万能不能触发能量卡）
	card_syms = card_syms.filter(func(s): return s != "wild")
	for eidx in unlocked:
		var e: Dictionary = DB.energy_cards[eidx]
		var cost: Array = e["cost"]
		var gain: Array = e["gain"]
		# 统计能凑出多少组 cost（每凑一组获得一次 gain）
		var pool: Array = card_syms.duplicate()
		var times := 0
		while true:
			var ok := true
			var tmp: Array = pool.duplicate()
			for s2 in cost:
				var fi: int = tmp.find(s2)
				if fi == -1:
					ok = false
					break
				tmp.remove_at(fi)
			if not ok:
				break
			pool = tmp
			times += 1
		if times > 0:
			for i in range(times):
				for s3 in gain:
					state["action_symbols"].append(s3)
			_log("⚡ 能量卡效果：%s（凑齐 %d 组 → %s）" % [e["name"], times, e["effect_text"]], Color(0.9, 0.9, 0.4))
	Events.emit_state_changed()

# ---------------------------------------------------------------- win / lose

func _check_lose() -> bool:
	var vill: Dictionary = DB.villain(state["villain"])
	var track: String = vill.get("plot_track", "")
	if track == "fear" and state["fear"] >= vill.get("fear_track_max", 20):
		_lose("红骷髅的恐惧轨道到达 20，邪恶计划完成！")
		return true
	if track == "slaughter" and state.get("slaughter", 0) >= 12:
		_lose("暗夜比邻星的屠宰轨道到达 12，邪恶计划完成！")
		return true
	if state["villain"] == "thanos" and state.get("eliminated", []).size() >= state["player_count"]:
		_lose("被淘汰的英雄数量等于起始英雄数量，恶毒的阴谋得逞！")
		return true
	if track == "full":
		var all_full := true
		for l in state["locations"]:
			if l["civ"] + l["thug"] < int(DB.location(l["id"])["slots"]):
				all_full = false
				break
		if all_full:
			_lose("奥创占领了全部地点，邪恶计划完成！")
			return true
	# 基尔格蒙·邪恶阴谋：4 个或更多地点各有 3 个或更多危机指示物 → 英雄失败
	if state["villain"] == "kilmonger":
		var crisis_locs := 0
		for l in state["locations"]:
			if int(l["crisis"]) >= 3:
				crisis_locs += 1
		if crisis_locs >= 4:
			_lose("基尔格蒙的邪恶阴谋得逞：4 个以上地点有 3 个以上危机指示物，英雄失败！")
			return true
	# 罗南·邪恶计划：英雄们总计获得 4 个 KO 指示物 → 英雄失败
	if state["villain"] == "ronan" and int(state.get("ko_tokens", 0)) >= 4:
		_lose("英雄们总计获得 4 个 KO 指示物，罗南的邪恶计划得逞了！")
		return true
	# 亡刃将军·邪恶计划：KO 指示物总数 == 英雄数 → 英雄失败
	if state["villain"] == "corvus" and int(state.get("ko_tokens", 0)) >= state["hero_ids"].size():
		_lose("英雄们总计获得 %d 个 KO 指示物，亡刃将军的邪恶计划得逞了！" % state["hero_ids"].size())
		return true
	# 绿魔·邪恶计划：当所有地点都有威胁卡时，英雄失败
	if state["villain"] == "goblin":
		var all_threat := true
		for l in state["locations"]:
			if l["threat"] == null:
				all_threat = false
				break
		if all_threat:
			_lose("绿魔占领了所有地点（全部地点都有威胁卡），邪恶计划得逞！")
			return true
	# 猎人克莱文·邪恶计划：英雄们"同一时间"全部被击倒（KO）→ 英雄失败
	if state["villain"] == "kraven":
		var all_ko := true
		for hid in state["hero_ids"]:
			if not state["heroes"][hid]["ko"]:
				all_ko = false
				break
		if all_ko and state["hero_ids"].size() > 0:
			_lose("英雄们在同一时间全部被击倒，猎人克莱文的邪恶计划得逞了！")
			return true
	# 沙人·邪恶计划：生命值达到 20 以上 → 英雄失败
	if state["villain"] == "sandman" and int(state["villain_hp"]) >= 20:
		_lose("沙人的生命值达到 %d（20 以上），英雄们失败了！" % int(state["villain_hp"]))
		return true
	# 电光人·邪恶计划：所有地点都有危机指示物 → 英雄失败
	if state["villain"] == "electro":
		var all_crisis := true
		for l in state["locations"]:
			if l.get("destroyed", false):
				continue
			if int(l["crisis"]) <= 0:
				all_crisis = false
				break
		if all_crisis:
			_lose("所有地点都有危机指示物，电光人的邪恶计划得逞了！")
			return true
	# 摩多克·恶毒的阴谋：故事情节中的所有英雄卡都面朝下 → 英雄失败
	if state["villain"] == "modok" and VillainRules._modok_all_story_heroes_face_down(self):
		_lose("故事情节中的所有英雄卡都面朝下（被摩多克翻转），摩多克的恶毒阴谋得逞了！")
		return true
	return false

func _lose(reason: String) -> void:
	state["phase"] = "game_over"
	state["lose_reason"] = reason
	# 无限战争前 3 局失败：本局埋入卡组的宝石全部交给灭霸，战役不一定直接失败
	if state.get("mode", "base") == "iw" and not state.get("final_battle", false):
		var c: Dictionary = state.get("campaign", {})
		var inserted: Array = state.get("stones_inserted", [])
		if not c.is_empty():
			for sidx in inserted:
				if not c["stones_collected"].has(sidx):
					c["stones_collected"].append(sidx)
			pending_campaign = c
			if c["stones_collected"].size() >= 6:
				# 集齐 6 颗宝石：战役失败（标题"英雄失败"，副标题说明）
				reason = "灭霸收集了6颗宝石，消灭了宇宙一半生命"
				state["lose_reason"] = reason
				state["campaign_lost"] = true
				_log(reason, Color(1, 0.4, 0.4))
				Events.game_over.emit(false, reason)
				return
			_log("本局战败：%d 颗宝石落入灭霸手中（已收集 %d/6），战役继续！" % [inserted.size(), c["stones_collected"].size()], Color(1, 0.5, 0.5))
	_log(reason, Color(1, 0.4, 0.4))
	Events.game_over.emit(false, reason)

func _win() -> void:
	state["phase"] = "game_over"
	state["victory"] = true
	if state.get("mode", "base") == "iw":
		_campaign_victory_log()
	_log("反派被击败！英雄们胜利！", Color(0.5, 1, 0.5))
	Events.game_over.emit(true, "")

## 无限战争：翻出无限宝石卡
## 前 3 局：卡牌本身无效果，代表反派拿到宝石交给灭霸，收集到灭霸卡组旁；
## 决战（第 4 局）：宝石卡作为普通反派行动生效（效果极强），然后抽取另一张行动卡。
func _reveal_stone(sidx: int) -> void:
	var stone: Dictionary = DB.stones[sidx]
	var c: Dictionary = state.get("campaign", {})
	if not c.is_empty() and not c.get("stones_collected", []).has(sidx):
		c["stones_collected"].append(sidx)
		_log("🔮 反派翻出无限宝石：%s 被灭霸收集！（已收集 %d/6）" % [stone["name"], c["stones_collected"].size()], Color(1, 0.6, 1))
		if c["stones_collected"].size() >= 6:
			_lose("灭霸集齐 6 颗无限宝石，打响指毁灭了宇宙！")
			return
	else:
		_log("🔮 无限宝石：%s（已收集过）" % stone["name"], Color(1, 0.6, 1))
	# 决战：宝石作为行动生效
	if state.get("final_battle", false):
		_log("💎 宝石效果：%s" % stone["text"], Color(1, 0.7, 0.9))
		match stone["id"]:
			"mind":
				# 从现在开始，英雄们打出卡牌时均为随机打出
				state["iw_mind_active"] = true
				_log("心灵宝石：从现在开始，英雄们随机打出卡牌", Color(1, 0.7, 0.9))
			"power":
				# 立即效果：对所有英雄造成 1 点伤害
				for hid in state["hero_ids"].duplicate():
					if not state["heroes"][hid]["ko"]:
						await _deal_damage_to_hero(hid, 1)
			"reality":
				# 立即效果：将所有已完成的任务重新激活（从头开始）
				for m in state["missions"]:
					if m.get("done", false):
						m["done"] = false
						m["tokens"] = 0
						state["missions_completed"] = maxi(state["missions_completed"] - 1, 0)
				_log("现实宝石：所有已完成任务重新激活", Color(1, 0.7, 0.9))
			"soul":
				# 立即效果：灭霸获得 6 点生命值（可以超过上限）
				state["villain_hp"] += 6
				state["villain_hp_max"] = maxi(state["villain_hp_max"], state["villain_hp"])
				_log("灵魂宝石：灭霸获得 6 点生命（当前 %d）" % state["villain_hp"], Color(1, 0.7, 0.9))
			"space":
				# 从现在开始：英雄们忽略回合中的第一个移动行动
				state["iw_space_active"] = true
				_log("空间宝石：从现在开始，英雄们忽略回合中的第一个移动行动", Color(1, 0.7, 0.9))
			"time":
				# 立即效果：反派立刻抽取并执行两张行动卡
				state["extra_villain_card"] += 2
				_log("时间宝石：反派立刻抽取并执行两张行动卡", Color(1, 0.7, 0.9))
	Events.emit_state_changed()
	if _check_lose():
		return

## 无限战争：英雄击败本局反派后记录战役进度（前 3 局胜利 → 下一局；决战胜利 → 战役胜利）
func _campaign_victory_log() -> void:
	var c: Dictionary = state.get("campaign", {})
	if c.is_empty():
		return
	if state.get("final_battle", false):
		# 决战胜利：战役胜利
		_log("🌌 战役胜利！宇宙获救，无限宝石回归原位！", Color(0.5, 1, 0.5))
		return
	# 前 3 局胜利：进入下一局
	var game_no: int = int(c.get("game", 1))
	if game_no >= 3:
		_log("✅ 全部前哨战完成！准备最终决战灭霸！", Color(0.5, 1, 0.5))
	else:
		_log("✅ 前哨战胜利！准备战役第 %d 局" % (game_no + 1), Color(0.5, 1, 0.5))
	Events.emit_state_changed()

# ---------------------------------------------------------------- damage / KO

func _deal_damage_to_hero(hid: String, amount: int, no_redirect: bool = false) -> void:
	var h: Dictionary = state["heroes"][hid]
	if h["ko"]:
		return
	# 第二批·绯红女巫「心灵能量场」：下一个反派回合内，每名英雄免疫首次伤害
	if String(state.get("phase", "")) == "villain" and bool(h.get("ignore_first_hit", false)):
		h["ignore_first_hit"] = false
		_log("%s 免疫本次伤害（心灵能量场）" % DB.hero_name(hid), Color(0.8, 0.8, 1))
		Events.emit_state_changed()
		return
	if h["invulnerable"]:
		_log("%s 免疫伤害（无懈可击）" % DB.hero_name(hid), Color(0.6, 0.9, 1))
		return
	# 第三批·月光骑士「月光骑士战衣」（裁定5）：每次受伤都可无视该伤害，并（可选）移动到任意地点
	if bool(h.get("moon_suit", false)):
		_log("%s 无视本次 %d 点伤害（月光骑士战衣）" % [DB.hero_name(hid), amount], Color(0.85, 0.9, 1))
		if await _ask_confirm("月光骑士战衣：要移动到任意地点吗？（可以不走）"):
			var ms_cands: Array = []
			for _ms_l in range(LOCATION_COUNT):
				ms_cands.append(_ms_l)
			await _effect_move_to(hid, ms_cands, "月光骑士战衣：选择目的地")
		Events.emit_state_changed()
		return
	# 鹰眼·武术家：直到下回合开始，可以把将要承受的伤害转移到所在地点的敌人身上
	if not no_redirect and bool(h.get("martial_artist", false)):
		var ma_loc: int = int(h["location"])
		var ma_tgts: Array = _enemy_targets_at(ma_loc)
		if ma_tgts.size() > 0:
			if await _ask_confirm("武术家：把这次 %d 点伤害转移到你所在地点的敌人身上？" % amount):
				var ma_p: int = int(await _ask_action("武术家：选择承受伤害的敌人", _enemy_target_rows(ma_loc, ma_tgts)))
				var ma_t: String = String(ma_tgts[wrapi(ma_p, 0, ma_tgts.size())])
				_log("武术家：%s 把 %d 点伤害转移给 %s" % [DB.hero_name(hid), amount, _target_name(ma_t)], Color(0.8, 0.9, 1))
				for _mi in range(amount):
					await _perform_attack_at(ma_loc, ma_t, hid)
				Events.emit_state_changed()
				return
	# 奥克耶·多拉·米拉杰：直到下回合开始，同地点的另一名英雄可以替其承受伤害
	if not no_redirect:
		var dora_hid := ""
		for oh in state["hero_ids"]:
			if oh == hid:
				continue
			var ohh: Dictionary = state["heroes"][oh]
			if ohh["ko"] or not bool(ohh.get("dora_milaje", false)):
				continue
			if int(ohh["location"]) != int(h["location"]):
				continue
			dora_hid = String(oh)
			break
		if dora_hid != "":
			if await _ask_confirm("多拉·米拉杰：%s 是否替 %s 承受这 %d 点伤害？" % [DB.hero_name(dora_hid), DB.hero_name(hid), amount]):
				_log("多拉·米拉杰：%s 替 %s 承受 %d 点伤害" % [DB.hero_name(dora_hid), DB.hero_name(hid), amount], Color(0.8, 0.9, 1))
				await _deal_damage_to_hero(dora_hid, amount, true)
				return
	# 战术支援（暗夜比邻星威胁）：该地点的英雄在受到伤害时会受到额外 1 点伤害
	var hl: int = h["location"]
	var threat_here: Variant = state["locations"][hl]["threat"]
	if threat_here != null and threat_here["name"] == "战术支援":
		amount += 1
		_log("战术支援：%s 受到的伤害 +1" % DB.hero_name(hid), Color(1, 0.6, 0.4))
	# 高压（电光人威胁）：在该地点受到伤害的英雄额外 +1
	if threat_here != null and threat_here["name"] == "高压":
		amount += 1
		_log("高压：%s 受到的伤害 +1" % DB.hero_name(hid), Color(1, 0.6, 0.4))
	# 陷阱（猎人克莱文威胁）：该地点没有平民也没有暴徒时，英雄在此受到的伤害 +1
	if threat_here != null and threat_here["name"] == "陷阱":
		var tl: Dictionary = state["locations"][hl]
		if int(tl["civ"]) == 0 and int(tl["thug"]) == 0:
			amount += 1
			_log("陷阱：%s 没有平民/暴徒，%s 受到的伤害 +1" % [_loc_name(hl), DB.hero_name(hid)], Color(1, 0.6, 0.4))
	# 险恶地形（亡刃将军威胁）：在此地点受到伤害的英雄会受到 1 点额外伤害
	if threat_here != null and threat_here["name"] == "险恶地形":
		amount += 1
		_log("险恶地形：%s 受到的伤害 +1" % DB.hero_name(hid), Color(1, 0.6, 0.4))
	# 神盾局模式：弃共享手牌
	var hand_ref: Array = state["shield_hand"] if state["mode"] == "shield" else h["hand"]
	var total: int = hand_ref.size()
	var n: int = mini(amount, total)
	if n > 0:
		# 玩家选择弃掉哪些手牌（每 1 点伤害弃 1 张）
		var picked: Array = await _ask_hand_cards(hid, n, "%s 受到 %d 点伤害：选择要弃掉的 %d 张手牌" % [DB.hero_name(hid), amount, n])
		var dropped: Array = []
		if picked.size() == 0:
			# 异常保护（正常无法取消）：自动弃最后 n 张
			for i in range(n):
				if hand_ref.size() > 0:
					dropped.append(hand_ref.pop_back())
		else:
			picked.sort()
			# 蜘猪侠卡通精髓：最后一张牌不能被弃置（弃后至少保留 1 张手牌）
			var protect: bool = h.get("protect_last_card", false) or _immortality_active(hid)   # 第三批·术士亚当·不朽：同样保护最后一张手牌
			for i in range(picked.size() - 1, -1, -1):
				var idx: int = int(picked[i])
				if idx >= 0 and idx < hand_ref.size():
					if protect and hand_ref.size() == 1:
						continue
					dropped.append(hand_ref[idx])
					hand_ref.remove_at(idx)
		# 受伤弃掉的牌回到该英雄牌库底（官方规则；神盾局模式回共享牌库底）
		for c in dropped:
			if state["mode"] == "shield":
				state["shield_deck"].append(c)
			else:
				h["deck"].append(c)
		_log("%s 受到 %d 点伤害，弃 %d 张手牌到牌库底" % [DB.hero_name(hid), amount, dropped.size()], Color(1, 0.6, 0.6))
	# 犀牛人威胁卡「开阔地带」：在此地点受到伤害的英雄还将获得 1 个危机指示物。
	# 放在这里（实际结算完伤害之后、KO 判定之前）：被免疫/被转移的伤害在上面就已经 return，
	# 那种情况不算"受到伤害"，不会走到这里。
	if state["villain"] == "rhino":
		VillainRules._rhino_on_hero_damaged(self, hid)
	# 手牌被弃空（含刚好弃光）→ 该英雄被击倒（KO），触发反派 BAM
	# 普通模式：手牌清空即 KO；神盾局模式：共享手牌机制不同，保持原判断（伤害超过可弃手牌才 KO）
	if state["mode"] != "shield" and hand_ref.size() == 0:
		await _ko_hero(hid)
	elif state["mode"] == "shield" and n < amount:
		await _ko_hero(hid)
	Events.emit_state_changed()

func _ko_hero(hid: String) -> void:
	var h: Dictionary = state["heroes"][hid]
	if h["ko"]:
		return
	# KO 时将该英雄整手牌弃置到其牌库底（沃米尔等特殊 KO 不会清空手牌，需先弃置，避免复活后手牌爆多）
	while h["hand"].size() > 0:
		h["deck"].append(h["hand"].pop_back())
	h["ko"] = true
	await _step_pause()
	if state["villain"] == "ronan":
		# 罗南特殊规则：有英雄被 KO 时，该英雄获得 1 个 KO 指示物（标记在英雄图标上）；累计 4 个判负。
		# 罗南 KO 不替换英雄（那是灭霸规则）；英雄保持 KO 状态，回合开始复活，并触发普通 BAM。
		h["ko_count"] = int(h.get("ko_count", 0)) + 1
		state["ko_tokens"] = int(state.get("ko_tokens", 0)) + 1
		_log("💥 %s 被击倒（KO）！获得 1 个 KO 指示物（该英雄 %d 个，全场 %d/4）" % [DB.hero_name(hid), h["ko_count"], state["ko_tokens"]], Color(0.9, 0.3, 0.3))
		if int(state.get("ko_tokens", 0)) >= 4:
			_lose("英雄们总计获得 4 个 KO 指示物，罗南的邪恶计划得逞了！")
			return
		_log("💥 %s 被击倒（KO）！触发反派 BAM 效果！" % DB.hero_name(hid), Color(1, 0.5, 0.2))
		await _trigger_panel_bam()
		if _check_lose():
			return
		Events.emit_state_changed()
		return
	if state["villain"] == "corvus":
		# 亡刃将军特殊规则：英雄被 KO 时获得 1 个 KO 指示物；邪恶计划=KO 指示物总数==英雄数时失败。
		# KO 不替换英雄（那是灭霸规则）；英雄保持 KO 状态，回合开始复活，并触发普通 BAM。
		h["ko_count"] = int(h.get("ko_count", 0)) + 1
		state["ko_tokens"] = int(state.get("ko_tokens", 0)) + 1
		var heronum: int = state["hero_ids"].size()
		_log("💥 %s 被击倒（KO）！获得 1 个 KO 指示物（该英雄 %d 个，全场 %d/%d）" % [DB.hero_name(hid), h["ko_count"], state["ko_tokens"], heronum], Color(0.9, 0.3, 0.3))
		if int(state.get("ko_tokens", 0)) >= heronum:
			_lose("英雄们总计获得 %d 个 KO 指示物，亡刃将军的邪恶计划得逞了！" % heronum)
			return
		_log("💥 %s 被击倒（KO）！触发反派 BAM 效果！" % DB.hero_name(hid), Color(1, 0.5, 0.2))
		await _trigger_panel_bam()
		if _check_lose():
			return
		Events.emit_state_changed()
		return
	if state["villain"] == "thanos":
		# 灭霸特殊规则：KO 时不触发 BAM！该英雄被从游戏中淘汰，玩家选择新的英雄继续游戏
		_log("💥 %s 被击倒（KO）！灭霸不触发 BAM，英雄被淘汰！" % DB.hero_name(hid), Color(0.9, 0.3, 0.3))
		state["eliminated"].append(hid)
		state["hero_ids"].erase(hid)
		# KO 的英雄被移出 hero_ids 后，current_hero 可能指向越界，需收回到有效范围
		state["current_hero"] = clampi(state["current_hero"], 0, maxi(state["hero_ids"].size() - 1, 0))
		if _check_lose():
			return
		# 玩家选择新的英雄继续游戏（从英雄池中未使用的英雄选择）；新英雄在被淘汰英雄的地点、以 KO 状态登场
		await _choose_replacement_hero(int(h["location"]))
		Events.emit_state_changed()
		return
	if state["villain"] == "cull":
		# 黑矮星特殊规则：KO 时不触发 BAM，打出另一张反派行动牌
		_log("💥 %s 被击倒（KO）！黑矮星不触发 BAM，改为打出另一张行动牌！（额外打出的那张牌若自带 BAM，仍会照常触发——那是它自己的 BAM，不是本次 KO 触发的）" % DB.hero_name(hid), Color(1, 0.5, 0.2))
		state["extra_villain_card"] += 1
		state["extra_villain_card_src"] = "%s 被击倒（KO）" % DB.hero_name(hid)
		Events.emit_state_changed()
		return
	if state["villain"] == "loki":
		# 洛基特殊规则：KO 时不触发 BAM！而是抽取一张反派行动牌，面朝下放到故事情节中
		_log("💥 %s 被击倒（KO）！洛基不触发 BAM，抽取一张反派行动牌面朝下放入故事情节！" % DB.hero_name(hid), Color(1, 0.5, 0.2))
		if state["master_deck"].size() > 0:
			var d: Variant = state["master_deck"].pop_front()
			# 若抽到无限宝石，洛基将其作为"面朝下"剧情牌收入故事情节（只展示，不结算）
			state["story"].append({"type": "villain", "villain": state["villain"], "idx": d if d is int else -1, "move": 0, "face_down": true})
			_log("洛基将一张反派行动牌背面朝上放进故事情节", Color(0.8, 0.9, 1))
		else:
			_log("洛基的牌堆已空，无法抽取", Color(1, 0.5, 0.5))
		Events.emit_state_changed()
		return
	if state.get("mode", "") == "s6":
		# 邪恶六人组共用规则：英雄被 KO 时不触发 BAM，改为抽 1 张反派行动卡面朝下放入故事情节
		_log("💥 %s 被击倒（KO）！邪恶六人组不激活 BAM，改为抽取 1 张反派行动卡面朝下放入故事情节！" % DB.hero_name(hid), Color(1, 0.5, 0.2))
		_s6_add_face_down_card("英雄被 KO")
		Events.emit_state_changed()
		return
	if state["villain"] == "kraven" or state["villain"] == "sandman" or state["villain"] == "kang":
		# 猎人克莱文 / 沙人 / 康（第一季众筹）特殊规则：KO 时不触发 BAM，打出另一张反派行动牌
		# （康的面板特别规则：当英雄被 KO 时，康不会激活他的 BAM！改为他打出另一张反派行动牌）
		_log("💥 %s 被击倒（KO）！%s 不触发 BAM，改为立刻打出另一张反派行动卡！" % [DB.hero_name(hid), DB.villain_name(state["villain"])], Color(1, 0.5, 0.2))
		state["extra_villain_card"] += 1
		state["extra_villain_card_src"] = "%s 被击倒（KO）" % DB.hero_name(hid)
		Events.emit_state_changed()
		return
	if state["villain"] == "electro":
		# 电光人特殊规则：KO 时不激活 BAM，改为在被 KO 英雄所在地点放置 1 个危机指示物
		_log("💥 %s 被击倒（KO）！电光人不激活 BAM，改为在其所在地点放置 1 个危机指示物！" % DB.hero_name(hid), Color(1, 0.5, 0.2))
		_electro_add_crisis(int(h["location"]))
		Events.emit_state_changed()
		return
	if state["villain"] == "rhino":
		# 犀牛人特殊规则①：英雄被 KO 时，犀牛人不激活他的 BAM！，改为该英雄获得 1 个危机指示物
		VillainRules._rhino_on_ko(self, hid)
		return
	_log("💥 %s 被击倒（KO）！触发反派 BAM 效果！" % DB.hero_name(hid), Color(1, 0.5, 0.2))
	await _trigger_panel_bam()
	if _check_lose():
		return
	Events.emit_state_changed()

## 灭霸淘汰后：玩家从英雄池中未使用的英雄选择一个加入游戏。
## spawn_loc 为被淘汰英雄的位置：新英雄在此地点、以 KO 状态登场，回合开始时复活。
func _choose_replacement_hero(spawn_loc: int = -1) -> void:
	var pool: Array = []
	for hid in DB.heroes.keys():
		if not state["heroes"].has(hid):
			pool.append(hid)
	if pool.size() == 0:
		_log("没有可用的替换英雄，该玩家出局", Color(1, 0.5, 0.5))
		return
	if spawn_loc < 0 or spawn_loc >= state["locations"].size():
		spawn_loc = 0
	var nhid: String = await _ask_hero("英雄被淘汰！选择一个新的英雄继续游戏", pool)
	if nhid == "" or not DB.heroes.has(nhid):
		_log("未选择替换英雄，该玩家出局", Color(1, 0.5, 0.5))
		return
	# 新英雄加入：在被淘汰英雄的地点、KO 状态登场；回合开始复活时再抽牌
	var deck: Array = []
	for i in range(DB.hero_cards(nhid).size()):
		deck.append(i)
	deck.shuffle()
	state["heroes"][nhid] = {
		"id": nhid, "deck": deck, "discard": [], "hand": [], "location": spawn_loc, "ko": true,
		"crisis": 0, "invulnerable": false, "ko_count": 0, "cartoon_web_armed": false, "miles_web_armed": false,
			"cat_redraw_armed": false, "dora_milaje": false, "martial_artist": false,
		"tokens": {"move": 0, "attack": 0, "heroic": 0, "wild": 0},
	}
	state["hero_ids"].append(nhid)
	_log("%s 加入战斗！在被淘汰英雄的地点上场（KO 状态，回合开始复活），目前 %s 名英雄" % [DB.hero_name(nhid), state["hero_ids"].size()], Color(0.6, 1, 0.8))
	Events.emit_state_changed()

func _revive_hero(hid: String) -> void:
	var h: Dictionary = state["heroes"][hid]
	if not h["ko"]:
		return
	h["ko"] = false
	h["invulnerable"] = false
	# 第二批（裁定）：这些是"本回合/直到下回合"的标志，英雄新回合开始时统一清掉
	h["astral_turn"] = false
	h["qs_carry_heroes"] = false
	h["qs_defeat_on_enter"] = false
	h["qs_rescue_on_enter"] = false
	h["dd_move_on_thug"] = false
	h["dd_move_on_rescue"] = false
	h["dd_token_on_enter"] = false
	h["ignore_first_hit"] = false
	state["dmg_uncancellable_turn"] = false
	# 兜底：英雄所在的地点若已被摧毁（章鱼博士），复活时先挪到存活环上的下一个地点，避免卡在已移出游戏的地点上
	var hl: int = int(h["location"])
	if hl >= 0 and hl < LOCATION_COUNT and state["locations"][hl].get("destroyed", false):
		var nxt: int = _next_live_loc(hl)   # 该地点已不在存活环上 → 取存活环上的下一个
		if nxt >= 0 and nxt != hl:
			h["location"] = nxt
			_log("⚠ %s 原地点已被摧毁，复活时移到相邻地点 %s" % [DB.hero_name(hid), _loc_name(nxt)], Color(1, 0.8, 0.5))
	# 官方规则：复活抽牌直到手牌 3 张，回合开始再抽 1 张（共 4 张）
	for d in range(3):
		_draw_card(hid)
	_log("%s 复活！抽 3 张手牌（回合开始再抽 1 张，共 4 张）" % DB.hero_name(hid), Color(0.6, 1, 0.8))
	Events.emit_state_changed()

# ---------------------------------------------------------------- villain turn

func _run_villain_turn(extra_only: bool = false) -> void:
	if state["phase"] == "game_over":
		return
	# 邪恶六人组模式：整套反派回合逻辑不同（6 个反派 + 16 张行动卡），单独走 _s6_run_turn
	if state.get("mode", "") == "s6":
		await _s6_run_turn()
		return
	state["phase"] = "villain"
	state["turn_count"] += 1
	state["cull_armor_used"] = false
	state["proxima_parry_used"] = false
	state["kraven_decoy_used"] = false
	# 犀牛人：面板 BAM 的伤害 = "他本回合进入的地点数量"，所以每个反派回合开始时清零重算
	# （数字移动在 _do_villain_move 里按步数累加，字典移动记 1 次）
	if state["villain"] == "rhino":
		state["rhino_moved_locs"] = 0
	_log("—— 反派回合 #%d ——" % state["turn_count"], Color(1, 0.5, 0.5))
	await _step_pause()
	# extra_only（到达效果触发的"再打出一张行动牌"）：只打额外张数，不再默认额外打 1 张正常牌。
	# 普通回合打 = extra_villain_card(结转) + 1(正常1张)。
	var pending: int = state.get("extra_villain_card", 0) + state.get("villain_extra_card_next_turn", 0) + (0 if extra_only else 1) - state.get("skip_villain_card", 0)
	# 摩多克·超级天才智能：「下一个反派回合多打出 1 张反派行动卡」在这里兑现。
	# 注意 extra_only（到达效果触发的补打）属于**同一个**反派回合，不消耗该延迟张数。
	if int(state.get("villain_extra_card_next_turn", 0)) > 0 and not extra_only:
		_log("超级天才智能：本回合反派多打出 %d 张行动卡" % int(state["villain_extra_card_next_turn"]), Color(1, 0.6, 0.5))
		state["villain_extra_card_next_turn"] = 0
	state["extra_villain_card"] = 0
	# 蜘蛛女·毒液冲击：把下一个反派回合推迟 1 张牌（少打出 1 张行动卡）
	if int(state.get("skip_villain_card", 0)) > 0:
		_log("毒液冲击：本回合反派少打出 %d 张行动卡" % int(state["skip_villain_card"]), Color(0.7, 0.9, 1))
	state["skip_villain_card"] = 0
	pending = maxi(pending, 0)
	var guard := 0
	while pending > 0:
		# 第三批·术士亚当「生命化身」（裁定1）：本回合所有反派行动卡背面朝上、无任何效果（连移动也不发生）
		if bool(state.get("villain_turn_skip", false)):
			if state["master_deck"].size() == 0:
				_lose("反派行动牌组已抽空，英雄们失败了。")
				return
			var _lv_item: Variant = state["master_deck"].pop_front()
			if _lv_item is Dictionary:
				state["master_deck"].insert(0, _lv_item)   # 宝石卡不算行动卡，原样留在牌堆顶
				state["villain_turn_skip"] = false
				continue
			state["story"].append({"type": "villain", "villain": state["villain"], "idx": -1, "move": 0, "face_down": true})
			_log("生命化身：反派打出一张行动卡（背面朝上，无任何效果）", Color(0.75, 0.85, 1))
			pending -= 1
			if pending <= 0:
				state["villain_turn_skip"] = false
			Events.emit_state_changed()
			await _step_pause()
			continue
		if state["phase"] == "game_over":
			return
		pending -= 1
		# 反派要抽牌：主计划牌堆抽空 → 英雄失败（反派完成邪恶计划）
		if state["master_deck"].size() == 0:
			_lose("反派行动牌组已抽空，英雄们失败了。")
			return
		var drawn: Variant = state["master_deck"].pop_front() if not state.get("traitor_active", false) else await _traitor_pick_card()
		# 无限宝石卡：翻出即算一个回合（等同行动牌）。
		# 只有第 4 局决战（final_battle）例外：宝石卡结算后要**再翻一张行动牌**。
		if drawn is Dictionary and drawn.has("stone"):
			var sidx: int = int(drawn["stone"])
			await _reveal_stone(sidx)
			if bool(state.get("final_battle", false)):
				pending += 1      # 决战：宝石不算这张行动牌 → 继续翻下一张
			guard += 1
			if guard > 30:
				_log("额外行动卡超出保护上限，停止", Color(1, 0.5, 0.5))
				break
			continue
		var card_idx: int = drawn
		state["master_discard"].append(card_idx)
		var vill: Dictionary = DB.villain(state["villain"])
		var card: Dictionary = vill["actions"][card_idx]
		var move_desc: String = _move_desc(card.get("move", 0))
		# 顺序：先翻牌动画，再显示移动 —— 动画期间不把这张牌的移动/效果内容写进故事区与日志
		# （避免"日志先剧透移动X、之后才翻牌"）。动画结束后才挂入故事区、写日志并执行移动。
		if not autopilot:
			await _await_villain_reveal(card_idx)
		# 猫女·猫抓 / 猫之幸运：翻牌动画播完后（_await_villain_reveal 之后）再询问是否把这张牌放牌库底并重翻一张
		var cat_armed: Array = []
		for ch in state["hero_ids"]:
			if bool(state["heroes"][ch].get("cat_redraw_armed", false)):
				cat_armed.append(ch)
		if cat_armed.size() > 0:
			var cat_redraw := false
			for ch in cat_armed:
				state["heroes"][ch]["cat_redraw_armed"] = false
				if await _ask_confirm("猫抓/猫之幸运（%s）：把「%s」放到牌堆底部，并重新翻开一张主计划卡牌？"
						% [DB.hero_name(ch), villain_action_desc(card_idx)]):
					cat_redraw = true
			if cat_redraw:
				state["master_discard"].erase(card_idx)
				state["master_deck"].append(card_idx)
				_log("猫抓/猫之幸运：把「%s」放到牌堆底部，重新翻开一张主计划卡牌" % villain_action_desc(card_idx), Color(0.8, 0.9, 1))
				guard += 1
				if guard > 30:
					_log("额外行动卡超出保护上限，停止", Color(1, 0.5, 0.5))
					break
				pending += 1
				continue
		state["story"].append({"type": "villain", "villain": state["villain"], "idx": card_idx, "move": move_desc})
		var parts: Array = [move_desc]
		if card.get("bam", false): parts.append("BAM")
		if card.get("effect", null) != null: parts.append(card["effect"]["name"])
		_log("反派行动牌：%s" % " - ".join(parts), Color(1, 0.7, 0.7))
		await _step_pause()
		# 1. 移动（数字move为普通顺时针走；Dictionary为罗南等特殊移动）
		await _do_villain_move(card.get("move", 0))
		# 立即刷新：先展示移动（动画/位置），之后才结算 BAM 的伤害（修复"先弃牌后移动"）
		Events.emit_state_changed()
		await _step_pause()
		# 3. BAM
		# 3. BAM（螳螂女·移情操控，裁定⑩：取消"下一张翻出的反派行动卡"的 BAM；
		#    移动等其它部分照常执行；效果到此结束——下一张牌翻出即失效，跨回合也保留）
		var _bam_cancelled := false
		if bool(state.get("cancel_bam_pending", false)):
			state["cancel_bam_pending"] = false
			_bam_cancelled = true
			_log("移情操控：本张反派行动卡的 BAM 被取消（移动与其它效果照常）", Color(0.8, 0.9, 1))
		if card.get("bam", false) and not _bam_cancelled:
			await _trigger_panel_bam()
			await _trigger_all_threat_bam()
			Events.emit_state_changed()
			await _step_pause()
			if _check_lose():
				return   # 秃鹫战利品收满等：BAM 阶段已判负则后续"效果/放置"不再执行
		# 4. 特殊效果（在放置之前执行）
		if card.get("effect", null) != null:
			await _resolve_villain_effect(card["effect"])
			Events.emit_state_changed()
			await _step_pause()
			if _check_lose():
				return
		# 5. 放置指示物
		if card.get("place", null) != null:
			await _do_placement(card["place"])
			Events.emit_state_changed()
			await _step_pause()
			if _check_lose():
				return
		if _check_lose():
			return
		# 结算过程中可能又加入了额外行动卡（天才智力/劝诱/黑矮星KO/灭霸威胁乌木侯）
		var extra_src: String = String(state.get("extra_villain_card_src", ""))
		pending += state.get("extra_villain_card", 0)
		state["extra_villain_card"] = 0
		state["extra_villain_card_src"] = ""
		if pending > 0:
			_log("立即打出额外反派行动卡（剩余 %d 张）%s" % [pending, ("—— 原因：" + extra_src) if extra_src != "" else ""], Color(1, 0.6, 0.5))
		guard += 1
		if guard > 30:
			_log("额外行动卡超出保护上限，停止", Color(1, 0.5, 0.5))
			break
	if _check_lose():
		return
	# 反派回合结束：只有反派"到达效果"威胁仍在反派最终停留地点，才结算到达效果
	# （若本回合中反派已离开该地点，则不再触发；避免与 BAM 伤害叠加导致重复弃牌）
	await _step_pause()
	# 康（第一季众筹）：康不在场上时他没有停留地点，不结算任何威胁"到达效果"
	if not (state["villain"] == "kang" and VillainRules.kang_off_field(self)):
		await _trigger_threat_arrival(state["villain_pos"])
	# 到达效果可能要求"反派回合结束后再进行一次反派回合"（如乌木侯劝诱-无英雄）
	if state.get("extra_villain_turn", false) and state["phase"] != "game_over":
		state["extra_villain_turn"] = false
		_log("—— 劝诱：乌木侯再进行一次反派回合 ——", Color(1, 0.6, 0.5))
		await _run_villain_turn(true)
		return
	# 到达效果也可能在到达时才加入"立即打出另一张反派行动卡"（如灭霸威胁卡 乌木侯到达：额外打出一张）
	# 此时反派回合的主循环已结束，需再执行一次反派回合才能真正"打出并结算"这张行动牌
	if state.get("extra_villain_card", 0) > 0 and state["phase"] != "game_over":
		_log("到达效果：立即再打出反派行动卡（视为灭霸再进行一个回合）", Color(1, 0.6, 0.5))
		await _run_villain_turn(true)
		return
	Events.emit_state_changed()
	_start_hero_phase()

## 动画4：反派出牌后等待 UI 弹窗展示（Board 检测 pending_villain_reveal 播放弹窗，完成后调 _villain_reveal_done）。

## 裁定 A2：反派回合结束时，未被用掉的"首次免伤"作废（不留到下一回合）
func _expire_first_hit_shields() -> void:
	var n := 0
	for hh in state["hero_ids"]:
		if bool(state["heroes"][hh].get("ignore_first_hit", false)):
			state["heroes"][hh]["ignore_first_hit"] = false
			n += 1
	if n > 0:
		_log("心灵能量场：本回合未被用掉的首次免伤已作废（%d 名英雄）" % n, Color(0.8, 0.85, 1))

func _await_villain_reveal(card_idx: int) -> void:
	state["pending_villain_reveal"] = card_idx
	Events.emit_state_changed()
	# 最多等约 4.5s（UI 弹窗 3s 展示 + 余量）；超时也继续，避免 villain 回合悬挂
	var guard := 0
	while int(state.get("pending_villain_reveal", -1)) >= 0 and guard < 90:
		await get_tree().create_timer(0.05).timeout
		guard += 1
	if int(state.get("pending_villain_reveal", -1)) >= 0:
		state["pending_villain_reveal"] = -1

## UI 展示完成后调用：清掉等待标记，让 villain 回合继续。
func _villain_reveal_done() -> void:
	if state.get("pending_villain_reveal", -1) >= 0:
		state["pending_villain_reveal"] = -1
		Events.emit_state_changed()

## 反派回合各步骤之间的间隔暂停（0.5s），让"回合开始→出牌→移动→BAM→效果→放置→到达"逐帧进行。
## autopilot（无 UI / 测试）时跳过，避免拖慢自动化。
func _step_pause() -> void:
	if autopilot:
		return
	await get_tree().create_timer(VILLAIN_STEP_DELAY).timeout

## 抽牌阶段停留：真人模式抽完牌后停留约 0.9s，让"牌背→正面"翻牌动画播完再进入可操作的英雄回合；
## 期间 phase=hero_draw，手牌等交互保持锁定。autopilot 时跳过。
func _draw_phase_pause() -> void:
	if autopilot:
		return
	await get_tree().create_timer(0.9).timeout

## 行动卡"移动"的可读描述。数字=普通顺时针走 N 步；Dictionary=罗南特殊移动。
func _move_desc(mv: Variant) -> String:
	if mv is Dictionary:
		var dir: String = "顺时针" if mv.get("dir", "cw") == "cw" else "逆时针"
		if mv.has("threat_in"):
			return "%s→下一有威胁卡地点" % dir
		var tgt: String = "有英雄" if mv.get("hero_in", true) else "没有英雄"
		return "%s→下一%s地点" % [dir, tgt]
	return "移动%d" % int(mv)

## 执行反派移动。数字=普通顺时针走 N 步；Dictionary=罗南特殊移动（顺/逆时针到下一有/无英雄地点）。
func _do_villain_move(mv: Variant) -> void:
	# 康（第一季众筹）：康不在场上（被「时间大师」移出游戏）时没有地点，任何移动都不发生
	# （他不在这张行动卡所示的任何位置上，只有「时间大师」能决定他重新从哪个地点上场）
	if state["villain"] == "kang" and VillainRules.kang_off_field(self):
		_log("康不在场上，本次移动不结算", Color(0.8, 0.8, 0.8))
		return
	# 蜘猪侠卡通蛛网：下一个反派行动时，反派不能移动
	if state.get("no_villain_move_next", false):
		state["no_villain_move_next"] = false
		_log("卡通蛛网：反派不能移动，停留原地", Color(0.7, 0.9, 1))
		return
	if mv is Dictionary:
		# 罗南特殊移动：沿指定方向找第一个满足条件的地点（从当前位置的后一个开始）
		var dir: String = mv.get("dir", "cw")
		var want_hero: bool = mv.get("hero_in", true)
		var want_threat: bool = mv.has("threat_in")
		var step_dir: int = 1 if dir == "cw" else LOCATION_COUNT - 1
		var target: int = state["villain_pos"]
		var found := false
		for s in range(1, LOCATION_COUNT + 1):
			var i: int = (state["villain_pos"] + s * step_dir) % LOCATION_COUNT
			if state["locations"][i].get("destroyed", false):
				continue   # 被摧毁的地点（章鱼博士）已移出游戏，不能停上去
			var here_heroes: int = _heroes_at(i).size()
			var ok := (here_heroes > 0) if want_hero else (here_heroes == 0)
			if want_threat:
				var lt: Variant = state["locations"][i]["threat"]
				ok = lt != null
				if mv.get("threat_in", true) == false:
					ok = lt == null
			if ok:
				target = i
				found = true
				break
		if found:
			state["villain_pos"] = target
			var dir_txt: String = "顺时针" if dir == "cw" else "逆时针"
			var tgt_txt: String = ""
			if want_threat:
				tgt_txt = "有威胁卡" if mv.get("threat_in", true) else "无威胁卡"
			else:
				tgt_txt = "有英雄" if want_hero else "没有英雄"
			_log("反派%s移动到：%s（下一%s地点）" % [dir_txt, _loc_name(target), tgt_txt], Color(0.9, 0.7, 1))
			# 犀牛人：一次字典移动 = 进入 1 个地点（面板 BAM 的伤害值要按它累加）
			if state["villain"] == "rhino":
				state["rhino_moved_locs"] = int(state.get("rhino_moved_locs", 0)) + 1
		else:
			_log("未找到符合条件的地点，反派停留原地", Color(0.9, 0.7, 1))
		return
	var mv_n: int = int(mv)
	# 负数 move 是"特殊移动"标记（如亡刃将军屠宰/刀刃攻击），移动逻辑交由对应 effect 处理，这里不做数字移动
	if mv_n < 0:
		return
	if mv_n > 0:
		# 数字移动在"存活环"上走 N 格：被摧毁的地点（章鱼博士）已被移出游戏，不能再停上去
		var cur: int = state["villain_pos"]
		var steps := 0
		for step in range(mv_n):
			var nxt: int = _next_live_loc(cur)
			if nxt < 0 or nxt == cur:
				break
			cur = nxt
			steps += 1
		state["villain_pos"] = cur
		# 犀牛人：数字移动按"实际走过的步数"累加进入过的地点数（面板 BAM 的伤害值）
		if state["villain"] == "rhino" and steps > 0:
			state["rhino_moved_locs"] = int(state.get("rhino_moved_locs", 0)) + steps
		_log("反派移动到：%s" % _loc_name(cur), Color(0.9, 0.7, 1))

## 亡刃将军特殊移动：顺时针移动到下一个"有英雄"(single=false) 或 "只有一个英雄"(single=true) 的地点。
func _corvus_move_to_next_hero(single: bool) -> bool:
	var target: int = state["villain_pos"]
	var found := false
	for s in range(1, LOCATION_COUNT + 1):
		var i: int = (state["villain_pos"] + s) % LOCATION_COUNT
		var n: int = _heroes_at(i).size()
		var ok := (n == 1) if single else (n > 0)
		if ok:
			target = i
			found = true
			break
	if found:
		state["villain_pos"] = target
		_log("亡刃将军%s移动到：%s（下一%s地点）" % ["顺时针", _loc_name(target), ("只有一个英雄" if single else "有英雄")], Color(0.9, 0.7, 1))
	else:
		_log("亡刃将军：未找到%s地点，停留原地" % ("只有一个英雄" if single else "有英雄"), Color(0.9, 0.7, 1))
	return found

func _trigger_panel_bam() -> void:
	_begin_overflow_event()   # 一次 BAM！= 一次溢出结算事件
	var vill: Dictionary = DB.villain(state["villain"])
	_log("BAM！%s：%s" % [DB.villain_name(state["villain"]), vill["bam"]], Color(1, 0.6, 0.3))
	# 反派专属 BAM 特效交给 VillainRules 处理（基础规则与反派规则分离）
	await VillainRules.on_bam(self, state["villain"])

## 完整的一次 BAM！结算 = 反派面板 BAM + 场上所有威胁卡的 BAM
## （行动卡效果里写的"然后 BAM！"用这个，和"翻出带 BAM 的行动卡"口径一致）
func _trigger_full_bam() -> void:
	await _trigger_panel_bam()
	if _check_lose():
		return
	await _trigger_all_threat_bam()

func _trigger_all_threat_bam() -> void:
	_begin_overflow_event()
	# 每轮开始重置所有威胁卡的 BAM 执行标记（避免猎人克莱文移动后在新地点被再次触发，导致 BAM 执行两次）
	for loc in range(LOCATION_COUNT):
		var lt: Variant = state["locations"][loc]["threat"]
		if lt != null:
			lt["_bam_done"] = false
	for i in range(LOCATION_COUNT):
		if state["phase"] == "game_over":
			return   # 威胁 BAM 过程中已判负：不再继续结算其余威胁卡
		var l: Dictionary = state["locations"][i]
		if l["threat"] == null or not l["threat"].get("bam", false) or l["threat"].get("_bam_done", false):
			continue
		_begin_overflow_event()   # 每张威胁卡的 BAM 各算一次结算事件
		var t: Dictionary = l["threat"]
		t["_bam_done"] = true
		_log("威胁牌 BAM（%s）：%s" % [t["name"], t["text"]], Color(1, 0.75, 0.4))
		match t["name"]:
			"奥创克隆体":
				# 卡面：该地点放置 1 个暴徒；若该地点全部英雄都选择受到 1 点伤害，则阻止此效果
				var heroes_here: Array = _heroes_at(i)
				var all_choose_damage := true
				for hid in heroes_here:
					if state["heroes"][hid]["ko"]:
						continue
					var choose: bool = await _ask_confirm("奥创克隆体：%s 选择受到 1 点伤害来阻止放置暴徒？" % DB.hero_name(hid))
					if not choose:
						all_choose_damage = false
						break
				if all_choose_damage and heroes_here.size() > 0:
					# 全部英雄（未 KO 的）都选择受伤 → 阻止放暴徒，并结算伤害
					for hid in heroes_here:
						if not state["heroes"][hid]["ko"]:
							await _deal_damage_to_hero(hid, 1)
					_log("全部英雄选择受伤，克隆体效果被阻止", Color(0.8, 0.9, 0.7))
				else:
					await _place_token_at("thug", i, 1)
			"九头蛇夫人":
				for hid in _heroes_at(i):
					await _hero_crisis_block_damage(hid, 1, 1)
			"交叉骨":
				for hid in _heroes_at(i):
					await _hero_crisis_block_damage(hid, 2, 2)
			"暗夜比邻星":
				# 灭霸威胁 BAM：丢弃此地点的所有平民；
				# 若【没有平民可丢弃】(即丢弃动作未发生)，则对 1 名英雄造成 1 点伤害（玩家选择，不限地点）
				var dropped_civ: int = l["civ"]
				l["civ"] = 0
				_log("暗夜比邻星：丢弃此地点的所有平民（%d 个）" % dropped_civ, Color(1, 0.6, 0.4))
				# 只有"没丢弃任何平民"时，后面的伤害效果才执行
				if dropped_civ == 0:
					var candidates: Array = []
					for hid in state["hero_ids"]:
						if not state["heroes"][hid]["ko"]:
							candidates.append(hid)
					if candidates.size() > 0:
						var labels: Array = []
						for hid in candidates:
							labels.append(DB.hero_name(hid))
						var picked_idx: int = await _ask("暗夜比邻星：选择 1 名英雄受到 1 点伤害（不限地点）", labels)
						await _deal_damage_to_hero(candidates[picked_idx], 1)
			"黑矮星":
				# 灭霸威胁 BAM：对该地点的每个英雄造成 1 点伤害
				for hid in _heroes_at(i):
					await _deal_damage_to_hero(hid, 1)
			"克莱文":
				# 秃鹫威胁 BAM：在此地点对 1 名英雄造成 2 点伤害（玩家选择）
				var kv_heroes: Array = _heroes_at(i).filter(func(h): return not state["heroes"][h]["ko"])
				if kv_heroes.size() == 0:
					_log("克莱文：该地点没有英雄", Color(0.8, 0.8, 0.8))
				else:
					var kv_labels: Array = []
					for h in kv_heroes:
						kv_labels.append(DB.hero_name(h))
					var kv_idx: int = await _ask("克莱文 BAM！：选择 1 名英雄受到 2 点伤害", kv_labels)
					var kv_who: String = kv_heroes[wrapi(int(kv_idx), 0, kv_heroes.size())]
					await _deal_damage_to_hero(kv_who, 2)
					_log("克莱文：%s 受到 2 点伤害" % DB.hero_name(kv_who), Color(1, 0.5, 0.4))
			"沙人":
				if state["villain"] == "docock":
					# 章鱼博士威胁 BAM：沙人获得 1 点生命值，该地点每个英雄受 1 点伤害
					t["hp"] = int(t.get("hp", 0)) + 1
					_log("沙人：获得 1 点生命值（当前 %d）" % int(t["hp"]), Color(1, 0.8, 0.4))
					for hid in _heroes_at(i):
						await _deal_damage_to_hero(hid, 1)
				else:
					# 秃鹫威胁 BAM：该地点 1 名英雄受 1 点伤害；若该地点没有英雄，则此处的 1 个战利品被收走
					var sd_heroes: Array = _heroes_at(i).filter(func(h): return not state["heroes"][h]["ko"])
					if sd_heroes.size() > 0:
						var sd_labels: Array = []
						for h in sd_heroes:
							sd_labels.append(DB.hero_name(h))
						var sd_idx: int = await _ask("沙人 BAM！：选择 1 名英雄受到 1 点伤害", sd_labels)
						var sd_who: String = sd_heroes[wrapi(int(sd_idx), 0, sd_heroes.size())]
						await _deal_damage_to_hero(sd_who, 1)
						_log("沙人：%s 受到 1 点伤害" % DB.hero_name(sd_who), Color(1, 0.6, 0.4))
					else:
						if not VillainRules._vulture_take_loot(self, i):
							_log("沙人：该地点没有英雄，也没有战利品可收", Color(0.8, 0.8, 0.8))
			"秃鹫":
				# 章鱼博士威胁 BAM：此地点 1 名英雄受 1 点伤害；然后把此威胁卡移到顺时针第一个没有威胁卡的地点
				var vh_heroes: Array = _heroes_at(i).filter(func(h): return not state["heroes"][h]["ko"])
				if vh_heroes.size() > 0:
					var vh_labels: Array = []
					for h in vh_heroes:
						vh_labels.append(DB.hero_name(h))
					var vh_idx: int = await _ask("秃鹫 BAM！：选择 1 名英雄受到 1 点伤害", vh_labels)
					await _deal_damage_to_hero(vh_heroes[wrapi(int(vh_idx), 0, vh_heroes.size())], 1)
				else:
					_log("秃鹫：该地点没有英雄", Color(0.8, 0.8, 0.8))
				var vh_dest := -1
				for step in range(1, LOCATION_COUNT + 1):
					var cand: int = (i + step) % LOCATION_COUNT
					var cl: Dictionary = state["locations"][cand]
					if cl.get("destroyed", false):
						continue
					if cl["threat"] == null:
						vh_dest = cand
						break
				if vh_dest >= 0:
					state["locations"][vh_dest]["threat"] = t
					l["threat"] = null
					_log("秃鹫：威胁卡移动到 %s（该地点原无威胁卡）" % _loc_name(vh_dest), Color(0.9, 0.8, 1))
				else:
					_log("秃鹫：没有可移动的空地点，威胁卡留在原地", Color(0.8, 0.8, 0.8))
			"神秘客":
				if state["villain"] == "docock":
					# 章鱼博士威胁 BAM：此地点 1 名英雄受 1 点伤害；并在此地点加 1 平民 + 1 暴徒
					var my_heroes: Array = _heroes_at(i).filter(func(h): return not state["heroes"][h]["ko"])
					if my_heroes.size() > 0:
						var my_labels: Array = []
						for h in my_heroes:
							my_labels.append(DB.hero_name(h))
						var my_idx: int = await _ask("神秘客 BAM！：选择 1 名英雄受到 1 点伤害", my_labels)
						await _deal_damage_to_hero(my_heroes[wrapi(int(my_idx), 0, my_heroes.size())], 1)
					await _place_token_at("civ", i, 1)
					await _place_token_at("thug", i, 1)
			"冰霜巨人":
				# 洛基威胁 BAM：对该地点的所有英雄都造成 1 点伤害
				for hid in _heroes_at(i):
					await _deal_damage_to_hero(hid, 1)
			"电光人":
				if state["villain"] == "sandman":
					# 沙人威胁 BAM：该地点每个英雄受 1 点伤害；若该地点没有英雄，则相邻地点的每个英雄受 1 点伤害
					var el_here: Array = _heroes_at(i).filter(func(h): return not state["heroes"][h]["ko"])
					if el_here.size() > 0:
						for hid in el_here:
							await _deal_damage_to_hero(hid, 1)
						_log("电光人：%s 的每个英雄受到 1 点伤害" % _loc_name(i), Color(1, 0.6, 0.4))
					else:
						for adj in _adjacent_locs(i):
							for hid in _heroes_at(adj):
								await _deal_damage_to_hero(hid, 1)
						_log("电光人：%s 没有英雄，改为相邻地点的英雄各受到 1 点伤害" % _loc_name(i), Color(1, 0.6, 0.4))
				else:
					# 绿魔威胁 BAM：对相邻地点的每位英雄造成 1 点伤害（不包括电光人所在地点）
					for adj in _adjacent_locs(i):
						for hid in _heroes_at(adj):
							await _deal_damage_to_hero(hid, 1)
					_log("电光人：相邻地点的英雄各受到 1 点伤害", Color(1, 0.6, 0.4))
			"章鱼博士":
				# 沙人威胁 BAM：此地点 1 名英雄受到 1 点伤害（玩家选择）
				var oc_heroes: Array = _heroes_at(i).filter(func(h): return not state["heroes"][h]["ko"])
				if oc_heroes.size() == 0:
					_log("章鱼博士：该地点没有英雄", Color(0.8, 0.8, 0.8))
				else:
					var oc_labels: Array = []
					for h in oc_heroes:
						oc_labels.append(DB.hero_name(h))
					var oc_idx: int = await _ask("章鱼博士 BAM！：选择 1 名英雄受到 1 点伤害", oc_labels)
					var oc_who: String = oc_heroes[wrapi(int(oc_idx), 0, oc_heroes.size())]
					await _deal_damage_to_hero(oc_who, 1)
					_log("章鱼博士：%s 受到 1 点伤害" % DB.hero_name(oc_who), Color(1, 0.6, 0.4))
			"猎人克莱文":
				# 绿魔威胁 BAM：将此威胁卡移动到顺时针下一个有英雄、且无威胁卡的地点（尽可能执行），对该地点每位英雄造成 1 点伤害
				var kk_target := -1
				for step in range(1, LOCATION_COUNT + 1):
					var kk_i: int = (i + step) % LOCATION_COUNT
					if state["locations"][kk_i]["threat"] == null and _heroes_at(kk_i).size() > 0:
						kk_target = kk_i
						break
				if kk_target >= 0:
					state["locations"][kk_target]["threat"] = t
					state["locations"][i]["threat"] = null
					t["arrival_triggered"] = true
					_log("猎人克莱文：移动到 %s" % _loc_name(kk_target), Color(1, 0.7, 0.4))
					for hid in _heroes_at(kk_target):
						await _deal_damage_to_hero(hid, 1)
				else:
					_log("猎人克莱文：没有可移动的有英雄且无威胁卡地点", Color(1, 0.6, 0.4))
			"蜥蜴人":
				# 绿魔威胁 BAM：该地点所有英雄合计承受 2 点伤害（英雄自行分配分摊）
				var heroes_here: Array = _heroes_at(i).filter(func(h): return not state["heroes"][h]["ko"])
				for dmg_idx in range(2):
					if heroes_here.size() == 0:
						break
					var hnames: Array = []
					for hh in heroes_here:
						hnames.append(DB.hero_name(hh))
					var picked: int = await _ask("蜥蜴人：第 %d 点伤害由哪个英雄承受？" % (dmg_idx + 1), hnames)
					var hid2: String = heroes_here[wrapi(int(picked), 0, heroes_here.size())]
					await _deal_damage_to_hero(hid2, 1)
			"修理师", "甲虫", "尖叫咪咪", "月石", "歌利亚":
				# 泽莫男爵 5 张带 BAM 的威胁卡（邪恶大师无 BAM）：各卡规则不同，
				# 交由 VillainRules 按卡名分发（基础引擎不写死反派卡片规则）
				await VillainRules._zemo_threat_bam(self, String(t["name"]), i)
			"活体激光", "变色龙", "斑点":
				# 摩多克 3 张带 BAM 的威胁卡（能量投射/科技共情/心灵异能无 BAM）：同样按卡名分发
				await VillainRules._modok_threat_bam(self, String(t["name"]), i)

func _hero_crisis_block_damage(hid: String, dmg: int, cost: int) -> void:
	var h: Dictionary = state["heroes"][hid]
	if h["ko"]:
		return
	if h["crisis"] >= cost:
		h["crisis"] -= cost
		_log("%s 消耗 %d 危机指示物免疫 %d 点伤害" % [DB.hero_name(hid), cost, dmg], Color(0.7, 0.9, 1))
	else:
		await _deal_damage_to_hero(hid, dmg)

## 场上是否存在指定名称的威胁牌（未清除）
func _threat_present(tname: String) -> bool:
	for l in state["locations"]:
		if l["threat"] != null and l["threat"]["name"] == tname:
			return true
	return false

# ---------------------------------------------------------------- 威胁牌"到达效果"（底层规则）
## 底层规则：所有的"反派到达地点效果"一律是 **反派停留在该地点、且其行动全部完成后** 才执行。
## 由 _run_villain_turn 在反派回合结束时、反派最终停留位置调用本函数；若反派当回合离开了该地点则不触发。
## 无特殊情况（不因某角色单独改写）。到达效果只在该威胁第一次停驻时触发一次（避免停留时每回合重复触发）。
func _trigger_threat_arrival(loc: int) -> void:
	var l: Dictionary = state["locations"][loc]
	if l["threat"] == null or not l["threat"].get("arrival", false):
		return
	_begin_overflow_event()   # 每张威胁卡的"到达效果"各算一次结算事件
	var t: Dictionary = l["threat"]
	# 到达效果只在"反派第一次停驻在此"时触发一次，避免反派停留时每回合重复触发（如劝诱无限加回合）
	if t.get("arrival_triggered", false):
		return
	t["arrival_triggered"] = true
	_log("反派抵达 %s，威胁牌触发（%s）：%s" % [_loc_name(loc), t["name"], t["text"]], Color(1, 0.8, 0.4))
	match t["name"]:
		"复制":
			await _place_token_at("thug", loc, 1)
		"洗脑":
			for hid in state["hero_ids"]:
				var hl: int = state["heroes"][hid]["location"]
				if hl == loc or _ring_dist(hl, loc) == 1:
					state["heroes"][hid]["crisis"] += 1
			_log("该地点及相邻地点的英雄各获得 1 危机指示物", Color(0.7, 0.7, 1))
		"颠覆":
			var discarded: int = l["civ"] + l["thug"]
			l["civ"] = 0
			l["thug"] = 0
			state["fear"] = mini(state["fear"] + discarded, 20)
			_log("弃置 %d 个指示物，恐惧轨道 +%d（当前 %d）" % [discarded, discarded, state["fear"]], Color(0.9, 0.6, 0.6))
		"亡刃将军":
			await _place_token_at("thug", loc, 2)
		"乌木侯":
			# 灭霸威胁：执行当前反派行动后，立即打出另一张反派行动卡
			state["extra_villain_card"] += 1
			_log("乌木侯：本回合将额外打出 1 张反派行动卡", Color(1, 0.6, 0.5))
		"冲锋":
			for hid in _heroes_at(loc):
				await _deal_damage_to_hero(hid, 1)
		"手雷轰炸":
			# 秃鹫威胁到达：此地点的每个英雄受到 2 点伤害
			for hid in _heroes_at(loc):
				await _deal_damage_to_hero(hid, 2)
			_log("手雷轰炸：%s 的每个英雄受到 2 点伤害" % _loc_name(loc), Color(1, 0.5, 0.4))
		"充能":
			# 电光人威胁到达：电光人获得 3 点生命值（可以超过初始值）
			state["villain_hp"] = int(state["villain_hp"]) + 3
			_log("充能：电光人获得 3 点生命值（当前 %d）" % int(state["villain_hp"]), Color(1, 0.85, 0.4))
			Events.emit_state_changed()
		"力量过载":
			# 电光人威胁到达：解决当前反派行动卡后，再打出一张反派行动卡
			state["extra_villain_card"] += 1
			_log("力量过载：本回合将额外打出 1 张反派行动卡", Color(1, 0.6, 0.5))
		"劝诱":
			var heroes_here: Array = _heroes_at(loc)
			if heroes_here.size() > 0:
				for hid in heroes_here:
					state["heroes"][hid]["crisis"] += 1
				_log("劝诱：该地点的英雄各获得 1 危机指示物", Color(0.7, 0.7, 1))
			else:
				# 该地点无英雄：乌木侯在**当前反派回合结束后**再进行一次完整的反派回合
				state["extra_villain_turn"] = true
				_log("劝诱：该地点无英雄，乌木侯将在反派回合结束后再进行一次反派回合", Color(1, 0.6, 0.5))
		"念力":
			var targets: Array = [loc] + _adjacent_locs(loc)
			for hid in state["hero_ids"]:
				var hl: int = state["heroes"][hid]["location"]
				if targets.has(hl):
					await _deal_damage_to_hero(hid, 1)
		"能量投射", "科技共情":
			# 摩多克 2 张"到达地点效果"威胁卡（各卡规则不同，交由 VillainRules 按卡名分发）
			await VillainRules._modok_threat_arrival(self, String(t["name"]), loc)
		"武器走私":
			# 到达地点效果：若该地点有空位（民+暴 < 槽位），放 1 个危机指示物；
			# 若全满，则将最左边的平民/暴徒替换为危机指示物。
			var slots: int = int(DB.location(l["id"])["slots"])
			if l["civ"] + l["thug"] < slots:
				l["crisis"] += 1
				_log("武器走私：%s 在空位放置 1 个危机指示物（危机 %d）" % [_loc_name(loc), l["crisis"]], Color(0.8, 0.6, 1))
			else:
				VillainRules._km_replace_leftmost(self, loc)
		"身陷险境的平民":
			# 到达效果：丢弃此地点的所有平民指示物；若丢弃任意数量，亡刃将军再打出一张反派行动牌。
			var cv_discarded: int = l["civ"]
			l["civ"] = 0
			if cv_discarded > 0:
				state["extra_villain_card"] += 1
				_log("身陷险境的平民：丢弃 %d 个平民，亡刃将军额外打出 1 张反派行动牌" % cv_discarded, Color(1, 0.7, 0.4))
			else:
				_log("身陷险境的平民：本地点没有平民可丢弃", Color(0.9, 0.8, 0.8))
	await _step_pause()

## 绿魔：从威胁牌堆抽一张威胁卡，沿顺时针（从 loc 起）放到第一个无威胁卡的地点；若有"放置暴徒"则放置。若牌堆空则提示。
func _goblin_place_threat_from_deck(loc: int) -> void:
	var deck: Array = state.get("goblin_threat_deck", [])
	if deck.size() == 0:
		_log("绿魔的威胁牌堆已空，无法放置威胁卡", Color(1, 0.5, 0.5))
		return
	# 找顺时针第一个无威胁卡的地点
	var target := -1
	for s in range(1, LOCATION_COUNT + 1):
		var i: int = (loc + s) % LOCATION_COUNT
		if state["locations"][i]["threat"] == null:
			target = i
			break
	if target < 0:
		_log("绿魔：没有空地点可放置威胁卡", Color(1, 0.5, 0.5))
		return
	var t: Dictionary = deck.pop_front()
	t["hp"] = t.get("henchman_hp", 0)
	t["heroic_tokens"] = 0
	t["arrival_triggered"] = false
	if t.has("clear"):
		t["clear_progress"] = []
	state["locations"][target]["threat"] = t
	_log("绿魔放置威胁卡：%s（%s）" % [t["name"], _loc_name(target)], Color(1, 0.75, 0.4))
	# 放置型威胁（企业爪牙）：放置时在此地点添加 1 个暴徒
	if t.get("place_thug_on_setup", false):
		await _place_token_at("thug", target, 1)
	Events.emit_state_changed()

func _do_placement(place: Array) -> void:
	# 康（第一季众筹）：康不在场上时，面板 BAM 已经"在每个位置添加 1 个暴徒"，
	# 并明确"不要添加这张反派行动卡上指示的所有需要添加的平民/暴徒" → 本张行动卡的放置图案整张不结算。
	if VillainRules.kang_skip_placement(self):
		_log("康不在场上：不结算这张行动卡所示的添加平民/暴徒", Color(0.8, 0.8, 0.8))
		return
	_begin_overflow_event()   # 一张行动卡的"放置"算一次结算事件
	var vpos: int = state["villain_pos"]
	var _vadj: Array = _adjacent_locs(vpos)
	var slots: Array = [place[0], place[1], place[2]]
	var slot_locs: Array = [int(_vadj[0]) if _vadj.size() > 0 else vpos, vpos, int(_vadj[1]) if _vadj.size() > 1 else vpos]
	# 同一张卡在同一地点放置的指示物合并成**一次放置事件**：
	# 溢出按"该地点 1 个或多个放不下 → 只结算一次"处理（不再一个指示物结算一次）
	var order: Array = []
	var per_loc: Dictionary = {}
	for s in range(3):
		var l0: int = int(slot_locs[s])
		if not per_loc.has(l0):
			per_loc[l0] = []
			order.append(l0)
		var kinds0: Array = per_loc[l0]
		for t in slots[s]:
			kinds0.append(t)
	for l0 in order:
		if state["phase"] == "game_over":
			return   # 已判负/结束：不再继续放置
		await _place_mixed_tokens(int(l0), per_loc[l0])

func _place_token_at(kind: String, loc: int, count: int) -> void:
	# 第三批·仿声鸟「间谍大师」：下一个反派回合，反派不能在该英雄所在地点添加平民/暴徒
	if String(state.get("phase", "")) == "villain":
		for _sm_w in state["hero_ids"]:
			var _sm: Dictionary = state["heroes"][String(_sm_w)]
			if bool(_sm.get("spy_master_armed", false)) and int(_sm.get("spy_master_loc", -1)) == loc:
				_log("间谍大师：反派无法在 %s 添加指示物" % _loc_name(loc), Color(0.8, 0.9, 1))
				return
	var kinds: Array = []
	for c in range(count):
		kinds.append(kind)
	await _place_mixed_tokens(loc, kinds)

## 某反派的弱点卡是否还能用该符号填一格
func _s6_can_fill(vid: String, sym: String) -> bool:
	var v: Dictionary = _s6()["vills"][vid]
	if bool(v.get("weak_done", false)):
		return false
	var syms: Array = v["weak_syms"]
	var filled: Array = v["weak_filled"]
	for i in range(syms.size()):
		var done: bool = i < filled.size() and int(filled[i]) == 1
		if not done and String(syms[i]) == sym:
			return true
	return false

## 该反派弱点卡当前还需要的符号（用于提示为什么这个行动化解不了）
func _s6_weak_need_text(vid: String) -> String:
	var v: Dictionary = _s6()["vills"][vid]
	var syms: Array = v["weak_syms"]
	var filled: Array = v["weak_filled"]
	var need: Array = []
	for i in range(syms.size()):
		var done: bool = i < filled.size() and int(filled[i]) == 1
		if not done:
			need.append(DB.symbol_name(String(syms[i])))
	return "/".join(need) if need.size() > 0 else "已完成"

## 邪恶六人组：同一地点有多个反派时，让玩家选一个来化解弱点卡（返回 "" 表示取消）
func _s6_pick_weak_villain(hid: String, sym: String) -> String:
	var cands: Array = _s6_weak_candidates(hid)
	if cands.size() == 1 and not _s6_can_fill(cands[0], sym):
		Events.emit_toast("%s 的弱点卡现在需要：%s（本行动无法化解）" % [DB.villain_name(String(cands[0])), _s6_weak_need_text(String(cands[0]))])
		return ""
	cands = cands.filter(func(v): return _s6_can_fill(String(v), sym))
	if cands.size() == 0:
		return ""
	if cands.size() == 1:
		return String(cands[0])
	var rows2: Array = []
	for vid in cands:
		var v: Dictionary = _s6()["vills"][vid]
		var filled := 0
		for f in (v["weak_filled"] as Array):
			if int(f) == 1:
				filled += 1
		rows2.append({"icon": sym, "img": "res://assets/cards/s6/weak_%02d.png" % int(DB.s6["weak"][vid]["img"]),
			"text": "化解 %s 的弱点卡（%d/3）" % [DB.villain_name(String(vid)), filled], "card": "threat"})
	rows2.append({"text": "取消"})
	var pick: int = int(await _ask_action("化解弱点卡：选择要化解哪个反派的弱点卡", rows2))
	if pick < 0 or pick >= cands.size():
		return ""
	return String(cands[pick])

## 在指定地点放置一串指示物（kinds 为 "civ"/"thug" 序列）。
## 本次"放置事件"内该地点的溢出**只结算一次**，但会把放不下的总数传给反派规则
## （红骷髅=推进对应数量、模仿大师=等量危机、暗夜比邻星=每平民+1 屠宰、罗南=每个 1 点伤害）。
func _place_mixed_tokens(loc: int, kinds: Array) -> void:
	if state["phase"] == "game_over":
		return   # 已判负：不再放置（战利品溢出判负后立即停止剩余放置）
	if state["locations"][loc].get("destroyed", false):
		return   # 地点已被摧毁（章鱼博士）：不可再放置，也不触发溢出
	var fails := {"civ": 0, "thug": 0}
	for k in kinds:
		var l: Dictionary = state["locations"][loc]
		var slots_total: int = int(DB.location(l["id"])["slots"])
		# 基尔格蒙：危机指示物占槽位（相当于占据民/暴槽位，使可用槽位-1）；其他反派危机不占槽
		var occupied: int = l["civ"] + l["thug"] + (l["crisis"] if state["villain"] == "kilmonger" else 0)
		if occupied < slots_total:
			if k == "thug": l["thug"] += 1
			else: l["civ"] += 1
			_log("在 %s 放置 1 个%s" % [_loc_name(loc), "暴徒" if k == "thug" else "平民"], Color(0.9, 0.9, 0.9))
		else:
			fails[k] = int(fails.get(k, 0)) + 1
		# 每次放置立即刷新 UI，让指示物逐格/逐地点同步出现（否则会全部放完后才一次性更新）
		Events.emit_state_changed()
		await _step_pause()
	var total: int = int(fails["civ"]) + int(fails["thug"])
	if total == 0:
		return
	# 同一次"结算事件"（一次 BAM！／一张卡的一次效果／一次放置）在同一地点**只结算一次溢出**。
	# 除非卡面明确写"每个无法放置的指示物都要结算"（红骷髅/模仿大师/暗夜比邻星/罗南按数量），
	# 否则默认只结算一次——反派 BAM、爪牙 BAM、威胁卡 BAM、卡牌效果全部同一口径。
	if bool(_overflow_event_locs.get(loc, false)):
		_log("溢出：%s 在本次结算中已结算过溢出，不再重复（本次放不下 %d 个）" % [_loc_name(loc), total], Color(0.8, 0.8, 0.8))
		return
	_overflow_event_locs[loc] = true
	# 混合放置时取放不下较多的那种作为"主类型"（红骷髅/模仿大师等只看数量）
	var kind: String = "thug" if int(fails["thug"]) >= int(fails["civ"]) else "civ"
	# 濒危地点模式：反派在这位玩家守护的地点溢出时，该玩家英雄受 1 点伤害（每次溢出事件一次）
	if state["challenge"] == "endangered" and state.get("endangered", {}).size() > 0:
		for hid in state["hero_ids"]:
			if state["endangered"].get(hid, -1) == loc:
				_log("🏠 濒危地点！%s 守护的地点被撑爆，受到 1 点伤害" % DB.hero_name(hid), Color(1, 0.5, 0.5))
				await _deal_damage_to_hero(hid, 1)
	await _overflow_token(kind, loc, total)

## 开始一次新的"溢出结算事件"：一次 BAM！／一张卡的一次效果／一次放置都算一次结算。
## 每次结算在同一地点最多只结算一次溢出（除非卡面按数量结算）。
func _begin_overflow_event() -> void:
	_overflow_event_locs = {}

func _overflow_token(kind: String, loc: int, count: int = 1) -> void:
	# 反派专属溢出处理交给 VillainRules（基础规则与反派规则分离）；
	# count = 本次放置事件在该地点放不下的指示物总数
	state["overflow_settled"] = int(state.get("overflow_settled", 0)) + 1
	var settled_locs: Array = state.get("overflow_settled_locs", [])
	settled_locs.append(loc)
	state["overflow_settled_locs"] = settled_locs
	await VillainRules.on_overflow(self, state["villain"], kind, loc, count)

func _resolve_villain_effect(eff: Dictionary) -> void:
	_begin_overflow_event()   # 一张行动卡的"特殊效果"算一次结算事件
	# 反派专属特殊效果交给 VillainRules（基础规则与反派规则分离）
	await VillainRules.resolve_effect(self, eff)

## 净化/狩猎长矛共用：丢弃指定地点的所有平民并增加屠宰轨道；英雄可选受1伤保留1平民（可多次）
func _discard_civs_with_choice(locs: Array) -> void:
	var total := 0
	for loc in locs:
		total += state["locations"][loc]["civ"]
	if total == 0:
		_log("没有平民被丢弃", Color(0.8, 0.8, 0.8))
		return
	for loc in locs:
		# 决策次数 = 该地点初始平民数（保留/丢弃各算一次），避免保留时 civ 不减导致循环多跑
		var decisions: int = state["locations"][loc]["civ"]
		for k in range(decisions):
			if state["locations"][loc]["civ"] <= 0:
				break
			var heroes_here: Array = []
			for hid in _heroes_at(loc):
				if not state["heroes"][hid]["ko"]:
					heroes_here.append(hid)
			var kept := false
			if heroes_here.size() > 0:
				# 玩家选择"由哪个英雄承受 1 点伤害来保留这个平民"；也可选择弃置平民。
				# 每个平民单独决策。若仅一个英雄，仍让其确认是否用它承受伤害。
				var labels: Array = []
				for hid in heroes_here:
					labels.append("%s（承受1伤保平民）" % DB.hero_name(hid))
				labels.append("❌ 弃置这个平民")
				var picked_idx: int = await _ask("%s：选择哪个英雄承受 1 点伤害来保留 1 个平民？（%s 剩余 %d 个平民）" % [_loc_name(loc), DB.hero_name(heroes_here[0]), state["locations"][loc]["civ"]], labels)
				if picked_idx >= 0 and picked_idx < heroes_here.size():
					await _deal_damage_to_hero(heroes_here[picked_idx], 1)
					kept = true
			if not kept:
				state["locations"][loc]["civ"] -= 1
				total -= 1
				state["slaughter"] = mini(state["slaughter"] + 1, 12)
			Events.emit_state_changed()
	state["slaughter"] = mini(state["slaughter"] + 0, 12)
	_log("净化/狩猎：屠宰轨道当前 %d / 12" % state["slaughter"], Color(0.9, 0.5, 0.5))

func _count_last_hero_symbols(sym: String) -> int:
	var count := 0
	var found := 0
	for i in range(state["story"].size() - 1, -1, -1):
		var entry: Dictionary = state["story"][i]
		if entry["type"] == "hero":
			# 面朝下的英雄行动牌不计（无效果/无行动）
			if entry.get("face_down", false):
				continue
			for s in DB.hero_cards(entry["hero"])[entry["idx"]]["symbols"]:
				if s == sym:
					count += 1
			found += 1
			if found >= 2:
				break
	return count

# ---------------------------------------------------------------- hero turn

func _start_hero_phase() -> void:
	if state["phase"] == "game_over":
		return
	# 裁定 A2：反派回合（含"再进行一次反派回合"的连锁）结束后，未被用掉的"首次免伤"作废。
	# 这里是反派阶段 → 英雄阶段的唯一出口（_run_villain_turn 与 _s6_run_turn 都走这里），
	# 放在这里能覆盖所有结束时点（含到达效果结算之后），且不会误伤英雄回合内新获得的标志。
	_expire_first_hit_shields()
	state["hero_cards_played"] = 0
	if state["mode"] == "shield":
		# 神盾局：无英雄轮流，直接进入下一回合（抽 1 打 1）
		_start_hero_turn()
		return
	# 开局（第一个反派回合后）从英雄 0 开始；之后从当前英雄的下一位继续，
	# 避免英雄数量多于节奏数时后面的英雄回合被跳过（如 3 英雄、节奏 2）
	if state["turn_count"] <= 1:
		state["current_hero"] = 0
	else:
		state["current_hero"] = (state["current_hero"] + 1) % state["hero_ids"].size()
	_start_hero_turn()

func _start_hero_turn() -> void:
	if state["phase"] == "game_over":
		return
	# 泽莫男爵（裁定③）：卡面写"可在同一回合内被玩家使用 N 个英勇行动击败"的威胁卡，
	# 必须同一个英雄回合内凑够 N 个英勇；新英雄回合开始 → 未凑满的进度清空重来。
	# （放在最前面：神盾局单一回合模式同样适用）
	_reset_same_turn_threats()
	# 每回合重置英雄效果临时旗标
	state["gamora_fury"] = false
	state["token_double"] = false
	state["gamora_bonus"] = 0   # 卡魔拉斩击：当前可用的"bonus攻击"数（不触发斩击）
	state["dmg_uncancellable_turn"] = false   # 惩罚者·精准射击："本回合伤害不可取消"必须随回合结束（原先只在 KO 复活时清 → 会整局生效）
	if state["mode"] == "shield":
		# 神盾局单人：每回合抽 1 张到共享手牌，然后打出任意一张（该英雄行动）
		state["phase"] = "hero_draw"
		if state["shield_deck"].size() == 0 and state["shield_hand"].size() == 0:
			_lose("共享牌组已抽空，英雄们失败了。")
			return
		_log("—— 神盾局回合：抽 1 张，打出任意一张 ——", Color(0.6, 0.9, 1))
		_draw_card(state["hero_ids"][0])
		# 抽牌阶段：先刷新并播放抽牌翻牌（phase=hero_draw，交互锁定），再进入可操作回合
		Events.emit_state_changed()
		await _draw_phase_pause()
		state["virus_ignore"] = false
		state["phase"] = "hero_play"
		Events.emit_state_changed()
		return
	var hid: String = state["hero_ids"][state["current_hero"]]
	var h: Dictionary = state["heroes"][hid]
	state["phase"] = "hero_draw"
	if h["ko"]:
		_revive_hero(hid)
	else:
		h["invulnerable"] = false
		h["protect_last_card"] = false   # 蜘猪侠卡通精髓：下回合开始清除"最后一张牌不可弃置"
		h["cartoon_web_armed"] = false   # 蜘猪侠卡通蛛网：下回合开始清除待触发标记
		h["miles_web_armed"] = false   # 迈尔斯蛛网：下回合开始清除待触发标记
		# 第一季众筹：这些效果都是"直到你下回合开始"，在本人回合开始时清除
		h["cat_redraw_armed"] = false    # 猫女·猫抓/猫之幸运：下一次反派翻行动卡时的待触发标记
		h["dora_milaje"] = false         # 奥克耶·多拉·米拉杰：为同地点英雄承伤
		h["martial_artist"] = false      # 鹰眼·武术家：把受到的伤害转移给同地点敌人
		h["ignore_reduction"] = false    # 蜘蛛侠2099·利爪：本回合造成的伤害无法被降低
		# 第二批（A1 修正）：这些也是"本回合"标志，必须**在本人回合开始时**清掉，
		# 否则打出一张后整局一直生效（原先只在 KO 复活时清）。
		h["astral_turn"] = false         # 螳螂女·星体投射
		h["moon_suit"] = false                # 第三批·月光骑士战衣（每次受伤可无视并移动，直到自己回合开始）
		h["hunter_skill"] = false             # 第三批·刀锋战士·猎人技巧
		h["elastic_extension"] = false        # 第三批·惊奇女士·弹性延伸
		h["appearance_change"] = false        # 第三批·惊奇女士·外观改造
		h["attack_locked_turn"] = false       # 第三批·霍华德鸭·中子分解器
		h["spy_master_armed"] = false         # 第三批·仿声鸟·间谍大师
		h["spy_master_loc"] = -1
		h["qs_carry_heroes"] = false     # 快银·超人速度
		h["qs_defeat_on_enter"] = false  # 快银·速度格斗
		h["qs_rescue_on_enter"] = false  # 快银·奔赴救援
		h["dd_move_on_thug"] = false     # 夜魔侠·盲眼正义
		h["dd_move_on_rescue"] = false   # 夜魔侠·无畏之人
		h["dd_token_on_enter"] = false   # 夜魔侠·雷达感官
	state["ql_busy"] = false             # 蚁人·量子跃迁：每回合最多跃迁一次
	# 秘密身份挑战：身份已暴露 → 本回合必须背面打出英雄卡；英雄回合序号 +1（每人每回合最多 1 个曝光）
	state["hero_turn_seq"] = int(state.get("hero_turn_seq", 0)) + 1
	if state.get("challenge", "") == "secretid" and bool(h.get("exposed_face_down", false)):
		state["forced_face_down_hero"] = hid
		_log("🎭 身份已暴露：%s 本回合必须把英雄卡背面朝下打出（该卡无效果，但仍继承上一张卡的符号）" % DB.hero_name(hid), Color(1, 0.6, 0.5))
	if h["hand"].size() == 0 and h["deck"].size() == 0 and h["discard"].size() == 0:
		_lose("%s 回合开始无手牌无牌库，英雄们失败了。" % DB.hero_name(hid))
		return
	_log("—— %s 的回合 ——" % DB.hero_name(hid), Color(0.6, 0.9, 1))
	await _step_pause()
	_draw_card(hid)
	# 抽牌阶段：先刷新并播放抽牌翻牌（phase=hero_draw，手牌交互锁定），再进入可操作回合
	Events.emit_state_changed()
	await _draw_phase_pause()
	state["iw_space_ignored"] = false
	var l: Dictionary = state["locations"][h["location"]]
	var virus := false
	# 折磨摧残（乌木侯威胁）：在此地点开始回合的英雄不会从故事情节中的前一张英雄卡中获得行动
	state["no_prev_symbols"] = false
	if l["threat"] != null and l["threat"].get("start_turn", false) and l["threat"]["name"] != "太空伏击" and l["threat"]["name"] != "心灵异能":
		state["no_prev_symbols"] = true
		_log("折磨摧残：%s 本回合不会获得上一张英雄卡的符号" % DB.hero_name(hid), Color(1, 0.8, 0.4))
	if l["threat"] != null and l["threat"].get("start_turn", false) and l["threat"]["name"] != "折磨摧残" and l["threat"]["name"] != "太空伏击" and l["threat"]["name"] != "心灵异能":
		virus = true
		_log("奥创病毒：%s 必须选择一个行动符号并忽略它" % DB.hero_name(hid), Color(1, 0.8, 0.4))
	# 摩多克·心灵异能（威胁卡）：在此地点开始回合的英雄必须把英雄卡面朝下打出
	# （面朝下的卡视为空白：不会从自己的牌上获得任何行动，但仍继承上一张英雄卡的符号）
	if l["threat"] != null and String(l["threat"]["name"]) == "心灵异能" and String(state["villain"]) == "modok":
		state["forced_face_down_hero"] = hid
		_log("心灵异能：%s 本回合必须面朝下打出英雄卡（不会从自己的牌获得行动）" % DB.hero_name(hid), Color(1, 0.8, 0.4))
	# 犀牛人特殊规则②：身上有任何危机指示物的英雄，本回合打牌必须正面朝下
	# （回合结束时丢弃这些危机指示物，见 VillainRules._rhino_on_hero_end_turn）
	if String(state["villain"]) == "rhino":
		VillainRules._rhino_start_turn(self, hid)
	# 罗南·太空伏击：在此地点开始回合的英雄受到 1 点伤害
	if l["threat"] != null and l["threat"]["name"] == "太空伏击" and not h["ko"]:
		_log("太空伏击：%s 开始回合受到 1 点伤害" % DB.hero_name(hid), Color(1, 0.6, 0.4))
		await _deal_damage_to_hero(hid, 1)
	if l["threat"] != null and l["threat"]["name"] == "九头蛇特工鲍勃":
		h["crisis"] += 1
		_log("%s 获得 1 危机指示物（鲍勃）" % DB.hero_name(hid), Color(0.7, 0.7, 1))
	# 乌木侯特殊规则：拥有任何危机指示物的英雄必须在回合中改为随机打出英雄卡，然后丢弃 1 个危机指示物
	# 心灵宝石（决战）：从现在开始英雄们随机打出卡牌
	state["random_play"] = (state["villain"] == "ebony" and h["crisis"] > 0) or state.get("iw_mind_active", false)
	# 邪恶六人组·神秘客（未被击败时）：身上有危机指示物的英雄必须随机出牌（出牌后丢弃 1 个危机指示物）
	if state.get("mode", "") == "s6" and not bool(_s6()["vills"]["mysterio"]["defeated"]) and int(h["crisis"]) > 0:
		state["random_play"] = true
	if state["random_play"]:
		if state.get("iw_mind_active", false):
			_log("心灵宝石：%s 本回合随机打出卡牌" % DB.hero_name(hid), Color(1, 0.7, 0.9))
		else:
			_log("乌木侯：%s 拥有危机指示物，本回合将随机打出英雄卡，并丢弃 1 个危机指示物" % DB.hero_name(hid), Color(1, 0.7, 0.5))
	state["virus_ignore"] = virus
	state["phase"] = "hero_play"
	Events.emit_state_changed()

## 秘密身份挑战：身份暴露后本回合强制背面出牌（该卡无效果，但仍可享用故事区上一张英雄卡的符号）
func _play_forced_face_down(hid: String, hand_idx: int) -> void:
	var h: Dictionary = state["heroes"][hid]
	if hand_idx < 0 or hand_idx >= h["hand"].size():
		return
	var card_idx: int = h["hand"][hand_idx]
	h["hand"].remove_at(hand_idx)
	h["discard"].append(card_idx)
	var prev_syms: Array = []
	if not state.get("no_prev_symbols", false):
		prev_syms = _last_hero_card_symbols()   # 仍继承故事区上一张英雄卡的符号加成
	state["story"].append({"type": "hero", "hero": hid, "idx": card_idx, "face_down": true})
	state["hero_cards_played"] += 1
	state["action_symbols"] = prev_syms.duplicate()
	state["prev_hero_symbols"] = prev_syms.duplicate()
	state["used_tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
	state["effect_available"] = false
	state["effect_used"] = false
	state["played_effect"] = null
	state["forced_face_down_hero"] = ""
	h["exposed_face_down"] = false
	state["phase"] = "hero_actions"
	_log("🎭 身份暴露：%s 将英雄卡背面朝下打出（本回合无卡牌效果，继承上一张卡的 %d 个符号）"
		% [DB.hero_name(hid), prev_syms.size()], Color(1, 0.7, 0.6))
	if prev_syms.size() == 0:
		Events.emit_toast("身份暴露：本回合背面出牌，且故事区没有可继承符号")
	Events.emit_state_changed()

## 打出一张手牌（hand_idx 为手牌下标；神盾局模式为共享手牌下标）
func play_card(hand_idx: int) -> void:
	if _net_gate("play_card", [hand_idx]):
		return
	if state["phase"] != "hero_play":
		return
	var hid: String = state["hero_ids"][state["current_hero"]]
	var h: Dictionary = state["heroes"][hid]
	# 秘密身份挑战（身份已暴露）/ 摩多克·心灵异能（威胁卡）：本回合打出的牌一律背面朝下
	# （无效果，但继承上一张英雄卡的符号；心灵异能的口径即"不会从自己的牌获得行动"）
	if String(state.get("forced_face_down_hero", "")) == hid:
		await _play_forced_face_down(hid, hand_idx)
		return
	var card_idx: int
	if state["mode"] == "shield":
		# 神盾局：共享手牌，打出哪张卡该卡所属英雄就行动
		if hand_idx < 0 or hand_idx >= state["shield_hand"].size():
			return
		var card: Dictionary = state["shield_hand"][hand_idx]
		state["shield_hand"].remove_at(hand_idx)
		hid = card["hero"]
		card_idx = card["idx"]
		state["current_hero"] = state["hero_ids"].find(hid)
		h = state["heroes"][hid]
	else:
		if hand_idx < 0 or hand_idx >= h["hand"].size():
			return
		# 通用"随机出牌"（如乌木侯控制 / 邪恶六人组的神秘客）：忽略点击下标，随机选一张打出
		if state.get("random_play", false):
			var drop_c: bool = (state["villain"] == "ebony") or (state.get("mode", "") == "s6" and not bool(_s6()["vills"]["mysterio"]["defeated"]))
			card_idx = _pick_random_hand_card(hid, drop_c)
		else:
			card_idx = h["hand"][hand_idx]
			h["hand"].remove_at(hand_idx)
			h["discard"].append(card_idx)
	state["story"].append({"type": "hero", "hero": hid, "idx": card_idx})
	_check_hyper_awareness()   # 第三批·松鼠女·非常感知：故事情节变化后持续检查

	# 电光人·消失：本张牌之后若每个英雄都打出过牌，则解除电光人的免伤
	if state["villain"] == "electro" and state.get("electro_vanish", false):
		_electro_check_vanish()
	state["hero_cards_played"] += 1
	var cards: Array = DB.hero_cards(hid)
	_log("%s 打出卡牌：%s" % [DB.hero_name(hid), _card_desc(hid, card_idx)], Color(0.8, 0.9, 1))
	state["action_symbols"] = cards[card_idx]["symbols"].duplicate()
	# 折磨摧残（乌木侯威胁）：此地点开始回合的英雄不从上一张英雄卡获得行动
	if state.get("no_prev_symbols", false):
		state["prev_hero_symbols"] = []
	else:
		state["prev_hero_symbols"] = _last_hero_card_symbols()
	state["action_symbols"].append_array(state["prev_hero_symbols"])
	state["used_tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
	var peff: Variant = cards[card_idx].get("effect", null)
	# 卡通蛛网（蜘猪侠）/ 迈尔斯蛛网（迈尔斯）是被动效果：打出即标记"待触发"，不占效果按钮（结束回合时自动生效）
	var peff_type: String = peff.get("type", "") if peff != null else ""
	match peff_type:
		"cartoon_web":
			state["heroes"][hid]["cartoon_web_armed"] = true
			_log("卡通蛛网：已标记，若在反派所在地点结束回合则取消下一次反派移动", Color(1, 0.85, 0.4))
			state["effect_available"] = false
		"miles_web":
			state["heroes"][hid]["miles_web_armed"] = true
			_log("迈尔斯蛛网：已标记，若在反派所在地点结束回合则推迟反派下一个回合", Color(0.7, 0.9, 1))
			state["effect_available"] = false
		_:
			state["effect_available"] = peff != null
	state["effect_used"] = false
	state["played_effect"] = peff
	state["phase"] = "hero_actions"
	# 无限战争决战：结算能量卡效果（每凑齐 cost → 获得 gain；产出行动不能用于解锁/触发其他能量卡）
	# 灭霸作为非无限战争 Boss 时同样生效（已激活能量卡）
	if state.get("mode", "base") == "iw" or (state["villain"] == "thanos" and state.get("mode", "base") != "iw"):
		_resolve_energy_activation()
	Events.emit_state_changed()

# ---------------------------------------------------------------- 通用随机出牌（底层规则）
## 随机从当前英雄手牌挑一张打出并加入弃牌堆。drop_crisis 为真时丢弃 1 个危机指示物（乌木侯规则用）。
## 返回打出的卡索引。供任意"受控/随机出牌"场景复用（不绑死乌木侯）。
func _pick_random_hand_card(hid: String, drop_crisis: bool) -> int:
	var h: Dictionary = state["heroes"][hid]
	if h["hand"].size() == 0:
		return -1
	var ridx: int = randi_range(0, h["hand"].size() - 1)
	var card_idx: int = h["hand"][ridx]
	h["hand"].remove_at(ridx)
	h["discard"].append(card_idx)
	if drop_crisis and h["crisis"] > 0:
		h["crisis"] -= 1
		_log("%s 随机打出英雄卡，丢弃 1 个危机指示物（剩余 %d）" % [DB.hero_name(hid), h["crisis"]], Color(0.7, 0.7, 1))
	return card_idx

func _card_desc(hid: String, card_idx: int) -> String:
	var c: Dictionary = DB.hero_cards(hid)[card_idx]
	var parts: Array = []
	for s in c["symbols"]:
		parts.append(DB.symbol_name(s))
	if c.has("effect"):
		parts.append("【" + c["effect"]["name"] + "】")
	return " ".join(parts)

## 叛徒模式：背面打出英雄牌，丢弃自己的 1 个不信任指示物。该卡无效果，但英雄仍获得上一张英雄牌的符号。
func play_card_face_down(hand_idx: int) -> void:
	if state["phase"] != "hero_play":
		return
	var hid: String = state["hero_ids"][state["current_hero"]]
	var h: Dictionary = state["heroes"][hid]
	if h["distrust"] <= 0:
		return
	if hand_idx < 0 or hand_idx >= h["hand"].size():
		return
	var card_idx: int = h["hand"][hand_idx]
	h["hand"].remove_at(hand_idx)
	h["discard"].append(card_idx)
	# 先记录"上一张英雄牌"的符号（背面卡自身无效果，但仍继承上张牌的符号）
	var prev_syms: Array = []
	if not state.get("no_prev_symbols", false):
		prev_syms = _last_hero_card_symbols()
	state["story"].append({"type": "hero", "hero": hid, "idx": card_idx, "face_down": true})
	state["hero_cards_played"] += 1
	h["distrust"] = 0
	state["action_symbols"] = prev_syms.duplicate()
	state["prev_hero_symbols"] = prev_syms.duplicate()
	state["used_tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
	state["effect_available"] = false
	state["effect_used"] = false
	state["played_effect"] = null
	state["phase"] = "hero_actions"
	_log("%s 将英雄牌背面打出，丢弃 1 个不信任指示物（本回合无卡牌效果）" % DB.hero_name(hid), Color(0.9, 0.7, 0.9))
	Events.emit_state_changed()

## 叛徒模式：弹窗让玩家选一张手牌"背面打出"以丢弃 1 个不信任指示物。
func play_face_down_choice() -> void:
	if state["phase"] != "hero_play":
		return
	var hid: String = state["hero_ids"][state["current_hero"]]
	if state["heroes"][hid].get("distrust", 0) <= 0:
		return
	var picked: Array = await _ask_hand_cards(hid, 1, "%s 选择背面打出的英雄牌（丢弃 1 个不信任指示物）" % DB.hero_name(hid))
	if picked.size() == 0:
		return
	play_card_face_down(int(picked[0]))

## 叛徒模式：达成 2 个任务后触发指认 → 翻身份 → 处置（KO仍持不信任的忠臣）→ 叛徒接管反派。
func _run_traitor_accusation() -> void:
	if state["traitor_revealed"]:
		return
	state["traitor_revealed"] = true
	_log("🤫 任务达成 2 个！所有人同时指认心目中的叛徒…", Color(1, 0.8, 0.4))
	# 每个玩家(英雄)秘密指认一名其他英雄
	for hid in state["hero_ids"]:
		var others: Array = []
		for o in state["hero_ids"]:
			if o != hid:
				others.append(o)
		if others.size() == 0:
			continue
		var pick: int = await _ask_pick_hero("「%s」你指认谁是你心中的叛徒？" % DB.hero_name(hid), others)
		state["accusations"][hid] = others[wrapi(pick, 0, others.size())]
	# 翻身份，展示
	_log("—— 身份揭晓 ——", Color(1, 0.8, 0.4))
	var traitor: String = state["traitor_hid"]
	for hid in state["hero_ids"]:
		var role: String = state["loyalty"][hid]
		_log("%s 是%s" % [DB.hero_name(hid), "叛徒！" if role == "traitor" else "忠臣"],
			Color(1, 0.5, 0.4) if role == "traitor" else Color(0.5, 1, 0.6))
	# 正确指认叛徒的忠臣获得 1 个万能指示物
	for hid in state["hero_ids"]:
		if state["loyalty"][hid] == "loyal" and state["accusations"].get(hid, "") == traitor:
			state["heroes"][hid]["tokens"]["wild"] += 1
			_log("%s 正确指认叛徒，获得 1 个万能指示物" % DB.hero_name(hid), Color(0.9, 0.9, 0.5))
	# 仍持有不信任指示物的忠臣立即 KO（直接用 KO 标记，不触发反派 BAM）
	for hid in state["hero_ids"]:
		if state["loyalty"][hid] == "loyal" and state["heroes"][hid]["distrust"] > 0 and not state["heroes"][hid]["ko"]:
			state["heroes"][hid]["ko"] = true
			_log("%s 仍持有不信任指示物，被 KO！" % DB.hero_name(hid), Color(1, 0.5, 0.3))
	# 叛徒离开英雄阵营并接管反派
	state["traitor_active"] = true
	state["heroes"][traitor]["ko"] = true
	state["eliminated"].append(traitor)
	state["hero_ids"].erase(traitor)
	state["current_hero"] = clampi(state["current_hero"], 0, maxi(state["hero_ids"].size() - 1, 0))
	_log("叛徒 %s 离开英雄阵营，公开接管反派！此后由叛徒操控反派。" % DB.hero_name(traitor), Color(1, 0.5, 0.2))
	Events.emit_state_changed()

## 叛徒接管反派后的"看顶2选1"：叛徒查看前 2 张行动牌，打出 1 张、另 1 张放牌堆底；只剩 1 张直接打出。
func _traitor_pick_card() -> Variant:
	if state["master_deck"].size() == 0:
		return null
	if state["master_deck"].size() <= 1:
		return state["master_deck"].pop_front()
	# 若顶 2 张里有无限宝石等隐藏牌，则正常翻顶（不进入手选）
	if state["master_deck"][0] is Dictionary or state["master_deck"][1] is Dictionary:
		return state["master_deck"].pop_front()
	var rows: Array = _traitor_pick_rows([state["master_deck"][0], state["master_deck"][1]])
	var pick: int = int(await _ask_action("叛徒：选择要打出的反派行动牌（另一张放回牌堆底）", rows))
	var pick_i := wrapi(pick, 0, 2)
	var played: Variant = state["master_deck"][pick_i]
	state["master_deck"].remove_at(pick_i)
	var other: Variant = state["master_deck"][0]
	state["master_deck"].remove_at(0)
	state["master_deck"].append(other)
	return played

func _traitor_pick_rows(top: Array) -> Array:
	var vid: String = state["villain"]
	var rows: Array = []
	for i in range(mini(top.size(), 2)):
		var idx: int = int(top[i])
		var img := UiKit.villain_action_image(vid, idx)
		rows.append({"img": img, "hide_text": false, "text": villain_action_desc(idx)})
	return rows

func _last_hero_card_symbols() -> Array:
	for i in range(state["story"].size() - 2, -1, -1):
		var entry: Dictionary = state["story"][i]
		if entry["type"] == "hero":
			# 面朝下的英雄行动牌不给行动（下一名英雄无法获得其符号）
			if entry.get("face_down", false):
				continue
			# 泽莫男爵（裁定①）：被危机指示物盖住的符号永久失效 → 下一位英雄不能继承
			return _entry_uncovered_symbols(entry)
	return []

## 可用符号（含行动指示物，token_ 前缀表示消耗指示物）
## 神盾局模式：指示物共享给玩家（任意英雄都能用）
func available_symbols() -> Array:
	var hid: String = state["hero_ids"][state["current_hero"]]
	var h: Dictionary = state["heroes"][hid]
	var out: Array = state["action_symbols"].duplicate()
	var t: Dictionary = state["shield_tokens"] if state["mode"] == "shield" else h["tokens"]
	for tk in ["move", "attack", "heroic", "wild"]:
		for i in range(t[tk] - state["used_tokens"][tk]):
			out.append("token_" + tk)
	return out

func remaining_symbols() -> int:
	return state["action_symbols"].size()

## 使用一个行动符号（异步：可能弹出选择）
func use_symbol(sym: String) -> void:
	# 第三批·霍华德鸭「中子分解器」：本回合不能再使用攻击行动
	if sym == "attack" and not state["hero_ids"].is_empty():
		var _al_hid: String = String(state["hero_ids"][state["current_hero"]])
		if bool(state["heroes"].get(_al_hid, {}).get("attack_locked_turn", false)):
			Events.emit_toast("中子分解器：本回合不能再使用攻击行动")
			return
	if _net_gate("use_symbol", [sym]):
		return
	if state["phase"] != "hero_actions":
		return
	if undo_enabled:
		_undo_snapshot = state.duplicate(true)
	var hid: String = state["hero_ids"][state["current_hero"]]
	if state.get("virus_ignore", false):
		state["virus_ignore"] = false
		_log("%s 忽略了一个行动符号（奥创病毒）" % DB.hero_name(hid), Color(0.9, 0.8, 0.6))
		state["action_symbols"].erase(sym)
		Events.emit_state_changed()
		return
	var is_token := sym.begins_with("token_")
	var base := sym.substr(6) if is_token else sym
	if base == "wild":
		var wrows := [
			{"icon": "move", "text": "移动", "hide_text": true},
			{"icon": "attack", "text": "攻击", "hide_text": true},
			{"icon": "heroic", "text": "英勇", "hide_text": true},
			{"text": "返回"},
		]
		var choice = await _ask_action("万能行动：选择用途", wrows)
		var ci := int(choice)
		if ci == 3:
			# 返回：不消耗万能，重新选择行动
			Events.emit_state_changed()
			return
		match ci:
			0: base = "move"
			1: base = "attack"
			2: base = "heroic"
			_: base = "move"
		# 消耗万能：移除一个 wild 卡牌符号，或消耗一个 wild 指示物
		if is_token:
			var pool: Dictionary = state["shield_tokens"] if state["mode"] == "shield" else state["heroes"][hid]["tokens"]
			pool["wild"] -= 1
		else:
			var widx: int = state["action_symbols"].find("wild")
			if widx == -1:
				Events.emit_toast("没有可用的万能行动")
				return
			state["action_symbols"].remove_at(widx)
		# 万能选好具体行动后，同样走"正常使用 / 填充能量卡"选择
		var wres: String = await _offer_energy_or_use(base, "wild_token" if is_token else "wild_symbol", hid)
		if wres == "fill":
			return  # 已用于填充能量卡（万能已消耗）
		if wres == "back":
			# 返回：归还万能
			if is_token:
				var pool_b: Dictionary = state["shield_tokens"] if state["mode"] == "shield" else state["heroes"][hid]["tokens"]
				pool_b["wild"] += 1
			else:
				state["action_symbols"].append("wild")
			Events.emit_state_changed()
			return
		# 卡魔拉·斩击：使用攻击行动前先结算额外攻击，避免"最后一个攻击被 auto_end_turn 提前结束回合"。
		# bonus 攻击不再触发（防套娃）；普通攻击先 +1 一个 attack 符号，后续 _maybe_auto_end_turn 仍能看到它。
		if state.get("gamora_fury", false) and base == "attack":
			if int(state.get("gamora_bonus", 0)) > 0:
				# 本次是斩击额外给的 bonus 攻击：消耗它，不再产生新攻击
				state["gamora_bonus"] = int(state["gamora_bonus"]) - 1
			else:
				# 本次是普通攻击：先获得 1 个额外攻击（标记为 bonus）
				state["action_symbols"].append("attack")
				state["gamora_bonus"] = int(state.get("gamora_bonus", 0)) + 1
				_log("卡魔拉·斩击：获得 1 个额外攻击行动", Color(1, 0.5, 0.5))
		match base:
			"move":
				_execute_move(hid, "wild_token" if is_token else "wild_symbol")
			"attack":
				_execute_attack(hid, "wild_token" if is_token else "wild_symbol")
			"heroic":
				_execute_heroic(hid, "wild_token" if is_token else "wild_symbol")
		# 火箭·天才技师（用1当2）：万能指示物也执行两次
		if state.get("token_double", false) and is_token:
			state["action_symbols"].append(base)
			_log("天才技师：%s 指示物执行两次行动" % DB.symbol_name(base), Color(1, 0.85, 0.4))
		Events.emit_state_changed()
		return
	# 普通符号：先扣除，再询问是否用于填充能量卡；选"返回"则归还
	if not is_token:
		var idx: int = state["action_symbols"].find(base)
		if idx == -1:
			Events.emit_toast("没有可用的%s行动" % DB.symbol_name(base))
			return
		state["action_symbols"].remove_at(idx)
	else:
		var pool0: Dictionary = state["shield_tokens"] if state["mode"] == "shield" else state["heroes"][hid]["tokens"]
		if int(pool0[base]) - int(state["used_tokens"][base]) <= 0:
			Events.emit_toast("没有可用的%s指示物" % DB.symbol_name(base))
			return
		pool0[base] -= 1
	var use_res: String = await _offer_energy_or_use(base, "token" if is_token else "symbol", hid)
	if use_res == "fill":
		return  # 已用于填充能量卡（行动已消耗）
	if use_res == "back":
		# 返回：归还本次行动
		if is_token:
			var pool_r: Dictionary = state["shield_tokens"] if state["mode"] == "shield" else state["heroes"][hid]["tokens"]
			pool_r[base] += 1
		else:
			state["action_symbols"].append(base)
		Events.emit_state_changed()
		return
	# use：正常执行
	# 卡魔拉·斩击：使用攻击行动前先结算额外攻击，避免"最后一个攻击被 auto_end_turn 提前结束回合"。
	# bonus 攻击不再触发（防套娃）；普通攻击先 +1 一个 attack 符号，后续 _maybe_auto_end_turn 仍能看到它。
	if state.get("gamora_fury", false) and base == "attack":
		if int(state.get("gamora_bonus", 0)) > 0:
			# 本次是斩击额外给的 bonus 攻击：消耗它，不再产生新攻击
			state["gamora_bonus"] = int(state["gamora_bonus"]) - 1
		else:
			# 本次是普通攻击：先获得 1 个额外攻击（标记为 bonus）
			state["action_symbols"].append("attack")
			state["gamora_bonus"] = int(state.get("gamora_bonus", 0)) + 1
			_log("卡魔拉·斩击：获得 1 个额外攻击行动", Color(1, 0.5, 0.5))
	match base:
		"move":
			_execute_move(hid, "token" if is_token else "symbol")
		"attack":
			_execute_attack(hid, "token" if is_token else "symbol")
		"heroic":
			_execute_heroic(hid, "token" if is_token else "symbol")
	# 火箭·天才技师（用1当2）：行动指示物（含万能指示物）额外 +1 对应符号
	if state.get("token_double", false) and is_token:
		state["action_symbols"].append(base)
		_log("天才技师：%s 指示物执行两次行动" % DB.symbol_name(base), Color(1, 0.85, 0.4))
	Events.emit_state_changed()

## 无限战争：行动执行前询问——正常使用 还是 填充能量卡
## 返回 "use" 正常使用 / "fill" 已用于填充（行动已由调用方扣除）/ "back" 用户返回
func _offer_energy_or_use(base: String, consumed: String, hid: String) -> String:
	if state.get("mode", "base") != "iw" or state.get("final_battle", false):
		return "use"
	if base == "threat":
		return "use"
	# 收集可填的能量卡（未完成且该符号可填某个空槽；万能也算可填）
	var fillable: Array = []  # 每项 {"eidx": int, "label": String}
	for eidx in [int(state.get("table_energy", -1)), int(state.get("hidden_energy", -1))]:
		if eidx < 0:
			continue
		if not energy_can_fill(eidx) or energy_done(eidx):
			continue
		if energy_match_slot(eidx, base) >= 0 or base == "wild":
			fillable.append({"eidx": eidx, "label": "填充能量卡 %d（%d/%d）" % [energy_local_no(eidx), energy_filled(eidx), energy_required_syms(eidx).size()]})
	if fillable.size() == 0:
		return "use"
	var options: Array = ["正常使用 %s" % DB.symbol_name(base)]
	var keys: Array = ["use"]
	for f in fillable:
		options.append(f["label"])
		keys.append("e" + str(f["eidx"]))
	options.append("返回")
	# 用和普通模式**同一套**"行动图标 + 箭头 + 卡图"弹窗：
	# 以前这里是纯文字选项列表（prompt_choice），无限战争下每次行动都会弹一个纯文字框，
	# 看着和普通模式的行动弹窗完全不一样（用户报的 bug）。
	var rows: Array = [{"icon": base, "arrow": base, "text": "正常使用 %s" % DB.symbol_name(base)}]
	var fill_eidx: Array = []
	for f in fillable:
		var fe: int = int(f["eidx"])
		var r: Dictionary = {"icon": base, "text": String(f["label"])}
		if fe >= 0 and fe < DB.energy_cards.size():
			var eimg: String = String((DB.energy_cards[fe] as Dictionary).get("img", ""))
			if eimg != "":
				r["img"] = eimg
				r["card"] = "threat"      # 按卡牌样式渲染，和行动弹窗里的卡图一致
		rows.append(r)
		fill_eidx.append(fe)
	rows.append({"text": "返回"})
	var pick: int = int(await _ask_action("使用 %s 行动：" % DB.symbol_name(base), rows))
	if pick <= 0:
		return "back" if pick < 0 else "use"
	if pick >= rows.size() - 1:
		return "back"
	var eidx: int = int(fill_eidx[pick - 1])
	# 填充能量卡（行动已由调用方扣除）
	var filled_slots: Array = energy_filled_slots(eidx)
	var slot_idx: int = energy_match_slot(eidx, base)
	if slot_idx == -1:
		Events.emit_toast("该能量卡没有可填的空槽")
		return "back"
	filled_slots.append(slot_idx)
	state["energy_tokens"][str(eidx)] = filled_slots
	_log("%s 将 %s 行动用于填充能量卡 %d（%d/%d）" % [DB.hero_name(hid), DB.symbol_name(base), energy_local_no(eidx), filled_slots.size(), energy_required_syms(eidx).size()], Color(0.9, 0.9, 0.5))
	if filled_slots.size() >= energy_required_syms(eidx).size():
		_unlock_energy_card(eidx)
	Events.emit_state_changed()
	await _maybe_auto_end_turn()
	return "fill"

## 罗南威胁卡符号清除：若当前地点威胁卡有 clear 字段且可用当前符号填充，询问是否填入。
## 返回 true 表示已填入（调用方应停止本次常规行动）；false 表示继续常规行动。
## sym 为实际符号（move/attack/heroic）。
## 该地点威胁卡是否可用 sym 符号再填一次（罗南 clear 型威胁卡）。
# ---------------------------------------------------------------- 神秘客 (Mysterio)

## 场上是否有"已揭示"的破碎幻像（决定神秘客能否受到伤害）
func _mysterio_illusion_present() -> bool:
	for loc in range(LOCATION_COUNT):
		var t: Variant = state["locations"][loc]["threat"]
		if t != null and t["name"] == "破碎幻像" and not t.get("_face_down", false):
			return true
	return false

## 背面朝上的威胁卡所在地点列表
func _face_down_threat_locs() -> Array:
	var out: Array = []
	for loc in range(LOCATION_COUNT):
		var t: Variant = state["locations"][loc]["threat"]
		if t != null and t.get("_face_down", false):
			out.append(loc)
	return out

## 该地点是否有一张"已翻开"的威胁卡（背面朝上的不可交互）
func _threat_active(loc: int) -> bool:
	var t: Variant = state["locations"][loc]["threat"]
	return t != null and not t.get("_face_down", false)

## 是否还有未消耗的"任意行动"（行动符号或任意行动指示物）
func _has_available_any_action(hid: String) -> bool:
	if state["action_symbols"].size() > 0:
		return true
	var pool: Dictionary = state["shield_tokens"] if state["mode"] == "shield" else state["heroes"][hid]["tokens"]
	for k in ["move", "attack", "heroic", "wild"]:
		if int(pool[k]) - int(state["used_tokens"][k]) > 0:
			return true
	return false

## 可用的"任意行动"清单（供玩家选择用哪个行动支付）：
## ① 本回合打出的英雄卡上的行动符号（move/attack/heroic/wild，合并同类计数）
## ② 行动指示物中尚未使用的（含万能指示物）
func _available_any_actions(hid: String) -> Array:
	var out: Array = []
	var sym_counts := {}
	for s in state["action_symbols"]:
		sym_counts[s] = int(sym_counts.get(s, 0)) + 1
	for k in ["move", "attack", "heroic", "wild"]:
		if int(sym_counts.get(k, 0)) > 0:
			out.append({"kind": "symbol", "key": k, "icon": k,
				"text": "%s行动 x%d" % [DB.symbol_name(k), int(sym_counts[k])]})
	var pool: Dictionary = state["shield_tokens"] if state["mode"] == "shield" else state["heroes"][hid]["tokens"]
	for k in ["move", "attack", "heroic", "wild"]:
		var left := int(pool[k]) - int(state["used_tokens"][k])
		if left > 0:
			out.append({"kind": "token", "key": k, "icon": k,
				"text": "指示物·%s x%d" % [DB.symbol_name(k), left]})
	return out

## 消耗玩家**指定**的那个行动（与 _consume_any_action 同口径，但不再自动挑一个）
func _consume_chosen_action(hid: String, act: Dictionary) -> bool:
	var k := String(act.get("key", ""))
	if String(act.get("kind", "")) == "symbol":
		var i: int = state["action_symbols"].rfind(k)
		if i < 0:
			return false
		state["action_symbols"].remove_at(i)
		return true
	var pool: Dictionary = state["shield_tokens"] if state["mode"] == "shield" else state["heroes"][hid]["tokens"]
	if int(pool[k]) - int(state["used_tokens"][k]) > 0:
		state["used_tokens"][k] = int(state["used_tokens"][k]) + 1
		return true
	return false

## 神秘客：花费 1 个任意行动翻开一张背面威胁卡（无视地点限制），并结算其揭示效果
## 两步：① 玩家选**用哪个行动**支付（行动符号 / 各类行动指示物，可取消）② 选翻开哪一张（盲翻）
func reveal_threat_choice() -> void:
	if _net_gate("reveal_threat_choice", []):
		return
	if state["phase"] != "hero_actions":
		return
	var hid: String = state["hero_ids"][state["current_hero"]]
	var locs: Array = _face_down_threat_locs()
	if locs.size() == 0:
		Events.emit_toast("场上没有背面朝上的威胁卡")
		return
	# ① 选择使用的行动
	var acts: Array = _available_any_actions(hid)
	if acts.size() == 0:
		Events.emit_toast("没有可用的任意行动")
		return
	var arows: Array = []
	for a in acts:
		arows.append({"icon": a["icon"], "text": a["text"]})
	arows.append({"text": "取消（不翻开）"})
	var apick: int = int(await _ask_action("翻开背面威胁卡：选择要使用的行动", arows))
	if apick < 0 or apick >= acts.size():
		Events.emit_state_changed()
		return
	# ② 选择翻开哪一张（盲翻：只显示卡背，绝不泄露正面）
	var vid: String = state["villain"]
	var rows: Array = []
	var back_img := "res://assets/cards/villains/%s/threat_back.png" % vid
	for loc in locs:
		rows.append({"img": back_img, "card": "threat", "text": _loc_name(loc)})
	var pick: int = int(await _ask_action("翻开一张背面威胁卡（花费：%s）" % String(acts[apick]["text"]), rows))
	var target: int = int(locs[wrapi(pick, 0, locs.size())])
	if not _consume_chosen_action(hid, acts[apick]):
		Events.emit_toast("该行动已不可用")
		return
	_log("翻开威胁卡：使用 %s" % String(acts[apick]["text"]), Color(0.8, 0.85, 1))
	await _reveal_threat_at(target, hid)
	await _maybe_auto_end_turn()   # 与其他行动一致：若行动已用尽则自动结束回合

## 翻开指定地点的威胁卡并结算其"揭示效果"
func _reveal_threat_at(loc: int, hid: String) -> void:
	var t: Dictionary = state["locations"][loc]["threat"]
	if t == null:
		return
	t["_face_down"] = false
	_begin_overflow_event()   # 一次"揭示威胁卡"算一次结算事件
	_log("🃏 揭示威胁卡【%s】（%s）" % [t["name"], _loc_name(loc)], Color(0.8, 0.9, 1))
	match String(t.get("reveal", "")):
		"damage1":
			await _deal_damage_to_hero(hid, 1)
			_log("战斗无人机：%s 受到 1 点伤害" % DB.hero_name(hid), Color(1, 0.6, 0.4))
		"enable_damage":
			_log("破碎幻像：神秘客现在可以受到伤害（仍需完成 2 个任务）", Color(0.9, 0.9, 0.6))
		"add_thug":
			await _place_token_at("thug", loc, 1)
		"add_civ":
			await _place_token_at("civ", loc, 1)
		_:
			pass
	Events.emit_state_changed()

# ---------------------------------------------------------------- 邪恶六人组模式 (Sinister Six)

const S6_LETTERS := {"A": "docock", "B": "mysterio", "C": "kraven", "D": "sandman", "E": "electro", "F": "vulture"}

## 邪恶六人组模式：完整初始化（不走单人反派的通用 setup：无任务卡、无威胁卡、6 个反派各自独立）
func _setup_s6_full(hero_ids: Array, expansions: Array = []) -> void:
	state = {
		"villain": "",
		"hero_ids": hero_ids.duplicate(),
		"player_count": hero_ids.size(),
		"challenge": "none",
		"mode": "s6",
		"campaign": {}, "shield_deck": [], "shield_hand": [],
		"heroes": {}, "locations": [],
		"villain_pos": 0, "villain_hp": 0, "villain_hp_max": 0,
		"fear": 0, "slaughter": 0, "eliminated": [],
		"cull_armor_used": false, "proxima_parry_used": false, "no_prev_symbols": false,
		"random_play": false, "iw_mind_active": false, "iw_space_active": false, "final_battle": false,
		"extra_villain_card": 0, "extra_villain_turn": false,
		"phase": "setup", "current_hero": 0, "action_symbols": [], "used_tokens": {"move": 0, "attack": 0, "heroic": 0, "wild": 0},
		"story": [], "log": [], "master_deck": [], "master_discard": [], "turn_count": 0,
		"missions": [], "missions_completed": 0, "hero_cards_played": 0,
		"prev_hero_symbols": [], "effect_available": false, "effect_used": false, "played_effect": null,
		"end_turn_busy": false, "pending_villain_reveal": -1, "undo_stack": [], "solved_threats": [],
		"in_effect": false, "ql_busy": false, "skip_villain_card": 0,
		"traitor_revealed": false, "traitor_pending": false, "accusations": [], "delay_villain_turn": false,
		"forced_face_down_hero": "", "hero_turn_seq": 0, "overflow_settled": 0, "overflow_settled_locs": [],
	}
	# 地点（沿用基础配置；本模式不放威胁卡）
	var loc_ids: Array = []
	for id in DB.locations.keys():
		var loc_exp: String = DB.location(id).get("expansion", "基础盒")
		if loc_exp == "无限战争决战":
			continue
		if expansions.size() == 0 or expansions.has(loc_exp):
			loc_ids.append(id)
	loc_ids.shuffle()
	var loc_n: int = mini(LOCATION_COUNT, loc_ids.size())
	for i in range(loc_n):
		var init: Array = DB.location(loc_ids[i]).get("initial", [])
		var civ := 0
		var thug := 0
		for t in init:
			if t == "civ": civ += 1
			elif t == "thug": thug += 1
		state["locations"].append({
			"id": loc_ids[i], "civ": civ, "thug": thug, "crisis": 0,
			"threat": null, "threat_token": false, "destroyed": false, "reporter": false,
		})
	# 英雄
	for hid in hero_ids:
		var deck: Array = []
		for i in range(DB.hero_cards(hid).size()):
			deck.append(i)
		deck.shuffle()
		state["heroes"][hid] = {
			"id": hid, "deck": deck, "discard": [], "hand": [], "location": -1, "ko": false,
			"crisis": 0, "invulnerable": false, "ko_count": 0, "cartoon_web_armed": false, "miles_web_armed": false,
			"cat_redraw_armed": false, "dora_milaje": false, "martial_artist": false,
			"tokens": {"move": 0, "attack": 0, "heroic": 0, "wild": 0},
			"distrust": 0, "exposure": 0, "exposed": false, "exposure_turn": -1, "exposed_face_down": false,
		}
	_setup_s6(hero_ids)
	_log("📖 邪恶六人组模式：不使用任务卡与威胁卡；伤害门槛 = 先填满该反派的弱点卡", Color(0.8, 0.9, 1))
	Events.emit_state_changed()

## 模式初始化：6 个反派各自独立生命值/位置/弱点卡；无任务卡、无威胁卡；英雄在"反派起始地点"对面
func _setup_s6(hero_ids: Array) -> void:
	var hp_key := str(maxi(hero_ids.size(), 2))
	var vills := {}
	for vid in S6_LETTERS.values():
		var vd: Dictionary = DB.villain(String(vid))
		# 邪恶六人组模式：6 个反派生命值统一为 2/3/4 人 = 2/3/4
		var hp: int = maxi(hero_ids.size(), 2)
		var w: Dictionary = DB.s6["weak"][vid]
		vills[vid] = {
			"id": vid, "hp": hp, "hp_max": hp, "pos": 0, "defeated": false,
			"weak_syms": (w["syms"] as Array).duplicate(), "weak_filled": [], "weak_done": false,
			"held_civ": 0, "held_thug": 0, "decoy_used": false, "first_turn_done": false,
		}
	# 随机选一个地点：2 个反派在该地点，2 个在其顺时针相邻地点，2 个在其逆时针相邻地点
	var base: int = randi_range(0, LOCATION_COUNT - 1)
	var adj: Array = _adjacent_locs(base)
	var spots: Array = [base]
	for a in adj:
		spots.append(int(a))
	var ids: Array = S6_LETTERS.values().duplicate()
	ids.shuffle()
	for i in range(ids.size()):
		vills[ids[i]]["pos"] = int(spots[i / 2])
	state["s6"] = {
		"vills": vills,
		"deck": [],
		"discard": [],
		"hero_turns": 0,
		"rotation": randf() * TAU,     # 仪表板随机中心旋转角度
		"base_loc": base,
		"last_card": -1,
	}
	var acts: Array = DB.s6["actions"]
	for i in range(acts.size()):
		state["s6"]["deck"].append(i)
	state["s6"]["deck"].shuffle()
	# 英雄放在反派起始地点的对面
	var opposite: int = (base + 3) % LOCATION_COUNT
	for i in range(hero_ids.size()):
		var hid: String = hero_ids[i]
		state["heroes"][hid]["location"] = opposite
		for d in range(3):
			_draw_card(hid)
	_log("🕸 邪恶六人组模式：6 个反派起始于 %s（2 个）+ %s（2 个）+ %s（2 个）；行动牌堆 %d 张；英雄在 %s"
		% [_loc_name(base), _loc_name(int(spots[1])), _loc_name(int(spots[2])), state["s6"]["deck"].size(), _loc_name(opposite)], Color(0.8, 0.9, 1))

func _s6() -> Dictionary:
	return state.get("s6", {})

## 该地点的未被击败的反派 id 列表
func _s6_at(loc: int) -> Array:
	var out: Array = []
	var s: Dictionary = _s6()
	for vid in (s.get("vills", {}) as Dictionary):
		var v: Dictionary = s["vills"][vid]
		if not v["defeated"] and int(v["pos"]) == loc:
			out.append(String(vid))
	return out

## 还活着的反派 id（按 A~F 顺序）
func _s6_alive() -> Array:
	var out: Array = []
	var s: Dictionary = _s6()
	for letter in ["A", "B", "C", "D", "E", "F"]:
		var vid: String = S6_LETTERS[letter]
		if not s["vills"][vid]["defeated"]:
			out.append(vid)
	return out

func _s6_vid(letter: String) -> String:
	return String(S6_LETTERS.get(letter, ""))

## 反派在存活环上顺时针走 n 格
func _s6_step(vid: String, n: int) -> void:
	var v: Dictionary = _s6()["vills"][vid]
	var cur: int = int(v["pos"])
	for i in range(n):
		var nxt: int = _next_live_loc(cur)
		if nxt < 0 or nxt == cur:
			break
		cur = nxt
	v["pos"] = cur
	_log("🕸 %s 顺时针移动 %d 格 → %s" % [DB.villain_name(vid), n, _loc_name(cur)], Color(0.9, 0.8, 1))

## 邪恶六人组模式：溢出 / KO 共用规则 —— 抽 1 张反派行动卡面朝下放入故事情节
func _s6_add_face_down_card(reason: String) -> void:
	var s: Dictionary = _s6()
	if (s["deck"] as Array).size() == 0:
		_lose("反派行动牌堆已空，英雄们失败了。")
		return
	var idx: int = int((s["deck"] as Array).pop_front())
	(s["discard"] as Array).append(idx)
	state["story"].append({"type": "villain", "villain": "s6", "idx": idx, "move": 0, "face_down": true})
	_log("🕸 %s：抽取 1 张反派行动卡面朝下放入故事情节" % reason, Color(0.9, 0.9, 0.6))
	Events.emit_state_changed()

## 邪恶六人组模式的一次反派回合：每 2 个英雄回合打出一张反派行动卡
func _s6_run_turn() -> void:
	var s: Dictionary = _s6()
	if state["phase"] == "game_over":
		return
	state["phase"] = "villain"
	state["turn_count"] += 1
	for _sv in (_s6()["vills"] as Dictionary):
		_s6()["vills"][_sv]["decoy_used"] = false
	_log("—— 邪恶六人组回合 #%d ——" % state["turn_count"], Color(1, 0.5, 0.5))
	await _step_pause()
	if (s["deck"] as Array).size() == 0:
		_lose("反派行动牌堆已空，英雄们失败了。")
		return
	var idx: int = int((s["deck"] as Array).pop_front())
	(s["discard"] as Array).append(idx)
	s["last_card"] = idx
	var card: Dictionary = DB.s6["actions"][idx]
	state["story"].append({"type": "villain", "villain": "s6", "idx": idx, "move": _move_desc(int(card.get("move", 0)))})
	if not autopilot:
		await _await_villain_reveal(idx)
	_log("🕸 反派行动卡：%s - 移动%d - BAM！%s" % [
		String(card.get("text", "激活前 2 个未被击败的反派（%s）" % String(card.get("order", "")))),
		int(card.get("move", 1)), "" if card.get("all", false) else "（第 1 个放暴徒，第 2 个放平民）"], Color(1, 0.7, 0.7))
	await _step_pause()
	# 激活名单
	var line: String = String(card.get("order", "ABCDEF"))
	var activate: Array = []
	if bool(card.get("all", false)):
		activate = _s6_alive()
	else:
		for ch in line:
			var vid: String = _s6_vid(String(ch))
			var v: Dictionary = s["vills"][vid]
			if not v["defeated"]:
				activate.append(vid)
			if activate.size() >= 2:
				break
	# 只剩最后 1 个未被击败的反派 → 他每次激活都执行两轮
	var twice: bool = _s6_alive().size() == 1
	if twice and activate.size() > 0:
		activate.append(activate[0])
		_log("🕸 只剩 %s 一个反派：他本次激活执行两轮" % DB.villain_name(String(activate[0])), Color(1, 0.5, 0.5))
	var rounds: int = activate.size()
	for i in range(rounds):
		if state["phase"] == "game_over":
			return
		var vid: String = String(activate[i])
		await _s6_activate(vid, int(card.get("move", 1)), i, card)
		if _check_lose():
			return
	if rounds == 0:
		_log("🕸 没有未被击败的反派被激活", Color(0.8, 0.8, 0.8))
	Events.emit_state_changed()
	_start_hero_phase()

## 激活一个反派：顺时针移动 N 格 → BAM！→ 放指示物（第 1 个放暴徒、第 2 个放平民）
func _s6_activate(vid: String, move_n: int, slot: int, card: Dictionary) -> void:
	_s6_step(vid, move_n)
	Events.emit_state_changed()
	await _step_pause()
	await _s6_bam(vid)
	if state["phase"] == "game_over":
		return
	# 只有普通卡（带 #1/#2）才放指示物；"激活全部"的卡不放
	if not bool(card.get("all", false)) and slot <= 1:
		var kind: String = String(card.get("first" if slot == 0 else "second", "thug"))
		var v: Dictionary = _s6()["vills"][vid]
		var loc: int = int(v["pos"])
		_s6_place_indicators(loc, kind, 1)

## 在指定地点放 1 个指示物（放不下 → 邪恶六人组溢出规则：抽 1 张行动卡面朝下入故事情节）
func _s6_place_indicators(loc: int, kind: String, count: int) -> void:
	_begin_overflow_event()
	for i in range(count):
		var l: Dictionary = state["locations"][loc]
		var slots_total: int = int(DB.location(l["id"])["slots"])
		if l["civ"] + l["thug"] < slots_total:
			if kind == "thug": l["thug"] += 1
			else: l["civ"] += 1
			_log("🕸 在 %s 放置 1 个%s" % [_loc_name(loc), "暴徒" if kind == "thug" else "平民"], Color(0.9, 0.9, 0.9))
		else:
			_s6_add_face_down_card("溢出（%s 放不下指示物）" % _loc_name(loc))
			Events.emit_state_changed()
			return
		Events.emit_state_changed()
		await _step_pause()

## 各反派在 evil six 模式下的 BAM（以六边形面板/规则 docx 为准，与单人局不同）
func _s6_bam(vid: String) -> void:
	var v: Dictionary = _s6()["vills"][vid]
	var vpos: int = int(v["pos"])
	_log("BAM！%s：%s" % [DB.villain_name(vid), String(DB.s6["bam"].get(vid, ""))], Color(1, 0.6, 0.3))
	match vid:
		"kraven":
			# 从克莱文顺时针算，第一个"孤独"（所在地点只有他一个英雄）的英雄受 2 点伤害；没有孤独英雄则放 2 个平民
			var loner := ""
			for step in range(0, LOCATION_COUNT):
				var loc: int = (vpos + step) % LOCATION_COUNT
				var heroes_here: Array = _heroes_at(loc).filter(func(h): return not state["heroes"][h]["ko"])
				if heroes_here.size() == 1:
					loner = String(heroes_here[0])
					break
			if loner != "":
				_log("🕸 克莱文 BAM！：%s 是顺时针方向第一个孤独的英雄，受到 2 点伤害" % DB.hero_name(loner), Color(1, 0.5, 0.4))
				await _deal_damage_to_hero(loner, 2)
			else:
				_log("🕸 克莱文 BAM！：没有孤独的英雄 → 在 %s 添加 2 个平民" % _loc_name(vpos), Color(1, 0.7, 0.4))
				await _place_token_at("civ", vpos, 2)
		"sandman":
			v["hp"] = int(v["hp"]) + 1
			_log("🕸 沙人 BAM！：生命值 +1（当前 %d，上限 %d）" % [int(v["hp"]), int(v["hp_max"])], Color(1, 0.8, 0.4))
			for hid in _heroes_at(vpos):
				await _deal_damage_to_hero(hid, 1)
				if state["phase"] == "game_over":
					return
		"electro":
			for loc in _adjacent_locs(vpos):
				for hid in _heroes_at(int(loc)):
					await _deal_damage_to_hero(hid, 1)
					if state["phase"] == "game_over":
						return
		"mysterio":
			for hid in _heroes_at(vpos):
				state["heroes"][hid]["crisis"] = int(state["heroes"][hid].get("crisis", 0)) + 1
			_log("🕸 神秘客 BAM！：%s 的每个英雄各获得 1 个危机指示物" % _loc_name(vpos), Color(0.8, 0.8, 1))
		"docock":
			state["locations"][vpos]["crisis"] = int(state["locations"][vpos]["crisis"]) + 1
			_log("🕸 章鱼博士 BAM！：在 %s 放置 1 个危机指示物（当前 %d）" % [_loc_name(vpos), int(state["locations"][vpos]["crisis"])], Color(1, 0.7, 0.5))
			for hid in state["hero_ids"]:
				if state["heroes"][hid]["ko"]:
					continue
				var hl: int = int(state["heroes"][hid]["location"])
				if int(state["locations"][hl]["crisis"]) > 0:
					await _deal_damage_to_hero(hid, 1)
					if state["phase"] == "game_over":
						return
		"vulture":
			var l: Dictionary = state["locations"][vpos]
			var moved_c: int = int(l["civ"])
			var moved_t: int = int(l["thug"])
			l["civ"] = 0
			l["thug"] = 0
			v["held_civ"] = int(v["held_civ"]) + moved_c
			v["held_thug"] = int(v["held_thug"]) + moved_t
			_log("🕸 秃鹫 BAM！：把 %s 的 %d 民 / %d 暴移到秃鹫身上（身上现有 %d 民 / %d 暴）"
				% [_loc_name(vpos), moved_c, moved_t, int(v["held_civ"]), int(v["held_thug"])], Color(1, 0.8, 0.5))
	Events.emit_state_changed()

## 英雄是否可以在该地点化解该反派的弱点卡（必须与该反派同地点，且该卡未完成）
func _s6_weak_targets(hid: String, sym: String) -> Array:
	var out: Array = []
	if state.get("mode", "") != "s6":
		return out
	var h: Dictionary = state["heroes"][hid]
	var loc: int = int(h["location"])
	for vid in _s6_at(loc):
		var v: Dictionary = _s6()["vills"][vid]
		if bool(v["weak_done"]):
			continue
		var syms: Array = v["weak_syms"]
		var filled: Array = v["weak_filled"]
		for i in range(syms.size()):
			if i >= filled.size() or int(filled[i]) == 0:
				if String(syms[i]) == sym:
					out.append(vid)
					break
	return out

## 邪恶六人组：与该英雄同地点、且弱点卡**尚未完成**的所有反派（用于弹窗列出全部可化解对象）
func _s6_weak_candidates(hid: String) -> Array:
	var out: Array = []
	if state.get("mode", "") != "s6":
		return out
	var loc: int = int(state["heroes"][hid]["location"])
	for vid in _s6_at(loc):
		if not bool(_s6()["vills"][vid].get("weak_done", false)):
			out.append(String(vid))
	return out

## 用一次对应符号的行动化解弱点卡的一个槽位；填满 3 个 → 该反派可以受到伤害
func _s6_fill_weak(hid: String, vid: String, sym: String) -> bool:
	var v: Dictionary = _s6()["vills"][vid]
	var syms: Array = v["weak_syms"]
	var filled: Array = v["weak_filled"]
	while filled.size() < syms.size():
		filled.append(0)
	for i in range(syms.size()):
		if int(filled[i]) == 0 and String(syms[i]) == sym:
			filled[i] = 1
			break
	v["weak_filled"] = filled
	var done := 0
	for f in filled:
		if int(f) == 1:
			done += 1
	_log("🎯 化解弱点卡：%s 的弱点卡 %s 填入 1 个%s（%d/3）"
		% [DB.villain_name(vid), DB.symbol_name(sym), DB.symbol_name(sym), done], Color(0.7, 1, 0.8))
	if done >= syms.size():
		v["weak_done"] = true
		_log("💥 %s 的弱点卡已全部填满并移除：他现在可以受到伤害！" % DB.villain_name(vid), Color(1, 0.9, 0.4))
	Events.emit_state_changed()
	return true

## 对某个反派造成伤害（秃鹫持有指示物时忽略本回合全部伤害并把他们丢到所在地点）
func _s6_damage_villain(vid: String, dmg: int, hid: String) -> void:
	var v: Dictionary = _s6()["vills"][vid]
	if bool(v["defeated"]):
		return
	if vid == "vulture" and (int(v["held_civ"]) + int(v["held_thug"])) > 0 and not bool(v.get("decoy_used", false)) and not _dmg_uncancellable():   # 裁定⑦：精准射击期间无视秃鹫免伤
		v["decoy_used"] = true
		var loc: int = int(v["pos"])
		var c: int = int(v["held_civ"])
		var t: int = int(v["held_thug"])
		v["held_civ"] = 0
		v["held_thug"] = 0
		_log("🦅 秃鹫身上有 %d 民 / %d 暴：忽略本回合的全部伤害，并把指示物丢到 %s（会引发溢出）" % [c, t, _loc_name(loc)], Color(1, 0.8, 0.4))
		for i in range(c):
			_s6_place_indicators(loc, "civ", 1)
		for i in range(t):
			_s6_place_indicators(loc, "thug", 1)
		Events.emit_state_changed()
		return
	v["hp"] = int(v["hp"]) - dmg
	_log("⚔ %s 攻击 %s：生命值 %d/%d" % [DB.hero_name(hid), DB.villain_name(vid), int(v["hp"]), int(v["hp_max"])], Color(1, 0.9, 0.3))
	if int(v["hp"]) <= 0:
		v["defeated"] = true
		_log("🏆 %s 被击败！他的特殊规则不再生效。" % DB.villain_name(vid), Color(0.5, 1, 0.5))
		if _s6_alive().size() == 0:
			_win()
	Events.emit_state_changed()

## 该地点的所有未被击败的反派都已击败？（英雄回合结束时是否可用地点效果：有反派就不能用）
func _s6_loc_has_villain(loc: int) -> bool:
	return _s6_at(loc).size() > 0

## 邪恶六人组的胜负检查（并入 _check_lose）
func _s6_check_lose() -> bool:
	if state.get("mode", "") != "s6":
		return false
	if (_s6().get("deck", []) as Array).size() == 0 and state["phase"] != "game_over" and state["phase"] != "setup":
		# 牌堆空：只有在"需要抽牌"时才判负（在 _s6_run_turn / _s6_add_face_down_card 里处理），此处不主动判负
		pass
	return false


# ---------------------------------------------------------------- 秘密身份挑战模式

## 设置：英雄起始点**相邻的所有地点**各放 1 个记者指示物；反派起始地点额外放 1 个记者指示物。
func _setup_secret_identity() -> void:
	var hero_start: int = int(state["heroes"][state["hero_ids"][0]]["location"])
	var placed: Array = []
	for loc in _adjacent_locs(hero_start):
		state["locations"][int(loc)]["reporter"] = true
		placed.append(int(loc))
	var vpos: int = int(state["villain_pos"])
	state["locations"][vpos]["reporter"] = true
	if not placed.has(vpos):
		placed.append(vpos)
	_log("📷 秘密身份挑战：记者指示物已放置于 %s（英雄起始点 %s 的相邻地点 + 反派起始地点）"
		% [", ".join(placed.map(func(i): return _loc_name(int(i)))), _loc_name(hero_start)], Color(1, 0.9, 0.5))

## 英雄在某地点执行了"非移动"行动 → 若该地点有记者指示物则获得 1 个曝光指示物（每人每回合最多 1 个）。
func _gain_exposure(hid: String, reason: String = "") -> void:
	if state.get("challenge", "") != "secretid":
		return
	if state["phase"] == "game_over" or state["phase"] == "setup":
		return
	var h: Dictionary = state["heroes"][hid]
	if h["ko"] or bool(h.get("exposed", false)):
		return   # 已经暴露过的英雄不再获得曝光指示物
	var loc: int = int(h["location"])
	if loc < 0 or loc >= LOCATION_COUNT or not state["locations"][loc].get("reporter", false):
		return   # 该地点没有记者
	if int(h.get("exposure_turn", -1)) == int(state.get("hero_turn_seq", 0)):
		return   # 本回合已经获得过 1 个曝光指示物
	h["exposure"] = int(h.get("exposure", 0)) + 1
	h["exposure_turn"] = int(state.get("hero_turn_seq", 0))
	_log("📷 %s 在 %s（有记者）%s，获得 1 个曝光指示物（%d/3）"
		% [DB.hero_name(hid), _loc_name(loc), reason, int(h["exposure"])], Color(1, 0.9, 0.4))
	if int(h["exposure"]) >= 3:
		await _expose_hero(hid)
	Events.emit_state_changed()

## 曝光满 3 个：立刻受到 1 点伤害；下个回合必须把英雄卡背面朝下打出（该卡无效果，但仍继承上一张卡的符号）
func _expose_hero(hid: String) -> void:
	var h: Dictionary = state["heroes"][hid]
	if bool(h.get("exposed", false)):
		return
	h["exposed"] = true
	h["exposed_face_down"] = true
	_log("🎭 %s 的曝光指示物达到 3 个 —— 身份暴露！立刻受到 1 点伤害，且下回合必须背面打出英雄卡"
		% DB.hero_name(hid), Color(1, 0.4, 0.4))
	await _deal_damage_to_hero(hid, 1)
	Events.emit_state_changed()

## 移动记者指示物：消耗 1 个任意行动，把任意一个记者指示物挪到相邻地点（此行动不获得曝光指示物）
func move_reporter_choice() -> void:
	if state.get("challenge", "") != "secretid":
		return
	if state["phase"] != "hero_actions":
		return
	var hid: String = state["hero_ids"][state["current_hero"]]
	var reporter_locs: Array = []
	for i in range(LOCATION_COUNT):
		if state["locations"][i].get("reporter", false):
			reporter_locs.append(i)
	if reporter_locs.size() == 0:
		Events.emit_toast("场上没有记者指示物")
		return
	var acts: Array = _available_any_actions(hid)
	if acts.size() == 0:
		Events.emit_toast("没有可用的任意行动")
		return
	# ① 选择要挪动的记者
	var rows: Array = []
	for loc in reporter_locs:
		rows.append({"img": "res://assets/tokens/reporter_token.png", "text": _loc_name(int(loc))})
	rows.append({"text": "取消（不移动）"})
	var pick_r: int = int(await _ask_action("移动记者指示物：选择要移动的记者", rows))
	if pick_r < 0 or pick_r >= reporter_locs.size():
		Events.emit_state_changed()
		return
	var from: int = int(reporter_locs[pick_r])
	# ② 选择相邻目的地（被摧毁的地点不在存活环上，自动跳过）
	var dests: Array = _adjacent_locs(from)
	if dests.size() == 0:
		Events.emit_toast("该地点没有可用的相邻地点")
		return
	var drows: Array = []
	for d in dests:
		drows.append({"img": "res://assets/tokens/reporter_token.png", "text": _loc_name(int(d))})
	var pick_d: int = int(await _ask_action("移动记者指示物：%s → 选择相邻地点" % _loc_name(from), drows))
	var to: int = int(dests[wrapi(pick_d, 0, dests.size())])
	# ③ 选择用哪个行动支付（与"翻开威胁卡"一致：由玩家指定）
	var arows: Array = []
	for a in acts:
		arows.append({"icon": a["icon"], "text": a["text"]})
	arows.append({"text": "取消（返回）"})
	var apick: int = int(await _ask_action("移动记者指示物：选择要使用的行动", arows))
	if apick < 0 or apick >= acts.size():
		Events.emit_state_changed()
		return
	if not _consume_chosen_action(hid, acts[apick]):
		Events.emit_toast("该行动已不可用")
		return
	state["locations"][from]["reporter"] = false
	state["locations"][to]["reporter"] = true
	_log("📷 记者指示物从 %s 移动到 %s（消耗 %s，此行动不产生曝光）"
		% [_loc_name(from), _loc_name(to), String(acts[apick]["text"])], Color(0.9, 0.9, 0.6))
	Events.emit_state_changed()
	# 注意：按规则"把记者从自己所在地点移走"这一行动不会获得曝光指示物 → 此处不调用 _gain_exposure
	await _maybe_auto_end_turn()


# ---------------------------------------------------------------- 电光人 (Electro)

## 电光人：在某地点添加 1 个危机指示物。
## 特殊规则：若有危机指示物的地点需要再放危机，则改为在顺时针下一个"没有危机指示物"的地点添加。
func _electro_add_crisis(loc: int) -> void:
	var target: int = loc
	if int(state["locations"][target]["crisis"]) > 0:
		var found := false
		for s in range(1, LOCATION_COUNT + 1):
			var i: int = (loc + s) % LOCATION_COUNT
			if state["locations"][i].get("destroyed", false):
				continue
			if int(state["locations"][i]["crisis"]) == 0:
				target = i
				found = true
				break
		if found:
			_log("⚡ %s 已有危机指示物 → 改为顺时针下一个无危机的地点 %s" % [_loc_name(loc), _loc_name(target)], Color(1, 0.8, 0.4))
		else:
			_log("⚡ 所有地点都已有危机指示物（%s 再加 1 个）" % _loc_name(loc), Color(1, 0.6, 0.4))
	state["locations"][target]["crisis"] = int(state["locations"][target]["crisis"]) + 1
	_log("⚡ 在 %s 放置 1 个危机指示物（该地点共 %d 个）" % [_loc_name(target), int(state["locations"][target]["crisis"])], Color(1, 0.85, 0.4))
	Events.emit_state_changed()
	_check_lose()

## 电光人·消失：每个英雄都在「消失」那张行动卡之后打出过牌 → 解除免伤
func _electro_check_vanish() -> void:
	var start: int = int(state.get("electro_vanish_story", 0))
	var played := {}
	for idx in range(mini(start, state["story"].size()), state["story"].size()):
		var e: Dictionary = state["story"][idx]
		if String(e.get("type", "")) == "hero":
			played[e.get("hero", "")] = true
	var all_played: bool = int(state["hero_ids"].size()) > 0
	for hid in state["hero_ids"]:
		if not played.has(hid):
			all_played = false
			break
	if all_played:
		state["electro_vanish"] = false
		_log("消失结束：每个英雄都已打出过行动卡，电光人重新可以受到伤害", Color(0.8, 1, 0.8))

func _ronan_threat_can_fill(loc: int, sym: String) -> bool:
	var l: Dictionary = state["locations"][loc]
	var t: Variant = l["threat"]
	if t == null or not t.has("clear"):
		return false
	if t.get("_face_down", false):
		return false   # 背面朝上的威胁卡不可交互（神秘客）
	if t.get("unclearable", false):
		return false   # 不可清除的威胁卡（神秘客·破碎幻像）
	var clear: Array = t["clear"]
	var filled: Array = t.get("clear_progress", [])
	return filled.count(sym) < clear.count(sym)

## 威胁卡需填符号总数。
func _ronan_threat_size(loc: int) -> int:
	var t: Variant = state["locations"][loc]["threat"]
	if t == null or not t.has("clear"):
		return 0
	return int(t["clear"].size())

## 威胁卡已填符号数。
func _ronan_threat_filled(loc: int) -> int:
	var t: Variant = state["locations"][loc]["threat"]
	if t == null or not t.has("clear"):
		return 0
	return int(t.get("clear_progress", []).size())

## 向当前地点威胁卡填入一个符号；填满则清除威胁（作为行动选项调用，不弹窗询问）。
func _fill_ronan_threat(hid: String, loc: int, sym: String) -> void:
	var l: Dictionary = state["locations"][loc]
	var t: Dictionary = l["threat"]
	if t == null or not t.has("clear"):
		return
	var filled: Array = t.get("clear_progress", [])
	filled.append(sym)
	t["clear_progress"] = filled
	var total: int = t["clear"].size()
	_log("%s 用%s符号填充威胁卡 %s（%d/%d）" % [DB.hero_name(hid), DB.symbol_name(sym), t["name"], filled.size(), total], Color(0.7, 1, 0.9))
	Events.emit_state_changed()
	if filled.size() >= total:
		_log("威胁卡【%s】符号填满，威胁清除！" % t["name"], Color(0.6, 1, 0.8))
		_clear_threat(loc)

## 泽莫男爵（裁定③）：带 same_turn_clear 的威胁卡，其"N 个英勇"必须同一个英雄回合内凑够，
## 新英雄回合开始时把没凑满的进度清空重来（数据驱动：任何反派只要威胁卡写了这个标记都适用）。
func _reset_same_turn_threats() -> void:
	for loc in range(LOCATION_COUNT):
		var t: Variant = state["locations"][loc]["threat"]
		if t == null or not bool(t.get("same_turn_clear", false)):
			continue
		var filled: Array = t.get("clear_progress", [])
		if filled.size() == 0:
			continue
		t["clear_progress"] = []
		_log("【%s】新的英雄回合开始，上一回合凑的 %d 个符号清空（须在同一回合内凑够 %d 个）"
			% [t["name"], filled.size(), int(t.get("clear", []).size())], Color(1, 0.8, 0.5))

## 泽莫男爵（裁定⑤·「邪恶大师」常量效果）：只要场上存在带 immune_henchmen 的威胁卡，
## 其它爪牙（hp>0 的威胁卡）就不受任何伤害。返回免伤是否生效。
func _henchman_immune() -> bool:
	for loc in range(LOCATION_COUNT):
		var t: Variant = state["locations"][loc]["threat"]
		if t != null and bool(t.get("immune_henchmen", false)) and not bool(t.get("_face_down", false)):
			return true
	return false

## 故事情节里某张英雄卡的"未被危机指示物盖住"的印刷符号。
## 泽莫男爵（裁定①）：被盖住的符号永久失效——下一位英雄不能继承、其它效果也不能引用。
func _entry_uncovered_symbols(entry: Dictionary) -> Array:
	var syms: Array = DB.hero_cards(String(entry["hero"]))[int(entry["idx"])]["symbols"].duplicate()
	var covered: Array = entry.get("covered", [])
	if covered.is_empty():
		return syms
	var out: Array = []
	for i in range(syms.size()):
		if covered.has(i):
			continue
		out.append(syms[i])
	return out

## 泽莫男爵（裁定①/②/⑥）：本回合打出的行动卡在故事情节里的下标（没有则 -1）
func _current_hero_story_index(hid: String) -> int:
	for i in range(state["story"].size() - 1, -1, -1):
		var e: Dictionary = state["story"][i]
		if String(e.get("type", "")) != "hero":
			continue
		if String(e.get("hero", "")) != hid:
			continue
		if e.get("face_down", false):
			return -1   # 面朝下的牌没有可用符号，不参与覆盖
		return i
	return -1

## 泽莫男爵特殊规则（裁定①②）：英雄回合结束时，身上的危机指示物**逐个弹窗**盖到本回合打出的
## 行动卡底部的行动符号上（每次选一个尚未被盖的符号）；弹窗次数上限 = 该卡印刷符号数；
## 多余的危机指示物留在英雄身上，下个回合继续。被盖住的符号永久失效。
func _zemo_cover_crisis(hid: String) -> void:
	if String(state["villain"]) != "zemo":
		return
	var h: Dictionary = state["heroes"][hid]
	if int(h.get("crisis", 0)) <= 0:
		return
	var si: int = _current_hero_story_index(hid)
	if si < 0:
		_log("危机指示物：%s 本回合没有正面朝上的行动卡，%d 个危机指示物留在身上"
			% [DB.hero_name(hid), int(h["crisis"])], Color(0.9, 0.8, 0.6))
		return
	var entry: Dictionary = state["story"][si]
	var syms: Array = DB.hero_cards(String(entry["hero"]))[int(entry["idx"])]["symbols"]
	var covered: Array = (entry.get("covered", []) as Array).duplicate()
	# 上限 = 该卡底部的行动符号数（每个符号最多被盖 1 次，不能重复选择）
	var times: int = mini(int(h["crisis"]), syms.size() - covered.size())
	for n in range(times):
		var cand: Array = []
		for i in range(syms.size()):
			if not covered.has(i):
				cand.append(i)
		if cand.is_empty():
			break
		var labels: Array = []
		for i in cand:
			labels.append("第 %d 个符号（%s）" % [int(i) + 1, DB.symbol_name(String(syms[int(i)]))])
		var pick: int = int(await _ask(
			"泽莫男爵：把 1 个危机指示物盖到「%s」的哪个行动符号上？（第 %d/%d 次，身上还有 %d 个）"
				% [_card_desc(hid, int(entry["idx"])), n + 1, times, int(h["crisis"])], labels))
		var idx: int = int(cand[wrapi(pick, 0, cand.size())])
		covered.append(idx)
		h["crisis"] = int(h["crisis"]) - 1
		# 本回合剩余的同一符号也一并失效（该符号已被盖住 → 任何来源都不能再用）
		state["action_symbols"].erase(String(syms[idx]))
		_log("危机指示物盖住了 %s 本回合「%s」的第 %d 个符号（%s）——该符号永久失效（身上还剩 %d 个危机指示物）"
			% [DB.hero_name(hid), _card_desc(hid, int(entry["idx"])), idx + 1,
			DB.symbol_name(String(syms[idx])), int(h["crisis"])], Color(0.8, 0.6, 1))
	entry["covered"] = covered
	if int(h["crisis"]) > 0:
		_log("危机指示物：%s 身上还有 %d 个（本回合的行动卡符号已盖满或已达上限），留到下个回合"
			% [DB.hero_name(hid), int(h["crisis"])], Color(0.9, 0.8, 0.6))
	Events.emit_state_changed()

func _consume_symbol(base: String, is_token: bool, hid: String) -> void:
	if not is_token:
		var idx: int = state["action_symbols"].find(base)
		if idx == -1:
			Events.emit_toast("没有可用的%s行动" % DB.symbol_name(base))
			return
		state["action_symbols"].remove_at(idx)
	else:
		var pool: Dictionary = state["shield_tokens"] if state["mode"] == "shield" else state["heroes"][hid]["tokens"]
		pool[base] -= 1
	match base:
		"move":
			_execute_move(hid, "token" if is_token else "symbol")
		"attack":
			_execute_attack(hid, "token" if is_token else "symbol")
		"heroic":
			_execute_heroic(hid, "token" if is_token else "symbol")
	Events.emit_state_changed()

# ---- move

## 移动行动（consumed 为本次已消耗的行动来源：symbol/token/wild_symbol/wild_token）
## 裁定①（用户二次确认）：**移动行动不适用星体投射**——移动永远按英雄的真实位置算，
## `_astral_pick_loc()` 只在攻击/英勇行动前被调用（3728 / 4297）。这里**不读** `state["_astral_loc"]`。
func _execute_move(hid: String, consumed: String) -> void:
	var h: Dictionary = state["heroes"][hid]
	var loc: int = h["location"]
	var l: Dictionary = state["locations"][loc]
	# 空间宝石（决战）：英雄们忽略回合中的第一个移动行动
	if state.get("iw_space_active", false) and not state.get("iw_space_ignored", false):
		state["iw_space_ignored"] = true
		_log("空间宝石：%s 的移动行动被忽略" % DB.hero_name(hid), Color(1, 0.7, 0.9))
		Events.emit_state_changed()
		return
	# 越狱/纠缠陷阱：移动"离开该地点"需消耗 2 个移动行动（仅影响真正移动离开，不干扰用移动填充威胁）
	var jammed := false
	if l["threat"] != null and (l["threat"]["name"] == "纠缠陷阱" or l["threat"]["name"] == "越狱" or l["threat"]["name"] == "流沙"):
		jammed = true
	# 移动目的地 = 相邻地点；被摧毁的地点（章鱼博士）从环上跳过，
	# 其左右两个地点因此互为相邻（例：A-B-C 中 B 被摧毁 → A 与 C 相邻）
	var opts: Array = _adjacent_locs(loc)
	# 图形化选项行：移动图标 + 绿色箭头 + 地点名 + 地点小图
	var rows: Array = []
	for o in opts:
		var lid := int(o)
		var loc_img := ""
		var locdef: Dictionary = DB.location(state["locations"][lid]["id"])
		if locdef.has("image"):
			loc_img = locdef["image"]
		rows.append({"icon": "move", "arrow": "move", "text": _loc_name(lid), "bottom": loc_img})
	# 罗南威胁卡：可用"移动行动"填充（作为移动选项之一，与正常威胁卡一致）
	var fill_idx := -1
	if _ronan_threat_can_fill(loc, "move"):
		fill_idx = rows.size()
		rows.append({"icon": "move", "arrow": "move", "text": "用移动行动填充威胁（%d/%d）" % [_ronan_threat_filled(loc), _ronan_threat_size(loc)], "img": "res://assets/cards/villains/%s/threat_back.png" % state["villain"], "card": "threat", "hide_text": true})
	# 邪恶六人组：与该反派同地点 → 可用移动行动化解他弱点卡的移动槽（每个反派各占一行，同一个弹窗）
	var wv_move: String = ""
	var weak_move_idx := -1
	var weak_m_vids: Array = []
	if state.get("mode", "") == "s6":
		weak_m_vids = _s6_weak_candidates(hid).filter(func(v): return _s6_can_fill(String(v), "move"))
		if weak_m_vids.size() > 0:
			wv_move = String(weak_m_vids[0])
			weak_move_idx = rows.size()
			for _wvm in weak_m_vids:
				var wmv: Dictionary = _s6()["vills"][_wvm]
				var fmv := 0
				for f in (wmv["weak_filled"] as Array):
					if int(f) == 1:
						fmv += 1
				rows.append({"icon": "move", "img": "res://assets/cards/s6/weak_%02d.png" % int(DB.s6["weak"][_wvm]["img"]), "text": "化解弱点卡（%s %d/3）" % [DB.villain_name(String(_wvm)), fmv], "card": "threat"})
	rows.append({"text": "跳过行动"})
	if not jammed:
		rows.append({"text": "返回"})  # 越狱/纠缠陷阱场景涉及额外消耗，不提供返回
	var choice = await _ask_action("选择移动目的地", rows)
	var ci := int(choice)
	# ⓪ 化解弱点卡（移动槽）：只耗本次移动
	if weak_move_idx >= 0 and ci >= weak_move_idx and ci < weak_move_idx + weak_m_vids.size():
		_s6_fill_weak(hid, String(weak_m_vids[ci - weak_move_idx]), "move")
		Events.emit_state_changed()
		await _maybe_auto_end_turn()
		return
	# ① 用移动填充威胁：只耗本次移动，不走"离开需2移动"逻辑
	if fill_idx >= 0 and ci == fill_idx:
		_log("%s 使用移动行动填充威胁（越狱/纠缠陷阱不影响填充）" % DB.hero_name(hid), Color(0.7, 1, 0.9))
		_fill_ronan_threat(hid, loc, "move")
		return
	if ci >= opts.size():
		if not jammed and ci == rows.size() - 1:
			# 返回：归还本次消耗的移动行动，重新选择行动
			_refund_symbol(hid, "move", consumed)
			_log("%s 返回（移动行动已归还）" % DB.hero_name(hid), Color(0.8, 0.8, 0.8))
			Events.emit_state_changed()
			return
		# 跳过：放弃该行动，移动数量减一（不归还）
		_log("%s 跳过移动行动" % DB.hero_name(hid), Color(0.8, 0.8, 0.8))
		Events.emit_state_changed()
		return
	# ② 真正移动离开：若处于越狱/纠缠陷阱，需额外消耗 1 个移动行动
	if jammed:
		var remaining: int = state["action_symbols"].count("move")
		var pool: Dictionary = state["shield_tokens"] if state["mode"] == "shield" else h["tokens"]
		var tok_avail: int = pool["move"]
		if remaining + tok_avail < 1:
			Events.emit_toast("越狱/纠缠陷阱：离开需要 2 个移动行动（不足），已返还本次移动")
			_refund_symbol(hid, "move", consumed)
			return
		var idx: int = state["action_symbols"].find("move")
		if idx != -1:
			state["action_symbols"].remove_at(idx)
		else:
			pool["move"] -= 1
		_log("%s 消耗 2 个移动行动脱离越狱/纠缠陷阱" % DB.hero_name(hid), Color(0.9, 0.8, 0.5))
	var oi := wrapi(int(opts[ci]), 0, LOCATION_COUNT)
	await _set_hero_loc(hid, oi)   # 移动行动（A1：统一出口）
	_log("%s 移动到 %s" % [DB.hero_name(hid), _loc_name(oi)], Color(0.8, 0.9, 1))
	Events.emit_state_changed()
	await _maybe_auto_end_turn()

## 按消耗类型归还行动符号（卡牌符号/行动指示物/万能行动），用于返回/纠缠陷阱不足
func _refund_symbol(hid: String, base: String, consumed: String) -> void:
	var pool: Dictionary = state["shield_tokens"] if state["mode"] == "shield" else state["heroes"][hid]["tokens"]
	match consumed:
		"token":
			pool[base] += 1
		"wild_symbol":
			state["action_symbols"].append("wild")
		"wild_token":
			pool["wild"] += 1
		"none":
			pass   # 效果驱动的行动：本就没有消耗符号，无需归还（否则会凭空多出行动）
		_:
			state["action_symbols"].append(base)

# ---- attack

func _execute_attack(hid: String, consumed: String) -> void:
	await _gain_exposure(hid, "使用攻击行动")
	# 螳螂女·星体投射（裁定①）：本回合每次使用行动时可各自任选一个地点"如同你在那里"，
	# 本人实际位置不变（别人对你的位置判定/伤害/溢出仍按真实位置算）——这里只改本次行动用哪个地点。
	if bool(state["heroes"].get(hid, {}).get("astral_turn", false)):
		var _al: int = await _astral_pick_loc(hid, "星体投射：这次攻击行动如同你在哪个地点？")
		if _al >= 0:
			state["_astral_loc"] = _al
	var h: Dictionary = state["heroes"][hid]
	var loc: int = h["location"]
	if int(state.get("_astral_loc", -1)) >= 0:
		loc = int(state["_astral_loc"])   # 星体投射：本次行动如同在该地点
		state["_astral_loc"] = -1
	var l: Dictionary = state["locations"][loc]
	var targets: Array = []
	if l["thug"] > 0:
		targets.append("thug")
	if l["threat"] != null and l["threat"]["hp"] > 0 and not l["threat"].get("_face_down", false):
		targets.append("henchman:" + l["threat"]["name"])
	var vill_attackable: bool = state["missions_completed"] >= 2 and state["villain_pos"] == loc and state["villain_hp"] > 0
	if state.get("mode", "") == "s6":
		# 邪恶六人组：与反派同地点、且他的弱点卡已填满 → 可以攻击他
		for svid in _s6_at(loc):
			if bool(_s6()["vills"][svid].get("weak_done", false)):
				targets.append("s6:" + String(svid))
		vill_attackable = false
	if vill_attackable:
		var blocked: bool = state["villain"] == "taskmaster" and l["crisis"] > 0
		if not blocked:
			targets.append("villain")
	# 危机清除选项（无平民暴徒时）
	var crisis_option := false
	if state["villain"] == "taskmaster" and l["civ"] == 0 and l["thug"] == 0 and l["crisis"] > 0:
		crisis_option = true
	# 邪恶六人组：可用攻击行动化解"与该反派同地点"的弱点卡槽位（每个可化解的反派各占一行）
	var weak_vid: String = ""
	var weak_vids: Array = [] if state.get("mode", "") != "s6" else _s6_weak_candidates(hid).filter(func(v): return _s6_can_fill(String(v), "attack"))
	if weak_vids.size() > 0:
		weak_vid = String(weak_vids[0])
	# 罗南威胁卡：可用"攻击行动"填充（作为攻击选项之一，与正常威胁卡一致）
	var can_fill: bool = _ronan_threat_can_fill(loc, "attack")
	if targets.size() == 0 and not crisis_option and not can_fill and weak_vid == "":
		Events.emit_toast("此地没有可攻击的目标")
		return
	var rows: Array = []
	var vid_now: String = state["villain"]
	var vill_back: String = "" if state.get("mode", "") == "s6" else DB.villain(vid_now)["back"]
	var threat_back: String = "res://assets/cards/villains/%s/threat_back.png" % vid_now
	for t in targets:
		var t_img := ""
		if t == "thug":
			t_img = "res://assets/tokens/thug_token.png"
		elif String(t).begins_with("s6:"):
			t_img = DB.villain(String(t).substr(3))["back"]   # 邪恶六人组：用该反派的行动卡背面图
		elif t.begins_with("henchman"):
			# 爪牙威胁卡 → 用该威胁卡的正面图（threat_%02d，序号记录在 _tidx）；缺序号回退背面
			var ht: Dictionary = state["locations"][loc]["threat"]
			if ht.has("_tidx"):
				t_img = "res://assets/cards/villains/%s/threat_%02d.png" % [vid_now, int(ht["_tidx"]) + 1]
			else:
				t_img = threat_back
		else:
			t_img = vill_back   # 反派 → 反派行动卡背面
		var rrow := {"icon": "attack", "arrow": "attack", "text": _target_name(t), "img": t_img, "hide_text": true}
		if t.begins_with("henchman"):
			rrow["card"] = "threat"
		rows.append(rrow)
	if crisis_option:
		rows.append({"icon": "attack", "arrow": "attack", "text": "清除 1 个危机指示物"})
	var fill_idx := -1
	if can_fill:
		fill_idx = rows.size()
		rows.append({"icon": "attack", "arrow": "attack", "text": "用攻击行动填充威胁（%d/%d）" % [_ronan_threat_filled(loc), _ronan_threat_size(loc)], "img": threat_back, "card": "threat", "hide_text": true})
	var weak_idx := -1
	if weak_vids.size() > 0:
		weak_idx = rows.size()
		# 每个"可用攻击行动化解"的反派各占一行（同一个弹窗里直接选，不再弹第二个窗）
		for _wv in weak_vids:
			var wv2: Dictionary = _s6()["vills"][_wv]
			var wfilled := 0
			for f in (wv2["weak_filled"] as Array):
				if int(f) == 1:
					wfilled += 1
			rows.append({"icon": "attack", "img": "res://assets/cards/s6/weak_%02d.png" % int(DB.s6["weak"][_wv]["img"]), "text": "化解弱点卡（%s %d/3）" % [DB.villain_name(String(_wv)), wfilled], "card": "threat"})
	rows.append({"text": "跳过行动"})
	rows.append({"text": "返回"})
	var choice = await _ask_action("选择攻击目标", rows)
	var ci := int(choice)
	if weak_idx >= 0 and ci >= weak_idx and ci < weak_idx + weak_vids.size():
		_s6_fill_weak(hid, String(weak_vids[ci - weak_idx]), "attack")
		Events.emit_state_changed()
		await _maybe_auto_end_turn()
		return
	if fill_idx >= 0 and ci == fill_idx:
		_fill_ronan_threat(hid, loc, "attack")
		return
	if ci >= rows.size() - 2:
		if ci == rows.size() - 1:
			# 返回：归还本次消耗的攻击行动，重新选择行动
			_refund_symbol(hid, "attack", consumed)
			_log("%s 返回（攻击行动已归还）" % DB.hero_name(hid), Color(0.8, 0.8, 0.8))
			Events.emit_state_changed()
			return
		# 跳过：放弃该行动，攻击数量减一（不归还）
		_log("%s 跳过攻击行动" % DB.hero_name(hid), Color(0.8, 0.8, 0.8))
		Events.emit_state_changed()
		return
	if crisis_option and ci >= targets.size() and (fill_idx < 0 or ci < fill_idx):
		l["crisis"] -= 1
		_log("%s 清除 1 个危机指示物（%s）" % [DB.hero_name(hid), _loc_name(loc)], Color(0.7, 0.7, 1))
		Events.emit_state_changed()
		return
	await _perform_attack_at(loc, targets[ci], hid)
	await _maybe_auto_end_turn()

## 对指定地点执行一次攻击（普通攻击/光子冲击共用）
func _perform_attack_at(loc: int, tgt: String, hid: String) -> void:
	var l: Dictionary = state["locations"][loc]
	match tgt:
		"thug":
			_damage_thug_at(loc, 1, hid)
		_:
			if String(tgt).begins_with("s6:"):
				# 邪恶六人组：攻击某个反派
				var svid: String = String(tgt).substr(3)
				var sv: Dictionary = _s6()["vills"][svid]
				if int(sv["pos"]) != loc:
					_log("%s 已不在 %s，本次攻击落空" % [DB.villain_name(svid), _loc_name(loc)], Color(0.8, 0.8, 0.8))
					Events.emit_state_changed()
					return
				_s6_damage_villain(svid, 1, hid)
			elif tgt.begins_with("henchman:"):
				# 泽莫男爵「邪恶大师」（裁定⑤）：它在场时其它爪牙不受任何伤害
				if _henchman_immune() and not bool(l["threat"].get("immune_henchmen", false)):
					_log("%s 攻击爪牙 %s，但「邪恶大师」在场：爪牙不会受到任何伤害"
						% [DB.hero_name(hid), l["threat"]["name"]], Color(0.8, 0.85, 1))
					Events.emit_state_changed()
					return
				l["threat"]["hp"] -= 1
				_log("%s 攻击爪牙 %s（剩余 %d 生命）" % [DB.hero_name(hid), l["threat"]["name"], l["threat"]["hp"]], Color(1, 0.7, 0.4))
				if l["threat"]["hp"] <= 0:
					_clear_threat(loc)
			elif tgt == "villain":
				# 时序保护：本次行动中反派可能已被效果强制移动（如秃鹫·电磁飞翼移动到对面），
				# 此时对该地点的后续攻击不再命中（否则会在旧地点"隔空"继续扣血）
				if state["villain_pos"] != loc:
					_log("反派已不在 %s，本次攻击落空" % _loc_name(loc), Color(0.8, 0.8, 0.8))
					Events.emit_state_changed()
					return
				# 蜘蛛侠2099·利爪：本回合该英雄造成的伤害无法被降低/忽略 → 跳过一切减伤判定
				var ign_red: bool = bool(state["heroes"][hid].get("ignore_reduction", false))
				# 惩罚者·精准射击（裁定⑦）：本回合「你造成的伤害无视一切取消/忽略/减少」。
				# 这一整块免伤/减伤判定（超级坚甲/洛基幻象/沙人硬化/电光人消失/克莱文诱饵/秃鹫持有…）
				# 本来都由 ign_red 统一放行，所以把本批标志并进来即可。
				if _dmg_uncancellable():
					ign_red = true
				# 武学大师（暗夜比邻星威胁）：忽略每个回合对她的第一个攻击行动
				if state["villain"] == "proxima" and not state.get("proxima_parry_used", false) and _threat_present("武学大师") and not ign_red:
					state["proxima_parry_used"] = true
					_log("武学大师：暗夜比邻星格挡了本回合第一个攻击行动（无效）", Color(0.7, 0.7, 1))
					Events.emit_state_changed()
					return
				# 超级坚甲（黑矮星威胁）：黑矮星每回合忽略 1 点伤害
				var real_dmg := 1
				if state["villain"] == "cull" and not state.get("cull_armor_used", false) and _threat_present("超级坚甲") and not ign_red:
					state["cull_armor_used"] = true
					real_dmg = 0
					_log("超级坚甲：黑矮星本回合忽略 1 点伤害", Color(0.7, 0.9, 0.8))
				# 洛基-幻象威胁：只要洛基在这张威胁卡所在地点，他就不受伤害
				if state["villain"] == "loki" and not ign_red:
					var lvpos: int = state["villain_pos"]
					var lthreat: Variant = state["locations"][lvpos]["threat"]
					if lthreat != null and lthreat["name"] == "幻象":
						real_dmg = 0
						_log("幻象：洛基在该地点不受任何伤害（攻击无效）", Color(0.7, 0.9, 0.9))
				# 康·时间藏匿处威胁：只要康在该威胁卡所在地点**或与其相邻**，康就不受任何伤害
				if state["villain"] == "kang" and real_dmg > 0 and not ign_red and VillainRules._kang_hideout_protects(self):
					real_dmg = 0
					_log("时间藏匿处：康在该威胁卡所在地点或相邻地点，不受任何伤害（攻击无效）", Color(0.7, 0.9, 0.9))
				# 绿魔·以平民为盾：绿魔所在地点有"以平民为盾"威胁卡且该地点有平民 → 绿魔免受伤害
				if state["villain"] == "goblin" and real_dmg > 0 and not ign_red:
					var gvpos: int = state["villain_pos"]
					var gthreat: Variant = state["locations"][gvpos]["threat"]
					if gthreat != null and gthreat["name"] == "以平民为盾" and state["locations"][gvpos]["civ"] > 0:
						real_dmg = 0
						_log("以平民为盾：该地点有平民，绿魔免受伤害（攻击无效）", Color(0.7, 0.9, 0.9))
					# 绿魔面板有被绑架的平民指示物 → 绿魔免受伤害
					elif int(state.get("goblin_panel_civ", 0)) > 0:
						real_dmg = 0
						_log("绿魔面板有平民，绿魔免受伤害（攻击无效）", Color(0.7, 0.9, 0.9))
				# 神秘客·破碎幻像：场上没有已揭示的"破碎幻像"时，神秘客不受任何伤害
				if state["villain"] == "mysterio" and real_dmg > 0 and not ign_red:
					if not _mysterio_illusion_present():
						real_dmg = 0
						_log("破碎幻像：场上没有已揭示的「破碎幻像」，神秘客不受任何伤害（攻击无效）", Color(0.8, 0.9, 1))
				# 沙人·更难：该行动卡结算后沙人不受伤害，直到所有「沙尘暴」威胁卡被清除
				if state["villain"] == "sandman" and real_dmg > 0 and state.get("sandman_hard", false) and not ign_red:
					real_dmg = 0
					_log("更难：沙人不会受到任何伤害，直到所有「沙尘暴」威胁卡都被清除（攻击无效）", Color(0.9, 0.8, 0.6))
				# 电光人·消失：电光人不受任何伤害，直到每个英雄都在这张卡之后打出一张牌
				if state["villain"] == "electro" and real_dmg > 0 and state.get("electro_vanish", false) and not ign_red:
					real_dmg = 0
					_log("消失：电光人不会受到任何伤害，直到每个英雄都在这张行动卡之后打出一张牌（攻击无效）", Color(0.8, 0.9, 1))
				# 猎人克莱文·诱饵：一个回合内，克莱文在该地点忽略受到的第一次伤害
				if state["villain"] == "kraven" and real_dmg > 0 and not state.get("kraven_decoy_used", false) and not ign_red:
					var kt: Variant = state["locations"][state["villain_pos"]]["threat"]
					if kt != null and kt["name"] == "诱饵":
						real_dmg = 0
						state["kraven_decoy_used"] = true
						_log("诱饵：克莱文忽略了本回合在这个地点受到的第一次伤害", Color(0.9, 0.8, 0.6))
				# 秃鹫·电磁飞翼威胁：在"电磁飞翼·秃鹫"所在地点攻击秃鹫，他只会受到 1 点伤害，然后立即移动到对面地点
				var vulture_wing := false
				if state["villain"] == "vulture" and real_dmg > 0 and not ign_red:
					var wvpos: int = state["villain_pos"]
					var wthreat: Variant = state["locations"][wvpos]["threat"]
					if wthreat != null and wthreat["name"] == "电磁飞翼·秃鹫":
						real_dmg = 1
						vulture_wing = true
						_log("电磁飞翼：秃鹫只会受到 1 点伤害，并将立即移动到对面地点", Color(0.8, 0.9, 1))
				state["villain_hp"] -= real_dmg
				_check_hyper_awareness()   # 第三批·松鼠女·非常感知：反派生命变化后持续检查
				_log("%s 攻击反派！生命 %d/%d" % [DB.hero_name(hid), state["villain_hp"], state["villain_hp_max"]], Color(1, 0.9, 0.3))
				# 洛基-诡计大师威胁：洛基受到伤害，该地点的每个英雄也受到 1 点伤害
				if state["villain"] == "loki" and real_dmg > 0:
					var lvpos2: int = state["villain_pos"]
					var lthreat2: Variant = state["locations"][lvpos2]["threat"]
					if lthreat2 != null and lthreat2["name"] == "诡计大师":
						for hh in _heroes_at(lvpos2):
							if not state["heroes"][hh]["ko"]:
								await _deal_damage_to_hero(hh, 1)
						_log("诡计大师：洛基受伤，%s 的每位英雄各受到 1 点伤害" % _loc_name(lvpos2), Color(1, 0.6, 0.4))
				if state["villain_hp"] <= 0:
					_win()
				# 电磁飞翼：受击后立即移动到对面地点（相隔 3 格）
				elif vulture_wing:
					var wopp: int = (state["villain_pos"] + 3) % LOCATION_COUNT
					state["villain_pos"] = wopp
					_log("电磁飞翼：秃鹫移动到对面地点 %s" % _loc_name(wopp), Color(0.8, 0.9, 1))
	Events.emit_state_changed()

## 在指定地点进行一次可选择目标的攻击（光子冲击/雷神之锤用；可攻击暴徒/爪牙/反派/清除危机）
## times > 1 时：玩家只选一次目标，然后对该目标连续攻击 times 次
func _attack_once_at(hid: String, loc: int, label: String, times: int = 1) -> void:
	# 第三批·刀锋战士「猎人技巧」：本回合对单个敌人的一次攻击行动改为造成两点伤害
	if times == 1 and bool(state["heroes"].get(hid, {}).get("hunter_skill", false)):
		times = 2
	var l: Dictionary = state["locations"][loc]
	var targets: Array = []
	if l["thug"] > 0:
		targets.append("thug")
	if l["threat"] != null and l["threat"]["hp"] > 0 and not l["threat"].get("_face_down", false):
		targets.append("henchman:" + l["threat"]["name"])
	if state["missions_completed"] >= 2 and state["villain_pos"] == loc and state["villain_hp"] > 0:
		var blocked: bool = state["villain"] == "taskmaster" and l["crisis"] > 0
		if not blocked:
			targets.append("villain")
	# 模仿大师：无平民暴徒时可消耗攻击清除危机
	var crisis_option := false
	if state["villain"] == "taskmaster" and l["civ"] == 0 and l["thug"] == 0 and l["crisis"] > 0:
		crisis_option = true
	# 罗南威胁卡：可用"攻击行动"填充（作为效果攻击的目标选项之一）
	var can_fill: bool = _ronan_threat_can_fill(loc, "attack")
	if targets.size() == 0 and not crisis_option and not can_fill:
		Events.emit_toast("该地点没有可攻击的目标")
		return
	var rows: Array = []
	var vid_now: String = state["villain"]
	var vill_back: String = "" if state.get("mode", "") == "s6" else DB.villain(vid_now)["back"]
	var threat_back: String = "res://assets/cards/villains/%s/threat_back.png" % vid_now
	for t in targets:
		var t_img := ""
		if t == "thug":
			t_img = "res://assets/tokens/thug_token.png"
		elif t.begins_with("henchman"):
			# 爪牙威胁卡 → 用该威胁卡的正面图（threat_%02d，序号记录在 _tidx）；缺序号回退背面
			var ht: Dictionary = state["locations"][loc]["threat"]
			if ht.has("_tidx"):
				t_img = "res://assets/cards/villains/%s/threat_%02d.png" % [vid_now, int(ht["_tidx"]) + 1]
			else:
				t_img = threat_back
		else:
			t_img = vill_back   # 反派 → 反派行动卡背面
		var rrow := {"icon": "attack", "arrow": "attack", "text": _target_name(t), "img": t_img, "hide_text": true}
		if t.begins_with("henchman"):
			rrow["card"] = "threat"
		rows.append(rrow)
	if crisis_option:
		rows.append({"icon": "attack", "arrow": "attack", "text": "清除 1 个危机指示物"})
	var fill_idx := -1
	if can_fill:
		fill_idx = rows.size()
		rows.append({"icon": "attack", "arrow": "attack", "text": "用攻击行动填充威胁（%d/%d）" % [_ronan_threat_filled(loc), _ronan_threat_size(loc)], "img": threat_back, "card": "threat", "hide_text": true})
	var choice = await _ask_action(label + "：选择攻击目标", rows)
	var ci := int(choice)
	if fill_idx >= 0 and ci == fill_idx:
		_fill_ronan_threat(hid, loc, "attack")
		return
	if ci >= targets.size() and crisis_option and (fill_idx < 0 or ci < fill_idx):
		l["crisis"] -= 1
		_log("%s 用攻击清除 1 个危机指示物（%s）" % [DB.hero_name(hid), _loc_name(loc)], Color(0.7, 0.7, 1))
		Events.emit_state_changed()
		return
	for k in range(times):
		await _perform_attack_at(loc, targets[ci], hid)
		Events.emit_state_changed()

func _target_name(t: String) -> String:
	if t == "thug":
		return "暴徒"
	if t.begins_with("henchman:"):
		return "爪牙：" + t.get_slice(":", 1)
	if t.begins_with("s6:"):
		return "反派：" + DB.villain_name(t.substr(3))
	return "反派：" + DB.villain_name(state["villain"])

## 对地点造成伤害（处理需2伤/3伤的暴徒）
func _damage_thug_at(loc: int, dmg: int, hid: String) -> void:
	var l: Dictionary = state["locations"][loc]
	var need := 1
	if l["threat"] != null:
		if l["threat"]["name"] == "致残酷刑":
			need = 3
		elif l["threat"]["name"] == "精锐暴徒" or l["threat"]["name"] == "九头蛇精英部队":
			need = 2
		elif l["threat"]["name"] == "雇佣兵":
			need = 2
		elif l["threat"]["name"] == "克里精英部队":
			need = 2
	if need > 1:
		# 简化：本地点所有暴徒共享伤害计数，每 need 伤消灭1个
		var key := "thug_dmg_%d" % loc
		state[key] = state.get(key, 0) + dmg
		var kills: int = state[key] / need
		if kills > 0:
			state[key] = state[key] % need
			_defeat_thug(loc, kills, hid)
		else:
			_log("%s 攻击暴徒（需要 %d 点伤害，已累计 %d/%d）" % [DB.hero_name(hid), need, state[key], need], Color(0.9, 0.8, 0.6))
	else:
		_defeat_thug(loc, dmg, hid)

func _defeat_thug(loc: int, count: int, hid: String = "") -> void:
	var l: Dictionary = state["locations"][loc]
	var n := mini(count, l["thug"])
	if n <= 0:
		return
	l["thug"] -= n
	# 夜魔侠·盲眼正义（裁定 B3）：本回合每击败一个暴徒 → 该英雄获得 1 个移动指示物
	if hid != "" and bool(state["heroes"].get(hid, {}).get("dd_move_on_thug", false)) and n > 0:
		state["heroes"][hid]["tokens"]["move"] += n
		_log("盲眼正义：击败 %d 个暴徒 → +%d 移动指示物" % [n, n], Color(0.9, 0.8, 0.6))
	_log("消灭 %d 个暴徒（%s）" % [n, _loc_name(loc)], Color(0.9, 0.9, 0.7))
	_add_mission_token("defeat", n, hid)
	Events.emit_state_changed()

func _clear_threat(loc: int, hid: String = "") -> void:
	var l: Dictionary = state["locations"][loc]
	var t: Dictionary = l["threat"]
	# 不可清除的威胁卡（神秘客·破碎幻像）：永久留在场上，拦截一切来源的"清除"
	if t.get("unclearable", false):
		_log("【%s】无法被清除：永久留在场上（%s）" % [t["name"], _loc_name(loc)], Color(1, 0.8, 0.5))
		return
	# 背面朝上的威胁卡（神秘客）：未翻开前不可交互，任何来源的"清除"都无效
	if t.get("_face_down", false):
		_log("【%s】背面朝上，未翻开前无法被清除（%s）" % [t["name"], _loc_name(loc)], Color(0.9, 0.85, 0.6))
		return
	_log("威胁清除：%s（%s）" % [t["name"], _loc_name(loc)], Color(0.6, 1, 0.8))
	l["threat"] = null
	l["threat_token"] = false
	# 沙人「更难」：所有「沙尘暴」威胁卡都被清除后，沙人重新可以受到伤害
	if state["villain"] == "sandman" and t["name"] == "沙尘暴" and state.get("sandman_hard", false):
		var still := false
		for fl in state["locations"]:
			var ft: Variant = fl["threat"]
			if ft != null and ft["name"] == "沙尘暴":
				still = true
				break
		if not still:
			state["sandman_hard"] = false
			_log("所有「沙尘暴」威胁卡都被清除：沙人重新可以受到伤害", Color(0.8, 1, 0.8))
	# 绿魔特殊：威胁卡清除后混洗放回绿魔牌堆（可再次被抽出），从供应堆拿威胁指示物放任务牌。
	if state["villain"] == "goblin":
		state["goblin_threat_deck"].append(t)
		state["goblin_threat_deck"].shuffle()
		_add_mission_token("clear", 1, hid)
		_log("绿魔：威胁卡 %s 混洗放回牌堆，供应堆放置 1 个威胁指示物到任务牌" % t["name"], Color(0.7, 1, 0.9))
		Events.emit_state_changed()
		return
	# 记录"被解决的威胁卡"，供洛基行动卡1（幻象大师）取用
	state["solved_threats"].append(t)
	# 无限战争：能量卡若有"威胁"空槽（第7张），可把威胁指示物放到能量卡上代替任务卡（任意顺序）
	var used_for_energy := false
	if state.get("mode", "base") == "iw" and not state.get("final_battle", false):
		for eidx in [int(state.get("table_energy", -1)), int(state.get("hidden_energy", -1))]:
			if eidx < 0:
				continue
			if not energy_can_fill(eidx) or energy_done(eidx):
				continue
			var need: Array = energy_required_syms(eidx)
			var filled_slots: Array = energy_filled_slots(eidx)
			# 找任意一个未填的 threat 槽
			var threat_slot := -1
			for si in range(need.size()):
				if need[si] == "threat" and not filled_slots.has(si):
					threat_slot = si
					break
			if threat_slot >= 0:
				if await _ask_confirm("能量卡需要威胁指示物：把威胁指示物放到能量卡上（代替任务卡）？"):
					filled_slots.append(threat_slot)
					state["energy_tokens"][str(eidx)] = filled_slots
					_log("威胁指示物放到能量卡 %d（%d/%d）" % [energy_local_no(eidx), filled_slots.size(), need.size()], Color(0.9, 0.9, 0.5))
					if filled_slots.size() >= need.size():
						_unlock_energy_card(eidx)
					used_for_energy = true
				break
	if not used_for_energy:
		_add_mission_token("clear", 1, hid)
	Events.emit_state_changed()
	await _step_pause()

## 至圣所回合结束：在"任意地点威胁卡"或"能量卡"上放置 1 个指示物。
## 放置的指示物类型由目标威胁卡决定：普通威胁卡放英勇；罗南 clear 型威胁卡放其所需符号（移动/英勇/攻击）。
## 本地点威胁卡可放则优先放；否则让英雄选择场上任意威胁卡或能量卡。
func _sanctum_place_token(hid: String, loc: int) -> void:
	var l: Dictionary = state["locations"][loc]
	var local_threat: Variant = l["threat"]
	# 本地点威胁卡可放（未清除）：优先直接放一个符合条件的指示物
	# （判定条件统一用 _threat_placeable_sym：涵盖 hp==0 的普通/罗南型，以及 hp>0 但带 clear 槽的泽莫型）
	if local_threat != null and _threat_placeable_sym(local_threat) != "":
		var local_sym: String = _threat_placeable_sym(local_threat)
		if local_sym != "":
			if await _ask_confirm("至圣所：在本地威胁卡上放置 1 个%s指示物？" % DB.symbol_name(local_sym)):
				_place_threat_token(hid, loc, local_sym)
			return
	# 本地点无威胁卡 / 威胁卡无可放符号：收集可选目标（场上任意可放的威胁卡 + 能量卡），让英雄选择
	var opts: Array = []
	var targets: Array = []   # 与 opts 一一对应：{"type":"threat","loc":i,"sym":s} / {"type":"energy","eidx":j,"slot":k}
	var threat_found := false
	for i in range(LOCATION_COUNT):
		var t: Variant = state["locations"][i]["threat"]
		if t != null and _threat_placeable_sym(t) != "":
			var sym: String = _threat_placeable_sym(t)
			if sym != "":
				opts.append("%s\n%s（放%s）" % [_loc_name(i), t["name"], DB.symbol_name(sym)])
				targets.append({"type": "threat", "loc": i, "sym": sym})
				threat_found = true
	# 场上没有可放置指示物的威胁卡：不触发此效果（即使有能量卡）
	if not threat_found:
		_log("至圣所：场上没有可放置指示物的威胁卡，效果不触发", Color(0.8, 0.9, 0.9))
		return
	# 能量卡（无限战争）：可填入的槽（优先"threat"槽，其次任意空槽）
	if state.get("mode", "base") == "iw" and not state.get("final_battle", false):
		for eidx in [int(state.get("table_energy", -1)), int(state.get("hidden_energy", -1))]:
			if eidx < 0:
				continue
			if not energy_can_fill(eidx) or energy_done(eidx):
				continue
			var need: Array = energy_required_syms(eidx)
			var filled: Array = energy_filled_slots(eidx)
			for si in range(need.size()):
				if not filled.has(si):
					opts.append("能量卡 %d\n（%d/%d）" % [energy_local_no(eidx), filled.size(), need.size()])
					targets.append({"type": "energy", "eidx": eidx, "slot": si})
					break
	if opts.is_empty():
		_log("至圣所：场上没有可放置指示物的威胁卡或能量卡", Color(0.8, 0.9, 0.9))
		return
	# 追加"放弃"（可取消，至圣所文案"可以...放置"，无强制字眼）
	opts.append("放弃（不放置指示物）")
	targets.append({"type": "none"})
	var choice: int = await _ask("至圣所：选择要放置 1 个指示物的目标", opts)
	var tgt: Dictionary = targets[wrapi(int(choice), 0, targets.size())]
	if tgt["type"] == "none":
		return
	if tgt["type"] == "threat":
		_place_threat_token(hid, int(tgt["loc"]), tgt["sym"])
	else:
		var eidx: int = int(tgt["eidx"])
		var filled2: Array = energy_filled_slots(eidx)
		if not filled2.has(int(tgt["slot"])):
			filled2.append(int(tgt["slot"]))
			state["energy_tokens"][str(eidx)] = filled2
			_log("至圣所：威胁指示物放到能量卡 %d（%d/%d）" % [energy_local_no(eidx), filled2.size(), energy_required_syms(eidx).size()], Color(0.7, 1, 0.9))
			if filled2.size() >= energy_required_syms(eidx).size():
				_unlock_energy_card(eidx)
	Events.emit_state_changed()

## 返回某威胁卡当前还能放置的符号类型；无可放符号返回 ""。
## 普通威胁卡（hp==0 且无 clear）→ "heroic"（英勇槽未满）。罗南 clear 型 → clear 中尚未填满的符号。
func _threat_placeable_sym(t: Dictionary) -> String:
	# 背面朝上的威胁卡（神秘客）不可交互：需先花费任意行动翻开
	if t.get("_face_down", false):
		return ""
	# 不可清除的威胁卡（神秘客·破碎幻像）：翻开后永久留在场上，任何行动都放不上指示物
	if t.get("unclearable", false):
		return ""
	# 爪牙型威胁卡（hp>0）靠攻击击败；但卡面同时写了"同一回合内用 N 个英勇行动击败"的
	# （泽莫男爵的 6 张威胁卡）——此时 clear 槽仍然可放，所以先判 clear 再判 hp。
	if t.has("clear"):
		var syms: Array = t["clear"]
		# 找出 clear 中还未填满的符号（任意一个可放的）；若多个可放，优先移动>攻击>英勇
		for sym in ["move", "attack", "heroic"]:
			if _sym_can_fill(t, sym):
				return sym
		return ""
	# 爪牙型威胁卡（hp>0）靠攻击击败，没有任何"放置指示物"的槽 → 不可放
	if int(t.get("hp", 0)) > 0:
		return ""
	if int(t.get("heroic_tokens", 0)) >= THREAT_CLEAR_TOKENS:
		return ""
	return "heroic"

## 威胁卡是否还能用 sym 符号填一次（罗南 clear 型专用）。
func _sym_can_fill(t: Dictionary, sym: String) -> bool:
	if t == null or not t.has("clear"):
		return false
	var clear: Array = t["clear"]
	var filled: Array = t.get("clear_progress", [])
	return filled.count(sym) < clear.count(sym)

## 向威胁卡放置 1 个符号指示物。放置的符号由该威胁卡"需要什么行动"决定（_threat_placeable_sym）：
##   普通威胁卡（无 clear）→ 英勇；罗南/绿魔等 clear 型 → 其 clear 数组中尚未填满的符号（移动/攻击/英勇）。
## subject 为主体名（至圣所/克林监狱等），仅用于日志显示，不同主体复用此底层规则。
func _place_threat_token(hid: String, loc: int, sym: String = "", subject: String = "至圣所") -> void:
	var t: Dictionary = state["locations"][loc]["threat"]
	if t == null:
		return
	# 看该威胁卡需要什么行动符号（需求驱动；若外部传的符号为空/不符则用需求符号）
	var need: String = _threat_placeable_sym(t)
	if need == "":
		_log("%s：%s 的威胁卡没有可放置的符号" % [subject, t["name"]], Color(0.8, 0.9, 0.9))
		return
	if t.has("clear"):
		var filled: Array = t.get("clear_progress", [])
		filled.append(need)
		t["clear_progress"] = filled
		_log("%s：%s 的威胁卡放置 %s 指示物（%d/%d）" % [subject, t["name"], DB.symbol_name(need), filled.size(), t["clear"].size()], Color(0.7, 1, 0.9))
		if filled.size() >= t["clear"].size():
			_clear_threat(loc)
	else:
		t["heroic_tokens"] = int(t.get("heroic_tokens", 0)) + 1
		_log("%s：%s 的威胁卡英勇指示物 %d/%d" % [subject, t["name"], t["heroic_tokens"], THREAT_CLEAR_TOKENS], Color(0.7, 1, 0.9))
		if int(t["heroic_tokens"]) >= THREAT_CLEAR_TOKENS:
			_clear_threat(loc)
	Events.emit_state_changed()

func _add_mission_token(mission_id: String, n: int, hid: String = "") -> void:
	for m in state["missions"]:
		if m["id"] == mission_id and not m.get("done", false):
			var add := mini(n, m["slots"] - m["tokens"])
			m["tokens"] += add
			if m["tokens"] >= m["slots"]:
				_complete_mission(m, hid)
			return

func _complete_mission(m: Dictionary, hid: String = "") -> void:
	state["missions_completed"] += 1
	var actor: String = hid if hid != "" else (state["hero_ids"][state["current_hero"]] if state["hero_ids"].size() > 0 else "")
	m["done"] = true
	m["tokens"] = 0
	_log("🎯 任务完成：%s！（已完成 %d/3）" % [m["name"], state["missions_completed"]], Color(0.5, 1, 0.5))
	Events.mission_completed.emit(state["missions_completed"], actor)
	if Net.active and Net.is_host:
		Net.broadcast_mission_completed(state["missions_completed"], actor)

	match state["missions_completed"]:
		1:
			_log("反派进入高压状态：每 2 张英雄牌触发一次反派回合", Color(1, 0.8, 0.4))
		2:
			if state["challenge"] == "traitor" and not state["traitor_revealed"]:
				# 不在此处立即指认：任务可能在英雄行动中途完成，立即 await 会与"回合地点结算/反派回合"交错乱序。
				# 只打标记，等本回合流程走到"地点结算之后、进入反派回合之前"再按顺序执行指认。
				state["traitor_pending"] = true
				_log("🕵 已达成 2 个任务：本回合结束（地点结算后）将进行指认叛徒", Color(1, 0.8, 0.4))
			_log("解锁攻击反派权限！", Color(1, 0.9, 0.3))
		3:
			for hh in state["hero_ids"]:
				_draw_card(hh)
			_log("所有英雄各抽 1 张牌", Color(0.7, 1, 0.9))
	# B计划挑战：完成全部 3 张专属任务卡 → 英雄直接获胜
	if state["challenge"] == "planb" and state["missions_completed"] >= 3 and state["phase"] != "game_over":
		_log("🏆 B计划达成：三张任务卡全部完成，英雄们直接获胜！", Color(0.5, 1, 0.5))
		_win()
		return

# ---- heroic

func _execute_heroic(hid: String, consumed: String) -> void:
	await _gain_exposure(hid, "使用英勇行动")
	# 螳螂女·星体投射（裁定①）：英勇行动同样可"如同在任选地点"（本人位置不变）
	if bool(state["heroes"].get(hid, {}).get("astral_turn", false)):
		var _al2: int = await _astral_pick_loc(hid, "星体投射：这次英勇行动如同你在哪个地点？")
		if _al2 >= 0:
			state["_astral_loc"] = _al2
	var h: Dictionary = state["heroes"][hid]
	var loc: int = h["location"]
	# 星体投射：本次英勇行动如同在 `_astral_loc` 那个地点（本人 location 字段不动）。
	# 注意：必须在同一处立刻消费掉这个临时值，否则会漏给下一个行动（攻击那边同理）。
	if int(state.get("_astral_loc", -1)) >= 0:
		loc = int(state["_astral_loc"])
		state["_astral_loc"] = -1
	var l: Dictionary = state["locations"][loc]
	var options: Array = []
	var rescue_cost := 1
	var explosive := false
	if l["threat"] != null:
		if l["threat"]["name"] == "爆炸陷阱":
			rescue_cost = 2
			explosive = true
		elif l["threat"]["name"] == "战俘营地":
			rescue_cost = 2
		elif l["threat"]["name"] == "危及平民":
			rescue_cost += 1   # 章鱼博士威胁：该地点的每个平民需多花 1 个行动指示物才能获救
	if l["civ"] > 0:
		options.append({"icon": "heroic", "arrow": "heroic", "text": "营救平民（需%d英勇）" % rescue_cost, "img": "res://assets/tokens/civ_token.png", "hide_text": true})
	# hp==0 的普通/罗南型威胁卡可放；hp>0 但带 clear 槽的（泽莫男爵）同样可用英勇行动填充
	if l["threat"] != null and _threat_placeable_sym(l["threat"]) != "" and not l["threat"].get("_face_down", false) and not l["threat"].get("unclearable", false):
		if l["threat"].has("clear"):
			# 罗南威胁卡：用英勇行动填充（作为英勇选项之一，与正常威胁卡一致）
			if _ronan_threat_can_fill(loc, "heroic"):
				options.append({"icon": "heroic", "arrow": "heroic", "text": "用英勇行动填充威胁（%d/%d）" % [_ronan_threat_filled(loc), _ronan_threat_size(loc)], "img": "res://assets/cards/villains/%s/threat_back.png" % state["villain"], "card": "threat", "hide_text": true})
		else:
			options.append({"icon": "heroic", "arrow": "heroic", "text": "放置英勇指示物清除威胁（%d/3）" % (l["threat"]["heroic_tokens"] + 1), "img": "res://assets/cards/villains/%s/threat_back.png" % state["villain"], "card": "threat", "hide_text": true})
	if state["villain"] == "taskmaster" and l["civ"] == 0 and l["thug"] == 0 and l["crisis"] > 0:
		options.append({"icon": "heroic", "arrow": "heroic", "text": "清除 1 个危机指示物"})
	# 绿魔：只有英雄在绿魔所在地点，才能用两次英勇行动营救 1 个绿魔面板上的平民
	if state["villain"] == "goblin" and int(state.get("goblin_panel_civ", 0)) > 0 and loc == state["villain_pos"]:
		options.append({"icon": "heroic", "arrow": "heroic", "text": "营救绿魔面板平民（需2英勇）", "img": "res://assets/tokens/civ_token.png", "hide_text": true})
	# 邪恶六人组：与该反派同地点 → 可用英勇行动化解他弱点卡的英勇槽（每个反派各占一行，同一个弹窗）
	var wv_heroic: String = ""
	var weak_h_vids: Array = []
	if state.get("mode", "") == "s6":
		weak_h_vids = _s6_weak_candidates(hid).filter(func(v): return _s6_can_fill(String(v), "heroic"))
		for _wv2 in weak_h_vids:
			var w2: Dictionary = _s6()["vills"][_wv2]
			var f2 := 0
			for f in (w2["weak_filled"] as Array):
				if int(f) == 1:
					f2 += 1
			options.append({"icon": "heroic", "img": "res://assets/cards/s6/weak_%02d.png" % int(DB.s6["weak"][_wv2]["img"]), "text": "化解弱点卡（%s %d/3）" % [DB.villain_name(String(_wv2)), f2], "card": "threat"})
		if weak_h_vids.size() > 0:
			wv_heroic = String(weak_h_vids[0])
	if options.size() == 0:
		Events.emit_toast("此地没有可用的英勇行动")
		return
	options.append({"text": "跳过行动"})
	options.append({"text": "返回"})
	var choice = await _ask_action("英勇行动：选择", options)
	var ci := int(choice)
	if wv_heroic != "" and ci < options.size() - 2 and ci >= options.size() - 2 - weak_h_vids.size():
		_s6_fill_weak(hid, String(weak_h_vids[ci - (options.size() - 2 - weak_h_vids.size())]), "heroic")
		Events.emit_state_changed()
		await _maybe_auto_end_turn()
		return
	if ci >= options.size() - 2:
		if ci == options.size() - 1:
			# 返回：归还本次消耗的英勇行动，重新选择行动
			_refund_symbol(hid, "heroic", consumed)
			_log("%s 返回（英勇行动已归还）" % DB.hero_name(hid), Color(0.8, 0.8, 0.8))
			Events.emit_state_changed()
			return
		# 跳过：放弃该行动，英勇数量减一（不归还）
		_log("%s 跳过英勇行动" % DB.hero_name(hid), Color(0.8, 0.8, 0.8))
		Events.emit_state_changed()
		return
	var picked: String = str(options[ci]["text"])
	if picked.contains("营救平民"):
		if explosive or rescue_cost > 1:
			var ok := _consume_extra_heroic(rescue_cost - 1)
			if ok:
				_rescue_civ(hid, loc)
		else:
			_rescue_civ(hid, loc)
	elif picked.contains("放置英勇"):
		l["threat"]["heroic_tokens"] += 1
		_log("%s 在威胁卡上放置英勇指示物（%d/3）" % [DB.hero_name(hid), l["threat"]["heroic_tokens"]], Color(0.7, 1, 0.9))
		if l["threat"]["heroic_tokens"] >= THREAT_CLEAR_TOKENS:
			_clear_threat(loc)
	elif picked.contains("填充威胁"):
		_fill_ronan_threat(hid, loc, "heroic")
	elif picked.contains("危机"):
		l["crisis"] -= 1
		_log("%s 清除 1 个危机指示物（%s）" % [DB.hero_name(hid), _loc_name(loc)], Color(0.7, 0.7, 1))
	elif picked.contains("绿魔面板"):
		# 绿魔：用两次英勇营救 1 个绿魔面板上的平民（需额外消耗 1 个英勇）
		if await _consume_extra_heroic(1):
			state["goblin_panel_civ"] = int(state.get("goblin_panel_civ", 0)) - 1
			_add_mission_token("rescue", 1, hid)
			_log("%s 营救了 1 个绿魔面板平民（面板剩余 %d）" % [DB.hero_name(hid), maxi(state.get("goblin_panel_civ", 0), 0)], Color(0.7, 1, 0.9))
	Events.emit_state_changed()
	await _maybe_auto_end_turn()

func _consume_extra_heroic(n: int) -> bool:
	var got := 0
	while got < n:
		var idx: int = state["action_symbols"].find("heroic")
		if idx != -1:
			state["action_symbols"].remove_at(idx)
			got += 1
		else:
			var hid: String = state["hero_ids"][state["current_hero"]]
			var pool: Dictionary = state["shield_tokens"] if state["mode"] == "shield" else state["heroes"][hid]["tokens"]
			if int(pool["heroic"]) - state["used_tokens"]["heroic"] > 0:
				state["used_tokens"]["heroic"] += 1
				got += 1
			else:
				break
	if got < n:
		Events.emit_toast("英勇行动不足（该营救需要额外 %d 个英勇）" % n)
		state["action_symbols"].append("heroic")
		return false
	return true

func _rescue_civ(hid: String, loc: int) -> void:
	var l: Dictionary = state["locations"][loc]
	l["civ"] -= 1
	_log("%s 营救 1 名平民（%s）" % [DB.hero_name(hid), _loc_name(loc)], Color(0.8, 1, 0.9))
	_add_mission_token("rescue", 1, hid)
	if bool(state["heroes"][hid].get("dd_move_on_rescue", false)):
		state["heroes"][hid]["tokens"]["move"] += 1
		_log("无畏之人：营救平民 +1 移动指示物", Color(0.9, 0.8, 0.6))
	Events.emit_state_changed()

# ---------------------------------------------------------------- card effect

# ---------------------------------------------------------------- 第一季众筹英雄效果：通用辅助

## 英雄的行动指示物池（神盾局模式为玩家共享池）
func _hero_token_pool(hid: String) -> Dictionary:
	return state["shield_tokens"] if state["mode"] == "shield" else state["heroes"][hid]["tokens"]

## 某地点上可作为攻击/伤害对象的敌人清单（暴徒 / 爪牙 / 反派；邪恶六人组为已化解弱点的反派）
func _enemy_targets_at(loc: int) -> Array:
	var l: Dictionary = state["locations"][loc]
	var out: Array = []
	if int(l["thug"]) > 0:
		out.append("thug")
	if l["threat"] != null and int(l["threat"]["hp"]) > 0 and not l["threat"].get("_face_down", false):
		out.append("henchman:" + String(l["threat"]["name"]))
	if state["missions_completed"] >= 2 and state["villain_pos"] == loc and state["villain_hp"] > 0:
		if not (state["villain"] == "taskmaster" and int(l["crisis"]) > 0):
			out.append("villain")
	if state.get("mode", "") == "s6":
		out = out.filter(func(t): return String(t) != "villain")
		for svid in _s6_at(loc):
			if bool(_s6()["vills"][svid].get("weak_done", false)):
				out.append("s6:" + String(svid))
	return out

## 敌人目标选择行（图形口径与 _attack_once_at 一致）
func _enemy_target_rows(loc: int, targets: Array) -> Array:
	var rows: Array = []
	var vid_now: String = state["villain"]
	var vill_back: String = "" if state.get("mode", "") == "s6" else String(DB.villain(vid_now)["back"])
	var threat_back: String = "res://assets/cards/villains/%s/threat_back.png" % vid_now
	for t in targets:
		var ts := String(t)
		var t_img := vill_back
		if ts == "thug":
			t_img = "res://assets/tokens/thug_token.png"
		elif ts.begins_with("s6:"):
			t_img = String(DB.villain(ts.substr(3))["back"])
		elif ts.begins_with("henchman"):
			var ht: Dictionary = state["locations"][loc]["threat"]
			if ht.has("_tidx"):
				t_img = "res://assets/cards/villains/%s/threat_%02d.png" % [vid_now, int(ht["_tidx"]) + 1]
			else:
				t_img = threat_back
		var rrow := {"icon": "attack", "arrow": "attack", "text": _target_name(ts), "img": t_img, "hide_text": true}
		if ts.begins_with("henchman"):
			rrow["card"] = "threat"
		rows.append(rrow)
	return rows

## 效果驱动的移动：在候选地点中选一个并直接移动（不消耗行动符号）。
## 返回移动后的地点下标；-1 表示没有可移动的地点。
func _effect_move_to(hid: String, cands: Array, title: String, icon: String = "move") -> int:
	var h: Dictionary = state["heroes"][hid]
	var rows: Array = []
	var locs: Array = []
	for c in cands:
		var ci := int(c)
		if ci < 0 or ci >= LOCATION_COUNT:
			continue
		if state["locations"][ci].get("destroyed", false):
			continue
		if ci == int(h["location"]):
			continue
		var ld: Dictionary = DB.location(state["locations"][ci]["id"])
		rows.append({"icon": icon, "arrow": "move", "text": _loc_name(ci), "bottom": String(ld.get("image", ""))})
		locs.append(ci)
	if rows.size() == 0:
		Events.emit_toast("没有可移动的地点")
		return -1
	var pick: int = int(await _ask_action(title, rows))
	var tgt: int = int(locs[wrapi(pick, 0, locs.size())])
	await _set_hero_loc(hid, tgt)   # 效果移动（A1：统一出口）
	_log("%s 移动到 %s" % [DB.hero_name(hid), _loc_name(tgt)], Color(0.8, 0.9, 1))
	Events.emit_state_changed()
	return tgt

## 多重集差集：从 a 中移除 b 里出现过的元素（按出现次数计）
func _multiset_sub(a: Array, b: Array) -> Array:
	var out: Array = a.duplicate()
	for x in b:
		var i: int = out.find(x)
		if i != -1:
			out.remove_at(i)
	return out

## 统计故事情节中最近 n 张正面朝上的英雄卡印刷的 sym 符号数（默认跳过当前刚打出的这张）
func _count_recent_story_symbols(sym: String, n: int, skip_top: bool = true) -> int:
	var count := 0
	var found := 0
	var skipped := false
	for i in range(state["story"].size() - 1, -1, -1):
		var entry: Dictionary = state["story"][i]
		if String(entry.get("type", "")) != "hero":
			continue
		if entry.get("face_down", false):
			continue
		if skip_top and not skipped:
			skipped = true
			continue
		skipped = true
		# 泽莫男爵（裁定①）：被危机指示物盖住的符号永久失效，其它效果也不能引用
		for s in _entry_uncovered_symbols(entry):
			if String(s) == sym:
				count += 1
		found += 1
		if found >= n:
			break
	return count

## 环上正对面的地点（相隔 3 格）；若它已被摧毁，则取存活环上最接近"对面"的地点
func _opposite_loc(loc: int) -> int:
	var direct: int = (loc + 3) % LOCATION_COUNT
	if not state["locations"][direct].get("destroyed", false):
		return direct
	var live: Array = _live_locs()
	if live.size() <= 1:
		return loc
	var best: int = loc
	var best_score := -999999
	for c in live:
		var ci := int(c)
		if ci == loc:
			continue
		var d: int = _live_ring_dist(loc, ci)
		var score: int = -absi(d * 2 - live.size())   # 越接近半个环越"对面"
		if score > best_score:
			best_score = score
			best = ci
	return best

## 蚁人·量子跃迁：把这张牌与故事情节上任意一张正面朝上的英雄卡交换，
## 随后按交换到的那张卡重新结算（符号 + 效果都按该卡，用户口径 2）。
func _antman_quantum_leap(hid: String) -> void:
	if state.get("ql_busy", false):
		_log("量子跃迁：本回合已经跃迁过一次，无法再次交换", Color(0.8, 0.8, 0.8))
		return
	var story: Array = state["story"]
	var cur_i: int = story.size() - 1
	if cur_i < 0 or String(story[cur_i].get("type", "")) != "hero":
		_log("量子跃迁：故事情节里没有可交换的牌", Color(0.8, 0.8, 0.8))
		return
	var rows: Array = []
	var idxs: Array = []
	for i in range(cur_i):
		var e: Dictionary = story[i]
		if String(e.get("type", "")) != "hero" or e.get("face_down", false):
			continue
		rows.append({"img": UiKit.hero_card_image(String(e["hero"]), int(e["idx"])),
			"text": "%s · %s" % [DB.hero_name(String(e["hero"])), _card_desc(String(e["hero"]), int(e["idx"]))]})
		idxs.append(i)
	if idxs.size() == 0:
		_log("量子跃迁：故事情节里没有其他正面朝上的英雄卡，无效", Color(0.8, 0.8, 0.8))
		return
	var pick: int = int(await _ask_action("量子跃迁：选择要与这张牌交换的故事情节卡牌", rows))
	var j: int = int(idxs[wrapi(pick, 0, idxs.size())])
	var swapped: Dictionary = story[j]
	# 交换：量子跃迁占原来那张牌的位置，被换出的牌落到本回合最新的位置
	story[j] = story[cur_i]
	story[cur_i] = swapped
	state["ql_busy"] = true
	var sh: String = String(swapped["hero"])
	var si: int = int(swapped["idx"])
	var scard: Dictionary = DB.hero_cards(sh)[si]
	# 符号重新结算：换成新卡的印刷符号 + 仍保留的继承符号；本回合已用掉的符号不返还
	var prev: Array = (state.get("prev_hero_symbols", []) as Array).duplicate()
	var cur: Array = (state["action_symbols"] as Array).duplicate()
	var used: Array = _multiset_sub(prev, cur)
	var extra: Array = _multiset_sub(cur, prev)
	var new_syms: Array = _multiset_sub((scard["symbols"] as Array).duplicate() + prev, used)
	new_syms.append_array(extra)
	state["action_symbols"] = new_syms
	var sym_txt: Array = []
	for s in new_syms:
		sym_txt.append(DB.symbol_name(String(s)))
	_log("量子跃迁：与 %s 的「%s」交换，按该卡重新结算（符号：%s）"
		% [DB.hero_name(sh), _card_desc(sh, si), "、".join(sym_txt) if sym_txt.size() > 0 else "无"], Color(0.8, 0.9, 1))
	# 效果重新结算：换成新卡的效果，玩家可再次点击"发动效果"按钮
	var seff: Variant = scard.get("effect", null)
	if seff == null:
		state["played_effect"] = null
		state["effect_available"] = false
		state["effect_used"] = true
	else:
		var stype: String = String(seff.get("type", ""))
		state["played_effect"] = seff
		if stype == "cartoon_web" or stype == "miles_web":
			# 被动型效果：按被动处理，不占用效果按钮
			state["heroes"][hid][stype + "_armed"] = true
			state["effect_available"] = false
			state["effect_used"] = true
			_log("量子跃迁：按「%s」的被动效果标记" % String(seff.get("name", "")), Color(0.8, 0.9, 1))
		else:
			state["effect_available"] = true
			state["effect_used"] = false
			_log("量子跃迁：可再次点击「发动效果」按钮结算「%s」" % String(seff.get("name", "")), Color(0.8, 0.9, 1))
	Events.emit_state_changed()

## ---------------------------------------------------------------- 联机（局域网）
## 主机权威：客户端把操作作为"意图"发给主机；主机只有当前英雄的玩家能操作。
## 返回 true = 已被拦截，调用方应直接 return。

var _net_remote := false        ## 正在执行来自客户端的意图（不要再次转发）
var net_auto_start := false     ## 联机开局：主机的 Board 就绪后自动开始第一个反派回合
## 本弹窗该由"哪个英雄的玩家"回答（空 = 当前行动英雄）。
## 弃牌/看牌库/濒危地点守卫这类弹窗的目标是某个具体英雄，而不是"当前英雄"——
## 以前一律按当前英雄算，导致"该他选的人"被判成不能选，界面显示"等待其他玩家选择"→ 直接卡死。
var _prompt_answer_hero := ""

func _prompt_who(answer_hero: String = "") -> String:
	if answer_hero != "":
		return answer_hero
	if _prompt_answer_hero != "":
		return _prompt_answer_hero
	return current_hero_id()

func _net_gate(intent: String, args: Array) -> bool:
	if not Net.active or _net_remote:
		return false
	if Net.is_host:
		return not Net.is_my_turn()
	# 客户端：不是我的操作就直接忽略（连意图都不发；主机侧也会再校验一次）
	if not Net.is_my_turn():
		return true
	Net.send_intent(intent, args)
	return true

## 主机：执行来自客户端的意图
func apply_net_intent(name: String, args: Array) -> void:
	_net_remote = true
	match name:
		"play_card":
			await play_card(int(args[0]))
		"use_symbol":
			await use_symbol(String(args[0]))
		"trigger_effect":
			await trigger_effect()
		"end_actions":
			await end_actions()
		"end_turn":
			await end_turn()
		"reveal_threat_choice":
			await reveal_threat_choice()
		"play_face_down_choice":
			await play_face_down_choice()
		"move_reporter_choice":
			await move_reporter_choice()
		"undo_last":
			undo_last()
	_net_remote = false
	Net.broadcast_snapshot()

## 主机：把客户端对弹窗的回答喂回正在等待的 _ask_* 协程
func apply_net_answer(kind: String, value: Variant) -> void:
	match kind:
		"choice", "action", "confirm":
			_on_answer(value)
		"hand":
			_on_hand_answered(value)
		"story":
			_on_story_answered(value)
		"deck":
			_on_deck_answered(value)
		"hero":
			_on_hero_answered(value)
		"villain_card":
			_on_villain_card_answered(value)
		"reorder":
			_on_reorder_answered(value)

## 让玩家从"有敌人的地点"里选一个来打（用于"在相邻/任意地点攻击"这类效果）。
## 返回地点索引；没有任何可打的地点时返回 -1（并给一条提示）。
## 第二批·钩子：英雄进入某地点后，结算"每进入一个地点"类效果（快银 / 夜魔侠）
## 统一出口（裁定 A1）：英雄位置"真正改变"时只在这里通知「进入地点」类钩子。
## 为什么不直接在各处调钩子：移动来源很多（移动行动、卡效果、地点效果、被别的效果推动…），
## 裁定要求所有来源都算，所以收敛到这一个赋值出口。原地不动不触发；出发地不算。
var _enter_hook_depth := 0   # 只在"携带英雄"期间 >0：被携带的英雄不再触发携带（防无限递归），其余钩子照常

func _set_hero_loc(hid: String, loc: int, reason: String = "") -> void:
	var h: Dictionary = state["heroes"][hid]
	var old: int = int(h["location"])
	h["location"] = loc
	if loc < 0 or loc == old:
		return
	await _on_hero_entered_loc(hid, loc, old, reason)

## loc = 新地点（"进入"的地点），from = 出发地（携带类钩子要按出发地找同伴）。
## reason = "forced" 表示"不是英雄自己移动"（被秃鹫吹飞、被章鱼博士拉走/挤出）——
## 这种情况仍然算"进入一个地点"（雷达感官/速度格斗/奔赴救援都触发），但不算"你移动"，
## 所以不触发快银·超人速度的携带。
func _on_hero_entered_loc(hid: String, loc: int, from: int = -1, reason: String = "") -> void:
	var h: Dictionary = state["heroes"][hid]
	# 快银·超人速度：可携带"离开时与你同地点"的其他英雄一起移动（他们一起进到新地点）
	if _enter_hook_depth == 0 and reason != "forced" and bool(h.get("qs_carry_heroes", false)) and from >= 0:
		var go: Array = []
		for hh in state["hero_ids"]:
			if hh != hid and int(state["heroes"][hh]["location"]) == from and not bool(state["heroes"][hh]["ko"]):
				go.append(hh)
		if go.size() > 0 and await _ask_confirm("超人速度：携带%s的其他英雄一起过来？" % _loc_name(from)):
			_enter_hook_depth += 1
			for hh in go:
				await _set_hero_loc(String(hh), loc)   # 被快银携带（A1：被携带也算"进入"，会走各自的进入钩子）
			_enter_hook_depth -= 1
			_log("超人速度：%s 一起被带到 %s" % ["、".join(go.map(func(x): return DB.hero_name(String(x)))), _loc_name(loc)], Color(0.8, 0.95, 1))
	if bool(h.get("qs_defeat_on_enter", false)):
		if int(state["locations"][loc]["thug"]) > 0:
			_log("速度格斗：%s 进入 %s，自动击败 1 个暴徒" % [DB.hero_name(hid), _loc_name(loc)], Color(1, 0.8, 0.6))
			_defeat_thug(loc, 1, hid)   # 走统一减员出口：算任务进度，并触发"击败暴徒"类钩子
	if bool(h.get("qs_rescue_on_enter", false)):
		var rl: Dictionary = state["locations"][loc]
		if int(rl["civ"]) > 0:
			await _rescue_civ(hid, loc)
	if bool(h.get("dd_token_on_enter", false)):
		var dd_rows: Array = [
			{"icon": "heroic", "text": "获得 1 个英勇指示物"},
			{"icon": "attack", "text": "获得 1 个攻击指示物"},
		]
		var dd_p: int = int(await _ask_action("雷达感官：选择获得的指示物", dd_rows))
		var dd_key: String = "attack" if dd_p == 1 else "heroic"
		h["tokens"][dd_key] += 1
		_log("雷达感官：%s 进入 %s，获得 1 个%s指示物" % [DB.hero_name(hid), _loc_name(loc), DB.symbol_name(dd_key)], Color(0.9, 0.8, 0.7))
	Events.emit_state_changed()
func _pick_attack_loc(hid: String, cands: Array, title: String) -> int:
	var rows: Array = []
	var locs: Array = []
	for c in cands:
		var ci := int(c)
		if ci < 0 or ci >= LOCATION_COUNT:
			continue
		if _enemy_targets_at(ci).size() == 0:
			continue
		var ld: Dictionary = DB.location(state["locations"][ci]["id"])
		rows.append({"icon": "attack", "arrow": "attack", "text": _loc_name(ci), "bottom": String(ld.get("image", ""))})
		locs.append(ci)
	if rows.is_empty():
		return -1
	var pick: int = int(await _ask_action(title, rows))
	return int(locs[wrapi(pick, 0, locs.size())])
## 螳螂女·星体投射（裁定①）：让玩家为"本次行动"选一个地点（如同你在那里）。
## 返回选中的地点索引；选"就在我所在地点"或没有别的可选时返回 -1（表示用真实位置）。
## 注意：本人实际位置不变，别人对你的位置判定/伤害/溢出仍按真实位置算。
func _astral_pick_loc(hid: String, title: String) -> int:
	var h: Dictionary = state["heroes"][hid]
	var here: int = int(h["location"])
	var rows: Array = [{"icon": "heroic", "text": "就在我所在地点（%s）" % _loc_name(here)}]
	var locs: Array = [-1]
	for i in range(LOCATION_COUNT):
		if i == here or state["locations"][i].get("destroyed", false):
			continue
		var ld: Dictionary = DB.location(state["locations"][i]["id"])
		rows.append({"icon": "heroic", "arrow": "heroic", "text": _loc_name(i), "bottom": String(ld.get("image", ""))})
		locs.append(i)
	if locs.size() == 1:
		return -1
	var pick: int = int(await _ask_action(title, rows))
	return int(locs[wrapi(pick, 0, locs.size())])
## 故事情节"可见区"口径（裁定③）：棋盘故事情节区一屏显示最近 STORY_VISIBLE 张，
## 所以"某张卡还在可见区" = 它在 story 数组里位于最后 STORY_VISIBLE 个之内。
##
## ⚠️ 这个数必须等于**棋盘故事情节区一屏实际能显示的张数**，否则会"看着还在、程序却认为已离开"。
## 实测推导（Board.gd 的 _story_scroll / _story_box）：
##   滚动区宽 780px；每张卡 46px + 间距 2px = 48px → 780 / 48 = 16.25 → 一屏 16 张。
## 之前写成 6（随手拍的），导致玩家刚往故事情节里放 3 张牌，球卡就被判"已离开可见区"、效果停掉。
## 若以后改故事情节区的宽度/卡片尺寸，务必同步这个常量。
const STORY_VISIBLE := 16

## 惩罚者·精准射击（裁定⑦）：本回合你造成的伤害无视一切"取消/忽略/减少"（秃鹫持物、神秘客诱饵、
## 洛基幻象、超级坚甲、沙人硬化、克莱文诱饵等全部无效）。
func _dmg_uncancellable() -> bool:
	return bool(state.get("dmg_uncancellable_turn", false))

func _villain_top_public_now() -> bool:
	var story: Array = state.get("story", [])
	var from: int = maxi(story.size() - STORY_VISIBLE, 0)
	for i in range(from, story.size()):
		var e: Dictionary = story[i]
		if String(e.get("type", "")) != "hero" or bool(e.get("face_down", false)):
			continue
		var hh: String = String(e.get("hero", ""))
		var ci: int = int(e.get("idx", -1))
		if hh == "" or ci < 0 or ci >= DB.hero_cards(hh).size():
			continue
		if String(DB.hero_cards(hh)[ci].get("effect", {}).get("type", "")) == "drstrange_orb_of_agamotto":
			return true
	return false

func trigger_effect() -> void:
	if _net_gate("trigger_effect", []):
		return
	if state["phase"] != "hero_actions":
		return
	if not state.get("effect_available", false) or state.get("effect_used", false):
		return
	var hid: String = state["hero_ids"][state["current_hero"]]
	await _gain_exposure(hid, "使用英雄卡特殊能力")
	if state["phase"] == "game_over":
		return
	state["effect_used"] = true
	state["in_effect"] = true   # 效果结算期间不提前结束回合（由本函数末尾统一判定）
	var eff: Dictionary = state.get("played_effect", {})
	_log("%s 发动效果：%s" % [DB.hero_name(hid), eff.get("name", "")], Color(0.9, 0.9, 0.4))
	match eff["type"]:
		"give_wild", "give_wild_x2":
			var n := 1 if eff["type"] == "give_wild" else 2
			# 神盾局单人：指示物直接给玩家共享池（无需选英雄）
			if state["mode"] == "shield":
				state["shield_tokens"]["wild"] += n
				_log("供应池 +%d 万能指示物（玩家）" % n, Color(0.9, 0.9, 0.5))
				state["in_effect"] = false
				return
			# 选择获得万能指示物的英雄：
			# 领导力（give_wild）卡面为"给另一个英雄"→ 排除自己；单英雄局退化为给自己
			# 斯塔克资源/高级战斗分析（give_wild_x2）卡面为"任意英雄"→ 含自己
			var targets: Array = state["hero_ids"].duplicate()
			if eff["type"] == "give_wild":
				targets.erase(hid)
				if targets.size() == 0:
					targets = [hid]
			var tid := hid
			if targets.size() > 1:
				var ch: int = await _ask_pick_hero("选择获得万能指示物的英雄", targets)
				tid = targets[ch]
			state["heroes"][tid]["tokens"]["wild"] += n
			_log("供应池 +%d 万能指示物（给 %s）" % [n, DB.hero_name(tid)], Color(0.9, 0.9, 0.5))
		"give_attack_x2":
			# 钢铁侠：拿 2 个攻击指示物，任意分配（可给同一英雄或分给不同英雄）
			# 神盾局单人：直接给玩家共享池
			if state["mode"] == "shield":
				state["shield_tokens"]["attack"] += 2
				_log("供应池 +2 攻击指示物（玩家）", Color(0.9, 0.9, 0.5))
				state["in_effect"] = false
				return
			var targets: Array = state["hero_ids"].duplicate()
			for i in range(2):
				var ch: int = await _ask_pick_hero("分配第 %d 个攻击指示物给哪个英雄？" % (i + 1), targets)
				var tid: String = targets[ch]
				state["heroes"][tid]["tokens"]["attack"] += 1
				_log("供应池 +1 攻击指示物（给 %s）" % DB.hero_name(tid), Color(0.9, 0.9, 0.5))
		"give_move_x2":
			# 钢铁侠：拿 2 个移动指示物，任意分配（可给同一英雄或分给不同英雄）
			# 神盾局单人：直接给玩家共享池
			if state["mode"] == "shield":
				state["shield_tokens"]["move"] += 2
				_log("供应池 +2 移动指示物（玩家）", Color(0.9, 0.9, 0.5))
				state["in_effect"] = false
				return
			var targets: Array = state["hero_ids"].duplicate()
			for i in range(2):
				var ch: int = await _ask_pick_hero("分配第 %d 个移动指示物给哪个英雄？" % (i + 1), targets)
				var tid: String = targets[ch]
				state["heroes"][tid]["tokens"]["move"] += 1
				_log("供应池 +1 移动指示物（给 %s）" % DB.hero_name(tid), Color(0.9, 0.9, 0.5))
		"draw_to_3":
			while state["heroes"][hid]["hand"].size() < 3:
				if not _draw_card(hid):
					break
			_log("%s 抽牌直到手牌 3 张" % DB.hero_name(hid), Color(0.8, 0.9, 1))
		"veteran_assassin":
			# 冬兵·资深刺客：冬兵获得两个攻击指示物
			if state["mode"] == "shield":
				state["shield_tokens"]["attack"] += 2
				_log("供应池 +2 攻击指示物（玩家）", Color(0.9, 0.9, 0.5))
			else:
				state["heroes"][hid]["tokens"]["attack"] += 2
				_log("%s 获得 2 个攻击指示物" % DB.hero_name(hid), Color(0.9, 0.9, 0.5))
		"prodigy":
			# 苏瑞·少年天才：给予任意一名英雄 1 个万能指示物，然后该英雄可抽牌直到手牌 3 张
			var targets: Array = state["hero_ids"].duplicate()
			var tid := hid
			if targets.size() > 1:
				var ch: int = await _ask_pick_hero("少年天才：选择获得万能指示物的英雄", targets)
				tid = targets[ch]
			if state["mode"] == "shield":
				state["shield_tokens"]["wild"] += 1
			else:
				state["heroes"][tid]["tokens"]["wild"] += 1
			_log("少年天才：%s 获得 1 个万能指示物" % DB.hero_name(tid), Color(0.9, 0.9, 0.5))
			# 该英雄可抽牌直到手牌 3 张
			while state["heroes"][tid]["hand"].size() < 3:
				if not _draw_card(tid):
					break
			_log("少年天才：%s 抽牌直到手牌 3 张" % DB.hero_name(tid), Color(0.8, 0.9, 1))
		"panther_instinct":
			# 黑豹·黑豹习性：本回合获得一些行动符号（effect 里内置要加的行动列表）
			var gained: Array = eff.get("gain", [])
			for s in gained:
				state["action_symbols"].append(s)
			_log("黑豹习性：本回合额外获得行动 %s" % "、".join(gained), Color(0.8, 1, 0.6))
		"photon_blast":
			var loc: int = state["heroes"][hid]["location"]
			var opts: Array = _adjacent_locs(loc)
			var p_rows: Array = []
			for o in opts:
				var oi0 := wrapi(int(o), 0, LOCATION_COUNT)
				var ld0: Dictionary = DB.location(state["locations"][oi0]["id"])
				var li0: String = ld0.get("image", "")
				p_rows.append({"icon": "attack", "arrow": "attack", "text": _loc_name(oi0), "bottom": li0})
			var choice = await _ask_action("光子冲击：选择攻击地点", p_rows)
			var oi := wrapi(int(opts[int(choice)]), 0, LOCATION_COUNT)
			for i in range(2):
				# 每次攻击可自选目标：暴徒 / 爪牙 / 反派（完成 2 个任务后可攻击反派）
				await _attack_once_at(hid, oi, "光子冲击第 %d 次" % (i + 1))
		"hulk_smash":
			var loc2: int = state["heroes"][hid]["location"]
			var l: Dictionary = state["locations"][loc2]
			# ① 本地点所有暴徒：各受 1 点伤害（直接击败 → 计入击败任务）
			if l["thug"] > 0:
				_defeat_thug(loc2, l["thug"])
			# ② 本地点爪牙：受 1 点伤害（泽莫男爵「邪恶大师」在场时爪牙免疫·裁定⑤）
			if l["threat"] != null and l["threat"]["hp"] > 0:
				if _henchman_immune() and not bool(l["threat"].get("immune_henchmen", false)):
					_log("绿巨人重击！但「邪恶大师」在场，爪牙 %s 不受伤害" % l["threat"]["name"], Color(0.8, 0.85, 1))
				else:
					l["threat"]["hp"] -= 1
					_log("绿巨人重击！爪牙 %s 受到 1 伤害（剩余 %d）" % [l["threat"]["name"], l["threat"]["hp"]], Color(1, 0.7, 0.4))
					if l["threat"]["hp"] <= 0:
						_clear_threat(loc2)
			# ③ 本地点其他英雄：各受 1 点伤害
			for other in state["hero_ids"]:
				if other != hid and state["heroes"][other]["location"] == loc2:
					await _deal_damage_to_hero(other, 1)
			# ④ 本地点反派：受 1 点伤害（需完成 2 个任务后才能伤害反派）
			if state["missions_completed"] >= 2 and state["villain_pos"] == loc2 and state["villain_hp"] > 0:
				var blocked: bool = state["villain"] == "taskmaster" and l["crisis"] > 0
				if not blocked:
					state["villain_hp"] -= 1
					_log("绿巨人重击！反派受到 1 伤害（生命 %d/%d）" % [state["villain_hp"], state["villain_hp_max"]], Color(1, 0.9, 0.3))
					if state["villain_hp"] <= 0:
						_win()
			# ⑤ 随后丢弃本地点全部平民
			if l["civ"] > 0:
				l["civ"] = 0
				_log("绿巨人重击！丢弃本地点全部平民", Color(0.9, 0.8, 0.6))
		"interrogate":
			if state["master_deck"].size() > 0:
				# 只展示"下一张真正的反派行动牌"：若堆顶上方有无限宝石(隐藏卡)，跳过它但不清除，
				# 避免玩家据牌背/异常推断出下一张是宝石。
				var view_idx: int = _next_villain_action_from_top()
				if view_idx >= 0:
					var ok: bool = await _ask_villain_card(view_idx, "审讯：查看主计划牌堆顶。是否放到牌组底部？")
					if ok:
						_state_move_card_to_bottom(view_idx)
						_log("审讯：将顶牌放到牌组底部", Color(0.7, 0.9, 1))
					else:
						_log("审讯：顶牌保持原位", Color(0.7, 0.9, 1))
				else:
					_log("审讯：主计划牌堆已没有可查看的行动牌", Color(0.7, 0.8, 0.9))
		"korg_fighter":
			# 科格·科格战斗机：在相邻两个地点各进行一次攻击；或者在你所在地点进行两次攻击
			# 用 _attack_once_at（效果攻击专用，每次攻击各自选目标、不调 _maybe_auto_end_turn）
			var k_loc: int = state["heroes"][hid]["location"]
			var adjl: Array = _adjacent_locs(k_loc)
			var mode_rows: Array = [
				{"icon": "attack", "text": "在相邻两地点各进行 1 次攻击"},
				{"icon": "attack", "text": "在所在地点进行 2 次攻击"},
			]
			var mode_choice: int = int(await _ask_action("科格战斗机：选择攻击方式", mode_rows))
			if int(mode_choice) == 0:
				for a_loc in adjl:
					await _attack_once_at(hid, a_loc, "科格战斗机（相邻）", 1)
			else:
				await _attack_once_at(hid, k_loc, "科格战斗机第 1 次", 1)
				await _attack_once_at(hid, k_loc, "科格战斗机第 2 次", 1)
		"war_song":
			# 女武神·战歌：移动到任意地点（被摧毁的地点不可选）
			var w_rows: Array = []
			var w_locs: Array = []
			for i in range(LOCATION_COUNT):
				if state["locations"][i].get("destroyed", false):
					continue
				var ld1: Dictionary = DB.location(state["locations"][i]["id"])
				var li1: String = ld1.get("image", "")
				w_rows.append({"icon": "move", "arrow": "move", "text": _loc_name(i), "bottom": li1})
				w_locs.append(i)
			var w_choice: int = await _ask_action("战歌：移动到任意地点", w_rows)
			var w_loc: int = int(w_locs[wrapi(int(w_choice), 0, w_locs.size())])
			await _set_hero_loc(hid, w_loc)   # 效果移动（A1）
			_log("%s 移动到 %s（战歌）" % [DB.hero_name(hid), _loc_name(w_loc)], Color(0.8, 0.9, 1))
		"stormbreaker":
			# 马面雷神·风暴战斧：进行两次攻击，然后抽取一张牌
			for r in range(2):
				await _execute_attack(hid, "")
			_draw_card(hid)
			_log("%s 风暴战斧：抽取 1 张牌" % DB.hero_name(hid), Color(0.8, 0.9, 1))
		"mjolnir":
			# 雷神·雷神之锤：对所在地点的一个敌人造成 3 次攻击（只选一次目标）
			var mj_loc: int = state["heroes"][hid]["location"]
			await _attack_once_at(hid, mj_loc, "雷神之锤", 3)
		"problem_solver":
			# 星爵·问题解决者：从供应池拿 1 个非万能行动指示物给任意英雄
			var ps_keys: Array = ["move", "attack", "heroic"]
			var ps_rows: Array = [
				{"icon": "move", "text": "移动"},
				{"icon": "attack", "text": "攻击"},
				{"icon": "heroic", "text": "英勇"},
			]
			var ps_t: int = int(await _ask_action("问题解决者：选择要给的指示物类型", ps_rows))
			var ps_key: String = ps_keys[wrapi(ps_t, 0, ps_keys.size())]
			var ps_tgt: int = await _ask_pick_hero("问题解决者：选择获得指示物的英雄", state["hero_ids"])
			var ps_hid: String = state["hero_ids"][ps_tgt]
			state["heroes"][ps_hid]["tokens"][ps_key] += 1
			_log("问题解决者：%s 获得 1 个%s指示物" % [DB.hero_name(ps_hid), DB.symbol_name(ps_key)], Color(0.9, 0.9, 0.5))
		"raccoon_senses":
			# 火箭·浣熊感官：获得 1 个万能指示物；或 指定任意数量你拥有的行动指示物转化为万能
			var rs_rows: Array = [
				{"icon": "wild", "text": "获得 1 个万能指示物"},
				{"text": "转化你的行动指示物为万能"},
			]
			var rs_t: int = int(await _ask_action("浣熊感官：选择其一", rs_rows))
			if int(rs_t) == 0:
				state["heroes"][hid]["tokens"]["wild"] += 1
				_log("浣熊感官：%s 获得 1 个万能指示物" % DB.hero_name(hid), Color(0.9, 0.9, 0.5))
			else:
				for k in ["move", "attack", "heroic"]:
					if state["heroes"][hid]["tokens"][k] > 0:
						state["heroes"][hid]["tokens"]["wild"] += state["heroes"][hid]["tokens"][k]
						state["heroes"][hid]["tokens"][k] = 0
				_log("浣熊感官：%s 的所有行动指示物转化为万能" % DB.hero_name(hid), Color(0.9, 0.9, 0.5))
		"genius_engineer":
			# 火箭·天才技师：获得 1 个万能指示物；或 本回合行动指示物用 1 当 2
			var ge_rows: Array = [
				{"icon": "wild", "text": "获得 1 个万能指示物"},
				{"text": "本回合行动指示物执行两次行动"},
			]
			var ge_t: int = int(await _ask_action("天才技师：选择其一", ge_rows))
			if int(ge_t) == 0:
				state["heroes"][hid]["tokens"]["wild"] += 1
				_log("天才技师：%s 获得 1 个万能指示物" % DB.hero_name(hid), Color(0.9, 0.9, 0.5))
			else:
				state["token_double"] = true
				_log("天才技师：本回合行动指示物可使用两次", Color(0.9, 0.9, 0.5))
		"gamora_fury":
			# 卡魔拉·斩击：本回合每用一次万能/攻击符号 → 额外 +1 攻击（效果获得的攻击不再触发）
			state["gamora_fury"] = true
			_log("卡魔拉·斩击：本回合每用万能/攻击符号，额外获得 1 个攻击行动", Color(0.9, 0.9, 0.5))
		"get_groot_q":
			# 格鲁特·我是格鲁特？：选择一名其他英雄，移到其相邻地点
			var gq_tgts: Array = []
			for hh in state["hero_ids"]:
				if hh != hid:
					gq_tgts.append(hh)
			if gq_tgts.size() > 0:
				var gq_rows: Array = []
				for hh in gq_tgts:
					gq_rows.append({"text": DB.hero_name(hh), "img": DB.hero_back(hh), "hide_text": true})
				var gq_t: int = await _ask_action("我是格鲁特？：选择一名其他英雄", gq_rows)
				var gq_hid: String = gq_tgts[wrapi(int(gq_t), 0, gq_tgts.size())]
				var gq_loc: int = state["heroes"][gq_hid]["location"]
				var gq_adj: Array = _adjacent_locs(gq_loc)
				# 第二个弹窗：选相邻地点（图形：移动图标+绿箭头+地点小图）
				var gq_rows2: Array = []
				for _gi in gq_adj:
					var _gld: Dictionary = DB.location(state["locations"][int(_gi)]["id"])
					var _gli: String = _gld.get("image", "")
					gq_rows2.append({"icon": "move", "arrow": "move", "text": _loc_name(int(_gi)), "bottom": _gli})
				var gq_c: int = await _ask_action("我是格鲁特？：%s 移到相邻地点" % DB.hero_name(gq_hid), gq_rows2)
				var gq_new: int = gq_adj[wrapi(int(gq_c), 0, gq_adj.size())]
				await _set_hero_loc(gq_hid, gq_new)   # A1：统一出口
				_log("格鲁特：%s 移动到 %s" % [DB.hero_name(gq_hid), _loc_name(gq_new)], Color(0.8, 0.9, 1))
		"get_groot":
			# 格鲁特·我是格鲁特！：选择一名其他英雄，你与该英雄在各自所在地点各攻击一次
			var gg_tgts: Array = []
			for hh in state["hero_ids"]:
				if hh != hid:
					gg_tgts.append(hh)
			if gg_tgts.size() > 0:
				var gg_rows: Array = []
				for hh in gg_tgts:
					gg_rows.append({"text": DB.hero_name(hh), "img": DB.hero_back(hh), "hide_text": true})
				var gg_t: int = await _ask_action("我是格鲁特！：选择一起攻击的英雄", gg_rows)
				var gg_hid: String = gg_tgts[wrapi(int(gg_t), 0, gg_tgts.size())]
				await _attack_once_at(hid, state["heroes"][hid]["location"], "格鲁特")
				await _attack_once_at(gg_hid, state["heroes"][gg_hid]["location"], "格鲁特同伴")
		"we_are_groot":
			# 格鲁特·我们是格鲁特：选择一名其他英雄，你与其各抽一张牌
			var wg_tgts: Array = []
			for hh in state["hero_ids"]:
				if hh != hid:
					wg_tgts.append(hh)
			if wg_tgts.size() > 0:
				var wg_rows: Array = []
				for hh in wg_tgts:
					wg_rows.append({"text": DB.hero_name(hh), "img": DB.hero_back(hh), "hide_text": true})
				var wg_t: int = await _ask_action("我们是格鲁特：选择一名其他英雄", wg_rows)
				var wg_hid: String = wg_tgts[wrapi(int(wg_t), 0, wg_tgts.size())]
				_draw_card(hid)
				_draw_card(wg_hid)
				_log("格鲁特：%s 与 %s 各抽 1 张牌" % [DB.hero_name(hid), DB.hero_name(wg_hid)], Color(0.8, 0.9, 1))
		# ---------------- 蜘蛛侠扩英雄效果 ----------------
		"web_shoot":
			# 蜘蛛侠·蛛网喷射：获得 2 个移动指示物
			state["heroes"][hid]["tokens"]["move"] += 2
			_log("%s 蛛网喷射：获得 2 个移动指示物" % DB.hero_name(hid), Color(0.8, 0.9, 1))
		"super_strength":
			# 蜘蛛侠·超凡力量：进行三次攻击，每击败一个暴徒获得 1 个英勇指示物
			var ss_loc: int = state["heroes"][hid]["location"]
			for si in range(3):
				var thug_before: int = state["locations"][ss_loc]["thug"]
				await _attack_once_at(hid, ss_loc, "超凡力量第 %d 次" % (si + 1))
				var killed: int = thug_before - state["locations"][ss_loc]["thug"]
				if killed > 0:
					state["heroes"][hid]["tokens"]["heroic"] += killed
					_log("超凡力量：击败 %d 个暴徒，获得 %d 个英勇指示物" % [killed, killed], Color(0.8, 1, 0.8))
		"great_responsibility":
			# 蜘蛛侠·重大责任：营救所在地点最多 3 个平民，每营救 1 个获得 1 个攻击指示物。
			# 分次结算：每次营救单独弹窗确认；检查平民是否还有，且玩家选"否"即停止。
			var gr_loc: int = state["heroes"][hid]["location"]
			var gr_saved := 0
			for gi in range(3):
				if state["locations"][gr_loc]["civ"] <= 0:
					break
				var ok := await _ask_confirm("重大责任：营救 1 个平民？（剩余 %d，已救 %d）" % [state["locations"][gr_loc]["civ"], gr_saved])
				if ok:
					_rescue_civ(hid, gr_loc)
					state["heroes"][hid]["tokens"]["attack"] += 1
					gr_saved += 1
				else:
					break
			_log("重大责任：营救 %d 个平民，获得 %d 个攻击指示物" % [gr_saved, gr_saved], Color(0.8, 1, 0.8))
		"venom_strike":
			# 迈尔斯·毒液突袭：对你所在地点的一个敌人造成两次攻击
			var vs_loc: int = state["heroes"][hid]["location"]
			await _attack_once_at(hid, vs_loc, "毒液突袭", 2)
		"invisibility", "web_dancer":
			# 迈尔斯·隐形 / 格温蛛·蛛网舞者：直到下回合开始无法受到伤害
			state["heroes"][hid]["invulnerable"] = true
			_log("%s：直到你下个回合开始不会受到伤害" % DB.hero_name(hid), Color(0.7, 0.9, 1))
		"miles_web":
			# 迈尔斯·蛛网：被动效果（打出即标记，英雄在反派所在地点结束回合时触发）
			state["heroes"][hid]["miles_web_armed"] = true
			_log("迈尔斯蛛网：已标记，若在反派所在地点结束回合则推迟反派下一个回合", Color(0.7, 0.9, 1))
		"web_weaver":
			# 格温蛛·蛛网交织者：选择两张威胁卡，交换它们的位置
			var threat_locs: Array = []
			for ti in range(LOCATION_COUNT):
				if state["locations"][ti]["threat"] != null:
					threat_locs.append(ti)
			if threat_locs.size() < 2:
				_log("蛛网交织者：场上威胁卡不足 2 张，无效", Color(0.8, 0.8, 0.8))
			else:
				var ww_vid: String = state["villain"]
				var ww_back: String = "res://assets/cards/villains/%s/threat_back.png" % ww_vid
				var ww_img := func(tl: int) -> String:
					var ht: Variant = state["locations"][tl]["threat"]
					# 背面朝上的威胁卡（神秘客）：只显示卡背，不泄露正面
					if ht != null and ht.get("_face_down", false):
						return ww_back
					if ht is Dictionary and ht.has("_tidx"):
						var ip := "res://assets/cards/villains/%s/threat_%02d.png" % [ww_vid, int(ht["_tidx"]) + 1]
						if ResourceLoader.exists(ip):
							return ip
					return ww_back
				var ww_text := func(tl: int) -> String:
					var ht: Variant = state["locations"][tl]["threat"]
					if ht != null and ht.get("_face_down", false):
						return "%s（背面朝上）" % _loc_name(tl)   # 未翻开不显示卡名
					return "%s（%s）" % [_loc_name(tl), ht["name"]]
				var rows_l: Array = []
				for tl in threat_locs:
					rows_l.append({"img": ww_img.call(tl), "card": "threat", "text": ww_text.call(tl)})
				var p1: int = int(await _ask_action("蛛网交织者：选择第 1 张威胁卡", rows_l))
				var loc1: int = threat_locs[wrapi(p1, 0, threat_locs.size())]
				var rows_l2: Array = []
				for tl in threat_locs:
					if tl != loc1:
						rows_l2.append({"img": ww_img.call(tl), "card": "threat", "text": ww_text.call(tl)})
				var p2: int = int(await _ask_action("蛛网交织者：选择第 2 张威胁卡", rows_l2))
				var avail2: Array = threat_locs.filter(func(x): return x != loc1)
				var loc2: int = avail2[wrapi(p2, 0, avail2.size())]
				var t1: Variant = state["locations"][loc1]["threat"]
				var t2: Variant = state["locations"][loc2]["threat"]
				state["locations"][loc1]["threat"] = t2
				state["locations"][loc2]["threat"] = t1
				_log("蛛网交织者：交换了 %s 与 %s 的威胁卡" % [_loc_name(loc1), _loc_name(loc2)], Color(0.7, 0.9, 1))
		"acrobatic_fight":
			# 格温蛛·杂技格斗：击败所在地点所有的暴徒
			var af_loc: int = state["heroes"][hid]["location"]
			var af_count: int = state["locations"][af_loc]["thug"]
			if af_count > 0:
				_defeat_thug(af_loc, af_count, hid)
				_log("杂技格斗：击败 %s 的所有 %d 个暴徒" % [_loc_name(af_loc), af_count], Color(0.8, 1, 0.8))
		"cartoon_web":
			# 蜘猪侠·卡通蛛网：被动效果（打出即标记，英雄在反派所在地点结束回合时触发）
			state["heroes"][hid]["cartoon_web_armed"] = true
			_log("卡通蛛网：已标记，若在反派所在地点结束回合则取消失下一次反派移动", Color(0.7, 0.9, 1))
		"cartoon_essence":
			# 蜘猪侠·卡通精髓：直到下回合开始，你的最后一张牌不能被弃置
			state["heroes"][hid]["protect_last_card"] = true
			_log("卡通精髓：直到你下回合开始，最后一张牌不能被弃置", Color(0.7, 0.9, 1))
		"cartoon_weapon":
			# 蜘猪侠·卡通武器：在任意地点进行一次攻击（被摧毁的地点不可选）
			var cw_rows: Array = []
			var cw_locs: Array = []
			for ci in range(LOCATION_COUNT):
				if state["locations"][ci].get("destroyed", false):
					continue
				var ld2: Dictionary = DB.location(state["locations"][ci]["id"])
				var li2: String = ld2.get("image", "")
				cw_rows.append({"icon": "attack", "arrow": "attack", "text": _loc_name(ci), "bottom": li2})
				cw_locs.append(ci)
			var cw_p: int = await _ask_action("卡通武器：选择攻击地点", cw_rows)
			var cw_loc: int = int(cw_locs[wrapi(int(cw_p), 0, cw_locs.size())])
			await _attack_once_at(hid, cw_loc, "卡通武器")
		# ---------------- 第一季众筹英雄效果 ----------------
		"wasp_energy_blast", "falcon_airstrike", "venom_track":
			# 黄蜂女·能量投射 / 猎鹰·空袭 / 毒液·追踪：移动到任意地点，然后进行一次攻击
			var mb_name: String = String(eff.get("name", "效果"))
			var mb_loc: int = await _effect_move_to(hid, _live_locs(), "%s：选择要移动到的地点" % mb_name)
			if mb_loc >= 0 and state["phase"] != "game_over":
				await _attack_once_at(hid, mb_loc, mb_name)
		"wasp_wings":
			# 黄蜂女·翅膀：将你自己和任意数量英雄从你所在地点移动到其他任意地点
			var wg_from: int = int(state["heroes"][hid]["location"])
			var wg_to: int = await _effect_move_to(hid, _live_locs(), "翅膀：选择你要移动到的地点")
			if wg_to >= 0:
				for oh in state["hero_ids"]:
					if oh == hid or state["heroes"][oh]["ko"]:
						continue
					if int(state["heroes"][oh]["location"]) != wg_from:
						continue
					if await _ask_confirm("翅膀：带 %s 一起移动到 %s 吗？" % [DB.hero_name(String(oh)), _loc_name(wg_to)]):
						await _set_hero_loc(oh, wg_to)   # A1：统一出口
						_log("翅膀：%s 随同移动到 %s" % [DB.hero_name(String(oh)), _loc_name(wg_to)], Color(0.8, 0.9, 1))
				Events.emit_state_changed()
		"wasp_shrink", "antman_shrink", "sm2099_enhanced_senses", "spiderwoman_super_resist", "vision_phase":
			# 缩小 / 强化感官 / 超级抗性 / 透明化：直到你下回合开始不会受到任何伤害
			state["heroes"][hid]["invulnerable"] = true
			_log("%s：直到你下个回合开始不会受到任何伤害" % String(eff.get("name", "效果")), Color(0.7, 0.9, 1))
		"okoye_strategist":
			# 奥克耶·资深战略家：展示牌库顶一张牌，可以将其置于牌堆底
			var ok_deck: Array = state["heroes"][hid]["deck"]
			if ok_deck.size() == 0:
				_log("资深战略家：牌库为空，无效", Color(0.8, 0.8, 0.8))
			else:
				var ok_top: int = int(ok_deck[0])
				await _ask_action("资深战略家：这是你牌库顶的牌", [
					{"img": UiKit.hero_card_image(hid, ok_top), "text": "牌库顶：" + _card_desc(hid, ok_top)}])
				if await _ask_confirm("资深战略家：把这张牌置于牌堆底部？"):
					ok_deck.remove_at(0)
					ok_deck.append(ok_top)
					_log("资深战略家：将牌库顶的「%s」置于牌堆底" % _card_desc(hid, ok_top), Color(0.8, 0.9, 1))
				else:
					_log("资深战略家：牌库顶的「%s」保持原位" % _card_desc(hid, ok_top), Color(0.8, 0.9, 1))
		"okoye_dora_milaje":
			# 奥克耶·多拉·米拉杰：直到下回合开始，同地点另一名英雄受伤时可代其承受（询问在 _deal_damage_to_hero 中）
			state["heroes"][hid]["dora_milaje"] = true
			_log("多拉·米拉杰：直到你下个回合开始，%s 可以替同地点的英雄承受伤害" % DB.hero_name(hid), Color(0.8, 0.9, 1))
		"okoye_vibranium_spear", "warmachine_repulsor", "warmachine_rocket", "hawkeye_long_shot":
			# 振金长矛/光束武器/火箭发射器：在相邻地点攻击 1~2 次；远射：在对面地点攻击 2 次
			var at_times: int = 1 if eff["type"] == "warmachine_repulsor" else 2
			var at_name: String = String(eff.get("name", "效果"))
			var at_loc: int = -1
			if eff["type"] == "hawkeye_long_shot":
				at_loc = _opposite_loc(int(state["heroes"][hid]["location"]))
				if at_loc == int(state["heroes"][hid]["location"]):
					_log("远射：没有可攻击的对面地点", Color(0.8, 0.8, 0.8))
					at_loc = -1
			else:
				var at_rows: Array = []
				var at_locs: Array = []
				for o in _adjacent_locs(int(state["heroes"][hid]["location"])):
					var ai := int(o)
					if state["locations"][ai].get("destroyed", false):
						continue
					var ald: Dictionary = DB.location(state["locations"][ai]["id"])
					at_rows.append({"icon": "attack", "arrow": "attack", "text": _loc_name(ai), "bottom": String(ald.get("image", ""))})
					at_locs.append(ai)
				if at_locs.size() == 0:
					_log("%s：没有可攻击的相邻地点" % at_name, Color(0.8, 0.8, 0.8))
				else:
					var at_p: int = int(await _ask_action("%s：选择相邻地点进行攻击" % at_name, at_rows))
					at_loc = int(at_locs[wrapi(at_p, 0, at_locs.size())])
			if at_loc >= 0 and state["phase"] != "game_over":
				await _attack_once_at(hid, at_loc, at_name, at_times)
		"antman_grow":
			# 蚁人·变大：先进行一次移动（相邻地点），然后对单个目标进行 3 次攻击
			await _effect_move_to(hid, _adjacent_locs(int(state["heroes"][hid]["location"])), "变大：先选择移动目的地")
			if state["phase"] != "game_over":
				await _attack_once_at(hid, int(state["heroes"][hid]["location"]), "变大", 3)
		"antman_quantum_leap":
			await _antman_quantum_leap(hid)
		"sm2099_claws":
			# 蜘蛛侠2099·利爪：对你所在地点的单个目标进行两次攻击；本回合你造成的伤害无法被降低
			state["heroes"][hid]["ignore_reduction"] = true
			_log("利爪：本回合 %s 造成的伤害无法被降低" % DB.hero_name(hid), Color(0.9, 0.8, 0.6))
			await _attack_once_at(hid, int(state["heroes"][hid]["location"]), "利爪", 2)
		"sm2099_riley_assist":
			# 蜘蛛侠2099·莱利援助：在任意地点进行一次英勇行动（暂时移到该地点后执行，再移回）
			var ra_rows: Array = []
			var ra_locs: Array = []
			for i in range(LOCATION_COUNT):
				if state["locations"][i].get("destroyed", false):
					continue
				var rld: Dictionary = DB.location(state["locations"][i]["id"])
				ra_rows.append({"icon": "heroic", "arrow": "heroic", "text": _loc_name(i), "bottom": String(rld.get("image", ""))})
				ra_locs.append(i)
			if ra_locs.size() == 0:
				_log("莱利援助：没有可执行英勇行动的地点", Color(0.8, 0.8, 0.8))
			else:
				var ra_p: int = int(await _ask_action("莱利援助：选择执行英勇行动的地点", ra_rows))
				var ra_loc: int = int(ra_locs[wrapi(ra_p, 0, ra_locs.size())])
				var ra_old: int = int(state["heroes"][hid]["location"])
				await _set_hero_loc(hid, ra_loc)   # 莱利援助（A1）
				_log("莱利援助：在 %s 进行一次英勇行动" % _loc_name(ra_loc), Color(0.8, 0.9, 1))
				await _execute_heroic(hid, "none")
				if not state["heroes"][hid]["ko"]:
					await _set_hero_loc(hid, ra_old)   # A1：统一出口
				Events.emit_state_changed()
		"blackcat_cat_reflex":
			# 猫女·猫之本能：获得任意 2 个移动/攻击/英勇指示物（可任意组合）
			var cr_keys: Array = ["move", "attack", "heroic"]
			for ci2 in range(2):
				var cr_rows: Array = []
				for k2 in cr_keys:
					cr_rows.append({"icon": String(k2), "text": DB.symbol_name(String(k2)), "hide_text": true})
				var cr_p: int = int(await _ask_action("猫之本能：选择第 %d 个指示物" % (ci2 + 1), cr_rows))
				var cr_k: String = String(cr_keys[wrapi(cr_p, 0, cr_keys.size())])
				_hero_token_pool(hid)[cr_k] = int(_hero_token_pool(hid)[cr_k]) + 1
				_log("猫之本能：%s 获得 1 个%s指示物" % [DB.hero_name(hid), DB.symbol_name(cr_k)], Color(0.9, 0.9, 0.5))
		"blackcat_cat_scratch", "blackcat_cat_luck":
			# 猫女·猫抓 / 猫之幸运：记"待触发"标记，下一次反派翻行动卡（动画播完后）再询问
			state["heroes"][hid]["cat_redraw_armed"] = true
			_log("%s：已标记，下一张主计划卡牌被翻开时可将其放到牌堆底部并重翻一张" % String(eff.get("name", "效果")), Color(0.8, 0.8, 1))
		"venom_symbiote_boost":
			# 毒液·共生体强化：获得一个移动和一个攻击行动
			state["action_symbols"].append("move")
			state["action_symbols"].append("attack")
			_log("共生体强化：本回合额外获得 1 个移动行动和 1 个攻击行动", Color(0.8, 1, 0.6))
		"venom_regen":
			# 毒液·再生：抽牌直到手牌 3 张
			while state["heroes"][hid]["hand"].size() < 3:
				if not _draw_card(hid):
					break
			_log("再生：%s 抽牌直到手牌 3 张" % DB.hero_name(hid), Color(0.8, 0.9, 1))
		"spiderwoman_venom_blast":
			# 蜘蛛女·毒液冲击：二选一（两次攻击 / 下个反派回合少翻 1 张牌）
			var vb_rows: Array = [
				{"icon": "attack", "arrow": "attack", "text": "对你所在地点的单个目标进行两次攻击"},
				{"text": "将下一个反派回合推迟 1 张牌"},
			]
			var vb_p: int = int(await _ask_action("毒液冲击：选择其一", vb_rows))
			if vb_p == 0:
				await _attack_once_at(hid, int(state["heroes"][hid]["location"]), "毒液冲击", 2)
			else:
				state["skip_villain_card"] = int(state.get("skip_villain_card", 0)) + 1
				_log("毒液冲击：下一个反派回合少打出 1 张行动卡", Color(0.7, 0.9, 1))
		"vision_mind_gem":
			# 幻视·心灵宝石冲击：故事情节最后 4 张英雄牌的攻击符号数（不含此牌），对所在地点的一个目标造成等量伤害
			var mg_dmg: int = _count_recent_story_symbols("attack", 4)
			_log("心灵宝石冲击：故事情节最后 4 张英雄牌共有 %d 个攻击符号" % mg_dmg, Color(0.9, 0.8, 0.6))
			if mg_dmg > 0:
				await _attack_once_at(hid, int(state["heroes"][hid]["location"]), "心灵宝石冲击", mg_dmg)
			else:
				Events.emit_toast("心灵宝石冲击：没有攻击符号，造成 0 点伤害")
		"vision_evolved_intellect":
			# 幻视·进化智力：没有空余平民/暴徒槽位的地点数量 → 获得等量万能指示物
			var ei_n := 0
			for i in range(LOCATION_COUNT):
				var li: Dictionary = state["locations"][i]
				if li.get("destroyed", false):
					continue
				var slots_total: int = int(DB.location(String(li["id"]))["slots"])
				if int(li["civ"]) + int(li["thug"]) >= slots_total:
					ei_n += 1
			if ei_n > 0:
				_hero_token_pool(hid)["wild"] = int(_hero_token_pool(hid)["wild"]) + ei_n
				_log("进化智力：%d 个地点没有空余槽位，%s 获得 %d 个万能指示物" % [ei_n, DB.hero_name(hid), ei_n], Color(0.9, 0.9, 0.5))
			else:
				_log("进化智力：没有槽位全满的地点，未获得万能指示物", Color(0.8, 0.8, 0.8))
		"hawkeye_martial_artist":
			# 鹰眼·武术家：直到下回合开始，受到的伤害都可转移给同地点敌人（询问在 _deal_damage_to_hero 中）
			state["heroes"][hid]["martial_artist"] = true
			_log("武术家：直到你下个回合开始，受到的伤害都可以转移到你所在地点的敌人身上", Color(0.8, 0.9, 1))
		"hawkeye_master_marksman":
			# 鹰眼·神射手大师：本回合可用的每个符号都视为两次攻击（含继承符号与本卡自身符号）
			var mm_n: int = state["action_symbols"].size()
			if mm_n == 0:
				_log("神射手大师：本回合没有可用符号，无效", Color(0.8, 0.8, 0.8))
			else:
				state["action_symbols"].clear()
				for _mi2 in range(mm_n * 2):
					state["action_symbols"].append("attack")
				_log("神射手大师：%d 个可用符号视为 %d 次攻击" % [mm_n, mm_n * 2], Color(0.9, 0.8, 0.6))
		"warmachine_strafe":
			# 战争机器·扫射攻击：先进行两次攻击，然后进行一次移动
			await _attack_once_at(hid, int(state["heroes"][hid]["location"]), "扫射攻击第 1 次")
			if state["phase"] != "game_over":
				await _attack_once_at(hid, int(state["heroes"][hid]["location"]), "扫射攻击第 2 次")
			if state["phase"] != "game_over":
				await _effect_move_to(hid, _adjacent_locs(int(state["heroes"][hid]["location"])), "扫射攻击：选择移动目的地")
		"nickfury_director_move", "nickfury_director_attack", "nickfury_director_heroic":
			# 尼克福瑞·神盾局局长：选择一名英雄立刻执行两次 移动/攻击/英勇 行动
			var nf_kind := "move"
			if eff["type"] == "nickfury_director_attack":
				nf_kind = "attack"
			elif eff["type"] == "nickfury_director_heroic":
				nf_kind = "heroic"
			var nf_t: int = await _ask_pick_hero("神盾局局长：选择执行两次%s行动的英雄" % DB.symbol_name(nf_kind), state["hero_ids"])
			var nf_hid: String = String(state["hero_ids"][nf_t])
			_log("神盾局局长：%s 立刻执行两次%s行动" % [DB.hero_name(nf_hid), DB.symbol_name(nf_kind)], Color(0.8, 0.9, 1))
			for _ni in range(2):
				if state["phase"] == "game_over" or state["heroes"][nf_hid]["ko"]:
					break
				match nf_kind:
					"move":
						await _execute_move(nf_hid, "none")
					"attack":
						await _execute_attack(nf_hid, "none")
					_:
						await _execute_heroic(nf_hid, "none")
		# ==================== 第一季众筹第二批（2.x）====================
		"mantis_astral_projection":
			# 螳螂女·星体投射（裁定①）：本回合你每次使用行动时，可各自任选一个地点「如同你在那里」；
			# 你本人的实际位置不变（位置判定/伤害/溢出仍按真实位置）。
			state["heroes"][hid]["astral_turn"] = true
			_log("星体投射：本回合 %s 的每次行动都可任选一个地点使用（本人位置不变）" % DB.hero_name(hid), Color(0.8, 0.9, 1))
		"mantis_empathic_control":
			# 螳螂女·移情操控（裁定⑩）：只取消 BAM，那张牌的移动照常；保留到下一张反派行动卡翻出为止。
			state["cancel_bam_pending"] = true
			_log("移情操控：下一张翻出的反派行动卡不触发 BAM（移动照常）", Color(0.8, 0.9, 1))
		"drstrange_orb_of_agamotto":
			# 奇异博士·阿戈摩托之球（裁定③）：把反派牌堆顶那张公开给所有人（牌不动、不结算；顶牌是宝石也能看到）。
			# 持续到这张卡离开故事情节"可见区"为止 —— 可见区口径见 _villain_top_public_now()。
			_log("阿戈摩托之球：反派牌堆顶从现在起对所有人公开（直到这张卡离开故事情节显示区）", Color(0.8, 0.8, 1))
		"mantis_mind_heal":
			# 螳螂女·心灵治疗：选择一名其他英雄，该英雄抽 2 张牌
			var mh_pool: Array = state["hero_ids"].duplicate()
			mh_pool.erase(hid)
			if mh_pool.size() == 0:
				mh_pool = [hid]
			var mh_i: int = await _ask_pick_hero("心灵治疗：选择抽 2 张牌的英雄", mh_pool)
			var mh_hid: String = String(mh_pool[wrapi(mh_i, 0, mh_pool.size())])
			for _i in range(2):
				_draw_card(mh_hid)
			_log("心灵治疗：%s 抽取 2 张牌" % DB.hero_name(mh_hid), Color(0.8, 0.9, 1))
		"shangchi_martial_master":
			# 尚气·武术大师：继承上一张英雄卡的攻击行动数量翻倍
			var sm_n := 0
			for s in state.get("prev_hero_symbols", []):
				if String(s) == "attack":
					sm_n += 1
			if sm_n <= 0:
				_log("武术大师：上一张英雄卡没有攻击行动，无可翻倍", Color(0.9, 0.8, 0.6))
			else:
				for _i in range(sm_n):
					state["action_symbols"].append("attack")
				_log("武术大师：上一张有过 %d 个攻击行动 → 额外获得 %d 个攻击行动" % [sm_n, sm_n], Color(0.9, 0.6, 0.4))
		"drax_vengeance":
			# 德拉克斯·复仇：把"你所在地点的所有敌人"带到顺时针下一个地点，然后在该地点攻击 1 次。
			# 三条裁定：
			#   ① 暴徒：先看目标地点的**空位数**，能搬几个搬几个（敌人少于空位数则全搬）；
			#   ② 爪牙/威胁卡：只有目标地点**没有威胁卡**时才跟着走，否则留在原地；
			#   ③ 反派本体：直接搬过去（不受空位数、也不受目标地点有无威胁卡的限制）。
			var dv_from: int = int(state["heroes"][hid]["location"])
			var dv_to: int = _next_live_loc(dv_from)   # 存活环上的顺时针下一地点（被摧毁的地点不落）
			if dv_to < 0 or dv_to == dv_from:
				_log("复仇：顺时针下一个地点不可用，%s 原地攻击 1 次" % DB.hero_name(hid), Color(0.9, 0.6, 0.4))
				await _attack_once_at(hid, dv_from, "复仇", 1)
			else:
				var dv_src: Dictionary = state["locations"][dv_from]
				var dv_dst: Dictionary = state["locations"][dv_to]
				# ① 暴徒：口径与 _place_mixed_tokens() 的槽位占用一致（基尔格蒙的危机指示物占槽位）
				var dv_slots: int = int(DB.location(String(dv_dst["id"]))["slots"])
				var dv_occ: int = int(dv_dst["civ"]) + int(dv_dst["thug"]) + (int(dv_dst["crisis"]) if state["villain"] == "kilmonger" else 0)
				var dv_free: int = maxi(dv_slots - dv_occ, 0)
				var dv_have: int = int(dv_src["thug"])
				var dv_move: int = mini(dv_have, dv_free)
				if dv_move > 0:
					dv_src["thug"] = dv_have - dv_move
					await _place_token_at("thug", dv_to, dv_move)
				if dv_have > dv_move:
					_log("复仇：%s 只剩 %d 个空位，只带走 %d 个暴徒（%d 个留在原地）"
						% [_loc_name(dv_to), dv_free, dv_move, dv_have - dv_move], Color(0.9, 0.7, 0.5))
				# ② 威胁卡（爪牙）：目标地点已有威胁卡则留下不动
				var dv_threat: Variant = dv_src["threat"]
				var dv_threat_moved := false
				if dv_threat != null:
					if dv_dst["threat"] == null:
						dv_dst["threat"] = dv_threat
						dv_src["threat"] = null
						dv_threat_moved = true
						_log("复仇：威胁卡「%s」被一起带到 %s" % [String((dv_threat as Dictionary).get("name", "")), _loc_name(dv_to)], Color(0.9, 0.7, 0.5))
					else:
						_log("复仇：%s 已有威胁卡，本地点威胁卡留在原地" % _loc_name(dv_to), Color(0.9, 0.7, 0.5))
				# ③ 反派本体：直接搬（邪恶六人组模式下按各自位置逐个搬）
				var dv_vills: Array = []
				if String(state.get("mode", "")) == "s6":
					for vid in _s6_at(dv_from):
						_s6()["vills"][vid]["pos"] = dv_to
						dv_vills.append(DB.villain_name(String(vid)))
				elif int(state["villain_pos"]) == dv_from:
					state["villain_pos"] = dv_to
					dv_vills.append(DB.villain_name(String(state["villain"])))
				await _set_hero_loc(hid, dv_to)   # 德拉克斯复仇（A1：落点变更统一出口）
				_log("复仇：%s 携带 %d 个暴徒%s%s移动到 %s" % [
					DB.hero_name(hid), dv_move,
					"" if not dv_threat_moved else "、威胁卡",
					"" if dv_vills.is_empty() else "、反派 " + "、".join(dv_vills),
					_loc_name(dv_to)], Color(0.9, 0.6, 0.4))
				await _attack_once_at(hid, dv_to, "复仇", 1)
		"drstrange_portal":
			# 奇异博士·维度传送门：移动到任意地点
			var dp_cands: Array = []
			for _i in range(LOCATION_COUNT):
				dp_cands.append(_i)
			await _effect_move_to(hid, dp_cands, "维度传送门：选择目的地")
		"drstrange_cloak":
			# 奇异博士·悬浮斗篷：在相邻地点进行一次攻击，或者进行一次移动行动
			var dc_rows: Array = [
				{"icon": "attack", "text": "在相邻地点进行一次攻击"},
				{"icon": "move", "text": "进行一次移动行动"},
			]
			var dc_p: int = int(await _ask_action("悬浮斗篷：选择其一", dc_rows))
			if dc_p == 0:
				var dc_from: int = int(state["heroes"][hid]["location"])
				var dc_loc: int = await _pick_attack_loc(hid, _adjacent_locs(dc_from), "悬浮斗篷：选择相邻攻击地点")
				if dc_loc < 0:
					Events.emit_toast("相邻地点没有可攻击的目标")
				else:
					await _attack_once_at(hid, dc_loc, "悬浮斗篷", 1)
			else:
				await _execute_move(hid, "none")
		"drstrange_eye_of_agamotto":
			# 奇异博士·阿戈摩托之眼：选择故事情节中一张正面朝上的反派行动卡，洗入反派牌堆
			var ey_rows: Array = []
			var ey_si: Array = []
			for si in range(state["story"].size()):
				var se: Dictionary = state["story"][si]
				if String(se.get("type", "")) == "villain" and not bool(se.get("face_down", false)):
					ey_rows.append({"img": DB.villain(String(state["villain"]))["back"], "text": "故事情节第 %d 张" % (si + 1), "hide_text": true})
					ey_si.append(si)
			if ey_rows.is_empty():
				Events.emit_toast("故事情节里没有正面朝上的反派行动卡")
			else:
				var ey_p: int = int(await _ask_action("阿戈摩托之眼：选择要洗回牌堆的反派行动卡", ey_rows))
				var ey_k: int = int(ey_si[wrapi(ey_p, 0, ey_si.size())])
				var ey_card: int = int(state["story"][ey_k].get("idx", -1))
				state["story"].remove_at(ey_k)
				if ey_card >= 0:
					state["master_deck"].append(ey_card)
					state["master_deck"].shuffle()
				_log("阿戈摩托之眼：一张反派行动卡被洗回牌堆（当前牌堆 %d 张）" % state["master_deck"].size(), Color(0.8, 0.7, 1))
		"drstrange_book_of_vishanti":
			# 奇异博士·维山蒂之书：查看反派牌堆 → 选一张永久移出游戏 → 混洗牌堆
			var bv_rows: Array = []
			var bv_cards: Array = []
			for item in state["master_deck"]:
				if item is int:
					bv_rows.append({"img": DB.villain(String(state["villain"]))["back"], "text": villain_action_desc(int(item))})
					bv_cards.append(int(item))
			if bv_rows.is_empty():
				Events.emit_toast("反派牌堆里没有可移除的行动卡")
			else:
				var bv_p: int = int(await _ask_action("维山蒂之书：选择一张永久移出游戏的反派行动卡", bv_rows))
				var bv_card: int = int(bv_cards[wrapi(bv_p, 0, bv_cards.size())])
				state["master_deck"].erase(bv_card)
				if not state.has("master_removed"):
					state["master_removed"] = []
				state["master_removed"].append(bv_card)
				state["master_deck"].shuffle()
				_log("维山蒂之书：一张反派行动卡移出游戏，牌堆已混洗（剩 %d 张）" % state["master_deck"].size(), Color(0.8, 0.7, 1))
		"ironfist_chi_boost":
			# 铁拳·气之强化：两次攻击，可在你所在地点或两个相邻地点任意分配
			var ic_from: int = int(state["heroes"][hid]["location"])
			var ic_cands: Array = [ic_from]
			for a in _adjacent_locs(ic_from):
				ic_cands.append(int(a))
			for _i in range(2):
				if state["phase"] == "game_over":
					break
				var ic_loc: int = await _pick_attack_loc(hid, ic_cands, "气之强化：选择第 %d 次攻击的地点" % (_i + 1))
				if ic_loc < 0:
					Events.emit_toast("这些地点已经没有可攻击的目标")
					break
				await _attack_once_at(hid, ic_loc, "气之强化", 1)
		"punisher_precise_shot":
			# 惩罚者·精准射击：对所在地点的一个敌人打 4 次；本回合你造成的伤害不可被取消/忽略
			state["dmg_uncancellable_turn"] = true
			_log("精准射击：本回合你造成的伤害无法被取消或忽略", Color(0.9, 0.6, 0.4))
			await _attack_once_at(hid, int(state["heroes"][hid]["location"]), "精准射击", 4)
		"punisher_heavy_firepower":
			# 惩罚者·强大火力：在任意地点攻击两次，并在该地点的两个相邻地点各攻击一次
			var hf_cands: Array = []
			for _i in range(LOCATION_COUNT):
				hf_cands.append(_i)
			var hf_loc: int = await _pick_attack_loc(hid, hf_cands, "强大火力：选择主攻击地点")
			if hf_loc < 0:
				Events.emit_toast("场上没有可攻击的目标")
			else:
				for _i in range(2):
					await _attack_once_at(hid, hf_loc, "强大火力", 1)
				for a in _adjacent_locs(hf_loc):
					if _enemy_targets_at(int(a)).size() > 0:
						await _attack_once_at(hid, int(a), "强大火力（相邻）", 1)
		"punisher_special_ops":
			# 惩罚者·特种作战训练：移动到任意地点，然后进行两次攻击
			var so_cands: Array = []
			for _i in range(LOCATION_COUNT):
				so_cands.append(_i)
			await _effect_move_to(hid, so_cands, "特种作战训练：选择目的地")
			for _i in range(2):
				if state["phase"] == "game_over":
					break
				await _execute_attack(hid, "none")
		"scarletwitch_psychic_energy":
			# 绯红女巫·心灵能量：对相邻地点的单个敌人进行三次攻击
			var sw_from: int = int(state["heroes"][hid]["location"])
			var sw_loc: int = await _pick_attack_loc(hid, _adjacent_locs(sw_from), "心灵能量：选择相邻地点的目标")
			if sw_loc < 0:
				Events.emit_toast("相邻地点没有可攻击的目标")
			else:
				await _attack_once_at(hid, sw_loc, "心灵能量", 3)
		"scarletwitch_psychic_field":
			# 绯红女巫·心灵能量场：所有英雄在下个反派回合免疫首次伤害
			for hh in state["hero_ids"]:
				state["heroes"][hh]["ignore_first_hit"] = true
			_log("心灵能量场：所有英雄在下个反派回合免疫首次伤害", Color(0.8, 0.8, 1))
		"scarletwitch_chaos_magic":
			# 绯红女巫·混沌魔法：选另一名英雄，该英雄可把手牌一张与故事情节中自己正面朝上的牌交换
			var cm_pool: Array = state["hero_ids"].duplicate()
			cm_pool.erase(hid)
			if cm_pool.size() == 0:
				Events.emit_toast("混沌魔法：没有其他英雄可选")
			else:
				var cm_i: int = await _ask_pick_hero("混沌魔法：选择要交换手牌的英雄", cm_pool)
				var cm_hid: String = String(cm_pool[wrapi(cm_i, 0, cm_pool.size())])
				var cm_hc: Array = await _ask_hand_cards(cm_hid, 1, "混沌魔法：%s 选择要换出的手牌" % DB.hero_name(cm_hid))
				if cm_hc.size() > 0:
					var cm_story: int = await _ask_story_card("混沌魔法：选择要换入的故事情节卡牌", cm_hid)
					if cm_story >= 0:
						var cm_h: Dictionary = state["heroes"][cm_hid]
						var cm_hi: int = int(cm_hc[0])
						if cm_hi >= 0 and cm_hi < cm_h["hand"].size():
							var cm_out: int = int(cm_h["hand"][cm_hi])
							var cm_in: int = int(state["story"][cm_story]["idx"])
							cm_h["hand"][cm_hi] = cm_in
							state["story"][cm_story]["idx"] = cm_out
							_log("混沌魔法：%s 用手牌与故事情节中的卡牌交换" % DB.hero_name(cm_hid), Color(0.9, 0.7, 1))
		"lukecage_super_strength":
			# 卢克凯奇·超人力量：本回合获得等同于手牌数量的攻击行动
			var lc_n: int = int(state["heroes"][hid]["hand"].size())
			for _i in range(lc_n):
				state["action_symbols"].append("attack")
			_log("超人力量：本回合获得 %d 个攻击行动（手牌 %d 张）" % [lc_n, lc_n], Color(0.9, 0.6, 0.4))
		"lukecage_healing_factor":
			# 卢克凯奇·再生治愈因子：立刻抽 2 张牌
			for _i in range(2):
				_draw_card(hid)
			_log("再生治愈因子：%s 抽取 2 张牌" % DB.hero_name(hid), Color(0.8, 0.9, 1))
		"lukecage_near_invincible":
			# 卢克凯奇·近乎无敌：抽 1 张牌；直到你下回合开始不受伤害
			_draw_card(hid)
			state["heroes"][hid]["invulnerable"] = true
			_log("近乎无敌：%s 抽 1 张牌，且直到下回合开始不受伤害" % DB.hero_name(hid), Color(0.8, 0.8, 1))
		"jessicajones_private_eye":
			# 洁西卡·私家侦探：展示反派牌堆顶一张牌；然后你可以移动到任意地点
			var pe_idx: int = _next_villain_action_from_top()
			if pe_idx >= 0:
				await _ask_villain_card(pe_idx, "私家侦探：这是反派牌堆顶的牌")
			else:
				_log("私家侦探：牌堆里没有可展示的反派行动卡", Color(0.9, 0.8, 0.6))
			var pe_rows: Array = [
				{"icon": "move", "text": "移动到任意地点"},
				{"text": "不移动"},
			]
			var pe_p: int = int(await _ask_action("私家侦探：是否移动？", pe_rows))
			if pe_p == 0:
				var pe_cands: Array = []
				for _i in range(LOCATION_COUNT):
					pe_cands.append(_i)
				await _effect_move_to(hid, pe_cands, "私家侦探：选择目的地")
		"jessicajones_psychic_shield":
			# 洁西卡·心灵防护：抽牌直到手牌有 3 张
			while state["heroes"][hid]["hand"].size() < 3:
				if not _draw_card(hid):
					break
			_log("心灵防护：%s 抽牌直到手牌 3 张" % DB.hero_name(hid), Color(0.8, 0.9, 1))
		"jessicajones_master_detective":
			# 洁西卡·侦探专家：展示反派牌堆顶一张牌，获得等同于该牌移动数量的指示物（类型由玩家选）
			var md_idx: int = _next_villain_action_from_top()
			if md_idx < 0:
				Events.emit_toast("侦探专家：牌堆里没有反派行动卡")
			else:
				await _ask_villain_card(md_idx, "侦探专家：这是反派牌堆顶的牌")
				var md_card: Dictionary = DB.villain(String(state["villain"]))["actions"][md_idx]
				var md_n: int = int(md_card.get("move", 0))
				if md_n <= 0:
					_log("侦探专家：顶牌的移动数量为 0，没有获得指示物", Color(0.9, 0.8, 0.6))
				else:
					var md_keys: Array = ["move", "attack", "heroic", "wild"]
					var md_rows: Array = [
						{"icon": "move", "text": "移动指示物 ×%d" % md_n},
						{"icon": "attack", "text": "攻击指示物 ×%d" % md_n},
						{"icon": "heroic", "text": "英勇指示物 ×%d" % md_n},
						{"icon": "wild", "text": "万能指示物 ×%d" % md_n},
					]
					var md_p: int = int(await _ask_action("侦探专家：选择获得哪种指示物", md_rows))
					var md_key: String = String(md_keys[wrapi(md_p, 0, md_keys.size())])
					state["heroes"][hid]["tokens"][md_key] += md_n
					_log("侦探专家：%s 获得 %d 个%s指示物" % [DB.hero_name(hid), md_n, DB.symbol_name(md_key)], Color(0.8, 0.9, 1))
		"elektra_assassin":
			# 艾丽卡·刺杀大师：进行两次攻击行动
			for _i in range(2):
				if state["phase"] == "game_over":
					break
				await _execute_attack(hid, "none")
		"elektra_ninja_training":
			# 艾丽卡·忍者训练：进行两次攻击行动；或者直到你下回合开始不受伤害
			var nt_rows: Array = [
				{"icon": "attack", "text": "进行两次攻击行动"},
				{"text": "直到下回合开始不受伤害"},
			]
			var nt_p: int = int(await _ask_action("忍者训练：选择其一", nt_rows))
			if nt_p == 0:
				for _i in range(2):
					if state["phase"] == "game_over":
						break
					await _execute_attack(hid, "none")
			else:
				state["heroes"][hid]["invulnerable"] = true
				_log("忍者训练：%s 直到下回合开始不受伤害" % DB.hero_name(hid), Color(0.8, 0.8, 1))
		"elektra_nunchaku":
			# 艾丽卡·双截棍：对两个相邻地点各进行一次攻击
			var nn_from: int = int(state["heroes"][hid]["location"])
			for a in _adjacent_locs(nn_from):
				if state["phase"] == "game_over":
					break
				if _enemy_targets_at(int(a)).size() > 0:
					await _attack_once_at(hid, int(a), "双截棍", 1)
		"quicksilver_super_speed":
			# 快银·超人速度：本回合你移动时可以携带你所在地点的其他英雄一起移动
			state["heroes"][hid]["qs_carry_heroes"] = true
			_log("超人速度：本回合 %s 移动时可携带同地点的其他英雄" % DB.hero_name(hid), Color(0.8, 0.95, 1))
		"quicksilver_speed_combat":
			# 快银·速度格斗：本回合你移动时，每进入一个地点可击败一个暴徒
			state["heroes"][hid]["qs_defeat_on_enter"] = true
			_log("速度格斗：本回合 %s 每进入一个地点可击败 1 个暴徒" % DB.hero_name(hid), Color(0.8, 0.95, 1))
		"quicksilver_dash_rescue":
			# 快银·奔赴救援：本回合你移动时，每进入一个地点可营救一个平民
			state["heroes"][hid]["qs_rescue_on_enter"] = true
			_log("奔赴救援：本回合 %s 每进入一个地点可营救 1 个平民" % DB.hero_name(hid), Color(0.8, 0.95, 1))
		"daredevil_blind_justice":
			# 夜魔侠·盲眼正义：本回合你每击败一个暴徒，就获得一个移动指示物
			state["heroes"][hid]["dd_move_on_thug"] = true
			_log("盲眼正义：本回合 %s 每击败 1 个暴徒获得 1 个移动指示物" % DB.hero_name(hid), Color(0.9, 0.7, 0.7))
		"daredevil_man_without_fear":
			# 夜魔侠·无畏之人：本回合你每营救一个平民，就获得一个移动指示物
			state["heroes"][hid]["dd_move_on_rescue"] = true
			_log("无畏之人：本回合 %s 每营救 1 个平民获得 1 个移动指示物" % DB.hero_name(hid), Color(0.9, 0.7, 0.7))
		"daredevil_radar_sense":
			# 夜魔侠·雷达感官：本回合你每进入一个地点，获得 1 个英勇或攻击指示物（由玩家选择）
			state["heroes"][hid]["dd_token_on_enter"] = true
			_log("雷达感官：本回合 %s 每进入一个地点获得 1 个英勇/攻击指示物" % DB.hero_name(hid), Color(0.9, 0.7, 0.7))

		# ============ 第一季众筹第三批（3.x，13 位）============
		"adamwarlock_life_avatar":
			# 术士亚当·生命化身（裁定1）：下一个反派回合翻出的牌背面朝上、连移动也不发生 → 反派整个回合空过
			state["villain_turn_skip"] = true
			_log("生命化身：下一个反派回合的反派行动卡将背面朝上加入故事情节，且不发生任何效果（反派空过该回合）", Color(0.75, 0.85, 1))
		"adamwarlock_quantum_magic":
			# 术士亚当·量子魔法（裁定2）：查看牌堆顶 3 张并按任意顺序放回（鼠标拖拽排序）
			await _ask_quantum_magic_order(hid)
		"adamwarlock_immortality":
			# 术士亚当·不朽：只要这张牌在故事情节可见区正面朝上，弃牌时不会丢掉最后一张手牌
			# （判定在 _immortality_active()，弃牌流程里消费；这里只记录）
			_log("不朽：只要这张牌仍在故事情节可见区，%s 就不会因为弃牌丢掉最后一张手牌" % DB.hero_name(hid), Color(0.85, 0.85, 1))
		"missamerica_stargate":
			# 美国小姐·星门：进行两次万能行动
			for _ma_i in range(2):
				state["action_symbols"].append("wild")
			_log("星门：%s 获得 2 次万能行动" % DB.hero_name(hid), Color(0.9, 0.7, 1))
		"missamerica_energy_infusion":
			# 美国小姐·能量注入：进行两次攻击行动
			for _ma_j in range(2):
				state["action_symbols"].append("attack")
			_log("能量注入：%s 获得 2 次攻击行动" % DB.hero_name(hid), Color(1, 0.8, 0.6))
		"missamerica_invincible":
			# 美国小姐·无敌：直到你下回合开始，你无法受到任何伤害
			state["heroes"][hid]["invulnerable"] = true
			_log("无敌：直到 %s 的下个回合开始，其不会受到任何伤害" % DB.hero_name(hid), Color(0.8, 0.95, 1))
		"nebula_regen_implant":
			# 星云·再生植入体：抽牌直到你有 3 张手牌
			var nb_need: int = 3 - int(state["heroes"][hid]["hand"].size())
			var nb_n := 0
			while nb_n < nb_need:
				if not _draw_card(hid):
					break
				nb_n += 1
			_log("再生植入体：%s 抽牌直到 3 张手牌（实抽 %d 张）" % [DB.hero_name(hid), nb_n], Color(0.8, 0.9, 1))
		"nebula_image_projection":
			# 星云·影像投射（裁定3）：每个英雄自愿交换手牌与故事情节卡（可跳过），然后移除反派牌堆顶一张
			await _nebula_image_projection(hid)
		"nebula_electro_baton":
			# 星云·电机警棍：在两个相邻地点进行两次攻击，由玩家分配
			await _distribute_attacks(hid, _adjacent_locs(int(state["heroes"][hid]["location"])), 2, "电机警棍")
		"yondou_yaka_whirlwind":
			# 勇度·亚卡箭旋风：从你所在地点顺时针，击败每个地点 1 个暴徒，直到遇到没有暴徒的地点
			var yd_cur: int = int(state["heroes"][hid]["location"])
			var yd_guard := 0
			while yd_guard < LOCATION_COUNT:
				if int(state["locations"][yd_cur]["thug"]) <= 0:
					break
				_defeat_thug(yd_cur, 1, hid)
				_log("亚卡箭旋风：击败 %s 的 1 个暴徒" % _loc_name(yd_cur), Color(0.9, 0.8, 0.5))
				yd_cur = (yd_cur + 1) % LOCATION_COUNT
				yd_guard += 1
			if yd_guard == 0:
				_log("亚卡箭旋风：你所在地点没有暴徒，效果结束", Color(0.8, 0.8, 0.8))
		"yondou_yaka_barrage":
			# 勇度·亚卡箭乱射：三次攻击，可分配在你所在地点和两个相邻地点
			var yd_locs: Array = _adjacent_locs(int(state["heroes"][hid]["location"]))
			yd_locs.append(int(state["heroes"][hid]["location"]))
			await _distribute_attacks(hid, yd_locs, 3, "亚卡箭乱射")
		"yondou_traitor":
			# 勇度·叛徒：将你所在地点的平民↔暴徒互换
			var yd_loc: int = int(state["heroes"][hid]["location"])
			var yd_civ: int = int(state["locations"][yd_loc]["civ"])
			var yd_thug: int = int(state["locations"][yd_loc]["thug"])
			state["locations"][yd_loc]["civ"] = yd_thug
			state["locations"][yd_loc]["thug"] = yd_civ
			_log("叛徒：%s 的平民与暴徒互换（民 %d→%d，暴 %d→%d）" % [_loc_name(yd_loc), yd_civ, yd_thug, yd_thug, yd_civ], Color(0.9, 0.8, 0.5))
		"ghostrider_mystic_chain":
			# 恶灵骑士·神秘锁链：对你所在地点的每个暴徒进行两次攻击
			var gr_loc: int = int(state["heroes"][hid]["location"])
			var gr_guard := 0
			while int(state["locations"][gr_loc]["thug"]) > 0 and gr_guard < 20:
				await _attack_once_at(hid, gr_loc, "神秘锁链", 2)
				gr_guard += 1
			if gr_guard == 0:
				_log("神秘锁链：你所在地点没有暴徒", Color(0.8, 0.8, 0.8))
		"ghostrider_hellfire_control":
			# 恶灵骑士·地狱火操控：对你所在地点的单个敌人造成三次攻击
			var gr_loc2: int = int(state["heroes"][hid]["location"])
			if _enemy_targets_at(gr_loc2).size() > 0:
				await _attack_once_at(hid, gr_loc2, "地狱火操控", 3)
			else:
				Events.emit_toast("你所在地点没有可攻击的敌人")
		"ghostrider_supernatural_sense":
			# 恶灵骑士·超自然感知：进行一次攻击行动和一次英勇行动，然后抽 1 张牌
			state["action_symbols"].append("attack")
			state["action_symbols"].append("heroic")
			_draw_card(hid)
			_log("超自然感知：%s 获得 1 次攻击行动、1 次英勇行动，并抽 1 张牌" % DB.hero_name(hid), Color(0.9, 0.8, 0.6))
		"mockingbird_battle_staff":
			# 仿声鸟·战斗法杖：击败你所在地点的 2 个暴徒
			var mb_loc: int = int(state["heroes"][hid]["location"])
			_defeat_thug(mb_loc, 2, hid)
			_log("战斗法杖：击败 %s 的 2 个暴徒" % _loc_name(mb_loc), Color(0.9, 0.8, 0.6))
		"mockingbird_spy_master_1", "mockingbird_spy_master_2":
			# 仿声鸟·间谍大师（两张卡各自独立生效）：下一个反派回合，反派无法在你所在地点添加平民/暴徒
			state["heroes"][hid]["spy_master_armed"] = true
			state["heroes"][hid]["spy_master_loc"] = int(state["heroes"][hid]["location"])
			_log("间谍大师：下一个反派回合，反派无法在 %s 添加平民/暴徒指示物" % _loc_name(int(state["heroes"][hid]["location"])), Color(0.8, 0.9, 1))
		"shehulk_transform_1", "shehulk_transform_2", "shehulk_transform_3", "shehulk_transform_4":
			# 女浩克·变形（4 张各自独立生效）：一次攻击行动 + 故事情节中每有一张「变形」（含这张）额外一次
			var sh_n: int = _transform_count_in_story()
			for _sh_i in range(sh_n):
				state["action_symbols"].append("attack")
			_log("变形：故事情节中有 %d 张「变形」（含这张）→ %s 获得 %d 次攻击行动" % [sh_n, DB.hero_name(hid), sh_n], Color(0.85, 1, 0.7))
		"squirrelgirl_night_vision":
			# 松鼠女·夜视：揭示牌堆顶一张牌（公开、原位），然后可选择把它放到牌堆底
			await _reveal_top_optionally_to_bottom(hid)
		"squirrelgirl_squirrel_army":
			# 松鼠女·松鼠大军：对每个地点的一个敌人造成一点攻击（每个地点都要弹窗选择）
			for _sq_l in range(LOCATION_COUNT):
				if state["phase"] == "game_over":
					break
				var sq_tgts: Array = _enemy_targets_at(_sq_l)
				if sq_tgts.size() == 0:
					continue
				var sq_rows: Array = _enemy_target_rows(_sq_l, sq_tgts)
				sq_rows.append({"text": "跳过这个地点"})
				var sq_pick: int = int(await _ask_action("松鼠大军：%s 要攻击哪个敌人？" % _loc_name(_sq_l), sq_rows))
				if sq_pick < 0 or sq_pick >= sq_tgts.size():
					continue
				await _perform_attack_at(_sq_l, String(sq_tgts[sq_pick]), hid)
			_log("松鼠大军：对每个地点的一个敌人各攻击一次", Color(0.9, 0.8, 0.6))
		"squirrelgirl_hyper_awareness":
			# 松鼠女·非常感知（裁定4）：特殊效果牌数 > 反派当前生命值 → 英雄直接获胜（持续检查见 _check_hyper_awareness）
			_check_hyper_awareness("非常感知")
		"moonknight_moon_suit":
			# 月光骑士·月光骑士战衣（裁定5）：直到你下个回合开始，每次受到伤害都可无视并（可选）移动到任意地点
			state["heroes"][hid]["moon_suit"] = true
			_log("月光骑士战衣：直到 %s 下个回合开始，其每次受到伤害都可无视并（可选）移动到任意地点" % DB.hero_name(hid), Color(0.85, 0.9, 1))
		"moonknight_dissociative":
			# 月光骑士·解离性身份障碍：手牌与牌库混洗后重抽 3 张
			var mk_h: Dictionary = state["heroes"][hid]
			for c in (mk_h["hand"] as Array):
				(mk_h["deck"] as Array).append(c)
			(mk_h["hand"] as Array).clear()
			(mk_h["deck"] as Array).shuffle()
			var mk_n := 0
			for _mk_i in range(3):
				if _draw_card(hid):
					mk_n += 1
			_log("解离性身份障碍：手牌与牌库混洗后重抽 %d 张" % mk_n, Color(0.8, 0.85, 1))
		"moonknight_khonshu_power":
			# 月光骑士·孔苏之力：故事情节中每有一张特殊效果牌（含这张）→ 获得等量万能指示物
			var mk_n2: int = _special_effect_cards_in_story()
			var mk_pool: Dictionary = _hero_token_pool(hid)
			mk_pool["wild"] = int(mk_pool["wild"]) + mk_n2
			_log("孔苏之力：故事情节中有 %d 张特殊效果牌（含这张）→ %s 获得 %d 个万能指示物" % [mk_n2, DB.hero_name(hid), mk_n2], Color(0.9, 0.8, 1))
		"nova_helping_hand_1", "nova_helping_hand_2", "nova_helping_hand_3":
			# 新星·我就是援手（3 张各自独立生效）：在一个相邻地点进行两次英勇行动
			var nv_locs: Array = _adjacent_locs(int(state["heroes"][hid]["location"]))
			if nv_locs.size() == 0:
				Events.emit_toast("没有相邻地点")
			else:
				var nv_loc := -1
				var nv_rows: Array = []
				for a in nv_locs:
					nv_rows.append({"icon": "heroic", "arrow": "heroic", "text": _loc_name(int(a)), "bottom": String(state["locations"][int(a)].get("image", ""))})
				var nv_pick: int = int(await _ask_action("我就是援手：选择在哪个相邻地点进行两次英勇行动", nv_rows))
				nv_loc = int(nv_locs[clampi(nv_pick, 0, nv_locs.size() - 1)])
				for _nv_i in range(2):
					state["_astral_loc"] = nv_loc      # 借"星体投射"的临时地点机制，让这次英勇行动在该地点结算
					await _execute_heroic(hid, "none")
				_log("我就是援手：在 %s 进行两次英勇行动" % _loc_name(nv_loc), Color(0.8, 0.95, 1))
		"blade_blood_bath":
			# 刀锋战士·血浴：击败你所在地点的所有暴徒
			var bl_loc: int = int(state["heroes"][hid]["location"])
			var bl_n: int = int(state["locations"][bl_loc]["thug"])
			_defeat_thug(bl_loc, bl_n, hid)
			_log("血浴：击败 %s 的全部 %d 个暴徒" % [_loc_name(bl_loc), bl_n], Color(0.9, 0.6, 0.6))
		"blade_vampiric_heal":
			# 刀锋战士·吸血愈合：抽 1 张牌
			_draw_card(hid)
			_log("吸血愈合：%s 抽取 1 张牌" % DB.hero_name(hid), Color(0.8, 0.9, 1))
		"blade_hunter_skill":
			# 刀锋战士·猎人技巧：本回合你对单个敌人的一次攻击行动改为两次攻击（一次行动造成两点伤害）
			state["heroes"][hid]["hunter_skill"] = true
			_log("猎人技巧：本回合 %s 对单个敌人的一次攻击行动造成两点伤害" % DB.hero_name(hid), Color(0.9, 0.6, 0.6))
		"howardtheduck_no_more_mr_nice_duck":
			# 霍华德鸭·不再是好好先生鸭！：对你所在地点的每个敌人造成两次攻击
			var hd_loc: int = int(state["heroes"][hid]["location"])
			var hd_tgts: Array = _enemy_targets_at(hd_loc).duplicate()
			for tgt in hd_tgts:
				if state["phase"] == "game_over":
					break
				await _perform_attack_at(hd_loc, String(tgt), hid)
				await _perform_attack_at(hd_loc, String(tgt), hid)
			_log("不再是好好先生鸭！：对 %s 的每个敌人各攻击两次" % _loc_name(hd_loc), Color(1, 0.7, 0.5))
		"howardtheduck_big_weird_gun":
			# 霍华德鸭·巨大的怪枪：对任意一个地点进行两次攻击行动
			var hd_cands: Array = []
			for _hd_i in range(LOCATION_COUNT):
				hd_cands.append(_hd_i)
			var hd_pick: int = await _pick_attack_loc(hid, hd_cands, "巨大的怪枪：选择攻击地点")
			if hd_pick < 0:
				Events.emit_toast("场上没有可攻击的目标")
			else:
				for _hd_j in range(2):
					await _attack_once_at(hid, hd_pick, "巨大的怪枪", 1)
		"howardtheduck_neutron_disintegrator":
			# 霍华德鸭·中子分解器：对你所在地点一个反派/爪牙造成伤害直到其生命值剩 1；本回合不能再使用攻击行动
			await _howard_neutron_disintegrator(hid)
		"msmarvel_appearance_change":
			# 惊奇女士·外观改造：本回合你所有行动视为万能行动
			var ms_conv := 0
			for _ms_i in range(state["action_symbols"].size()):
				if String(state["action_symbols"][_ms_i]) != "wild":
					state["action_symbols"][_ms_i] = "wild"
					ms_conv += 1
			state["heroes"][hid]["appearance_change"] = true
			_log("外观改造：本回合 %s 的所有行动视为万能行动（已转换 %d 个）" % [DB.hero_name(hid), ms_conv], Color(0.9, 0.8, 1))
		"msmarvel_elastic_extension":
			# 惊奇女士·弹性延伸：本回合你的攻击行动可以指定相邻地点的敌人
			state["heroes"][hid]["elastic_extension"] = true
			_log("弹性延伸：本回合 %s 的攻击行动可以指定相邻地点的敌人" % DB.hero_name(hid), Color(0.9, 0.8, 1))
		"msmarvel_morphogenesis":
			# 惊奇女士·形态发生：可将任意数量手牌与故事情节中任意数量正面朝上的自己的行动牌交换
			await _msmarvel_morphogenesis(hid)
	state["in_effect"] = false
	Events.emit_state_changed()
	await _maybe_auto_end_turn()  # 效果用完后符号若已用尽则自动结束回合

## 从牌堆顶往下找第一张真正的反派行动牌（跳过无限宝石这类隐藏字典），返回其索引；找不到返回 -1
func _next_villain_action_from_top() -> int:
	for item in state["master_deck"]:
		if item is Dictionary:
			continue
		return int(item)
	return -1

## 审讯"放到牌组底部"：把堆顶第一张真正的反派行动牌移到牌底（其上若有隐藏宝石则保持原位不动）
func _state_move_card_to_bottom(card_idx: int) -> void:
	var hit := -1
	for i in range(state["master_deck"].size()):
		var item: Variant = state["master_deck"][i]
		if item is Dictionary:
			continue
		if int(item) == card_idx:
			hit = i
			break
	if hit >= 0:
		state["master_deck"].remove_at(hit)
		state["master_deck"].append(card_idx)

func villain_action_desc(idx: int) -> String:
	var a: Dictionary = DB.villain(state["villain"])["actions"][idx]
	var parts: Array = ["移动%d" % a.get("move", 0)]
	if a.get("bam", false): parts.append("BAM")
	if a.get("effect", null) != null: parts.append(a["effect"]["name"])
	if a.get("place", null) != null: parts.append("放置指示物")
	return " - ".join(parts)

# ---------------------------------------------------------------- end of hero turn

## 结束行动阶段（玩家主动提前结束；随后自动结束回合）
func end_actions() -> void:
	if _net_gate("end_actions", []):
		return
	if state["phase"] != "hero_actions":
		return
	state["phase"] = "hero_end"
	Events.emit_state_changed()
	await _maybe_auto_end_turn()

## 行动用完后自动结束回合（不再需要手动点"结束回合"）：
## 行动符号用尽、行动指示物用尽、且卡牌效果已使用/不可用时，自动进入回合结束流程
func _maybe_auto_end_turn() -> void:
	if state["phase"] != "hero_actions" and state["phase"] != "hero_end":
		return
	if state.get("end_turn_busy", false):
		return
	# 卡牌效果结算中（trigger_effect 内调用 _execute_move/_execute_attack/_execute_heroic）：
	# 此时不提前结束回合，等效果整体结算完由 trigger_effect 末尾统一判定
	if state.get("in_effect", false):
		return
	if state["phase"] == "hero_actions":
		if state["action_symbols"].size() > 0:
			return  # 还有行动符号未用
		if _hero_has_action_tokens():
			return  # 还有行动指示物可用（玩家可继续行动）
		if state.get("effect_available", false) and not state.get("effect_used", false):
			return  # 还有卡牌效果可用，留给玩家
		state["phase"] = "hero_end"
		Events.emit_state_changed()
	# 自动结束回合是"流程推进"，不能被联机闸门拦住：
	# 否则主机在别人回合里 _net_gate 返回拦截 → 回合永远结束不了，玩家被迫手动点"结束回合"。
	_net_remote = true
	await end_turn()
	_net_remote = false

## 当前英雄是否还有可用的行动指示物（移动/攻击/英勇/万能）
## 神盾局模式：玩家共享指示物池
func _hero_has_action_tokens() -> bool:
	var hid: String = state["hero_ids"][state["current_hero"]]
	var t: Dictionary = state["shield_tokens"] if state["mode"] == "shield" else state["heroes"][hid]["tokens"]
	return int(t["move"]) > 0 or int(t["attack"]) > 0 or int(t["heroic"]) > 0 or int(t["wild"]) > 0

## 结束回合（异步：可能等待地点效果确认）
func end_turn() -> void:
	if _net_gate("end_turn", []):
		return
	if state["phase"] != "hero_end":
		return
	if state.get("end_turn_busy", false):
		return  # 防止地点效果执行期间被重复触发（如再次点击结束回合）
	state["end_turn_busy"] = true
	var hid: String = state["hero_ids"][state["current_hero"]]
	var h: Dictionary = state["heroes"][hid]
	var loc: int = h["location"]
	var l: Dictionary = state["locations"][loc]
	# 蜘猪侠卡通蛛网（被动）：若该英雄在反派所在地点结束回合，则取消失下一次反派移动
	if h.get("cartoon_web_armed", false):
		if loc == state["villain_pos"]:
			state["no_villain_move_next"] = true
			_log("卡通蛛网：%s 在反派所在地点结束回合，取消失下一次反派移动" % DB.hero_name(hid), Color(1, 0.85, 0.4))
		else:
			_log("卡通蛛网：%s 未在反派所在地点结束回合，效果未触发" % DB.hero_name(hid), Color(0.9, 0.8, 0.6))
		h["cartoon_web_armed"] = false
	# 迈尔斯蛛网（被动）：若该英雄在反派所在地点结束回合，则推迟反派下一个回合
	if h.get("miles_web_armed", false):
		if loc == state["villain_pos"]:
			state["delay_villain_turn"] = true
			_log("迈尔斯蛛网：%s 在反派所在地点结束回合，推迟反派下一个回合" % DB.hero_name(hid), Color(0.7, 0.9, 1))
		else:
			_log("迈尔斯蛛网：%s 未在反派所在地点结束回合，效果未触发" % DB.hero_name(hid), Color(0.9, 0.8, 0.6))
		h["miles_web_armed"] = false
	if l["threat"] == null and int(l["crisis"]) > 0 and (state["villain"] == "electro" or state["villain"] == "kang"):
		# 电光人 / 康（第一季众筹）：只要地点上有危机指示物，英雄就无法使用该地点的回合结束效果
		# （康的面板溢出文字：拥有危机指示物的地点将失去其回合效果）
		_log("%s %s 有危机指示物，无法使用该地点的回合结束效果"
			% ["⚡" if state["villain"] == "electro" else "⏳", _loc_name(loc)], Color(1, 0.85, 0.4))
	elif l["threat"] == null and state.get("mode", "") == "s6" and _s6_loc_has_villain(loc):
		# 邪恶六人组：地点上有任何反派，英雄就不能使用该地点的回合结束效果
		_log("🕸 %s 上有反派（%s），不能使用该地点的回合结束效果"
			% [_loc_name(loc), ", ".join(_s6_at(loc).map(func(x): return DB.villain_name(String(x))))], Color(1, 0.85, 0.5))
	elif l["threat"] == null:
		await _resolve_location_end_effect(hid, loc)
	else:
		# 暗杀企图（基尔格蒙威胁）：在该地点结束回合的英雄受到 1 点伤害
		if l["threat"]["name"] == "暗杀企图":
			_log("暗杀企图：%s 在该地点结束回合，受到 1 点伤害" % DB.hero_name(hid), Color(1, 0.6, 0.4))
			await _deal_damage_to_hero(hid, 1)
		# 隐藏陷阱（亡刃将军威胁）：在该地点结束回合的英雄受到 1 点伤害
		if l["threat"]["name"] == "隐藏陷阱":
			_log("隐藏陷阱：%s 在该地点结束回合，受到 1 点伤害" % DB.hero_name(hid), Color(1, 0.6, 0.4))
			await _deal_damage_to_hero(hid, 1)
	# 康·时间军队威胁（持续）：英雄在**有暴徒**的任何地点结束回合都受到 1 点伤害
	# （与该地点有没有威胁卡无关；场上每张生效的「时间军队」各造成 1 点）
	if state["villain"] == "kang" and int(l["thug"]) > 0:
		var army_dmg: int = VillainRules.kang_time_army_damage(self)
		if army_dmg > 0:
			_log("时间军队：%s 在有暴徒的 %s 结束回合，受到 %d 点伤害"
				% [DB.hero_name(hid), _loc_name(loc), army_dmg], Color(1, 0.6, 0.4))
			await _deal_damage_to_hero(hid, army_dmg)
	if state["phase"] == "game_over":
		state["end_turn_busy"] = false
		return
	# 泽莫男爵特殊规则（裁定①②）：英雄回合结束 → 逐个危机指示物弹窗，盖住本回合行动卡的底部符号
	await _zemo_cover_crisis(hid)
	# 犀牛人：① 威胁卡「无掩护」→ 在此位置结束回合的英雄获得 1 个危机指示物；
	#         ② 特殊规则②→ 本回合被要求面朝下出牌的英雄，回合结束时丢弃所有危机指示物
	if String(state["villain"]) == "rhino":
		VillainRules._rhino_on_hero_end_turn(self, hid)
	if state["phase"] == "game_over":
		state["end_turn_busy"] = false
		return
	if state["mode"] == "shield":
		# 神盾局：无英雄 KO 检查（共享手牌），按节奏进入反派或下一回合
		var needed := 2 if state["missions_completed"] >= 1 else 3
		if state["hero_cards_played"] >= needed:
			await _run_villain_turn()
		else:
			_start_hero_turn()
		state["end_turn_busy"] = false
		return
	if h["hand"].size() == 0 and not h["ko"]:
		await _ko_hero(hid)
	if state["phase"] == "game_over":
		state["end_turn_busy"] = false
		return
	if state.get("traitor_pending", false) and state["challenge"] == "traitor" and not state["traitor_revealed"]:
		# 按顺序：英雄回合 → 地点结束效果 → （此处）指认叛徒 → 再进入反派回合/下一英雄
		state["traitor_pending"] = false
		await _run_traitor_accusation()
		if state["phase"] == "game_over":
			state["end_turn_busy"] = false
			return
	var needed := 2 if state["missions_completed"] >= 1 else 3
	# 邪恶六人组模式：节奏固定为"每 2 个英雄回合"打出一张反派行动卡（不按英雄卡数）
	if state.get("mode", "") == "s6":
		var s6t: Dictionary = _s6()
		s6t["hero_turns"] = int(s6t.get("hero_turns", 0)) + 1
		if int(s6t["hero_turns"]) % 2 == 0:
			await _s6_run_turn()
		else:
			state["current_hero"] = (state["current_hero"] + 1) % state["hero_ids"].size()
			_start_hero_turn()
		state["end_turn_busy"] = false
		return
	# 迈尔斯蛛网：反派回合被推迟一个英雄回合（把本次进入反派的所需英雄卡数 +1，真正延后一个英雄回合）
	if state.get("delay_villain_turn", false):
		state["delay_villain_turn"] = false
		needed += 1
		_log("蛛网：反派回合被推迟一个英雄回合", Color(0.7, 0.9, 1))
	if state["hero_cards_played"] >= needed:
		await _run_villain_turn()
	else:
		state["current_hero"] = (state["current_hero"] + 1) % state["hero_ids"].size()
		_start_hero_turn()
	state["end_turn_busy"] = false

func _resolve_location_end_effect(hid: String, loc: int) -> void:
	var l: Dictionary = state["locations"][loc]
	var def: Dictionary = DB.location(l["id"])
	var eff: Dictionary = def["end_turn"]
	match eff["type"]:
		"defeat_thug":
			if l["thug"] > 0 and await _ask_confirm("纽约警察局总部：消灭本地点 1 个暴徒？"):
				_defeat_thug(loc, 1)
		"rescue_civ":
			if l["civ"] > 0 and await _ask_confirm("时代广场：营救本地点 1 名平民？"):
				_rescue_civ(hid, loc)
		"move_anywhere":
			if await _ask_confirm("神盾局天空母舰：移动到任意地点？"):
				var opts: Array = []
				var names: Array = []
				for i in range(LOCATION_COUNT):
					if state["locations"][i].get("destroyed", false):
						continue   # 被摧毁的地点已移出游戏，不可选
					opts.append(i)
					names.append(_loc_name(i))
				var choice = await _ask("选择移动目的地", names)
				await _set_hero_loc(hid, int(opts[wrapi(int(choice), 0, opts.size())]))   # A1：统一出口
				_log("%s 移动到 %s（天空母舰）" % [DB.hero_name(hid), _loc_name(state["heroes"][hid]["location"])], Color(0.8, 0.9, 1))
		"draw_to_3":
			# 复仇者大厦2（"你可以抽牌直到3张"）可取消；复仇者庄园（强制）直接抽
			var is_cancelable: bool = l["id"] == "avengers_tower2"
			if (not is_cancelable) or await _ask_confirm("复仇者大厦：抽取手牌直到 3 张？"):
				while state["heroes"][hid]["hand"].size() < 3:
					if not _draw_card(hid):
						break
				_log("复仇者大厦：抽牌直到手牌 3 张", Color(0.8, 0.9, 1))
		"search_top":
			if await _ask_confirm("复仇者大厦：从牌组搜寻 1 张牌放到顶部？"):
				var h2: Dictionary = state["heroes"][hid]
				if h2["deck"].size() > 0:
					var di: int = await _ask_deck_card(hid, "%s：从牌库选择 1 张牌放到牌库顶部" % DB.hero_name(hid))
					if di >= 0 and di < h2["deck"].size():
						var card: int = h2["deck"][di]
						h2["deck"].remove_at(di)
						h2["deck"].push_front(card)
						_log("%s 搜寻牌库：选中的牌放到牌库顶部" % DB.hero_name(hid), Color(0.8, 0.9, 1))
						Events.emit_state_changed()
		"attack_once":
			# 勇士瀑布：你可以在该地点执行 1 个攻击（玩家选目标）
			await _execute_attack(hid, "")
		"remove_crisis_any":
			# 大土丘：从任意地点删除 1 个危机指示物（无代价，任意来源的危机都能清）
			var with_crisis: Array = []
			for i in range(LOCATION_COUNT):
				if state["locations"][i].get("destroyed", false):
					continue
				if int(state["locations"][i]["crisis"]) > 0:
					with_crisis.append(i)
			if with_crisis.size() > 0:
				var nm: Array = []
				for i in with_crisis:
					nm.append(_loc_name(i))
				var cr_choice: int = await _ask("大土丘：选择要删除危机的任意地点", nm)
				var tgt_loc: int = with_crisis[wrapi(int(cr_choice), 0, with_crisis.size())]
				state["locations"][tgt_loc]["crisis"] -= 1
				_log("大土丘：%s 删除 1 个危机指示物" % _loc_name(tgt_loc), Color(0.7, 0.7, 1))
				Events.emit_state_changed()
			else:
				_log("大土丘：没有任何地点有危机指示物", Color(0.8, 0.8, 0.8))
		"gain_wild_1":
			# 贾巴里部落：获得 1 个万能行动指示物
			state["heroes"][hid]["tokens"]["wild"] += 1
			_log("%s 获得 1 个万能行动指示物（贾巴里部落）" % DB.hero_name(hid), Color(0.9, 0.9, 0.5))
			Events.emit_state_changed()
		"move_hero_to_adjacent":
			# 王座大殿：选择 1 名英雄（含自己），移到该英雄所在地点的相邻地点
			var nm_t: Array = []
			var hids_t: Array = []
			for hh in state["hero_ids"]:
				nm_t.append(DB.hero_name(hh))
				hids_t.append(hh)
			if hids_t.size() > 0:
				var pick_t: int = await _ask("王座大殿：选择 1 名英雄", nm_t)
				var pick_hid: String = hids_t[wrapi(int(pick_t), 0, hids_t.size())]
				var hl: int = state["heroes"][pick_hid]["location"]
				var adj_opts: Array = _adjacent_locs(hl)
				var adj_names: Array = [_loc_name(adj_opts[0]), _loc_name(adj_opts[1])]
				var pick_adj: int = await _ask("王座大殿：%s 移到的相邻地点" % DB.hero_name(pick_hid), adj_names)
				var new_loc: int = adj_opts[wrapi(int(pick_adj), 0, adj_opts.size())]
				await _set_hero_loc(pick_hid, new_loc)   # 王座大殿（A1）
				_log("王座大殿：%s 移动到 %s" % [DB.hero_name(pick_hid), _loc_name(new_loc)], Color(0.8, 0.9, 1))
				Events.emit_state_changed()
		"discard_2_tokens_any":
			# 阿斯加德宫殿：将任意地点以任意组合弃置 2 个平民/暴徒指示物（可选，可跳过）
			var with_tok: Array = []
			for i in range(LOCATION_COUNT):
				if state["locations"][i].get("destroyed", false):
					continue
				if int(state["locations"][i]["civ"]) + int(state["locations"][i]["thug"]) > 0:
					with_tok.append(i)
			if with_tok.size() > 0:
				var nm_tok: Array = []
				for i in with_tok:
					nm_tok.append(_loc_name(i))
				nm_tok.append("◎ 跳过")
				var t_choice: int = await _ask("阿斯加德宫殿：选择弃置指示物的地点", nm_tok)
				if int(t_choice) >= with_tok.size():
					_log("阿斯加德宫殿：跳过此效果", Color(0.8, 0.8, 0.8))
					Events.emit_state_changed()
					return
				var t_loc: int = with_tok[wrapi(int(t_choice), 0, with_tok.size())]
				var tl2: Dictionary = state["locations"][t_loc]
				# 任意组合弃 2 个：优先弃民，其次弃暴；每弃一个都记录
				var dropped_n := 0
				while dropped_n < 2 and (tl2["civ"] > 0 or tl2["thug"] > 0):
					var opts: Array = ["❌ 结束"]
					var keys: Array = ["end"]
					if tl2["civ"] > 0:
						opts.append("弃 1 平民"); keys.append("civ")
					if tl2["thug"] > 0:
						opts.append("弃 1 暴徒"); keys.append("thug")
					var pick_d: int = await _ask("阿斯加德宫殿：%s 弃置（已弃 %d/2）" % [_loc_name(t_loc), dropped_n], opts)
					var pk: String = keys[wrapi(int(pick_d), 0, keys.size())]
					if pk == "end":
						break
					if pk == "civ": tl2["civ"] -= 1
					else: tl2["thug"] -= 1
					dropped_n += 1
				_log("阿斯加德宫殿：%s 弃置 %d 个指示物" % [_loc_name(t_loc), dropped_n], Color(0.9, 0.7, 0.4))
				Events.emit_state_changed()
		"move_all_heroes_here":
			# 彩虹桥：该地点所有英雄移动到任意地点（同一目的地；被摧毁的地点不可选）
			var heroes_here: Array = _heroes_at(loc)
			if heroes_here.size() > 0:
				var any_nm: Array = []
				var any_locs: Array = []
				for i in range(LOCATION_COUNT):
					if state["locations"][i].get("destroyed", false):
						continue
					any_nm.append(_loc_name(i))
					any_locs.append(i)
				var pick_any: int = await _ask("彩虹桥：所有英雄移到的地点", any_nm)
				var dest: int = int(any_locs[wrapi(int(pick_any), 0, any_locs.size())])
				for hh2 in heroes_here:
					await _set_hero_loc(hh2, dest)   # A1：统一出口
				_log("彩虹桥：%d 名英雄移动到 %s" % [heroes_here.size(), _loc_name(dest)], Color(0.8, 0.9, 1))
				Events.emit_state_changed()
		"move_heroes_to_here":
			# 海姆达尔天文台：逐个选任意英雄从其他地点移到该地点
			while true:
				var cand: Array = []
				for hh3 in state["hero_ids"]:
					if state["heroes"][hh3]["location"] != loc and not state["heroes"][hh3]["ko"]:
						cand.append(hh3)
				if cand.size() == 0:
					break
				var cnm: Array = []
				for hh3 in cand:
					cnm.append(DB.hero_name(hh3))
				cnm.append("❌ 结束")
				var pick_hmove: int = await _ask("海姆达尔天文台：选择移到此地点的英雄", cnm)
				if int(pick_hmove) >= cand.size():
					break
				var mv_hid: String = cand[wrapi(int(pick_hmove), 0, cand.size())]
				await _set_hero_loc(mv_hid, loc)   # 地点效果推动（A1）
				_log("海姆达尔天文台：%s 移到 %s" % [DB.hero_name(mv_hid), _loc_name(loc)], Color(0.8, 0.9, 1))
			Events.emit_state_changed()
		"valhalla_redraw":
			# 瓦尔哈拉：任意张手牌放牌库底，抽等量手牌（全弃不KO）
			var hv: Dictionary = state["heroes"][hid]
			if hv["hand"].size() > 0:
				# 让玩家选择要放置几张（0=不放置）
				var cnt_opts: Array = []
				for c in range(0, hv["hand"].size() + 1):
					cnt_opts.append("放置 %d 张" % c)
				var cnt_choice: int = await _ask("瓦尔哈拉：选择放置牌库底的手牌数量", cnt_opts)
				var want_n: int = wrapi(int(cnt_choice), 0, cnt_opts.size())
				var moved_n := 0
				if want_n > 0 and want_n <= hv["hand"].size():
					var picked_v: Array = await _ask_hand_cards(hid, want_n, "瓦尔哈拉：选择要放置牌库底的 %d 张手牌" % want_n)
					var idxs: Array = picked_v.duplicate()
					idxs.sort()
					var hvr: Array = hv["hand"]
					for k in range(idxs.size() - 1, -1, -1):
						var idx_v: int = int(idxs[k])
						if idx_v >= 0 and idx_v < hvr.size():
							var cv: int = hvr[idx_v]
							hvr.remove_at(idx_v)
							hv["deck"].append(cv)
							moved_n += 1
					for mv in range(moved_n):
						_draw_card(hid)
				_log("瓦尔哈拉：%s 放 %d 张到牌库底并抽 %d 张（不KO）" % [DB.hero_name(hid), moved_n, moved_n], Color(0.8, 0.9, 1))
				Events.emit_state_changed()

		"move_tokens":
			if l["civ"] + l["thug"] > 0 and await _ask_confirm("中央公园：移动此地最多 2 名指示物到任意地点？（分批次：每批选一个指示物和一个地点）"):
				await _move_tokens_from(loc)  # 必须 await：效果执行完才继续回合流程
		"swap_story":
			var h3: Dictionary = state["heroes"][hid]
			if h3["hand"].size() > 0 and state["story"].size() > 0 and await _ask_confirm("斯塔克实验室：用一张手牌交换故事情节中的一张卡牌？"):
				await _swap_story(hid)
		"remove_crisis":
			if await _ask_confirm("神盾局总部：弃一张手牌到牌库底，移除任意一处 1 个危机指示物？"):
				await _remove_crisis_effect(hid)
		"draw_if_hand_le2":
			# 阿斯加德：手牌 1 或 2 张时可抽 1 张
			var h4: Dictionary = state["heroes"][hid]
			if (h4["hand"].size() == 1 or h4["hand"].size() == 2) and await _ask_confirm("阿斯加德：抽取 1 张牌？"):
				_draw_card(hid)
				_log("%s 在阿斯加德抽取 1 张牌" % DB.hero_name(hid), Color(0.8, 0.9, 1))
		"gain_attack_2":
			# 尼达维利尔：获得 1 个攻击指示物；可将 1 张手牌放牌库底，再获得 1 个攻击指示物
			if await _ask_confirm("尼达维利尔：获得 1 个攻击指示物？（可再将 1 张手牌放牌库底获得第 2 个）"):
				state["heroes"][hid]["tokens"]["attack"] += 1
				_log("%s 获得 1 攻击指示物（尼达维利尔）" % DB.hero_name(hid), Color(0.9, 0.9, 0.5))
				if state["heroes"][hid]["hand"].size() > 0 and await _ask_confirm("尼达维利尔：将 1 张手牌放牌库底，再获得 1 个攻击指示物？"):
					var h5: Dictionary = state["heroes"][hid]
					var picked5: Array = await _ask_hand_cards(hid, 1, "%s：选择放回牌库底的手牌" % DB.hero_name(hid))
					if picked5.size() > 0:
						var ci5: int = int(picked5[0])
						var card5: int = h5["hand"][ci5]
						h5["hand"].remove_at(ci5)
						h5["deck"].append(card5)
						state["heroes"][hid]["tokens"]["attack"] += 1
						_log("%s 放 1 张手牌到牌库底，再获得 1 攻击指示物" % DB.hero_name(hid), Color(0.9, 0.9, 0.5))
		"place_threat_token":
			# 至圣所：回合结束，可在"任意地点的威胁卡"或"能量卡"上放置 1 个对应的指示物（目前均为英勇/威胁）。
			# 约定：优先本地点威胁（若有且可放）；本地点无威胁时，改为让英雄选择场上任意威胁卡或能量卡。
			await _sanctum_place_token(hid, loc)
		"ko_hero_clear_threat":
			# 沃米尔：KO 该地点另一个英雄，立即清除一张威胁卡
			var candidates: Array = []
			for hid2 in _heroes_at(loc):
				if hid2 != hid and not state["heroes"][hid2]["ko"]:
					candidates.append(hid2)
			if candidates.size() == 0:
				Events.emit_toast("沃米尔：本地点没有其他英雄可牺牲")
			elif await _ask_confirm("沃米尔：KO 本地点另一个英雄以清除一张威胁卡？"):
				var labels: Array = []
				for hid2 in candidates:
					labels.append(DB.hero_name(hid2))
				var picked6: int = await _ask("选择牺牲的英雄", labels)
				var victim: String = candidates[picked6]
				# 先清威胁再 KO（避免 KO 触发 BAM 时威胁已清）
				# 背面朝上的威胁卡（神秘客）不可选：未翻开前不可交互，也不显示卡名（防剧透）
				var threat_locs: Array = []
				for i2 in range(LOCATION_COUNT):
					var t2: Variant = state["locations"][i2]["threat"]
					if t2 != null and not t2.get("_face_down", false):
						threat_locs.append(i2)
				if threat_locs.size() > 0:
					var names6: Array = []
					for i2 in threat_locs:
						names6.append("%s（%s）" % [_loc_name(i2), state["locations"][i2]["threat"]["name"]])
					var pick6: int = await _ask("选择要清除的威胁卡", names6)
					_clear_threat(threat_locs[pick6])
				# 牺牲英雄的整手牌在 _ko_hero 中统一弃置到牌库底
				await _ko_hero(victim)
				_log("沃米尔：%s 牺牲，清除了一张威胁卡" % DB.hero_name(victim), Color(1, 0.6, 0.4))
		"discard_token_draw":
			# 纽约：弃置 1 个行动指示物，然后抽 1 张牌
			var tok_pool: Dictionary = state["shield_tokens"] if state["mode"] == "shield" else state["heroes"][hid]["tokens"]
			var has_any: bool = int(tok_pool["move"]) + int(tok_pool["attack"]) + int(tok_pool["heroic"]) + int(tok_pool["wild"]) > 0
			if has_any and await _ask_confirm("纽约：弃置 1 个行动指示物，抽取 1 张牌？"):
				var tk_names: Array = ["移动", "攻击", "英勇", "万能"]
				var tk_keys2: Array = ["move", "attack", "heroic", "wild"]
				var avail: Array = []
				for ti in range(4):
					if int(tok_pool[tk_keys2[ti]]) > 0:
						avail.append(ti)
				var tk_labels: Array = []
				for a in avail:
					tk_labels.append(tk_names[a])
				var tk_choice: int = await _ask("选择弃置的指示物", tk_labels)
				tok_pool[tk_keys2[avail[int(tk_choice)]]] -= 1
				_draw_card(hid)
				_log("%s 弃 1 个行动指示物并抽 1 张牌（纽约）" % DB.hero_name(hid), Color(0.8, 0.9, 1))
		"move_villain_here":
			# 泰坦星：移动灭霸到该地点
			if await _ask_confirm("泰坦星：移动灭霸到该地点？"):
				state["villain_pos"] = loc
				_log("泰坦星：灭霸移动到 %s" % _loc_name(loc), Color(0.9, 0.7, 1))
		"swap_story_2":
			# 量子隧道：交换故事情节中任意 2 张英雄卡的位置
			var hero_story: Array = []
			for i2 in range(state["story"].size()):
				if state["story"][i2]["type"] == "hero":
					hero_story.append(i2)
			if hero_story.size() >= 2 and await _ask_confirm("量子隧道：交换故事情节中任意 2 张英雄卡的位置？"):
				var names7: Array = []
				for i2 in hero_story:
					var e7: Dictionary = state["story"][i2]
					names7.append("%s：%s" % [DB.hero_name(e7["hero"]), _card_desc(e7["hero"], e7["idx"])])
				var c1: int = await _ask("选择第 1 张英雄卡", names7)
				var c2: int = await _ask("选择第 2 张英雄卡", names7)
				var a7: int = hero_story[int(c1)]
				var b7: int = hero_story[int(c2)]
				var tmp7: Dictionary = state["story"][a7]
				state["story"][a7] = state["story"][b7]
				state["story"][b7] = tmp7
				_log("量子隧道：交换了故事情节中的 2 张英雄卡", Color(0.8, 0.9, 1))
		"discard_bottom_gain_attack2":
			# 灭霸宫殿：1 张手牌放牌库底，获得 2 个攻击指示物
			var h7: Dictionary = state["heroes"][hid]
			if h7["hand"].size() > 0 and await _ask_confirm("灭霸宫殿：将 1 张手牌放牌库底，获得 2 个攻击指示物？"):
				var picked7: Array = await _ask_hand_cards(hid, 1, "%s：选择放回牌库底的手牌" % DB.hero_name(hid))
				if picked7.size() > 0:
					var ci7: int = int(picked7[0])
					var card7: int = h7["hand"][ci7]
					h7["hand"].remove_at(ci7)
					h7["deck"].append(card7)
					state["heroes"][hid]["tokens"]["attack"] += 2
					_log("%s 获得 2 攻击指示物（灭霸宫殿）" % DB.hero_name(hid), Color(0.9, 0.9, 0.5))
		"give_energy_token":
			# 瓦坎达原野：该地点任意 1 名英雄获得 1 个能量指示物（暂作为万能指示物，战役能量卡机制另行实现）
			var heroes_here: Array = []
			for hid2 in _heroes_at(loc):
				if not state["heroes"][hid2]["ko"]:
					heroes_here.append(hid2)
			if heroes_here.size() > 0 and await _ask_confirm("瓦坎达原野：让该地点任意 1 名英雄获得 1 个能量指示物？"):
				var labels8: Array = []
				for hid2 in heroes_here:
					labels8.append(DB.hero_name(hid2))
				var pick8: int = await _ask("选择获得能量指示物的英雄", labels8)
				state["heroes"][heroes_here[pick8]]["tokens"]["wild"] += 1
				_log("%s 获得 1 个能量指示物（瓦坎达原野，暂作万能指示物）" % DB.hero_name(heroes_here[pick8]), Color(0.9, 0.9, 0.5))
		"klin_discard_threat_token":
			# 克林监狱：弃 1 张手牌到牌库底，然后在场上任意一张威胁卡上放置对应的行动指示物。
			# 若场上没有可放置指示物的威胁卡，则不触发此效果。
			var klin_opt: Array = []
			for i2 in range(LOCATION_COUNT):
				var lth2: Variant = state["locations"][i2]["threat"]
				# 只收集"可放置指示物"的威胁卡（排除爪牙型 hp>0）
				if lth2 != null and _threat_placeable_sym(lth2) != "":
					klin_opt.append(i2)
			if klin_opt.is_empty():
				_log("克林监狱：场上没有可放置指示物的威胁卡，效果不触发", Color(0.8, 0.9, 0.9))
			else:
				var kh: Dictionary = state["heroes"][hid]
				if kh["hand"].size() > 0 and await _ask_confirm("克林监狱：弃 1 张手牌到牌库底，并在场上任一威胁卡上放指示物？"):
					var picked_k: Array = await _ask_hand_cards(hid, 1, "%s：选择放回牌库底的手牌" % DB.hero_name(hid))
					if picked_k.size() > 0:
						var cik: int = int(picked_k[0])
						var cardk: int = kh["hand"][cik]
						kh["hand"].remove_at(cik)
						kh["deck"].append(cardk)
					var names_th: Array = []
					for i2 in klin_opt:
						names_th.append("%s（%s）" % [_loc_name(i2), state["locations"][i2]["threat"]["name"]])
					var pick_th: int = await _ask("克林监狱：选择放置指示物的威胁卡", names_th)
					var t_loc: int = klin_opt[wrapi(int(pick_th), 0, klin_opt.size())]
					var t_sym: String = _threat_placeable_sym(state["locations"][t_loc]["threat"])
					if t_sym != "":
						_place_threat_token(hid, t_loc, t_sym, "克林监狱")
		"discard_token_choose2":
			# 虚无之地：弃 1 个行动指示物，然后从移动/攻击/英勇指示物中选择两个（任意组合）
			var tp2: Dictionary = state["shield_tokens"] if state["mode"] == "shield" else state["heroes"][hid]["tokens"]
			if int(tp2["move"]) + int(tp2["attack"]) + int(tp2["heroic"]) + int(tp2["wild"]) > 0 and await _ask_confirm("虚无之地：弃 1 个行动指示物，选 2 个指示物？"):
				var dnames: Array = ["移动", "攻击", "英勇", "万能"]
				var dkeys2: Array = ["move", "attack", "heroic", "wild"]
				var d_avail: Array = []
				for ti in range(4):
					if int(tp2[dkeys2[ti]]) > 0:
						d_avail.append(ti)
				var dlabels: Array = []
				for a in d_avail:
					dlabels.append(dnames[a])
				var dc: int = await _ask("虚无之地：选择弃置的指示物", dlabels)
				tp2[dkeys2[d_avail[int(dc)]]] -= 1
				# 选 2 个（移动/攻击/英勇，可重复）
				var chosen: Array = ["move", "attack", "heroic"]
				for ci in range(2):
					var cnames: Array = ["移动", "攻击", "英勇", "❌ 结束"]
					var ckeys: Array = ["move", "attack", "heroic", "end"]
					var cc: int = await _ask("虚无之地：选第 %d 个指示物" % (ci + 1), cnames)
					if ckeys[wrapi(int(cc), 0, ckeys.size())] == "end":
						break
					var ck: String = ckeys[wrapi(int(cc), 0, ckeys.size())]
					state["heroes"][hid]["tokens"][ck] += 1
		"gain_move_1":
			# 奥斯本大厦：获得 1 个移动指示物
			state["heroes"][hid]["tokens"]["move"] += 1
			_log("%s 获得 1 移动指示物（奥斯本大厦）" % DB.hero_name(hid), Color(0.9, 0.9, 0.5))
		"gain_attack_1":
			# 奥斯本实验室：获得 1 个攻击指示物
			state["heroes"][hid]["tokens"]["attack"] += 1
			_log("%s 获得 1 攻击指示物（奥斯本实验室）" % DB.hero_name(hid), Color(0.9, 0.9, 0.5))
		"gain_heroic_1":
			# 中城高中：获得 1 个英勇指示物
			state["heroes"][hid]["tokens"]["heroic"] += 1
			_log("%s 获得 1 英勇指示物（中城高中）" % DB.hero_name(hid), Color(0.9, 0.9, 0.5))
		"add_civ_rescue":
			# 布鲁克林大桥：在任意地点添加 1 个平民（包括该地点），然后在该地点营救 1 个平民
			if await _ask_confirm("布鲁克林大桥：在任意地点添加 1 个平民，然后营救 1 个平民？"):
				var ac_names: Array = []
				for i2 in range(LOCATION_COUNT):
					if state["locations"][i2].get("destroyed", false):
						continue
					ac_names.append(_loc_name(i2))
				var ac: int = await _ask("布鲁克林大桥：选择添加平民的地点", ac_names)
				var ac_loc: int = wrapi(int(ac), 0, LOCATION_COUNT)
				await _place_token_at("civ", ac_loc, 1)
				_rescue_civ(hid, ac_loc)
				_log("%s 在 %s 添加并营救 1 个平民（布鲁克林大桥）" % [DB.hero_name(hid), _loc_name(ac_loc)], Color(0.8, 0.9, 1))
		"peek_villain_deck":
			# 号角日报：查看主计划牌堆顶的牌，然后可放置到牌堆底（与黑寡妇"审讯"同机制，复用底层 code + 卡牌图标）
			if state["master_deck"].size() > 0:
				var view_idx: int = _next_villain_action_from_top()
				if view_idx >= 0:
					var ok: bool = await _ask_villain_card(view_idx, "号角日报：查看主计划牌堆顶。是否放到牌组底部？")
					if ok:
						_state_move_card_to_bottom(view_idx)
						_log("号角日报：将顶牌放到牌组底部", Color(0.7, 0.9, 1))
					else:
						_log("号角日报：顶牌保持原位", Color(0.7, 0.9, 1))
				else:
					_log("号角日报：主计划牌堆已没有可查看的行动牌", Color(0.7, 0.8, 0.9))

## 中央公园：分批次移动指示物（最多 2 批；每批：玩家选 1 个指示物（平民/暴徒任意组合）
## → 选 1 个任意有空位的地点），可提前结束
func _move_tokens_from(loc: int) -> void:
	var l: Dictionary = state["locations"][loc]
	for batch in range(2):
		if l["civ"] + l["thug"] == 0:
			break
		# 1) 选择要移动的指示物种类（仅列出此地存在的种类；可提前结束）
		var opts: Array = []
		if l["civ"] > 0:
			opts.append("平民")
		if l["thug"] > 0:
			opts.append("暴徒")
		opts.append("不再移动")
		var kind_choice = await _ask("中央公园：选择要移动的指示物（第 %d/2 个）" % (batch + 1), opts)
		var ki := int(kind_choice)
		if ki < 0 or ki >= opts.size() - 1:
			break  # 选择"不再移动"
		var kind := "civ" if opts[ki] == "平民" else "thug"
		# 2) 选择目标地点（任意有空位的地点，不含中央公园本身）
		var dests: Array = []
		var names: Array = []
		for i in range(LOCATION_COUNT):
			if i == loc:
				continue
			var l2: Dictionary = state["locations"][i]
			if l2["civ"] + l2["thug"] < int(DB.location(l2["id"])["slots"]):
				dests.append(i)
				names.append(_loc_name(i))
		if dests.size() == 0:
			Events.emit_toast("没有其他地点有空位")
			break
		var choice = await _ask("选择放置地点", names)
		var oi := int(dests[int(choice)])
		# 3) 移动指示物
		if kind == "civ":
			l["civ"] -= 1
			state["locations"][oi]["civ"] += 1
		else:
			l["thug"] -= 1
			state["locations"][oi]["thug"] += 1
		_log("中央公园：%s → %s" % ["平民" if kind == "civ" else "暴徒", _loc_name(oi)], Color(0.8, 0.9, 1))
		Events.emit_state_changed()
	Events.emit_state_changed()

func _swap_story(hid: String) -> void:
	var shield: bool = state["mode"] == "shield"
	var hand_ref: Array = state["shield_hand"] if shield else state["heroes"][hid]["hand"]
	if hand_ref.size() == 0 or state["story"].size() == 0:
		return
	# 玩家选择要交换的手牌
	var picked: Array = await _ask_hand_cards(hid, 1, "%s：选择要交换的手牌" % DB.hero_name(hid))
	if picked.size() == 0:
		return
	var hand_idx: int = int(picked[0])
	if hand_idx < 0 or hand_idx >= hand_ref.size():
		return
	# 玩家在故事情节中选择要交换的卡牌（卡牌图标弹窗；基础模式仅限自己的卡，神盾局共享）
	var story_i: int = await _ask_story_card("%s：点击选择故事情节中要交换的卡牌" % DB.hero_name(hid), "" if shield else hid)
	if story_i < 0:
		return
	var entry: Dictionary = state["story"][story_i]
	if shield:
		var hand_card: Dictionary = state["shield_hand"][hand_idx]
		state["shield_hand"].remove_at(hand_idx)
		state["story"][story_i] = {"type": "hero", "hero": entry["hero"], "idx": hand_card["idx"]}
		state["shield_hand"].append({"hero": entry["hero"], "idx": entry["idx"]})
		_log("%s 用一张手牌与故事情节卡牌交换" % DB.hero_name(hid), Color(0.8, 0.9, 1))
		Events.emit_state_changed()
		return
	var hand_card: int = state["heroes"][hid]["hand"][hand_idx]
	state["heroes"][hid]["hand"].remove_at(hand_idx)
	state["story"][story_i] = {"type": "hero", "hero": entry["hero"], "idx": hand_card}
	state["heroes"][hid]["hand"].append(entry["idx"])
	_log("%s 用一张手牌与故事情节卡牌交换" % DB.hero_name(hid), Color(0.8, 0.9, 1))
	Events.emit_state_changed()

func _remove_crisis_effect(hid: String) -> void:
	var shield: bool = state["mode"] == "shield"
	var hand_ref: Array = state["shield_hand"] if shield else state["heroes"][hid]["hand"]
	if hand_ref.size() == 0:
		Events.emit_toast("没有手牌可弃")
		return
	# 玩家选择弃掉哪张手牌
	var picked: Array = await _ask_hand_cards(hid, 1, "%s：选择弃掉 1 张手牌（移除 1 个危机指示物）" % DB.hero_name(hid))
	if picked.size() == 0:
		return
	var idx: int = int(picked[0])
	if idx < 0 or idx >= hand_ref.size():
		return
	hand_ref.remove_at(idx)
	_log("%s 弃 1 张手牌" % DB.hero_name(hid), Color(0.9, 0.9, 0.7))
	for hid2 in state["hero_ids"]:
		if state["heroes"][hid2]["crisis"] > 0:
			state["heroes"][hid2]["crisis"] -= 1
			_log("移除 %s 的 1 个危机指示物" % DB.hero_name(hid2), Color(0.7, 0.7, 1))
			Events.emit_state_changed()
			return
	for l in state["locations"]:
		if l["crisis"] > 0:
			l["crisis"] -= 1
			_log("移除一个地点的 1 个危机指示物", Color(0.7, 0.7, 1))
			Events.emit_state_changed()
			return

# ---------------------------------------------------------------- public queries

func current_hero_id() -> String:
	if state["hero_ids"].is_empty():
		return ""
	var idx: int = clampi(state["current_hero"], 0, state["hero_ids"].size() - 1)
	return state["hero_ids"][idx]

func current_hero_state() -> Dictionary:
	return state["heroes"][current_hero_id()]

func get_state() -> Dictionary:
	return state

# ================================================================ 第一季众筹第三批（3.x）helpers

## 故事情节中"带特殊效果（effect 字段）"的英雄行动牌张数（含刚打出的这张）
## 口径（裁定6）：带 effect 字段的英雄行动牌 = 特殊效果牌
func _special_effect_cards_in_story() -> int:
	return _story_hero_effect_cards("")

## 故事情节中某个英雄自己的、指定效果前缀的牌张数（prefix 为空 = 任意带效果的牌）
func _story_hero_effect_cards(effect_prefix: String, only_hero: String = "") -> int:
	var n := 0
	for e in state.get("story", []):
		if String(e.get("type", "")) != "hero" or bool(e.get("face_down", false)):
			continue
		var hid2 := String(e.get("hero", ""))
		if only_hero != "" and hid2 != only_hero:
			continue
		var idx := int(e.get("idx", -1))
		if idx < 0 or not DB.heroes.has(hid2):
			continue
		var cards: Array = DB.hero_cards(hid2)
		if idx >= cards.size():
			continue
		var eff: Variant = (cards[idx] as Dictionary).get("effect", null)
		if eff == null:
			continue
		var et := String((eff as Dictionary).get("type", ""))
		if effect_prefix == "" or et.begins_with(effect_prefix):
			n += 1
	return n

## 故事情节中「变形」的张数（含刚打出的这张）
func _transform_count_in_story() -> int:
	return _story_hero_effect_cards("shehulk_transform_")

## 某英雄的某张效果卡是否仍在故事情节"可见区"内且正面朝上（口径同阿戈摩托之球：最后 STORY_VISIBLE 张）
func _effect_card_in_visible_story(effect_type: String, only_hero: String = "") -> bool:
	var story: Array = state.get("story", [])
	var from: int = maxi(story.size() - STORY_VISIBLE, 0)
	for i in range(from, story.size()):
		var e: Dictionary = story[i]
		if String(e.get("type", "")) != "hero" or bool(e.get("face_down", false)):
			continue
		var hid2 := String(e.get("hero", ""))
		if only_hero != "" and hid2 != only_hero:
			continue
		var idx := int(e.get("idx", -1))
		if idx < 0 or not DB.heroes.has(hid2):
			continue
		var cards: Array = DB.hero_cards(hid2)
		if idx >= cards.size():
			continue
		var eff: Variant = (cards[idx] as Dictionary).get("effect", null)
		if eff != null and String((eff as Dictionary).get("type", "")) == effect_type:
			return true
	return false

## 术士亚当·不朽：该英雄的「不朽」卡是否仍在可见区（在就保护"最后一张手牌不被弃置"）
func _immortality_active(hid: String) -> bool:
	return _effect_card_in_visible_story("adamwarlock_immortality", hid)

## 松鼠女·非常感知（裁定4）：特殊效果牌数 > 反派当前生命值 → 英雄直接获胜。
## 「持续检查」的判据 = 这张牌此刻仍在故事情节可见区正面朝上（口径同阿戈摩托之球），
## 所以打出后每次"故事情节变化 / 反派掉血"都会重查；被挤出可见区就自然失效。
## 检查点：play_card 追加故事情节之后、反派生命值减少之后、以及本效果结算时。
func _check_hyper_awareness(reason: String = "") -> void:
	if String(state.get("phase", "")) == "game_over":
		return
	if not _effect_card_in_visible_story("squirrelgirl_hyper_awareness"):
		return
	var n: int = _special_effect_cards_in_story()
	var hp: int = int(state.get("villain_hp", 0))
	if n > hp:
		_log("非常感知：故事情节中特殊效果牌 %d 张 > 反派当前生命 %d → 英雄们直接获胜！" % [n, hp], Color(0.5, 1, 0.5))
		_win()

## 只在"同一批牌的一个排列"时才接受玩家给的顺序（防止客户端乱发/重复牌）
func _validated_permutation(candidate: Array, original: Array) -> Array:
	if candidate.size() != original.size():
		return original.duplicate()
	var pool: Array = original.duplicate()
	for x in candidate:
		var hit: int = pool.find(int(x))
		if hit < 0:
			return original.duplicate()
		pool.remove_at(hit)
	return candidate.duplicate()

## 术士亚当·量子魔法（裁定2）：查看反派牌堆顶 3 张行动牌，玩家拖拽调整顺序后按原位置放回。
## 宝石卡（字典项）位置保持不动。
func _ask_quantum_magic_order(hid: String) -> void:
	var slots: Array = []
	var cards: Array = []
	for i in range(state["master_deck"].size()):
		var item: Variant = state["master_deck"][i]
		if item is Dictionary:
			continue
		slots.append(i)
		cards.append(int(item))
		if cards.size() >= 3:
			break
	if cards.size() == 0:
		_log("量子魔法：反派牌堆已空，无牌可看", Color(0.8, 0.8, 0.8))
		return
	# 没有 UI（纯逻辑测试 / 自动托管）就直接保持原顺序，不然 await 会一直挂着
	if autopilot or Events.prompt_reorder.get_connections().size() == 0:
		_log("量子魔法：无拖拽界面，保持原顺序（看牌堆顶 %d 张）" % cards.size(), Color(0.8, 0.8, 0.8))
		return
	var order: Variant = await _prompt("reorder", {
		"title": "量子魔法：查看反派牌堆顶 %d 张，拖动卡牌调整顺序后确认" % cards.size(),
		"public_title": "量子魔法：%s 正在查看反派牌堆顶 %d 张并调整顺序…" % [DB.hero_name(hid), cards.size()],
		"cards": cards, "villain": String(state["villain"]),
	}, hid)
	var new_order: Array = cards.duplicate()
	if order is Array:
		new_order = _validated_permutation(order as Array, cards)
	for k in range(mini(slots.size(), new_order.size())):
		state["master_deck"][int(slots[k])] = int(new_order[k])
	_log("量子魔法：调整了反派牌堆顶 %d 张牌的顺序" % new_order.size(), Color(0.8, 0.85, 1))
	Events.emit_state_changed()

## 把 n 次攻击分配给给定地点（每次询问打哪个地点；该地点无可打目标则自动跳过）
## 用于：星云·电机警棍、勇度·亚卡箭乱射
func _distribute_attacks(hid: String, locs_in: Array, n: int, label: String) -> void:
	var locs: Array = []
	for l in locs_in:
		if _enemy_targets_at(int(l)).size() > 0 and not locs.has(int(l)):
			locs.append(int(l))
	if locs.is_empty():
		Events.emit_toast("%s：可攻击的地点都没有敌人" % label)
		return
	for _atk in range(n):
		if state["phase"] == "game_over":
			return
		var rows: Array = []
		var live: Array = []
		for l in locs:
			if _enemy_targets_at(int(l)).size() == 0:
				continue
			live.append(int(l))
			rows.append({"icon": "attack", "arrow": "attack", "text": _loc_name(int(l)),
				"bottom": String(state["locations"][int(l)].get("image", ""))})
		if live.is_empty():
			return
		rows.append({"text": "剩余攻击放弃"})
		var pick: int = int(await _ask_action("%s：第 %d 次攻击选哪个地点" % [label, _atk + 1], rows))
		if pick < 0 or pick >= live.size():
			return
		await _attack_once_at(hid, int(live[pick]), label, 1)

## 松鼠女·夜视：揭示牌堆顶一张（公开、原位），然后可选择把它放到牌堆底
func _reveal_top_optionally_to_bottom(hid: String) -> void:
	var top: int = _next_villain_action_from_top()
	if top < 0:
		_log("夜视：反派牌堆已无行动牌", Color(0.8, 0.8, 0.8))
		return
	await _ask_villain_card(top, "夜视：这是反派牌堆顶的牌")
	var yes: bool = await _ask_confirm("夜视：要把这张牌放到反派牌堆底部吗？")
	if yes:
		_state_move_card_to_bottom(top)
		_log("夜视：把「%s」放到了反派牌堆底部" % villain_action_desc(top), Color(0.85, 0.9, 1))
	else:
		_log("夜视：保持牌堆顶不变", Color(0.8, 0.8, 0.8))
	Events.emit_state_changed()

## 星云·影像投射（裁定3）：每个英雄各自自愿把手牌与故事情节卡交换（可跳过），
## 然后移除反派牌堆顶的一张牌。
func _nebula_image_projection(hid: String) -> void:
	for who in state["hero_ids"]:
		var w := String(who)
		if state["phase"] == "game_over":
			break
		var h: Dictionary = state["heroes"][w]
		if bool(h.get("ko", false)) or (h["hand"] as Array).size() == 0:
			continue
		var want: bool = await _ask_confirm("影像投射：%s 要用手牌与故事情节中的牌交换吗？（可以跳过）" % DB.hero_name(w))
		if not want:
			continue
		var picked: Array = await _ask_hand_cards(w, 1, "影像投射：选择 %s 要换出的手牌" % DB.hero_name(w))
		if picked.is_empty():
			continue
		var story_i: int = int(await _ask_story_card("影像投射：选择要与手牌交换的故事情节卡", w))
		if story_i < 0 or story_i >= state["story"].size():
			continue
		var card_idx: int = int(picked[0])
		var entry: Dictionary = state["story"][story_i]
		if String(entry.get("type", "")) != "hero" or String(entry.get("hero", "")) != w:
			continue
		# 交换：手牌那张牌进故事情节（原位置），故事情节那张回到手牌
		h["hand"].erase(card_idx)
		h["hand"].append(int(entry.get("idx", -1)))
		entry["idx"] = card_idx
		entry["face_down"] = false
		_log("影像投射：%s 交换了一张手牌与故事情节中的一张牌" % DB.hero_name(w), Color(0.85, 0.85, 1))
	# 最后：移除反派牌堆顶的一张行动牌（移出本局）
	var rm: int = _next_villain_action_from_top()
	if rm >= 0:
		var hit := -1
		for i in range(state["master_deck"].size()):
			if state["master_deck"][i] is Dictionary:
				continue
			if int(state["master_deck"][i]) == rm:
				hit = i
				break
		if hit >= 0:
			state["master_deck"].remove_at(hit)
			_log("影像投射：移除反派牌堆顶的「%s」（本局不再出现）" % villain_action_desc(rm), Color(0.9, 0.8, 1))
	Events.emit_state_changed()
	await _maybe_auto_end_turn()

## 霍华德鸭·中子分解器：对你所在地点的一个反派/爪牙造成伤害直到其生命值剩 1；
## 之后本回合不能再使用攻击行动（清掉剩余攻击符号/指示物并上锁）
func _howard_neutron_disintegrator(hid: String) -> void:
	var loc: int = int(state["heroes"][hid]["location"])
	var tgts: Array = []
	for t in _enemy_targets_at(loc):
		var ts := String(t)
		if ts == "thug":
			continue   # 只对反派/爪牙
		tgts.append(ts)
	if tgts.is_empty():
		Events.emit_toast("你所在地点没有反派或爪牙")
		return
	var rows: Array = _enemy_target_rows(loc, tgts)
	rows.append({"text": "取消"})
	var pick: int = int(await _ask_action("中子分解器：选择目标（伤害直到其生命剩 1）", rows))
	if pick < 0 or pick >= tgts.size():
		return
	var tgt: String = String(tgts[pick])
	# 造成伤害直到剩 1 点
	_damage_enemy_to_one(loc, tgt, hid)
	# 本回合不能再使用攻击行动
	state["heroes"][hid]["attack_locked_turn"] = true
	var removed := 0
	for i in range(state["action_symbols"].size() - 1, -1, -1):
		if String(state["action_symbols"][i]) == "attack":
			state["action_symbols"].remove_at(i)
			removed += 1
	var pool: Dictionary = _hero_token_pool(hid)
	var tok: int = int(pool["attack"])
	pool["attack"] = 0
	_log("中子分解器：本回合 %s 不能再使用攻击行动（清掉符号 %d 个、攻击指示物 %d 个）" % [DB.hero_name(hid), removed, tok], Color(0.9, 0.6, 0.6))

## 对某地点的指定敌人"造成伤害直到其生命值剩余 1 点"（中子分解器用）
## 目标字符串口径：thug / henchman:<名> / villain / s6:<id>
func _damage_enemy_to_one(loc: int, tgt: String, hid: String) -> void:
	if tgt.begins_with("s6:"):
		var svid: String = String(tgt).substr(3)
		var sv: Dictionary = _s6()["vills"][svid]
		if int(sv["hp"]) > 1:
			var before: int = int(sv["hp"])
			sv["hp"] = 1
			_log("中子分解器：%s 生命值 %d → 1" % [DB.villain_name(svid), before], Color(0.9, 0.6, 0.6))
		return
	if tgt == "villain":
		if int(state["villain_hp"]) > 1:
			var b2: int = int(state["villain_hp"])
			state["villain_hp"] = 1
			_log("中子分解器：%s 生命值 %d → 1" % [DB.villain_name(state["villain"]), b2], Color(0.9, 0.6, 0.6))
		return
	if tgt.begins_with("henchman:"):
		var th: Variant = state["locations"][loc].get("threat", null)
		if th is Dictionary and int((th as Dictionary).get("hp", 1)) > 1:
			var b3: int = int((th as Dictionary)["hp"])
			(th as Dictionary)["hp"] = 1
			_log("中子分解器：%s 生命值 %d → 1" % [String((th as Dictionary).get("name", "爪牙")), b3], Color(0.9, 0.6, 0.6))

## 惊奇女士·形态发生：可将任意数量手牌与故事情节中任意数量正面朝上的自己的行动牌交换
func _msmarvel_morphogenesis(hid: String) -> void:
	var swapped := 0
	while true:
		if state["phase"] == "game_over":
			break
		var h: Dictionary = state["heroes"][hid]
		if (h["hand"] as Array).size() == 0:
			break
		if _ask_story_card_candidates(hid).is_empty():
			break
		var more: bool = await _ask_confirm("形态发生：还要再交换一张吗？（已交换 %d 张）" % swapped)
		if not more:
			break
		var picked: Array = await _ask_hand_cards(hid, 1, "形态发生：选择要换出的手牌")
		if picked.is_empty():
			break
		var story_i: int = int(await _ask_story_card("形态发生：选择要与手牌交换的故事情节卡", hid))
		if story_i < 0 or story_i >= state["story"].size():
			break
		var entry: Dictionary = state["story"][story_i]
		if String(entry.get("type", "")) != "hero" or String(entry.get("hero", "")) != hid:
			continue
		var card_idx: int = int(picked[0])
		(h["hand"] as Array).erase(card_idx)
		(h["hand"] as Array).append(int(entry.get("idx", -1)))
		entry["idx"] = card_idx
		entry["face_down"] = false
		swapped += 1
		_log("形态发生：%s 交换了第 %d 张手牌" % [DB.hero_name(hid), swapped], Color(0.9, 0.8, 1))
	_log("形态发生：共交换 %d 张手牌" % swapped, Color(0.9, 0.8, 1))
	Events.emit_state_changed()

## 故事情节中"该英雄自己的、正面朝上的"卡索引列表（形态发生用）
func _ask_story_card_candidates(hid: String) -> Array:
	var out: Array = []
	for i in range(state["story"].size()):
		var e: Dictionary = state["story"][i]
		if String(e.get("type", "")) == "hero" and String(e.get("hero", "")) == hid and not bool(e.get("face_down", false)):
			out.append(i)
	return out
