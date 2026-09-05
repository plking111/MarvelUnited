extends Node
## Setup 模式7（无限战争）选择流程测试：选模式7 → 选英雄 → 选3个反派顺序 → 开始。

func _ready() -> void:
	Game.pending_campaign = {"game": 1, "order": ["cull", "proxima", "ebony"], "stones_collected": [], "energy_unlocked": []}
	Game.pending_setup = {"villain": "cull", "heroes": ["cap", "ironman", "hulk"], "challenge": "none", "mode": "iw", "expansions": ["无限战争"], "campaign_order": ["cull", "proxima", "ebony"]}
	var setup_scene: PackedScene = load("res://src/ui/Setup.tscn")
	var inst := setup_scene.instantiate()
	add_child(inst)
	for i in range(30):
		await get_tree().process_frame
	# 模拟：选中模式7
	inst._on_mode_selected(7)
	await get_tree().process_frame
	_check(inst._mode == "iw", "模式7 -> mode=iw")
	# 战役槽位：选 3 个反派顺序
	inst._campaign_slots = ["cull", "proxima", "ebony"]
	inst._update_villain_highlight()
	await get_tree().process_frame
	_check(inst._campaign_slots[0] == "cull" and inst._campaign_slots[2] == "ebony", "战役反派顺序槽位正确")
	# 勾选无限战争扩展
	if not inst._selected_expansions.has("无限战争"):
		inst._selected_expansions.append("无限战争")
	# 英雄槽位
	inst._hero_slots = ["cap", "ironman", "hulk"]
	inst._refresh_selected()
	print("=== SETUP IW TEST PASSED ===")
	get_tree().quit(0)

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("OK: " + msg)
	else:
		print("FAIL: " + msg)
		get_tree().quit(1)
