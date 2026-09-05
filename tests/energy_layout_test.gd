extends Node
## 能量卡分列布局验证：<=4 单列居中；>4 两列各半、整体居中于任务牌中心
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
	var onscreen_x := 1340.0  # 任务牌中心
	var bad: Array = []

	# 用 4 张测单列
	_do_case([0, 1, 2, 3], "≤4单列", onscreen_x, bad)
	# 用 7 张测两列
	_do_case([0, 1, 2, 3, 4, 5, 6], ">4两列", onscreen_x, bad)

	print("---- RESULT ----")
	if bad.is_empty():
		print("=== ENERGY COLUMN LAYOUT PASSED ===")
		get_tree().quit(0)
	else:
		print("=== FAILED: ", bad, " ===")
		get_tree().quit(1)

func _do_case(unlocked: Array, name: String, cx: float, bad: Array) -> void:
	# 直接注入 campaign.energy_unlocked，然后刷新
	var camp: Dictionary = Game.state.get("campaign", {})
	camp["energy_unlocked"] = unlocked.duplicate()
	Game.state["campaign"] = camp
	board._refresh_energy_stack(Game.state)
	var xs: Array = []
	var ys: Array = []
	for ch in board._energy_stack_box.get_children():
		xs.append(ch.position.x)
		ys.append(ch.position.y)
	# 屏幕x = 1340(容器原点) + 卡x
	var screen_xs: Array = xs.map(func(v): return 1340.0 + v)
	print(name, " n=", unlocked.size(), " xs=", screen_xs, " ys=", ys)
	if unlocked.size() <= 4:
		# 单列：卡中心(屏幕x+卡宽一半)应=任务牌中心1340
		var center: float = screen_xs[0] + 59.0
		if abs(center - 1340.0) > 2.0:
			bad.append(name + " 单列未居中于1340（中心%f）" % center)
	else:
		# 两列：左列中心与右列中心对称于1340
		var uniq_x: Array = []
		for v in screen_xs:
			if not uniq_x.has(v):
				uniq_x.append(v)
		uniq_x.sort()
		if uniq_x.size() != 2:
			bad.append(name + " 应有两列（实际x值%d种）" % uniq_x.size())
		else:
			var c0: float = uniq_x[0] + 59.0
			var c1: float = uniq_x[1] + 59.0
			var mid: float = (c0 + c1) / 2.0
			if abs(mid - 1340.0) > 2.0:
				bad.append(name + " 两列中心未对齐1340（中点%f）" % mid)
