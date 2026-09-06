class_name VillainRules
## 反派专属规则（与"基础规则"分离）。
## 这里只放"某一反派特有"的规则实现；通用的抽牌/移动/伤害/威胁等基础逻辑留在 Game 引擎。
## 新增反派 = 在这里新增对应 villian_id 的方法并注册到 dispatch，不改 Game 的通用循环。
##
## 设计约定：
##  - 不把反派规则写死进 Game 的通用函数（如 BAM/溢出/特殊效果）。
##  - 各反派方法互相独立，绝不跨角色复用彼此代码；相同逻辑各自实现。

# 反派 ID 列表（用于校验/迭代）
const IDS := ["redskull", "ultron", "taskmaster", "thanos", "proxima", "cull", "ebony", "kilmonger", "loki", "ronan", "goblin"]


## BAM 特效入口：Game 翻出 BAM 时调用，按反派分发。
## 注意：各 _*_bam 是异步协程（内部有 await），这里必须逐条 await，否则协程会后台游离、
## 导致 BAM 结算（弃牌/丢弃平民/屠宰）与英雄回合竞态错序。
static func on_bam(game: Node, villain_id: String) -> void:
	match villain_id:
		"redskull":
			await _redskull_bam(game)
		"ultron":
			await _ultron_bam(game)
		"taskmaster":
			await _taskmaster_bam(game)
		"thanos":
			await _thanos_bam(game)
		"proxima":
			await _proxima_bam(game)
		"cull":
			await _cull_bam(game)
		"ebony":
			await _ebony_bam(game)
		"kilmonger":
			await _kilmonger_bam(game)
		"loki":
			await _loki_bam(game)
		"ronan":
			await _ronan_bam(game)
		"goblin":
			await _goblin_bam(game)
		_:
			pass


## 溢出特效入口：某个地点放不下指示物时，按反派处理。
static func on_overflow(game: Node, villain_id: String, kind: String, loc: int) -> void:
	match villain_id:
		"redskull":
			await _redskull_overflow(game, loc)
		"ultron":
			await _ultron_overflow(game, kind, loc)
		"taskmaster":
			await _taskmaster_overflow(game, loc)
		"thanos":
			await _thanos_overflow(game, loc)
		"proxima":
			await _proxima_overflow(game, kind, loc)
		"cull":
			await _cull_overflow(game, loc)
		"ebony":
			await _ebony_overflow(game, loc)
		"kilmonger":
			await _kilmonger_overflow(game, loc)
		"loki":
			await _loki_overflow(game)
		"ronan":
			await _ronan_overflow(game, kind, loc)
		"goblin":
			await _goblin_overflow(game, loc)
		_:
			pass


# ---------------------------------------------------------------- BAM 实现

static func _heroes_at(game: Node, loc: int) -> Array:
	return game._heroes_at(loc)


static func _vpos(game: Node) -> int:
	return game.state["villain_pos"]


static func _redskull_bam(game: Node) -> void:
	var vpos := _vpos(game)
	for hid in _heroes_at(game, vpos):
		await game._deal_damage_to_hero(hid, 1)
	game.state["fear"] = mini(game.state["fear"] + 2, 20)
	game._log("恐惧轨道 +2（当前 %d）" % game.state["fear"], Color(0.9, 0.6, 0.6))


static func _ultron_bam(game: Node) -> void:
	var vpos := _vpos(game)
	await game._place_token_at("thug", vpos, 3)
	for hid in _heroes_at(game, vpos):
		await game._deal_damage_to_hero(hid, 1)


static func _taskmaster_bam(game: Node) -> void:
	var vpos := _vpos(game)
	for hid in _heroes_at(game, vpos):
		await game._deal_damage_to_hero(hid, 1)
	game.state["locations"][vpos]["crisis"] += 1
	game._log("%s +1 危机指示物" % game._loc_name(vpos), Color(0.7, 0.7, 1))


static func _thanos_bam(game: Node) -> void:
	var vpos := _vpos(game)
	for hid in game.state["hero_ids"]:
		var hl: int = game.state["heroes"][hid]["location"]
		if hl == vpos:
			await game._deal_damage_to_hero(hid, 2)
		else:
			await game._deal_damage_to_hero(hid, 1)


