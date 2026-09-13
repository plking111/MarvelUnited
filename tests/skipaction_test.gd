extends Node
## 跳过/返回行动验证（bug2+需求1）：
## 「跳过行动」= 放弃该行动，行动数量减一（不归还）；
## 「返回」= 归还本次消耗的行动，可重新选择行动。

var _answer_mode := 2  # 1=跳过(倒数第2项) 0=返回(最后一项)

func _ready() -> void:
	Game.setup("redskull", ["cap"], "none")
	var hid := "cap"
	var loc: int = Game.state["heroes"][hid]["location"]
	Game.state["locations"][loc]["thug"] = 1
	Game.state["heroes"][hid]["hand"] = [0, 1, 2]
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	var bad: Array = []
	Events.prompt_choice.connect(func(options: Array, title: String, cb: Callable) -> void:
		Game._on_answer.call_deferred(options.size() - _answer_mode))
	# 攻击目标/跳过/返回这些弹窗现在走行动弹窗（prompt_action）而不是纯文字 prompt_choice，
	# 所以这里也必须接：把 rows 摊平成"选项文字数组"后索引含义不变，"倒数第 N 项"逻辑照用。
	Events.prompt_action.connect(func(rows: Array, _t3: String, _cb3: Callable) -> void:
		var options: Array = []
		for r in rows:
			options.append(String((r as Dictionary).get("text", "")))
		Game._on_answer.call_deferred(options.size() - _answer_mode))

	# 场景1：跳过攻击（选「跳过行动」，倒数第2项）→ 符号被消耗（数量减一），不归还
	_answer_mode = 2
	Game.state["action_symbols"] = ["attack"]
	Game.use_symbol("attack")
	for i in range(8):
		await get_tree().process_frame
	print("跳过攻击后 符号=%s 暴徒=%d" % [str(Game.state["action_symbols"]), Game.state["locations"][loc]["thug"]])
	if Game.state["action_symbols"].count("attack") != 0:
		bad.append("跳过攻击应消耗该行动（数量减一）")
	if Game.state["locations"][loc]["thug"] != 1:
		bad.append("跳过攻击不应造成伤害")

	# 场景2：返回（选最后一项「返回」）→ 归还攻击符号，可重新选择
	_answer_mode = 1
	Game.state["phase"] = "hero_actions"
	Game.state["action_symbols"] = ["attack"]
	Game.use_symbol("attack")
	for i in range(8):
		await get_tree().process_frame
	print("返回后 符号=%s 暴徒=%d phase=%s" % [str(Game.state["action_symbols"]), Game.state["locations"][loc]["thug"], Game.state["phase"]])
	if Game.state["action_symbols"].count("attack") != 1:
		bad.append("返回应归还攻击符号（重新选择行动）")
	if Game.state["phase"] != "hero_actions":
		bad.append("返回后应停留在行动阶段")

	if bad.is_empty():
		print("=== SKIP ACTION TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== SKIP ACTION TEST FAILED: ", bad, " ===")
		get_tree().quit(1)
