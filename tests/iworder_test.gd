extends Node
## 验证：bug1 iw反派页三手下置前+剩余拼音排序；bug2 返回/换模式重置无残留。

var _fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("OK: " + msg)
	else:
		_fails.append(msg)
		print("FAIL: " + msg)

func _ready() -> void:
	var setup_scene: PackedScene = load("res://src/ui/Setup.tscn")
	var inst := setup_scene.instantiate()
	add_child(inst)
	for i in range(30):
		await get_tree().process_frame

	# ===== bug1：iw 反派页排序 =====
	inst._on_mode_selected(7)  # iw
	await get_tree().process_frame
	inst._show_step(3)
	await get_tree().process_frame
	inst._render_villains()
	await get_tree().process_frame
	var order: Array = []
	for vid in ["proxima", "cull", "ebony", "ultron", "redskull", "taskmaster", "thanos"]:
		if inst._villain_buttons.has(vid):
			order.append({"vid": vid, "pos": inst._villain_buttons[vid].position})
	order.sort_custom(func(a, b): return a["pos"].y < b["pos"].y or (a["pos"].y == b["pos"].y and a["pos"].x < b["pos"].x))
	var seq: Array = []
	for o in order:
		seq.append(o["vid"])
	print("iw反派顺序:", str(seq))
	# 三手下在前
	_check(seq.find("proxima") < seq.find("redskull") and seq.find("cull") < seq.find("redskull") and seq.find("ebony") < seq.find("redskull"),
		"三手下置前")
	# 剩余按拼音：ultron(奥/A) redskull(红/H) taskmaster(模/M) thanos(灭/M)
	var rest: Array = ["ultron", "redskull", "taskmaster", "thanos"]
	var rest_idx: Array = []
	for v in rest:
		rest_idx.append(seq.find(v))
	_check(rest_idx[0] < rest_idx[1] and rest_idx[1] < rest_idx[2] and rest_idx[2] < rest_idx[3],
		"剩余按拼音排序（奥→红→模→灭）idx=%s" % str(rest_idx))

	# ===== bug2：返回 step1 换基础模式，iw 残留清空 =====
	inst._show_step(2)
	await get_tree().process_frame
	inst._on_back()  # 返回 step1
	await get_tree().process_frame
	inst._on_mode_selected(1)  # 基础模式
	await get_tree().process_frame
	inst._show_step(3)
	await get_tree().process_frame
	_check(inst._campaign_slots == ["", "", ""], "换基础模式后战役槽位清空（%s）" % str(inst._campaign_slots))
	_check(inst._campaign_label.text == "", "基础模式战役提示清空（'%s'）" % inst._campaign_label.text)

	# ===== bug2：从反派页返回 step2，反派选择清空 =====
	inst._on_mode_selected(1)
	await get_tree().process_frame
	inst._show_step(3)
	await get_tree().process_frame
	inst._on_villain_selected("redskull")
	_check(inst._selected_villain == "redskull", "选中红骷髅")
	inst._on_back()  # 返回 step2
	await get_tree().process_frame
	_check(inst._selected_villain == "", "返回后反派选择清空")

	if _fails.size() == 0:
		print("=== IW ORDER & RESET TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== IW ORDER & RESET TEST FAILED (%d) ===" % _fails.size())
		get_tree().quit(1)
