extends Node
## 暗夜比邻星威胁 BAM：有平民→只弃置不伤害；无平民→才伤害
func _ready() -> void:
	Game.autopilot = true   # _ask/_ask_hand_cards 自动返回，避免弹窗阻塞
	Game.setup("thanos", ["cap", "ironman"], "none")
	var bad: Array = []
	# 清空所有地点的威胁，只留地点0的暗夜比邻星，避免其它威胁BAM干扰
	for i in range(Game.LOCATION_COUNT):
		Game.state["locations"][i]["threat"] = null
	for hid in ["cap", "ironman"]:
		Game.state["heroes"][hid]["hand"] = [0, 1, 2]
	Game.state["locations"][0]["threat"] = {
		"name": "暗夜比邻星", "text": "BAM：丢弃平民；若无平民则伤害1英雄",
		"hp": 4, "henchman_hp": 4, "heroic_tokens": 0, "arrival_triggered": false,
		"bam": true, "arrival": false, "start_turn": false, "constant": false,
	}
	Game.state["villain_pos"] = 0

	# 场景1：有平民 → 弃置，不伤害
	Game.state["locations"][0]["civ"] = 3
	var civ_before: int = Game.state["locations"][0]["civ"]
	await Game._trigger_all_threat_bam()
	var civ_after: int = Game.state["locations"][0]["civ"]
	print("有平民: civ %d->%d, cap手牌=%d ironman手牌=%d" % [civ_before, civ_after, Game.state["heroes"]["cap"]["hand"].size(), Game.state["heroes"]["ironman"]["hand"].size()])
	if civ_after != 0: bad.append("有平民应全弃置")
	if Game.state["heroes"]["cap"]["ko"] or Game.state["heroes"]["ironman"]["ko"]: bad.append("有平民不应伤害")
	if Game.state["heroes"]["cap"]["hand"].size() != 3 or Game.state["heroes"]["ironman"]["hand"].size() != 3: bad.append("有平民不应弃英雄手牌")

	# 场景2：无平民 → 伤害（选0号=cap）
	Game.state["locations"][0]["civ"] = 0
	for hid in ["cap", "ironman"]:
		Game.state["heroes"][hid]["hand"] = [0, 1, 2]
	await Game._trigger_all_threat_bam()
	# autopilot 下 _ask 返回0 → 选 cap 受伤(弃1张手牌)
	print("无平民: cap手牌=%d ironman手牌=%d capko=%s" % [Game.state["heroes"]["cap"]["hand"].size(), Game.state["heroes"]["ironman"]["hand"].size(), str(Game.state["heroes"]["cap"]["ko"])])
	if Game.state["heroes"]["cap"]["hand"].size() != 2: bad.append("无平民应让cap受伤(弃1手牌)")
	if Game.state["heroes"]["ironman"]["hand"].size() != 3: bad.append("无平民只应伤1名英雄")

	print("---- RESULT ----")
	if bad.is_empty():
		print("=== PROXIMA THREAT BAM PASSED ===")
		get_tree().quit(0)
	else:
		print("=== FAILED: ", bad, " ===")
		get_tree().quit(1)
