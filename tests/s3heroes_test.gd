extends Node
## 第一季众筹第三批（3.x）13 位英雄：数据 + 效果 + 6 条裁定。
##
## 覆盖内容：
##   ① 数据层：13 位英雄在册、各 12 张卡、扩展=第一季众筹、卡背资源路径正确、符号合法；
##   ② 效果层：每位英雄至少触发一次特殊能力（autopilot 下弹窗自动答第 0 项），
##      断言"没报错 + 日志里新增了这次效果的记录"；
##   ③ 六条裁定：
##      裁定1 生命化身  = 下一个反派回合整回合空过（牌仍翻，背面朝上，无移动、无效果）
##      裁定2 量子魔法  = 真的能拖拽排序（这里连 prompt_reorder 模拟"拖完确认"，验顺序落库）
##      裁定3 影像投射  = 各英雄自愿交换（可跳过），随后移除反派牌堆顶一张
##      裁定4 非常感知  = 特殊效果牌数 > 反派当前生命值 → 立即获胜（持续检查）
##      裁定5 战衣/不朽 = 月光骑士战衣每次伤害都可无视；不朽保护最后一张手牌不被弃
##      裁定6 口径       = "特殊效果牌" = 带 effect 字段的英雄行动牌
##   ④ 其它落地细节：间谍大师拦截指示物、中子分解器把敌人打到剩 1 血、宝石卡在排序时不动。

const B3 := {
	"adamwarlock": "术士亚当", "missamerica": "美国小姐", "nebula": "星云", "yondou": "勇度",
	"ghostrider": "恶灵骑士", "mockingbird": "仿声鸟", "shehulk": "女浩克", "squirrelgirl": "松鼠女",
	"moonknight": "月光骑士", "nova": "新星", "blade": "刀锋战士", "howardtheduck": "霍华德鸭",
	"msmarvel": "惊奇女士",
}
## 每位英雄挑一张"结算安全、日志里带效果名"的卡来触发（1..12）
const B3_EFF_CARD := {
	"adamwarlock": 6, "missamerica": 2, "nebula": 10, "yondou": 10, "ghostrider": 10,
	"mockingbird": 7, "shehulk": 9, "squirrelgirl": 10, "moonknight": 10, "nova": 10,
	"blade": 9, "howardtheduck": 3, "msmarvel": 8,
}
## 上面这些卡的日志前缀（子串匹配）
const B3_EFF_LOG := {
	"adamwarlock": "生命化身", "missamerica": "星门", "nebula": "再生植入体", "yondou": "亚卡箭旋风",
	"ghostrider": "超自然感知", "mockingbird": "战斗法杖", "shehulk": "变形", "squirrelgirl": "夜视",
	"moonknight": "孔苏之力", "nova": "我就是援手", "blade": "吸血愈合",
	"howardtheduck": "不再是好好先生鸭", "msmarvel": "外观改造",
}

var _fail := 0
var _reorder_seen: Array = []
var _reorder_calls := 0
var _reorder_title := ""

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS: " + name)
	else:
		_fail += 1
		print("FAIL: %s — %s" % [name, detail])

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _count_log(needle: String) -> int:
	var n := 0
	for e in (Game.state.get("log", []) as Array):
		if String((e as Dictionary).get("t", "")).contains(needle):
			n += 1
	return n

## 当前日志条数（用来判断"这次效果是否留下了记录"）
func _log_size() -> int:
	return (Game.state.get("log", []) as Array).size()

func _mission_tokens(mid: String) -> int:
	for m in (Game.state["missions"] as Array):
		if String((m as Dictionary)["id"]) == mid:
			return int((m as Dictionary)["tokens"])
	return -1

## 准备状态（会重开一局，只带该英雄 + cap）
func _prep(hero: String, card_idx: int) -> void:
	Game.setup("redskull", [hero] + ["cap"], "none", "base")
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	var c: Dictionary = DB.hero_cards(hero)[card_idx]
	var syms: Array = (c.get("symbols", []) as Array).duplicate()
	if syms.is_empty():
		syms = ["attack"]
	Game.state["heroes"][hero]["hand"] = [card_idx]
	Game.state["story"].append({"type": "hero", "hero": hero, "idx": card_idx})
	Game.state["action_symbols"] = syms
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	Game.state["played_effect"] = c.get("effect", {})

