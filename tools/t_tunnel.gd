extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size=Vector2i(1280,720)
	var m=load("res://scripts/main.gd").new()
	m._make_materials()
	var env:=Environment.new(); env.background_mode=Environment.BG_COLOR; env.background_color=Color(0.0,0.0,0.0)
	env.ambient_light_color=Color(0.8,0.85,0.8); env.ambient_light_energy=0.6; env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	var we:=WorldEnvironment.new(); we.environment=env; root.add_child(we)
	var tube:=MeshInstance3D.new(); tube.mesh=m._tube_mesh(m.TUNNEL_R,4.6,13.2,64); tube.material_override=m.tile_mat
	tube.set_instance_shader_parameter("tint",Color(0.7,0.82,0.86)); tube.set_instance_shader_parameter("tile_scale",1.5); tube.set_instance_shader_parameter("mesh_uv",1.0)
	tube.position=Vector3(0,m.TUNNEL_Y,-52.0); root.add_child(tube)
	for ex in [4.6,13.2]:
		var cap:=MeshInstance3D.new(); cap.mesh=m._tube_cap(m.TUNNEL_R,1.06,-0.36-m.TUNNEL_Y,2.26-m.TUNNEL_Y,48); cap.material_override=m.tile_mat
		cap.set_instance_shader_parameter("tint",Color(0.7,0.82,0.86)); cap.set_instance_shader_parameter("tile_scale",1.5)
		cap.position=Vector3(ex,m.TUNNEL_Y,-52.0); root.add_child(cap)
	# zeď atria s obdélníkovým otvorem (z -53..-51, y -0.35..2.2)
	var wm:=StandardMaterial3D.new(); wm.albedo_color=Color(0.85,0.85,0.8)
	for b in [[Vector3(13.5,1.0,-55.0),Vector3(0.6,4,4)],[Vector3(13.5,1.0,-49.0),Vector3(0.6,4,4)],[Vector3(13.5,3.1,-52.0),Vector3(0.6,1.8,2.0)]]:
		var w:=MeshInstance3D.new(); var bm:=BoxMesh.new(); bm.size=b[1]; w.mesh=bm; w.position=b[0]; w.material_override=wm; root.add_child(w)
	var fl:=MeshInstance3D.new(); var fb:=BoxMesh.new(); fb.size=Vector3(12,0.1,4); fl.mesh=fb; fl.position=Vector3(10,-0.4,-52); fl.material_override=wm; root.add_child(fl)
	var l:=OmniLight3D.new(); l.position=Vector3(8.9,2.0,-52.0); l.omni_range=9; l.light_energy=2.0; root.add_child(l)
	var l2:=OmniLight3D.new(); l2.position=Vector3(16,2.0,-52.0); l2.omni_range=9; l2.light_energy=1.5; root.add_child(l2)
	var cam:=Camera3D.new(); root.add_child(cam); cam.current=true; cam.fov=75
	var views=[[Vector3(17.5,1.55,-52.0),Vector3(10,1.4,-52.0)],[Vector3(12.0,1.55,-52.0),Vector3(6,1.55,-52.0)],[Vector3(11.0,1.55,-52.4),Vector3(9.5,2.2,-51.6)]]
	var imgs=[]
	for v in views:
		cam.position=v[0]; cam.look_at(v[1])
		for k in 3: await RenderingServer.frame_post_draw
		imgs.append(root.get_texture().get_image())
	var out:=Image.create(1280*3,720,false,imgs[0].get_format())
	for i in 3: out.blit_rect(imgs[i],Rect2i(0,0,1280,720),Vector2i(1280*i,0))
	out.resize(1920,360)
	out.save_png("/tmp/tunnel.png")
	quit()
