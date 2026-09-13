class_name VillainRules
## 反派专属规则（与"基础规则"分离）。
## 这里只放"某一反派特有"的规则实现；通用的抽牌/移动/伤害/威胁等基础逻辑留在 Game 引擎。
## 新增反派 = 在这里新增对应 villian_id 的方法并注册到 dispatch，不改 Game 的通用循环。
##
## 设计约定：
##  - 不把反派规则写死进 Game 的通用函数（如 BAM/溢出/特殊效果）。
##  - 各反派方法互相独立，绝不跨角色复用彼此代码；相同逻辑各自实现。

# 反派 ID 列表（用于校验/迭代）
const IDS := ["redskull", "ultron", "taskmaster", "thanos", "proxima", "cull", "ebony", "kilmonger", "loki", "ronan", "goblin", "corvus", "vulture", "mysterio", "docock", "kraven", "sandman", "electro", "zemo", "modok"]


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
		"corvus":
			await _corvus_bam(game)
		"vulture":
			await _vulture_bam(game)
		"mysterio":
			await _mysterio_bam(game)
		"docock":
			await _docock_bam(game)
		"kraven":
			await _kraven_bam(game)
		"sandman":
			await _sandman_bam(game)
		"electro":
			await _electro_bam(game)
		"zemo":
			await _zemo_bam(game)
		"modok":
			await _modok_bam(game)
		_:
			pass


## 溢出特效入口：某个地点放不下指示物时，按反派处理。
## count = 本次"放置事件"在该地点放不下的指示物总数（默认 1）。
## 约定：卡面写"1 个或多个…"或未提数量的反派，无论 count 多少都**只结算一次**；
## 卡面明确按数量结算的（红骷髅/模仿大师/暗夜比邻星/罗南）才使用 count。
static func on_overflow(game: Node, villain_id: String, kind: String, loc: int, count: int = 1) -> void:
	match villain_id:
		"redskull":
			await _redskull_overflow(game, loc, count)
		"ultron":
			await _ultron_overflow(game, kind, loc)
		"taskmaster":
			await _taskmaster_overflow(game, loc, count)
		"thanos":
			await _thanos_overflow(game, loc)
		"proxima":
			await _proxima_overflow(game, kind, loc, count)
		"cull":
			await _cull_overflow(game, loc)
		"ebony":
			await _ebony_overflow(game, loc)
		"kilmonger":
			await _kilmonger_overflow(game, loc)
		"loki":
			await _loki_overflow(game)
		"ronan":
			await _ronan_overflow(game, kind, loc, count)
		"goblin":
			await _goblin_overflow(game, loc)
		"corvus":
			await _corvus_overflow(game, loc)
		"vulture":
			await _vulture_overflow(game, loc)
		"mysterio":
			await _mysterio_overflow(game, loc)
		"docock":
			await _docock_overflow(game, loc)
		"kraven":
			await _kraven_overflow(game, loc)
		"sandman":
			await _sandman_overflow(game, loc)
		"electro":
			await _electro_overflow(game, loc)
		"zemo":
			# 卡面为"1 个或多个…"→ 一次结算事件只结算一次（忽略 count）
			await _zemo_overflow(game, loc)
		"modok":
			# 面板为"1 个或多个…"→ 一次结算事件只翻转 1 张英雄卡（忽略 count）
			await _modok_overflow(game, loc)
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
	# 卡面：对**灭霸所在地点**的每个英雄造成 2 点伤害，然后对**两个相邻地点**的每个英雄各造成 1 点伤害。
	# ⚠️ 旧实现写成"凡是不在灭霸所在地点的英雄都受 1 点"→ 实际把整张地图都打了一遍（用户报的 bug）。
	#   现在按 _cull_bam 的既有写法：只遍历 _adjacent_locs(vpos)。
	#   _adjacent_locs 返回的是 Variant，循环变量必须 int(...) 包一下（备忘里记过的类型推断坑）。
	var vpos := _vpos(game)
	for hid in _heroes_at(game, vpos):
		await game._deal_damage_to_hero(hid, 2)
	for adj in game._adjacent_locs(vpos):
		for hid in _heroes_at(game, int(adj)):
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
		for adj in game._adjacent_locs(vpos):
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

static func _redskull_overflow(game: Node, loc: int, count: int = 1) -> void:
	game.state["fear"] = mini(game.state["fear"] + count, 20)
	game._log("溢出！%s 放不下 %d 个指示物，恐惧轨道 +%d（当前 %d）" % [game._loc_name(loc), count, count, game.state["fear"]], Color(0.9, 0.5, 0.5))


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


static func _taskmaster_overflow(game: Node, loc: int, count: int = 1) -> void:
	game.state["locations"][loc]["crisis"] += count
	game._log("溢出！改为在 %s 放置 %d 个危机指示物（当前 %d）" % [game._loc_name(loc), count, int(game.state["locations"][loc]["crisis"])], Color(0.7, 0.7, 1))


static func _thanos_overflow(game: Node, loc: int) -> void:
	if game.state["locations"][loc]["civ"] > 0:
		game.state["locations"][loc]["civ"] -= 1
		game.state["locations"][loc]["thug"] += 1
		game._log("溢出！%s 最左边的平民转换为暴徒" % game._loc_name(loc), Color(0.9, 0.6, 0.6))
	else:
		game.state["extra_villain_card"] += 1
		game._log("溢出！%s 无平民可转换，抽取一张反派行动卡" % game._loc_name(loc), Color(1, 0.6, 0.5))


static func _proxima_overflow(game: Node, kind: String, loc: int, count: int = 1) -> void:
	if kind == "thug":
		for hid in _heroes_at(game, loc):
			await game._deal_damage_to_hero(hid, 1)
		game._log("溢出！%s 的暴徒放不下，该地点英雄各受 1 点伤害" % game._loc_name(loc), Color(1, 0.6, 0.4))
	else:
		game.state["slaughter"] = mini(game.state["slaughter"] + count, 12)
		game._log("溢出！%s 有 %d 个平民放不下，屠宰轨道 +%d（当前 %d / 12）" % [game._loc_name(loc), count, count, game.state["slaughter"]], Color(0.9, 0.5, 0.5))


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
			await game._discard_civs_with_choice(game._adjacent_locs(vpos))
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
		"corvus_slaughter":
			await _corvus_slaughter(game)
		"corvus_blade":
			await _corvus_blade(game)
		"mysterio_hologram":
			await _mysterio_hologram(game)
		"mysterio_false_hero":
			await _mysterio_false_hero(game)
		"docock_master_plan":
			await _docock_master_plan(game)
		"docock_tentacle_grab":
			await _docock_tentacle_grab(game)
		"vulture_heist":
			_vulture_heist(game)
		"kraven_stalk":
			await _kraven_stalk(game)
		"sandman_harder":
			_sandman_harder(game)
		"sandman_better":
			await _sandman_better(game)
		"sandman_faster":
			await _sandman_faster(game)
		"sandman_stronger":
			await _sandman_stronger(game)
		"electro_vanish":
			_electro_vanish(game)
		"electro_blackout":
			_electro_blackout(game)
		"zemo_thunderbolt":
			await _zemo_thunderbolt(game)
		"zemo_civil_five":
			await _zemo_civil_five(game)
		"modok_preparation":
			await _modok_preparation(game)
		"modok_mind_transfer":
			_modok_mind_transfer(game)
		"modok_superior_intellect":
			_modok_superior_intellect(game)
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
	var targets: Array = [vpos] + game._adjacent_locs(vpos)
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
	var targets: Array = [vpos] + game._adjacent_locs(vpos)
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
	var targets: Array = [vpos] + game._adjacent_locs(vpos)
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
static func _ronan_overflow(game: Node, kind: String, loc: int, count: int = 1) -> void:
	var heroes_here: Array = _heroes_at(game, loc).filter(func(h): return not game.state["heroes"][h]["ko"])
	if heroes_here.size() == 0:
		game._log("溢出！%s 没有英雄可伤害" % game._loc_name(loc), Color(0.8, 0.8, 0.8))
		return
	for i in range(count):   # 每个放不下的指示物 = 1 次伤害结算
		var alive: Array = _heroes_at(game, loc).filter(func(h): return not game.state["heroes"][h]["ko"])
		if alive.size() == 0:
			return
		var labels: Array = []
		for hid in alive:
			labels.append(DB.hero_name(hid))
		var picked_idx: int = await game._ask("溢出！%s 放不下（%s，第 %d/%d 个），选择 1 名英雄受到 1 点伤害" % [game._loc_name(loc), "暴徒" if kind == "thug" else "平民", i + 1, count], labels)
		var hid: String = alive[wrapi(int(picked_idx), 0, alive.size())]
		await game._deal_damage_to_hero(hid, 1)
		game._log("溢出：%s 受到 1 点伤害" % DB.hero_name(hid), Color(1, 0.6, 0.4))
		if game.state["phase"] == "game_over":
			return

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

