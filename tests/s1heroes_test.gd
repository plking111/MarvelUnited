extends Node
## 第一季众筹 12 位英雄接入 + 全部卡牌效果验证
## 覆盖：黄蜂女 / 奥克耶 / 猎鹰 / 蚁人 / 蜘蛛侠2099 / 猫女 / 毒液 / 蜘蛛女 / 幻视 / 鹰眼 / 战争机器 / 尼克福瑞
## 口径（用户裁定）：
##  1) 蚁人·量子跃迁：与故事情节任意一张卡交换后，符号 + 效果都按换到的那张卡重新结算
##  2) 猫女·猫抓/猫之幸运：翻牌动画播完后（_await_villain_reveal 之后）再询问是否放牌库底并重翻
##  3) 鹰眼·神射手大师：本回合可用符号都视为两次攻击（含继承符号与本卡自身符号）
##  4) 幻视·心灵宝石冲击：统计故事情节最后 4 张英雄牌的攻击符号数（不含此牌），1 符号 = 1 伤害
##  5) "无"符号卡打出后仍继承上一张英雄卡的符号

const S1_HEROES := ["wasp", "okoye", "falcon", "antman", "spiderman2099", "blackcat",
	"venom", "spiderwoman", "vision", "hawkeye", "warmachine", "nickfury"]

var _fail := 0
var _answers: Array = []      # prompt_action 的预设答案（顺序弹出）
var _confirms: Array = []     # prompt_confirm 的预设答案
var _prompts: Array = []      # 记录 prompt_action 的 rows，便于断言

func _check(n: String, ok: bool, d: String = "") -> void:
	if ok:
		print("PASS: " + n)
	else:
		_fail += 1
		print("FAIL: " + n + " — " + d)

