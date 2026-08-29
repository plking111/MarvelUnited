extends Node
## 弹窗层级回归测试：验证弹窗位于独立 CanvasLayer(100) 中，
## 主界面（含动态重建的角色图标/卡片）永远不可能遮挡弹窗。
## 复现场景：显示弹窗 → 重建角色图标 → 弹窗仍在其层且可见。

var _confirm_flag := false

func _ready() -> void:
	Game.pending_setup = {"villain": "ultron", "heroes": ["cap", "ironman", "hulk"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(12):
		await get_tree().process_frame
	var bad: Array = []
	# 1) 弹窗必须是 CanvasLayer 且层号 >= 100（主界面为 0）
	if not (inst._popup is CanvasLayer):
		bad.append("弹窗层不是 CanvasLayer")
	if inst._popup.layer < 100:
		bad.append("弹窗层号 < 100: %d" % inst._popup.layer)
	# 2) 显示一个选择弹窗（通过 Events 信号，与真实游戏路径一致）
	var got: Array = []
	var cb := func(idx: int) -> void: got.append(idx)
	Events.prompt_choice.emit(["选项A", "选项B"], "测试弹窗", cb)
	print("弹窗可见=", inst._popup.prompt_panel.visible)
	if not inst._popup.prompt_panel.visible:
		bad.append("选择弹窗未显示")
	# 3) 重建角色图标（此前会导致图标盖住弹窗的元凶）
	inst._refresh_hero_badges()
	for i in range(6):
		await get_tree().process_frame
	print("重建图标后 弹窗可见=", inst._popup.prompt_panel.visible,
		" 父节点=", inst._popup.prompt_panel.get_parent().name)
	if not inst._popup.prompt_panel.visible:
		bad.append("重建图标后弹窗被隐藏")
	# 4) 其他弹窗组件也都在弹窗层
	var all_in_layer := true
	for p in [inst._popup.confirm_panel, inst._popup.hand_pick_panel,
			inst._popup.story_pick_panel, inst._popup.info_panel, inst._popup.overlay]:
		if p.get_parent() != inst._popup:
			all_in_layer = false
	if not all_in_layer:
		bad.append("部分弹窗不在弹窗层内")
	# 5) 放大预览应在独立 CanvasLayer（50）中，且低于弹窗层
	var zl: CanvasLayer = inst._zoom_panel.get_parent()
	if not (zl is CanvasLayer) or zl.layer != 50:
		bad.append("放大层配置错误: layer=%d" % (zl.layer if zl is CanvasLayer else -1))
	# 6) 弹窗按钮点击回调正常（确认框：面板→VBox(标签+按钮行)→确认按钮）
	var cb2 := func(ok: bool) -> void: _confirm_flag = ok
	Events.prompt_confirm.emit("确定？", cb2)
	inst._popup.confirm_panel.get_child(0).get_child(1).get_child(0).pressed.emit()
	print("确认回调=", _confirm_flag)
	if not _confirm_flag:
		bad.append("确认框回调未触发")
	# 7) 结算层「返回主菜单」按钮应水平居中（修复偏左）
	inst._popup.show_game_over(true, "测试")
	for i in range(3):
		await get_tree().process_frame
	var ob_rect: Rect2 = inst._popup.overlay_button.get_global_rect()
	var ob_center: float = ob_rect.position.x + ob_rect.size.x / 2.0
	print("结算按钮中心x=", ob_center)
	if absf(ob_center - 960.0) > 3.0:
		bad.append("结算按钮未水平居中: 中心x=%.0f" % ob_center)
	inst._popup.overlay.visible = false
	# 8) 反派牌堆数量显示（与英雄牌库一致）
	print("反派牌堆显示=", inst._villain_deck_num.text, " 实际=", Game.state["master_deck"].size())
	if inst._villain_deck_num.text != str(Game.state["master_deck"].size()):
		bad.append("反派牌堆数量显示错误")
	if bad.is_empty():
		print("=== POPUP LAYER TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== POPUP LAYER TEST FAILED: ", bad, " ===")
		get_tree().quit(1)