# ---------------------------------------------------------------- 亡刃将军 (Corvus Glaive)

## BAM：对亡刃将军所在地点的每个英雄造成 1 点伤害。
static func _corvus_bam(game: Node) -> void:
	var vpos := _vpos(game)
	for hid in _heroes_at(game, vpos):
		await game._deal_damage_to_hero(hid, 1)
	game._log("亡刃将军 BAM：%s 的每个英雄受到 1 点伤害" % game._loc_name(vpos), Color(1, 0.6, 0.3))

## 溢出：若指示物无法添加到某地点，则对该地点的每个英雄造成 1 点伤害。
static func _corvus_overflow(game: Node, loc: int) -> void:
	for hid in _heroes_at(game, loc):
		await game._deal_damage_to_hero(hid, 1)
	game._log("溢出：%s 的每个英雄受到 1 点伤害" % game._loc_name(loc), Color(1, 0.6, 0.4))

## 屠宰：顺时针移动到下一个有英雄的地点，对所在地点的每个英雄造成 1 点伤害。
static func _corvus_slaughter(game: Node) -> void:
	var found: bool = game._corvus_move_to_next_hero(false)
	var vpos := _vpos(game)
	if found:
		for hid in _heroes_at(game, vpos):
			await game._deal_damage_to_hero(hid, 1)
		game._log("屠宰！%s 的每个英雄受到 1 点伤害" % game._loc_name(vpos), Color(1, 0.6, 0.4))
	else:
		game._log("屠宰：未找到有英雄的地点", Color(1, 0.6, 0.4))

## 刀刃攻击：顺时针移动到下一个只有一个英雄的地点，并对其造成 2 点伤害；若无则对所有英雄造成 1 点伤害。
static func _corvus_blade(game: Node) -> void:
	var found: bool = game._corvus_move_to_next_hero(true)
	var vpos := _vpos(game)
	if found:
		var heroes: Array = _heroes_at(game, vpos)
		for hid in heroes:
			await game._deal_damage_to_hero(hid, 2)
		game._log("刀刃攻击：%s 的 %s 受到 2 点伤害" % [game._loc_name(vpos), DB.hero_name(heroes[0])], Color(1, 0.6, 0.4))
	else:
		# 没有"只有一个英雄"的地点 → 对所有英雄造成 1 点伤害（全场所有英雄）
		for hid in game.state["hero_ids"]:
			await game._deal_damage_to_hero(hid, 1)
		game._log("刀刃攻击：没有单英雄地点，所有英雄各受到 1 点伤害", Color(1, 0.6, 0.4))


# ---------------------------------------------------------------- 秃鹫 (Vulture，邪恶六人组)

## 战利品失败阈值：2/3/4 人 = 9/7/5（1 人按 2 人处理）
static func _vulture_loot_max(game: Node) -> int:
	var n: int = game.state["hero_ids"].size()
	if n >= 4:
		return 5
	elif n == 3:
		return 7
	return 9

## 收集战利品后检查英雄是否失败
static func _vulture_check_lose(game: Node) -> void:
	var need: int = _vulture_loot_max(game)
	var have: int = int(game.state.get("vulture_loot", 0))
	if have >= need:
		game._lose("秃鹫收集到 %d 个战利品（%d 人局需要 %d 个），英雄们失败了！" % [have, game.state["hero_ids"].size(), need])

## 收走某地点的 1 个战利品到反派面板（返回是否成功）
static func _vulture_take_loot(game: Node, loc: int) -> bool:
	var l: Dictionary = game.state["locations"][loc]
	if int(l["crisis"]) <= 0:
		return false
	l["crisis"] = int(l["crisis"]) - 1
	game.state["vulture_loot"] = int(game.state.get("vulture_loot", 0)) + 1
	game._log("🦅 秃鹫收走 %s 的 1 个战利品（共 %d）" % [game._loc_name(loc), game.state["vulture_loot"]], Color(1, 0.8, 0.4))
	_vulture_check_lose(game)
	return true

## BAM：将秃鹫所在地点的 1 个战利品收进面板，然后把该地点的所有英雄移到"对面地点"（相隔 3 格）。
## 该地点任意一名英雄可以受到 2 点伤害来防止此效果（玩家选择）。
static func _vulture_bam(game: Node) -> void:
	var vpos := _vpos(game)
	var here: Array = _heroes_at(game, vpos).filter(func(h): return not game.state["heroes"][h]["ko"])
	# 阻止：任意一名在场英雄受到 2 点伤害
	if here.size() > 0:
		var prevent: bool = await game._ask_confirm("秃鹫 BAM！：是否让该地点一名英雄受到 2 点伤害，来防止此效果？")
		if prevent:
			var who: String = here[0]
			if here.size() > 1:
				var labels: Array = []
				for h in here:
					labels.append(DB.hero_name(h))
				var idx: int = await game._ask("秃鹫 BAM！：选择承受 2 点伤害的英雄（阻止此效果）", labels)
				who = here[wrapi(int(idx), 0, here.size())]
			game._log("秃鹫 BAM！被 %s 以 2 点伤害阻止" % DB.hero_name(who), Color(0.8, 1, 0.8))
			await game._deal_damage_to_hero(who, 2)
			Events.emit_state_changed()
			return
	# 未被阻止：收 1 个战利品
	if not _vulture_take_loot(game, vpos):
		game._log("秃鹫 BAM！：%s 已无战利品可收" % game._loc_name(vpos), Color(0.8, 0.8, 0.8))
	# 该地点所有英雄移动到对面地点
	var opp: int = (vpos + 3) % int(game.LOCATION_COUNT)
	var moved := 0
	for hid in _heroes_at(game, vpos):
		if game.state["heroes"][hid]["ko"]:
			continue
		await game._set_hero_loc(hid, opp, "forced")   # A1：被吹飞也算"进入一个地点"（但不是自己移动）
		moved += 1
		game._log("%s 被吹飞到对面：%s" % [DB.hero_name(hid), game._loc_name(opp)], Color(0.8, 0.9, 1))
	if moved == 0:
		game._log("秃鹫 BAM！：%s 没有英雄需要移动" % game._loc_name(vpos), Color(0.8, 0.8, 0.8))
	Events.emit_state_changed()

