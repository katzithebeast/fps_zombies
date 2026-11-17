extends SceneTree
var main: Node3D
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	main=load("res://main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.6).timeout
	print("A");main._on_play()
	print("B")
	await create_timer(2.0).timeout
	var p: Player=main.player
	var env: Environment=main.get_viewport().world_3d.environment if main.get_viewport().world_3d.environment else null
	for we in main.find_children("*","WorldEnvironment",true,false):
		we.environment.ambient_light_energy=3.0
		we.environment.ambient_light_color=Color(1,1,1)
		we.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
		we.environment.tonemap_exposure=2.0
	var shots:=[[Vector3(-4.5,-0.35,-7.0),PI/2,0.15],[Vector3(4.0,-0.35,-10.5),PI,0.15]]
	var i:=0
	var toys: Node=null
	for n in main.get_children(): if n.has_method("shot") and n.get("_floats")!=null: toys=n
	print("toys ",toys!=null," floats ",toys._floats.size()," balls ",toys._balls.size())
	toys.shot(toys._floats[0].body,toys._floats[0].root.global_position,Vector3.FORWARD)
	print("popped dead=",toys._floats[0].dead)
	for s in shots:
		p.teleport(s[0],s[1],s[2])
		await create_timer(1.5).timeout
		root.get_texture().get_image().save_png("/tmp/ws/toy_%d.png"%i)
		i+=1
	quit()
