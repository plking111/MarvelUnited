extends Node
## 至圣所放置罗南 clear 型威胁卡符号指示物验证：
## 至圣所应能放"符合威胁卡需求"的符号（移动/英勇/攻击），而非只放英勇。

var _fail := 0

func _ready() -> void:
	await _test_sanctum_ronan()
	if _fail == 0:
		print("=== SANCTUM RONAN TEST ALL PASSED ===")
		get_tree().quit(0)
	else:
		print("=== SANCTUM RONAN TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)

func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		_fail += 1
		print("FAIL: %s — %s" % [name, detail])
	else:
		print("PASS: %s — %s" % [name, detail])

func _test_sanctum_ronan() -> void:
	Game.autopilot = true
	Game.setup("ronan", ["cap"], "none")
	await Game.start_game()
	var guard := 0
	while Game.state["phase"] != "hero_play" and guard < 300:
		guard += 1
		await get_tree().process_frame
	Game.autopilot = false

	# 找一个 clear 型威胁卡（罗南：太空伏击/越狱/克里精英部队）
	var clear_loc := -1
	for i in range(Game.state["locations"].size()):
		var t: Variant = Game.state["locations"][i]["threat"]
		if t != null and t.has("clear"):
			clear_loc = i
			break
	if clear_loc < 0:
		_check("找到 clear 型威胁卡位置", false, "地图上无 clear 威胁卡")
		return
	var t0: Dictionary = Game.state["locations"][clear_loc]["threat"]
	var placeable: String = Game._threat_placeable_sym(t0)
	print("clear 威胁卡: %s clear=%s 可放符号=%s" % [t0["name"], str(t0["clear"]), placeable])
	_check("至圣所判定出可放符号", placeable != "", "placeable=" + str(placeable))
	if placeable == "":
		return
	var before: int = t0.get("clear_progress", []).size()
	# 调用至圣所放置（hid=cap, loc=clear_loc），自动确认放本地威胁卡
	var conn := func(text: String, cb: Callable) -> void:
		await get_tree().process_frame
		cb.call(true)
	Events.prompt_confirm.connect(conn)
	await Game._sanctum_place_token("cap", clear_loc)
	Events.prompt_confirm.disconnect(conn)
	var t1: Dictionary = Game.state["locations"][clear_loc]["threat"]
	var after: int = t1.get("clear_progress", []).size()
	print("至圣所放置后 clear_progress: %d (期望 > %d), 放符号=%s" % [after, before, placeable])
	_check("至圣所在罗南威胁卡上放置符号指示物", after > before, "clear_progress %d->%d" % [before, after])
	_check("放置的是符合威胁卡的符号", placeable in t1["clear"], "placeable=%s in clear=%s" % [placeable, str(t1["clear"])])