static func _proxima_bam(game: Node) -> void:
	var vpos := _vpos(game)
	for hid in _heroes_at(game, vpos):
		await game._deal_damage_to_hero(hid, 1)
	var dropped: int = game.state["locations"][vpos]["civ"]
	game.state["locations"][vpos]["civ"] = 0
	game.state["slaughter"] = mini(game.state["slaughter"] + dropped, 12)
	game._log("丢弃 %d 平民，屠宰轨道 +%d（当前 %d / 12）" % [dropped, dropped, game.state["slaughter"]], Color(0.9, 0.5, 0.5))


static func _cull_bam(game: Node) -> void:
	var vpos := _vpos(game)
	for hid in _heroes_at(game, vpos):
		await game._deal_damage_to_hero(hid, 1)
	var has_chain: bool = game._threat_present("链锤")
	if has_chain:
		for adj in [(vpos + game.LOCATION_COUNT - 1) % game.LOCATION_COUNT, (vpos + 1) % game.LOCATION_COUNT]:
			for hid in _heroes_at(game, adj):
				await game._deal_damage_to_hero(hid, 1)
		game._log("链锤：相邻地点的英雄也受到 1 点伤害", Color(1, 0.6, 0.4))


static func _ebony_bam(game: Node) -> void:
	var vpos := _vpos(game)
	for hid in _heroes_at(game, vpos):
		game.state["heroes"][hid]["crisis"] += 1
		await game._deal_damage_to_hero(hid, 1)
	game._log("%s 的英雄各获得 1 危机指示物" % game._loc_name(vpos), Color(0.7, 0.7, 1))


# ---------------------------------------------------------------- 溢出实现

static func _redskull_overflow(game: Node, loc: int) -> void:
	game.state["fear"] = mini(game.state["fear"] + 1, 20)
	game._log("溢出！%s 放不下，恐惧轨道 +1（当前 %d）" % [game._loc_name(loc), game.state["fear"]], Color(0.9, 0.5, 0.5))


static func _ultron_overflow(game: Node, kind: String, loc: int) -> void:
	var cur := loc
	for attempt in range(game.LOCATION_COUNT):
		cur = (cur + 1) % game.LOCATION_COUNT
		var l2: Dictionary = game.state["locations"][cur]
		var slots_total: int = int(DB.location(l2["id"])["slots"])
		if l2["civ"] + l2["thug"] < slots_total:
			if kind == "thug":
				l2["thug"] += 1
			else:
				l2["civ"] += 1
			game._log("溢出！顺延到 %s 放置" % game._loc_name(cur), Color(0.9, 0.9, 0.6))
			return
	game._log("溢出！所有地点已满，%s 被丢弃" % ("暴徒" if kind == "thug" else "平民"), Color(0.8, 0.6, 0.6))


static func _taskmaster_overflow(game: Node, loc: int) -> void:
	game.state["locations"][loc]["crisis"] += 1
	game._log("溢出！改为在 %s 放置 1 危机指示物" % game._loc_name(loc), Color(0.7, 0.7, 1))


static func _thanos_overflow(game: Node, loc: int) -> void:
	if game.state["locations"][loc]["civ"] > 0:
		game.state["locations"][loc]["civ"] -= 1
		game.state["locations"][loc]["thug"] += 1
		game._log("溢出！%s 最左边的平民转换为暴徒" % game._loc_name(loc), Color(0.9, 0.6, 0.6))
	else:
		game.state["extra_villain_card"] += 1
		game._log("溢出！%s 无平民可转换，抽取一张反派行动卡" % game._loc_name(loc), Color(1, 0.6, 0.5))


static func _proxima_overflow(game: Node, kind: String, loc: int) -> void:
	if kind == "thug":
		for hid in _heroes_at(game, loc):
			await game._deal_damage_to_hero(hid, 1)
		game._log("溢出！%s 的暴徒放不下，该地点英雄各受 1 点伤害" % game._loc_name(loc), Color(1, 0.6, 0.4))
	else:
		game.state["slaughter"] = mini(game.state["slaughter"] + 1, 12)
		game._log("溢出！%s 的平民放不下，屠宰轨道 +1（当前 %d / 12）" % [game._loc_name(loc), game.state["slaughter"]], Color(0.9, 0.5, 0.5))


static func _cull_overflow(game: Node, loc: int) -> void:
	for hid in _heroes_at(game, loc):
		await game._deal_damage_to_hero(hid, 1)
	game._log("溢出！%s 的指示物放不下，该地点英雄各受 1 点伤害" % game._loc_name(loc), Color(1, 0.6, 0.4))


