extends SceneTree
func _init():
	var world:=Node3D.new(); root.add_child(world)
	var env:=WorldEnvironment.new(); env.environment=Environment.new(); env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color(0.25,0.27,0.3); env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color=Color.WHITE; env.environment.ambient_light_energy=0.6; world.add_child(env)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-40,-60,0); world.add_child(sun)
	var a: Node3D=load("res://scripts/props.gd").angel(17.8)
	world.add_child(a)
	a.position=Vector3(0,-14.4,0)
	a.rotation.y=-PI/2
	var water:=MeshInstance3D.new(); var pm:=PlaneMesh.new(); pm.size=Vector2(15,18); water.mesh=pm
	var wm:=StandardMaterial3D.new(); wm.albedo_color=Color(0.1,0.3,0.35,0.7); wm.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; water.material_override=wm; world.add_child(water)
	var cam:=Camera3D.new(); world.add_child(cam); cam.current=true
	var views:=[[Vector3(-12,2.0,0),Vector3(0,1.5,0)],[Vector3(0,3,-14),Vector3(0,0,0)]]
	for i in 2:
		cam.look_at_from_position(views[i][0],views[i][1])
		for f in 6: await process_frame
		root.get_texture().get_image().save_png("/tmp/ws/an%d.png"%i)
	quit()