## 溢出：平民/暴徒放不下时，该地点的 1 个战利品被收走
static func _vulture_overflow(game: Node, loc: int) -> void:
	if not _vulture_take_loot(game, loc):
		game._log("溢出！%s 已无战利品可收" % game._loc_name(loc), Color(0.8, 0.8, 0.8))

## 抢劫计划（行动卡 1-4）：如果这不是故事情节中第一张「抢劫计划」，
## 则将**每个没有英雄的地点**的 1 个危机指示物（战利品）移动到反派面板。
static func _vulture_heist(game: Node) -> void:
	# 判定"是不是故事情节里第一张抢劫计划"：数故事情节中已打出的抢劫计划行动卡
	# （当前这张已由 _run_villain_turn 写入故事情节，所以 >=2 表示"不是第一张"）
	var heist_idx: Array = [0, 1, 2, 3]   # villains.json 中带 vulture_heist 的卡序号
	var seen := 0
	for e in game.state["story"]:
		if e.get("type", "") == "villain" and int(e.get("idx", -1)) in heist_idx:
			seen += 1
	if seen <= 1:
		game._log("抢劫计划：这是故事情节中第一张抢劫计划卡，不收取战利品", Color(0.85, 0.85, 0.7))
		return
	var took := 0
	var empty_locs: Array = []
	for i in range(int(game.LOCATION_COUNT)):
		if game.state["locations"][i].get("destroyed", false):
			continue
		if _heroes_at(game, i).size() > 0:
			continue   # 有英雄的地点不结算
		empty_locs.append(i)
		if _vulture_take_loot(game, i):
			took += 1
	game._log("抢劫计划：%d 个无英雄地点共收走 %d 个战利品（共 %d）" % [empty_locs.size(), took, int(game.state.get("vulture_loot", 0))], Color(1, 0.75, 0.35))
	Events.emit_state_changed()

# ---------------------------------------------------------------- 神秘客 (Mysterio，邪恶六人组)

## BAM：将场上所有平民↔暴徒互换，然后在神秘客所在地点放置 1 个平民
static func _mysterio_bam(game: Node) -> void:
	var swapped := 0
	for i in range(int(game.LOCATION_COUNT)):
		var l: Dictionary = game.state["locations"][i]
		var civ: int = int(l["civ"])
		var thug: int = int(l["thug"])
		if civ == 0 and thug == 0:
			continue
		l["civ"] = thug
		l["thug"] = civ
		swapped += 1
	game._log("🔄 神秘客 BAM！：所有平民与暴徒互换（%d 个地点受影响）" % swapped, Color(0.8, 0.7, 1))
	var vpos := _vpos(game)
	await game._place_token_at("civ", vpos, 1)
	game._log("神秘客 BAM！：在 %s 放置 1 个平民" % game._loc_name(vpos), Color(0.9, 0.8, 1))

## 溢出：抽取一张反派行动卡背面朝上加入故事情节
static func _mysterio_overflow(game: Node, loc: int) -> void:
	if game.state["master_deck"].size() == 0:
		game._log("溢出！%s 放不下，但反派牌堆已空，无法抽牌" % game._loc_name(loc), Color(0.8, 0.8, 0.8))
		return
	var d: Variant = game.state["master_deck"].pop_front()
	game.state["story"].append({"type": "villain", "villain": game.state["villain"], "idx": d if d is int else -1, "move": 0, "face_down": true})
	game._log("溢出！%s 放不下指示物，神秘客抽取一张行动卡背面朝上加入故事情节" % game._loc_name(loc), Color(1, 0.7, 0.5))

## 全息投影：把场上所有威胁卡（清空其上指示物）混洗后，从神秘客所在地点开始顺时针背面朝上放置
static func _mysterio_hologram(game: Node) -> void:
	var cards: Array = []
	for i in range(int(game.LOCATION_COUNT)):
		var l: Dictionary = game.state["locations"][i]
		var t: Variant = l["threat"]
		if t == null:
			continue
		var td: Dictionary = t.duplicate(true)
		td["heroic_tokens"] = 0
		td["clear_progress"] = []
		td["arrival_triggered"] = false
		td["_face_down"] = true
		td["_bam_done"] = false
		cards.append(td)
		l["threat"] = null
	cards.shuffle()
	var vpos := _vpos(game)
	var placed := 0
	var live: Array = game._live_locs()
	var vpos_i: int = live.find(vpos)
	if vpos_i == -1:
		vpos_i = 0
	for k in range(cards.size()):
		if k >= live.size():
			break
		var loc: int = int(live[(vpos_i + k) % live.size()])
		game.state["locations"][loc]["threat"] = cards[k]
		placed += 1
	game._log("🎭 全息投影：%d 张威胁卡被混洗后背面朝上重新放置（从 %s 开始顺时针）" % [placed, game._loc_name(vpos)], Color(0.8, 0.8, 1))
	Events.emit_state_changed()

## 虚假英雄行径：移动到平民最多的地点，弃掉该地点所有平民/暴徒，然后抽一张行动卡背面朝上放进故事情节
static func _mysterio_false_hero(game: Node) -> void:
	var best := -1
	var best_civ := -1
	for i in range(int(game.LOCATION_COUNT)):
		if game.state["locations"][i].get("destroyed", false):
			continue   # 被摧毁地点不参与"平民最多"的判定
		var civ: int = int(game.state["locations"][i]["civ"])
		if civ > best_civ:
			best_civ = civ
			best = i
	if best >= 0:
		game.state["villain_pos"] = best
		game._log("🎭 虚假英雄行径：神秘客移动到平民最多的地点 %s（%d 个平民）" % [game._loc_name(best), best_civ], Color(0.9, 0.7, 1))
	var l: Dictionary = game.state["locations"][game.state["villain_pos"]]
	var discarded: int = int(l["civ"]) + int(l["thug"])
	l["civ"] = 0
	l["thug"] = 0
	game._log("🎭 虚假英雄行径：弃掉 %s 的所有平民/暴徒（共 %d 个）" % [game._loc_name(game.state["villain_pos"]), discarded], Color(0.9, 0.7, 1))
	if game.state["master_deck"].size() > 0:
		var d: Variant = game.state["master_deck"].pop_front()
		game.state["story"].append({"type": "villain", "villain": game.state["villain"], "idx": d if d is int else -1, "move": 0, "face_down": true})
		game._log("🎭 虚假英雄行径：抽取一张行动卡背面朝上加入故事情节", Color(0.9, 0.8, 1))
	else:
		game._log("🎭 虚假英雄行径：反派牌堆已空，无法抽牌", Color(0.8, 0.8, 0.8))
	Events.emit_state_changed()

# ---------------------------------------------------------------- 章鱼博士 (Doctor Octopus，邪恶六人组)

