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
var debug_full_slots: bool = false   # 调试：填满地点指示物（主菜单设置面板设置）
var peek_hands: bool = false   # 调试/便利：允许查看其他英雄手牌（非官方规则，主菜单设置面板设置）
var undo_enabled: bool = false   # 可选：允许撤回上一步行动（非官方，主菜单设置面板设置）
var _undo_snapshot: Dictionary = {}   # 撤回快照（使用行动符号前保存）

# ---------------------------------------------------------------- setup

func setup(villain_id: String, hero_ids: Array, challenge: String = "none", mode: String = "base", expansions: Array = []) -> void:
	var vill: Dictionary = DB.villain(villain_id)
	# 神盾局单人模式按 3 人局血量；基础模式 1 人按 2 人血量（房规）
	var hp_key := "3" if mode == "shield" else str(maxi(hero_ids.size(), 2))
	state = {
		"villain": villain_id,
		"hero_ids": hero_ids.duplicate(),
		"player_count": hero_ids.size(),
		"challenge": challenge,
		"mode": mode,
		"shield_deck": [],
		"shield_hand": [],
		"heroes": {},
		"locations": [],
		"villain_pos": 0,
		"villain_hp": int(vill["health"][hp_key]),
		"villain_hp_max": int(vill["health"][hp_key]),
		"fear": 0,
		"story": [],
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
		"log": [],
	}
	# 地点环：按选中的扩展过滤后随机取6张
	var loc_ids: Array = []
	for id in DB.locations.keys():
		if expansions.size() == 0 or expansions.has(DB.location(id).get("expansion", "基础盒")):
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
	# 神盾局单人模式：3 英雄牌组合并成一个牌组，共享手牌
	if mode == "shield":
		state["shield_deck"] = []
		for hid in hero_ids:
			for i in range(DB.hero_cards(hid).size()):
				state["shield_deck"].append({"hero": hid, "idx": i})
		state["shield_deck"].shuffle()
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
	_log("—— 游戏设置完成 ——", Color(1, 0.8, 0.3))
	_log("反派：%s（%d 生命）｜英雄：%s" % [DB.villain_name(villain_id), state["villain_hp"], "、".join(hero_ids)])
	_log("初始指示物已按地点卡放置完毕，点击“开始游戏”进入第一个反派回合。", Color(0.8, 0.95, 0.8))
	state["phase"] = "setup"
	Events.emit_state_changed()

## 玩家确认初始布置后开始游戏：执行第一个反派回合（官方规则：游戏从反派回合开始）。
## 注意：setup 不再自动跑反派回合，保证开局展示的指示物数量与地点卡初始配置完全一致。
func start_game() -> void:
	if state["phase"] != "setup":
		return
	await _run_villain_turn()

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
	Events.prompt_story_card.emit(Callable(self, "_on_story_answered"), title)
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

# ---------------------------------------------------------------- win / lose

func _check_lose() -> bool:
	var vill: Dictionary = DB.villain(state["villain"])
	var track: String = vill.get("plot_track", "")
	if track == "fear" and state["fear"] >= vill.get("fear_track_max", 20):
		_lose("红骷髅的恐惧轨道到达 20，邪恶计划完成！")
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
	return false

func _lose(reason: String) -> void:
	state["phase"] = "game_over"
	state["lose_reason"] = reason
	_log(reason, Color(1, 0.4, 0.4))
	Events.game_over.emit(false, reason)

func _win() -> void:
	state["phase"] = "game_over"
	state["victory"] = true
	_log("反派被击败！英雄们胜利！", Color(0.5, 1, 0.5))
	Events.game_over.emit(true, "")

# ---------------------------------------------------------------- damage / KO

