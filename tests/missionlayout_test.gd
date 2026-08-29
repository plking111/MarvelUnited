extends Node
## 任务卡布局验证：3 张任务卡在任务区横向排开，不得重叠（回归：MissionView 最小尺寸缺失）。

func _ready() -> void:
	Game.pending_setup = {"villain": "ultron", "heroes": ["cap"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(12):
		await get_tree().process_frame
	var children: Array = inst._mission_box.get_children()
	print("任务卡数量=", children.size())
	var bad: Array = []
	if children.size() != 3:
		bad.append("任务卡数量应为3: %d" % children.size())
	var prev_end := -1e9
	for c in children:
		var r := Rect2(c.position, c.size)
		print("任务卡 rect=pos(%d,%d) size(%d,%d)" % [int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)])
		if r.size.x < 90.0:
			bad.append("任务卡宽度过小: %.0f" % r.size.x)
		if r.position.x < prev_end - 0.5:
			bad.append("任务卡重叠")
		prev_end = r.position.x + r.size.x
	if bad.is_empty():
		print("=== MISSION LAYOUT TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== MISSION LAYOUT TEST FAILED: ", bad, " ===")
		get_tree().quit(1)
