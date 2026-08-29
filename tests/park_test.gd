extends Node
## 中央公园分批次移动验证：
## 每批 = 选 1 个指示物（平民/暴徒任意组合）→ 选 1 个任意有空位的地点；
## 共 2 批，可提前结束；指示物总数守恒。

var _queue: Array = []

func _ready() -> void:
	Game.setup("redskull", ["cap"], "none")
	# 强制把中央公园放进游戏（setup 是随机取 6 个地点）：替换 0 号地点
	var park := 0
	Game.state["locations"][park] = {"id": "central_park", "civ": 0, "thug": 0, "crisis": 0, "threat": null, "threat_token": false}
	# 清空其他地点（保证有空位）；中央公园放 1 平民 + 1 暴徒
	for i in range(Game.LOCATION_COUNT):
		if i != park:
			Game.state["locations"][i]["civ"] = 0
			Game.state["locations"][i]["thug"] = 0
	Game.state["locations"][park]["civ"] = 1
	Game.state["locations"][park]["thug"] = 1
	Game.state["heroes"]["cap"]["location"] = park
	Game.state["phase"] = "hero_end"
	# 应答队列：确认(是) → 平民(索引0) → 地点0 → 暴徒(此时只剩暴徒,索引0) → 地点0
	_queue = [true, 0, 0, 0, 0]
	Events.prompt_confirm.connect(_on_confirm)
	Events.prompt_choice.connect(_on_choice)
	await Game._resolve_location_end_effect("cap", park)
	for i in range(5):
		await get_tree().process_frame
	var bad: Array = []
	var park_tokens: int = Game.state["locations"][park]["civ"] + Game.state["locations"][park]["thug"]
	var total := 0
	for l in Game.state["locations"]:
		total += l["civ"] + l["thug"]
	print("中央公园剩余=%d 总指示物=%d 队列剩余=%s" % [park_tokens, total, str(_queue)])
	if park_tokens != 0:
		bad.append("中央公园应移走全部 2 个指示物（剩余 %d）" % park_tokens)
	if total != 2:
		bad.append("指示物总数应守恒为 2（实际 %d）" % total)
	if _queue.size() != 0:
		bad.append("应答队列未消费完（可能少执行了批次）")
	if bad.is_empty():
		print("=== PARK MOVE TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== PARK MOVE TEST FAILED: ", bad, " ===")
		get_tree().quit(1)

func _on_confirm(text: String, cb: Callable) -> void:
	if _queue.size() > 0:
		var a: Variant = _queue.pop_front()
		Game._on_answer.call_deferred(a)

func _on_choice(options: Array, title: String, cb: Callable) -> void:
	if _queue.size() > 0:
		var a: Variant = _queue.pop_front()
		Game._on_answer.call_deferred(a)
