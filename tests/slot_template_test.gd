extends Node
## 回归：locations.json 中每个地点的 slots 值，LocationView.SLOT_TEMPLATES 必须有对应模板，
## 否则渲染该地点时 SLOT_TEMPLATES[slots] 为 null -> 读取 tpl["x"] 崩溃。
var _bad: Array = []

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("OK: " + msg)
	else:
		_bad.append(msg)
		print("FAIL: " + msg)

func _ready() -> void:
	# 收集所有出现过的 slots 值
	var slots_set := {}
	for id in DB.locations.keys():
		var slots: int = int(DB.location(id).get("slots", -1))
		slots_set[slots] = true
	print("locations.json 中的 slots 取值: ", slots_set.keys())
	# 遍历每个地点，断言 SLOT_TEMPLATES 有对应键
	var lt: Dictionary = LocationView.SLOT_TEMPLATES
	for id in DB.locations.keys():
		var slots: int = int(DB.location(id).get("slots", -1))
		_check(lt.has(slots), "%s slots=%d 在 SLOT_TEMPLATES 中有模板" % [id, slots])
		if lt.has(slots):
			# 模板 x 数组长度应等于 slots
			var xarr: Array = lt[slots]["x"]
			_check(xarr.size() == slots, "%s 模板 x 长度 %d == slots %d" % [id, xarr.size(), slots])

	print("---- RESULT ----")
	if _bad.is_empty():
		print("=== SLOT TEMPLATE COVERAGE PASSED ===")
		get_tree().quit(0)
	else:
		print("=== FAILED: ", _bad, " ===")
		get_tree().quit(1)
