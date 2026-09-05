extends Node
## 英雄选择面板冒烟：搜索/排序/渲染
var board: Node
func _ready() -> void:
	Game.pending_setup = {
		"villain": "thanos", "heroes": ["cap", "ironman"], "challenge": "none",
		"mode": "base", "expansions": [], "debug_full_slots": false, "peek_hands": false,
	}
	var scene = load("res://src/ui/Board.tscn")
	board = scene.instantiate()
	add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame
	var pop = board._popup
	# 打开面板，给 6 个未用英雄
	var options: Array = ["cmarvel", "hulk", "widow", "winter", "shuri", "blackpanther"]
	pop.show_hero_pick(func(h): print("picked=", h), "测试选择", options)
	await get_tree().process_frame
	var n0: int = pop.hero_pick_box.get_child_count()
	print("alpha 数量=", n0, " (期望 6)")
	# 搜索过滤
	pop.hero_pick_search.text = "黑"
	pop._on_hero_search_changed("")
	await get_tree().process_frame
	var nsearch: int = pop.hero_pick_box.get_child_count()
	print("搜索'黑'数量=", nsearch)
	pop.hero_pick_search.text = ""
	pop._on_hero_search_changed("")
	# 排序切换
	pop._on_hero_sort("expansion")
	await get_tree().process_frame
	var nexp: int = pop.hero_pick_box.get_child_count()
	print("按扩展数量=", nexp, " (期望 6)")
	var bad: Array = []
	if n0 != 6: bad.append("alpha 应显示 6 个")
	if nsearch < 1: bad.append("搜索应有结果")
	if nexp != 6: bad.append("按扩展应显示 6 个")
	print("---- RESULT ----")
	if bad.is_empty():
		print("=== HERO PICK UI SMOKE PASSED ===")
		get_tree().quit(0)
	else:
		print("=== FAILED: ", bad, " ===")
		get_tree().quit(1)
