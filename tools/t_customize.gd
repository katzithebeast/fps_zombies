extends SceneTree
## Menu Customize: snímky panelu s různými styly → /tmp/cust_<k>.png
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size=Vector2i(1440,1080)
	var main_node: Node=load("res://scripts/main.gd").new()
	var settings: Dictionary=main_node.settings.duplicate()
	main_node.free()
	var menu: CanvasLayer=load("res://scripts/menu.gd").new(settings)
	root.add_child(menu)
	await process_frame
	menu.open(false)
	menu._show_customize(true)
	var panel=menu._customize
	for k in [0,2,3,5,6]:
		panel._preset(panel.PRESETS[k])
		for i in 30: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/cust_%d.png"%k)
	print("vzhled ",panel.look())
	quit()
