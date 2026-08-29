extends Node
## 验证奥创克隆体爪牙：BAM 时该地点放 1 暴徒；若全部英雄都选择受 1 伤则阻止。

func _ready() -> void:
	Game.pending_setup = {"villain": "ultron", "heroes": ["cap", "ironman", "hulk"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	var st: Dictionary = Game.state
	# 场景1：autopilot（_ask_confirm 返回 true → 全部选择受伤 → 阻止放暴徒）
	var loc := 1
	st["locations"][loc]["thug"] = 0
	st["locations"][loc]["threat"] = {"name": "奥创克隆体", "hp": 4, "bam": true, "text": ""}
	st["heroes"]["cap"]["location"] = loc
	st["heroes"]["ironman"]["location"] = loc
	st["heroes"]["hulk"]["location"] = 4  # 不在该地点
	st["heroes"]["cap"]["hand"] = [0, 1, 2]
	st["heroes"]["ironman"]["hand"] = [0, 1, 2]
	Game.autopilot = true
	await Game._trigger_all_threat_bam()
	var ok1: bool = st["locations"][loc]["thug"] == 0  # 阻止放暴徒
	var ok2: bool = st["heroes"]["cap"]["hand"].size() == 2 and st["heroes"]["ironman"]["hand"].size() == 2  # 各自受 1 伤
	print("场景1: 暴徒=", st["locations"][loc]["thug"], " cap手牌=", st["heroes"]["cap"]["hand"].size(), " iron手牌=", st["heroes"]["ironman"]["hand"].size())
	# 场景2：cap 拒绝受伤 → 放暴徒；清掉场景1 的威胁，只留 loc2 一个
	var loc2 := 3
	for li in range(6):
		if li != loc2:
			st["locations"][li]["threat"] = null
	st["locations"][loc2]["thug"] = 0
	st["locations"][loc2]["threat"] = {"name": "奥创克隆体", "hp": 4, "bam": true, "text": ""}
	st["heroes"]["cap"]["location"] = loc2
	st["heroes"]["ironman"]["location"] = 4
	st["heroes"]["hulk"]["location"] = 4
	st["heroes"]["cap"]["hand"] = [0, 1, 2]
	st["heroes"]["ironman"]["hand"] = [0, 1, 2]
	Game.autopilot = false
	# 连接确认信号：每次询问都回答 false（拒绝）→ 第一个英雄拒绝即停止询问并放暴徒
	var cb := func(_text: String, _cb: Callable) -> void:
		Game._on_answer.call_deferred(false)
	Events.prompt_confirm.connect(cb)
	await Game._trigger_all_threat_bam()
	Events.prompt_confirm.disconnect(cb)
	for i in range(3):
		await get_tree().process_frame
	var ok3: bool = st["locations"][loc2]["thug"] == 1  # 有人拒绝 → 放暴徒
	var ok4: bool = st["heroes"]["cap"]["hand"].size() == 3  # 拒绝者不受伤
	print("场景2: 暴徒=", st["locations"][loc2]["thug"], " cap手牌=", st["heroes"]["cap"]["hand"].size(), " (期望3不受伤)")
	if ok1 and ok2 and ok3 and ok4:
		print("=== ULTRON CLONE TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== ULTRON CLONE TEST FAILED ===", [ok1, ok2, ok3, ok4])
		get_tree().quit(1)