static func _ebony_overflow(game: Node, loc: int) -> void:
	for hid in _heroes_at(game, loc):
		game.state["heroes"][hid]["crisis"] += 1
	game._log("溢出！%s 的指示物放不下，该地点英雄各获得 1 危机指示物" % game._loc_name(loc), Color(0.7, 0.7, 1))


# ---------------------------------------------------------------- 反派特殊效果

## 反派特殊效果入口：翻出带 effect 的反派行动卡时，按 eff["type"] 分发。
static func resolve_effect(game: Node, eff: Dictionary) -> void:
	var etype: String = eff["type"]
	game._log("反派特殊效果：%s" % eff["text"], Color(1, 0.8, 0.4))
	var vpos: int = game.state["villain_pos"]
	match etype:
		"redskull_emergency":
			await _redskull_emergency(game)
		"hail_hydra":
			await _hail_hydra(game)
		"hypnotize":
			await _hypnotize(game, vpos)
		"head_case":
			await _head_case(game)
		"mimic_heroic", "mimic_attack":
			await _mimic(game, etype, vpos)
		"dark_plan":
			_dark_plan(game, vpos)
		"mad_titan":
			await _mad_titan(game, vpos)
		"thanos_mercy":
			_thanos_mercy(game, vpos)
		"purify":
			await game._discard_civs_with_choice([(vpos + game.LOCATION_COUNT - 1) % game.LOCATION_COUNT, (vpos + 1) % game.LOCATION_COUNT])
		"hunt_spear":
			await _hunt_spear(game)
		"axe_swing":
			_axe_swing(game, vpos)
		"heal_factor":
			await _heal_factor(game, vpos)
		"genius_intellect":
			_genius_intellect(game)
		"manipulate":
			await _manipulate(game)
		"km_overthrow":
			await _km_overthrow(game)
		"km_duel":
			await _km_duel(game)
		"loki_reach_empty_threat":
			await _loki_reach_empty_threat(game)
		"loki_witchcraft":
			await _loki_witchcraft(game)
		"loki_discord":
			await _loki_discord(game)
		"ronan_kree":
			await _ronan_kree(game)
		"ronan_universal":
			await _ronan_universal(game)
		"goblin_kidnap":
			await _goblin_kidnap(game)
		"goblin_scoundrel":
			_goblin_scoundrel(game)
		_:
			pass


static func _redskull_emergency(game: Node) -> void:
	var total := 0
	for hid in game.state["hero_ids"]:
		total += game.state["heroes"][hid]["crisis"]
	game.state["fear"] = mini(game.state["fear"] + total, 20)
	game._log("英雄共有 %d 个危机指示物，恐惧轨道 +%d（当前 %d）" % [total, total, game.state["fear"]], Color(0.9, 0.6, 0.6))


static func _hail_hydra(game: Node) -> void:
	var discarded := 0
	for hid in game.state["hero_ids"]:
		var l: Dictionary = game.state["locations"][game.state["heroes"][hid]["location"]]
		discarded += l["civ"]
		l["civ"] = 0
		await game._deal_damage_to_hero(hid, 1)
	game.state["fear"] = mini(game.state["fear"] + discarded, 20)
	game._log("弃置 %d 名平民，恐惧轨道 +%d（当前 %d）" % [discarded, discarded, game.state["fear"]], Color(0.9, 0.6, 0.6))


static func _hypnotize(game: Node, vpos: int) -> void:
	var targets: Array = [vpos, (vpos + game.LOCATION_COUNT - 1) % game.LOCATION_COUNT, (vpos + 1) % game.LOCATION_COUNT]
	for hid in game.state["hero_ids"]:
		if targets.has(game.state["heroes"][hid]["location"]):
			game.state["heroes"][hid]["crisis"] += 1
	game._log("奥创所在地点及相邻地点的英雄各获得 1 危机指示物", Color(0.7, 0.7, 1))
	for loc in targets:
		if _heroes_at(game, loc).size() == 0:
			await game._place_token_at("thug", loc, 1)
	for loc in targets:
		if _heroes_at(game, loc).size() == 0:
			return
	game._log("三个地点都有英雄，无地点放置暴徒", Color(0.8, 0.8, 0.6))