func _deal_damage_to_hero(hid: String, amount: int) -> void:
	var h: Dictionary = state["heroes"][hid]
	if h["ko"]:
		return
	if h["invulnerable"]:
		_log("%s 免疫伤害（无懈可击）" % DB.hero_name(hid), Color(0.6, 0.9, 1))
		return
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
	h["ko"] = true
	_log("💥 %s 被击倒（KO）！触发反派 BAM 效果！" % DB.hero_name(hid), Color(1, 0.5, 0.2))
	await _trigger_panel_bam()
	if _check_lose():
		return
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
	_log("—— 反派回合 #%d ——" % state["turn_count"], Color(1, 0.5, 0.5))
	if state["master_deck"].size() == 0:
		_lose("反派行动牌组已抽空，英雄们失败了。")
		return
	var card_idx: int = state["master_deck"].pop_front()
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
	# 2. 到达效果（移动0也结算）
	_trigger_threat_arrival(state["villain_pos"])
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
		_do_placement(card["place"])
		Events.emit_state_changed()
	if _check_lose():
		return
	Events.emit_state_changed()
	_start_hero_phase()

func _trigger_panel_bam() -> void:
	var vill: Dictionary = DB.villain(state["villain"])
	_log("BAM！%s：%s" % [DB.villain_name(state["villain"]), vill["bam"]], Color(1, 0.6, 0.3))
	var vpos: int = state["villain_pos"]
	match state["villain"]:
		"redskull":
			for hid in _heroes_at(vpos):
				await _deal_damage_to_hero(hid, 1)
			state["fear"] = mini(state["fear"] + 2, 20)
			_log("恐惧轨道 +2（当前 %d）" % state["fear"], Color(0.9, 0.6, 0.6))
		"ultron":
			_place_token_at("thug", vpos, 3)
			for hid in _heroes_at(vpos):
				await _deal_damage_to_hero(hid, 1)
		"taskmaster":
			for hid in _heroes_at(vpos):
				await _deal_damage_to_hero(hid, 1)
			state["locations"][vpos]["crisis"] += 1
			_log("%s +1 危机指示物" % _loc_name(vpos), Color(0.7, 0.7, 1))

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
					_place_token_at("thug", i, 1)
			"九头蛇夫人":
				for hid in _heroes_at(i):
					await _hero_crisis_block_damage(hid, 1, 1)
			"交叉骨":
				for hid in _heroes_at(i):
					await _hero_crisis_block_damage(hid, 2, 2)

func _hero_crisis_block_damage(hid: String, dmg: int, cost: int) -> void:
	var h: Dictionary = state["heroes"][hid]
	if h["ko"]:
		return
	if h["crisis"] >= cost:
		h["crisis"] -= cost
		_log("%s 消耗 %d 危机指示物免疫 %d 点伤害" % [DB.hero_name(hid), cost, dmg], Color(0.7, 0.9, 1))
	else:
		await _deal_damage_to_hero(hid, dmg)

func _trigger_threat_arrival(loc: int) -> void:
	var l: Dictionary = state["locations"][loc]
	if l["threat"] == null or not l["threat"].get("arrival", false):
		return
	var t: Dictionary = l["threat"]
	_log("反派抵达 %s，威胁牌触发（%s）：%s" % [_loc_name(loc), t["name"], t["text"]], Color(1, 0.8, 0.4))
	match t["name"]:
		"复制":
			_place_token_at("thug", loc, 1)
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

func _do_placement(place: Array) -> void:
	var vpos: int = state["villain_pos"]
	var slots: Array = [place[0], place[1], place[2]]
	var slot_locs: Array = [(vpos + LOCATION_COUNT - 1) % LOCATION_COUNT, vpos, (vpos + 1) % LOCATION_COUNT]
	for s in range(3):
		for t in slots[s]:
			_place_token_at(t, slot_locs[s], 1)

func _place_token_at(kind: String, loc: int, count: int) -> void:
	for c in range(count):
		var l: Dictionary = state["locations"][loc]
		var slots_total: int = int(DB.location(l["id"])["slots"])
		if l["civ"] + l["thug"] < slots_total:
			if kind == "thug": l["thug"] += 1
			else: l["civ"] += 1
			_log("在 %s 放置 1 个%s" % [_loc_name(loc), "暴徒" if kind == "thug" else "平民"], Color(0.9, 0.9, 0.9))
		else:
			_overflow_token(kind, loc)

