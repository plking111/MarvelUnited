extends Node
## 英雄顺位（稳定槽位）验证：
## 初始无选中 → 选择依次填入 P1/P2/P3 → 满员拒绝 →
## 取消某顺位只清空该槽（其他顺位不变）→ 重选英雄填入最低空槽位。

func _ready() -> void:
	var setup: PackedScene = load("res://src/ui/Setup.tscn")
	var inst: Control = setup.instantiate()
	add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	var bad: Array = []

	# 1) 初始无选中，槽位全空
	print("初始槽位=", str(inst._hero_slots))
	if inst._selected_heroes.size() != 0:
		bad.append("初始应无英雄选中")

	# 2) 依次选择：hulk(P1) cap(P2) ironman(P3)
	inst._on_hero_toggle("hulk")
	inst._on_hero_toggle("cap")
	inst._on_hero_toggle("ironman")
	print("选中=", str(inst._selected_heroes), " 槽位=", str(inst._hero_slots))
	if inst._hero_slots != ["hulk", "cap", "ironman"]:
		bad.append("槽位填充错误: %s" % str(inst._hero_slots))
	var l_hulk: Label = inst._hero_buttons["hulk"].get_meta("p_label")
	var l_cap: Label = inst._hero_buttons["cap"].get_meta("p_label")
	var l_iron: Label = inst._hero_buttons["ironman"].get_meta("p_label")
	print("P标签: hulk=%s cap=%s ironman=%s" % [l_hulk.text, l_cap.text, l_iron.text])
	if l_hulk.text != "P1" or l_cap.text != "P2" or l_iron.text != "P3":
		bad.append("P 标签错误")

	# 3) 满员后第 4 个英雄被拒绝
	inst._on_hero_toggle("widow")
	if inst._hero_slots.has("widow") or inst._selected_heroes.size() != 3:
		bad.append("满员后不应再选中")

	# 4) P2(cap) 取消：只清空自己的槽位，P1/P3 顺位不变
	inst._on_hero_toggle("cap")
	print("取消cap后 槽位=", str(inst._hero_slots), " 紧凑=", str(inst._selected_heroes))
	if inst._hero_slots != ["hulk", "", "ironman"]:
		bad.append("取消后槽位应保留空位: %s" % str(inst._hero_slots))
	if inst._hero_buttons["ironman"].get_meta("p_label").text != "P3":
		bad.append("取消后 P3 顺位不应改变")
	if inst._hero_buttons["hulk"].get_meta("p_label").text != "P1":
		bad.append("取消后 P1 顺位不应改变")
	if inst._hero_buttons["cap"].get_meta("p_label").visible:
		bad.append("取消后 cap 的 P 标签应隐藏")

	# 5) 重选英雄 → 填入最低空槽位（P2），P1/P3 不变
	inst._on_hero_toggle("widow")
	print("重选后 槽位=", str(inst._hero_slots), " 紧凑=", str(inst._selected_heroes))
	if inst._hero_slots != ["hulk", "widow", "ironman"]:
		bad.append("重选应填入最低空槽: %s" % str(inst._hero_slots))
	if inst._hero_buttons["widow"].get_meta("p_label").text != "P2":
		bad.append("重选英雄应为 P2")

	# 6) 顺位框颜色 = 彩虹色且互不相同
	var c_hulk: Color = inst._hero_buttons["hulk"].get_meta("sel_frames")[0].color
	var c_widow: Color = inst._hero_buttons["widow"].get_meta("sel_frames")[0].color
	var c_iron: Color = inst._hero_buttons["ironman"].get_meta("sel_frames")[0].color
	var exp: Array = [inst.HERO_SLOT_COLORS[0], inst.HERO_SLOT_COLORS[1], inst.HERO_SLOT_COLORS[2]]
	var got_colors: Array = [c_hulk, c_widow, c_iron]
	var rainbow_ok := true
	for i in range(3):
		var g: Color = got_colors[i]
		var w: Color = exp[i]
		if absf(g.r - w.r) > 0.02 or absf(g.g - w.g) > 0.02 or absf(g.b - w.b) > 0.02:
			rainbow_ok = false
	print("彩虹色匹配=", rainbow_ok)
	if not rainbow_ok:
		bad.append("顺位框颜色未按彩虹色排列")

	if bad.is_empty():
		print("=== HERO SEQ TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== HERO SEQ TEST FAILED: ", bad, " ===")
		get_tree().quit(1)