## BAM：章鱼博士所在地点每个英雄受 1 点伤害，并在该地点放置 1 个危机指示物；随后检查地点摧毁
static func _docock_bam(game: Node) -> void:
	var vpos := _vpos(game)
	for hid in _heroes_at(game, vpos):
		await game._deal_damage_to_hero(hid, 1)
	var l: Dictionary = game.state["locations"][vpos]
	l["crisis"] = int(l["crisis"]) + 1
	game._log("🐙 章鱼博士 BAM：在 %s 放置 1 个危机指示物（当前 %d）" % [game._loc_name(vpos), int(l["crisis"])], Color(0.9, 0.6, 0.6))
	Events.emit_state_changed()
	await game._docock_check_destroy()

## 溢出：该地点添加 1 个危机指示物，随后检查地点摧毁
static func _docock_overflow(game: Node, loc: int) -> void:
	var l: Dictionary = game.state["locations"][loc]
	l["crisis"] = int(l["crisis"]) + 1
	game._log("溢出！%s 放不下指示物，改为添加 1 个危机指示物（当前 %d）" % [game._loc_name(loc), int(l["crisis"])], Color(1, 0.7, 0.5))
	Events.emit_state_changed()
	await game._docock_check_destroy()

## 总规划师（行动卡 2-3）：在"拥有危机指示物"地点的每个英雄各受 1 点伤害；
## 然后在章鱼博士所在地点添加 1 个危机指示物（随后照常检查地点摧毁）。
static func _docock_master_plan(game: Node) -> void:
	var hit := 0
	for hid in game.state["hero_ids"]:
		if game.state["heroes"][hid]["ko"]:
			continue
		var hl: int = int(game.state["heroes"][hid]["location"])
		if int(game.state["locations"][hl]["crisis"]) > 0:
			game._log("🐙 总规划师：%s 所在的 %s 有危机指示物，受到 1 点伤害" % [DB.hero_name(hid), game._loc_name(hl)], Color(1, 0.6, 0.4))
			await game._deal_damage_to_hero(hid, 1)
			hit += 1
			if game.state["phase"] == "game_over":
				return
	if hit == 0:
		game._log("🐙 总规划师：没有英雄在拥有危机指示物的地点", Color(0.8, 0.8, 0.8))
	var vpos := _vpos(game)
	var l: Dictionary = game.state["locations"][vpos]
	if l.get("destroyed", false):
		game._log("🐙 总规划师：章鱼博士所在地点已被摧毁，不放置危机指示物", Color(0.8, 0.8, 0.8))
		return
	l["crisis"] = int(l["crisis"]) + 1
	game._log("🐙 总规划师：在 %s 添加 1 个危机指示物（当前 %d）" % [game._loc_name(vpos), int(l["crisis"])], Color(0.9, 0.6, 0.6))
	Events.emit_state_changed()
	await game._docock_check_destroy()

## 触手抓握（行动卡 4-5）：将所有英雄朝章鱼博士移动一个地点（就近原则），然后触发一次 BAM！
static func _docock_tentacle_grab(game: Node) -> void:
	var vpos := _vpos(game)
	var moved := 0
	for hid in game.state["hero_ids"]:
		if game.state["heroes"][hid]["ko"]:
			continue
		var hl: int = int(game.state["heroes"][hid]["location"])
		if hl == vpos:
			continue   # 已在章鱼博士所在地点
		var adj: Array = game._adjacent_locs(hl)
		if adj.size() == 0:
			continue
		var best: int = int(adj[0])
		var best_d: int = game._live_ring_dist(best, vpos)
		for a in adj:
			var d: int = game._live_ring_dist(int(a), vpos)
			if d < best_d:
				best = int(a)
				best_d = d
		await game._set_hero_loc(hid, best, "forced")   # A1：被拉走也算"进入一个地点"（但不是自己移动）
		moved += 1
		game._log("🐙 触手抓握：%s 被拉向章鱼博士（%s → %s）" % [DB.hero_name(hid), game._loc_name(hl), game._loc_name(best)], Color(0.9, 0.7, 1))
	Events.emit_state_changed()
	if moved == 0:
		game._log("🐙 触手抓握：没有英雄需要移动", Color(0.8, 0.8, 0.8))
	if game.state["phase"] == "game_over":
		return
	await game._trigger_full_bam()   # 然后 BAM！


# ---------------------------------------------------------------- 猎人克莱文 (Kraven the Hunter，邪恶六人组)

## BAM：克莱文所在地点 1 名英雄受 1 点伤害；此外，一名"拥有危机指示物"的英雄受到等于其危机指示物数量的伤害
static func _kraven_bam(game: Node) -> void:
	var vpos: int = _vpos(game)
	var here: Array = _heroes_at(game, vpos).filter(func(h): return not game.state["heroes"][h]["ko"])
	if here.size() > 0:
		var who: String = here[0]
		if here.size() > 1:
			var labels: Array = []
			for h in here:
				labels.append(DB.hero_name(h))
			var idx: int = await game._ask("猎人克莱文 BAM！：选择受到 1 点伤害的英雄", labels)
			who = here[wrapi(int(idx), 0, here.size())]
		game._log("🦁 克莱文 BAM！：%s 受到 1 点伤害" % DB.hero_name(who), Color(1, 0.6, 0.4))
		await game._deal_damage_to_hero(who, 1)
		if game.state["phase"] == "game_over":
			return
	else:
		game._log("🦁 克莱文 BAM！：%s 没有英雄" % game._loc_name(vpos), Color(0.8, 0.8, 0.8))
	# 拥有危机指示物的英雄：受到等于其危机指示物数量的伤害（多名时由玩家选一人）
	var with_crisis: Array = []
	for hid in game.state["hero_ids"]:
		if game.state["heroes"][hid]["ko"]:
			continue
		if int(game.state["heroes"][hid].get("crisis", 0)) > 0:
			with_crisis.append(hid)
	if with_crisis.size() == 0:
		game._log("🦁 克莱文 BAM！：没有英雄持有危机指示物", Color(0.8, 0.8, 0.8))
		Events.emit_state_changed()
		return
	var target: String = with_crisis[0]
	if with_crisis.size() > 1:
		var labels2: Array = []
		for h in with_crisis:
			labels2.append("%s（危机 %d）" % [DB.hero_name(h), int(game.state["heroes"][h]["crisis"])])
		var idx2: int = await game._ask("猎人克莱文 BAM！：选择受到危机指示物伤害的英雄", labels2)
		target = with_crisis[wrapi(int(idx2), 0, with_crisis.size())]
	var n: int = int(game.state["heroes"][target]["crisis"])
	game._log("🦁 克莱文 BAM！：%s 持有 %d 个危机指示物，受到 %d 点伤害" % [DB.hero_name(target), n, n], Color(1, 0.5, 0.4))
	await game._deal_damage_to_hero(target, n)
	Events.emit_state_changed()