func _overflow_token(kind: String, loc: int) -> void:
	match state["villain"]:
		"redskull":
			state["fear"] = mini(state["fear"] + 1, 20)
			_log("溢出！%s 放不下，恐惧轨道 +1（当前 %d）" % [_loc_name(loc), state["fear"]], Color(0.9, 0.5, 0.5))
		"ultron":
			var cur := loc
			for attempt in range(LOCATION_COUNT):
				cur = (cur + 1) % LOCATION_COUNT
				var l2: Dictionary = state["locations"][cur]
				var slots_total: int = int(DB.location(l2["id"])["slots"])
				if l2["civ"] + l2["thug"] < slots_total:
					if kind == "thug": l2["thug"] += 1
					else: l2["civ"] += 1
					_log("溢出！顺延到 %s 放置" % _loc_name(cur), Color(0.9, 0.9, 0.6))
					return
			_log("溢出！所有地点已满，%s 被丢弃" % ("暴徒" if kind == "thug" else "平民"), Color(0.8, 0.6, 0.6))
		"taskmaster":
			state["locations"][loc]["crisis"] += 1
			_log("溢出！改为在 %s 放置 1 危机指示物" % _loc_name(loc), Color(0.7, 0.7, 1))

func _resolve_villain_effect(eff: Dictionary) -> void:
	var etype: String = eff["type"]
	_log("反派特殊效果：%s" % eff["text"], Color(1, 0.8, 0.4))
	var vpos: int = state["villain_pos"]
	match etype:
		"redskull_emergency":
			var total := 0
			for hid in state["hero_ids"]:
				total += state["heroes"][hid]["crisis"]
			state["fear"] = mini(state["fear"] + total, 20)
			_log("英雄共有 %d 个危机指示物，恐惧轨道 +%d（当前 %d）" % [total, total, state["fear"]], Color(0.9, 0.6, 0.6))
		"hail_hydra":
			var discarded := 0
			for hid in state["hero_ids"]:
				var l: Dictionary = state["locations"][state["heroes"][hid]["location"]]
				discarded += l["civ"]
				l["civ"] = 0
				await _deal_damage_to_hero(hid, 1)
			state["fear"] = mini(state["fear"] + discarded, 20)
			_log("弃置 %d 名平民，恐惧轨道 +%d（当前 %d）" % [discarded, discarded, state["fear"]], Color(0.9, 0.6, 0.6))
		"hypnotize":
			# 奥创所在地点 + 相邻两个地点（共 3 个）：有英雄的地点英雄各 +1 危机；
			# 无英雄的地点各放置 1 个暴徒
			var targets: Array = [vpos, (vpos + LOCATION_COUNT - 1) % LOCATION_COUNT, (vpos + 1) % LOCATION_COUNT]
			for hid in state["hero_ids"]:
				if targets.has(state["heroes"][hid]["location"]):
					state["heroes"][hid]["crisis"] += 1
			_log("奥创所在地点及相邻地点的英雄各获得 1 危机指示物", Color(0.7, 0.7, 1))
			for loc in targets:
				if _heroes_at(loc).size() == 0:
					_place_token_at("thug", loc, 1)
			for loc in targets:
				if _heroes_at(loc).size() == 0:
					return
			_log("三个地点都有英雄，无地点放置暴徒", Color(0.8, 0.8, 0.6))
		"head_case":
			# 每名带有危机指示物的英雄受到 1 点伤害
			for hid in state["hero_ids"]:
				var h: Dictionary = state["heroes"][hid]
				if not h["ko"] and h["crisis"] > 0:
					await _deal_damage_to_hero(hid, 1)
			# 玩家选择一名英雄获得 1 个危机指示物（仅未 KO 的英雄可选）
			var candidates: Array = []
			for hid in state["hero_ids"]:
				if not state["heroes"][hid]["ko"]:
					candidates.append(hid)
			if candidates.size() == 0:
				return
			var labels: Array = []
			for hid in candidates:
				labels.append(DB.hero_name(hid))
			var picked_idx: int = await _ask("脑袋视线：选择一名英雄获得 1 个危机指示物", labels)
			var picked_hid: String = candidates[picked_idx]
			state["heroes"][picked_hid]["crisis"] += 1
			_log("%s 获得 1 危机指示物" % DB.hero_name(picked_hid), Color(0.7, 0.7, 1))
		"mimic_heroic", "mimic_attack":
			var sym := "heroic" if etype == "mimic_heroic" else "attack"
			var n := _count_last_hero_symbols(sym)
			if n > 0:
				_place_token_at("civ" if etype == "mimic_heroic" else "thug", vpos, n)
				_log("模仿：添加 %d 个%s到 %s" % [n, "平民" if etype == "mimic_heroic" else "暴徒", _loc_name(vpos)], Color(0.9, 0.8, 0.5))
		"dark_plan":
			if _heroes_at(vpos).size() == 0:
				state["locations"][vpos]["crisis"] += 1
				_log("模仿大师地点无英雄，放置 1 危机指示物", Color(0.7, 0.7, 1))

