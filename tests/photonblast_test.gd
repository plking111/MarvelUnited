extends Node
## 惊奇队长光子冲击验证：在相邻地点执行 2 次攻击，每次可自选目标（暴徒/爪牙/反派）。

func _ready() -> void:
	Game.setup("redskull", ["cmarvel"], "none")
	var hid := "cmarvel"
	var loc: int = Game.state["heroes"][hid]["location"]
	var adj := (loc + 1) % Game.LOCATION_COUNT
	# 只清相邻地点的威胁（避免精锐暴徒干扰攻击次数判定）；英雄所在地保留威胁
	Game.state["locations"][adj]["threat"] = null
	Game.state["locations"][adj]["thug"] = 2
	Game.state["heroes"][hid]["hand"] = [0, 1, 2]
	Game.state["phase"] = "hero_actions"
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	Events.prompt_choice.connect(func(options: Array, title: String, cb: Callable) -> void:
		if title.contains("相邻地点"):
			Game._on_answer.call_deferred(1)   # 选择第二个相邻地点（loc+1，暴徒所在处）
		else:
			Game._on_answer.call_deferred(0))  # 每次攻击目标选暴徒
	Game.state["played_effect"] = DB.hero_cards("cmarvel")[6]["effect"]
	await Game.trigger_effect()
	var thugs_left: int = Game.state["locations"][adj]["thug"]
	print("相邻地点剩余暴徒=", thugs_left)
	if thugs_left == 0:
		print("=== PHOTON BLAST TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== PHOTON BLAST TEST FAILED: 只攻击了 %d 次 ===" % (2 - thugs_left))
		get_tree().quit(1)
