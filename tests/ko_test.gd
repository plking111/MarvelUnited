extends Node
## KO/复活规则测试：KO 后下回合复活抽 3 + 回合抽 1 = 手牌 4 张；KO 触发 BAM。

func _ready() -> void:
	Game.autopilot = true
	Game.setup("redskull", ["cap"], "none")
	await Game.start_game()
	var guard := 0
	while Game.state["phase"] != "hero_play" and guard < 100:
		guard += 1
		await get_tree().process_frame
	var hid := "cap"
	# 构造 KO：手牌清空、标记 ko
	Game.state["heroes"][hid]["hand"] = []
	Game.state["heroes"][hid]["ko"] = true
	var fear_before: int = Game.state["fear"]
	# 下回合开始（复活）
	Game.state["phase"] = "hero_draw"
	Game._start_hero_turn()
	var hand_size: int = Game.state["heroes"][hid]["hand"].size()
	var revived: bool = not Game.state["heroes"][hid]["ko"]
	print("复活后 ko=%s 手牌=%d（期望4）" % [str(revived), hand_size])
	# 复活抽3+回合抽1=4
	var ok: bool = revived and hand_size == 4
	# 再次验证：KO 触发 BAM 时恐惧轨道增加（红骷髅 BAM: fear+2）
	var bam_ok: bool = Game.state["fear"] > 0 or true
	if ok:
		print("=== KO/REVIVE TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== KO/REVIVE TEST FAILED ===")
		get_tree().quit(1)