func _count_last_hero_symbols(sym: String) -> int:
	var count := 0
	var found := 0
	for i in range(state["story"].size() - 1, -1, -1):
		var entry: Dictionary = state["story"][i]
		if entry["type"] == "hero":
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
	var l: Dictionary = state["locations"][h["location"]]
	var virus := false
	if l["threat"] != null and l["threat"].get("start_turn", false):
		virus = true
		_log("奥创病毒：%s 必须选择一个行动符号并忽略它" % DB.hero_name(hid), Color(1, 0.8, 0.4))
	if l["threat"] != null and l["threat"]["name"] == "九头蛇特工鲍勃":
		h["crisis"] += 1
		_log("%s 获得 1 危机指示物（鲍勃）" % DB.hero_name(hid), Color(0.7, 0.7, 1))
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
		card_idx = h["hand"][hand_idx]
		h["hand"].remove_at(hand_idx)
		h["discard"].append(card_idx)
	state["story"].append({"type": "hero", "hero": hid, "idx": card_idx})
	state["hero_cards_played"] += 1
	var cards: Array = DB.hero_cards(hid)
	_log("%s 打出卡牌：%s" % [DB.hero_name(hid), _card_desc(hid, card_idx)], Color(0.8, 0.9, 1))
	state["action_symbols"] = cards[card_idx]["symbols"].duplicate()
	state["prev_hero_symbols"] = _last_hero_card_symbols()
	state["action_symbols"].append_array(state["prev_hero_symbols"])
	state["used_tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
	state["effect_available"] = cards[card_idx].has("effect")
	state["effect_used"] = false
	state["played_effect"] = cards[card_idx].get("effect", null)
	state["phase"] = "hero_actions"
	Events.emit_state_changed()

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
		if state["story"][i]["type"] == "hero":
			return DB.hero_cards(state["story"][i]["hero"])[state["story"][i]["idx"]]["symbols"].duplicate()
	return []

## 可用符号（含行动指示物，token_ 前缀表示消耗指示物）
func available_symbols() -> Array:
	var hid: String = state["hero_ids"][state["current_hero"]]
	var h: Dictionary = state["heroes"][hid]
	var out: Array = state["action_symbols"].duplicate()
	for t in ["move", "attack", "heroic", "wild"]:
		for i in range(h["tokens"][t] - state["used_tokens"][t]):
			out.append("token_" + t)
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
			state["heroes"][hid]["tokens"]["wild"] -= 1
		else:
			var widx: int = state["action_symbols"].find("wild")
			if widx == -1:
				Events.emit_toast("没有可用的万能行动")
				return
			state["action_symbols"].remove_at(widx)
		match base:
			"move":
				_execute_move(hid, "wild_token" if is_token else "wild_symbol")
			"attack":
				_execute_attack(hid, "wild_token" if is_token else "wild_symbol")
			"heroic":
				_execute_heroic(hid, "wild_token" if is_token else "wild_symbol")
		Events.emit_state_changed()
		return
	_consume_symbol(base, is_token, hid)

func _consume_symbol(base: String, is_token: bool, hid: String) -> void:
	if not is_token:
		var idx: int = state["action_symbols"].find(base)
		if idx == -1:
			Events.emit_toast("没有可用的%s行动" % DB.symbol_name(base))
			return
		state["action_symbols"].remove_at(idx)
	else:
		state["heroes"][hid]["tokens"][base] -= 1
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
	var entangle := false
	if l["threat"] != null and l["threat"]["name"] == "纠缠陷阱":
		entangle = true
	if entangle:
		# 纠缠陷阱：离开该地点需要消耗 2 个移动行动（本次 1 个 + 再补 1 个）
		var remaining: int = state["action_symbols"].count("move")
		var tok_avail: int = h["tokens"]["move"]
		if remaining + tok_avail < 1:
			Events.emit_toast("纠缠陷阱：离开需要 2 个移动行动（不足），已返还本次移动")
			_refund_symbol(hid, "move", consumed)
			return
		var idx: int = state["action_symbols"].find("move")
		if idx != -1:
			state["action_symbols"].remove_at(idx)
		else:
			h["tokens"]["move"] -= 1
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
	match consumed:
		"token":
			state["heroes"][hid]["tokens"][base] += 1
		"wild_symbol":
			state["action_symbols"].append("wild")
		"wild_token":
			state["heroes"][hid]["tokens"]["wild"] += 1
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
	_perform_attack_at(loc, targets[ci], hid)
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
				state["villain_hp"] -= 1
				_log("%s 攻击反派！生命 %d/%d" % [DB.hero_name(hid), state["villain_hp"], state["villain_hp_max"]], Color(1, 0.9, 0.3))
				if state["villain_hp"] <= 0:
					_win()
	Events.emit_state_changed()

## 在指定地点进行一次可选择目标的攻击（光子冲击用；可攻击暴徒/爪牙/反派）
func _attack_once_at(hid: String, loc: int, label: String) -> void:
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
	if targets.size() == 0:
		Events.emit_toast("该地点没有可攻击的目标")
		return
	var names: Array = []
	for t in targets:
		names.append(_target_name(t))
	var choice = await _ask(label + "：选择攻击目标", names)
	_perform_attack_at(loc, targets[int(choice)], hid)

func _target_name(t: String) -> String:
	if t == "thug":
		return "暴徒"
	if t.begins_with("henchman:"):
		return "爪牙：" + t.get_slice(":", 1)
	return "反派：" + DB.villain_name(state["villain"])

## 对地点造成伤害（处理需2伤的暴徒）
func _damage_thug_at(loc: int, dmg: int, hid: String) -> void:
	var l: Dictionary = state["locations"][loc]
	var needs2 := false
	if l["threat"] != null and (l["threat"]["name"] == "精锐暴徒" or l["threat"]["name"] == "九头蛇精英部队"):
		needs2 = true
	if needs2:
		# 简化：本地点所有暴徒共享伤害计数，每2伤消灭1个
		var key := "thug_dmg_%d" % loc
		state[key] = state.get(key, 0) + dmg
		var kills: int = state[key] / 2
		if kills > 0:
			state[key] = state[key] % 2
			_defeat_thug(loc, kills)
		else:
			_log("%s 攻击暴徒（需要 2 点伤害，已累计 %d/2）" % [DB.hero_name(hid), state[key]], Color(0.9, 0.8, 0.6))
	else:
		_defeat_thug(loc, dmg)

func _defeat_thug(loc: int, count: int) -> void:
	var l: Dictionary = state["locations"][loc]
	var n := mini(count, l["thug"])
	if n <= 0:
		return
	l["thug"] -= n
	_log("消灭 %d 个暴徒（%s）" % [n, _loc_name(loc)], Color(0.9, 0.9, 0.7))
	_add_mission_token("defeat", n)
	Events.emit_state_changed()

func _clear_threat(loc: int) -> void:
	var l: Dictionary = state["locations"][loc]
	var t: Dictionary = l["threat"]
	_log("威胁清除：%s（%s）" % [t["name"], _loc_name(loc)], Color(0.6, 1, 0.8))
	l["threat"] = null
	l["threat_token"] = false
	_add_mission_token("clear", 1)
	Events.emit_state_changed()

func _add_mission_token(mission_id: String, n: int) -> void:
	for m in state["missions"]:
		if m["id"] == mission_id and not m.get("done", false):
			var add := mini(n, m["slots"] - m["tokens"])
			m["tokens"] += add
			if m["tokens"] >= m["slots"]:
				_complete_mission(m)
			return

func _complete_mission(m: Dictionary) -> void:
	state["missions_completed"] += 1
	m["done"] = true
	m["tokens"] = 0
	_log("🎯 任务完成：%s！（已完成 %d/3）" % [m["name"], state["missions_completed"]], Color(0.5, 1, 0.5))
	match state["missions_completed"]:
		1:
			_log("反派进入高压状态：每 2 张英雄牌触发一次反派回合", Color(1, 0.8, 0.4))
		2:
			_log("解锁攻击反派权限！", Color(1, 0.9, 0.3))
		3:
			for hid in state["hero_ids"]:
				_draw_card(hid)
			_log("所有英雄各抽 1 张牌", Color(0.7, 1, 0.9))

# ---- heroic

func _execute_heroic(hid: String, consumed: String) -> void:
	var h: Dictionary = state["heroes"][hid]
	var loc: int = h["location"]
	var l: Dictionary = state["locations"][loc]
	var options: Array = []
	var rescue_cost := 1
	var explosive := false
	if l["threat"] != null and l["threat"]["name"] == "爆炸陷阱":
		rescue_cost = 2
		explosive = true
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
		if explosive:
			var ok := _consume_extra_heroic(1)
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
			var h: Dictionary = state["heroes"][hid]
			if h["tokens"]["heroic"] - state["used_tokens"]["heroic"] > 0:
				state["used_tokens"]["heroic"] += 1
				got += 1
			else:
				break
	if got < n:
		Events.emit_toast("英勇行动不足（爆炸陷阱需要 2 个英勇）")
		state["action_symbols"].append("heroic")
		return false
	return true

func _rescue_civ(hid: String, loc: int) -> void:
	var l: Dictionary = state["locations"][loc]
	l["civ"] -= 1
	_log("%s 营救 1 名平民（%s）" % [DB.hero_name(hid), _loc_name(loc)], Color(0.8, 1, 0.9))
	_add_mission_token("rescue", 1)
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
				var top: int = state["master_deck"][0]
				var ok: bool = await _ask_villain_card(top, "审讯：查看主计划牌堆顶。是否放到牌组底部？")
				if ok:
					state["master_deck"].remove_at(0)
					state["master_deck"].append(top)
					_log("审讯：将顶牌放到牌组底部", Color(0.7, 0.9, 1))
				else:
					_log("审讯：顶牌保持原位", Color(0.7, 0.9, 1))
	Events.emit_state_changed()
	await _maybe_auto_end_turn()  # 效果用完后符号若已用尽则自动结束回合

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
func _hero_has_action_tokens() -> bool:
	var hid: String = state["hero_ids"][state["current_hero"]]
	var t: Dictionary = state["heroes"][hid]["tokens"]
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
			while state["heroes"][hid]["hand"].size() < 3:
				if not _draw_card(hid):
					break
			_log("复仇者庄园：抽牌直到手牌 3 张", Color(0.8, 0.9, 1))
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
	return state["hero_ids"][state["current_hero"]]

func current_hero_state() -> Dictionary:
	return state["heroes"][current_hero_id()]

func get_state() -> Dictionary:
	return state
