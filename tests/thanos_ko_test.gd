extends Node
## 灭霸替换英雄：验证新英雄 KO 状态登场、同地点、回复活
var board: Node
var _deal_started := false
var picked_hero := ""
func _ready() -> void:
	Game.pending_setup = {
		"villain": "thanos", "heroes": ["cap", "ironman"], "challenge": "none",
		"mode": "base", "expansions": [], "debug_full_slots": false, "peek_hands": false,
	}
	var scene = load("res://src/ui/Board.tscn")
	board = scene.instantiate()
	add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame
	print("READY heroes=", Game.state["hero_ids"], " vpos=", Game.state["villain_pos"])
	# 把 cap 放到反派位置，将在 locA 受伤 KO
	var locA: int = Game.state["villain_pos"]
	Game.state["current_hero"] = 1   # ironman KO 越界还原用例
	Game.state["heroes"]["ironman"]["location"] = locA
	Game.state["heroes"]["ironman"]["hand"] = [0]
	Game.state["heroes"]["cap"]["hand"] = [0]
	Game.state["heroes"]["cap"]["location"] = 0  # cap 不动
	var bad: Array = []
	# 捕获 hero_pick 选择：选 shuri（可得其 location 校验）
	Events.prompt_hero_pick.connect(func(cb, title, options):
		picked_hero = "shuri"
		cb.call("shuri"))
	call_deferred("_start_deal")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	for i in range(40):
		await get_tree().process_frame
		var pop = board._popup
		if pop.hand_pick_panel.visible:
			pop.confirm_hand_pick()
		elif pop.hero_pick_panel.visible:
			pop._on_hero_pick_input(click, picked_hero, null)
	# 校验
	var sh: Dictionary = Game.state["heroes"]["shuri"]
	print("shuri ko=", sh["ko"], " location=", sh["location"], " hand=", sh["hand"].size(), " deck=", sh["deck"].size(), " hero_ids=", Game.state["hero_ids"])
	if not sh["ko"]: bad.append("新英雄应 KO 登场")
	if sh["location"] != locA: bad.append("新英雄应在被淘汰英雄地点登场")
	if sh["hand"].size() != 0: bad.append("新英雄 KO 登场应无手牌")
	if sh["deck"].size() != 12: bad.append("新英雄应有完整 12 张牌库")
	# 回合开始复活：抽 3(复活) + 1(回合) = 4
	Game.state["current_hero"] = Game.state["hero_ids"].find("shuri")
	Game.state["phase"] = "hero_draw"
	Game._start_hero_turn()
	var rev: Dictionary = Game.state["heroes"]["shuri"]
	print("after turn start: ko=", rev["ko"], " hand=", rev["hand"].size(), " deck=", rev["deck"].size())
	if rev["ko"]: bad.append("回合开始应复活")
	if rev["hand"].size() != 4: bad.append("复活后回合开始应有 4 张手牌")
	print("---- RESULT ----")
	if bad.is_empty():
		print("=== THANOS REPLACE RULES PASSED ===")
		get_tree().quit(0)
	else:
		print("=== FAILED: ", bad, " ===")
		get_tree().quit(1)

func _start_deal() -> void:
	if _deal_started:
		return
	_deal_started = true
	await Game._deal_damage_to_hero("ironman", 99)
	print("deal done")
