extends Node
## 鲍勃威胁卡验证：英雄在鲍勃地点开始回合只获得危机，不触发奥创病毒。

func _ready() -> void:
	Game.autopilot = true
	Game.setup("redskull", ["cap"], "none")
	await Game.start_game()
	var hid := "cap"
	var loc: int = Game.state["heroes"][hid]["location"]
	Game.state["locations"][loc]["threat"] = {
		"name": "九头蛇特工鲍勃", "text": "英雄在该地点开启回合时获得 1 危机指示物",
		"henchman_hp": 4, "bam": false, "arrival": false, "start_turn": false, "constant": false,
	}
	var crisis_before: int = Game.state["heroes"][hid]["crisis"]
	Game.state["phase"] = "hero_draw"
	Game._start_hero_turn()
	var virus: bool = Game.state.get("virus_ignore", false)
	var crisis_after: int = Game.state["heroes"][hid]["crisis"]
	print("virus_ignore=%s 危机 %d->%d" % [str(virus), crisis_before, crisis_after])
	var ok: bool = not virus and crisis_after == crisis_before + 1
	if ok:
		print("=== BOB THREAT TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== BOB THREAT TEST FAILED ===")
		get_tree().quit(1)
