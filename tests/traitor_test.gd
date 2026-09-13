extends Node
## 叛徒挑战模式逻辑测试：身份发放/不信任/背面出牌/指认接管
var _fail := 0
func _check(n: String, ok: bool, d: String) -> void:
	if ok: print("PASS: " + n)
	else: _fail += 1; print("FAIL: " + n + " — " + d)

func _ready() -> void:
	Game.autopilot = true
	Game.setup("redskull", ["cap", "ironman", "hulk"], "traitor", "base")
	# 1. 身份发放：3 人 → 2 忠臣 1 叛徒
	var tr_count := 0
	for hid in Game.state["hero_ids"]:
		if Game.state["loyalty"].get(hid, "") == "traitor":
			tr_count += 1
	_check("身份发放(3人)", Game.state["loyalty"].size() == 3 and tr_count == 1,
		"loyalty=%s traitor=%d" % [str(Game.state["loyalty"]), tr_count])
	_check("叛徒已标记", Game.state["traitor_hid"] != "" and Game.state["loyalty"][Game.state["traitor_hid"]] == "traitor",
		"traitor_hid=%s" % Game.state["traitor_hid"])
	# 2. 每人 1 不信任 + 1 万能补偿
	var all_ok := true
	for hid in Game.state["hero_ids"]:
		var h: Dictionary = Game.state["heroes"][hid]
		if h.get("distrust", 0) != 1 or h["tokens"]["wild"] < 1:
			all_ok = false
	_check("每人1不信任+1万能", all_ok, "")
	# 3. 背面出牌丢弃不信任
	Game.state["phase"] = "hero_play"
	var cap: Dictionary = Game.state["heroes"]["cap"]
	cap["hand"] = [0, 1, 2]
	var d0: int = cap["distrust"]
	Game.state["current_hero"] = Game.state["hero_ids"].find("cap")
	Game.play_card_face_down(0)
	_check("背面出牌丢弃不信任", cap["distrust"] == 0 and cap["distrust"] == d0 - 1, "distrust %d->%d" % [d0, cap["distrust"]])
	var last: Dictionary = Game.state["story"].back()
	_check("面朝下入故事情节", last.get("face_down", false) == true and last["type"] == "hero", "last=%s" % str(last))
	_check("背面牌无自身符号", Game.state["action_symbols"].size() == 0, "symbols=%s" % str(Game.state["action_symbols"]))
	# 4. 完成第2个任务 → 只置待处理标记（不再立即结算，避免与地点结算/反派回合交错）
	Game.state["phase"] = "hero_actions"
	var before_heroes: int = Game.state["hero_ids"].size()
	Game.state["missions_completed"] = 1
	Game._complete_mission(Game.state["missions"][0])
	_check("2任务后仅置待处理标记", Game.state.get("traitor_pending", false) == true and Game.state["traitor_active"] == false,
		"pending=%s active=%s" % [str(Game.state.get("traitor_pending", false)), str(Game.state["traitor_active"])])
	# 5. 回合结束流程中按顺序执行指认 → 叛徒接管
	Game.state["traitor_pending"] = false
	await Game._run_traitor_accusation()
	_check("叛徒离开并接管", Game.state["traitor_active"] == true, "traitor_active=%s" % str(Game.state["traitor_active"]))
	_check("英雄减少1(叛徒移除)", Game.state["hero_ids"].size() == before_heroes - 1, "%d->%d" % [before_heroes, Game.state["hero_ids"].size()])
	_check("未弃不信任的忠臣被KO", _any_loyal_ko(), "")
	if _fail == 0:
		print("=== TRAITOR TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== TRAITOR FAILED (%d) ===" % _fail)
		get_tree().quit(1)

func _any_loyal_ko() -> bool:
	for hid in Game.state["hero_ids"]:
		if Game.state["loyalty"].get(hid, "") == "loyal" and Game.state["heroes"][hid].get("distrust", 0) > 0 and Game.state["heroes"][hid]["ko"]:
			return true
	return false
