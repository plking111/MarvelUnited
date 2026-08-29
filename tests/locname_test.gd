extends Node
## 验证：地点名称显示在卡片上边缘外侧（不压在卡面内部），且在屏幕内。

func _ready() -> void:
	Game.pending_setup = {"villain": "ultron", "heroes": ["cap", "ironman", "hulk"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(12):
		await get_tree().process_frame
	var bad: Array = []
	for data in inst._loc_views:
		var nl: Label = data.name_label
		var card: TextureRect = data.card
		var nb: float = nl.position.y + nl.size.y  # 名称底边
		var ct: float = card.position.y            # 卡片顶边
		print("地点%d: 名称y=%.0f..%.0f 卡顶=%.0f" % [data.i, nl.position.y, nb, ct])
		if nb > ct + 0.5:
			bad.append("地点%d 名称压进卡面内部 (底边%.0f>卡顶%.0f)" % [data.i, nb, ct])
		if nl.position.y < 0.0:
			bad.append("地点%d 名称超出屏幕顶部" % data.i)
	if bad.is_empty():
		print("=== LOC NAME ABOVE CARD TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== LOC NAME TEST FAILED: ", bad, " ===")
		get_tree().quit(1)
