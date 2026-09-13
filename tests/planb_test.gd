extends Node
## B计划挑战测试：专属任务卡(12/12/6)+完成全部3张直接获胜
var _fail := 0
func _check(n: String, ok: bool, d: String) -> void:
	if ok: print("PASS: " + n)
	else: _fail += 1; print("FAIL: " + n + " — " + d)

func _ready() -> void:
	Game.autopilot = true
	Game.setup("redskull", ["cap", "ironman", "hulk"], "planb", "base")
	var ms: Array = Game.state["missions"]
	_check("B计划3张任务卡", ms.size() == 3, "size=%d" % ms.size())
	var slots: Array = []
	var imgs_ok := true
	var layout_ok := true
	for m in ms:
		slots.append(int(m["slots"]))
		if String(m.get("img", "")) == "":
			imgs_ok = false
		if not (m.has("xs") and m.has("ys")):
			layout_ok = false
	_check("任务数值 12/12/6", slots == [12, 12, 6], str(slots))
	_check("三张卡都有卡图", imgs_ok, "")
	_check("三张卡都有槽位坐标", layout_ok, "")
	_check("第三张名为化解威胁", String(ms[2]["name"]) == "化解威胁", String(ms[2]["name"]))
	# 完成 1、2 张：不应获胜
	Game._add_mission_token("rescue", 12)
	_check("完成1张未获胜", Game.state["missions_completed"] == 1 and not Game.state.get("victory", false),
		"done=%d victory=%s" % [Game.state["missions_completed"], str(Game.state.get("victory", false))])
	Game._add_mission_token("defeat", 12)
	_check("完成2张未获胜", Game.state["missions_completed"] == 2 and not Game.state.get("victory", false),
		"done=%d victory=%s" % [Game.state["missions_completed"], str(Game.state.get("victory", false))])
	# 完成第 3 张：直接获胜
	Game._add_mission_token("clear", 6)
	_check("完成3张直接获胜", Game.state["missions_completed"] == 3 and Game.state.get("victory", false) == true,
		"done=%d victory=%s phase=%s" % [Game.state["missions_completed"], str(Game.state.get("victory", false)), Game.state["phase"]])
	if _fail == 0:
		print("=== PLANB TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== PLANB FAILED (%d) ===" % _fail)
		get_tree().quit(1)
