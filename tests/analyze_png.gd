extends Node
func _ready() -> void:
	Game.autopilot = true
	Game.setup("redskull", ["cap", "ironman"], "none")
	Game.state["story"] = [
		{"type": "hero", "hero": "cap", "idx": 0},
		{"type": "hero", "hero": "ironman", "idx": 1},
		{"type": "hero", "hero": "cap", "idx": 2},
	]
	# 过滤 cap：应返回最后一个 cap 的索引（2）
	var di: int = await Game._ask_story_card("test", "cap")
	print("cap 过滤返回索引=", di, "（应=2，ironman 的1被过滤）")
	# 不过滤：返回最后一个（cap 的2）
	var di2: int = await Game._ask_story_card("test")
	print("不过滤返回索引=", di2, "（应=2）")
	# 过滤 ironman：应返回 1
	var di3: int = await Game._ask_story_card("test", "ironman")
	print("ironman 过滤返回索引=", di3, "（应=1）")
	var ok: bool = di == 2 and di2 == 2 and di3 == 1
	get_tree().quit(0 if ok else 1)