## 溢出：玩家必须选择一名英雄受到 1 点伤害
static func _kraven_overflow(game: Node, loc: int) -> void:
	var alive: Array = []
	for hid in game.state["hero_ids"]:
		if not game.state["heroes"][hid]["ko"]:
			alive.append(hid)
	if alive.size() == 0:
		return
	var who: String = alive[0]
	if alive.size() > 1:
		var labels: Array = []
		for h in alive:
			labels.append(DB.hero_name(h))
		var idx: int = await game._ask("溢出！选择一名英雄受到 1 点伤害", labels)
		who = alive[wrapi(int(idx), 0, alive.size())]
	game._log("溢出！%s 放不下指示物，%s 受到 1 点伤害" % [game._loc_name(loc), DB.hero_name(who)], Color(1, 0.6, 0.4))
	await game._deal_damage_to_hero(who, 1)
	Events.emit_state_changed()

## 顽固的狩猎：克莱文所在地点的 1 名英雄获得 1 个危机指示物，然后触发一次 BAM！
static func _kraven_stalk(game: Node) -> void:
	var vpos: int = _vpos(game)
	var here: Array = _heroes_at(game, vpos).filter(func(h): return not game.state["heroes"][h]["ko"])
	if here.size() == 0:
		game._log("顽固的狩猎：%s 没有英雄，跳过" % game._loc_name(vpos), Color(0.8, 0.8, 0.8))
		return
	var who: String = here[0]
	if here.size() > 1:
		var labels: Array = []
		for h in here:
			labels.append(DB.hero_name(h))
		var idx: int = await game._ask("顽固的狩猎：选择获得 1 个危机指示物的英雄", labels)
		who = here[wrapi(int(idx), 0, here.size())]
	game.state["heroes"][who]["crisis"] = int(game.state["heroes"][who].get("crisis", 0)) + 1
	game._log("🎯 顽固的狩猎：%s 获得 1 个危机指示物（共 %d）" % [DB.hero_name(who), int(game.state["heroes"][who]["crisis"])], Color(0.9, 0.7, 1))
	Events.emit_state_changed()
	if game.state["phase"] == "game_over":
		return
	await game._trigger_full_bam()   # 然后触发一次 BAM！


# ---------------------------------------------------------------- 沙人 (Sandman，邪恶六人组)

## 沙人获得生命值（可以超过生命值上限）
static func _sandman_gain_hp(game: Node, n: int) -> void:
	game.state["villain_hp"] = int(game.state["villain_hp"]) + n
	game._log("🏖 沙人获得 %d 点生命值（当前 %d，可超过上限 %d）" % [n, int(game.state["villain_hp"]), int(game.state["villain_hp_max"])], Color(1, 0.8, 0.4))
	Events.emit_state_changed()
	game._check_lose()

## BAM：沙人获得 2 点生命值，并对沙人所在地点的每个英雄造成 1 点伤害
static func _sandman_bam(game: Node) -> void:
	_sandman_gain_hp(game, 2)
	if game.state["phase"] == "game_over":
		return
	var vpos: int = _vpos(game)
	for hid in _heroes_at(game, vpos):
		await game._deal_damage_to_hero(hid, 1)
		if game.state["phase"] == "game_over":
			return
	Events.emit_state_changed()

## 溢出：沙人获得 2 点生命值
static func _sandman_overflow(game: Node, loc: int) -> void:
	game._log("溢出！%s 放不下指示物，沙人获得 2 点生命值" % game._loc_name(loc), Color(1, 0.7, 0.5))
	_sandman_gain_hp(game, 2)

## 更难：从现在开始沙人不会受到任何伤害，直到所有「沙尘暴」威胁卡都被清除
static func _sandman_harder(game: Node) -> void:
	game.state["sandman_hard"] = true
	game._log("🏖 更难：沙人从现在起不会受到任何伤害，直到所有「沙尘暴」威胁卡都被清除", Color(1, 0.7, 0.5))

## 更好：对两个相邻地点的每个英雄造成 1 点伤害
static func _sandman_better(game: Node) -> void:
	var vpos: int = _vpos(game)
	for loc in game._adjacent_locs(vpos):
		for hid in _heroes_at(game, loc):
			await game._deal_damage_to_hero(hid, 1)
			if game.state["phase"] == "game_over":
				return
	Events.emit_state_changed()

## 更快：沙人所在地点的每个英雄受到 1 点伤害
static func _sandman_faster(game: Node) -> void:
	for hid in _heroes_at(game, _vpos(game)):
		await game._deal_damage_to_hero(hid, 1)
		if game.state["phase"] == "game_over":
			return
	Events.emit_state_changed()

## 更强：丢弃沙人所在地点威胁卡上的所有行动指示物，每丢弃 1 个，每个英雄受到 1 点伤害
static func _sandman_stronger(game: Node) -> void:
	var vpos: int = _vpos(game)
	var t: Variant = game.state["locations"][vpos]["threat"]
	var dropped := 0
	if t != null:
		dropped = int(t.get("heroic_tokens", 0))
		if t.has("clear_progress"):
			var cp: Array = t["clear_progress"]
			dropped += cp.size()
			t["clear_progress"] = []
		t["heroic_tokens"] = 0
	game._log("🏖 更强：从 %s 的威胁卡上丢弃 %d 个行动指示物" % [game._loc_name(vpos), dropped], Color(1, 0.7, 0.4))
	for i in range(dropped):
		for hid in game.state["hero_ids"]:
			await game._deal_damage_to_hero(hid, 1)
			if game.state["phase"] == "game_over":
				return
	Events.emit_state_changed()


# ---------------------------------------------------------------- 电光人 (Electro，邪恶六人组)

## BAM：对电光人所在地点的**对面地点**，以及**电光人所在地点的两个相邻地点**，每个英雄各 1 点伤害
## （注意：相邻的两个地点是"电光人所在地点"的邻居，不是"对面地点"的邻居）
static func _electro_bam(game: Node) -> void:
	var vpos: int = _vpos(game)
	var n: int = int(game.LOCATION_COUNT)
	var opp: int = (vpos + 3) % n          # 对面地点（与秃鹫"对面"口径一致：相隔 3 格）
	var targets: Array = [opp]
	for loc in game._adjacent_locs(vpos):   # 电光人所在地点的两个相邻地点
		targets.append(loc)
	game._log("⚡ 电光人 BAM！：对面地点 %s + 电光人所在 %s 的相邻两地点，每个英雄各 1 点伤害"
		% [game._loc_name(opp), game._loc_name(vpos)], Color(1, 0.6, 0.4))
	for hid in game.state["hero_ids"]:
		if game.state["heroes"][hid]["ko"]:
			continue
		if targets.has(int(game.state["heroes"][hid]["location"])):
			await game._deal_damage_to_hero(hid, 1)
			if game.state["phase"] == "game_over":
				return
	Events.emit_state_changed()

## 溢出：在该地点添加 1 个危机指示物（受"同地点不能重复"的顺时针转移规则影响）
static func _electro_overflow(game: Node, loc: int) -> void:
	game._log("溢出！%s 放不下指示物，改为放置 1 个危机指示物" % game._loc_name(loc), Color(1, 0.7, 0.5))
	game._electro_add_crisis(loc)

## 消失：电光人不能受到任何伤害，直到每个英雄都在这张行动卡之后打出一张牌
static func _electro_vanish(game: Node) -> void:
	game.state["electro_vanish"] = true
	game.state["electro_vanish_story"] = game.state["story"].size()
	game._log("⚡ 消失：电光人不会受到任何伤害，直到每个英雄都在这张行动卡之后打出一张牌", Color(0.8, 0.9, 1))

