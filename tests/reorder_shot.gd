extends Node
## 视觉取证：术士亚当·量子魔法 → "用鼠标拖动反派牌堆顶 3 张调整顺序"的弹窗（裁定2 要求真拖拽）。
##
## 三层证据一次拿全：
##   ① 通过**真实效果路径**弹出（Game.trigger_effect → Events.prompt_reorder → Board/PopupLayer）；
##   ② 用**合成的真鼠标事件**（viewport.push_input：按下→移动→松开）拖第 1 张到第 3 张；
##   ③ 截图存档（拖之前 / 正在拖 / 拖完）并打印顺序与"确认后写回牌堆"的结果。
## 只在有显示服务器时截图（headless 跑只会打印文字结论）。

const OUT_DIR := "F:/桌游相关/漫威联合/电子游戏/devtools/"

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _save(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(OUT_DIR + name)
		print("已保存 devtools/" + name)

func _press(pos: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = pos
	e.global_position = pos
	get_viewport().push_input(e)

func _motion(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	get_viewport().push_input(e)

## 深度优先找按钮（按文字）
func _find_button(n: Node, text: String) -> Button:
	if n is Button and String((n as Button).text).contains(text):
		return n as Button
	for c in n.get_children():
		var r: Button = _find_button(c, text)
		if r != null:
			return r
	return null

func _ready() -> void:
	Game.autopilot = false
	Game.pending_setup = {"villain": "redskull", "heroes": ["adamwarlock", "cap"], "challenge": "none", "mode": "base"}
	var inst: Control = (load("res://src/ui/Board.tscn") as PackedScene).instantiate()
	add_child(inst)
	await _frames(8)

	# ---- 用真实效果路径触发量子魔法（打出术士亚当第 8 张卡 = 量子魔法）----
	var ci := 7
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	Game.state["heroes"]["adamwarlock"]["hand"] = [ci]
	Game.state["story"].append({"type": "hero", "hero": "adamwarlock", "idx": ci})
	Game.state["action_symbols"] = ["attack", "move"]
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	Game.state["played_effect"] = DB.hero_cards("adamwarlock")[ci]["effect"]
	Game.state["master_deck"] = [1, 4, 7, 2, 5]
	Game.trigger_effect()      # 故意不 await：它要等玩家拖完点确认
	await _frames(8)

	var pop: Node = inst._popup
	var slots: Array = pop._reorder_slots
	print("弹窗槽位数=%d 初始顺序=%s" % [slots.size(), str(pop._reorder_cards)])
	_save("shot_reorder_cards.png")

	if slots.size() < 3:
		print("❌ 没有弹出 3 张可拖的牌，拿不到拖拽证据")
		get_tree().quit(1)
		return

	# ---- 合成真鼠标：按住第 1 张 → 拖到第 3 张上 → 松开（应当互换）----
	var p0: Vector2 = (slots[0] as Control).get_global_rect().get_center()
	var p2: Vector2 = (slots[2] as Control).get_global_rect().get_center()
	print("槽位中心：第1张=%s 第3张=%s" % [str(p0), str(p2)])
	_press(p0, true)
	await _frames(2)
	_motion(Vector2((p0.x + p2.x) * 0.5, p0.y))
	await _frames(2)
	_motion(p2)
	await _frames(3)
	print("拖拽中：drag=%d hover=%d 残影可见=%s" % [
		int(pop._reorder_drag), int(pop._reorder_hover), str((pop._reorder_ghost as TextureRect).visible)])
	_save("shot_reorder_dragging.png")
	_press(p2, false)
	await _frames(3)
	print("松手后顺序=%s（期望 [7,4,1,2,5] 里的前三张互换 → 第1张与第3张对调）" % str(pop._reorder_cards))
	_save("shot_reorder_after_drag.png")

	# ---- 点"确认顺序" → 新顺序应当写回反派牌堆顶 ----
	var deck_before: Array = (Game.state["master_deck"] as Array).duplicate()
	var ok_btn: Button = _find_button(pop, "确认顺序")
	if ok_btn == null:
		print("❌ 找不到「确认顺序」按钮")
		get_tree().quit(1)
		return
	ok_btn.pressed.emit()
	await _frames(4)
	print("牌堆变化：%s → %s" % [str(deck_before), str(Game.state["master_deck"])])
	print("日志：%s" % str((Game.state.get("log", []) as Array).slice(-2)))
	await _frames(4)
	_save("shot_reorder_confirmed.png")
	get_tree().quit(0)
