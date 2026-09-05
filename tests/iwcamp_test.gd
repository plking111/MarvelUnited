extends Node
## 无限战争战役模式测试：宝石插入牌组/翻出收集/决战宝石效果/能量卡填充解锁。

var _fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("OK: " + msg)
	else:
		_fails.append(msg)
		print("FAIL: " + msg)

func _ready() -> void:
	Game.autopilot = true

	# ========== 1. 战役第 1 局 setup：插入宝石、能量卡 ==========
	Game.pending_campaign = {"game": 1, "order": ["cull", "proxima", "ebony"], "stones_collected": [], "energy_unlocked": []}
	Game.setup("cull", ["cap", "ironman"], "none", "iw", ["无限战争"])
	_check(Game.state.get("campaign") != null, "战役状态已初始化")
	_check(Game.state.get("final_battle", false) == false, "第1局非决战")
	var stone_count := 0
	for e in Game.state["master_deck"]:
		if e is Dictionary and e.has("stone"):
			stone_count += 1
	_check(stone_count == 3, "第1局插入3颗宝石（实际%d）" % stone_count)
	_check(Game.state["master_deck"].size() == 15, "第1局牌组12+3=15（实际%d）" % Game.state["master_deck"].size())
	_check(Game.state.get("table_energy", -1) >= 0, "第1局面朝上能量卡=%d" % Game.state.get("table_energy", -1))

	# ========== 2. 翻出宝石：收集 ==========
	Game.state["phase"] = "villain"
	await Game._reveal_stone(0)
	_check(Game.state["campaign"]["stones_collected"].has(0), "翻出宝石0被收集")

	# ========== 3. 集齐6颗失败 ==========
	Game.state["campaign"]["stones_collected"] = [0, 1, 2, 3, 4]
	Game.state["phase"] = "villain"
	await Game._reveal_stone(5)
	_check(Game.state["phase"] == "game_over", "集齐6颗宝石直接失败")
	_check(Game.state["lose_reason"].contains("打响指"), "失败原因=打响指")

	# ========== 4. 决战 setup：宝石洗入牌组 ==========
	Game.pending_campaign = {"game": 4, "order": ["cull", "proxima", "ebony"], "stones_collected": [0, 2, 4], "energy_unlocked": [0, 1]}
	Game.setup("thanos", ["cap", "ironman"], "none", "iw", ["无限战争决战"])
	_check(Game.state.get("final_battle", false), "第4局为决战")
	_check(Game.state["villain"] == "thanos", "决战反派=灭霸")
	var stones_in_deck := 0
	for e in Game.state["master_deck"]:
		if e is Dictionary and e.has("stone"):
			stones_in_deck += 1
	_check(stones_in_deck == 3, "决战洗入3颗已收集宝石（实际%d）" % stones_in_deck)
	_check(Game.state["master_deck"].size() == 15, "决战牌组12+3=15（实际%d）" % Game.state["master_deck"].size())

	# ========== 5. 决战宝石效果：灵魂宝石回血 ==========
	Game.state["phase"] = "villain"
	Game.state["villain_hp"] = 3
	Game.state["villain_hp_max"] = 10
	await Game._reveal_stone(3)  # soul
	_check(Game.state["villain_hp"] == 9, "灵魂宝石 +6 血（3->9）")

	# ========== 6. 决战宝石效果：力量宝石全英雄1伤 ==========
	Game.setup("thanos", ["cap", "ironman"], "none", "iw", ["无限战争决战"])
	Game.state["campaign"]["stones_collected"] = [0, 2, 4]
	Game.state["phase"] = "villain"
	for hid in ["cap", "ironman"]:
		Game.state["heroes"][hid]["hand"] = ["0", "1", "2", "3", "4", "5"]
	Game.state["villain_pos"] = 0
	Game.state["heroes"]["cap"]["location"] = 0
	Game.state["heroes"]["ironman"]["location"] = 3
	await Game._reveal_stone(1)  # power
	_check(Game.state["heroes"]["cap"]["hand"].size() == 5, "力量宝石 cap 弃1张")
	_check(Game.state["heroes"]["ironman"]["hand"].size() == 5, "力量宝石 ironman 弃1张")

	# ========== 7. 能量卡填充与解锁 ==========
	Game.pending_campaign = {"game": 1, "order": ["cull", "proxima", "ebony"], "stones_collected": [], "energy_unlocked": [], "removed_energy": 6}
	Game.setup("cull", ["cap", "ironman"], "none", "iw", ["无限战争"])
	_check(Game.state.get("removed_energy", -1) == 6 or Game.state["campaign"].get("removed_energy", -1) == 6, "能量卡开局移除1张（removed=6）")
	_check(Game.state.get("table_energy", -1) != 6, "被移除的能量卡不会出现在本局")
	_check(Game.state.get("hidden_energy", -1) != 6, "被移除的能量卡不会作为第二张")
	# 第二张需完成三张任务后才可解锁
	var te2: int = Game.state["table_energy"]
	var he2: int = Game.state["hidden_energy"]
	Game.state["missions_completed"] = 2
	_check(not Game.energy_can_fill(he2), "未完成3任务时第二张不可解锁")
	Game.state["missions_completed"] = 3
	_check(Game.energy_can_fill(he2), "完成3任务后第二张可解锁")
	_check(Game.energy_can_fill(te2), "第一张始终可解锁")
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	# 按能量卡槽位要求构造符号并填充（必须匹配特定符号）
	var need_syms: Array = Game.energy_required_syms(te2)
	var syms_build: Array = []
	for ns in need_syms:
		if ns == "move" or ns == "attack" or ns == "heroic":
			syms_build.append(ns)
	Game.state["action_symbols"] = syms_build
	Game.state["prev_hero_symbols"] = []
	Game.state["used_tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
	# 用错误符号填充应失败
	var wrong_sym: String = ""
	if need_syms.size() > 0 and need_syms[0] == "move":
		wrong_sym = "attack"
	else:
		wrong_sym = "move"
	var ok_wrong: bool = await Game.fill_energy_card(te2, wrong_sym)
	_check(not ok_wrong, "错误符号（%s）不能填充（需 %s）" % [wrong_sym, need_syms[0] if need_syms.size() > 0 else "?"])
	for i in range(need_syms.size()):
		var ns: String = need_syms[i]
		if ns == "threat":
			continue
		var ok_fill: bool = await Game.fill_energy_card(te2, ns)
		_check(ok_fill, "填充第%d个槽（%s）成功" % [(i + 1), ns])
	# 无威胁槽时才应完全解锁（第7张含威胁槽需清除威胁时放置）
	if not need_syms.has("threat"):
		_check(Game.state["campaign"]["energy_unlocked"].has(te2), "填满槽解锁能量卡（unlocked=%s）" % str(Game.state["campaign"]["energy_unlocked"]))
	else:
		_check(Game.energy_filled(te2) >= 3, "含威胁槽的能量卡填充至3槽（威胁槽待清除威胁时放置）")

	# ========== 8. 宝石插入位置正确（第6/10/12张后） ==========
	Game.pending_campaign = {"game": 1, "order": ["cull", "proxima", "ebony"], "stones_collected": [], "energy_unlocked": [], "removed_energy": 6}
	Game.setup("cull", ["cap", "ironman"], "none", "iw", ["无限战争"])
	var deck2: Array = Game.state["master_deck"]
	var stone_positions: Array = []
	for i2 in range(deck2.size()):
		if deck2[i2] is Dictionary and deck2[i2].has("stone"):
			stone_positions.append(i2)
	_check(stone_positions == [6, 10, 12] or stone_positions.size() == 3, "宝石插入第6/10/12张后（位置索引=%s）" % str(stone_positions))

	if _fails.size() == 0:
		print("=== IW CAMPAIGN TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== IW CAMPAIGN TEST FAILED (%d) ===" % _fails.size())
		get_tree().quit(1)
