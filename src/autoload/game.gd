extends Node
## Game: 规则引擎（纯逻辑，UI 通过公开方法驱动）。
## 玩家决策通过 Events.prompt_* 信号 + await 协程完成。
## 所有状态保存在 state 字典中，支持序列化存档。

signal _answered(response)

const LOCATION_COUNT := 6
const THREAT_CLEAR_TOKENS := 3

var state: Dictionary = {}
var autopilot: bool = false   # 无 UI 时自动选择（测试用）
var pending_setup: Dictionary = {}   # Setup 界面写入，Board 读取
var pending_campaign: Dictionary = {}   # 无限战争战役跨局状态（局间保留）
var debug_full_slots: bool = false   # 调试：填满地点指示物（主菜单设置面板设置）
var peek_hands: bool = false   # 调试/便利：允许查看其他英雄手牌（非官方规则，主菜单设置面板设置）
var undo_enabled: bool = false   # 可选：允许撤回上一步行动（非官方，主菜单设置面板设置）
var _undo_snapshot: Dictionary = {}   # 撤回快照（使用行动符号前保存）

# ---------------------------------------------------------------- setup

func setup(villain_id: String, hero_ids: Array, challenge: String = "none", mode: String = "base", expansions: Array = []) -> void:
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
		"extra_villain_turn": false,
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
			"threat": null, "threat_token": true,
		})
	# 洗混威胁牌，每个地点1张
	var threats: Array = vill["threats"].duplicate()
	threats.shuffle()
	for i in range(loc_n):
		var t: Dictionary = threats[i].duplicate(true)
		t["hp"] = t.get("henchman_hp", 0)
		t["heroic_tokens"] = 0
		t["arrival_triggered"] = false
		state["locations"][i]["threat"] = t
	# 反派初始位置
	state["villain_pos"] = randi_range(0, maxi(loc_n - 1, 0))
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
			"crisis": 0, "invulnerable": false,
			"tokens": {"move": 0, "attack": 0, "heroic": 0, "wild": 0},
		}
	# 神盾局单人模式：3 英雄牌组合并成一个牌组，共享手牌；行动指示物共享给玩家
	if mode == "shield":
		state["shield_deck"] = []
		for hid in hero_ids:
			for i in range(DB.hero_cards(hid).size()):
				state["shield_deck"].append({"hero": hid, "idx": i})
		state["shield_deck"].shuffle()
		state["shield_tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
	# 英雄起始：全部放在反派初始地点的正对面（环上距离最远的点）
	var opposite: int = (int(state["villain_pos"]) + 3) % LOCATION_COUNT
	for i in range(hero_ids.size()):
		var hid: String = hero_ids[i]
		state["heroes"][hid]["location"] = opposite
		if mode == "shield":
			continue
		for d in range(3):
			_draw_card(hid)
	# 神盾局：初始共享手牌 5 张
	if mode == "shield":
		for d in range(5):
			_draw_card(hero_ids[0])
	# 任务卡
	state["missions"] = []
	for m in DB.missions:
		state["missions"].append({"id": m["id"], "name": m["name"], "slots": m["slots"], "tokens": 0, "done": false})
	# 主计划牌组
	state["master_deck"] = []
	for i in range(vill["actions"].size()):
		state["master_deck"].append(i)
	state["master_deck"].shuffle()
	# 无限战争战役模式：初始化战役状态（首次 setup 时），并插入无限宝石
	if is_iw:
		_setup_campaign(villain_id, hero_ids, expansions)
	_log("—— 游戏设置完成 ——", Color(1, 0.8, 0.3))
	_log("反派：%s（%d 生命）｜英雄：%s" % [DB.villain_name(villain_id), state["villain_hp"], "、".join(hero_ids)])
	_log("初始指示物已按地点卡放置完毕，点击“开始游戏”进入第一个反派回合。", Color(0.8, 0.95, 0.8))
	state["phase"] = "setup"
	Events.emit_state_changed()

## 无限战争战役：初始化/继续战役状态，按局数插入无限宝石到反派牌组
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
		_log("🔒 本局能量卡：%s（需完成三张任务卡后才可解锁）" % DB.energy_cards[c["hidden_energy"]]["name"], Color(0.9, 0.9, 0.5))
	if c.has("removed_energy"):
		_log("🔇 一张能量卡已在战役开始时被移出本战役", Color(0.7, 0.7, 0.7))

## 玩家确认初始布置后开始游戏：执行第一个反派回合（官方规则：游戏从反派回合开始）。
## 注意：setup 不再自动跑反派回合，保证开局展示的指示物数量与地点卡初始配置完全一致。
func start_game() -> void:
	if state["phase"] != "setup":
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
		var picked_idx: int = await _ask("%s：选择你要守护的地点" % DB.hero_name(hid), opts)
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

func _ring_dist(a: int, b: int) -> int:
	var d := absi(a - b)
	return mini(d, LOCATION_COUNT - d)

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

func _ask(title: String, options: Array) -> Variant:
	if autopilot:
		return 0
	_begin_wait()
	Events.prompt_choice.emit(options, title, Callable(self, "_on_answer"))
	var r: Variant = await _answered
	_end_wait()
	return r

func _ask_confirm(text: String) -> bool:
	if autopilot:
		return true
	_begin_wait()
	Events.prompt_confirm.emit(text, Callable(self, "_on_answer"))
	var r: bool = await _answered
	_end_wait()
	return r

signal _villain_card_answered(ok: bool)

## 显示一张反派行动牌（主计划牌）并要求确认（黑寡妇审讯用）
func _ask_villain_card(card_idx: int, title: String) -> bool:
	if autopilot:
		return true
	_begin_wait()
	Events.prompt_villain_card.emit(Callable(self, "_on_villain_card_answered"), title, card_idx)
	var r: bool = await _villain_card_answered
	_end_wait()
	return r

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
	_begin_wait()
	Events.prompt_hand_card.emit(Callable(self, "_on_hand_answered"), title, hid, count)
	var r: Array = await _hand_answered
	_end_wait()
	return r

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
	_begin_wait()
	Events.prompt_story_card.emit(Callable(self, "_on_story_answered"), title, filter_hero)
	var r: int = await _story_answered
	_end_wait()
	return r

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
	_begin_wait()
	Events.prompt_deck_card.emit(Callable(self, "_on_deck_answered"), title, hid)
	var r: int = await _deck_answered
	_end_wait()
	return r

func _on_deck_answered(idx: Variant) -> void:
	_deck_answered.emit(int(idx))

func _on_answer(response: Variant) -> void:
	_answered.emit(response)

signal _hero_answered(hero_id: String)

## 从可选英雄池中选一个英雄（异步）：返回 hero_id。options 为英雄 id 数组。
func _ask_hero(title: String, options: Array) -> String:
	if autopilot:
		return options[0] if options.size() > 0 else ""
	if options.size() == 0:
		return ""
	_begin_wait()
	Events.prompt_hero_pick.emit(Callable(self, "_on_hero_answered"), title, options)
	var r: String = await _hero_answered
	_end_wait()
	return r

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
		return raw.duplicate()
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

func _deal_damage_to_hero(hid: String, amount: int) -> void:
	var h: Dictionary = state["heroes"][hid]
	if h["ko"]:
		return
	if h["invulnerable"]:
		_log("%s 免疫伤害（无懈可击）" % DB.hero_name(hid), Color(0.6, 0.9, 1))
		return
	# 战术支援（暗夜比邻星威胁）：该地点的英雄在受到伤害时会受到额外 1 点伤害
	var hl: int = h["location"]
	var threat_here: Variant = state["locations"][hl]["threat"]
	if threat_here != null and threat_here["name"] == "战术支援":
		amount += 1
		_log("战术支援：%s 受到的伤害 +1" % DB.hero_name(hid), Color(1, 0.6, 0.4))
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
			for i in range(picked.size() - 1, -1, -1):
				var idx: int = int(picked[i])
				if idx >= 0 and idx < hand_ref.size():
					dropped.append(hand_ref[idx])
					hand_ref.remove_at(idx)
		# 受伤弃掉的牌回到该英雄牌库底（官方规则；神盾局模式回共享牌库底）
		for c in dropped:
			if state["mode"] == "shield":
				state["shield_deck"].append(c)
			else:
				h["deck"].append(c)
		_log("%s 受到 %d 点伤害，弃 %d 张手牌到牌库底" % [DB.hero_name(hid), amount, dropped.size()], Color(1, 0.6, 0.6))
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
		_log("💥 %s 被击倒（KO）！黑矮星不触发 BAM，改为打出另一张行动牌！" % DB.hero_name(hid), Color(1, 0.5, 0.2))
		state["extra_villain_card"] += 1
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
		"crisis": 0, "invulnerable": false,
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
	# 官方规则：复活抽牌直到手牌 3 张，回合开始再抽 1 张（共 4 张）
	for d in range(3):
		_draw_card(hid)
	_log("%s 复活！抽 3 张手牌（回合开始再抽 1 张，共 4 张）" % DB.hero_name(hid), Color(0.6, 1, 0.8))
	Events.emit_state_changed()

# ---------------------------------------------------------------- villain turn

func _run_villain_turn() -> void:
	if state["phase"] == "game_over":
		return
	state["phase"] = "villain"
	state["turn_count"] += 1
	state["cull_armor_used"] = false
	state["proxima_parry_used"] = false
	_log("—— 反派回合 #%d ——" % state["turn_count"], Color(1, 0.5, 0.5))
	var pending: int = state.get("extra_villain_card", 0) + 1
	state["extra_villain_card"] = 0
	var guard := 0
	while pending > 0:
		if state["phase"] == "game_over":
			return
		pending -= 1
		# 反派要抽牌：主计划牌堆抽空 → 英雄失败（反派完成邪恶计划）
		if state["master_deck"].size() == 0:
			_lose("反派行动牌组已抽空，英雄们失败了。")
			return
		var drawn: Variant = state["master_deck"].pop_front()
		# 无限宝石卡：翻出即算一个回合（等同行动牌，不额外补抽行动卡）
		if drawn is Dictionary and drawn.has("stone"):
			var sidx: int = int(drawn["stone"])
			await _reveal_stone(sidx)
			guard += 1
			if guard > 30:
				_log("额外行动卡超出保护上限，停止", Color(1, 0.5, 0.5))
				break
			continue
		var card_idx: int = drawn
		state["master_discard"].append(card_idx)
		var vill: Dictionary = DB.villain(state["villain"])
		var card: Dictionary = vill["actions"][card_idx]
		state["story"].append({"type": "villain", "villain": state["villain"], "idx": card_idx, "move": card.get("move", 0)})
		var parts: Array = ["移动%d" % card.get("move", 0)]
		if card.get("bam", false): parts.append("BAM")
		if card.get("effect", null) != null: parts.append(card["effect"]["name"])
		_log("反派行动牌：%s" % " - ".join(parts), Color(1, 0.7, 0.7))
		# 1. 移动
		var mv: int = card.get("move", 0)
		if mv > 0:
			state["villain_pos"] = (state["villain_pos"] + mv) % LOCATION_COUNT
			_log("反派移动到：%s" % _loc_name(state["villain_pos"]), Color(0.9, 0.7, 1))
		# 立即刷新：先展示移动（动画/位置），之后才结算 BAM 的伤害（修复"先弃牌后移动"）
		Events.emit_state_changed()
		# 3. BAM
		if card.get("bam", false):
			await _trigger_panel_bam()
			await _trigger_all_threat_bam()
			Events.emit_state_changed()
		# 4. 特殊效果（在放置之前执行）
		if card.get("effect", null) != null:
			await _resolve_villain_effect(card["effect"])
			Events.emit_state_changed()
		# 5. 放置指示物
		if card.get("place", null) != null:
			await _do_placement(card["place"])
			Events.emit_state_changed()
		if _check_lose():
			return
		# 结算过程中可能又加入了额外行动卡（天才智力/劝诱/黑矮星KO/灭霸威胁乌木侯）
		pending += state.get("extra_villain_card", 0)
		state["extra_villain_card"] = 0
		if pending > 0:
			_log("立即打出额外反派行动卡（剩余 %d 张）" % pending, Color(1, 0.6, 0.5))
		guard += 1
		if guard > 30:
			_log("额外行动卡超出保护上限，停止", Color(1, 0.5, 0.5))
			break
	if _check_lose():
		return
	# 反派回合结束：只有反派"到达效果"威胁仍在反派最终停留地点，才结算到达效果
	# （若本回合中反派已离开该地点，则不再触发；避免与 BAM 伤害叠加导致重复弃牌）
	await _trigger_threat_arrival(state["villain_pos"])
	# 到达效果可能要求"反派回合结束后再进行一次反派回合"（如乌木侯劝诱-无英雄）
	if state.get("extra_villain_turn", false) and state["phase"] != "game_over":
		state["extra_villain_turn"] = false
		_log("—— 劝诱：乌木侯再进行一次反派回合 ——", Color(1, 0.6, 0.5))
		await _run_villain_turn()
		return
	# 到达效果也可能在到达时才加入"立即打出另一张反派行动卡"（如灭霸威胁卡 乌木侯到达：额外打出一张）
	# 此时反派回合的主循环已结束，需再执行一次反派回合才能真正"打出并结算"这张行动牌
	if state.get("extra_villain_card", 0) > 0 and state["phase"] != "game_over":
		_log("到达效果：立即再打出反派行动卡（视为灭霸再进行一个回合）", Color(1, 0.6, 0.5))
		await _run_villain_turn()
		return
	Events.emit_state_changed()
	_start_hero_phase()

func _trigger_panel_bam() -> void:
	var vill: Dictionary = DB.villain(state["villain"])
	_log("BAM！%s：%s" % [DB.villain_name(state["villain"]), vill["bam"]], Color(1, 0.6, 0.3))
	# 反派专属 BAM 特效交给 VillainRules 处理（基础规则与反派规则分离）
	await VillainRules.on_bam(self, state["villain"])

func _trigger_all_threat_bam() -> void:
	for i in range(LOCATION_COUNT):
		var l: Dictionary = state["locations"][i]
		if l["threat"] == null or not l["threat"].get("bam", false):
			continue
		var t: Dictionary = l["threat"]
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
			"冰霜巨人":
				# 洛基威胁 BAM：对该地点的所有英雄都造成 1 点伤害
				for hid in _heroes_at(i):
					await _deal_damage_to_hero(hid, 1)

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
			var targets: Array = [loc, (loc + LOCATION_COUNT - 1) % LOCATION_COUNT, (loc + 1) % LOCATION_COUNT]
			for hid in state["hero_ids"]:
				var hl: int = state["heroes"][hid]["location"]
				if targets.has(hl):
					await _deal_damage_to_hero(hid, 1)
		"武器走私":
			# 到达地点效果：若该地点有空位（民+暴 < 槽位），放 1 个危机指示物；
			# 若全满，则将最左边的平民/暴徒替换为危机指示物。
			var slots: int = int(DB.location(l["id"])["slots"])
			if l["civ"] + l["thug"] < slots:
				l["crisis"] += 1
				_log("武器走私：%s 在空位放置 1 个危机指示物（危机 %d）" % [_loc_name(loc), l["crisis"]], Color(0.8, 0.6, 1))
			else:
				VillainRules._km_replace_leftmost(self, loc)

func _do_placement(place: Array) -> void:
	var vpos: int = state["villain_pos"]
	var slots: Array = [place[0], place[1], place[2]]
	var slot_locs: Array = [(vpos + LOCATION_COUNT - 1) % LOCATION_COUNT, vpos, (vpos + 1) % LOCATION_COUNT]
	for s in range(3):
		for t in slots[s]:
			await _place_token_at(t, slot_locs[s], 1)

func _place_token_at(kind: String, loc: int, count: int) -> void:
	for c in range(count):
		var l: Dictionary = state["locations"][loc]
		var slots_total: int = int(DB.location(l["id"])["slots"])
		# 基尔格蒙：危机指示物占槽位（相当于占据民/暴槽位，使可用槽位-1）；其他反派危机不占槽
		var occupied: int = l["civ"] + l["thug"] + (l["crisis"] if state["villain"] == "kilmonger" else 0)
		if occupied < slots_total:
			if kind == "thug": l["thug"] += 1
			else: l["civ"] += 1
			_log("在 %s 放置 1 个%s" % [_loc_name(loc), "暴徒" if kind == "thug" else "平民"], Color(0.9, 0.9, 0.9))
		else:
			# 濒危地点模式：反派在这位玩家守护的地点溢出时，该玩家英雄受 1 点伤害（常规溢出也触发）
			if state["challenge"] == "endangered" and state.get("endangered", {}).size() > 0:
				for hid in state["hero_ids"]:
					if state["endangered"].get(hid, -1) == loc:
						_log("🏠 濒危地点！%s 守护的地点被撑爆，受到 1 点伤害" % DB.hero_name(hid), Color(1, 0.5, 0.5))
						await _deal_damage_to_hero(hid, 1)
			await _overflow_token(kind, loc)

func _overflow_token(kind: String, loc: int) -> void:
	# 反派专属溢出处理交给 VillainRules（基础规则与反派规则分离）
	await VillainRules.on_overflow(self, state["villain"], kind, loc)

func _resolve_villain_effect(eff: Dictionary) -> void:
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
	# 每回合重置英雄效果临时旗标
	state["gamora_fury"] = false
	state["token_double"] = false
	if state["mode"] == "shield":
		# 神盾局单人：每回合抽 1 张到共享手牌，然后打出任意一张（该英雄行动）
		state["phase"] = "hero_draw"
		if state["shield_deck"].size() == 0 and state["shield_hand"].size() == 0:
			_lose("共享牌组已抽空，英雄们失败了。")
			return
		_log("—— 神盾局回合：抽 1 张，打出任意一张 ——", Color(0.6, 0.9, 1))
		_draw_card(state["hero_ids"][0])
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
	if h["hand"].size() == 0 and h["deck"].size() == 0 and h["discard"].size() == 0:
		_lose("%s 回合开始无手牌无牌库，英雄们失败了。" % DB.hero_name(hid))
		return
	_log("—— %s 的回合 ——" % DB.hero_name(hid), Color(0.6, 0.9, 1))
	_draw_card(hid)
	state["iw_space_ignored"] = false
	var l: Dictionary = state["locations"][h["location"]]
	var virus := false
	# 折磨摧残（乌木侯威胁）：在此地点开始回合的英雄不会从故事情节中的前一张英雄卡中获得行动
	state["no_prev_symbols"] = false
	if l["threat"] != null and l["threat"].get("start_turn", false):
		state["no_prev_symbols"] = true
		_log("折磨摧残：%s 本回合不会获得上一张英雄卡的符号" % DB.hero_name(hid), Color(1, 0.8, 0.4))
	if l["threat"] != null and l["threat"].get("start_turn", false) and l["threat"]["name"] != "折磨摧残":
		virus = true
		_log("奥创病毒：%s 必须选择一个行动符号并忽略它" % DB.hero_name(hid), Color(1, 0.8, 0.4))
	if l["threat"] != null and l["threat"]["name"] == "九头蛇特工鲍勃":
		h["crisis"] += 1
		_log("%s 获得 1 危机指示物（鲍勃）" % DB.hero_name(hid), Color(0.7, 0.7, 1))
	# 乌木侯特殊规则：拥有任何危机指示物的英雄必须在回合中改为随机打出英雄卡，然后丢弃 1 个危机指示物
	# 心灵宝石（决战）：从现在开始英雄们随机打出卡牌
	state["random_play"] = (state["villain"] == "ebony" and h["crisis"] > 0) or state.get("iw_mind_active", false)
	if state["random_play"]:
		if state.get("iw_mind_active", false):
			_log("心灵宝石：%s 本回合随机打出卡牌" % DB.hero_name(hid), Color(1, 0.7, 0.9))
		else:
			_log("乌木侯：%s 拥有危机指示物，本回合将随机打出英雄卡，并丢弃 1 个危机指示物" % DB.hero_name(hid), Color(1, 0.7, 0.5))
	state["virus_ignore"] = virus
	state["phase"] = "hero_play"
	Events.emit_state_changed()

## 打出一张手牌（hand_idx 为手牌下标；神盾局模式为共享手牌下标）
func play_card(hand_idx: int) -> void:
	if state["phase"] != "hero_play":
		return
	var hid: String = state["hero_ids"][state["current_hero"]]
	var h: Dictionary = state["heroes"][hid]
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
		# 通用"随机出牌"（如乌木侯控制）：忽略点击下标，随机选一张打出
		if state.get("random_play", false):
			card_idx = _pick_random_hand_card(hid, true)
		else:
			card_idx = h["hand"][hand_idx]
			h["hand"].remove_at(hand_idx)
			h["discard"].append(card_idx)
	state["story"].append({"type": "hero", "hero": hid, "idx": card_idx})
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
	state["effect_available"] = cards[card_idx].has("effect")
	state["effect_used"] = false
	state["played_effect"] = cards[card_idx].get("effect", null)
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

func _last_hero_card_symbols() -> Array:
	for i in range(state["story"].size() - 2, -1, -1):
		var entry: Dictionary = state["story"][i]
		if entry["type"] == "hero":
			# 面朝下的英雄行动牌不给行动（下一名英雄无法获得其符号）
			if entry.get("face_down", false):
				continue
			return DB.hero_cards(entry["hero"])[entry["idx"]]["symbols"].duplicate()
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
		var choice = await _ask("万能行动：选择用途", ["移动", "攻击", "英勇"])
		var ci := int(choice)
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
		match base:
			"move":
				_execute_move(hid, "wild_token" if is_token else "wild_symbol")
			"attack":
				_execute_attack(hid, "wild_token" if is_token else "wild_symbol")
			"heroic":
				_execute_heroic(hid, "wild_token" if is_token else "wild_symbol")
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
	match base:
		"move":
			_execute_move(hid, "token" if is_token else "symbol")
		"attack":
			_execute_attack(hid, "token" if is_token else "symbol")
		"heroic":
			_execute_heroic(hid, "token" if is_token else "symbol")
	# 卡魔拉·斩击：每用一次万能/攻击符号 → 额外 +1 攻击（效果获得的攻击不再触发）
	if state.get("gamora_fury", false) and base == "attack":
		state["action_symbols"].append("attack")
		_log("卡魔拉·斩击：获得 1 个额外攻击行动", Color(1, 0.5, 0.5))
	# 火箭·天才技师（用1当2）：使用行动指示物时，额外 +1 对应符号
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
	var pick: int = await _ask("使用 %s 行动：" % DB.symbol_name(base), options)
	if pick < 0 or pick >= keys.size():
		return "back"
	if keys[pick] == "use":
		return "use"
	if keys[pick] == "返回":
		return "back"
	var eidx: int = int(keys[pick].substr(1))
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
	var entangle := false
	if l["threat"] != null and l["threat"]["name"] == "纠缠陷阱":
		entangle = true
	if entangle:
		# 纠缠陷阱：离开该地点需要消耗 2 个移动行动（本次 1 个 + 再补 1 个）
		var remaining: int = state["action_symbols"].count("move")
		var pool: Dictionary = state["shield_tokens"] if state["mode"] == "shield" else h["tokens"]
		var tok_avail: int = pool["move"]
		if remaining + tok_avail < 1:
			Events.emit_toast("纠缠陷阱：离开需要 2 个移动行动（不足），已返还本次移动")
			_refund_symbol(hid, "move", consumed)
			return
		var idx: int = state["action_symbols"].find("move")
		if idx != -1:
			state["action_symbols"].remove_at(idx)
		else:
			pool["move"] -= 1
		_log("%s 消耗 2 个移动行动脱离纠缠陷阱" % DB.hero_name(hid), Color(0.9, 0.8, 0.5))
	var opts: Array = [loc - 1, loc + 1]
	var names: Array = []
	for o in opts:
		names.append(_loc_name(wrapi(o, 0, LOCATION_COUNT)))
	names.append("跳过行动")
	if not entangle:
		names.append("返回")  # 纠缠场景涉及额外消耗，不提供返回
	var choice = await _ask("选择移动目的地", names)
	var ci := int(choice)
	if ci >= opts.size():
		if not entangle and ci == names.size() - 1:
			# 返回：归还本次消耗的移动行动，重新选择行动
			_refund_symbol(hid, "move", consumed)
			_log("%s 返回（移动行动已归还）" % DB.hero_name(hid), Color(0.8, 0.8, 0.8))
			Events.emit_state_changed()
			return
		# 跳过：放弃该行动，移动数量减一（不归还）
		_log("%s 跳过移动行动" % DB.hero_name(hid), Color(0.8, 0.8, 0.8))
		Events.emit_state_changed()
		return
	var oi := wrapi(int(opts[ci]), 0, LOCATION_COUNT)
	state["heroes"][hid]["location"] = oi
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
		_:
			state["action_symbols"].append(base)

# ---- attack

func _execute_attack(hid: String, consumed: String) -> void:
	var h: Dictionary = state["heroes"][hid]
	var loc: int = h["location"]
	var l: Dictionary = state["locations"][loc]
	var targets: Array = []
	if l["thug"] > 0:
		targets.append("thug")
	if l["threat"] != null and l["threat"]["hp"] > 0:
		targets.append("henchman:" + l["threat"]["name"])
	var vill_attackable: bool = state["missions_completed"] >= 2 and state["villain_pos"] == loc and state["villain_hp"] > 0
	if vill_attackable:
		var blocked: bool = state["villain"] == "taskmaster" and l["crisis"] > 0
		if not blocked:
			targets.append("villain")
	# 危机清除选项（无平民暴徒时）
	var crisis_option := false
	if state["villain"] == "taskmaster" and l["civ"] == 0 and l["thug"] == 0 and l["crisis"] > 0:
		crisis_option = true
	if targets.size() == 0 and not crisis_option:
		Events.emit_toast("此地没有可攻击的目标")
		return
	var names: Array = []
	for t in targets:
		names.append(_target_name(t))
	if crisis_option:
		names.append("清除 1 个危机指示物")
	names.append("跳过行动")
	names.append("返回")
	var choice = await _ask("选择攻击目标", names)
	var ci := int(choice)
	if ci >= names.size() - 2:
		if ci == names.size() - 1:
			# 返回：归还本次消耗的攻击行动，重新选择行动
			_refund_symbol(hid, "attack", consumed)
			_log("%s 返回（攻击行动已归还）" % DB.hero_name(hid), Color(0.8, 0.8, 0.8))
			Events.emit_state_changed()
			return
		# 跳过：放弃该行动，攻击数量减一（不归还）
		_log("%s 跳过攻击行动" % DB.hero_name(hid), Color(0.8, 0.8, 0.8))
		Events.emit_state_changed()
		return
	if crisis_option and ci >= targets.size():
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
			if tgt.begins_with("henchman:"):
				l["threat"]["hp"] -= 1
				_log("%s 攻击爪牙 %s（剩余 %d 生命）" % [DB.hero_name(hid), l["threat"]["name"], l["threat"]["hp"]], Color(1, 0.7, 0.4))
				if l["threat"]["hp"] <= 0:
					_clear_threat(loc)
			elif tgt == "villain":
				# 武学大师（暗夜比邻星威胁）：忽略每个回合对她的第一个攻击行动
				if state["villain"] == "proxima" and not state.get("proxima_parry_used", false) and _threat_present("武学大师"):
					state["proxima_parry_used"] = true
					_log("武学大师：暗夜比邻星格挡了本回合第一个攻击行动（无效）", Color(0.7, 0.7, 1))
					Events.emit_state_changed()
					return
				# 超级坚甲（黑矮星威胁）：黑矮星每回合忽略 1 点伤害
				var real_dmg := 1
				if state["villain"] == "cull" and not state.get("cull_armor_used", false) and _threat_present("超级坚甲"):
					state["cull_armor_used"] = true
					real_dmg = 0
					_log("超级坚甲：黑矮星本回合忽略 1 点伤害", Color(0.7, 0.9, 0.8))
				# 洛基-幻象威胁：只要洛基在这张威胁卡所在地点，他就不受伤害
				if state["villain"] == "loki":
					var lvpos: int = state["villain_pos"]
					var lthreat: Variant = state["locations"][lvpos]["threat"]
					if lthreat != null and lthreat["name"] == "幻象":
						real_dmg = 0
						_log("幻象：洛基在该地点不受任何伤害（攻击无效）", Color(0.7, 0.9, 0.9))
				state["villain_hp"] -= real_dmg
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
	Events.emit_state_changed()

## 在指定地点进行一次可选择目标的攻击（光子冲击/雷神之锤用；可攻击暴徒/爪牙/反派/清除危机）
## times > 1 时：玩家只选一次目标，然后对该目标连续攻击 times 次
func _attack_once_at(hid: String, loc: int, label: String, times: int = 1) -> void:
	var l: Dictionary = state["locations"][loc]
	var targets: Array = []
	if l["thug"] > 0:
		targets.append("thug")
	if l["threat"] != null and l["threat"]["hp"] > 0:
		targets.append("henchman:" + l["threat"]["name"])
	if state["missions_completed"] >= 2 and state["villain_pos"] == loc and state["villain_hp"] > 0:
		var blocked: bool = state["villain"] == "taskmaster" and l["crisis"] > 0
		if not blocked:
			targets.append("villain")
	# 模仿大师：无平民暴徒时可消耗攻击清除危机
	var crisis_option := false
	if state["villain"] == "taskmaster" and l["civ"] == 0 and l["thug"] == 0 and l["crisis"] > 0:
		crisis_option = true
	if targets.size() == 0 and not crisis_option:
		Events.emit_toast("该地点没有可攻击的目标")
		return
	var names: Array = []
	for t in targets:
		names.append(_target_name(t))
	if crisis_option:
		names.append("清除 1 个危机指示物")
	var choice = await _ask(label + "：选择攻击目标", names)
	var ci := int(choice)
	if ci >= targets.size() and crisis_option and ci < names.size():
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
	_log("消灭 %d 个暴徒（%s）" % [n, _loc_name(loc)], Color(0.9, 0.9, 0.7))
	_add_mission_token("defeat", n, hid)
	Events.emit_state_changed()

func _clear_threat(loc: int, hid: String = "") -> void:
	var l: Dictionary = state["locations"][loc]
	var t: Dictionary = l["threat"]
	_log("威胁清除：%s（%s）" % [t["name"], _loc_name(loc)], Color(0.6, 1, 0.8))
	l["threat"] = null
	l["threat_token"] = false
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

## 至圣所回合结束：在"任意地点威胁卡"或"能量卡"上放置 1 个对应指示物（目前均为英勇/威胁）。
## 本地点威胁卡可放则优先放；否则让英雄选择场上任意威胁卡或能量卡。
func _sanctum_place_token(hid: String, loc: int) -> void:
	var l: Dictionary = state["locations"][loc]
	var local_threat: Variant = l["threat"]
	# 本地点威胁卡可放（未清除、未满英勇指示物）
	if local_threat != null and int(local_threat["hp"]) == 0 and int(local_threat.get("heroic_tokens", 0)) < THREAT_CLEAR_TOKENS:
		if await _ask_confirm("至圣所：在本地威胁卡上放置 1 个英勇指示物？"):
			local_threat["heroic_tokens"] = int(local_threat.get("heroic_tokens", 0)) + 1
			_log("至圣所：%s 的威胁卡英勇指示物 %d/%d" % [local_threat["name"], local_threat["heroic_tokens"], THREAT_CLEAR_TOKENS], Color(0.7, 1, 0.9))
			if int(local_threat["heroic_tokens"]) >= THREAT_CLEAR_TOKENS:
				_clear_threat(loc)
		return
	# 本地点无威胁卡：收集可选目标（场上任意可放的威胁卡 + 能量卡），让英雄选择
	var opts: Array = []
	var targets: Array = []   # 与 opts 一一对应：{"type":"threat","loc":i} / {"type":"energy","eidx":j}
	for i in range(LOCATION_COUNT):
		var t: Variant = state["locations"][i]["threat"]
		if t != null and t["hp"] == 0 and int(t.get("heroic_tokens", 0)) < THREAT_CLEAR_TOKENS:
			opts.append("%s\n%s" % [_loc_name(i), t["name"]])
			targets.append({"type": "threat", "loc": i})
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
	var choice: int = await _ask("至圣所：选择要放置 1 个英勇指示物的目标", opts)
	var tgt: Dictionary = targets[wrapi(int(choice), 0, targets.size())]
	if tgt["type"] == "none":
		return
	if tgt["type"] == "threat":
		var thr: Variant = state["locations"][tgt["loc"]]["threat"]
		thr["heroic_tokens"] = int(thr.get("heroic_tokens", 0)) + 1
		_log("至圣所：%s 的威胁卡英勇指示物 %d/%d" % [thr["name"], thr["heroic_tokens"], THREAT_CLEAR_TOKENS], Color(0.7, 1, 0.9))
		if int(thr["heroic_tokens"]) >= THREAT_CLEAR_TOKENS:
			_clear_threat(int(tgt["loc"]))
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
	match state["missions_completed"]:
		1:
			_log("反派进入高压状态：每 2 张英雄牌触发一次反派回合", Color(1, 0.8, 0.4))
		2:
			_log("解锁攻击反派权限！", Color(1, 0.9, 0.3))
		3:
			for hh in state["hero_ids"]:
				_draw_card(hh)
			_log("所有英雄各抽 1 张牌", Color(0.7, 1, 0.9))

# ---- heroic

func _execute_heroic(hid: String, consumed: String) -> void:
	var h: Dictionary = state["heroes"][hid]
	var loc: int = h["location"]
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
	if l["civ"] > 0:
		options.append("营救平民（需%d英勇）" % rescue_cost)
	if l["threat"] != null and l["threat"]["hp"] == 0:
		options.append("放置英勇指示物清除威胁（%d/3）" % (l["threat"]["heroic_tokens"] + 1))
	if state["villain"] == "taskmaster" and l["civ"] == 0 and l["thug"] == 0 and l["crisis"] > 0:
		options.append("清除 1 个危机指示物")
	if options.size() == 0:
		Events.emit_toast("此地没有可用的英勇行动")
		return
	options.append("跳过行动")
	options.append("返回")
	var choice = await _ask("英勇行动：选择", options)
	var ci := int(choice)
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
	var picked: String = str(options[ci])
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
	elif picked.contains("危机"):
		l["crisis"] -= 1
		_log("%s 清除 1 个危机指示物（%s）" % [DB.hero_name(hid), _loc_name(loc)], Color(0.7, 0.7, 1))
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
	Events.emit_state_changed()

# ---------------------------------------------------------------- card effect

func trigger_effect() -> void:
	if state["phase"] != "hero_actions":
		return
	if not state.get("effect_available", false) or state.get("effect_used", false):
		return
	var hid: String = state["hero_ids"][state["current_hero"]]
	state["effect_used"] = true
	var eff: Dictionary = state.get("played_effect", {})
	_log("%s 发动效果：%s" % [DB.hero_name(hid), eff.get("name", "")], Color(0.9, 0.9, 0.4))
	match eff["type"]:
		"give_wild", "give_wild_x2":
			var n := 1 if eff["type"] == "give_wild" else 2
			# 神盾局单人：指示物直接给玩家共享池（无需选英雄）
			if state["mode"] == "shield":
				state["shield_tokens"]["wild"] += n
				_log("供应池 +%d 万能指示物（玩家）" % n, Color(0.9, 0.9, 0.5))
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
				var names2: Array = []
				for t in targets:
					names2.append(DB.hero_name(t))
				var ch = await _ask("选择获得万能指示物的英雄", names2)
				tid = targets[wrapi(int(ch), 0, targets.size())]
			state["heroes"][tid]["tokens"]["wild"] += n
			_log("供应池 +%d 万能指示物（给 %s）" % [n, DB.hero_name(tid)], Color(0.9, 0.9, 0.5))
		"give_attack_x2":
			# 钢铁侠：拿 2 个攻击指示物，任意分配（可给同一英雄或分给不同英雄）
			# 神盾局单人：直接给玩家共享池
			if state["mode"] == "shield":
				state["shield_tokens"]["attack"] += 2
				_log("供应池 +2 攻击指示物（玩家）", Color(0.9, 0.9, 0.5))
				return
			var targets: Array = state["hero_ids"].duplicate()
			var names2: Array = []
			for t in targets:
				names2.append(DB.hero_name(t))
			for i in range(2):
				var ch = await _ask("分配第 %d 个攻击指示物给哪个英雄？" % (i + 1), names2)
				var tid: String = targets[wrapi(int(ch), 0, targets.size())]
				state["heroes"][tid]["tokens"]["attack"] += 1
				_log("供应池 +1 攻击指示物（给 %s）" % DB.hero_name(tid), Color(0.9, 0.9, 0.5))
		"give_move_x2":
			# 钢铁侠：拿 2 个移动指示物，任意分配（可给同一英雄或分给不同英雄）
			# 神盾局单人：直接给玩家共享池
			if state["mode"] == "shield":
				state["shield_tokens"]["move"] += 2
				_log("供应池 +2 移动指示物（玩家）", Color(0.9, 0.9, 0.5))
				return
			var targets: Array = state["hero_ids"].duplicate()
			var names2: Array = []
			for t in targets:
				names2.append(DB.hero_name(t))
			for i in range(2):
				var ch = await _ask("分配第 %d 个移动指示物给哪个英雄？" % (i + 1), names2)
				var tid: String = targets[wrapi(int(ch), 0, targets.size())]
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
				var names2: Array = []
				for t in targets:
					names2.append(DB.hero_name(t))
				var ch = await _ask("少年天才：选择获得万能指示物的英雄", names2)
				tid = targets[wrapi(int(ch), 0, targets.size())]
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
			var opts: Array = [(loc + LOCATION_COUNT - 1) % LOCATION_COUNT, (loc + 1) % LOCATION_COUNT]
			var names: Array = [_loc_name(opts[0]), _loc_name(opts[1])]
			var choice = await _ask("光子冲击：选择相邻地点（2 次攻击）", names)
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
			# ② 本地点爪牙：受 1 点伤害
			if l["threat"] != null and l["threat"]["hp"] > 0:
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
			var adjl: Array = [(k_loc + LOCATION_COUNT - 1) % LOCATION_COUNT, (k_loc + 1) % LOCATION_COUNT]
			var mode_opts: Array = ["在相邻两地点各进行 1 次攻击", "在所在地点进行 2 次攻击"]
			var mode_choice: int = await _ask("科格战斗机：选择攻击方式", mode_opts)
			if int(mode_choice) == 0:
				for a_loc in adjl:
					await _attack_once_at(hid, a_loc, "科格战斗机（相邻）", 1)
			else:
				await _attack_once_at(hid, k_loc, "科格战斗机第 1 次", 1)
				await _attack_once_at(hid, k_loc, "科格战斗机第 2 次", 1)
		"war_song":
			# 女武神·战歌：移动到任意地点
			var w_opts: Array = []
			var w_names: Array = []
			for i in range(LOCATION_COUNT):
				w_opts.append(i); w_names.append(_loc_name(i))
			var w_choice: int = await _ask("战歌：移动到任意地点", w_names)
			state["heroes"][hid]["location"] = wrapi(int(w_opts[int(w_choice)]), 0, LOCATION_COUNT)
			_log("%s 移动到 %s（战歌）" % [DB.hero_name(hid), _loc_name(state["heroes"][hid]["location"])], Color(0.8, 0.9, 1))
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
			var ps_opts: Array = ["移动", "攻击", "英勇"]
			var ps_keys: Array = ["move", "attack", "heroic"]
			var ps_t: int = await _ask("问题解决者：选择要给的指示物类型", ps_opts)
			var ps_key: String = ps_keys[wrapi(int(ps_t), 0, ps_keys.size())]
			var ps_targets: Array = []
			for hh in state["hero_ids"]:
				ps_targets.append(DB.hero_name(hh))
			var ps_tgt: int = await _ask("问题解决者：选择获得指示物的英雄", ps_targets)
			var ps_hid: String = state["hero_ids"][wrapi(int(ps_tgt), 0, state["hero_ids"].size())]
			state["heroes"][ps_hid]["tokens"][ps_key] += 1
			_log("问题解决者：%s 获得 1 个%s指示物" % [DB.hero_name(ps_hid), DB.symbol_name(ps_key)], Color(0.9, 0.9, 0.5))
		"raccoon_senses":
			# 火箭·浣熊感官：获得 1 个万能指示物；或 指定任意数量你拥有的行动指示物转化为万能
			var rs_opts: Array = ["获得 1 个万能指示物", "转化你的行动指示物为万能"]
			var rs_t: int = await _ask("浣熊感官：选择其一", rs_opts)
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
			var ge_opts: Array = ["获得 1 个万能指示物", "本回合行动指示物执行两次行动"]
			var ge_t: int = await _ask("天才技师：选择其一", ge_opts)
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
			var gq_targets: Array = []
			for hh in state["hero_ids"]:
				if hh != hid:
					gq_targets.append(DB.hero_name(hh))
			if gq_targets.size() > 0:
				var gq_t: int = await _ask("我是格鲁特？：选择一名其他英雄", gq_targets)
				var gq_hid: String = state["hero_ids"][wrapi(int(gq_t), 0, state["hero_ids"].size())]
				var gq_loc: int = state["heroes"][gq_hid]["location"]
				var gq_adj: Array = [(gq_loc + LOCATION_COUNT - 1) % LOCATION_COUNT, (gq_loc + 1) % LOCATION_COUNT]
				var gq_nm: Array = [_loc_name(gq_adj[0]), _loc_name(gq_adj[1])]
				var gq_c: int = await _ask("我是格鲁特？：%s 移到相邻地点" % DB.hero_name(gq_hid), gq_nm)
				var gq_new: int = gq_adj[wrapi(int(gq_c), 0, gq_adj.size())]
				state["heroes"][gq_hid]["location"] = gq_new
				_log("格鲁特：%s 移动到 %s" % [DB.hero_name(gq_hid), _loc_name(gq_new)], Color(0.8, 0.9, 1))
		"get_groot":
			# 格鲁特·我是格鲁特！：选择一名其他英雄，你与该英雄在各自所在地点各攻击一次
			var gg_targets: Array = []
			for hh in state["hero_ids"]:
				if hh != hid:
					gg_targets.append(DB.hero_name(hh))
			if gg_targets.size() > 0:
				var gg_t: int = await _ask("我是格鲁特！：选择一名其他英雄", gg_targets)
				var gg_hid: String = state["hero_ids"][wrapi(int(gg_t), 0, state["hero_ids"].size())]
				await _attack_once_at(hid, state["heroes"][hid]["location"], "格鲁特")
				await _attack_once_at(gg_hid, state["heroes"][gg_hid]["location"], "格鲁特同伴")
		"we_are_groot":
			# 格鲁特·我们是格鲁特：选择一名其他英雄，你与其各抽一张牌
			var wg_targets: Array = []
			for hh in state["hero_ids"]:
				if hh != hid:
					wg_targets.append(DB.hero_name(hh))
			if wg_targets.size() > 0:
				var wg_t: int = await _ask("我们是格鲁特：选择一名其他英雄", wg_targets)
				var wg_hid: String = state["hero_ids"][wrapi(int(wg_t), 0, state["hero_ids"].size())]
				_draw_card(hid)
				_draw_card(wg_hid)
				_log("格鲁特：%s 与 %s 各抽 1 张牌" % [DB.hero_name(hid), DB.hero_name(wg_hid)], Color(0.8, 0.9, 1))
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
	if state["phase"] == "hero_actions":
		if state["action_symbols"].size() > 0:
			return  # 还有行动符号未用
		if _hero_has_action_tokens():
			return  # 还有行动指示物可用（玩家可继续行动）
		if state.get("effect_available", false) and not state.get("effect_used", false):
			return  # 还有卡牌效果可用，留给玩家
		state["phase"] = "hero_end"
		Events.emit_state_changed()
	await end_turn()

## 当前英雄是否还有可用的行动指示物（移动/攻击/英勇/万能）
## 神盾局模式：玩家共享指示物池
func _hero_has_action_tokens() -> bool:
	var hid: String = state["hero_ids"][state["current_hero"]]
	var t: Dictionary = state["shield_tokens"] if state["mode"] == "shield" else state["heroes"][hid]["tokens"]
	return int(t["move"]) > 0 or int(t["attack"]) > 0 or int(t["heroic"]) > 0 or int(t["wild"]) > 0

## 结束回合（异步：可能等待地点效果确认）
func end_turn() -> void:
	if state["phase"] != "hero_end":
		return
	if state.get("end_turn_busy", false):
		return  # 防止地点效果执行期间被重复触发（如再次点击结束回合）
	state["end_turn_busy"] = true
	var hid: String = state["hero_ids"][state["current_hero"]]
	var h: Dictionary = state["heroes"][hid]
	var loc: int = h["location"]
	var l: Dictionary = state["locations"][loc]
	if l["threat"] == null:
		await _resolve_location_end_effect(hid, loc)
	else:
		# 暗杀企图（基尔格蒙威胁）：在该地点结束回合的英雄受到 1 点伤害
		if l["threat"]["name"] == "暗杀企图":
			_log("暗杀企图：%s 在该地点结束回合，受到 1 点伤害" % DB.hero_name(hid), Color(1, 0.6, 0.4))
			await _deal_damage_to_hero(hid, 1)
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
	var needed := 2 if state["missions_completed"] >= 1 else 3
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
					opts.append(i)
					names.append(_loc_name(i))
				var choice = await _ask("选择移动目的地", names)
				state["heroes"][hid]["location"] = wrapi(int(opts[int(choice)]), 0, LOCATION_COUNT)
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
				var adj_opts: Array = [(hl + LOCATION_COUNT - 1) % LOCATION_COUNT, (hl + 1) % LOCATION_COUNT]
				var adj_names: Array = [_loc_name(adj_opts[0]), _loc_name(adj_opts[1])]
				var pick_adj: int = await _ask("王座大殿：%s 移到的相邻地点" % DB.hero_name(pick_hid), adj_names)
				var new_loc: int = adj_opts[wrapi(int(pick_adj), 0, adj_opts.size())]
				state["heroes"][pick_hid]["location"] = new_loc
				_log("王座大殿：%s 移动到 %s" % [DB.hero_name(pick_hid), _loc_name(new_loc)], Color(0.8, 0.9, 1))
				Events.emit_state_changed()
		"discard_2_tokens_any":
			# 阿斯加德宫殿：将任意地点以任意组合弃置 2 个平民/暴徒指示物（可选，可跳过）
			var with_tok: Array = []
			for i in range(LOCATION_COUNT):
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
			# 彩虹桥：该地点所有英雄移动到任意地点（同一目的地）
			var heroes_here: Array = _heroes_at(loc)
			if heroes_here.size() > 0:
				var any_nm: Array = []
				for i in range(LOCATION_COUNT):
					any_nm.append(_loc_name(i))
				var pick_any: int = await _ask("彩虹桥：所有英雄移到的地点", any_nm)
				var dest: int = wrapi(int(pick_any), 0, LOCATION_COUNT)
				for hh2 in heroes_here:
					state["heroes"][hh2]["location"] = dest
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
				state["heroes"][mv_hid]["location"] = loc
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
				var threat_locs: Array = []
				for i2 in range(LOCATION_COUNT):
					if state["locations"][i2]["threat"] != null:
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
