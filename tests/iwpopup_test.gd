extends Node
## 验证 fill_energy_card 弹窗路径的选项过滤：要求英勇时只列英勇/万能。

var _seen_options: Array = []
var _answered_connected := false

func _ready() -> void:
	Game.autopilot = false
	Game.pending_campaign = {"game": 1, "order": ["cull", "proxima", "ebony"], "stones_collected": [], "energy_unlocked": [], "removed_energy": 6}
	Game.setup("cull", ["cap", "ironman"], "none", "iw", ["无限战争"])
	Game.state["table_energy"] = 0
	Game.state["hidden_energy"] = -1
	Game.state["campaign"]["table_energy"] = 0
	Game.state["energy_tokens"] = {"0": []}
	Game.state["phase"] = "hero_actions"
	Game.state["current_hero"] = 0
	Game.state["action_symbols"] = ["move", "attack", "heroic"]
	Game.state["prev_hero_symbols"] = []
	Game.state["used_tokens"] = {"move": 0, "attack": 0, "heroic": 0, "wild": 0}
	# 拦截弹窗选项：记录并自动选第一个
	Events.prompt_choice.connect(_on_prompt)
	_answered_connected = true
	var ok: bool = await Game.fill_energy_card(0)  # sym="" 走弹窗
	await get_tree().process_frame
	print("弹窗选项:", str(_seen_options))
	var bad: Array = []
	for o in _seen_options:
		if o.contains("移动") or o.contains("攻击"):
			bad.append(o)
	if _seen_options.size() > 0 and bad.size() == 0:
		print("=== ENERGY POPUP FILTER PASSED ===")
		get_tree().quit(0)
	else:
		print("=== ENERGY POPUP FILTER FAILED:", str(bad), " ===")
		get_tree().quit(1)

func _on_prompt(options: Array, _title: String, cb: Callable) -> void:
	_seen_options = options.duplicate()
	# 延迟应答，确保 await 先挂起
	cb.call_deferred(0)
