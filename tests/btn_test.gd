extends Node
func _ready() -> void:
	Game.autopilot = true
	Game.pending_setup = {"villain": "redskull", "heroes": ["cap"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	# 查找所有 Button
	for child in inst.get_children():
		if child is Button:
			print("BUTTON: ", child.text, " pos=", child.position, " visible=", child.visible, " size=", child.size)
	get_tree().quit(0)