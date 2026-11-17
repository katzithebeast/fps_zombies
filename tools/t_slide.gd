extends SceneTree
func _init():
	var world:=Node3D.new(); root.add_child(world)
	var env:=WorldEnvironment.new(); env.environment=Environment.new(); env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color(0.25,0.27,0.3); env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color=Color.WHITE; env.environment.ambient_light_energy=0.5; world.add_child(env)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-50,-30,0); world.add_child(sun)
	var T=load("res://scripts/pool_toys.gd")
	var toys: Node3D=T.new()
	world.add_child(toys)
	var spec: Dictionary=T.SLIDES[0]
	var pts: Array=T._spiral(spec.entry,spec.inward,spec.center,spec.radius,spec.top,spec.bottom,spec.turns,spec.exit)
	toys._make_slide(pts)
	var end: Vector3=pts[pts.size()-1]
	var cam:=Camera3D.new(); world.add_child(cam); cam.current=true
	var views:=[[end+Vector3(1.8,0.6,0.4),end],[Vector3(-5,2.5,-4),Vector3(-10,1.8,-8)]]
	for i in 2:
		cam.look_at_from_position(views[i][0],views[i][1])
		for f in 6: await process_frame
		root.get_texture().get_image().save_png("/tmp/ws/sl%d.png"%i)
	quit()
