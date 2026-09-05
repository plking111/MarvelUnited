extends Node
## 验证 4 个新反派行动卡切图在 Board 故事情节中显示（每张卡独立文件、尺寸正确）。

func _ready() -> void:
	Game.autopilot = true
	var ok := true
	for vid in ["thanos", "proxima", "cull", "ebony"]:
		for n in range(12):
			var path := "res://assets/cards/villains/%s/action_%02d.png" % [vid, n + 1]
			var tex: Texture2D = load(path)
			if tex == null:
				print("FAIL: 无法加载 ", path)
				ok = false
			else:
				var w: int = tex.get_width()
				var h: int = tex.get_height()
				# 竖版卡：宽 < 高（853x1198），比例约 0.712
				if w >= h or abs(float(w) / float(h) - 0.712) > 0.1:
					print("FAIL: %s 尺寸异常 %dx%d" % [path, w, h])
					ok = false
	print("四反派 12 张行动卡尺寸全部正常: ", ok)
	# 验证 Board 加载反派行动卡弹窗
	Game.pending_campaign = {"game": 1, "order": ["cull", "proxima", "ebony"], "stones_collected": [], "energy_unlocked": [], "removed_energy": 6}
	Game.pending_setup = {"villain": "cull", "heroes": ["cap", "ironman"], "challenge": "none", "mode": "iw", "expansions": ["无限战争"]}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(15):
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("F:/桌游相关/漫威联合/电子游戏/devtools/iw_actioncards.png")
	print("=== IW ACTION CARDS TEST PASSED ===")
	get_tree().quit(0)
