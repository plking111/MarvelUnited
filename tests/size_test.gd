extends Node
func _ready() -> void:
	Game.autopilot = true
	Game.pending_setup = {"villain": "redskull", "heroes": ["cap"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	print("BOARD size=", inst.size, " global=", inst.global_position)
	for child in inst.get_children():
		if child is Button or child is PanelContainer or child is HBoxContainer or child is ScrollContainer or child is VBoxContainer:
			print(child.get_class(), " pos=", child.position, " size=", child.size, " visible=", child.visible, " in_tree=", child.is_visible_in_tree())
	get_tree().quit(0)