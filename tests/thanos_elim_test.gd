extends Node
## Bug1: 阵亡计数(x/y)在生命值右侧，图标下方缩小，面板恢复原大小272
var board: Node
func _ready() -> void:
	Game.pending_setup = {
		"villain": "thanos", "heroes": ["cap", "ironman", "widow"], "challenge": "none",
		"mode": "base", "expansions": [], "debug_full_slots": false, "peek_hands": false,
	}
	var scene = load("res://src/ui/Board.tscn")
	board = scene.instantiate()
	add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame
	var bad: Array = []
	Game.state["eliminated"] = ["cap"]
	board._refresh_eliminated()
	print("label=", board._eliminated_label.text, " visible=", board._eliminated_label.visible)
	print("label_pos=", board._eliminated_label.position, " box_pos=", board._eliminated_box.position)
	if not board._eliminated_label.text.contains("1/3"): bad.append("计数应为1/3(玩家数3)")
	var lp: Vector2 = board._eliminated_label.position
	if lp.y < 175 or lp.x < 200: bad.append("计数应在生命值(y180)右侧")
	if board._eliminated_box.get_child_count() != 1: bad.append("应有1个图标")
	print("icon count=", board._eliminated_box.get_child_count())
	print("---- RESULT ----")
	if bad.is_empty():
		print("=== BUG1 PASSED ===")
		get_tree().quit(0)
	else:
		print("=== FAILED: ", bad, " ===")
		get_tree().quit(1)
