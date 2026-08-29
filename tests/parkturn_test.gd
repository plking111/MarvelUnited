extends Node
## 回合顺序回归：英雄触发地点结束效果（中央公园分批移动）时，
## 效果必须全部执行完才进入反派回合；效果弹窗期间不得推进回合。

func _ready() -> void:
	Game.setup("redskull", ["cap"], "none")
	# 强制中央公园在 0 号地点，放 1 平民 + 1 暴徒
	var park := 0
	Game.state["locations"][park] = {"id": "central_park", "civ": 1, "thug": 1, "crisis": 0, "threat": null, "threat_token": false}
	for i in range(1, Game.LOCATION_COUNT):
		Game.state["locations"][i]["civ"] = 0
		Game.state["locations"][i]["thug"] = 0
	Game.state["heroes"]["cap"]["location"] = park
	Game.state["heroes"]["cap"]["hand"] = [0, 1, 2]
	Game.state["phase"] = "hero_end"
	var bad: Array = []
	# 手动分步应答，验证效果进行中回合不推进
	Game.end_turn()  # fire-and-forget：跑到第一个弹窗挂起
	for i in range(3):
		await get_tree().process_frame
	print("确认弹窗 phase=", Game.state["phase"], " waiting=", Game.state.get("waiting_input", false))
	if Game.state["phase"] != "hero_end":
		bad.append("效果确认弹窗期间回合不应推进: %s" % Game.state["phase"])
	# 应答确认 → 进入第一批指示物选择
	Game._on_answer(true)
	for i in range(3):
		await get_tree().process_frame
	print("第一批弹窗 phase=", Game.state["phase"])
	if Game.state["phase"] != "hero_end":
		bad.append("中央公园效果执行中回合不应推进（反派回合提前）: %s" % Game.state["phase"])
	# 继续应答完整批次：平民→地点0 → 暴徒→地点0
	Game._on_answer(0)
	for i in range(3):
		await get_tree().process_frame
	Game._on_answer(0)
	for i in range(3):
		await get_tree().process_frame
	Game._on_answer(0)
	for i in range(3):
		await get_tree().process_frame
	Game._on_answer(0)
	for i in range(12):
		await get_tree().process_frame
	var park_left: int = Game.state["locations"][park]["civ"] + Game.state["locations"][park]["thug"]
	print("效果完成后 中央公园剩余=%d phase=%s" % [park_left, Game.state["phase"]])
	if park_left != 0:
		bad.append("中央公园效果未执行完")
	if Game.state["phase"] == "hero_end":
		bad.append("效果完成后回合应继续推进")
	if bad.is_empty():
		print("=== PARK TURN ORDER TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== PARK TURN ORDER TEST FAILED: ", bad, " ===")
		get_tree().quit(1)
