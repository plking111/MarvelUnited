extends Node
## 罗南 setup 验证：确认 villains.json 加载、威胁卡初始化、行动卡特殊 move 能被引擎识别。

var _fail := 0

func _ready() -> void:
	Game.autopilot = true
	await _test_ronan_setup()
	if _fail == 0:
		print("=== RONAN SETUP TEST ALL PASSED ===")
		get_tree().quit(0)
	else:
		print("=== RONAN SETUP TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)

func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		_fail += 1
		print("FAIL: %s — %s" % [name, detail])
	else:
		print("PASS: %s — %s" % [name, detail])

func _test_ronan_setup() -> void:
	_check("反派数量为10", DB.villains.size() == 10, "size=%d" % DB.villains.size())
	Game.setup("ronan", ["cap", "ironman", "hulk"], "none")
	# 检查威胁卡初始化：6 个地点各1张，罗南威胁卡应有 clear 字段
	var has_clear := false
	var total_threats := 0
	for l in Game.state["locations"]:
		var t: Variant = l["threat"]
		if t != null:
			total_threats += 1
			if t.has("clear"):
				has_clear = true
				_check("威胁卡 clear_progress 已初始化", t.has("clear_progress"), "%s clear_progress存在" % t["name"])
	_check("6处地点都有威胁卡", total_threats == 6, "total=%d" % total_threats)
	_check("罗南威胁卡为符号清除型", has_clear, "has_clear=%s" % str(has_clear))
	_check("KO指示物初始为0", 0 == int(Game.state.get("ko_tokens", 0)), "ko=%d" % Game.state.get("ko_tokens", 0))
	# 行动卡 move 描述：确认 engine 能识别（不崩溃）
	var vill: Dictionary = DB.villains["ronan"]
	var ok_move := true
	for a in vill["actions"]:
		var d: String = Game._move_desc(a.get("move", 0))
		if d == "":
			ok_move = false
	_check("行动卡 move 描述可生成", ok_move, "all move desc ok")
	print("罗南行动卡 move 描述示例:", Game._move_desc(vill["actions"][0].get("move", 0)))
