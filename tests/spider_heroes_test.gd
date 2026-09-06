extends Node
## 蜘蛛侠扩4英雄接入+效果冒烟验证：
## - heroes.json 含 20 英雄、4个蜘蛛侠英雄各12卡
## - 若干无需弹窗的效果正确触发（web_shoot/acrobatic_fight/invisibility/cartoon_web/miles_web）

var _fail := 0

func _ready() -> void:
	await _test_data_load()
	await _test_effects()
	if _fail == 0:
		print("=== SPIDER HEROES TEST ALL PASSED ===")
		get_tree().quit(0)
	else:
		print("=== SPIDER HEROES TEST FAILED (%d) ===" % _fail)
		get_tree().quit(1)

func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		_fail += 1
		print("FAIL: %s — %s" % [name, detail])
	else:
		print("PASS: %s — %s" % [name, detail])

func _test_data_load() -> void:
	_check("英雄总数=20", DB.heroes.size() == 20, "size=%d" % DB.heroes.size())
	for h in ["spiderman", "miles", "gwenspider", "spiderpig"]:
		_check("英雄 %s 有12卡" % h, DB.hero_cards(h).size() == 12, "cards=%d" % DB.hero_cards(h).size())

func _test_effects() -> void:
	# 用蜘蛛侠设局
	Game.autopilot = true
	Game.setup("redskull", ["spiderman", "miles", "gwenspider", "spiderpig"], "none")
	await Game.start_game()
	var guard := 0
	while Game.state["phase"] != "hero_play" and guard < 300:
		guard += 1
		await get_tree().process_frame
	Game.autopilot = false

	# web_shoot：蜘蛛侠获得2移动指示物
	Game.state["current_hero"] = Game.state["hero_ids"].find("spiderman")
	Game.state["phase"] = "hero_actions"
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	Game.state["played_effect"] = {"type": "web_shoot", "name": "蛛网喷射"}
	Game.state["action_symbols"] = ["move"]
	var b_move: int = Game.state["heroes"]["spiderman"]["tokens"]["move"]
	await Game.trigger_effect()
	_check("web_shoot +2移动指示物", Game.state["heroes"]["spiderman"]["tokens"]["move"] == b_move + 2,
		"move %d->%d" % [b_move, Game.state["heroes"]["spiderman"]["tokens"]["move"]])

	# acrobatic_fight：格温蛛击败所在地点所有暴徒
	var g_loc: int = Game.state["heroes"]["gwenspider"]["location"]
	Game.state["current_hero"] = Game.state["hero_ids"].find("gwenspider")
	Game.state["phase"] = "hero_actions"
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	Game.state["played_effect"] = {"type": "acrobatic_fight", "name": "杂技格斗"}
	Game.state["action_symbols"] = ["attack"]
	Game.state["locations"][g_loc]["thug"] = 3
	await Game.trigger_effect()
	_check("acrobatic_fight 击败所有暴徒", Game.state["locations"][g_loc]["thug"] == 0,
		"thug=%d" % Game.state["locations"][g_loc]["thug"])

	# invisibility：迈尔斯无敌
	Game.state["current_hero"] = Game.state["hero_ids"].find("miles")
	Game.state["phase"] = "hero_actions"
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	Game.state["played_effect"] = {"type": "invisibility", "name": "隐形"}
	Game.state["action_symbols"] = ["heroic"]
	await Game.trigger_effect()
	_check("invisibility 设置无敌", Game.state["heroes"]["miles"]["invulnerable"] == true,
		"invulnerable=%s" % str(Game.state["heroes"]["miles"]["invulnerable"]))

	# cartoon_web：蜘猪侠→下一反派行动不移动
	Game.state["current_hero"] = Game.state["hero_ids"].find("spiderpig")
	Game.state["phase"] = "hero_actions"
	Game.state["effect_available"] = true
	Game.state["effect_used"] = false
	Game.state["played_effect"] = {"type": "cartoon_web", "name": "卡通蛛网"}
	Game.state["action_symbols"] = ["move"]
	await Game.trigger_effect()
	_check("cartoon_web 标记待触发(被动)", Game.state["heroes"]["spiderpig"].get("cartoon_web_armed", false) == true,
		"armed=%s" % str(Game.state["heroes"]["spiderpig"].get("cartoon_web_armed", false)))
