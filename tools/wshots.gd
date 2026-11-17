extends SceneTree
# Náhled držení zbraně. -- --name=x --aim=0 --pitch=0 --event=reload|shoot|none --times=0.5,1.0 --tp=0 --speed=0
var args:={}
func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv:=a.trim_prefix("--").split("=",true,1)
		args[kv[0]]=kv[1] if kv.size()>1 else "1"
	call_deferred("run")
func run() -> void:
	var out:="/tmp/ws"
	DirAccess.make_dir_recursive_absolute(out)
	var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color(0.16,0.18,0.2)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color(0.6,0.62,0.66)
	env.ambient_light_energy=0.9
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	var we:=WorldEnvironment.new()
	we.environment=env
	root.add_child(we)
	var sun:=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-55,150,0)
	sun.light_energy=1.6
	root.add_child(sun)
	var wall:=MeshInstance3D.new()
	var box:=BoxMesh.new()
	box.size=Vector3(8,4,0.2)
	wall.mesh=box
	wall.position=Vector3(0,1.5,-4)
	root.add_child(wall)
	var player:=Player.new()
	root.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	var body: Node3D=player.body
	body.reset(0)
	body.weapon.equipped=true
	body.weapon.set_gun(String(args.get("gun","ak")))
	var pitch:=float(args.get("pitch","0"))
	var aim:=float(args.get("aim","0"))
	var tp: bool=String(args.get("tp","0"))=="1"
	var speed:=float(args.get("speed","0"))
	var cam:=Camera3D.new()
	root.add_child(cam)
	cam.current=true
	cam.near=0.03
	var times:PackedStringArray=String(args.get("times","0.5")).split(",")
	var event: String=String(args.get("event","none"))
	var t:=-1.0
	var shot:=0
	var fired:=false
	var next_fire:=0.0
	while shot<times.size():
		body.weapon.pitch=pitch
		body.weapon.aim=aim
		body.weapon.sprint=float(args.get("sprint","0"))
		body.weapon.inspect=float(args.get("inspect","0"))
		body.weapon.melee=float(args.get("melee","0"))
		if t>=0.0 and event=="reload" and not fired:
			fired=true
			body.weapon.begin_reload()
		if t>=0.0 and event=="shoot" and t>=next_fire:
			next_fire=t+0.1
			body.weapon.kick()
		body.update_body(1.0/60,Vector3.ZERO,0,Vector3(0,0,-speed),false,false,true)
		if tp:
			cam.cull_mask=0xFFFFF & ~8
			cam.fov=55
			cam.position=Vector3(float(args.get("cx","-1.3")),1.5,float(args.get("cz","-1.6")))
			cam.look_at(Vector3(0,1.25,-0.2))
		else:
			cam.cull_mask=0xFFFFF & ~4
			cam.fov=lerpf(75,50,aim)
			cam.position=body.first_person_eye(0)
			cam.rotation=Vector3(pitch,0,0)
		if t>=float(times[shot])-0.0001:
			if body.weapon.inspect>0.5:
				var dot:=MeshInstance3D.new()
				var sm:=SphereMesh.new()
				sm.radius=0.008
				sm.height=0.016
				dot.mesh=sm
				var mm:=StandardMaterial3D.new()
				mm.albedo_color=Color(1,0,0)
				mm.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
				mm.no_depth_test=true
				dot.material_override=mm
				dot.layers=0xFFFFF
				root.add_child(dot)
				dot.global_position=body.weapon.inspect_point()
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%s_%02d_%.2f.png"%[out,args.get("name","w"),shot,t])
			shot+=1
			continue
		await process_frame
		t+=1.0/60
	quit()
