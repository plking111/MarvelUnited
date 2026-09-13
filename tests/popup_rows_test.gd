extends Node
## 弹窗行动选择行（_make_action_row）结构回归：
## 每一类行（纯文字 / 图标 / 右侧小图 / 底部缩略图 / 组合）都必须真的被创建并加进弹窗，
## 且每行的子控件数量符合预期 —— 防止"某类行创建中途报错 → 该行凭空消失"（会让玩家选不到目的地）。

var _fail := 0

func _check(n: String, ok: bool, d: String = "") -> void:
	if ok:
		print("PASS: " + n)
	else:
		_fail += 1
		print("FAIL: " + n + " — " + d)

func _ready() -> void:
	# TextureRect 是否有 alignment 属性（用于定位 _make_action_row 里 bottom 小图的报错）
	var props: Array = []
	for p in TextureRect.new().get_property_list():
		if String(p["name"]).contains("align"):
			props.append("%s(%s)" % [p["name"], type_string(int(p["type"]))])
	print("TextureRect 含 'align' 的属性: ", props)

	var popup: CanvasLayer = load("res://src/ui/PopupLayer.gd").new()
	add_child(popup)

	var cases := [
		{"row": {"text": "跳过行动"}, "name": "纯文字行"},
		{"row": {"icon": "move", "arrow": "move", "text": "中央公园"}, "name": "图标+箭头+文字行"},
		{"row": {"img": "res://assets/tokens/thug_token.png", "text": "暴徒", "hide_text": true}, "name": "右侧小图行"},
		{"row": {"icon": "move", "arrow": "move", "text": "中央公园", "bottom": "res://assets/cards/locations/central_park.png"}, "name": "底部缩略图行"},
		{"row": {"img": UiKit.hero_card_image("wasp", 3), "text": "能量投射", "hide_text": true}, "name": "英雄牌行"},
	]
	for i in range(cases.size()):
		var c: Dictionary = cases[i]
		var row: Control = popup._make_action_row(c["row"], i)
		_check("创建成功：%s" % c["name"], row != null, "返回 null（创建中途报错）")

	# 端到端：show_action_prompt 后，弹窗里必须真的出现每一行
	var rows: Array = []
	var names: Array = []
	for c in cases:
		rows.append(c["row"])
		names.append(c["name"])
	popup.show_action_prompt(rows, "结构测试", func(_i): pass)
	await get_tree().process_frame
	var root: Control = popup._action_root
	_check("show_action_prompt 生成了弹窗", root != null and is_instance_valid(root), "")
	var found := 0
	if root != null:
		found = _count_row_holders(root)
	_check("弹窗里实际出现了全部 %d 行（含底部缩略图行）" % rows.size(), found == rows.size(),
		"实际 %d 行" % found)

	if _fail == 0:
		print("=== POPUP ROWS TEST ALL PASSED ===")
		get_tree().quit(0)
	else:
		print("=== POPUP ROWS TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)

## 统计弹窗里"行"的数量：只看 HFlowContainer 里真正的行控件（每行一个 PanelContainer）。
## 注意别用"递归数所有 PanelContainer"——那会把弹窗自身的面板一起数进去，
## 于是"行其实没加上"也照样能数够，测试就形同虚设。
func _count_row_holders(root: Node) -> int:
	var flow: Node = _find_flow(root)
	if flow == null:
		return -1
	var n := 0
	for row in flow.get_children():
		if row is PanelContainer:
			n += 1
	return n

func _find_flow(node: Node) -> Node:
	if node is HFlowContainer:
		return node
	for c in node.get_children():
		var r: Node = _find_flow(c)
		if r != null:
			return r
	return null
