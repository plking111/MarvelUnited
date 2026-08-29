extends Node
## 神盾局单人模式测试：合并牌组、共享手牌、打出卡对应英雄行动、3 人局血量。

var _fail := 0

func _ready() -> void:
	Game.autopilot = false
	Game.setup("redskull", ["cap", "ironman", "hulk"], "none", "shield")
	# 合并牌组 36 张、初始共享手牌 5 张、反派 3 人局血量
	var deck: Array = Game.state["shield_deck"]
	var hand: Array = Game.state["shield_hand"]
	print("shield_deck=%d shield_hand=%d villain_hp=%d" % [deck.size(), hand.size(), Game.state["villain_hp"]])
	_check("合并牌组共36张", deck.size() + hand.size() == 36, "deck=%d hand=%d" % [deck.size(), hand.size()])
	_check("初始共享手牌5张", hand.size() == 5, "hand=%d" % hand.size())
	_check("反派3人局血量", Game.state["villain_hp"] == int(DB.villain("redskull")["health"]["3"]), "hp=%d" % Game.state["villain_hp"])
	# 开始游戏 → 反派回合 → hero_play
	Game.autopilot = true
	await Game.start_game()
	Game.autopilot = false
	var guard := 0
	while Game.state["phase"] != "hero_play" and guard < 100:
		guard += 1
		await get_tree().process_frame
	_check("进入英雄阶段", Game.state["phase"] == "hero_play", "phase=%s" % Game.state["phase"])
	# 打出第一张共享手牌 → 该卡所属英雄行动
	var hand2: Array = Game.state["shield_hand"]
	if hand2.size() > 0:
		var first: Dictionary = hand2[0]
		var owner: String = first["hero"]
		Game.play_card(0)
		_check("打出卡后当前英雄=卡所属英雄", Game.current_hero_id() == owner,
			"owner=%s current=%s" % [owner, Game.current_hero_id()])
		_check("行动阶段", Game.state["phase"] == "hero_actions", "phase=%s" % Game.state["phase"])
	# 结束行动 → 结束回合 → 下一回合抽 1
	Game.state["phase"] = "hero_end"
	Game.autopilot = true
	await Game.end_turn()
	Game.autopilot = false
	await _wait_phase("hero_play")
	var hand3: Array = Game.state["shield_hand"]
	print("下一回合手牌=%d" % hand3.size())
	_check("回合结束进入英雄阶段", Game.state["phase"] == "hero_play", "phase=%s" % Game.state["phase"])
	if _fail == 0:
		print("=== SHIELD MODE TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== SHIELD MODE TEST FAILED ===")
		get_tree().quit(1)

func _wait_phase(p: String) -> void:
	var guard := 0
	while Game.state["phase"] != p and guard < 100:
		guard += 1
		await get_tree().process_frame

func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		_fail += 1
		print("FAIL: %s — %s" % [name, detail])
	else:
		print("PASS: %s — %s" % [name, detail])
