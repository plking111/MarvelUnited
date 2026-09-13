extends Node
## 视觉取证：邪恶六人组模式开局（中央六边形弱点卡 + 左侧仪表板 + 地点上的 6 个反派）
func _ready() -> void:
	Game.autopilot = true
	Game.pending_setup = {"villain": "vulture", "heroes": ["cap", "ironman"], "challenge": "none", "mode": "s6"}
	var inst: Control = (load("res://src/ui/Board.tscn") as PackedScene).instantiate()
	add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	print("s6 panel nodes=", inst._s6_nodes.size(), " center=", inst._s6_center_root != null)
	print("locations with villain icons:")
	for i in range(Game.LOCATION_COUNT):
		var vs: Array = Game._s6_at(i)
		if vs.size() > 0:
			print("  loc", i, " -> ", vs)
	if DisplayServer.get_name() != "headless":
		var img: Image = get_viewport().get_texture().get_image()
		if img != null:
			img.save_png("F:/桌游相关/漫威联合/电子游戏/devtools/shot_s6_board.png")
			print("已保存 devtools/shot_s6_board.png")
	get_tree().quit(0)
