extends Node
## 纠缠陷阱验证：英雄从带「纠缠陷阱」威胁卡的地点移动离开，
## 必须消耗 2 个移动行动（不是 1 个）。
## 场景1：仅 1 个移动 → 不能离开，移动被归还
## 场景2：2 个移动符号 → 正常离开，消耗 2 个
## 场景3：1 个移动符号 + 1 个移动指示物 → 正常离开，各消耗 1
## 场景4：仅 1 个移动指示物 → 不能离开，指示物被归还

func _ready() -> void:
	Game.setup("taskmaster", ["cap"], "none")
	var hid := "cap"
	var loc := 0
	Game.state["heroes"][hid]["location"] = loc
	Game.state["locations"][loc]["threat"] = {
		"name": "纠缠陷阱", "text": "英雄使用移动行动离开该地点时，必须消耗 2 个移动行动才能离开",
		"henchman_hp": 0, "bam": false, "arrival": false, "start_turn": false, "constant": true,
	}
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	# 给手牌：避免行动用完后自动结束回合时触发 KO 弹窗
	Game.state["heroes"][hid]["hand"] = [0, 1, 2]
	# 自动应答"选择移动目的地"（选第一个相邻地点）
	Events.prompt_choice.connect(func(options: Array, title: String, cb: Callable) -> void:
		Game._on_answer.call_deferred(0))
	var bad: Array = []

	# 场景1：只有 1 个移动符号 → 不能离开，符号被归还
	Game.state["action_symbols"] = ["move"]
	Game.state["heroes"][hid]["tokens"]["move"] = 0
	Game.use_symbol("move")
	for i in range(4):
		await get_tree().process_frame
	var loc_after1: int = Game.state["heroes"][hid]["location"]
	var syms1: Array = Game.state["action_symbols"]
	print("场景1: 位置=%d 符号=%s 离开=%s" % [loc_after1, str(syms1), loc_after1 != loc])
	if loc_after1 != loc or syms1.count("move") != 1:
		bad.append("场景1失败：1个移动不应离开")

	# 场景2：2 个移动符号 → 正常离开，消耗 2 个
	Game.state["phase"] = "hero_actions"
	Game.state["action_symbols"] = ["move", "move"]
	Game.use_symbol("move")
	for i in range(4):
		await get_tree().process_frame
	var loc_after2: int = Game.state["heroes"][hid]["location"]
	var syms2: Array = Game.state["action_symbols"]
	print("场景2: 位置=%d 符号=%s 离开=%s" % [loc_after2, str(syms2), loc_after2 != loc])
	if loc_after2 == loc or syms2.size() != 0:
		bad.append("场景2失败：2个移动应离开且消耗2个")

	# 场景3：1 个移动符号 + 1 个移动指示物 → 正常离开
	Game.state["phase"] = "hero_actions"
	Game.state["heroes"][hid]["location"] = loc
	Game.state["action_symbols"] = ["move"]
	Game.state["heroes"][hid]["tokens"]["move"] = 1
	Game.use_symbol("move")
	for i in range(4):
		await get_tree().process_frame
	var loc_after3: int = Game.state["heroes"][hid]["location"]
	var syms3: Array = Game.state["action_symbols"]
	var tok3: int = Game.state["heroes"][hid]["tokens"]["move"]
	print("场景3: 位置=%d 符号=%s 指示物=%d 离开=%s" % [loc_after3, str(syms3), tok3, loc_after3 != loc])
	if loc_after3 == loc or syms3.size() != 0 or tok3 != 0:
		bad.append("场景3失败：符号+指示物应各消耗1并离开")

	# 场景4：仅 1 个移动指示物 → 不能离开，指示物被归还
	Game.state["phase"] = "hero_actions"
	Game.state["heroes"][hid]["location"] = loc
	Game.state["action_symbols"] = []
	Game.state["heroes"][hid]["tokens"]["move"] = 1
	Game.use_symbol("token_move")
	for i in range(4):
		await get_tree().process_frame
	var loc_after4: int = Game.state["heroes"][hid]["location"]
	var tok4: int = Game.state["heroes"][hid]["tokens"]["move"]
	print("场景4: 位置=%d 指示物=%d 离开=%s" % [loc_after4, tok4, loc_after4 != loc])
	if loc_after4 != loc or tok4 != 1:
		bad.append("场景4失败：1个指示物不应离开且应归还")

	if bad.is_empty():
		print("=== ENTANGLE TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== ENTANGLE TEST FAILED: ", bad, " ===")
		get_tree().quit(1)
