extends Node
## 溢出"一次结算只结算一次"全反派审计：
## 规则：一次结算（一次 BAM！／一张卡的一次效果／一次放置）里，**同一地点**放不下
## 1 个或多个平民/暴徒，默认**只结算一次溢出**；反派 / 爪牙 / 威胁卡同一口径。
## 只有卡面明确按数量结算的（红骷髅/模仿大师/暗夜比邻星/罗南）才按放不下的**数量**结算。
var _fail := 0
func _check(n: String, ok: bool, d: String) -> void:
	if ok: print("PASS: " + n)
	else: _fail += 1; print("FAIL: " + n + " — " + d)

## 本次测试中，某地点被结算溢出的次数
func _settles_at(loc: int) -> int:
	var n := 0
	for l in Game.state.get("overflow_settled_locs", []):
		if int(l) == loc:
			n += 1
	return n

## 把指定地点重置为"已满且未被摧毁"，并清掉危机/回合状态，保证每一步都在干净前提下测试
func _prep(locs: Array, zero_counter: bool = true) -> void:
	Game.state["phase"] = "hero_actions"
	# 英雄起始点是随机的（setup 里 villain_pos = randi_range(...)，英雄又在"正对面"）：
	# 若英雄正好站在被测地点上，corvus/thanos 这类"溢出打英雄"的反派会打掉手牌 → KO →
	# 累计 KO 指示物触发判负 → game_over 把后续放置短路，本测试就时红时绿。
	# 统一把英雄挪到不在 locs 里的地点并补满手牌，让每一步都在确定前提下测试。
	var safe := 0
	for _i in range(Game.LOCATION_COUNT):
		if not locs.has(_i):
			safe = _i
			break
	for hid in Game.state["hero_ids"]:
		var h: Dictionary = Game.state["heroes"][hid]
		h["location"] = safe
		h["ko"] = false
		h["hand"] = [0, 1, 2]
	Game.state["ko_tokens"] = 0
	for _l in Game.state["locations"]:
		_l["crisis"] = 0
		_l["destroyed"] = false
		_l["threat"] = null
	for i in locs:
		var ld: Dictionary = Game.state["locations"][int(i)]
		var slots_total: int = int(DB.location(ld["id"])["slots"])
		ld["civ"] = slots_total     # 民+暴 == 槽位 → 已满
		ld["thug"] = 0
	if zero_counter:
		Game.state["overflow_settled"] = 0
		Game.state["overflow_settled_locs"] = []

func _ready() -> void:
	Game.autopilot = true
	var ids: Array = VillainRules.IDS
	_check("反派总数与 DB 一致", ids.size() == DB.villains.size(), "%d" % ids.size())

	for vid in ids:
		Game.setup(String(vid), ["cap", "ironman"], "none", "base")
		var loc := 2
		var loc2: int = (loc + 1) % Game.LOCATION_COUNT
		_prep([loc, loc2])

		# ① 同一次结算：同一地点连续 3 次放不下 → 该地点只结算 1 次
		_prep([loc, loc2])
		Game._begin_overflow_event()
		await Game._place_token_at("civ", loc, 3)
		var n1: int = _settles_at(loc)
		_check("[%s] 一次结算同一地点只结算 1 次溢出" % vid, n1 == 1,
			"该地点结算次数=%d（本次全部=%d）" % [n1, int(Game.state["overflow_settled"])])

		# ② 同一次结算：连续多次调用（民+暴各一次）→ 该地点仍然只 1 次
		_prep([loc, loc2])
		Game._begin_overflow_event()
		await Game._place_token_at("civ", loc, 1)
		await Game._place_token_at("thug", loc, 1)
		var n2: int = _settles_at(loc)
		_check("[%s] 一次结算内民+暴各放不下也只结算 1 次" % vid, n2 == 1, "该地点结算次数=%d" % n2)

		# ③ 同一次结算：两个不同地点各放不下 → 各结算 1 次
		_prep([loc, loc2])
		Game._begin_overflow_event()
		await Game._place_token_at("civ", loc, 1)
		await Game._place_token_at("civ", loc2, 1)
		var n3: int = _settles_at(loc)
		var n3b: int = _settles_at(loc2)
		_check("[%s] 一次结算两个地点各结算 1 次（按地点各一次）" % vid, n3 == 1 and n3b == 1,
			"loc%d=%d loc%d=%d" % [loc, n3, loc2, n3b])

		# ④ 两次独立结算（各带一次 begin）→ 该地点各 1 次，共 2 次（确认守卫不会过度抑制）
		_prep([loc, loc2])
		Game._begin_overflow_event()
		await Game._place_token_at("civ", loc, 1)
		_prep([loc, loc2], false)   # 章鱼博士等会让危机>=3 的地点被摧毁，重置地点但保留计数
		Game._begin_overflow_event()
		await Game._place_token_at("civ", loc, 1)
		var n4: int = _settles_at(loc)
		_check("[%s] 两次独立结算 = 该地点 2 次" % vid, n4 == 2, "该地点结算次数=%d" % n4)

	# ---------- 章鱼博士威胁卡「神秘客」：BAM 一次放 1 民 + 1 暴 → 只 1 个危机 ----------
	Game.setup("docock", ["cap", "ironman"], "none", "base")
	for _l in Game.state["locations"]:
		_l["crisis"] = 0
		_l["threat"] = null
	Game.state["overflow_settled"] = 0
	var tloc := 1
	var tl: Dictionary = Game.state["locations"][tloc]
	var tslots: int = int(DB.location(tl["id"])["slots"])
	tl["civ"] = tslots          # 该地点已满
	tl["thug"] = 0
	tl["threat"] = {"name": "神秘客", "text": "", "hp": 3, "henchman_hp": 3, "heroic_tokens": 0,
		"arrival": false, "arrival_triggered": false, "bam": true, "start_turn": false, "constant": false}
	await Game._trigger_all_threat_bam()
	_check("章鱼博士·神秘客威胁 BAM：放不下 1 民 + 1 暴 → 只加 1 个危机",
		int(tl["crisis"]) == 1 and int(Game.state["overflow_settled"]) == 1,
		"crisis=%d 结算次数=%d" % [int(tl["crisis"]), int(Game.state["overflow_settled"])])

	# ---------- 反派面板 BAM 一次结算也只一次（章鱼博士 BAM：1 伤 + 该地点 +1 危机） ----------
	Game.setup("docock", ["cap", "ironman"], "none", "base")
	for _l in Game.state["locations"]:
		_l["crisis"] = 0
	Game.state["overflow_settled"] = 0
	await Game._trigger_panel_bam()
	_check("反派面板 BAM 不产生多余溢出结算", int(Game.state["overflow_settled"]) == 0,
		"结算次数=%d" % int(Game.state["overflow_settled"]))

	if _fail == 0:
		print("=== OVERFLOW ONCE TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== OVERFLOW ONCE FAILED (%d) ===" % _fail)
		get_tree().quit(1)
