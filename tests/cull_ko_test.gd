extends Node
## 黑矮星（cull）特殊规则验证：英雄被 KO 时**不激活 BAM**，改为打出另一张反派行动牌。
## 数据依据：villains.json → cull.special = "当英雄被 KO 时，黑矮星不会激活他的 BAM！相反，他打出另一张反派行动牌。"
## 覆盖三条路径：① 直接 KO（单元）② 反派回合 BAM 造成 KO ③ 英雄回合结束手牌为空 KO

var _fail := 0

func _check(n: String, ok: bool, d: String = "") -> void:
	if ok:
		print("PASS: " + n)
	else:
		_fail += 1
		print("FAIL: " + n + " — " + d)

func _ready() -> void:
	Game.autopilot = true
	await _test_ko_direct()
	await _test_ko_by_bam_in_villain_turn()
	await _test_ko_at_hero_turn_end()
	if _fail == 0:
		print("=== CULL KO TEST ALL PASSED ===")
		get_tree().quit(0)
	else:
		print("=== CULL KO TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)

# ---------------------------------------------------------------- helpers

func _log_from(mark: int, needle: String) -> bool:
	var logs: Array = Game.state["log"]
	for i in range(mark, logs.size()):
		if String(logs[i]["t"]).contains(needle):
			return true
	return false

func _log_count_from(mark: int, needle: String) -> int:
	var n := 0
	var logs: Array = Game.state["log"]
	for i in range(mark, logs.size()):
		if String(logs[i]["t"]).contains(needle):
			n += 1
	return n

func _log_has_ko(mark: int, hid: String) -> bool:
	return _log_from(mark, "%s 被击倒（KO）" % DB.hero_name(hid))

func _log_mark() -> int:
	return (Game.state["log"] as Array).size()

## 把黑矮星的行动牌换成"可数"的牌：index0 带 BAM，其余不带 BAM/不放指示物，
## 这样 master_discard 的张数 = 本回合真正打出的行动牌张数。
func _use_countable_deck() -> void:
	DB.villain("cull")["actions"] = [
		{"move": 0, "bam": true, "effect": null, "place": null},
		{"move": 0, "bam": false, "effect": null, "place": null},
		{"move": 0, "bam": false, "effect": null, "place": null},
		{"move": 0, "bam": false, "effect": null, "place": null},
	]
	Game.state["master_deck"] = [0, 1, 2, 3]
	Game.state["master_discard"] = []
	Game.state["extra_villain_card"] = 0
	for l in Game.state["locations"]:
		l["threat"] = null

# ---------------------------------------------------------------- ① 直接 KO

func _test_ko_direct() -> void:
	Game.setup("cull", ["cap", "ironman"], "none", "base")
	_use_countable_deck()
	var hp0: int = int(Game.state["villain_hp"])
	var mark := _log_mark()
	Game.state["heroes"]["cap"]["hand"] = [0, 1, 2]
	await Game._ko_hero("cap")
	_check("① 直接 KO：黑矮星标记了额外行动牌（extra_villain_card=1）",
		int(Game.state.get("extra_villain_card", 0)) == 1,
		"extra=%d" % int(Game.state.get("extra_villain_card", -1)))
	_check("① 直接 KO：日志明确说明不触发 BAM", _log_from(mark, "黑矮星不触发 BAM"), "")
	_check("① 直接 KO：没有出现通用 BAM 日志（未激活 BAM）",
		not _log_from(mark, "触发反派 BAM 效果") and not _log_from(mark, "BAM！黑矮星"),
		"日志=%s" % str((Game.state["log"] as Array).slice(mark, _log_mark())))
	_check("① 直接 KO：反派生命值未变化（BAM 未被激活）",
		int(Game.state["villain_hp"]) == hp0, "%d -> %d" % [hp0, int(Game.state["villain_hp"])])
	_check("① 直接 KO：该英雄手牌已全部进牌库（KO 处理）",
		(Game.state["heroes"]["cap"]["hand"] as Array).is_empty(), "")

# ---------------------------------------------------------------- ② 反派回合 BAM 造成 KO

func _test_ko_by_bam_in_villain_turn() -> void:
	# 对照组：cap 手牌多，不会被 KO → 本回合只打 1 张
	Game.setup("cull", ["cap", "ironman"], "none", "base")
	_use_countable_deck()
	var vpos: int = int(Game.state["villain_pos"])
	Game.state["heroes"]["cap"]["location"] = vpos
	Game.state["heroes"]["cap"]["hand"] = [0, 1, 2, 3]
	Game.state["heroes"]["ironman"]["location"] = (vpos + 3) % Game.LOCATION_COUNT
	Game.state["heroes"]["ironman"]["hand"] = [0, 1, 2]
	await Game._run_villain_turn()
	var ctrl: int = (Game.state["master_discard"] as Array).size()
	_check("② 对照组：无 KO 时本回合只打出 1 张行动牌", ctrl == 1, "played=%d" % ctrl)

	# 实验组：cap 只有 1 张手牌 → BAM 1 伤 → 手牌清空 KO → 应额外打出 1 张（共 2 张）
	Game.setup("cull", ["cap", "ironman"], "none", "base")
	_use_countable_deck()
	vpos = int(Game.state["villain_pos"])
	Game.state["heroes"]["cap"]["location"] = vpos
	Game.state["heroes"]["cap"]["hand"] = [0]
	Game.state["heroes"]["ironman"]["location"] = (vpos + 3) % Game.LOCATION_COUNT
	Game.state["heroes"]["ironman"]["hand"] = [0, 1, 2]
	var mark := _log_mark()
	await Game._run_villain_turn()
	# 注意：不能用 h["ko"] 判断——回合结束时 _start_hero_phase → 该英雄回合开始会立刻复活（正常机制），
	# 所以这里用"KO 日志"判定 KO 确实发生过。
	_check("② 实验组：BAM 导致英雄被击倒（KO 日志已出现）", _log_has_ko(mark, "cap"), "")
	_check("② 实验组：KO 后不触发 BAM，改为额外打出 1 张（本回合共打出 2 张）",
		(Game.state["master_discard"] as Array).size() == 2,
		"played=%d discard=%s" % [(Game.state["master_discard"] as Array).size(), str(Game.state["master_discard"])])
	_check("② 实验组：日志说明改为打出另一张行动牌",
		_log_from(mark, "黑矮星不触发 BAM，改为打出另一张行动牌"), "")
	_check("② 实验组：额外牌已消耗（extra_villain_card 归零）",
		int(Game.state.get("extra_villain_card", 0)) == 0,
		"extra=%d" % int(Game.state.get("extra_villain_card", -1)))
	_check("② 实验组：日志出现「立即打出额外反派行动卡」",
		_log_from(mark, "立即打出额外反派行动卡"), "")
	_check("② 实验组：日志写明这张额外牌的原因是「英雄被击倒（KO）」",
		_log_from(mark, "原因：美国队长 被击倒（KO）"), "")
	_check("② 实验组：日志提醒「额外牌自带 BAM 仍会触发，不是本次 KO 触发的」",
		_log_from(mark, "那是它自己的 BAM，不是本次 KO 触发的"), "")

# ---------------------------------------------------------------- ③ 英雄回合结束手牌为空 KO

func _test_ko_at_hero_turn_end() -> void:
	Game.setup("cull", ["cap", "ironman"], "none", "base")
	_use_countable_deck()
	Game.state["current_hero"] = Game.state["hero_ids"].find("cap")
	Game.state["heroes"]["cap"]["hand"] = []
	Game.state["heroes"]["cap"]["deck"] = [0, 1, 2]
	# 地点是随机抽的：某些地点的"回合结束效果"会抽牌，会让手牌不为空从而不 KO。
	# 放一张无名威胁卡，让 end_turn 跳过地点结束效果（也不匹配任何威胁伤害名），保证"手牌为空 → KO"确定发生。
	var hl: int = Game.state["heroes"]["cap"]["location"]
	Game.state["locations"][hl]["threat"] = {"name": "测试占位", "hp": 0, "heroic_tokens": 0, "bam": false}
	Game.state["hero_cards_played"] = 3      # 达到节奏（未完成任务时需 3 张）→ 回合结束进反派回合
	Game.state["phase"] = "hero_end"
	var mark := _log_mark()
	await Game.end_turn()
	_check("③ 英雄回合结束手牌为空 → 被击倒（KO 日志已出现）", _log_has_ko(mark, "cap"), "")
	_check("③ KO 后下一次反派回合打出 2 张（1 正常 + 1 额外）",
		(Game.state["master_discard"] as Array).size() == 2,
		"played=%d discard=%s" % [(Game.state["master_discard"] as Array).size(), str(Game.state["master_discard"])])
	_check("③ 日志说明黑矮星不触发 BAM", _log_from(mark, "黑矮星不触发 BAM"), "")
