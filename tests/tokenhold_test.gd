extends Node
## 行动指示物验证（bug2）：符号用完但还有行动指示物时，不自动结束回合；
## 符号+指示物都用尽后，才自动结束回合。

func _ready() -> void:
	Game.setup("redskull", ["cap"], "none")
	for l in Game.state["locations"]:
		l["threat"] = null  # 避免精锐暴徒（需2伤）干扰
	var hid := "cap"
	var loc: int = Game.state["heroes"][hid]["location"]
	Game.state["locations"][loc]["thug"] = 2
	Game.state["heroes"][hid]["hand"] = [0, 1, 2]
	Game.state["phase"] = "hero_actions"
	Game.state["action_symbols"] = ["attack"]
	Game.state["heroes"][hid]["tokens"]["attack"] = 1
	Events.prompt_choice.connect(func(options: Array, title: String, cb: Callable) -> void:
		Game._on_answer.call_deferred(0))  # 攻击目标选暴徒
	var bad: Array = []

	# 场景1：符号用完，但还有 1 个攻击指示物 → 不自动结束
	Game.use_symbol("attack")
	for i in range(8):
		await get_tree().process_frame
	print("场景1 符号=%s 指示物=%d phase=%s 暴徒=%d" % [str(Game.state["action_symbols"]), Game.state["heroes"][hid]["tokens"]["attack"], Game.state["phase"], Game.state["locations"][loc]["thug"]])
	if Game.state["phase"] != "hero_actions":
		bad.append("还有行动指示物时不应自动结束回合")
	if Game.state["locations"][loc]["thug"] != 1:
		bad.append("符号攻击应消灭 1 暴徒")

	# 场景2：再用掉攻击指示物 → 符号+指示物都用尽 → 自动结束回合
	Game.use_symbol("token_attack")
	for i in range(12):
		await get_tree().process_frame
	print("场景2 符号=%s 指示物=%d phase=%s 暴徒=%d" % [str(Game.state["action_symbols"]), Game.state["heroes"][hid]["tokens"]["attack"], Game.state["phase"], Game.state["locations"][loc]["thug"]])
	if Game.state["phase"] == "hero_actions":
		bad.append("符号与指示物都用尽后应自动结束回合")
	if Game.state["locations"][loc]["thug"] != 0:
		bad.append("指示物攻击应消灭第 2 个暴徒")

	if bad.is_empty():
		print("=== TOKEN HOLD TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== TOKEN HOLD TEST FAILED: ", bad, " ===")
		get_tree().quit(1)
