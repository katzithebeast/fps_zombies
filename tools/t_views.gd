extends SceneTree
# Snímky míst: --views=x,y,z,yaw,pitch;...  (NOANGEL=1 pro rychlost)
var main: Node3D
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	main=load("res://main.tscn").instantiate()
	root.add_child(main)
	for we in main.find_children("*","WorldEnvironment",true,false):
		var e: Environment=we.environment
		e.sdfgi_enabled=false
		e.volumetric_fog_enabled=false
		e.ssil_enabled=false
		e.ssao_enabled=false
		e.ssr_enabled=false
	RenderingServer.directional_shadow_atlas_set_size(1024,true)
	await create_timer(0.6).timeout
	main._on_play()
	await create_timer(1.0).timeout
	for we in main.find_children("*","WorldEnvironment",true,false):
		we.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
		we.environment.ambient_light_color=Color(1,1,1)
		we.environment.ambient_light_energy=float(OS.get_environment("AMB") if OS.get_environment("AMB")!="" else "1.2")
	var p: Player=main.player
	var views:=[]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--views="): views=a.substr(8).split(";")
	var i:=0
	for v in views:
		var f:=(v as String).split(",")
		p.teleport(Vector3(float(f[0]),float(f[1]),float(f[2])),float(f[3]),float(f[4]))
		await create_timer(0.8).timeout
		root.get_texture().get_image().save_png("/tmp/ws/view_%d.png"%i)
		i+=1
	quit()
