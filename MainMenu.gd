extends Control

func _process(delta):
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	if Input.is_action_just_pressed("exit"):
		get_tree().quit()
	if Input.is_action_just_pressed("drink_potion"):
		get_tree().change_scene("res://World.tscn")
