extends Node
## 回归：棋盘上的英雄/反派图标（用卡背贴图）必须**每一位都能加载**。
##
## 背景（用户报的 bug）：`Board.gd` 里原来把英雄 id 写成**硬编码列表**，每加一批英雄都要手改；
## 第三批 13 位漏改了 → `_hero_icons` 里没有它们 → 地点上的英雄图标全是黑的（贴图为空、露出深色底板）。
## 现在 `Board.gd` 改成遍历 `DB.heroes.keys()`，这个测试就是防止以后又退回硬编码。

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _ready() -> void:
	Game.pending_setup = {
		"villain": "redskull", "heroes": ["adamwarlock", "msmarvel", "nebula"],
		"challenge": "none", "mode": "base", "expansions": [], "debug_full_slots": false, "peek_hands": false,
	}
	var board: Control = load("res://src/ui/Board.tscn").instantiate()
	add_child(board)
	await _frames(4)

	var bad: Array = []
	# ① 每一位英雄都要有贴图（含第三批）
	for hid in DB.heroes.keys():
		var t: Texture2D = board._hero_icons.get(String(hid))
		if t == null:
			bad.append("英雄图标缺失：%s(%s)" % [String(hid), DB.hero_name(String(hid))])
	# ② 每一个反派也要有贴图
	for vid in DB.villains.keys():
		var tv: Texture2D = board._villain_icons.get(String(vid))
		if tv == null:
			bad.append("反派图标缺失：%s" % String(vid))
	# ③ 覆盖面：_hero_icons 的条目数应等于全部英雄数（不能少）
	if board._hero_icons.size() != DB.heroes.size():
		bad.append("_hero_icons 条目数 %d ≠ 英雄总数 %d" % [board._hero_icons.size(), DB.heroes.size()])
	# ④ 抽查第三批的 13 位逐一非空
	for hid2 in ["adamwarlock", "missamerica", "nebula", "yondou", "ghostrider", "mockingbird",
			"shehulk", "squirrelgirl", "moonknight", "nova", "blade", "howardtheduck", "msmarvel"]:
		if board._hero_icons.get(hid2) == null:
			bad.append("第三批英雄图标缺失：%s" % hid2)

	print("英雄数=%d，_hero_icons 条目=%d，反派数=%d" % [DB.heroes.size(), board._hero_icons.size(), DB.villains.size()])
	if bad.is_empty():
		print("=== HERO ICONS TEST PASSED ===")
		get_tree().quit(0)
	else:
		for b in bad:
			print("FAIL: " + String(b))
		print("=== HERO ICONS TEST FAILED (%d) ===" % bad.size())
		get_tree().quit(1)
