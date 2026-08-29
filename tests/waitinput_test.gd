extends Node
## 等待输入机制验证（bug3/bug5）：
## 行动弹窗打开时 waiting_input=true 且行动按钮隐藏（防并发覆盖）；
## 行动完成后恢复。

func _ready() -> void:
	Game.pending_setup = {"villain": "ultron", "heroes": ["cap"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	for i in range(10):
		await get_tree().process_frame
	var hid := "cap"
	var loc: int = Game.state["heroes"][hid]["location"]
	Game.state["locations"][loc]["thug"] = 1
	Game.state["heroes"][hid]["hand"] = [0, 1, 2]
	Game.state["phase"] = "hero_actions"
	# 2 个攻击符号：用完 1 个后仍有 1 个剩余，不会触发自动结束回合
	Game.state["action_symbols"] = ["attack", "attack"]
	inst._refresh_all()
	var before: int = inst._action_box.get_child_count()
	print("行动前按钮数=", before)
	Events.prompt_choice.connect(func(options: Array, title: String, cb: Callable) -> void:
		Game._on_answer.call_deferred(0))
	var bad: Array = []
	Game.use_symbol("attack")
	# use_symbol 的同步段内已进入 _ask → begin_wait，且 Board 同步刷新隐藏按钮
	var waiting: bool = Game.state.get("waiting_input", false)
	var hidden: bool = inst._action_box.get_child_count() == 0
	print("弹窗打开时 waiting=", waiting, " 行动按钮隐藏=", hidden)
	if not waiting:
		bad.append("弹窗打开时应 waiting_input=true")
	if not hidden:
		bad.append("等待输入时行动按钮应隐藏")
	for i in range(8):
		await get_tree().process_frame
	var waiting2: bool = Game.state.get("waiting_input", false)
	var after: int = inst._action_box.get_child_count()
	print("执行后 waiting=", waiting2, " 按钮数=", after)
	if waiting2:
		bad.append("行动完成后 waiting_input 应恢复 false")
	if after == 0:
		bad.append("行动完成后行动按钮应恢复显示")
	if bad.is_empty():
		print("=== WAIT INPUT TEST PASSED ===")
		get_tree().quit(0)
	else:
		print("=== WAIT INPUT TEST FAILED: ", bad, " ===")
		get_tree().quit(1)