static func _head_case(game: Node) -> void:
	for hid in game.state["hero_ids"]:
		var h: Dictionary = game.state["heroes"][hid]
		if not h["ko"] and h["crisis"] > 0:
			await game._deal_damage_to_hero(hid, 1)
	var candidates: Array = []
	for hid in game.state["hero_ids"]:
		if not game.state["heroes"][hid]["ko"]:
			candidates.append(hid)
	if candidates.size() == 0:
		return
	var labels: Array = []
	for hid in candidates:
		labels.append(DB.hero_name(hid))
	var picked_idx: int = await game._ask("脑袋视线：选择一名英雄获得 1 个危机指示物", labels)
	var picked_hid: String = candidates[picked_idx]
	game.state["heroes"][picked_hid]["crisis"] += 1
	game._log("%s 获得 1 危机指示物" % DB.hero_name(picked_hid), Color(0.7, 0.7, 1))


static func _mimic(game: Node, etype: String, vpos: int) -> void:
	var sym := "heroic" if etype == "mimic_heroic" else "attack"
	var n: int = game._count_last_hero_symbols(sym)
	if n > 0:
		await game._place_token_at("civ" if etype == "mimic_heroic" else "thug", vpos, n)
		game._log("模仿：添加 %d 个%s到 %s" % [n, "平民" if etype == "mimic_heroic" else "暴徒", game._loc_name(vpos)], Color(0.9, 0.8, 0.5))


static func _dark_plan(game: Node, vpos: int) -> void:
	if _heroes_at(game, vpos).size() == 0:
		game.state["locations"][vpos]["crisis"] += 1
		game._log("模仿大师地点无英雄，放置 1 危机指示物", Color(0.7, 0.7, 1))


static func _mad_titan(game: Node, vpos: int) -> void:
	var heal := mini(5, int(game.state["villain_hp_max"]) - int(game.state["villain_hp"]))
	if heal > 0:
		game.state["villain_hp"] += heal
		game._log("灭霸回复 %d 点生命（当前 %d/%d）" % [heal, game.state["villain_hp"], game.state["villain_hp_max"]], Color(0.9, 0.6, 1))
	for hid in _heroes_at(game, vpos):
		await game._deal_damage_to_hero(hid, 1)


static func _thanos_mercy(game: Node, vpos: int) -> void:
	var targets: Array = [vpos, (vpos + game.LOCATION_COUNT - 1) % game.LOCATION_COUNT, (vpos + 1) % game.LOCATION_COUNT]
	for loc in targets:
		if game.state["locations"][loc]["civ"] > 0:
			game.state["locations"][loc]["civ"] -= 1
			game._log("灭霸的怜悯：%s 丢弃 1 个平民" % game._loc_name(loc), Color(0.9, 0.6, 0.6))


static func _hunt_spear(game: Node) -> void:
	var best := -1
	var best_count := -1
	for i in range(game.LOCATION_COUNT):
		var c: int = game.state["locations"][i]["civ"]
		if c > best_count:
			best_count = c
			best = i
	if best >= 0 and best_count > 0:
		game.state["villain_pos"] = best
		game._log("狩猎长矛：移动到 %s（拥有最多平民）" % game._loc_name(best), Color(0.9, 0.7, 1))
		await game._discard_civs_with_choice([best])
	else:
		game._log("狩猎长矛：没有地点有平民，未移动", Color(0.8, 0.8, 0.8))


static func _axe_swing(game: Node, vpos: int) -> void:
	var targets: Array = [vpos, (vpos + game.LOCATION_COUNT - 1) % game.LOCATION_COUNT, (vpos + 1) % game.LOCATION_COUNT]
	for hid in game.state["hero_ids"]:
		if targets.has(game.state["heroes"][hid]["location"]):
			await game._deal_damage_to_hero(hid, 1)


static func _heal_factor(game: Node, vpos: int) -> void:
	var heal := mini(3, int(game.state["villain_hp_max"]) - int(game.state["villain_hp"]))
	if heal > 0:
		game.state["villain_hp"] += heal
		game._log("黑矮星回复 %d 点生命（当前 %d/%d）" % [heal, game.state["villain_hp"], game.state["villain_hp_max"]], Color(0.9, 0.6, 1))
	else:
		for hid in _heroes_at(game, vpos):
			await game._deal_damage_to_hero(hid, 1)
		game._log("黑矮星生命已满，对所在地点英雄各造成 1 点伤害", Color(1, 0.6, 0.4))


static func _genius_intellect(game: Node) -> void:
	var total := 0
	for hid in game.state["hero_ids"]:
		total += game.state["heroes"][hid]["crisis"]
	if total > 0:
		game.state["extra_villain_card"] += total
		game._log("天才智力：英雄共有 %d 个危机指示物，额外打出 %d 张行动卡" % [total, total], Color(1, 0.6, 0.5))


