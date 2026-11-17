extends SceneTree
func _init():
	var world:=Node3D.new(); root.add_child(world)
	var env:=WorldEnvironment.new(); env.environment=Environment.new(); env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color(0.25,0.27,0.3); env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color=Color.WHITE; env.environment.ambient_light_energy=0.7; world.add_child(env)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-50,-30,0); world.add_child(sun)
	var src: Node3D=load("res://assets/props/crate/source/crate.fbx").instantiate()
	world.add_child(src)
	var mat:=StandardMaterial3D.new(); mat.albedo_texture=load("res://assets/props/crate/source/WeaponCrate_Albedo.png")
	for m in src.find_children("*","MeshInstance3D",true,false): m.material_override=mat
	var cam:=Camera3D.new(); world.add_child(cam); cam.current=true
	var views:=[Vector3(1.0,0.6,0.2),Vector3(0.05,1.2,0.01),Vector3(-0.9,0.3,0.6),Vector3(0.6,0.15,-0.9)]
	for i in views.size():
		cam.look_at_from_position(views[i],Vector3(0,0.1,0))
		for f in 4: await process_frame
		root.get_texture().get_image().save_png("/tmp/ws/cv%d.png"%i)
	quit()
