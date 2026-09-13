extends Node
## 视觉取证：三个新反派的面板轨道 + 地点/威胁卡是否正常加载
## 依次截图 kraven / sandman / electro 的开局地图
var _ids := ["kraven", "sandman", "electro"]

func _ready() -> void:
	Game.autopilot = true
	for vid in _ids:
		Game.pending_setup = {"villain": vid, "heroes": ["cap", "ironman"], "challenge": "none"}
		var inst: Control = (load("res://src/ui/Board.tscn") as PackedScene).instantiate()
		add_child(inst)
		for i in range(8):
			await get_tree().process_frame
		var missing := 0
		for i in range(Game.LOCATION_COUNT):
			var lv: LocationView = inst._loc_views[i]
			if lv.threat.visible and lv.threat.texture == null:
				missing += 1
		print("%s：威胁卡缺图=%d，面板轨道文本=%s" % [vid, missing, inst._fear_label.text if inst._fear_label.visible else "(未显示)"])
		if DisplayServer.get_name() != "headless":
			var img: Image = get_viewport().get_texture().get_image()
			if img != null:
				img.save_png("F:/桌游相关/漫威联合/电子游戏/devtools/shot_%s_board.png" % vid)
				print("已保存 devtools/shot_%s_board.png" % vid)
		inst.queue_free()
		await get_tree().process_frame
	get_tree().quit(0)
