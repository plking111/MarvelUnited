extends Control
func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	print("PHYS_WIN: ", DisplayServer.window_get_size())
	print("LOGIC_VIEW: ", get_viewport().get_visible_rect().size)
	var st := get_viewport().get_screen_transform()
	print("SCREEN_T: origin=", st.origin, " x=", st.x, " y=", st.y)
	print("MAP(1760,12): ", st * Vector2(1760, 12))
	print("MAP(1000,500): ", st * Vector2(1000, 500))
	get_tree().quit(0)