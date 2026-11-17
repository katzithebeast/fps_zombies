extends SceneTree
func _init():
	var world:=Node3D.new(); root.add_child(world)
	var env:=WorldEnvironment.new(); env.environment=Environment.new(); env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color(0.2,0.2,0.22); env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color=Color.WHITE; env.environment.ambient_light_energy=0.9; world.add_child(env)
	var wall:=MeshInstance3D.new(); var bm:=BoxMesh.new(); bm.size=Vector3(6,3,0.2); wall.mesh=bm; wall.position=Vector3(0,1.5,-0.1); world.add_child(wall)
	var fl:=MeshInstance3D.new(); var fm:=BoxMesh.new(); fm.size=Vector3(6,0.2,4); fl.mesh=fm; fl.position=Vector3(0,-0.1,2); world.add_child(fl)
	var B=load("res://scripts/blood_dressing.gd")
	var bd: Node3D=B.new(); world.add_child(bd)
	bd.make_decal("smears_04_gravity_drips",Vector3(-2,1.2,0),Vector3(0,0,1),0.9,0.0,0.9)
	bd.make_decal("handprints_01_full_palm_01",Vector3(-0.6,1.3,0),Vector3(0,0,1),0.3,0.0,0.9)
	bd.make_decal("splatters_05_heavy_splash",Vector3(0.8,1.0,0),Vector3(0,0,1),1.0,0.0,0.9)
	bd.make_decal("smears_05_thin_drip",Vector3(2.2,1.2,0),Vector3(0,0,1),0.8,0.0,0.9)
	bd.make_decal("smears_06_blood_pool",Vector3(0,0,1.5),Vector3.UP,1.4,0.0,0.85)
	var cam:=Camera3D.new(); world.add_child(cam); cam.current=true
	cam.look_at_from_position(Vector3(0,1.6,4.5),Vector3(0,0.9,0))
	for i in 6: await process_frame
	root.get_texture().get_image().save_png("/tmp/ws/decal.png")
	quit()