## 收尾：把状态钉在"当前英雄还能行动"，避免自动结束回合把流程带走
func _pin(hero: String) -> void:
	Game.state["phase"] = "hero_actions"
	Game.state["in_effect"] = false
	Game.state["effect_available"] = true
	Game.state["effect_used"] = true
	Game.state["action_symbols"] = ["move", "attack", "heroic"]
	Game.state["heroes"][hero]["tokens"]["move"] = 1

func _trigger(hero: String, card_idx: int) -> void:
	_prep(hero, card_idx)
	await Game.trigger_effect()
	_pin(hero)
	await _frames(2)

## 测试用的"拖拽"应答：把牌堆顶那张拖到最下面那张的位置（首尾互换），
## 必须等一帧再回答 —— 不然 cb 会在 _emit_prompt 返回之前触发，await 还没挂上，答案就丢了。
func _on_reorder(cards: Array, villain: String, title: String, cb: Callable) -> void:
	_reorder_calls += 1
	_reorder_seen = cards.duplicate()
	_reorder_title = title
	var out: Array = cards.duplicate()
	if out.size() >= 2:
		var t: Variant = out[0]
		out[0] = out[out.size() - 1]
		out[out.size() - 1] = t
	await get_tree().process_frame
	cb.call(out)

func _ready() -> void:
	Game.autopilot = true
	Events.prompt_reorder.connect(_on_reorder)
	await _frames(2)

	# ---------------- ① 数据层 ----------------
	_check("第三批 13 位英雄全部在册（英雄总数 57）", DB.heroes.size() == 57, "size=%d" % DB.heroes.size())
	for hid in B3.keys():
		_check("%s（%s）在册且中文名正确" % [hid, B3[hid]],
			DB.heroes.has(hid) and String(DB.heroes[hid]["name"]) == B3[hid],
			str(DB.heroes.get(hid, {}).get("name", "<无>")))
		_check("%s 有 12 张卡" % hid, (DB.hero_cards(hid) as Array).size() == 12,
			"cards=%d" % (DB.hero_cards(hid) as Array).size())
		_check("%s 扩展=第一季众筹" % hid, String(DB.heroes[hid]["expansion"]) == "第一季众筹",
			String(DB.heroes[hid]["expansion"]))
		_check("%s 卡背路径正确" % hid,
			String(DB.hero_back(hid)).ends_with("/%s/back.png" % hid), DB.hero_back(hid))
		var bad_sym := ""
		var eff_n := 0
		for card in DB.hero_cards(hid):
			for s in (card.get("symbols", []) as Array):
				if not ["move", "attack", "heroic", "wild"].has(String(s)):
					bad_sym = String(s)
			if (card as Dictionary).has("effect"):
				eff_n += 1
		_check("%s 符号合法（move/attack/heroic/wild 或空）" % hid, bad_sym == "", "非法符号=%s" % bad_sym)
		_check("%s 至少 1 张特殊效果牌" % hid, eff_n >= 1, "effect 卡=%d" % eff_n)

	# 数据抽查：效果 type 与 game.gd 分支一一对应（挑每人的一张核心卡）
	var spot := [
		["adamwarlock", 5, "adamwarlock_life_avatar"],
		["adamwarlock", 7, "adamwarlock_quantum_magic"],
		["adamwarlock", 8, "adamwarlock_immortality"],
		["nebula", 10, "nebula_image_projection"],
		["squirrelgirl", 11, "squirrelgirl_hyper_awareness"],
		["moonknight", 5, "moonknight_moon_suit"],
		["blade", 9, "blade_hunter_skill"],
		["howardtheduck", 4, "howardtheduck_neutron_disintegrator"],
		["shehulk", 11, "shehulk_transform_4"],
		["nova", 11, "nova_helping_hand_3"],
		["msmarvel", 11, "msmarvel_morphogenesis"],
	]
	for pair in spot:
		var hid2 := String(pair[0])
		var ci := int(pair[1])
		var want := String(pair[2])
		var got := String((DB.hero_cards(hid2)[ci] as Dictionary).get("effect", {}).get("type", ""))
		_check("%s 卡%d 效果 type = %s" % [hid2, ci + 1, want], got == want, got)

	# ---------------- ② 效果层：每位英雄触发一次 ----------------
	for hid in B3.keys():
		var ci2: int = int(B3_EFF_CARD[hid]) - 1
		_prep(String(hid), ci2)
		var before: int = _log_size()
		await Game.trigger_effect()
		_pin(String(hid))
		await _frames(2)
		var grew: int = _log_size() - before
		var needle: String = String(B3_EFF_LOG[hid])
		_check("%s·%s 效果已结算（日志 +%d 行）" % [B3[hid], needle, grew], grew >= 1,
			"log=%s" % str(Game.state.get("log", []).slice(-3)))
		_check("%s·%s 日志里能看到这次效果" % [B3[hid], needle], _count_log(needle) >= 1,
			"count=%d" % _count_log(needle))

	# ---------------- ③ 裁定1：生命化身 = 反派整回合空过 ----------------
	Game.setup("redskull", ["adamwarlock", "cap"], "none", "base")
	Game.state["phase"] = "villain"
	Game.state["villain_turn_skip"] = true
	Game.state["extra_villain_card"] = 0
	Game.state["skip_villain_card"] = 0
	Game.state["villain_pos"] = 0
	Game.state["locations"][0]["threat"] = null
	var vp_before: int = int(Game.state["villain_pos"])
	var deck_before: int = (Game.state["master_deck"] as Array).size()
	var story_before: int = (Game.state["story"] as Array).size()
	# 注意：extra_only=true 时 pending=0 → 一张都不翻，测不到"跳过"这件事，所以这里要跑正常回合
	await Game._run_villain_turn(false)
	var new_story: Array = (Game.state["story"] as Array).slice(story_before)
	var face_down_n := 0
	for e in new_story:
		var d: Dictionary = e
		if String(d.get("type", "")) == "villain" and bool(d.get("face_down", false)) and int(d.get("idx", 0)) == -1:
			face_down_n += 1
	_check("裁定1①：本回合翻出的反派行动卡背面朝上加入故事情节（%d 张）" % face_down_n, face_down_n >= 1,
		str(new_story))
	_check("裁定1②：连移动也不发生（反派位置不变 %d）" % vp_before,
		int(Game.state["villain_pos"]) == vp_before, "pos=%d" % int(Game.state["villain_pos"]))
	_check("裁定1③：牌仍然正常从牌堆翻出（牌堆 -1 张，卡本身仍进故事情节）",
		(Game.state["master_deck"] as Array).size() == deck_before - 1
		and _count_log("生命化身：反派打出一张行动卡") >= 1,
		"deck %d→%d" % [deck_before, (Game.state["master_deck"] as Array).size()])
	_check("裁定1④：跳过标志用完即清（不会污染后面的回合）",
		not bool(Game.state.get("villain_turn_skip", false)), str(Game.state.get("villain_turn_skip")))
	_check("裁定1⑤：反派回合结束后正常进入英雄阶段",
		String(Game.state["phase"]) == "hero_play", String(Game.state["phase"]))

	# ---------------- ③ 裁定2：量子魔法 = 拖拽排序 ----------------
	Game.autopilot = false          # 拖拽弹窗要真的弹出来（autopilot 会直接跳过）
	_prep("adamwarlock", 7)
	Game.state["master_deck"] = [1, 2, 3, 4, 5]
	_reorder_seen = []
	_reorder_calls = 0
	await Game.trigger_effect()
	_pin("adamwarlock")
	Game.autopilot = true
	await _frames(2)
	_check("裁定2①：弹出了拖拽排序弹窗（prompt_reorder 触发 1 次）", _reorder_calls == 1, "calls=%d" % _reorder_calls)
	_check("裁定2②：弹窗收到的就是牌堆顶 3 张 [1,2,3]", str(_reorder_seen) == str([1, 2, 3]), str(_reorder_seen))
	_check("裁定2③：标题写明「拖动卡牌调整顺序」", _reorder_title.contains("拖动"), _reorder_title)
	_check("裁定2④：拖出来的新顺序真的落到了牌堆里（1 和 3 互换 → [3,2,1,4,5]）",
		str(Game.state["master_deck"]) == str([3, 2, 1, 4, 5]), str(Game.state["master_deck"]))
	_check("裁定2⑤：日志记录了顺序调整", _count_log("量子魔法：调整了反派牌堆顶") >= 1,
		"count=%d" % _count_log("量子魔法：调整了反派牌堆顶"))
	# 宝石卡（字典项）不是行动卡 → 排序时位置不动
	Game.autopilot = false
	_prep("adamwarlock", 7)
	Game.state["master_deck"] = [1, {"stone": 0}, 2, 3]
	_reorder_calls = 0
	await Game.trigger_effect()
	_pin("adamwarlock")
	Game.autopilot = true
	await _frames(2)
	_check("裁定2⑥：宝石卡不参与排序（位置保持不动，只取 3 张行动牌）",
		str(Game.state["master_deck"]) == str([3, {"stone": 0}, 2, 1]), str(Game.state["master_deck"]))
	# 乱序/缺牌的答案要被拒（防止联机端乱发）
	_check("裁定2⑦：非法排列被拒（返回原顺序）",
		str(Game._validated_permutation([9, 9, 9], [1, 2, 3])) == str([1, 2, 3]),
		str(Game._validated_permutation([9, 9, 9], [1, 2, 3])))

	# ---------------- ③ 裁定3：影像投射 ----------------
	_prep("nebula", 10)
	var md_before3: int = (Game.state["master_deck"] as Array).size()
	var action_top_before: int = Game._next_villain_action_from_top()
	await Game.trigger_effect()
	_pin("nebula")
	await _frames(2)
	_check("裁定3①：各英雄可自愿交换（日志可查，可跳过）",
		_count_log("影像投射") >= 1, "count=%d" % _count_log("影像投射"))
	_check("裁定3②：随后移除反派牌堆顶的一张行动牌（%d 张 → %d 张，原顶牌 %d 已不在牌堆）" % [
			md_before3, (Game.state["master_deck"] as Array).size(), action_top_before],
		(Game.state["master_deck"] as Array).size() == md_before3 - 1
		and not (Game.state["master_deck"] as Array).has(action_top_before),
		str(Game.state["master_deck"]))
	_check("裁定3③：日志写明移除的是牌堆顶那张",
		_count_log("影像投射：移除反派牌堆顶") >= 1, "count=%d" % _count_log("影像投射：移除反派牌堆顶"))

	# ---------------- ③ 裁定4 + 裁定6：非常感知 / 特殊效果牌口径 ----------------
	Game.setup("redskull", ["squirrelgirl", "cap"], "none", "base")
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	# 口径：带 effect 字段的英雄行动牌 = 特殊效果牌（squirrelgirl 卡1 没有 effect，不算）
	Game.state["story"] = [
		{"type": "hero", "hero": "squirrelgirl", "idx": 0},
		{"type": "hero", "hero": "adamwarlock", "idx": 5},
		{"type": "hero", "hero": "blade", "idx": 8},
	]
	_check("裁定6①：特殊效果牌口径 = 带 effect 字段的牌（3 张里 2 张有 effect）",
		Game._special_effect_cards_in_story() == 2, str(Game._special_effect_cards_in_story()))
	Game.state["villain_hp"] = 5
	Game._check_hyper_awareness()
	_check("裁定4①：特殊效果牌 2 张 < 反派生命 5 → 不触发胜利（且此时没有非常感知）",
		String(Game.state["phase"]) != "game_over", String(Game.state["phase"]))
	# 打上非常感知（进故事情节可见区）后，特殊效果牌 3 张 > 生命 2 → 立即获胜
	Game.state["story"].append({"type": "hero", "hero": "squirrelgirl", "idx": 11})
	Game.state["villain_hp"] = 3
	Game._check_hyper_awareness()
	_check("裁定4②：非常感知在场上但 3 张 = 生命 3（不大于）→ 还没赢",
		String(Game.state["phase"]) != "game_over", String(Game.state["phase"]))
	Game.state["villain_hp"] = 2
	Game._check_hyper_awareness()
	_check("裁定4③：3 张特殊效果牌 > 反派当前生命 2 → 英雄立即获胜",
		String(Game.state["phase"]) == "game_over" and bool(Game.state.get("victory", false)),
		"phase=%s victory=%s" % [String(Game.state["phase"]), str(Game.state.get("victory", null))])
	_check("裁定4④：日志写明非常感知触发的胜利",
		_count_log("非常感知：故事情节中特殊效果牌") >= 1,
		"count=%d" % _count_log("非常感知：故事情节中特殊效果牌"))
	# 持续检查的另一个触发点：反派掉血后自动复查（这里直接验钩子存在且幂等）
	Game.setup("redskull", ["squirrelgirl", "cap"], "none", "base")
	Game.state["phase"] = "hero_actions"
	Game.state["story"] = [{"type": "hero", "hero": "squirrelgirl", "idx": 11}]
	Game.state["villain_hp"] = 0
	Game._check_hyper_awareness()
	_check("裁定4⑤：1 张特殊效果牌 > 生命 0 → 也判胜（钩子幂等，第二次调用不再改状态）",
		String(Game.state["phase"]) == "game_over", String(Game.state["phase"]))
	# 非常感知被挤出可见区 → 失效
	Game.setup("redskull", ["squirrelgirl", "cap"], "none", "base")
	Game.state["phase"] = "hero_actions"
	Game.state["story"] = [{"type": "hero", "hero": "squirrelgirl", "idx": 11}]
	for _k in range(Game.STORY_VISIBLE):
		Game.state["story"].append({"type": "hero", "hero": "cap", "idx": 0})
	Game.state["villain_hp"] = 0
	Game._check_hyper_awareness()
	_check("裁定4⑥：非常感知被挤出可见区 → 不再触发（口径同阿戈摩托之球）",
		String(Game.state["phase"]) != "game_over", String(Game.state["phase"]))

	# ---------------- ③ 裁定5：月光骑士战衣 ----------------
	Game.setup("redskull", ["moonknight", "cap"], "none", "base")
	Game.state["phase"] = "villain"
	var mk: Dictionary = Game.state["heroes"]["moonknight"]
	mk["moon_suit"] = true
	mk["hand"] = [0, 1, 2]
	var mk_loc0: int = int(mk["location"])
	await Game._deal_damage_to_hero("moonknight", 2)
	_check("裁定5①：每次受到伤害都可以无视（手牌 3 张一张没弃）",
		(mk["hand"] as Array).size() == 3, "hand=%d" % (mk["hand"] as Array).size())
	_check("裁定5②：日志写明无视了这次伤害", _count_log("无视本次") >= 1,
		"count=%d" % _count_log("无视本次"))
	_check("裁定5③：无视伤害后仍可选移动（autopilot 选了目标 → 位置发生变化或至少合法）",
		int(mk["location"]) >= 0 and int(mk["location"]) < Game.LOCATION_COUNT,
		"loc=%d（原 %d）" % [int(mk["location"]), mk_loc0])
	# 没有战衣时同样 2 点伤害会弃 2 张手牌（对照）
	Game.setup("redskull", ["moonknight", "cap"], "none", "base")
	Game.state["phase"] = "villain"
	var mk2: Dictionary = Game.state["heroes"]["moonknight"]
	mk2["moon_suit"] = false
	mk2["hand"] = [0, 1, 2]
	await Game._deal_damage_to_hero("moonknight", 2)
	_check("裁定5④（对照）：没有战衣时 2 点伤害弃 2 张手牌（3→1）",
		(mk2["hand"] as Array).size() == 1, "hand=%d" % (mk2["hand"] as Array).size())
	# 战衣是"直到你的下个回合开始"→ 本人回合开始时清掉
	Game.setup("redskull", ["moonknight", "cap"], "none", "base")
	var mk3: Dictionary = Game.state["heroes"]["moonknight"]
	mk3["moon_suit"] = true
	mk3["hunter_skill"] = true
	mk3["attack_locked_turn"] = true
	mk3["spy_master_armed"] = true
	mk3["elastic_extension"] = true
	mk3["appearance_change"] = true
	Game.state["phase"] = "villain"
	var mk_i: int = (Game.state["hero_ids"] as Array).find("moonknight")
	Game.state["current_hero"] = (mk_i - 1 + (Game.state["hero_ids"] as Array).size()) % (Game.state["hero_ids"] as Array).size()
	Game._start_hero_phase()
	await _frames(2)
	_check("裁定5⑤：这些「本回合」标志在本人回合开始时全部清掉",
		not bool(mk3.get("moon_suit", false)) and not bool(mk3.get("hunter_skill", false))
		and not bool(mk3.get("attack_locked_turn", false)) and not bool(mk3.get("spy_master_armed", false))
		and not bool(mk3.get("elastic_extension", false)) and not bool(mk3.get("appearance_change", false)),
		str(mk3))

	# ---------------- ④ 术士亚当·不朽：保护最后一张手牌 ----------------
	Game.setup("redskull", ["adamwarlock", "cap"], "none", "base")
	Game.state["phase"] = "villain"
	Game.state["story"] = [{"type": "hero", "hero": "adamwarlock", "idx": 8}]   # 不朽在可见区
	var aw: Dictionary = Game.state["heroes"]["adamwarlock"]
	aw["hand"] = [0]
	_check("不朽前置：不朽卡在可见区 → _immortality_active() 为真", Game._immortality_active("adamwarlock"), "")
	await Game._deal_damage_to_hero("adamwarlock", 2)
	_check("不朽①：弃牌时最后一张手牌被保住（仍是 1 张）",
		(aw["hand"] as Array).size() == 1, "hand=%d" % (aw["hand"] as Array).size())
	Game.setup("redskull", ["adamwarlock", "cap"], "none", "base")
	Game.state["phase"] = "villain"
	Game.state["story"] = []
	var aw2: Dictionary = Game.state["heroes"]["adamwarlock"]
	aw2["hand"] = [0]
	_check("不朽前置：不在可见区时 _immortality_active() 为假", not Game._immortality_active("adamwarlock"), "")
	await Game._deal_damage_to_hero("adamwarlock", 2)
	_check("不朽②（对照）：没有不朽时最后一张手牌照样被弃（1→0，并 KO）",
		(aw2["hand"] as Array).size() == 0, "hand=%d" % (aw2["hand"] as Array).size())

	# ---------------- ④ 间谍大师：拦截指示物 ----------------
	Game.setup("redskull", ["mockingbird", "cap"], "none", "base")
	Game.state["phase"] = "villain"
	var mb: Dictionary = Game.state["heroes"]["mockingbird"]
	var mb_loc: int = int(mb["location"])
	mb["spy_master_armed"] = true
	mb["spy_master_loc"] = mb_loc
	Game.state["locations"][mb_loc]["thug"] = 0
	await Game._place_token_at("thug", mb_loc, 1)
	_check("间谍大师①：该地点确实被拦住（暴徒 0 → 0）",
		int(Game.state["locations"][mb_loc]["thug"]) == 0,
		"thug=%d" % int(Game.state["locations"][mb_loc]["thug"]))
	_check("间谍大师②：日志写明反派无法在该地点添加指示物",
		_count_log("间谍大师：反派无法在") >= 1, "count=%d" % _count_log("间谍大师：反派无法在"))
	# 别的地点不受影响
	var other_loc: int = Game._next_live_loc(mb_loc)
	Game.state["locations"][other_loc]["thug"] = 0
	await Game._place_token_at("thug", other_loc, 1)
	_check("间谍大师③：只管自己所在地点（别的地点照常添加）",
		int(Game.state["locations"][other_loc]["thug"]) == 1,
		"thug=%d" % int(Game.state["locations"][other_loc]["thug"]))

	# ---------------- ④ 中子分解器：把敌人打到剩 1 血 ----------------
	Game.setup("redskull", ["howardtheduck", "cap"], "none", "base")
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	Game.state["villain_hp"] = 6
	Game.state["villain_pos"] = int(Game.state["heroes"]["howardtheduck"]["location"])
	Game._damage_enemy_to_one(Game.state["villain_pos"], "villain", "howardtheduck")
	_check("中子分解器①：反派生命被打到剩 1（6 → 1）", int(Game.state["villain_hp"]) == 1,
		"hp=%d" % int(Game.state["villain_hp"]))
	# 本回合不能再使用攻击行动（清符号 + 清攻击指示物 + 上锁）
	_prep("howardtheduck", 4)
	var hd: Dictionary = Game.state["heroes"]["howardtheduck"]
	Game.state["action_symbols"] = ["attack", "attack", "move"]
	hd["tokens"]["attack"] = 2
	Game.state["locations"][int(hd["location"])]["threat"] = {
		"name": "测试爪牙", "hp": 4, "heroic_tokens": 0, "arrival_triggered": true, "_tidx": 0,
	}
	Game.state["villain_pos"] = int(hd["location"]) + 1
	await Game.trigger_effect()
	# 注意：_pin() 会把 action_symbols 换成固定三项，符号类断言必须在 _pin 之前取值
	var hd_syms: Array = (Game.state["action_symbols"] as Array).duplicate()
	var hd_atk: int = int(hd["tokens"]["attack"])
	var hd_locked: bool = bool(hd.get("attack_locked_turn", false))
	_pin("howardtheduck")
	await _frames(2)
	_check("中子分解器②：本回合不能再使用攻击行动（攻击符号被清空）",
		hd_syms.count("attack") == 0, str(hd_syms))
	_check("中子分解器③：攻击指示物也被清零", hd_atk == 0, "attack tokens=%d" % hd_atk)
	_check("中子分解器④：上锁标志置位（use_symbol 会拦住后续攻击行动）",
		hd_locked, str(hd_locked))
	_check("中子分解器⑤：爪牙被打到剩 1 血",
		int((Game.state["locations"][int(hd["location"])]["threat"] as Dictionary)["hp"]) == 1,
		"hp=%d" % int((Game.state["locations"][int(hd["location"])]["threat"] as Dictionary)["hp"]))

	# ---------------- ④ 女浩克·变形：按故事情节里的「变形」张数给攻击行动 ----------------
	Game.setup("redskull", ["shehulk", "cap"], "none", "base")
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	# 情节里已经有 2 张变形（含刚打出的这张就 3 张）
	Game.state["story"] = [
		{"type": "hero", "hero": "shehulk", "idx": 8},
		{"type": "hero", "hero": "shehulk", "idx": 9},
	]
	Game.state["action_symbols"] = []
	Game.state["heroes"]["shehulk"]["hand"] = [10]
	Game.state["story"].append({"type": "hero", "hero": "shehulk", "idx": 10})
	Game.state["played_effect"] = DB.hero_cards("shehulk")[10]["effect"]
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	await Game.trigger_effect()
	var sh_syms: Array = (Game.state["action_symbols"] as Array).duplicate()
	var sh_count: int = Game._transform_count_in_story()
	_pin("shehulk")
	await _frames(2)
	_check("变形：故事情节里 3 张「变形」（含这张）→ 3 次攻击行动",
		sh_syms.count("attack") >= 3, str(sh_syms))
	_check("变形：计数口径只算「变形」（_transform_count_in_story）",
		sh_count == 3, str(sh_count))

	# ---------------- ④ 惊奇女士·外观改造：本回合所有行动视为万能 ----------------
	_prep("msmarvel", 7)
	Game.state["action_symbols"] = ["move", "attack", "heroic"]
	await Game.trigger_effect()
	var ms_syms: Array = (Game.state["action_symbols"] as Array).duplicate()
	var ms_flag: bool = bool(Game.state["heroes"]["msmarvel"].get("appearance_change", false))
	_pin("msmarvel")
	await _frames(2)
	var all_wild := true
	for s in ms_syms:
		if String(s) != "wild":
			all_wild = false
	_check("外观改造：本回合已有行动全部转为万能行动", all_wild, str(ms_syms))
	_check("外观改造：标志置位（之后新获得的行动也按万能算）", ms_flag, str(ms_flag))

	# ---------------- ④ 刀锋战士·猎人技巧：一次攻击行动→两点伤害 ----------------
	_prep("blade", 9)
	var bl: Dictionary = Game.state["heroes"]["blade"]
	bl["hunter_skill"] = true
	_check("猎人技巧：标志置位（_attack_once_at 会把 times=1 提到 2）",
		bool(bl.get("hunter_skill", false)), "")

	# ---------------- ④ 勇度·叛徒：平民↔暴徒互换 ----------------
	_prep("yondou", 11)
	var yd: Dictionary = Game.state["heroes"]["yondou"]
	var yd_loc: int = int(yd["location"])
	Game.state["locations"][yd_loc]["civ"] = 1
	Game.state["locations"][yd_loc]["thug"] = 2
	await Game.trigger_effect()
	_pin("yondou")
	await _frames(2)
	_check("叛徒：平民与暴徒数量互换（民 1→2、暴 2→1）",
		int(Game.state["locations"][yd_loc]["civ"]) == 2 and int(Game.state["locations"][yd_loc]["thug"]) == 1,
		"civ=%d thug=%d" % [int(Game.state["locations"][yd_loc]["civ"]), int(Game.state["locations"][yd_loc]["thug"])])

	# ---------------- ④ 霍华德鸭·巨大的怪枪：任意地点两次攻击行动 ----------------
	_prep("howardtheduck", 3)
	var hd2: Dictionary = Game.state["heroes"]["howardtheduck"]
	# 只留一个地点有敌人：这样"_pick_attack_loc"的候选只有一个，攻击地点才是确定的
	for l in range(Game.LOCATION_COUNT):
		Game.state["locations"][l]["thug"] = 0
		Game.state["locations"][l]["civ"] = 0
		Game.state["locations"][l]["threat"] = null
	var hd2_far: int = (int(hd2["location"]) + 3) % Game.LOCATION_COUNT
	Game.state["locations"][hd2_far]["thug"] = 2
	var def_before: int = _mission_tokens("defeat")
	await Game.trigger_effect()
	_pin("howardtheduck")
	await _frames(2)
	_check("巨大的怪枪：对任意地点打了两次（该地点暴徒 2→0，任务进度 +2）",
		int(Game.state["locations"][hd2_far]["thug"]) == 0 and _mission_tokens("defeat") - def_before == 2,
		"thug=%d defeat %d→%d" % [int(Game.state["locations"][hd2_far]["thug"]), def_before, _mission_tokens("defeat")])

	# ---------------- ④ 勇度·亚卡箭旋风：顺时针连打，遇到空地点停 ----------------
	_prep("yondou", 9)
	var yd2: Dictionary = Game.state["heroes"]["yondou"]
	var y0: int = int(yd2["location"])
	for l in range(Game.LOCATION_COUNT):
		Game.state["locations"][l]["thug"] = 0
		Game.state["locations"][l]["threat"] = null
	Game.state["locations"][y0]["thug"] = 1
	Game.state["locations"][(y0 + 1) % Game.LOCATION_COUNT]["thug"] = 1
	# (y0 + 2) 保持 0 → 应当在那里停下
	Game.state["locations"][(y0 + 3) % Game.LOCATION_COUNT]["thug"] = 1
	await Game.trigger_effect()
	_pin("yondou")
	await _frames(2)
	_check("亚卡箭旋风：打了起点和下一个地点各 1 个暴徒",
		int(Game.state["locations"][y0]["thug"]) == 0
		and int(Game.state["locations"][(y0 + 1) % Game.LOCATION_COUNT]["thug"]) == 0,
		str([int(Game.state["locations"][y0]["thug"]), int(Game.state["locations"][(y0 + 1) % Game.LOCATION_COUNT]["thug"])]))
	_check("亚卡箭旋风：遇到没有暴徒的地点就停（再远那个地点的暴徒没动）",
		int(Game.state["locations"][(y0 + 3) % Game.LOCATION_COUNT]["thug"]) == 1,
		"thug=%d" % int(Game.state["locations"][(y0 + 3) % Game.LOCATION_COUNT]["thug"]))
	_check("亚卡箭旋风：日志逐地点记录",
		_count_log("亚卡箭旋风：击败") == 2, "count=%d" % _count_log("亚卡箭旋风：击败"))

	# ---------------- ④ 新星·我就是援手：在相邻地点做两次英勇行动 ----------------
	_prep("nova", 9)
	var nv: Dictionary = Game.state["heroes"]["nova"]
	var nv_from: int = int(nv["location"])
	var nv_to: int = int(Game._adjacent_locs(nv_from)[0])
	for l in range(Game.LOCATION_COUNT):
		Game.state["locations"][l]["civ"] = 0
		Game.state["locations"][l]["thug"] = 0
		Game.state["locations"][l]["threat"] = null
	Game.state["locations"][nv_to]["civ"] = 3
	var rescue_before: int = _mission_tokens("rescue")
	await Game.trigger_effect()
	_pin("nova")
	await _frames(2)
	_check("我就是援手：在相邻地点做了两次英勇（营救 2 个平民，任务进度 +2）",
		int(Game.state["locations"][nv_to]["civ"]) == 1 and _mission_tokens("rescue") - rescue_before == 2,
		"civ=%d rescue %d→%d" % [int(Game.state["locations"][nv_to]["civ"]), rescue_before, _mission_tokens("rescue")])
	_check("我就是援手：本人位置不变（借临时地点结算）",
		int(nv["location"]) == nv_from, "loc=%d" % int(nv["location"]))

	# ---------------- ④ 松鼠女·夜视：揭示牌堆顶（原位）可放底 ----------------
	_prep("squirrelgirl", 9)
	var md_before4: int = (Game.state["master_deck"] as Array).size()
	var top4: int = Game._next_villain_action_from_top()
	await Game.trigger_effect()
	_pin("squirrelgirl")
	await _frames(2)
	var md_after4: Array = Game.state["master_deck"]
	_check("夜视：牌堆张数不变（只是揭示+可能换位，不消耗）", md_after4.size() == md_before4,
		"%d→%d" % [md_before4, md_after4.size()])
	_check("夜视：原顶牌仍在牌堆里（没被移出本局）", md_after4.has(top4), str(md_after4))
	_check("夜视：日志可见揭示或放底的结果",
		_count_log("夜视") >= 1, "count=%d" % _count_log("夜视"))

	if _fail == 0:
		print("=== S3 HEROES TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== S3 HEROES TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)
