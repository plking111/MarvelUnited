extends Node
## 视觉取证：阿戈摩托之球 → 反派牌堆右侧贴"牌堆顶那张行动牌"的卡图（含悬停放大）。
## 只在有显示服务器时截图（headless 跑只会打印一条提示）。
func _ready() -> void:
	Game.autopilot = true
	Game.pending_setup = {"villain": "redskull", "heroes": ["drstrange", "cap"], "challenge": "none", "mode": "base"}
	var inst: Control = (load("res://src/ui/Board.tscn") as PackedScene).instantiate()
	add_child(inst)
	for i in range(8):
		await get_tree().process_frame
	# 让"阿戈摩托之球"落在故事情节可见区里，并把牌堆顶设成行动卡 3（action_04.png）
	var orb_idx := -1
	for i in range(DB.hero_cards("drstrange").size()):
		if String(DB.hero_cards("drstrange")[i].get("effect", {}).get("type", "")) == "drstrange_orb_of_agamotto":
			orb_idx = i
	if orb_idx < 0:
		orb_idx = 6
	Game.state["story"].append({"type": "hero", "hero": "drstrange", "idx": orb_idx})
	Game.state["master_deck"] = [3, 5, 7]
	Events.state_changed.emit()
	for i in range(6):
		await get_tree().process_frame
	print("顶牌卡图可见=%s 位置=%s 贴图=%s" % [str(inst._villain_top_card.visible), str(inst._villain_top_card.position), str(inst._villain_top_card.texture)])
	if DisplayServer.get_name() != "headless":
		var img: Image = get_viewport().get_texture().get_image()
		if img != null:
			img.save_png("F:/桌游相关/漫威联合/电子游戏/devtools/shot_orb_top_card.png")
			print("已保存 devtools/shot_orb_top_card.png")
		# 再截一张"悬停放大"的
		inst._villain_top_card.mouse_entered.emit()
		for i in range(4):
			await get_tree().process_frame
		var img2: Image = get_viewport().get_texture().get_image()
		if img2 != null:
			img2.save_png("F:/桌游相关/漫威联合/电子游戏/devtools/shot_orb_top_card_zoom.png")
			print("已保存 devtools/shot_orb_top_card_zoom.png")
	get_tree().quit(0)
