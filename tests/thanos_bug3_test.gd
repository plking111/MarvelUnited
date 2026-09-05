extends Node
## Bug3: 灭霸阵亡英雄图标显示
var board: Node
var _deal_started := false
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
	print("READY heroes=", Game.state["hero_ids"])
	var bad: Array = []
	# 初始：无阵亡
	board._refresh_eliminated()
	var init_vis: bool = board._eliminated_box.visible
	print("初始 eliminated_box.visible=", init_vis, " children=", board._eliminated_box.get_child_count())
	if init_vis:
		bad.append("初始应不显示阵亡区")
	# 制造 KO：直接把两个英雄标记淘汰
	Game.state["eliminated"] = ["cap", "ironman"]
	Game.state["hero_ids"] = ["widow"]
	board._refresh_eliminated()
	var vis: bool = board._eliminated_box.visible
	var n: int = board._eliminated_box.get_child_count()
	print("KO后 visible=", vis, " icons=", n)
	if not vis:
		bad.append("有阵亡英雄应显示区")
	if n != 2:
		bad.append("应显示2个阵亡英雄图标（实际%d）" % n)
	# 每个图标应是 TextureRect 且带卡背材质
	var first: Node = board._eliminated_box.get_child(0)
	if not (first is TextureRect):
		bad.append("阵亡图标应为TextureRect")
	print("---- RESULT ----")
	if bad.is_empty():
		print("=== BUG3 PASSED ===")
		get_tree().quit(0)
	else:
		print("=== FAILED: ", bad, " ===")
		get_tree().quit(1)
