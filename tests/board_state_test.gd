extends Node
func _ready() -> void:
	Game.autopilot = true
	Game.pending_setup = {"villain": "redskull", "heroes": ["cap"], "challenge": "none"}
	var board: PackedScene = load("res://src/ui/Board.tscn")
	var inst: Control = board.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	print("icon_civ = ", inst._icon_civ)
	print("icon_thug = ", inst._icon_thug)
	print("icon_crisis = ", inst._icon_crisis)
	print("mission_rescue = ", inst._mission_textures.get("rescue"))
	var loc0: LocationView = inst._loc_views[0]
	print("loc0 slots:", loc0.slots.size(), " first icon texture=", loc0.slots[0]["icon"].texture, " visible=", loc0.slots[0]["icon"].visible)
	get_tree().quit(0)