## 停电：在电光人所在地点放置 1 个危机指示物
static func _electro_blackout(game: Node) -> void:
	game._log("⚡ 停电：在电光人所在地点放置 1 个危机指示物", Color(1, 0.85, 0.4))
	game._electro_add_crisis(_vpos(game))


# ---------------------------------------------------------------- 泽莫男爵 (Baron Zemo，第一季众筹)

## 裁定④：从 loc 起**顺时针**找到第一批有英雄的地点（含 loc 自身），返回该地点的英雄 id 列表。
## - 已 KO 的英雄不算"有英雄"（KO 英雄下回合才复活，无法承接指示物）。
## - 返回空数组 = 场上没有任何未 KO 的英雄。
static func _zemo_candidates(game: Node, loc: int) -> Array:
	var n: int = int(game.LOCATION_COUNT)
	for step in range(n):
		var i: int = (loc + step) % n
		var here: Array = _heroes_at(game, i).filter(func(h): return not game.state["heroes"][h]["ko"])
		if here.size() > 0:
			return here
	return []

## 裁定④：把 1 个危机指示物交给"离 from_loc 最近的英雄"（顺时针第一批；平手由玩家选择）。
static func _zemo_crisis_to_nearest(game: Node, from_loc: int, why: String) -> void:
	var cand: Array = _zemo_candidates(game, from_loc)
	if cand.size() == 0:
		game._log("%s：场上没有英雄，危机指示物无处放置" % why, Color(0.8, 0.8, 0.8))
		return
	var hid: String = String(cand[0])
	if cand.size() > 1:
		# 平手（同一地点上有多名英雄）：由玩家选择
		hid = String(cand[await game._ask_pick_hero("%s：距离最近的英雄不止一位，选择由谁获得 1 个危机指示物" % why, cand)])
	game.state["heroes"][hid]["crisis"] = int(game.state["heroes"][hid]["crisis"]) + 1
	game._log("%s：%s 获得 1 个危机指示物（现有 %d 个）"
		% [why, DB.hero_name(hid), int(game.state["heroes"][hid]["crisis"])], Color(0.8, 0.6, 1))

## BAM！：① 对泽莫男爵所在地点的 1 名英雄造成 1 点伤害（玩家选择）；
##        ② 离泽莫男爵最近的英雄获得 1 个危机指示物（顺时针，含所在地点；平手由玩家选择）。
static func _zemo_bam(game: Node) -> void:
	var vpos: int = _vpos(game)
	var here: Array = _heroes_at(game, vpos).filter(func(h): return not game.state["heroes"][h]["ko"])
	if here.size() == 0:
		game._log("泽莫男爵 BAM：%s 没有英雄，本段不造成伤害" % game._loc_name(vpos), Color(0.8, 0.8, 0.8))
	else:
		var target: String = String(here[0])
		if here.size() > 1:
			target = String(here[await game._ask_pick_hero(
				"泽莫男爵 BAM：%s 的哪名英雄受到 1 点伤害？" % game._loc_name(vpos), here)])
		await game._deal_damage_to_hero(target, 1)
	if game.state["phase"] == "game_over":
		return
	_zemo_crisis_to_nearest(game, vpos, "泽莫男爵 BAM")
	Events.emit_state_changed()

## 溢出：离"放不下的那个地点"最近的英雄获得 1 个危机指示物（顺时针；平手由玩家选择）。
## 卡面写"1 个或多个…"→ 一次结算事件只结算一次，与 count 无关。
static func _zemo_overflow(game: Node, loc: int) -> void:
	game._log("溢出！%s 放不下指示物" % game._loc_name(loc), Color(1, 0.7, 0.5))
	_zemo_crisis_to_nearest(game, loc, "泽莫男爵溢出")
	Events.emit_state_changed()

## 行动卡 1/2「雷电！」：在泽莫男爵所在地点放置 3 个暴徒，然后 BAM！
## （"然后 BAM！"与翻出带 BAM 的行动卡口径一致 = 面板 BAM + 场上所有威胁卡 BAM）
static func _zemo_thunderbolt(game: Node) -> void:
	var vpos: int = _vpos(game)
	game._log("雷电！：在 %s 放置 3 个暴徒，然后 BAM！" % game._loc_name(vpos), Color(1, 0.8, 0.4))
	await game._place_token_at("thug", vpos, 3)
	if game.state["phase"] == "game_over":
		return
	await game._trigger_full_bam()

## 行动卡 3/4「公民五」：顺时针移动到拥有最多平民指示物的地点；随后丢弃泽莫男爵所在地点
## 所有的平民和暴徒指示物。
## 解释：若场上任何地点都没有平民，则"没有拥有平民的地点"，泽莫男爵不移动（仍结算丢弃）。
static func _zemo_civil_five(game: Node) -> void:
	var n: int = int(game.LOCATION_COUNT)
	var vpos: int = _vpos(game)
	var best: int = -1
	var best_civ: int = 0
	# 从当前位置起顺时针扫描：取平民最多的地点；数量相同则取"顺时针先遇到"的那个
	for step in range(n):
		var i: int = (vpos + step) % n
		var c: int = int(game.state["locations"][i]["civ"])
		if c > best_civ:
			best_civ = c
			best = i
	if best < 0:
		game._log("公民五：场上没有平民，泽莫男爵不移动", Color(0.9, 0.8, 0.6))
	else:
		game.state["villain_pos"] = best
		game._log("公民五：泽莫男爵顺时针移动到 %s（平民最多的地点，%d 个）"
			% [game._loc_name(best), best_civ], Color(1, 0.8, 0.4))
	var l: Dictionary = game.state["locations"][int(game.state["villain_pos"])]
	var dc: int = int(l["civ"])
	var dt: int = int(l["thug"])
	l["civ"] = 0
	l["thug"] = 0
	game._log("公民五：丢弃 %s 的 %d 个平民与 %d 个暴徒"
		% [game._loc_name(int(game.state["villain_pos"])), dc, dt], Color(0.9, 0.7, 0.6))
	Events.emit_state_changed()

