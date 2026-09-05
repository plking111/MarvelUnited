extends Node
## 英雄页布局验证：图标必须渲染在 _hero_grid（scroll 内容区）内，
## 不落入页面上方文字/排序钮/人数行区域；扩展排序与搜索过滤后仍从左上角紧凑重排。
var setup: Node

func _ready() -> void:
	# 实例化 Setup 场景
	var scene := load("res://src/ui/Setup.tscn")
	setup = scene.instantiate()
	add_child(setup)
	await get_tree().process_frame
	await get_tree().process_frame
	setup._show_step(2)
	await get_tree().process_frame
	await get_tree().process_frame

	var bad: Array = []

	# --- 上方控件不得越过滚动区顶边（否则与英雄卡重叠）---
	_check_topcontrols("上方控件", bad)

	# --- 初始 alpha 排序 ---
	_check_layout("初始alpha", bad)
	var n0: int = setup._hero_buttons.size()
	print("初始英雄数=", n0, " (期望 16)")

	# --- 切换到扩展排序 ---
	setup._on_sort_mode("expansion")
	await get_tree().process_frame
	_check_layout("扩展排序", bad)
	var nexp: int = setup._hero_buttons.size()
	print("扩展排序英雄数=", nexp, " (期望 16)")

	# --- 返回 alpha 再搜索 ---
	setup._on_sort_mode("alpha")
	await get_tree().process_frame
	setup._hero_search.text = "黑"
	setup._on_hero_search("黑")
	await get_tree().process_frame
	_check_layout("搜索'黑'", bad)
	var nsearch: int = setup._hero_buttons.size()
	print("搜索'黑'匹配数=", nsearch, " (期望 2: 黑寡妇/黑豹)")
	# 搜索后：匹配项应从左上角(60,0)起紧凑排列，首行首个为最左上
	if setup._hero_buttons.size() > 0:
		var first: Control = setup._hero_buttons.values()[0]
		var p := first.position
		print("搜索后首个位置=", p)
		if p.x != 60.0 or p.y != 0.0:
			bad.append("搜索后首个应从(60,0)开始，实际 %s" % str(p))

	# 清空搜索
	setup._hero_search.text = ""
	setup._on_hero_search("")
	await get_tree().process_frame
	_check_layout("清空搜索", bad)

	print("---- RESULT ----")
	if bad.is_empty():
		print("=== HERO LAYOUT PASSED ===")
		get_tree().quit(0)
	else:
		print("=== FAILED: ", bad, " ===")
		get_tree().quit(1)

## 断言：所有英雄图标父级==_hero_grid，且未落入页面上方文字区(y<210)或超出滚动可视区
func _check_layout(tag: String, bad: Array) -> void:
	var grid: Control = setup._hero_grid
	if grid == null:
		bad.append(tag + ":_hero_grid 为空")
		return
	var cnt: int = 0
	for hid in setup._hero_buttons:
		var box: Control = setup._hero_buttons[hid]
		if box.get_parent() != grid:
			bad.append(tag + ": 卡片 %s 父级不在 _hero_grid（被渲染到页面顶层）" % hid)
		# 卡片的 y 坐标（相对 grid）：grid 在 scroll 内（页面 y=210），所以卡片局部 y=0 即页面 y=210
		if box.position.y < 0.0:
			bad.append(tag + ": 卡片 %s 局部 y=%s 越界进入上方" % [hid, str(box.position.y)])
		cnt += 1
	print(tag, " 卡片全部在 grid 内:", cnt)

## 断言：页面上方控件（标题/排序钮/搜索框/人数行全部子树）底边都不得越过滚动区顶边(210)
func _check_topcontrols(tag: String, bad: Array) -> void:
	var scroll: ScrollContainer = setup._hero_scroll
	if scroll == null:
		bad.append(tag + ":_hero_scroll 为空")
		return
	var top: float = scroll.global_position.y  # 210
	# 检查页面2顶层的非 scroll 控件（标题/排序/搜索/人数行容器）
	var page: Control = setup._step_pages[2]
	for c in page.get_children():
		if c is Control and not (c is ScrollContainer):
			_walk_bottom(c, top, bad)
	# 人数行内部控件特别检查（加减按钮/当前人数标签之前会越过 210）
	var cr: Control = setup._count_row
	if cr != null:
		_walk_bottom(cr, top, bad)

func _walk_bottom(node: Control, top: float, bad: Array) -> void:
	var b: float = node.global_position.y + node.size.y
	if b > top:
		bad.append("控件 %s 底边 %.0f 越过滚动区顶边 %.0f（与英雄卡重叠）" % [node.get_class(), b, top])
	for c in node.get_children():
		if c is Control:
			_walk_bottom(c, top, bad)
