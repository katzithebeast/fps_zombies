extends SceneTree
## Balíček dat exportuje Windows preset; přibalený Godot runtime ho spouští bez instalace.
func _initialize() -> void:
	var path := "res://dist/Hladina-Multiplayer-v0.1/"
	var file := FileAccess.open(path + "GODOT-LICENSES.txt", FileAccess.WRITE)
	file.store_string(Engine.get_license_text())
	file.store_string("\n\nThird-party components\n\n")
	file.store_string(JSON.stringify(Engine.get_copyright_info(), "  "))
	var licenses := Engine.get_license_info()
	for license_name in licenses:
		file.store_string("\n\n" + str(license_name) + "\n\n" + str(licenses[license_name]))
	file.close()
	quit()