## 威胁卡 BAM 入口（6 张威胁卡的 BAM 各不同；由 Game._trigger_all_threat_bam 按卡名分发到此处）
static func _zemo_threat_bam(game: Node, tname: String, loc: int) -> void:
	match tname:
		"修理师":
			# BAM!：从本地点丢弃 1 个平民
			var lf: Dictionary = game.state["locations"][loc]
			if int(lf["civ"]) > 0:
				lf["civ"] = int(lf["civ"]) - 1
				game._log("修理师：从 %s 丢弃 1 个平民（剩余 %d）"
					% [game._loc_name(loc), int(lf["civ"])], Color(1, 0.6, 0.4))
			else:
				game._log("修理师：%s 没有平民可丢弃" % game._loc_name(loc), Color(0.8, 0.8, 0.8))
		"甲虫":
			# BAM!：从本地点丢弃 1 个暴徒
			var lb: Dictionary = game.state["locations"][loc]
			if int(lb["thug"]) > 0:
				lb["thug"] = int(lb["thug"]) - 1
				game._log("甲虫：从 %s 丢弃 1 个暴徒（剩余 %d）"
					% [game._loc_name(loc), int(lb["thug"])], Color(1, 0.6, 0.4))
			else:
				game._log("甲虫：%s 没有暴徒可丢弃" % game._loc_name(loc), Color(0.8, 0.8, 0.8))
		"尖叫咪咪":
			# BAM!：对相邻地点的每位英雄造成 1 点伤害
			for adj in game._adjacent_locs(loc):
				var hs: Array = _heroes_at(game, int(adj)).filter(func(h): return not game.state["heroes"][h]["ko"])
				for hid in hs:
					game._log("尖叫咪咪：%s 在相邻地点 %s 受到 1 点伤害"
						% [DB.hero_name(String(hid)), game._loc_name(int(adj))], Color(1, 0.6, 0.4))
					await game._deal_damage_to_hero(String(hid), 1)
					if game.state["phase"] == "game_over":
						return
		"月石":
			# BAM!：对本地点每位英雄造成 2 点伤害，对相邻地点每位英雄造成 1 点伤害
			for hid in _heroes_at(game, loc).filter(func(h): return not game.state["heroes"][h]["ko"]):
				await game._deal_damage_to_hero(String(hid), 2)
				if game.state["phase"] == "game_over":
					return
			for adj in game._adjacent_locs(loc):
				for hid in _heroes_at(game, int(adj)).filter(func(h): return not game.state["heroes"][h]["ko"]):
					await game._deal_damage_to_hero(String(hid), 1)
					if game.state["phase"] == "game_over":
						return
		"歌利亚":
			# BAM!：对本地点 1 名英雄造成 2 点伤害（玩家选择）
			var hg: Array = _heroes_at(game, loc).filter(func(h): return not game.state["heroes"][h]["ko"])
			if hg.size() == 0:
				game._log("歌利亚：%s 没有英雄" % game._loc_name(loc), Color(0.8, 0.8, 0.8))
			else:
				var tg: String = String(hg[0])
				if hg.size() > 1:
					tg = String(hg[await game._ask_pick_hero(
						"歌利亚 BAM：%s 的哪名英雄受到 2 点伤害？" % game._loc_name(loc), hg)])
				await game._deal_damage_to_hero(tg, 2)
		_:
			pass
	Events.emit_state_changed()


# ---------------------------------------------------------------- 摩多克 (M.O.D.O.K.，第一季众筹)
#
# 卡面/面板口径（12 张行动卡 + 6 张威胁卡 + 面板全部逐张读图核对，见 反派_摩多克_交接.md）：
#   面板 生命值 2/3/4 人 = 4/7/10；
#   面板 特别规则：摩多克翻转英雄卡时，把**故事情节中最靠前的正面朝上的英雄行动卡**翻成正面朝下
#                  （面朝下的卡视为空白）；BAM! = 翻转 1 张英雄卡；
#   面板 溢出效果：1 个或多个平民/暴徒放不下 → 翻转 1 张英雄卡；
#   面板 恶毒的阴谋：故事情节中所有英雄卡都面朝下 → 英雄失败。

## 摩多克核心机制：翻转 n 张英雄卡。
## 面板特别规则：每次翻转的目标都是"最接近故事情节开始的正面朝上的英雄行动卡"
## （story 数组下标 0 一侧 = 故事情节开始；正面朝下的卡会被跳过，所以翻转是"从最早往后推进"）。
## 返回实际翻面的张数（故事情节里已没有正面朝上的英雄卡时不足 n）。
static func _modok_flip_hero_cards(game: Node, count: int, why: String) -> int:
	var done := 0
	for _k in range(maxi(count, 0)):
		var target := -1
		for i in range(game.state["story"].size()):
			var e: Dictionary = game.state["story"][i]
			if String(e.get("type", "")) != "hero":
				continue
			if bool(e.get("face_down", false)):
				continue
			target = i
			break
		if target < 0:
			break
		var te: Dictionary = game.state["story"][target]
		te["face_down"] = true
		done += 1
		game._log("%s：把故事情节中最靠前的正面朝上英雄卡（%s 的第 %d 张）翻为正面朝下"
			% [why, DB.hero_name(String(te.get("hero", ""))), int(te.get("idx", -1)) + 1], Color(1, 0.5, 0.7))
	if done < count:
		game._log("%s：故事情节中已没有正面朝上的英雄卡（要求翻转 %d 张，实际 %d 张）"
			% [why, count, done], Color(0.8, 0.8, 0.8))
	return done


## 面板"恶毒的阴谋"判据：故事情节里**存在**英雄卡，且它们全部面朝下。
## （没有任何英雄卡时不算失败，避免开局误判。）
static func _modok_all_story_heroes_face_down(game: Node) -> bool:
	var any := false
	for e in game.state.get("story", []):
		if String(e.get("type", "")) != "hero":
			continue
		any = true
		if not bool(e.get("face_down", false)):
			return false
	return any


## 故事情节中"正面朝上、且 effect.type == etype"的反派行动卡张数。
## 摩多克「意识转移」用：只要它还正面朝上在故事情节里，反派 BAM！之后就多翻转英雄卡。
static func _modok_faceup_effect_count(game: Node, etype: String) -> int:
	var n := 0
	if String(game.state.get("villain", "")) != "modok":
		return 0
	var acts: Array = DB.villain("modok")["actions"]
	for e in game.state.get("story", []):
		if String(e.get("type", "")) != "villain":
			continue
		if bool(e.get("face_down", false)):
			continue
		var idx := int(e.get("idx", -1))
		if idx < 0 or idx >= acts.size():
			continue
		var eff: Variant = (acts[idx] as Dictionary).get("effect", null)
		if eff == null:
			continue
		if String((eff as Dictionary).get("type", "")) == etype:
			n += 1
	return n


## 故事情节中"最近 n 张英雄卡"底部印刷 sym 符号的总数。
## 与 Game._count_recent_story_symbols 的差别：**面朝下的英雄卡也算一张**（面板：面朝下的卡视为空白，
## 即占位但不贡献任何符号）。变色龙 / 斑点的 BAM 按此口径取数。
static func _modok_recent_icon_count(game: Node, sym: String, n: int) -> int:
	var total := 0
	var found := 0
	for i in range(game.state["story"].size() - 1, -1, -1):
		var e: Dictionary = game.state["story"][i]
		if String(e.get("type", "")) != "hero":
			continue
		found += 1
		if not bool(e.get("face_down", false)):
			var hid := String(e.get("hero", ""))
			var idx := int(e.get("idx", -1))
			if DB.heroes.has(hid):
				var cards: Array = DB.hero_cards(hid)
				if idx >= 0 and idx < cards.size():
					for s in (cards[idx]["symbols"] as Array):
						if String(s) == sym:
							total += 1
		if found >= n:
			break
	return total


## BAM！：翻转 1 张英雄卡。
## 追加（行动卡 10/11「意识转移」）：只要它在故事情节中正面朝上，反派 BAM！之后再翻转 1 张英雄卡。
## 口径：故事情节里有 k 张正面朝上的「意识转移」就多翻转 k 张（每张各说"翻转一张"）。
static func _modok_bam(game: Node) -> void:
	var vpos: int = _vpos(game)
	game._log("摩多克 BAM：翻转 1 张英雄卡（%s）" % game._loc_name(vpos), Color(1, 0.6, 0.4))
	_modok_flip_hero_cards(game, 1, "摩多克 BAM")
	if game.state["phase"] == "game_over":
		return
	var extra: int = _modok_faceup_effect_count(game, "modok_mind_transfer")
	if extra > 0:
		game._log("意识转移：故事情节中有 %d 张「意识转移」正面朝上，BAM！之后再翻转 %d 张英雄卡"
			% [extra, extra], Color(1, 0.7, 0.9))
		_modok_flip_hero_cards(game, extra, "意识转移")
	Events.emit_state_changed()


