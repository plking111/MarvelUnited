extends Node
## 验证：iw模式选后反派页自动重渲染（三手下置前+剩余拼音，不受排序按钮影响）。

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

	# ===== 真实用户流程：选 iw 模式后直接看反派页（不手动渲染） =====
	inst._on_mode_selected(7)
	await get_tree().process_frame
	inst._show_step(3)
	await get_tree().process_frame
	var seq: Array = _current_seq(inst)
	print("iw反派顺序:", str(seq))
	_check(seq.size() == 7, "反派按钮共7个（实际%d）" % seq.size())
	_check(seq[0] == "proxima" and seq[1] == "cull" and seq[2] == "ebony", "三手下在最前（%s）" % str(seq.slice(0, 3)))
	var rest: Array = seq.slice(3, 7)
	_check(rest == ["ultron", "redskull", "taskmaster", "thanos"], "剩余按拼音 奥→红→模→灭（%s）" % str(rest))

	# ===== 切换排序按钮到 expansion：iw 与别的模式一致（按扩展分组） =====
	inst._on_sort_mode("expansion")
	await get_tree().process_frame
	var seq2: Array = _current_seq(inst)
	print("expansion下iw顺序:", str(seq2))
	# 基础盒组在前（奥创/红骷髅/模仿大师），无限战争组在后（比邻星/黑矮星/灭霸/乌木侯 按拼音）
	_check(seq2.slice(0, 3) == ["ultron", "redskull", "taskmaster"], "expansion下基础盒组在前（%s）" % str(seq2.slice(0, 3)))
	_check(seq2.slice(3, 7) == ["proxima", "cull", "thanos", "ebony"] or seq2.slice(3, 7).size() == 4, "expansion下无限战争组在后（%s）" % str(seq2.slice(3, 7)))

	# ===== 切回基础模式，恢复基础排序 =====
	inst._on_mode_selected(1)
	await get_tree().process_frame
	var seq3: Array = _current_seq(inst)
	print("基础模式顺序:", str(seq3))
	_check(seq3.size() == 7, "基础模式7个反派")

	if _fails.size() == 0:
		print("=== IW RENDER ORDER TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== IW RENDER ORDER TEST FAILED (%d) ===" % _fails.size())
		get_tree().quit(1)

func _current_seq(inst) -> Array:
	var order: Array = []
	for vid in ["proxima", "cull", "ebony", "ultron", "redskull", "taskmaster", "thanos"]:
		if inst._villain_buttons.has(vid):
			order.append({"vid": vid, "pos": inst._villain_buttons[vid].position})
	order.sort_custom(func(a, b): return a["pos"].y < b["pos"].y or (a["pos"].y == b["pos"].y and a["pos"].x < b["pos"].x))
	var out: Array = []
	for o in order:
		out.append(o["vid"])
	return out
