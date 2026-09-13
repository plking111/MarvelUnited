extends Node
## 视觉取证：泽莫男爵「危机指示物盖住行动符号」——把故事区里被盖住的符号拍下来，
## 并裁出那一张卡放大 8 倍（最近邻），用来人眼判断 8px 小图标在 46×64 的卡上是否看得清。
## 只在有显示服务器时截图（headless 跑只打印一条提示）。
func _ready() -> void:
	Game.autopilot = true
	Game.pending_setup = {"villain": "zemo", "heroes": ["ironman", "cap"], "challenge": "none", "mode": "base"}
	var inst: Control = (load("res://src/ui/Board.tscn") as PackedScene).instantiate()
	add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	# 挑一张符号数 >= 2 的钢铁侠行动卡，让其中 1 个符号被危机指示物盖住
	var idx := -1
	for i in range(DB.hero_cards("ironman").size()):
		var syms: Array = DB.hero_cards("ironman")[i]["symbols"]
		if syms.size() >= 2:
			idx = i
			break
	if idx < 0:
		idx = 0
	Game.state["story"].append({"type": "hero", "hero": "ironman", "idx": idx, "covered": [0]})
	Events.state_changed.emit()
	for i in range(10):
		await get_tree().process_frame
	var last: Dictionary = Game.state["story"][Game.state["story"].size() - 1]
	print("故事区最后一条 = %s" % str(last))
	print("该卡符号 = %s" % str(DB.hero_cards("ironman")[int(last["idx"])]["symbols"]))
	if DisplayServer.get_name() != "headless":
		var img: Image = get_viewport().get_texture().get_image()
		if img != null:
			img.save_png("F:/桌游相关/漫威联合/电子游戏/devtools/shot_zemo_crisis_board.png")
			print("已保存 devtools/shot_zemo_crisis_board.png")
		# 裁出故事区第一张卡并放大 8 倍（最近邻），看清 8px 图标
		var box: Control = inst._story_box
		var card: Control = null
		for c in box.get_children():
			if c is Control:
				card = c
				break
		if card != null:
			var gp: Vector2 = card.global_position
			var sz: Vector2 = card.size
			print("卡框 global_position=%s size=%s" % [str(gp), str(sz)])
			var x: int = clampi(int(gp.x), 0, img.get_width() - 1)
			var y: int = clampi(int(gp.y), 0, img.get_height() - 1)
			var w: int = clampi(int(sz.x), 1, img.get_width() - x)
			var h: int = clampi(int(sz.y), 1, img.get_height() - y)
			var crop: Image = img.get_region(Rect2i(x, y, w, h))
			if crop != null:
				crop.resize(w * 8, h * 8, Image.INTERPOLATE_NEAREST)
				crop.save_png("F:/桌游相关/漫威联合/电子游戏/devtools/shot_zemo_crisis_zoom.png")
				print("已保存 devtools/shot_zemo_crisis_zoom.png（裁剪 %dx%d 放大 8 倍）" % [w, h])
	get_tree().quit(0)
