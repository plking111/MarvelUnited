extends Node
## 灭霸 BAM 伤害范围回归（用户报的 bug）：
## 卡面口径 = 对**灭霸所在地点**的每个英雄造成 2 点伤害，然后对**两个相邻地点**的每个英雄各造成 1 点伤害。
## 旧实现写成"凡是不在灭霸所在地点的英雄都受 1 点"→ 整张地图都被打了一遍（非相邻地点也挨打）。
##
## 用例：
##   ① 数据文案：`thanos.bam` 必须是"两个相邻地点"，不能再出现"不同地点每个英雄"（防文案回退）
##   ② 所在地点每个英雄 2 点
##   ③ 顺时针相邻地点每个英雄 1 点
##   ④ 逆时针相邻地点每个英雄 1 点
##   ⑤ **非相邻地点（含正对面）的英雄完全不被 BAM 打到** ← 旧实现下必然失败
##   ⑥ 相邻地点恰好 2 个（不是"全部其他地点"）
var _fail: int = 0

func _check(n: String, ok: bool, d: String = "") -> void:
	if ok:
		print("PASS: " + n)
	else:
		_fail += 1
		print("FAIL: %s — %s" % [n, d])

## 干净开局：清场（无威胁/无指示物），英雄满手牌未 KO
func _prep() -> int:
	Game.setup("thanos", ["cap", "ironman", "hulk"], "none", "base")
	for l in Game.state["locations"]:
		l["civ"] = 0
		l["thug"] = 0
		l["crisis"] = 0
		l["threat"] = null
		l["destroyed"] = false
	for hid in Game.state["hero_ids"]:
		var h: Dictionary = Game.state["heroes"][hid]
		h["ko"] = false
		h["crisis"] = 0
		h["hand"] = [0, 1, 2, 3]
		h["invulnerable"] = false
	Game.state["phase"] = "hero_actions"
	Game.state["villain_hp"] = 999        # 避免 BAM 之外的因素影响
	return int(Game.state["villain_pos"])

func _hand(hid: String) -> int:
	return (Game.state["heroes"][hid]["hand"] as Array).size()

func _ready() -> void:
	Game.autopilot = true
	var N: int = int(Game.LOCATION_COUNT)

	# ---------------- ① 数据文案 ----------------
	var bam_txt: String = String(DB.villain("thanos")["bam"])
	_check("① thanos.bam 文案 = 「两个相邻地点…各造成 1 点伤害」", bam_txt.contains("两个相邻地点"), bam_txt)
	_check("① thanos.bam 文案不再出现旧的「不同地点的每个英雄」（防回退）",
		not bam_txt.contains("不同地点"), bam_txt)

	# ---------------- ⑥ 相邻地点恰好 2 个 ----------------
	var vpos: int = _prep()
	var adj: Array = Game._adjacent_locs(vpos)
	_check("⑥ 灭霸所在地点的「相邻地点」恰好 2 个（不是全部其他地点，共 %d 个地点）" % N,
		adj.size() == 2, "adj=%s" % str(adj))

	# ---------------- ②③⑤-B 第一轮：所在地点 / 顺时针相邻 / 正对面 ----------------
	vpos = _prep()
	adj = Game._adjacent_locs(vpos)
	var cw: int = int(adj[0])                    # 顺时针相邻
	var ccw: int = int(adj[1])                   # 逆时针相邻
	var opp: int = (vpos + 3) % N                # 正对面（非相邻）
	Game.state["heroes"]["hulk"]["location"] = vpos
	Game.state["heroes"]["cap"]["location"] = cw
	Game.state["heroes"]["ironman"]["location"] = opp
	await Game._trigger_panel_bam()
	_check("② 灭霸所在地点的英雄受到 2 点伤害（手牌 4→2）", _hand("hulk") == 2, "hulk hand=%d" % _hand("hulk"))
	_check("③ 顺时针相邻地点的英雄受到 1 点伤害（手牌 4→3）", _hand("cap") == 3, "cap hand=%d" % _hand("cap"))
	_check("⑤ 非相邻地点（正对面 %s）的英雄完全不被 BAM 打到（手牌仍为 4）" % Game._loc_name(opp),
		_hand("ironman") == 4, "ironman hand=%d" % _hand("ironman"))

	# ---------------- ④⑤-A 第二轮：逆时针相邻 / 另一个非相邻地点 ----------------
	vpos = _prep()
	adj = Game._adjacent_locs(vpos)
	cw = int(adj[0])
	ccw = int(adj[1])
	var far: int = (vpos + 2) % N                # 与"顺时针相邻"隔一格 → 非相邻
	Game.state["heroes"]["hulk"]["location"] = vpos
	Game.state["heroes"]["cap"]["location"] = ccw
	Game.state["heroes"]["ironman"]["location"] = far
	await Game._trigger_panel_bam()
	_check("④ 逆时针相邻地点的英雄受到 1 点伤害（手牌 4→3）", _hand("cap") == 3, "cap hand=%d" % _hand("cap"))
	_check("⑤ 另一个非相邻地点（%s，与相邻点隔一格）的英雄不被 BAM 打到（手牌仍为 4）" % Game._loc_name(far),
		_hand("ironman") == 4, "ironman hand=%d" % _hand("ironman"))
	_check("② 所在地点 2 点（第二轮复核）", _hand("hulk") == 2, "hulk hand=%d" % _hand("hulk"))

	# ---------------- 边界：相邻地点没有英雄时不报错、不误伤 ----------------
	vpos = _prep()
	adj = Game._adjacent_locs(vpos)
	Game.state["heroes"]["hulk"]["location"] = vpos
	Game.state["heroes"]["cap"]["location"] = (vpos + 3) % N
	Game.state["heroes"]["ironman"]["location"] = (vpos + 4) % N
	await Game._trigger_panel_bam()
	_check("边界：相邻两地点都没有英雄 → 只有所在地点英雄受 2 点，其余两人不受影响",
		_hand("hulk") == 2 and _hand("cap") == 4 and _hand("ironman") == 4,
		"hulk=%d cap=%d ironman=%d" % [_hand("hulk"), _hand("cap"), _hand("ironman")])

	# ---------------- 边界：所有英雄都在灭霸所在地点 ----------------
	vpos = _prep()
	for hid in Game.state["hero_ids"]:
		Game.state["heroes"][hid]["location"] = vpos
	await Game._trigger_panel_bam()
	_check("边界：所有英雄都在所在地点 → 每人只受 2 点（不会因为「不在相邻地点」再补 1 点）",
		_hand("cap") == 2 and _hand("ironman") == 2 and _hand("hulk") == 2,
		"cap=%d ironman=%d hulk=%d" % [_hand("cap"), _hand("ironman"), _hand("hulk")])

	print("---- RESULT ----")
	if _fail == 0:
		print("=== THANOS BAM TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== THANOS BAM TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)