## 溢出：1 个或多个平民/暴徒放不下 → 翻转 1 张英雄卡（面板写"1 个或多个"→ 只结算一次，与 count 无关）。
static func _modok_overflow(game: Node, loc: int) -> void:
	game._log("溢出！%s 放不下指示物，摩多克翻转 1 张英雄卡" % game._loc_name(loc), Color(1, 0.7, 0.5))
	_modok_flip_hero_cards(game, 1, "摩多克溢出")
	Events.emit_state_changed()


## 行动卡 1「制备」（特殊设置：本卡必定是摩多克打出的第一张行动卡）：
## 将摩多克移动到英雄的起始地点（setup 时记录的 hero_start_loc = 反派初始地点的正对面）。
static func _modok_preparation(game: Node) -> void:
	var n: int = int(game.LOCATION_COUNT)
	var start: int = int(game.state.get("hero_start_loc", (_vpos(game) + 3) % n))
	if start < 0 or start >= n or game.state["locations"][start].get("destroyed", false):
		game._log("制备：英雄起始地点不可用，摩多克停留原地", Color(0.9, 0.8, 0.6))
		return
	game.state["villain_pos"] = start
	game._log("制备：摩多克移动到英雄的起始地点 %s" % game._loc_name(start), Color(1, 0.8, 0.4))
	Events.emit_state_changed()


## 行动卡 10/11「意识转移」：被动持续效果（只要此卡正面朝上在故事情节中，
## 反派 BAM！之后翻转 1 张英雄卡）。打出时不立刻结算，真正生效点写在本文件的 _modok_bam 里。
static func _modok_mind_transfer(game: Node) -> void:
	game._log("意识转移：本卡正面朝上留在故事情节期间持续生效（反派 BAM！之后额外翻转 1 张英雄卡）",
		Color(1, 0.7, 0.9))


## 行动卡 12「超级天才智能」：下一个反派回合多打出 1 张反派行动卡。
## 用引擎的通用延迟键（Game._run_villain_turn 开头读取并清零）——若直接改 extra_villain_card，
## 会在**本回合**结尾被 pending 立刻消费掉（那就变成"本回合"而不是"下一个回合"）。
static func _modok_superior_intellect(game: Node) -> void:
	game.state["villain_extra_card_next_turn"] = int(game.state.get("villain_extra_card_next_turn", 0)) + 1
	game._log("超级天才智能：下一个反派回合摩多克将多打出 1 张行动卡", Color(1, 0.7, 0.5))
	Events.emit_state_changed()


## 威胁卡"到达地点效果"入口（能量投射 / 科技共情；由 Game._trigger_threat_arrival 按卡名分发）。
static func _modok_threat_arrival(game: Node, tname: String, loc: int) -> void:
	match tname:
		"能量投射":
			# 到达地点效果：翻转 1 张英雄卡
			game._log("能量投射：翻转 1 张英雄卡", Color(1, 0.6, 0.4))
			_modok_flip_hero_cards(game, 1, "能量投射")
		"科技共情":
			# 到达地点效果：英雄失去所有的行动指示物；英雄可以选择翻转 2 张英雄卡来避免失去。
			# 口径：逐个（未 KO 的、且身上还有行动指示物的）英雄单独询问，各自决定。
			for hid in game.state["hero_ids"]:
				var h: Dictionary = game.state["heroes"][hid]
				if bool(h["ko"]):
					continue
				var pool: Dictionary = h["tokens"]
				var total := 0
				for k in ["move", "attack", "heroic", "wild"]:
					total += int(pool[k])
				if total <= 0:
					continue
				var keep: bool = await game._ask_confirm(
					"科技共情：%s 是否翻转 2 张英雄卡，来避免失去全部行动指示物（共 %d 个）？"
					% [DB.hero_name(hid), total])
				if keep:
					_modok_flip_hero_cards(game, 2, "科技共情（%s）" % DB.hero_name(hid))
				else:
					for k in ["move", "attack", "heroic", "wild"]:
						pool[k] = 0
						game.state["used_tokens"][k] = 0
					game._log("科技共情：%s 失去全部行动指示物（%d 个）" % [DB.hero_name(hid), total], Color(1, 0.6, 0.4))
			game._log("科技共情：%s 的到达效果结算完毕" % game._loc_name(loc), Color(0.9, 0.8, 0.6))
		_:
			pass
	Events.emit_state_changed()


## 威胁卡 BAM 入口（3 张带 BAM 的威胁卡各不同；由 Game._trigger_all_threat_bam 按卡名分发到此处）。
static func _modok_threat_bam(game: Node, tname: String, loc: int) -> void:
	match tname:
		"活体激光":
			# BAM!：对该地点的每个英雄造成 1 点伤害；若此地点没有英雄，则翻转 1 张英雄卡
			var here: Array = _heroes_at(game, loc).filter(func(h): return not game.state["heroes"][h]["ko"])
			if here.size() > 0:
				for hid in here:
					game._log("活体激光：%s 在 %s 受到 1 点伤害"
						% [DB.hero_name(String(hid)), game._loc_name(loc)], Color(1, 0.6, 0.4))
					await game._deal_damage_to_hero(String(hid), 1)
					if game.state["phase"] == "game_over":
						return
			else:
				game._log("活体激光：%s 没有英雄，改为翻转 1 张英雄卡" % game._loc_name(loc), Color(1, 0.6, 0.4))
				_modok_flip_hero_cards(game, 1, "活体激光")
		"变色龙":
			# BAM!：对该地点 1 名英雄造成"故事情节中最后 2 张英雄卡底部的攻击图标数"点伤害
			var dmg: int = _modok_recent_icon_count(game, "attack", 2)
			var targets: Array = _heroes_at(game, loc).filter(func(h): return not game.state["heroes"][h]["ko"])
			game._log("变色龙：故事情节最后 2 张英雄卡底部共 %d 个攻击图标" % dmg, Color(1, 0.6, 0.4))
			if targets.size() == 0:
				game._log("变色龙：%s 没有英雄" % game._loc_name(loc), Color(0.8, 0.8, 0.8))
			elif dmg > 0:
				var who: String = String(targets[0])
				if targets.size() > 1:
					who = String(targets[await game._ask_pick_hero(
						"变色龙 BAM：%s 的哪名英雄受到 %d 点伤害？" % [game._loc_name(loc), dmg], targets)])
				await game._deal_damage_to_hero(who, dmg)
		"斑点":
			# BAM!：翻转"故事情节中最后 2 张英雄卡底部的英勇图标数"等量的英雄卡
			var cnt: int = _modok_recent_icon_count(game, "heroic", 2)
			game._log("斑点：故事情节最后 2 张英雄卡底部共 %d 个英勇图标 → 翻转 %d 张英雄卡" % [cnt, cnt],
				Color(1, 0.6, 0.4))
			if cnt > 0:
				_modok_flip_hero_cards(game, cnt, "斑点")
		_:
			pass
	Events.emit_state_changed()