static func _manipulate(game: Node) -> void:
	var best := -1
	var best_count := -1
	for i in range(game.LOCATION_COUNT):
		var c: int = _heroes_at(game, i).size()
		if c > best_count:
			best_count = c
			best = i
	if best >= 0 and best_count > 0:
		game.state["villain_pos"] = best
		game._log("操纵：移动到 %s（拥有最多英雄）" % game._loc_name(best), Color(0.9, 0.7, 1))
	for hid in _heroes_at(game, game.state["villain_pos"]):
		game.state["heroes"][hid]["crisis"] += 1
	game._log("操纵：所在地点英雄各获得 1 危机指示物", Color(0.7, 0.7, 1))

# ---------------------------------------------------------------- 基尔格蒙 (Killmonger)

## 把地点的最左边一个平民/暴徒指示物替换为 1 个危机指示物（一换一）
static func _km_replace_leftmost(game: Node, loc: int) -> void:
	var l: Dictionary = game.state["locations"][loc]
	# “最左边”按官方视觉约定：优先转换最左列。判定顺序：左边优先，其次选择 平民→暴徒 的左边。
	# 简化实现：若该地点有暴徒则先换最左暴徒，否则换最左平民；两种指示物各自“从左往右”取一个。
	# 这里按 平民/暴徒 一换一：优先转换最左边的一个平民（若有），否则最左边一个暴徒。
	var replaced := false
	if l["civ"] > 0 or l["thug"] > 0:
		# 优先转走一个平民（卡面“最左边的平民/暴徒”指视觉最左的指示物；此处用有一定代表性的取法）
		if l["civ"] > 0:
			l["civ"] -= 1
			replaced = true
		elif l["thug"] > 0:
			l["thug"] -= 1
			replaced = true
	if replaced:
		l["crisis"] += 1
		game._log("基尔格蒙：%s 最左边一个平民/暴徒替换为 1 个危机指示物（危机 %d）" % [game._loc_name(loc), l["crisis"]], Color(0.8, 0.6, 1))
	else:
		game._log("基尔格蒙：%s 没有平民/暴徒可替换" % game._loc_name(loc), Color(0.8, 0.8, 0.8))

## BAM：所在地点每位英雄 1 伤害；然后最左边平民/暴徒 → 危机
static func _kilmonger_bam(game: Node) -> void:
	var vpos := _vpos(game)
	for hid in game.state["hero_ids"]:
		var hl: int = game.state["heroes"][hid]["location"]
		if hl == vpos:
			await game._deal_damage_to_hero(hid, 1)
	_km_replace_leftmost(game, vpos)

## 溢出：最左边平民/暴徒 → 危机
static func _kilmonger_overflow(game: Node, _loc: int) -> void:
	# 卡面：无法放置时，将基尔格蒙所在地点最左边的平民/暴徒替换为危机指示物
	_km_replace_leftmost(game, _vpos(game))

## 推翻：移动到拥有最多危机指示物的最近位置；将该地点所有平民转为危机指示物；
## 若该地点没有平民，则顺时针移动到下一个地点（换个有平民/可转的，或继续找）。
static func _km_overthrow(game: Node) -> void:
	var vpos := _vpos(game)
	# 1. 找到危机数最多（且离当前最近）的地点
	var max_crisis := -1
	var best := vpos
	for i in range(game.LOCATION_COUNT):
		var c: int = game.state["locations"][i]["crisis"]
		if c > max_crisis:
			max_crisis = c
			best = i
	# 若有并列最多，取离当前最近（顺时针距离）的地点；实际按“最近”处理为距离最小者。
	best = _nearest_with_crisis(game, vpos, max_crisis)
	game.state["villain_pos"] = best
	game._log("推翻：移动到 %s（拥有最多危机指示物 %d 个）" % [game._loc_name(best), max_crisis], Color(1, 0.8, 0.3))
	# 2. 将该地点所有平民转为危机指示物
	var l: Dictionary = game.state["locations"][best]
	if l["civ"] > 0:
		l["crisis"] += l["civ"]
		l["civ"] = 0
		game._log("推翻：%s 全部 %d 个平民转为危机指示物（危机 %d）" % [game._loc_name(best), l["crisis"] - 0, l["crisis"]], Color(0.8, 0.6, 1))
	else:
		# 3. 无平民：顺时针移动到下一个地点继续执行
		var nxt: int = (best + 1) % game.LOCATION_COUNT
		game.state["villain_pos"] = nxt
		var l2: Dictionary = game.state["locations"][nxt]
		if l2["civ"] > 0:
			l2["crisis"] += l2["civ"]
			l2["civ"] = 0
			game._log("推翻：%s 无平民，顺移到 %s 将 %d 个平民转为危机" % [game._loc_name(best), game._loc_name(nxt), l2["crisis"]], Color(0.8, 0.6, 1))
		else:
			game._log("推翻：%s 及下一地点均无平民可转" % game._loc_name(best), Color(0.8, 0.8, 0.8))

