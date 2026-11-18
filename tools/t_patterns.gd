extends SceneTree
## Vzory obleku v Customize (detail obleku) → /tmp/pat_<n>.png; prestižní 2× v čase (animace)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size=Vector2i(960,720)
	var main_node: Node=load("res://scripts/main.gd").new()
	var settings: Dictionary=main_node.settings.duplicate()
	main_node.free()
	var menu: CanvasLayer=load("res://scripts/menu.gd").new(settings)
	root.add_child(menu)
	await process_frame
	menu.open(false)
	menu._show_customize(true)
	var panel=menu._customize
	var part:=OS.get_environment("PART") if OS.get_environment("PART")!="" else "suit"
	if OS.get_environment("RFX")!="": panel._set_look("look_rubber_fx",int(OS.get_environment("RFX")))
	panel._select(part)
	for i in 60: await process_frame
	for pat in (OS.get_environment("PATS").split_floats(",") if OS.get_environment("PATS")!="" else [1,2,3,4,5,6,7,8,9,10,11,12]):
		pat=int(pat)
		panel._set_look("look_pattern",pat)
		for rep in (2 if pat>=7 else 1):
			for i in (20 if rep==0 else 45): await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/pat_%d_%d.png"%[pat,rep])
	quit()
