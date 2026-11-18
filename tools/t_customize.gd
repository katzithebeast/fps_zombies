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
	for i in 40: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/cust_0.png")
	# najetí na oblek (rozvinutá čára)
	panel._hover="suit"
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/cust_1.png")
	var shots:=[["suit",7],["suit",9],["suit",10],["suit",12],["visor",-1],["gloves",-1],["suit",11],["suit",8],["boots",-1]]
	var k:=2
	for sh in shots:
		if sh[1]>=0: panel._set_look("look_pattern",sh[1])
		panel._select(sh[0])
		for i in 70: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/cust_%d.png"%k)
		k+=1
	panel._select("")
	for i in 70: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/cust_%d.png"%k)
	print("vzhled ",panel.look())
	quit()
