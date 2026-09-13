extends Node
## 危机指示物（战利品）图标位置回归：必须放在**威胁卡右侧**（数量标签在图标下方），
## 且不覆盖威胁卡正面；无威胁卡时退回卡片中下方；基尔格蒙用槽位显示 → 图标隐藏。
var _fail := 0
func _check(n: String, ok: bool, d: String) -> void:
	if ok: print("PASS: " + n)
	else: _fail += 1; print("FAIL: " + n + " — " + d)

func _ready() -> void:
	Game.autopilot = true
	Game.pending_setup = {"villain": "vulture", "heroes": ["cap", "ironman"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(4):
		await get_tree().process_frame

	var ok_right := true
	var ok_below := true
	var ok_no_overlap := true
	var detail := ""
	for i in range(Game.LOCATION_COUNT):
		var lv: LocationView = inst._loc_views[i]
		if not lv.crisis_icon.visible:
			ok_right = false
			detail = "loc%d 危机图标不可见" % i
			break
		var tsz: Vector2 = lv.threat.custom_minimum_size
		var right_edge: float = lv.threat.position.x + tsz.x
		var ico: Vector2 = lv.crisis_icon.position
		if ico.x < right_edge - 0.5:
			ok_right = false
			ok_no_overlap = false
			detail = "loc%d 图标 x=%.1f < 威胁卡右缘 %.1f" % [i, ico.x, right_edge]
		if ico.x > right_edge + 16.0:
			ok_right = false
			detail = "loc%d 图标离威胁卡太远 x=%.1f（右缘 %.1f）" % [i, ico.x, right_edge]
		if ico.y < lv.threat.position.y or ico.y > lv.threat.position.y + tsz.y:
			detail = "loc%d 图标 y=%.1f 不在威胁卡纵向范围内（%.1f~%.1f）" % [i, ico.y, lv.threat.position.y, lv.threat.position.y + tsz.y]
		if lv.crisis_label.position.y <= ico.y + 20.0:
			ok_below = false
			detail = "loc%d 数量标签没在图标下方（icon y=%.1f label y=%.1f）" % [i, ico.y, lv.crisis_label.position.y]
	_check("危机图标都在威胁卡右侧", ok_right, detail)
	_check("图标不压在威胁卡上", ok_no_overlap, detail)
	_check("数量标签在图标下方", ok_below, detail)
	_check("数量显示为开局 3 个战利品", inst._loc_views[0].crisis_label.text == "x3",
		inst._loc_views[0].crisis_label.text)

	# 威胁卡被化解/移走 → 危机指示物**位置保持不变**（不再跳回卡片中间）
	var li := 0
	var lv0: LocationView = inst._loc_views[li]
	var pos_before: Vector2 = lv0.crisis_icon.position
	var label_before: Vector2 = lv0.crisis_label.position
	Game.state["locations"][li]["threat"] = null
	lv0.refresh(Game.state)
	for i in range(2):
		await get_tree().process_frame
	_check("威胁卡被清除后图标仍显示", lv0.crisis_icon.visible, "不可见")
	_check("威胁卡被化解后危机图标位置保持不变",
		lv0.crisis_icon.position.is_equal_approx(pos_before) and lv0.crisis_label.position.is_equal_approx(label_before),
		"icon %s -> %s, label %s -> %s" % [str(pos_before), str(lv0.crisis_icon.position), str(label_before), str(lv0.crisis_label.position)])
	_check("威胁卡被化解后仍在原威胁卡右侧（未回到卡片中间）",
		lv0.crisis_icon.position.x > lv0._pos.x + 40.0,
		"icon.x=%.1f pos.x=%.1f" % [lv0.crisis_icon.position.x, lv0._pos.x])

	# 基尔格蒙：危机指示物进槽位显示 → 角落图标隐藏
	Game.pending_setup = {"villain": "kilmonger", "heroes": ["cap", "ironman"], "challenge": "none"}
	inst.queue_free()
	await get_tree().process_frame
	var inst2: Control = (load("res://src/ui/Board.tscn") as PackedScene).instantiate()
	add_child(inst2)
	for i in range(4):
		await get_tree().process_frame
	_check("基尔格蒙：危机进槽位后角落图标隐藏", not inst2._loc_views[0].crisis_icon.visible,
		"仍然可见")

	if _fail == 0:
		print("=== CRISIS ICON UI PASSED ===")
		get_tree().quit(0)
	else:
		print("=== CRISIS ICON UI FAILED (%d) ===" % _fail)
		get_tree().quit(1)
