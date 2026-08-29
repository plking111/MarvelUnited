extends Node
## 钢铁侠效果卡验证：
## 基础=攻击的效果卡 → 从供应池拿 2 个【移动】指示物
## 基础=移动的效果卡 → 从供应池拿 2 个【攻击】指示物
## 两次分配都选 0 号英雄（cap）。

func _ready() -> void:
	Game.setup("redskull", ["cap", "ironman"], "none")
	Game.state["phase"] = "hero_actions"
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	Events.prompt_choice.connect(func(options: Array, title: String, cb: Callable) -> void:
		Game._on_answer.call_deferred(0))
	var bad: Array = []

	# 场景1：卡牌下标9（基础=攻击）→ +2 移动指示物
	var cards: Array = DB.hero_cards("ironman")
	var move_before: int = Game.state["heroes"]["cap"]["tokens"]["move"] + Game.state["heroes"]["ironman"]["tokens"]["move"]
	Game.state["played_effect"] = cards[9]["effect"]
	Game.state["action_symbols"] = ["move"]  # 留一个符号：阻止自动结束回合推进
	await Game.trigger_effect()
	var move_after: int = Game.state["heroes"]["cap"]["tokens"]["move"] + Game.state["heroes"]["ironman"]["tokens"]["move"]
	print("移动指示物: %d -> %d" % [move_before, move_after])
	if move_after != move_before + 2:
		bad.append("基础攻击卡应给 2 个移动指示物")

	# 场景2：卡牌下标10（基础=移动）→ +2 攻击指示物
	Game.state["effect_used"] = false
	Game.state["phase"] = "hero_actions"
	Game.state["action_symbols"] = ["move"]
	var atk_before: int = Game.state["heroes"]["cap"]["tokens"]["attack"] + Game.state["heroes"]["ironman"]["tokens"]["attack"]
	Game.state["played_effect"] = cards[10]["effect"]
	await Game.trigger_effect()
	var atk_after: int = Game.state["heroes"]["cap"]["tokens"]["attack"] + Game.state["heroes"]["ironman"]["tokens"]["attack"]
	print("攻击指示物: %d -> %d" % [atk_before, atk_after])
	if atk_after != atk_before + 2:
		bad.append("基础移动卡应给 2 个攻击指示物")

	if bad.is_empty():
		print("=== IRON EFFECT TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== IRON EFFECT TEST FAILED: ", bad, " ===")
		get_tree().quit(1)
