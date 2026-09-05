extends Node
## 规则收录验证：27 本规则书全部 available 且有页面，打开可加载首页图片。

func _ready() -> void:
	var menu: PackedScene = load("res://src/ui/MainMenu.tscn")
	var inst: Control = menu.instantiate()
	add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	var bad: Array = []
	var books: Array = inst._rules_data.get("books", [])
	print("规则书总数=", books.size())
	if books.size() != 27:
		bad.append("应有 27 本规则书: %d" % books.size())
	var all_avail := true
	var all_pages := true
	for b in books:
		if not b.get("available", false):
			all_avail = false
			print("未收录: ", b.get("name"))
		if int(b.get("pages", 0)) <= 0:
			all_pages = false
			print("页数为0: ", b.get("name"))
	if not all_avail:
		bad.append("存在未收录的规则书")
	if not all_pages:
		bad.append("存在页数为 0 的规则书")
	# 打开基础规则书，验证首页图片可加载
	inst._open_rule("base")
	for i in range(5):
		await get_tree().process_frame
	if inst._rule_pages.size() != 12:
		bad.append("基础规则书应 12 页: %d" % inst._rule_pages.size())
	if inst._rule_view_img.texture == null:
		bad.append("基础规则首页图片加载失败")
	print("基础规则首页=", inst._rule_view_img.texture != null, " 页数=", inst._rule_pages.size())
	# 抽查一本扩展规则书
	inst._open_rule("civilwar")
	for i in range(5):
		await get_tree().process_frame
	if inst._rule_view_img.texture == null:
		bad.append("内战规则首页图片加载失败")
	print("内战规则首页加载=", inst._rule_view_img.texture != null)
	if bad.is_empty():
		print("=== RULES COLLECTION TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== RULES COLLECTION TEST FAILED: ", bad, " ===")
		get_tree().quit(1)
