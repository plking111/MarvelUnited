extends Node
## 验证奥创「脑袋视线」：带危机的英雄受 1 点伤害（弃1张手牌）+ 玩家选择一名英雄获得危机。

var _got_opts: Array = []
var _got_title := ""

func _ready() -> void:
	Game.pending_setup = {"villain": "ultron", "heroes": ["cap", "ironman", "hulk"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	var st: Dictionary = Game.state
	# 给每人发 3 张手牌（避免 KO）
	for hid in ["cap", "ironman", "hulk"]:
		st["heroes"][hid]["hand"] = [0, 1, 2]
	# ---- 阶段 1：autopilot（_ask 返回 0 → 第一个候选 cap）----
	st["heroes"]["cap"]["crisis"] = 2
	st["heroes"]["ironman"]["crisis"] = 1
	st["heroes"]["hulk"]["crisis"] = 0
	Game.autopilot = true
	await Game._resolve_villain_effect({"type": "head_case", "name": "脑袋视线", "text": ""})
	var ok1: bool = st["heroes"]["cap"]["hand"].size() == 2
	var ok2: bool = st["heroes"]["ironman"]["hand"].size() == 2
	var ok3: bool = st["heroes"]["hulk"]["hand"].size() == 3
	var ok4: bool = st["heroes"]["cap"]["crisis"] == 3 and st["heroes"]["ironman"]["crisis"] == 1 and st["heroes"]["hulk"]["crisis"] == 0
	print("阶段1: cap手牌=", st["heroes"]["cap"]["hand"].size(), " iron=", st["heroes"]["ironman"]["hand"].size(), " hulk=", st["heroes"]["hulk"]["hand"].size())
	print("阶段1: cap危机=", st["heroes"]["cap"]["crisis"], " iron=", st["heroes"]["ironman"]["crisis"], " hulk=", st["heroes"]["hulk"]["crisis"])
	# ---- 阶段 2：验证 prompt_choice 携带全部未KO英雄选项 ----
	Game.autopilot = false
	st["heroes"]["cap"]["crisis"] = 1
	st["heroes"]["ironman"]["crisis"] = 0
	st["heroes"]["hulk"]["crisis"] = 0
	st["heroes"]["cap"]["hand"] = [0, 1, 2]
	st["heroes"]["ironman"]["hand"] = [0, 1, 2]
	st["heroes"]["hulk"]["hand"] = [0, 1, 2]
	var got_opts: Array = []
	var got_title := ""
	# 监听：手牌选择应答弃最后一张；选择英雄时记录选项并应答选 hulk(2)
	# 注意：信号同步触发，须延迟应答（emit 后 _ask 才 await）
	var cb_hand := func(_cb: Callable, _title: String, _hid: String, _cnt: int) -> void:
		print("   [hand信号] hid=", _hid, " cnt=", _cnt, " hand_size=", Game.state["heroes"][_hid]["hand"].size())
		Game._on_hand_answered.call_deferred([Game.state["heroes"][_hid]["hand"].size() - 1])
	var cb_choice := func(opts: Array, title: String, _c: Callable) -> void:
		print("   [choice信号] opts=", str(opts))
		_got_opts = opts.duplicate()
		_got_title = title
		Game._on_answer.call_deferred(2)
	Events.prompt_hand_card.connect(cb_hand)
	Events.prompt_choice.connect(cb_choice)
	await Game._resolve_villain_effect({"type": "head_case", "name": "脑袋视线", "text": ""})
	Events.prompt_hand_card.disconnect(cb_hand)
	Events.prompt_choice.disconnect(cb_choice)
	await get_tree().process_frame  # 等待 deferred 应答落地
	var ok5: bool = st["heroes"]["hulk"]["crisis"] == 1 and st["heroes"]["cap"]["crisis"] == 1 and st["heroes"]["ironman"]["crisis"] == 0
	var ok6: bool = _got_opts.size() == 3 and _got_title.contains("危机")
	print("阶段2: cap危机=", st["heroes"]["cap"]["crisis"], " iron=", st["heroes"]["ironman"]["crisis"], " hulk=", st["heroes"]["hulk"]["crisis"])
	print("阶段2: 选项=", str(_got_opts), " 标题=", _got_title)
	if ok1 and ok2 and ok3 and ok4 and ok5 and ok6:
		print("=== HEAD CASE TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== HEAD CASE TEST FAILED ===", [ok1, ok2, ok3, ok4, ok5, ok6])
		get_tree().quit(1)
