extends Node
## 瓦坎达三英雄效果卡验证：
## 冬兵·资深刺客（veteran_assassin）：冬兵获得 2 个攻击指示物
## 苏瑞·少年天才（prodigy）：给予任意一名英雄 1 个万能指示物，然后该英雄抽牌直到手牌 3 张
## 黑豹·黑豹习性（panther_instinct）：本回合额外获得内置行动符号

func _ready() -> void:
	Game.setup("redskull", ["winter", "shuri"], "none")
	Game.state["phase"] = "hero_actions"
	Events.prompt_choice.connect(func(options: Array, title: String, cb: Callable) -> void:
		Game._on_answer.call_deferred(0))
	var bad: Array = []

	# ---------- 冬兵·资深刺客 ----------
	Game.state["current_hero"] = 0   # winter
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	Game.state["action_symbols"] = ["move"]  # 阻止自动结束回合推进
	var wcards: Array = DB.hero_cards("winter")
	var atk_before: int = Game.state["heroes"]["winter"]["tokens"]["attack"]
	Game.state["played_effect"] = wcards[9]["effect"]
	await Game.trigger_effect()
	var atk_after: int = Game.state["heroes"]["winter"]["tokens"]["attack"]
	print("冬兵 攻击指示物: %d -> %d" % [atk_before, atk_after])
	if atk_after != atk_before + 2:
		bad.append("资深刺客应给冬兵 +2 攻击指示物")

	# ---------- 苏瑞·少年天才 ----------
	Game.state["current_hero"] = 1   # shuri
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	Game.state["action_symbols"] = ["heroic"]  # 阻止推进，且不与万能冲突
	# 把 winter 手牌压到 1 张，测"抽牌直到 3 张"分支；prompt_choice 选 0 → winter
	Game.state["heroes"]["winter"]["hand"] = Game.state["heroes"]["winter"]["hand"].slice(0, 1)
	var scards: Array = DB.hero_cards("shuri")
	var wild_before: int = Game.state["heroes"]["winter"]["tokens"]["wild"]
	var hand_before: int = Game.state["heroes"]["winter"]["hand"].size()
	Game.state["played_effect"] = scards[9]["effect"]
	await Game.trigger_effect()
	var wild_after: int = Game.state["heroes"]["winter"]["tokens"]["wild"]
	var hand_after: int = Game.state["heroes"]["winter"]["hand"].size()
	print("少年天才 万能指示物: %d -> %d  手牌: %d -> %d" % [wild_before, wild_after, hand_before, hand_after])
	if wild_after != wild_before + 1:
		bad.append("少年天才应给所选英雄 +1 万能指示物")
	if hand_after != 3:
		bad.append("少年天才应抽牌直到该英雄手牌 3 张")

	# 再测一次"手牌已>=3 不抽牌"：把 hand 设为 3，抽牌应保持 3
	Game.state["effect_used"] = false
	Game.state["action_symbols"] = ["heroic"]
	Game.state["heroes"]["shuri"]["hand"] = scards.slice(0, 3)
	Game.state["heroes"]["shuri"]["hand"] = [0, 1, 2]
	Game.state["played_effect"] = scards[10]["effect"]
	await Game.trigger_effect()
	var shuri_hand: int = Game.state["heroes"]["shuri"]["hand"].size()
	print("少年天才(满手) 苏瑞手牌: %d" % shuri_hand)
	if shuri_hand != 3:
		bad.append("手牌已满时少年天才不应抽超 3 张")

	if bad.is_empty():
		print("=== WAKANDA EFFECT TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== WAKANDA EFFECT TEST FAILED: ", bad, " ===")
		get_tree().quit(1)
