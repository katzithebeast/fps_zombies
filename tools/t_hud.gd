extends SceneTree
# Snímky HUD ze skutečné hry (softwarový render, pomalé). -- --out=/tmp/hud
func _initialize() -> void:
	call_deferred("run")
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hud/%s.png" % name)
	print("saved ",name," at ",Time.get_ticks_msec())
func frames(n: int) -> void:
	for i in n: await process_frame
func run() -> void:
	DirAccess.make_dir_recursive_absolute("/tmp/hud")
	var main: Node3D=load("res://main.tscn").instantiate()
	root.add_child(main)
	main.settings["resolution_scale"]=50
	main.apply_setting("resolution_scale")
	await frames(3)
	main.menu.close()
	main._fade_rect.color.a=0.0
	var p: Player=main.player
	p.control_enabled=true
	p.weapon.equip()
	var views:=[["start",Vector3(0,0.5,8.6),0.0],["hala",Vector3(0,-0.35,-3.2),0.0],["galerie",Vector3(-4,-0.35,-14),-PI*0.5],["satny",Vector3(3.5,0.5,5.0),-PI*0.5],["technicka",Vector3(-13.5,-0.35,-15.0),PI*0.5]]
	for view in views:
		p.teleport(view[1],view[2],0.12 if view[0]=="galerie" else -0.03)
		main.flashlight.visible=false
		await frames(14)
		await shot(view[0]+"_tma")
		main.flashlight.visible=true
		await frames(6)
		await shot(view[0]+"_svitilna")
	quit()
