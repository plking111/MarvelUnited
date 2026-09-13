extends Node
## 视觉取证：秃鹫开局地图（危机指示物应显示在威胁卡右侧）
func _ready() -> void:
	Game.autopilot = true
	Game.pending_setup = {"villain": "vulture", "heroes": ["cap", "ironman"], "challenge": "none"}
	var inst: Control = (load("res://src/ui/Board.tscn") as PackedScene).instantiate()
	add_child(inst)
	for i in range(8):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		var img: Image = get_viewport().get_texture().get_image()
		if img != null:
			img.save_png("F:/桌游相关/漫威联合/电子游戏/devtools/shot_vulture_board.png")
			print("已保存 devtools/shot_vulture_board.png")
	get_tree().quit(0)
