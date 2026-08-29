extends Node
## 自动对局：遍历日志，每次"被击倒(KO)"后应紧跟"BAM！"（同一 _ko_hero 调用内）。

var _ko_no_bam: Array = []
var _ko_count := 0

func _ready() -> void:
	Game.autopilot = true
	for villain in ["ultron", "redskull", "taskmaster"]:
		await _play(villain)
		# 每局结束分析该局日志
		var logs: Array = Game.state["log"]
		for i in range(logs.size()):
			var txt: String = str(logs[i]["t"])
			if txt.contains("被击倒"):
				_ko_count += 1
				var next_has_bam := false
				for j in range(i + 1, mini(i + 12, logs.size())):
					if str(logs[j]["t"]).contains("BAM！"):
						next_has_bam = true
						break
				if not next_has_bam:
					_ko_no_bam.append(txt)
		print("### ", villain, " 本局KO=", _ko_count, " 累积无BAM=", _ko_no_bam.size())
	print("KO总数=", _ko_count, " 无BAM的KO=", _ko_no_bam.size())
	if _ko_no_bam.size() == 0 and _ko_count > 0:
		print("=== AUTO KO-BAM TEST PASSED ===")
		get_tree().quit(0)
	elif _ko_count == 0:
		print("=== NO KO (skip) ===")
		get_tree().quit(0)
	else:
		print("=== AUTO KO-BAM TEST FAILED ===", str(_ko_no_bam))
		get_tree().quit(1)

func _play(villain: String) -> void:
	Game.setup(villain, ["cap", "ironman", "hulk"], "none")
	var guard := 0
	while Game.state["phase"] != "game_over" and guard < 600:
		guard += 1
		match Game.state["phase"]:
			"setup":
				await Game.start_game()
			"hero_play":
				var hid: String = Game.current_hero_id()
				var hand: Array = Game.state["heroes"][hid]["hand"]
				if hand.size() == 0:
					Game.state["phase"] = "hero_end"
				else:
					Game.play_card(0)
			"hero_actions":
				if Game.state.get("effect_available", false) and not Game.state.get("effect_used", false):
					await Game.trigger_effect()
				var syms: Array = Game.available_symbols()
				if syms.size() == 0:
					Game.end_actions()
				else:
					var progressed := false
					for s in syms:
						var before: int = Game.available_symbols().size()
						await Game.use_symbol(s)
						if Game.available_symbols().size() < before:
							progressed = true
							break
					if not progressed:
						Game.end_actions()
			"hero_end":
				await Game.end_turn()
			_:
				pass
		await get_tree().process_frame
