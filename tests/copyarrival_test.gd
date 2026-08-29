extends Node
## 验证奥创威胁卡「复制」：奥创到达该威胁卡地点时在该地点放 1 暴徒。

func _ready() -> void:
	Game.pending_setup = {"villain": "ultron", "heroes": ["cap", "ironman", "hulk"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	var st: Dictionary = Game.state
	# 场景：2 号地点有「复制」威胁，奥创移动到该地点
	var loc := 2
	st["locations"][loc]["thug"] = 0
	st["locations"][loc]["threat"] = {"name": "复制", "text": "该地点增加 1 个暴徒", "arrival": true, "bam": false, "start_turn": false, "constant": false}
	st["villain_pos"] = (loc + 1) % 6  # 从别处移动
	Game.autopilot = true
	# 直接调用到达触发
	await Game._trigger_threat_arrival(loc)
	var ok1: bool = st["locations"][loc]["thug"] == 1
	print("复制到达效果: 2号地点暴徒=", st["locations"][loc]["thug"], " (期望1)")
	# 场景2：无到达标志的威胁不触发
	st["locations"][loc]["thug"] = 0
	st["locations"][loc]["threat"] = {"name": "奥创病毒", "text": "忽略符号", "arrival": false, "bam": false, "start_turn": true, "constant": false}
	await Game._trigger_threat_arrival(loc)
	var ok2: bool = st["locations"][loc]["thug"] == 0
	print("无到达标志: 暴徒=", st["locations"][loc]["thug"], " (期望0)")
	if ok1 and ok2:
		print("=== ULTRON COPY ARRIVAL TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== ULTRON COPY ARRIVAL TEST FAILED ===", [ok1, ok2])
		get_tree().quit(1)