## 辅助：在危机数等于 target 且离 vpos 最近的地点中选一个（顺时针距离取最小）
static func _nearest_with_crisis(game: Node, vpos: int, target: int) -> int:
	var best := vpos
	var best_dist := 999
	for i in range(game.LOCATION_COUNT):
		if game.state["locations"][i]["crisis"] != target:
			continue
		var d: int = (i - vpos + int(game.LOCATION_COUNT)) % int(game.LOCATION_COUNT)
		if d < best_dist:
			best_dist = d
			best = i
	return best

## 决斗：顺时针移动到有英雄的下一个地点；对该地点 1 名英雄造成 2 点伤害（英雄们选择分配）
static func _km_duel(game: Node) -> void:
	var vpos := _vpos(game)
	# 1. 顺时针找到下一个有英雄的地点
	var target := vpos
	for step in range(1, game.LOCATION_COUNT + 1):
		var i: int = (vpos + step) % game.LOCATION_COUNT
		if _heroes_at(game, i).size() > 0:
			target = i
			break
	game.state["villain_pos"] = target
	game._log("决斗：顺时针移动到 %s（有英雄）" % game._loc_name(target), Color(1, 0.8, 0.3))
	# 2. 该地点英雄分配 2 点伤害：玩家为每 1 点伤害选择承受英雄
	var heroes_here: Array = _heroes_at(game, target).filter(func(h): return not game.state["heroes"][h]["ko"])
	if heroes_here.size() == 0:
		game._log("决斗：该地点无可伤害英雄", Color(0.8, 0.8, 0.8))
		return
	for di in range(2):
		var labels: Array = []
		for hid in heroes_here:
			labels.append(DB.hero_name(hid))
		# 关键：第二次选择时排除已被 KO 的英雄（避免伤害选到已倒英雄）
		heroes_here = heroes_here.filter(func(h): return not game.state["heroes"][h]["ko"])
		if heroes_here.size() == 0:
			break
		var labels2: Array = []
		for hid in heroes_here:
			labels2.append(DB.hero_name(hid))
		var picked_idx: int = await game._ask("决斗：第 %d 点伤害由哪个英雄承受？" % (di + 1), labels2)
		var hid: String = heroes_here[picked_idx]
		await game._deal_damage_to_hero(hid, 1)
		game._log("决斗：%s 承受 1 点伤害" % DB.hero_name(hid), Color(1, 0.6, 0.4))

# ---------------------------------------------------------------- 洛基 (Loki)

## "孤独"判定：该地点只有 1 名未被 KO 的英雄。威胁卡/平民/暴徒/反派 不计入。
static func _lonely_heroes(game: Node) -> Array:
	var out: Array = []
	for i in range(int(game.LOCATION_COUNT)):
		var here: Array = _heroes_at(game, i).filter(func(h): return not game.state["heroes"][h]["ko"])
		if here.size() == 1:
			out.append(here[0])
	return out

## BAM：对洛基所在地点的所有英雄造成 1 点伤害
static func _loki_bam(game: Node) -> void:
	var vpos := _vpos(game)
	for hid in game.state["hero_ids"]:
		var hl: int = game.state["heroes"][hid]["location"]
		if hl == vpos and not game.state["heroes"][hid]["ko"]:
			await game._deal_damage_to_hero(hid, 1)

## 溢出：如果平民/暴徒无法放置在地点上，洛基获得 1 点额外生命值（可超过生命上限）
## 注意：一张行动牌最多触发 3 次（3 个地点各溢出 +1）
static func _loki_overflow(game: Node) -> void:
	game.state["villain_hp"] += 1
	game._log("溢出！洛基无法放置指示物，获得 1 点额外生命值（当前 %d / 上限 %d）" % [game.state["villain_hp"], game.state["villain_hp_max"]], Color(0.9, 0.6, 1))

