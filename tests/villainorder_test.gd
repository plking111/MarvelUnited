extends Node
## 反派回合时序验证：移动 → BAM → 特殊效果 → 放置；
## 且移动后立即刷新（state_changed 在 BAM 之前发生，先看到移动）。

func _ready() -> void:
	Game.setup("redskull", ["cap"], "none")
	# 清空所有威胁，避免威胁 BAM 干扰
	for l in Game.state["locations"]:
		l["threat"] = null
	var vfrom: int = Game.state["villain_pos"]
	# 定制一张行动牌：move=1 + BAM + 效果(黑暗的计划) + 放置3平民
	var vill: Dictionary = DB.villain("redskull")
	vill["actions"] = [{
		"move": 1, "bam": true,
		"effect": {"type": "dark_plan", "name": "黑暗的计划", "text": "如果在反派地点没有英雄，在该地点放置 1 个危机指示物"},
		"place": [["civ"], ["civ"], ["civ"]],
	}]
	Game.state["master_deck"] = [0]
	Game.state["master_discard"] = []
	# 英雄远离反派路径，避免 BAM 伤害弹窗
	for hid in Game.state["hero_ids"]:
		var hl: int = Game.state["heroes"][hid]["location"]
		if hl == vfrom or hl == (vfrom + 1) % Game.LOCATION_COUNT:
			Game.state["heroes"][hid]["location"] = (vfrom + 2) % Game.LOCATION_COUNT
	# 记录放置前的基线（setup 会放初始指示物）
	var base_civ := 0
	for l in Game.state["locations"]:
		base_civ += l["civ"]
	print("基线civ=", base_civ)
	# 记录反派阶段内的 state_changed 快照
	var snaps: Array = []
	Events.state_changed.connect(func() -> void:
		if Game.state["phase"] == "villain":
			var tot := 0
			for l in Game.state["locations"]:
				tot += l["civ"]
			snaps.append({
				"pos": Game.state["villain_pos"],
				"crisis": Game.state["locations"][Game.state["villain_pos"]]["crisis"],
				"civ": tot,
			}))
	await Game._run_villain_turn()
	var vto: int = (vfrom + 1) % Game.LOCATION_COUNT
	var bad: Array = []
	print("快照数=%d 首快照pos=%d 目标=%d" % [snaps.size(), (snaps[0]["pos"] if snaps.size() > 0 else -1), vto])
	# 1) 移动后立即刷新：反派阶段内至少 2 次 state_changed（移动后 + 步骤间）
	if snaps.size() < 2:
		bad.append("移动后应立刻刷新（反派阶段内 state_changed=%d 次）" % snaps.size())
	# 2) 每个快照都已是新位置（移动先发生）
	for s in snaps:
		if s["pos"] != vto:
			bad.append("移动应先于其他步骤发生")
			break
	# 3) 特殊效果在放置之前：存在 crisis>=1 且 civ 仍是基线（放置未发生）的快照
	var effect_before_place := false
	for s in snaps:
		if s["crisis"] >= 1 and s["civ"] == base_civ:
			effect_before_place = true
	print("效果先于放置=", effect_before_place)
	if not effect_before_place:
		bad.append("特殊效果应发生在放置之前")
	# 4) 最终状态：效果与放置都已执行
	var final_civ := 0
	for l in Game.state["locations"]:
		final_civ += l["civ"]
	print("最终 crisis=%d civ总数=%d" % [Game.state["locations"][vto]["crisis"], final_civ])
	if Game.state["locations"][vto]["crisis"] != 1 or final_civ < base_civ + 3:
		bad.append("效果与放置都应已执行")
	if bad.is_empty():
		print("=== VILLAIN ORDER TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== VILLAIN ORDER TEST FAILED: ", bad, " ===")
		get_tree().quit(1)
