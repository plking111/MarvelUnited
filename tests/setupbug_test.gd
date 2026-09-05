extends Node
## 验证：bug1 威胁卡英勇槽下移4px；bug2 非iw默认无反派选框；
## bug3 iw模式默认选中 暗夜比邻星/黑矮星/乌木侯 + 灭霸置暗。

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

	# ===== bug2：未选模式/基础模式时反派无默认选框 =====
	_check(inst._selected_villain == "", "非iw模式默认不选反派（_selected_villain='%s'）" % inst._selected_villain)

	# ===== bug3：iw 模式默认选中三手下 + 灭霸置暗 =====
	inst._on_mode_selected(7)
	await get_tree().process_frame
	_check(inst._campaign_slots[0] == "proxima" and inst._campaign_slots[1] == "cull" and inst._campaign_slots[2] == "ebony",
		"iw默认顺序 暗夜比邻星/黑矮星/乌木侯（%s）" % str(inst._campaign_slots))
	inst._render_villains()
	await get_tree().process_frame
	var thanos_box: Control = inst._villain_buttons.get("thanos")
	_check(thanos_box != null and thanos_box.modulate != Color.WHITE, "灭霸图标置暗（modulate=%s）" % (str(thanos_box.modulate) if thanos_box != null else "null"))
	# 灭霸点击应被拒绝
	var thanos_btn: Button = thanos_box.get_child(thanos_box.get_child_count() - 1)
	thanos_btn.pressed.emit()
	await get_tree().process_frame
	_check(inst._campaign_slots[0] == "proxima", "点击灭霸不改变槽位（仍默认）")

	# ===== bug1：威胁卡英勇槽 y 下移 4px =====
	# 直接验证 LocationView 的 THREAT_HEROIC_SLOTS 渲染偏移（+4）
	Game.setup("redskull", ["cap"], "none")
	var lv: LocationView = LocationView.new()
	var bank := {"civ": null, "thug": null, "crisis": null, "threat": null, "heroic": null}
	lv.setup(0, Vector2(500, 500), bank, Callable())
	# 构造威胁卡并刷新英勇槽
	var t := {"name": "复制", "hp": 0, "heroic_tokens": 0, "bam": false, "arrival": false, "constant": false}
	lv.threat.custom_minimum_size = Vector2(96, 96)
	lv.threat.visible = true
	lv._update_threat_heroic_slots(t)
	var slot0: TextureRect = lv.heroic_slots[0]
	var expect_y: float = 0.802 * 96.0 - 27.0 / 2.0 + 4.0
	_check(abs(slot0.position.y - expect_y) < 0.5, "英勇槽 y=%.1f（期望 %.1f，+4px）" % [slot0.position.y, expect_y])

	if _fails.size() == 0:
		print("=== SETUP/THREAT BUGS TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== SETUP/THREAT BUGS TEST FAILED (%d) ===" % _fails.size())
		get_tree().quit(1)
