extends Node
## 反派页布局验证：图标必须渲染在 _villain_grid（scroll 内容区）内，
## 不落入页面上方文字/排序钮/搜索框区域；扩展排序与搜索过滤后仍从左上角紧凑重排。
var setup: Node

func _ready() -> void:
	var scene := load("res://src/ui/Setup.tscn")
	setup = scene.instantiate()
	add_child(setup)
	await get_tree().process_frame
	await get_tree().process_frame
	setup._show_step(3)
	await get_tree().process_frame
	await get_tree().process_frame

	var bad: Array = []

	# --- 上方控件不得越过滚动区顶边（否则与反派卡重叠）---
	var scroll: ScrollContainer = setup._villain_scroll
	if scroll == null:
		bad.append("_villain_scroll 为空")
	else:
		var top: float = scroll.global_position.y
		var page: Control = setup._step_pages[3]
		for c in page.get_children():
			if c is Control and not (c is ScrollContainer):
				_walk_bottom(c, top, bad)

	# --- 初始 alpha 排序：卡片全部在 grid 内 ---
	_check_layout("初始alpha", bad)
	var n0: int = setup._villain_buttons.size()
	print("初始反派数=", n0, " (期望 9)")

	# --- 切到扩展排序 ---
	setup._on_sort_mode("expansion")
	await get_tree().process_frame
	_check_layout("扩展排序", bad)
	print("扩展反派数=", setup._villain_buttons.size(), " (期望 9)")

	# --- 返回 alpha 再搜索 ---
	setup._on_sort_mode("alpha")
	await get_tree().process_frame
	setup._villain_search.text = "洛"
	setup._on_villain_search("洛")
	await get_tree().process_frame
	_check_layout("搜索'洛'", bad)
	var nsearch: int = setup._villain_buttons.size()
	print("搜索'洛'匹配数=", nsearch, " (期望 1: 洛基)")
	if setup._villain_buttons.size() > 0:
		var first: Control = setup._villain_buttons.values()[0]
		var p := first.position
		print("搜索后首个位置=", p)
		if p.x != 60.0 or p.y != 0.0:
			bad.append("搜索后首个应从(60,0)开始，实际 %s" % str(p))

	# --- 清空搜索 ---
	setup._villain_search.text = ""
	setup._on_villain_search("")
	await get_tree().process_frame
	_check_layout("清空搜索", bad)

	print("---- RESULT ----")
	if bad.is_empty():
		print("=== VILLAIN LAYOUT PASSED ===")
		get_tree().quit(0)
	else:
		print("=== FAILED: ", bad, " ===")
		get_tree().quit(1)

func _check_layout(tag: String, bad: Array) -> void:
	var grid: Control = setup._villain_grid
	if grid == null:
		bad.append(tag + ":_villain_grid 为空")
		return
	var cnt: int = 0
	for vid in setup._villain_buttons:
		var box: Control = setup._villain_buttons[vid]
		if box.get_parent() != grid:
			bad.append(tag + ": 卡片 %s 父级不在 _villain_grid（被渲染到页面顶层）" % vid)
		if box.position.y < 0.0:
			bad.append(tag + ": 卡片 %s 局部 y=%s 越界进入上方" % [vid, str(box.position.y)])
		cnt += 1
	print(tag, " 卡片全部在 grid 内:", cnt)

func _walk_bottom(node: Control, top: float, bad: Array) -> void:
	var b: float = node.global_position.y + node.size.y
	if b > top:
		bad.append("控件 %s 底边 %.0f 越过滚动区顶边 %.0f（与反派卡重叠）" % [node.get_class(), b, top])
	for c in node.get_children():
		if c is Control:
			_walk_bottom(c, top, bad)
