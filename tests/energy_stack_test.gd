extends Node
## 灭霸(非IW) 激活能量卡 背面叠加：每张用对应背面（不同 cost->gain），上下叠加露底部
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
	var bad: Array = []
	var c: Variant = Game.state.get("campaign", {})
	var unlocked: Array = c.get("energy_unlocked", []) if c is Dictionary else []
	print("unlocked=", unlocked)
	board._refresh_energy_stack(Game.state)
	print("stack visible=", board._energy_stack_box.visible, " children=", board._energy_stack_box.get_child_count())
	# 每张卡背面应对应 eidx+1
	var tex_paths: Array = []
	for ch in board._energy_stack_box.get_children():
		if not (ch is TextureRect):
			bad.append("应为TextureRect")
			continue
		var tex: Texture2D = ch.texture
		var path: String = tex.resource_path
		tex_paths.append(path)
		print("tex=", path)
	if tex_paths.size() != unlocked.size():
		bad.append("卡片数应=%d" % unlocked.size())
	# 因为 2 张能量卡 eidx 不同 → 背面应不同
	if unlocked.size() >= 2 and tex_paths.size() >= 2 and tex_paths[0] == tex_paths[1]:
		bad.append("两张能量卡背面应不同（对应各自效果）")
	# 校验纵向错开
	var ys: Array = []
	for ch in board._energy_stack_box.get_children():
		ys.append(ch.position.y)
	var stagger_ok := true
	for i in range(1, ys.size()):
		if abs(ys[i] - ys[i-1]) != 34.0:
			stagger_ok = false
	if not stagger_ok:
		bad.append("应上下错开34px")
	# 卡片尺寸收缩校验
	var child: Node = board._energy_stack_box.get_child(0)
	var sz: Vector2 = child.custom_minimum_size
	print("card size=", sz)
	if sz.x != 118.0 or abs(sz.y - 118.0*960.0/1348.0) > 0.5:
		bad.append("卡片尺寸应为118宽")
	print("---- RESULT ----")
	if bad.is_empty():
		print("=== ENERGY STACK (per-card back) PASSED ===")
		get_tree().quit(0)
	else:
		print("=== FAILED: ", bad, " ===")
		get_tree().quit(1)
