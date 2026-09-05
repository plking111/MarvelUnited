extends Node
## 验证：灭霸怜悯卡BAM；结算界面居中+图标
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

	# ---- Bug2: 怜悯卡 bam 应为 True ----
	var th: Dictionary = DB.villain("thanos")
	if not th["actions"][10].get("bam", false): bad.append("怜悯卡10应有BAM")
	if not th["actions"][11].get("bam", false): bad.append("怜悯卡11应有BAM")
	# 疯狂泰坦人不应有BAM
	if th["actions"][8].get("bam", false): bad.append("疯狂泰坦人8不应有BAM")
	if th["actions"][9].get("bam", false): bad.append("疯狂泰坦人9不应有BAM")
	print("BAM check: mercy10/11=True, titan8/9=False", " ok=", bad.is_empty())

	# ---- Bug3: 结算界面 ----
	var pop = board._popup
	# 失败：显示反派图标
	pop.show_game_over(false, "测试失败")
	print("fail label=", pop.overlay_label.text, " icon=", pop.overlay_icon.texture.resource_path if pop.overlay_icon.texture else "null")
	if pop.overlay_icon.texture == null: bad.append("失败应显示反派图标")
	var icon_path: String = pop.overlay_icon.texture.resource_path if pop.overlay_icon.texture else ""
	print("fail icon path=", icon_path)
	if not icon_path.contains("thanos/back"): bad.append("失败图标应为灭霸行动牌背(back)")
	# 胜利：显示英雄图标
	var hids: Array = Game.state.get("hero_ids", [])
	pop.show_game_over(true, "测试胜利")
	print("win label=", pop.overlay_label.text, " icon=", pop.overlay_icon.texture.resource_path if pop.overlay_icon.texture else "null")
	if pop.overlay_icon.texture == null: bad.append("胜利应显示英雄图标")
	var wpath: String = pop.overlay_icon.texture.resource_path if pop.overlay_icon.texture else ""
	if not wpath.contains("heroes/"+str(hids[0])): bad.append("胜利图标应为英雄卡背")

	print("---- RESULT ----")
	if bad.is_empty():
		print("=== BUG2+3 PASSED ===")
		get_tree().quit(0)
	else:
		print("=== FAILED: ", bad, " ===")
		get_tree().quit(1)
