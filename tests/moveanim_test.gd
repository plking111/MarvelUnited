extends Node
## 角色移动动画验证：
## 场景1：英雄移动 1 步 → 进入动画，动画结束后图标重建到新地点
## 场景2：反派多步移动 → 沿环逐点动画（路径 ≥ 2 段），结束后落到目标地点

func _ready() -> void:
	Game.pending_setup = {"villain": "ultron", "heroes": ["cap", "ironman"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(12):
		await get_tree().process_frame
	var bad: Array = []

	# ---- 场景1：英雄移动 1 步 ----
	var hid := "cap"
	var from: int = Game.state["heroes"][hid]["location"]
	var to: int = (from + 1) % Game.LOCATION_COUNT
	Game.state["heroes"][hid]["location"] = to
	inst._refresh_hero_badges()
	var anim_started: bool = inst._animating_icons
	print("英雄移动 from=", from, " to=", to, " 进入动画=", anim_started)
	if not anim_started:
		bad.append("英雄移动未进入动画")
	var box_during: Control = inst._find_icon_box(hid)
	if box_during == null:
		bad.append("动画期间英雄图标缺失")
	# 等动画结束（按真实时间等待，不受无头帧率影响）
	var t0 := Time.get_ticks_msec()
	while inst._animating_icons and Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
	var box: Control = inst._find_icon_box(hid)
	var anchor: Vector2 = inst._icon_anchor_pos(to)
	var ok1: bool = not inst._animating_icons and box != null \
		and absf(box.position.y - anchor.y) < 5.0 \
		and absf(box.position.x - anchor.x) < 160.0
	print("英雄动画结束=", not inst._animating_icons, " 终点误差ok=", ok1,
		" box=", (box.position if box != null else Vector2.ZERO), " 锚点=", anchor)
	if not ok1:
		bad.append("英雄动画未完成或落点错误")

	# ---- 场景2：反派多步移动 ----
	var vfrom: int = Game.state["villain_pos"]
	var vto: int = (vfrom + 3) % Game.LOCATION_COUNT
	var path: Array = inst._ring_path(vfrom, vto)
	Game.state["villain_pos"] = vto
	inst._refresh_hero_badges()
	var v_anim: bool = inst._animating_icons
	print("反派移动 from=", vfrom, " to=", vto, " 路径=", str(path), " 步数=", path.size(), " 进入动画=", v_anim)
	if not v_anim or path.size() < 2:
		bad.append("反派多步未进入动画或路径不足2段")
	var t1 := Time.get_ticks_msec()
	while inst._animating_icons and Time.get_ticks_msec() - t1 < 8000:
		await get_tree().process_frame
	var vbox: Control = inst._find_icon_box("villain")
	var vanchor: Vector2 = inst._icon_anchor_pos(vto)
	var ok2: bool = not inst._animating_icons and vbox != null \
		and absf(vbox.position.y - vanchor.y) < 5.0 \
		and absf(vbox.position.x - vanchor.x) < 160.0
	print("反派动画结束=", not inst._animating_icons, " 终点误差ok=", ok2,
		" box=", (vbox.position if vbox != null else Vector2.ZERO), " 锚点=", vanchor)
	if not ok2:
		bad.append("反派动画未完成或落点错误")

	# ---- 场景3：路径方向（bug2）----
	# 反派 move 5 步：必须顺时针走 5 段 [1,2,3,4,5]，不能走反向 1 步近路
	var p_cw: Array = inst._ring_path(0, 5, true)
	var p_short: Array = inst._ring_path(0, 5)
	print("反派顺时针路径=", str(p_cw), " 最短路径=", str(p_short))
	if p_cw != [1, 2, 3, 4, 5]:
		bad.append("反派移动应严格顺时针 5 段: %s" % str(p_cw))
	if p_short != [5]:
		bad.append("普通角色仍应走最短路径: %s" % str(p_short))

	if bad.is_empty():
		print("=== MOVE ANIM TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== MOVE ANIM TEST FAILED: ", bad, " ===")
		get_tree().quit(1)