func _ready() -> void:
	Events.prompt_action.connect(func(rows: Array, _t: String, cb: Callable) -> void:
		_prompts.append(rows.duplicate(true))
		var a := 0
		if _answers.size() > 0:
			a = int(_answers.pop_front())
		await get_tree().process_frame
		cb.call(a))
	Events.prompt_confirm.connect(func(_t: String, cb: Callable) -> void:
		var a := true
		if _confirms.size() > 0:
			a = bool(_confirms.pop_front())
		await get_tree().process_frame
		cb.call(a))
	Events.prompt_choice.connect(func(_o: Array, _t: String, cb: Callable) -> void:
		await get_tree().process_frame
		cb.call(0))
	Events.prompt_hand_card.connect(func(cb: Callable, _t: String, hid: String, c: int) -> void:
		var h: Array = Game.state["heroes"][hid]["hand"]
		var out: Array = []
		for i in range(mini(c, h.size())):
			out.append(i)
		await get_tree().process_frame
		cb.call(out))

	await _test_data()
	await _test_wasp()
	await _test_okoye()
	await _test_falcon()
	await _test_antman()
	await _test_spiderman2099()
	await _test_blackcat()
	await _test_venom()
	await _test_spiderwoman()
	await _test_vision()
	await _test_hawkeye()
	await _test_warmachine()
	await _test_nickfury()

	if _fail == 0:
		print("=== S1 HEROES TEST ALL PASSED ===")
		get_tree().quit(0)
	else:
		print("=== S1 HEROES TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)

# ---------------------------------------------------------------- helpers

func _find_card(hid: String, etype: String) -> int:
	var cards: Array = DB.hero_cards(hid)
	for i in range(cards.size()):
		var e: Variant = cards[i].get("effect", null)
		if e != null and String(e.get("type", "")) == etype:
			return i
	return -1

func _find_cards(hid: String, etype: String) -> Array:
	var out: Array = []
	var cards: Array = DB.hero_cards(hid)
	for i in range(cards.size()):
		var e: Variant = cards[i].get("effect", null)
		if e != null and String(e.get("type", "")) == etype:
			out.append(i)
	return out

## 清空全部地点（无平民/暴徒/威胁），让攻击目标可控
func _wipe_board() -> void:
	for l in Game.state["locations"]:
		l["civ"] = 0
		l["thug"] = 0
		l["crisis"] = 0
		l["threat"] = null
		l["destroyed"] = false

func _set_thug_all(n: int) -> void:
	for l in Game.state["locations"]:
		l["thug"] = n

func _thug(loc: int) -> int:
	return int(Game.state["locations"][loc]["thug"])

func _loc_of(hid: String) -> int:
	return int(Game.state["heroes"][hid]["location"])

func _tokens(hid: String, k: String) -> int:
	return int(Game.state["heroes"][hid]["tokens"][k])

## 以"当前英雄打出带该效果的卡"为前提发动效果
func _trigger(hid: String, etype: String, syms: Array = ["move"]) -> void:
	var ci: int = _find_card(hid, etype)
	_check("%s 数据里有 %s 效果卡" % [hid, etype], ci >= 0, "未找到")
	if ci < 0:
		return
	Game.state["current_hero"] = Game.state["hero_ids"].find(hid)
	Game.state["phase"] = "hero_actions"
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	Game.state["played_effect"] = DB.hero_cards(hid)[ci]["effect"]
	Game.state["action_symbols"] = syms.duplicate()
	Game.state["prev_hero_symbols"] = syms.duplicate()
	await Game.trigger_effect()
	_check("%s 效果结算后 in_effect 已复位" % etype, Game.state.get("in_effect", true) == false,
		"in_effect 未复位 → 回合将无法自动结束")

# ---------------------------------------------------------------- 数据

func _test_data() -> void:
	_check("英雄总数=57（第一季众筹两批24位）", DB.heroes.size() == 57, "size=%d" % DB.heroes.size())
	for hid in S1_HEROES:
		_check("英雄 %s 已入库且有 12 张卡" % hid,
			DB.heroes.has(hid) and DB.hero_cards(hid).size() == 12,
			"cards=%d" % (DB.hero_cards(hid).size() if DB.heroes.has(hid) else -1))
		# 分类：黄蜂女 / 蚁人属于**基础盒**（用户 2026 裁定）——它们在基础盒里，不属于第一季众筹
		var want_exp := "基础盒" if hid in ["wasp", "antman"] else "第一季众筹"
		_check("英雄 %s 扩展=%s" % [hid, want_exp], String(DB.heroes[hid].get("expansion", "")) == want_exp,
			String(DB.heroes[hid].get("expansion", "")))
	# 卡序抽查（对照卡图；docx 表在黄蜂女第 1/4 张上顺序不同，以卡图为准）
	_check("黄蜂女卡4=攻击+能量投射", DB.hero_cards("wasp")[3]["symbols"] == ["attack"]
		and String(DB.hero_cards("wasp")[3]["effect"]["type"]) == "wasp_energy_blast", "")
	_check("黄蜂女卡1=纯移动(无效果)", not DB.hero_cards("wasp")[0].has("effect"), "")
	_check("蚁人卡5=无符号+量子跃迁", DB.hero_cards("antman")[4]["symbols"].size() == 0
		and String(DB.hero_cards("antman")[4]["effect"]["type"]) == "antman_quantum_leap", "")
	_check("幻视卡10=无符号+心灵宝石冲击", DB.hero_cards("vision")[9]["symbols"].size() == 0
		and String(DB.hero_cards("vision")[9]["effect"]["type"]) == "vision_mind_gem", "")
	# 重复卡各自独立
	_check("猎鹰有 3 张空袭", _find_cards("falcon", "falcon_airstrike").size() == 3, "")
	_check("蜘蛛女有 2 张毒液冲击", _find_cards("spiderwoman", "spiderwoman_venom_blast").size() == 2, "")
	_check("猫女有 2 张猫抓 + 2 张猫之幸运",
		_find_cards("blackcat", "blackcat_cat_scratch").size() == 2
		and _find_cards("blackcat", "blackcat_cat_luck").size() == 2, "")
	_check("尼克福瑞 3 张神盾局局长各不同",
		_find_cards("nickfury", "nickfury_director_move").size() == 1
		and _find_cards("nickfury", "nickfury_director_attack").size() == 1
		and _find_cards("nickfury", "nickfury_director_heroic").size() == 1, "")

# ---------------------------------------------------------------- 黄蜂女

func _test_wasp() -> void:
	Game.autopilot = false
	Game.setup("redskull", ["wasp", "falcon", "okoye", "antman"], "none", "base")
	_wipe_board()
	_set_thug_all(5)
	Game.state["heroes"]["wasp"]["location"] = 0

	# 能量投射：移动到任意地点 + 攻击一次
	var before_total: int = 0
	for i in range(6):
		before_total += _thug(i)
	await _trigger("wasp", "wasp_energy_blast")
	_check("能量投射：黄蜂女已移动", _loc_of("wasp") != 0, "loc=%d" % _loc_of("wasp"))
	var after_total: int = 0
	for i in range(6):
		after_total += _thug(i)
	_check("能量投射：移动后成功攻击（暴徒 -1）", after_total == before_total - 1,
		"%d -> %d" % [before_total, after_total])

	# 缩小：无敌
	await _trigger("wasp", "wasp_shrink")
	_check("缩小：直到下回合开始不受伤害", Game.state["heroes"]["wasp"]["invulnerable"] == true, "")

	# 翅膀：自己 + 任意数量英雄一起移动
	Game.setup("redskull", ["wasp", "falcon", "okoye", "antman"], "none", "base")
	_wipe_board()
	Game.state["heroes"]["wasp"]["location"] = 0
	Game.state["heroes"]["falcon"]["location"] = 0
	Game.state["heroes"]["okoye"]["location"] = 2
	_confirms = [true, true]   # 带 falcon 走、okoye 不在同地点不会询问
	Game.state["heroes"]["falcon"]["ko"] = false
	await _trigger("wasp", "wasp_wings")
	_check("翅膀：黄蜂女与同行英雄到了同一地点",
		_loc_of("wasp") == _loc_of("falcon") and _loc_of("wasp") != 0,
		"wasp=%d falcon=%d" % [_loc_of("wasp"), _loc_of("falcon")])
	_check("翅膀：不同地点的英雄不受影响", _loc_of("okoye") == 2, "okoye=%d" % _loc_of("okoye"))

# ---------------------------------------------------------------- 奥克耶

func _test_okoye() -> void:
	Game.setup("redskull", ["okoye", "wasp", "falcon", "antman"], "none", "base")
	_wipe_board()

	# 资深战略家：看牌库顶并可放底
	var deck: Array = Game.state["heroes"]["okoye"]["deck"]
	deck.clear()
	deck.append_array([1, 2, 3, 4])
	var top: int = int(deck[0])
	_confirms = [true]
	await _trigger("okoye", "okoye_strategist")
	_check("资深战略家：牌库顶的牌被放到牌库底",
		int(deck[deck.size() - 1]) == top and deck.size() == 4,
		"top=%d last=%d size=%d" % [top, int(deck[deck.size() - 1]), deck.size()])

	# 多拉·米拉杰：替同地点英雄承伤
	Game.setup("redskull", ["okoye", "wasp", "falcon", "antman"], "none", "base")
	_wipe_board()
	Game.state["heroes"]["okoye"]["location"] = 1
	Game.state["heroes"]["wasp"]["location"] = 1
	Game.state["heroes"]["okoye"]["hand"] = [0, 1, 2]
	Game.state["heroes"]["wasp"]["hand"] = [0, 1, 2]
	_confirms = [true]
	await _trigger("okoye", "okoye_dora_milaje")
	_check("多拉·米拉杰：已标记护卫", Game.state["heroes"]["okoye"].get("dora_milaje", false) == true, "")
	await Game._deal_damage_to_hero("wasp", 1)
	_check("多拉·米拉杰：奥克耶替黄蜂女承受伤害",
		Game.state["heroes"]["okoye"]["hand"].size() == 2 and Game.state["heroes"]["wasp"]["hand"].size() == 3,
		"okoye=%d wasp=%d" % [Game.state["heroes"]["okoye"]["hand"].size(), Game.state["heroes"]["wasp"]["hand"].size()])

	# 振金长矛：相邻地点两次攻击
	Game.setup("redskull", ["okoye", "wasp", "falcon", "antman"], "none", "base")
	_wipe_board()
	_set_thug_all(5)
	Game.state["heroes"]["okoye"]["location"] = 0
	var adj: Array = Game._adjacent_locs(0)
	var t0: int = _thug(int(adj[0]))
	_answers = [0]
	await _trigger("okoye", "okoye_vibranium_spear")
	_check("振金长矛：相邻地点（自动选第1个）暴徒 -2", _thug(int(adj[0])) == t0 - 2,
		"%d -> %d" % [t0, _thug(int(adj[0]))])

# ---------------------------------------------------------------- 猎鹰

func _test_falcon() -> void:
	Game.setup("redskull", ["falcon", "wasp", "okoye", "antman"], "none", "base")
	_wipe_board()
	_set_thug_all(5)
	Game.state["heroes"]["falcon"]["location"] = 0
	var before: int = 0
	for i in range(6):
		before += _thug(i)
	await _trigger("falcon", "falcon_airstrike")
	var after: int = 0
	for i in range(6):
		after += _thug(i)
	_check("空袭：移动到任意地点后攻击一次",
		_loc_of("falcon") != 0 and after == before - 1,
		"loc=%d thug %d->%d" % [_loc_of("falcon"), before, after])

# ---------------------------------------------------------------- 蚁人

func _test_antman() -> void:
	Game.setup("redskull", ["antman", "wasp", "okoye", "falcon"], "none", "base")
	_wipe_board()
	_set_thug_all(5)

	# 缩小
	await _trigger("antman", "antman_shrink")
	_check("缩小：直到下回合开始不受伤害", Game.state["heroes"]["antman"]["invulnerable"] == true, "")

	# 变大：先移动，然后对单个目标 3 次攻击
	Game.setup("redskull", ["antman", "wasp", "okoye", "falcon"], "none", "base")
	_wipe_board()
	_set_thug_all(5)
	Game.state["heroes"]["antman"]["location"] = 0
	await _trigger("antman", "antman_grow")
	_check("变大：先移动（离开原地点）", _loc_of("antman") != 0, "loc=%d" % _loc_of("antman"))
	_check("变大：对单个目标造成 3 次攻击（暴徒 -3）", _thug(_loc_of("antman")) == 2,
		"thug=%d" % _thug(_loc_of("antman")))

	# 量子跃迁：与故事情节任意一张正面朝上的牌交换，符号 + 效果按换到的那张卡重新结算
	Game.setup("redskull", ["antman", "wasp", "okoye", "falcon"], "none", "base")
	_wipe_board()
	# 故事情节：falcon 卡1（move + 空袭）在过去，蚁人卡5（本张，无符号）在最后
	Game.state["story"] = [
		{"type": "hero", "hero": "falcon", "idx": 0},
		{"type": "hero", "hero": "antman", "idx": 4},
	]
	Game.state["current_hero"] = Game.state["hero_ids"].find("antman")
	Game.state["phase"] = "hero_actions"
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	Game.state["played_effect"] = DB.hero_cards("antman")[4]["effect"]
	Game.state["action_symbols"] = ["heroic"]        # 口径5：无符号卡继承上一张卡的符号
	Game.state["prev_hero_symbols"] = ["heroic"]
	_answers = [0]                                   # 选第 1 张（falcon 卡1）
	await Game.trigger_effect()
	var story: Array = Game.state["story"]
	_check("量子跃迁：与故事情节卡交换成功（内容对调）",
		String(story[0]["hero"]) == "antman" and int(story[0]["idx"]) == 4
		and String(story[1]["hero"]) == "falcon" and int(story[1]["idx"]) == 0,
		"story0=%s%s story1=%s%s" % [story[0]["hero"], story[0]["idx"], story[1]["hero"], story[1]["idx"]])
	_check("量子跃迁：符号按换到的那张卡重新结算（falcon 卡1：move + 继承 heroic）",
		Game.state["action_symbols"].count("move") == 1 and Game.state["action_symbols"].count("heroic") == 1
		and Game.state["action_symbols"].size() == 2,
		"symbols=%s" % str(Game.state["action_symbols"]))
	_check("量子跃迁：效果也按换到的那张卡重新结算（= falcon 空袭）",
		String(Game.state["played_effect"].get("type", "")) == "falcon_airstrike"
		and Game.state["effect_available"] == true and Game.state["effect_used"] == false,
		"effect=%s avail=%s used=%s" % [String(Game.state["played_effect"].get("type", "")),
			str(Game.state["effect_available"]), str(Game.state["effect_used"])])

	# 量子跃迁②：换到"无效果"的卡 → 不再有可发动效果；多符号卡按卡面符号结算
	Game.setup("redskull", ["antman", "wasp", "okoye", "falcon"], "none", "base")
	_wipe_board()
	Game.state["story"] = [
		{"type": "hero", "hero": "falcon", "idx": 6},   # falcon 卡7：move + attack，无效果
		{"type": "hero", "hero": "antman", "idx": 4},
	]
	Game.state["current_hero"] = Game.state["hero_ids"].find("antman")
	Game.state["phase"] = "hero_actions"
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	Game.state["played_effect"] = DB.hero_cards("antman")[4]["effect"]
	Game.state["action_symbols"] = ["heroic"]
	Game.state["prev_hero_symbols"] = ["heroic"]
	_answers = [0]
	await Game.trigger_effect()
	_check("量子跃迁②：换到无效果的卡 → 符号按卡面重算（move+attack+继承 heroic），无效果可发动",
		Game.state["action_symbols"].count("move") == 1 and Game.state["action_symbols"].count("attack") == 1
		and Game.state["action_symbols"].count("heroic") == 1
		and Game.state["effect_available"] == false,
		"symbols=%s avail=%s" % [str(Game.state["action_symbols"]), str(Game.state["effect_available"])])

	# 量子跃迁③：本回合已经用掉的符号不会被"重新结算"返还
	Game.setup("redskull", ["antman", "wasp", "okoye", "falcon"], "none", "base")
	_wipe_board()
	Game.state["story"] = [
		{"type": "hero", "hero": "okoye", "idx": 3},    # okoye 卡4：只有 attack（换出的卡不含 move，便于验证"已用符号不返还"）
		{"type": "hero", "hero": "antman", "idx": 4},
	]
	Game.state["current_hero"] = Game.state["hero_ids"].find("antman")
	Game.state["phase"] = "hero_actions"
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	Game.state["played_effect"] = DB.hero_cards("antman")[4]["effect"]
	Game.state["action_symbols"] = ["move", "heroic"]   # 继承的 2 个符号
	Game.state["prev_hero_symbols"] = ["move", "heroic"]
	Game.state["action_symbols"].remove_at(0)           # 模拟已用掉 1 个 move
	_answers = [0]
	await Game.trigger_effect()
	_check("量子跃迁③：已用掉的符号不返还（换到只有 attack 的卡 → 只得 attack + 剩余 heroic）",
		Game.state["action_symbols"].count("move") == 0 and Game.state["action_symbols"].count("attack") == 1
		and Game.state["action_symbols"].count("heroic") == 1
		and Game.state["action_symbols"].size() == 2,
		"symbols=%s" % str(Game.state["action_symbols"]))

# ---------------------------------------------------------------- 蜘蛛侠2099

func _test_spiderman2099() -> void:
	Game.setup("redskull", ["spiderman2099", "wasp", "okoye", "falcon"], "none", "base")
	_wipe_board()
	_set_thug_all(5)

	# 利爪：两次攻击 + 本回合伤害无法被降低
	await _trigger("spiderman2099", "sm2099_claws")
	_check("利爪：对所在地点目标两次攻击（暴徒 -2）",
		_thug(_loc_of("spiderman2099")) == 3, "thug=%d" % _thug(_loc_of("spiderman2099")))
	_check("利爪：本回合造成的伤害无法被降低（标记已置）",
		Game.state["heroes"]["spiderman2099"].get("ignore_reduction", false) == true, "")

	# 强化感官：无敌
	await _trigger("spiderman2099", "sm2099_enhanced_senses")
	_check("强化感官：直到下回合开始不受伤害",
		Game.state["heroes"]["spiderman2099"]["invulnerable"] == true, "")

	# 莱利援助：在任意地点进行一次英勇行动
	Game.setup("redskull", ["spiderman2099", "wasp", "okoye", "falcon"], "none", "base")
	_wipe_board()
	Game.state["locations"][0]["civ"] = 2
	Game.state["heroes"]["spiderman2099"]["location"] = 3
	_answers = [0]
	await _trigger("spiderman2099", "sm2099_riley_assist")
	_check("莱利援助：在任意地点完成了英勇行动（营救平民）",
		int(Game.state["locations"][0]["civ"]) == 1, "civ=%d" % int(Game.state["locations"][0]["civ"]))
	_check("莱利援助：行动后英雄回到原地点", _loc_of("spiderman2099") == 3, "loc=%d" % _loc_of("spiderman2099"))

# ---------------------------------------------------------------- 猫女

func _test_blackcat() -> void:
	Game.setup("redskull", ["blackcat", "wasp", "okoye", "falcon"], "none", "base")
	_wipe_board()
	_set_thug_all(5)

	# 猫之本能：任意 2 个指示物（可任意组合）
	_answers = [0, 2]   # 第 1 个选移动，第 2 个选英勇
	await _trigger("blackcat", "blackcat_cat_reflex")
	_check("猫之本能：获得任意 2 个指示物（移动 +1、英勇 +1）",
		_tokens("blackcat", "move") == 1 and _tokens("blackcat", "heroic") == 1,
		"move=%d heroic=%d" % [_tokens("blackcat", "move"), _tokens("blackcat", "heroic")])

	# 猫抓：打出后记待触发标记
	await _trigger("blackcat", "blackcat_cat_scratch")
	_check("猫抓：打出后已标记待触发",
		Game.state["heroes"]["blackcat"].get("cat_redraw_armed", false) == true, "")

	# 猫抓：下一次反派翻行动卡时（动画播完后）可放牌库底并重翻
	Game.autopilot = true      # 跳过翻牌动画等待，并让确认弹窗自动答"是"
	Game.setup("redskull", ["blackcat", "wasp"], "none", "base")
	Game.state["heroes"]["blackcat"]["cat_redraw_armed"] = true
	var top: int = int(Game.state["master_deck"][0])
	var second: int = int(Game.state["master_deck"][1])
	await Game._run_villain_turn()
	var deck2: Array = Game.state["master_deck"]
	_check("猫抓：原顶牌被放到主计划牌堆底",
		deck2.size() > 0 and int(deck2[deck2.size() - 1]) == top,
		"last=%s top=%d" % [str(deck2[deck2.size() - 1] if deck2.size() > 0 else -1), top])
	_check("猫抓：实际结算的是重翻的那张卡（原顶牌未结算）",
		Game.state["master_discard"].has(second) and not Game.state["master_discard"].has(top),
		"discard=%s" % str(Game.state["master_discard"]))
	_check("猫抓：标记已消耗（只触发一次）",
		Game.state["heroes"]["blackcat"].get("cat_redraw_armed", false) == false, "")
	Game.autopilot = false

	# 猫之幸运：与猫抓同机制
	Game.setup("redskull", ["blackcat", "wasp"], "none", "base")
	await _trigger("blackcat", "blackcat_cat_luck")
	_check("猫之幸运：打出后已标记待触发",
		Game.state["heroes"]["blackcat"].get("cat_redraw_armed", false) == true, "")

# ---------------------------------------------------------------- 毒液

func _test_venom() -> void:
	Game.setup("redskull", ["venom", "wasp", "okoye", "falcon"], "none", "base")
	_wipe_board()
	_set_thug_all(5)

	# 共生体强化：获得一个移动和一个攻击行动
	var mv0: int = Game.state["action_symbols"].count("move")
	await _trigger("venom", "venom_symbiote_boost", [])
	_check("共生体强化：获得 1 个移动行动 + 1 个攻击行动",
		Game.state["action_symbols"].count("move") == mv0 + 1
		and Game.state["action_symbols"].count("attack") == 1,
		"symbols=%s" % str(Game.state["action_symbols"]))

	# 再生：抽牌直到手牌 3 张
	Game.state["heroes"]["venom"]["hand"] = [0]
	Game.state["heroes"]["venom"]["deck"] = [1, 2, 3, 4]
	await _trigger("venom", "venom_regen")
	_check("再生：抽牌直到手牌 3 张", Game.state["heroes"]["venom"]["hand"].size() == 3,
		"hand=%d" % Game.state["heroes"]["venom"]["hand"].size())

	# 追踪：移动到任意地点 + 攻击一次
	Game.setup("redskull", ["venom", "wasp", "okoye", "falcon"], "none", "base")
	_wipe_board()
	_set_thug_all(5)
	Game.state["heroes"]["venom"]["location"] = 0
	await _trigger("venom", "venom_track")
	_check("追踪：移动后攻击一次",
		_loc_of("venom") != 0 and _thug(_loc_of("venom")) == 4,
		"loc=%d thug=%d" % [_loc_of("venom"), _thug(_loc_of("venom"))])

# ---------------------------------------------------------------- 蜘蛛女

func _test_spiderwoman() -> void:
	Game.setup("redskull", ["spiderwoman", "wasp", "okoye", "falcon"], "none", "base")
	_wipe_board()
	_set_thug_all(5)

	# 毒液冲击①：两次攻击
	_answers = [0]
	await _trigger("spiderwoman", "spiderwoman_venom_blast")
	_check("毒液冲击①：对所在地点目标两次攻击（暴徒 -2）",
		_thug(_loc_of("spiderwoman")) == 3, "thug=%d" % _thug(_loc_of("spiderwoman")))

	# 毒液冲击②：下一个反派回合推迟 1 张牌
	_answers = [1]
	await _trigger("spiderwoman", "spiderwoman_venom_blast")
	_check("毒液冲击②：下一个反派回合少打 1 张牌",
		int(Game.state.get("skip_villain_card", 0)) == 1, "skip=%d" % int(Game.state.get("skip_villain_card", 0)))

	# 超级抗性：无敌
	await _trigger("spiderwoman", "spiderwoman_super_resist")
	_check("超级抗性：直到下回合开始不受伤害",
		Game.state["heroes"]["spiderwoman"]["invulnerable"] == true, "")

# ---------------------------------------------------------------- 幻视

func _test_vision() -> void:
	Game.setup("redskull", ["vision", "wasp", "okoye", "falcon"], "none", "base")
	_wipe_board()
	_set_thug_all(10)
	Game.state["heroes"]["vision"]["location"] = 2

	# 心灵宝石冲击：统计故事情节最后 4 张英雄牌（不含此牌）的攻击符号数，1 符号 = 1 伤害
	# 故事情节（自旧到新）：falcon卡5(wild)=0攻、falcon卡6(attack)=1攻、okoye卡6(攻攻)=2攻、okoye卡12(攻)=1攻、幻视卡10(本张)
	Game.state["story"] = [
		{"type": "hero", "hero": "falcon", "idx": 4},
		{"type": "hero", "hero": "falcon", "idx": 5},
		{"type": "hero", "hero": "okoye", "idx": 5},
		{"type": "hero", "hero": "okoye", "idx": 11},
		{"type": "hero", "hero": "vision", "idx": 9},
	]
	var n_atk: int = Game._count_recent_story_symbols("attack", 4)
	_check("心灵宝石冲击：最后 4 张英雄牌攻击符号数 = 4", n_atk == 4, "count=%d" % n_atk)
	await _trigger("vision", "vision_mind_gem", ["heroic"])
	_check("心灵宝石冲击：造成等量伤害（10-4=6）", _thug(2) == 6, "thug=%d" % _thug(2))

	# 进化智力：槽位全满的地点数量 → 等量万能指示物
	Game.setup("redskull", ["vision", "wasp", "okoye", "falcon"], "none", "base")
	_wipe_board()
	var slots0: int = int(DB.location(String(Game.state["locations"][0]["id"]))["slots"])
	var slots1: int = int(DB.location(String(Game.state["locations"][1]["id"]))["slots"])
	Game.state["locations"][0]["civ"] = slots0
	Game.state["locations"][1]["thug"] = slots1
	var w0: int = _tokens("vision", "wild")
	await _trigger("vision", "vision_evolved_intellect", ["wild"])
	_check("进化智力：2 个地点槽位全满 → 获得 2 个万能指示物",
		_tokens("vision", "wild") == w0 + 2, "wild %d -> %d" % [w0, _tokens("vision", "wild")])

	# 透明化：无敌
	await _trigger("vision", "vision_phase")
	_check("透明化：直到下回合开始不受伤害",
		Game.state["heroes"]["vision"]["invulnerable"] == true, "")

# ---------------------------------------------------------------- 鹰眼

func _test_hawkeye() -> void:
	Game.setup("redskull", ["hawkeye", "wasp", "okoye", "falcon"], "none", "base")
	_wipe_board()
	_set_thug_all(10)

	# 远射：对面地点两次攻击
	Game.state["heroes"]["hawkeye"]["location"] = 0
	var opp: int = Game._opposite_loc(0)
	_check("远射：对面地点 = 环上相隔 3 格", opp == 3, "opp=%d" % opp)
	await _trigger("hawkeye", "hawkeye_long_shot")
	_check("远射：对面地点暴徒 -2", _thug(opp) == 8, "thug=%d" % _thug(opp))

	# 武术家：受到的伤害转移给同地点敌人
	Game.setup("redskull", ["hawkeye", "wasp", "okoye", "falcon"], "none", "base")
	_wipe_board()
	Game.state["locations"][1]["thug"] = 3
	Game.state["heroes"]["hawkeye"]["location"] = 1
	Game.state["heroes"]["hawkeye"]["hand"] = [0, 1, 2]
	_confirms = [true]
	await _trigger("hawkeye", "hawkeye_martial_artist")
	_check("武术家：已标记", Game.state["heroes"]["hawkeye"].get("martial_artist", false) == true, "")
	await Game._deal_damage_to_hero("hawkeye", 1)
	_check("武术家：伤害转移给同地点敌人（暴徒 -1，鹰眼不弃牌）",
		_thug(1) == 2 and Game.state["heroes"]["hawkeye"]["hand"].size() == 3,
		"thug=%d hand=%d" % [_thug(1), Game.state["heroes"]["hawkeye"]["hand"].size()])

	# 神射手大师：本回合可用的每个符号都视为两次攻击（含本卡自身符号）
	Game.setup("redskull", ["hawkeye", "wasp", "okoye", "falcon"], "none", "base")
	_wipe_board()
	await _trigger("hawkeye", "hawkeye_master_marksman", ["move", "heroic", "wild"])
	_check("神射手大师：3 个可用符号视为 6 次攻击",
		Game.state["action_symbols"].size() == 6
		and Game.state["action_symbols"].count("attack") == 6,
		"symbols=%s" % str(Game.state["action_symbols"]))

# ---------------------------------------------------------------- 战争机器

func _test_warmachine() -> void:
	Game.setup("redskull", ["warmachine", "wasp", "okoye", "falcon"], "none", "base")
	_wipe_board()
	_set_thug_all(10)
	Game.state["heroes"]["warmachine"]["location"] = 0
	var adj: Array = Game._adjacent_locs(0)

	# 光束武器：相邻地点一次攻击
	_answers = [0]
	await _trigger("warmachine", "warmachine_repulsor")
	_check("光束武器：相邻地点攻击一次（暴徒 -1）", _thug(int(adj[0])) == 9,
		"thug=%d" % _thug(int(adj[0])))

	# 火箭发射器：相邻地点两次攻击
	_answers = [1]   # 选第 2 个相邻地点
	await _trigger("warmachine", "warmachine_rocket")
	_check("火箭发射器：相邻地点攻击两次（暴徒 -2）", _thug(int(adj[1])) == 8,
		"thug=%d" % _thug(int(adj[1])))

	# 扫射攻击：先两次攻击，然后一次移动
	Game.setup("redskull", ["warmachine", "wasp", "okoye", "falcon"], "none", "base")
	_wipe_board()
	_set_thug_all(10)
	Game.state["heroes"]["warmachine"]["location"] = 0
	await _trigger("warmachine", "warmachine_strafe")
	_check("扫射攻击：先在原地两次攻击（暴徒 -2）",
		_thug(0) == 8, "thug0=%d" % _thug(0))
	_check("扫射攻击：随后完成一次移动", _loc_of("warmachine") != 0,
		"loc=%d" % _loc_of("warmachine"))

# ---------------------------------------------------------------- 尼克福瑞

func _test_nickfury() -> void:
	# 神盾局局长·移动：选第 2 名英雄（wasp）执行两次移动
	Game.setup("redskull", ["nickfury", "wasp", "okoye", "falcon"], "none", "base")
	_wipe_board()
	Game.state["heroes"]["wasp"]["location"] = 0
	var w0: int = _loc_of("wasp")
	_answers = [1, 0, 0]   # 选英雄=index1(wasp)，两次移动各选第 1 个相邻地点
	await _trigger("nickfury", "nickfury_director_move")
	_check("神盾局局长：选定英雄立刻执行两次移动", _loc_of("wasp") != w0,
		"wasp %d -> %d" % [w0, _loc_of("wasp")])

	# 神盾局局长·攻击：选定英雄执行两次攻击
	Game.setup("redskull", ["nickfury", "wasp", "okoye", "falcon"], "none", "base")
	_wipe_board()
	_set_thug_all(10)
	Game.state["heroes"]["wasp"]["location"] = 2
	_answers = [1, 0, 0]
	await _trigger("nickfury", "nickfury_director_attack")
	_check("神盾局局长：选定英雄立刻执行两次攻击（暴徒 -2）", _thug(2) == 8, "thug=%d" % _thug(2))

	# 神盾局局长·英勇：选定英雄执行两次英勇行动
	Game.setup("redskull", ["nickfury", "wasp", "okoye", "falcon"], "none", "base")
	_wipe_board()
	Game.state["locations"][4]["civ"] = 2
	Game.state["heroes"]["wasp"]["location"] = 4
	_answers = [1, 0, 0]
	await _trigger("nickfury", "nickfury_director_heroic")
	_check("神盾局局长：选定英雄立刻执行两次英勇行动（营救 2 个平民）",
		int(Game.state["locations"][4]["civ"]) == 0, "civ=%d" % int(Game.state["locations"][4]["civ"]))