## 卡1（幻象大师）：顺时针移动到下一个没有威胁卡的地点，随机将一张"被解决的威胁卡"放置到该地点。
## 若没有已解决的威胁卡，或没有空位，则跳过移动（洛基不移动）。
static func _loki_reach_empty_threat(game: Node) -> void:
	var vpos := _vpos(game)
	var solved: Array = game.state["solved_threats"]
	if solved.size() == 0:
		game._log("幻象大师：没有已解决的威胁卡可放置，洛基不移动", Color(0.8, 0.8, 0.8))
		return
	# 顺时针找下一个"没有威胁卡"的地点
	for step in range(1, int(game.LOCATION_COUNT) + 1):
		var i: int = (vpos + step) % int(game.LOCATION_COUNT)
		var l: Dictionary = game.state["locations"][i]
		if l["threat"] == null:
			game.state["villain_pos"] = i
			game._log("幻象大师：洛基移动到 %s" % game._loc_name(i), Color(0.9, 0.7, 1))
			# 随机取一张被解决的威胁卡放置到该地点
			var t: Dictionary = solved[randi() % solved.size()]
			solved.erase(t)
			l["threat"] = t.duplicate(true)
			l["threat_token"] = true
			game._log("幻象大师：将「%s」放置到 %s" % [t["name"], game._loc_name(i)], Color(0.8, 0.6, 1))
			Events.emit_state_changed()
			return
	game._log("幻象大师：没有空位（无威胁卡地点），洛基不移动", Color(0.8, 0.8, 0.8))

## 巫术：每个孤独的英雄受到一点伤害。如果没有英雄是孤独的，就再抽取一张反派行动牌，面朝下加到故事情节中。
static func _loki_witchcraft(game: Node) -> void:
	var lonely: Array = _lonely_heroes(game)
	if lonely.size() > 0:
		for hid in lonely:
			await game._deal_damage_to_hero(hid, 1)
		game._log("巫术：%d 个孤独的英雄各受到 1 点伤害" % lonely.size(), Color(1, 0.6, 0.4))
	else:
		_loki_stash_villain_card(game)
		game._log("巫术：无孤独英雄，洛基抽取一张反派行动牌面朝下放入故事情节", Color(0.8, 0.9, 1))

## 传播不和：每个孤独的英雄受到一点伤害。如果所有英雄都是孤独的，就再抽取一张反派行动牌，面朝下加到故事情节中。
static func _loki_discord(game: Node) -> void:
	var lonely: Array = _lonely_heroes(game)
	var active: Array = []
	for hid in game.state["hero_ids"]:
		if not game.state["heroes"][hid]["ko"]:
			active.append(hid)
	if lonely.size() > 0:
		for hid in lonely:
			await game._deal_damage_to_hero(hid, 1)
		game._log("传播不和：%d 个孤独的英雄各受到 1 点伤害" % lonely.size(), Color(1, 0.6, 0.4))
	# 收割条件：所有英雄都是孤独的（每个英雄单独一处），而非"有孤独英雄"
	if active.size() > 0 and lonely.size() == active.size():
		_loki_stash_villain_card(game)
		game._log("传播不和：所有英雄都孤独，洛基抽取一张反派行动牌面朝下放入故事情节", Color(0.8, 0.9, 1))

## 辅佐：从主计划牌堆抽一张，面朝下放到故事情节（只展示，不结算）
static func _loki_stash_villain_card(game: Node) -> void:
	if game.state["master_deck"].size() == 0:
		game._log("洛基的主计划牌堆已空，无法抽牌", Color(1, 0.5, 0.5))
		return
	var d: Variant = game.state["master_deck"].pop_front()
	game.state["story"].append({"type": "villain", "villain": game.state["villain"], "idx": d if d is int else -1, "move": 0, "face_down": true})

# ---------------------------------------------------------------- 罗南 (Ronan)

## BAM：罗南所在地点的 1 名英雄受到 1 点伤害（玩家选择）。
static func _ronan_bam(game: Node) -> void:
	var vpos := _vpos(game)
	var heroes_here: Array = _heroes_at(game, vpos).filter(func(h): return not game.state["heroes"][h]["ko"])
	if heroes_here.size() == 0:
		game._log("BAM：罗南所在地点没有英雄可伤害", Color(0.8, 0.8, 0.8))
		return
	var labels: Array = []
	for hid in heroes_here:
		labels.append(DB.hero_name(hid))
	var picked_idx: int = await game._ask("罗南 BAM！选择 1 名英雄受到 1 点伤害", labels)
	var hid: String = heroes_here[picked_idx]
	await game._deal_damage_to_hero(hid, 1)
	game._log("罗南：%s 受到 1 点伤害" % DB.hero_name(hid), Color(1, 0.6, 0.4))

## 溢出：每有 1 个无法放置的平民/暴徒指示物，该地点 1 名英雄受到 1 点伤害（玩家选择）。
static func _ronan_overflow(game: Node, kind: String, loc: int) -> void:
	var heroes_here: Array = _heroes_at(game, loc).filter(func(h): return not game.state["heroes"][h]["ko"])
	if heroes_here.size() == 0:
		game._log("溢出！%s 没有英雄可伤害" % game._loc_name(loc), Color(0.8, 0.8, 0.8))
		return
	var labels: Array = []
	for hid in heroes_here:
		labels.append(DB.hero_name(hid))
	var picked_idx: int = await game._ask("溢出！%s 放不下（%s），选择 1 名英雄受到 1 点伤害" % [game._loc_name(loc), "暴徒" if kind == "thug" else "平民"], labels)
	var hid: String = heroes_here[picked_idx]
	await game._deal_damage_to_hero(hid, 1)
	game._log("溢出：%s 受到 1 点伤害" % DB.hero_name(hid), Color(1, 0.6, 0.4))

## 克里-法：在每个地点添加 1 个暴徒。
static func _ronan_kree(game: Node) -> void:
	for i in range(int(game.LOCATION_COUNT)):
		await game._place_token_at("thug", i, 1)
	game._log("克里-法：每个地点添加 1 个暴徒", Color(0.9, 0.7, 1))

## 宇宙-鲁：对罗南所在地点的每个英雄造成 1 点伤害。
static func _ronan_universal(game: Node) -> void:
	var vpos := _vpos(game)
	for hid in _heroes_at(game, vpos):
		await game._deal_damage_to_hero(hid, 1)
	game._log("宇宙-鲁：%s 的每个英雄受到 1 点伤害" % game._loc_name(vpos), Color(1, 0.6, 0.4))

# ---------------------------------------------------------------- 绿魔 (Green Goblin)

## BAM：对绿魔所在地点的每个英雄造成 1 点伤害，然后抽取一张威胁卡放置在顺时针下一个没有威胁卡的地点。
static func _goblin_bam(game: Node) -> void:
	var vpos := _vpos(game)
	for hid in _heroes_at(game, vpos):
		await game._deal_damage_to_hero(hid, 1)
	game._log("绿魔 BAM！，抽取威胁卡放置到下一个无威胁卡地点", Color(1, 0.7, 0.3))
	game._goblin_place_threat_from_deck(vpos)

## 溢出：若平民/暴徒无法添加，则抽取一张威胁卡放置在顺时针下一个没有威胁卡的地点（从溢出地点开始）。
static func _goblin_overflow(game: Node, loc: int) -> void:
	game._log("溢出！绿魔抽取威胁卡放置到下一个无威胁卡地点", Color(1, 0.7, 0.3))
	game._goblin_place_threat_from_deck(loc)

## 绑架：如果绿魔所在地点有平民指示物，则将一个平民指示物移动到绿魔反派面板区域。
static func _goblin_kidnap(game: Node) -> void:
	var vpos := _vpos(game)
	if game.state["locations"][vpos]["civ"] > 0:
		game.state["locations"][vpos]["civ"] -= 1
		game.state["goblin_panel_civ"] = int(game.state.get("goblin_panel_civ", 0)) + 1
		game._log("绑架：%s 的 1 个平民被移到绿魔面板（面板平民 %d）" % [game._loc_name(vpos), game.state["goblin_panel_civ"]], Color(1, 0.6, 0.4))
	else:
		game._log("绑架：绿魔所在地点没有平民可绑架", Color(0.8, 0.8, 0.8))

## 无赖：只要此行动正面朝上在故事情节中，绿魔获得 1 点额外生命值（只一次，可超上限），且 BAM! 额外造成 1 点伤害。
static func _goblin_scoundrel(game: Node) -> void:
	if not game.state.get("goblin_scoundrel_bonus", false):
		game.state["goblin_scoundrel_bonus"] = true
		game.state["villain_hp"] = int(game.state["villain_hp"]) + 1   # 可超过上限
		game._log("无赖！绿魔获得 1 点额外生命值（当前 %d）" % game.state["villain_hp"], Color(1, 0.7, 0.3))
	game.state["goblin_scoundrel_active"] = true

