extends SceneTree
# Render scénáře do PNG. Použití: --script res://tools/zshots.gd -- --name=chest3 --bone=Spine2 --hits=0,0.25,0.5 --dir=1 --times=0,0.1,... --out=/tmp/zs --side=1
var args:={}
func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv:=a.trim_prefix("--").split("=",true,1)
		args[kv[0]]=kv[1] if kv.size()>1 else "1"
	call_deferred("run")
func run() -> void:
	var out:String=args.get("out","/tmp/zs")
	DirAccess.make_dir_recursive_absolute(out)
	var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color(0.18,0.2,0.22)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color(0.55,0.58,0.62)
	env.ambient_light_energy=0.8
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	var we:=WorldEnvironment.new()
	we.environment=env
	root.add_child(we)
	var sun:=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-50,-30,0)
	sun.light_energy=2.0
	sun.shadow_enabled=true
	root.add_child(sun)
	var fb:=StaticBody3D.new()
	var sh:=BoxShape3D.new()
	sh.size=Vector3(30,0.5,30)
	var cs:=CollisionShape3D.new()
	cs.shape=sh
	fb.add_child(cs)
	var plane:=MeshInstance3D.new()
	var pm:=PlaneMesh.new()
	pm.size=Vector2(30,30)
	plane.mesh=pm
	var pmat:=StandardMaterial3D.new()
	pmat.albedo_color=Color(0.35,0.37,0.38)
	plane.material_override=pmat
	plane.position.y=0.25
	fb.add_child(plane)
	root.add_child(fb)
	fb.position.y=-0.25
	var cam:=Camera3D.new()
	cam.fov=50
	root.add_child(cam)
	var side:=float(args.get("side","1"))
	cam.position=Vector3(3.9*side,2.3,2.4)
	cam.look_at(Vector3(0,0.55,-0.2))
	cam.current=true
	var back:=StaticBody3D.new()
	var back_shape:=BoxShape3D.new()
	back_shape.size=Vector3(6,3,0.2)
	var back_col:=CollisionShape3D.new()
	back_col.shape=back_shape
	back.add_child(back_col)
	var back_mesh:=MeshInstance3D.new()
	var back_box:=BoxMesh.new()
	back_box.size=back_shape.size
	back_mesh.mesh=back_box
	back_mesh.material_override=pmat
	back.add_child(back_mesh)
	back.position=Vector3(0,1.5,-1.6)
	if args.has("wall"): root.add_child(back)
	var fx: Node3D=preload("res://scripts/combat_fx.gd").new()
	root.add_child(fx)
	var zs: GDScript=load("res://scripts/zombie.gd")
	zs.fx=fx
	zs.water_level=float(args.get("water","-50"))
	if args.has("cam"):
		var c:PackedStringArray=String(args["cam"]).split(",")
		cam.position=Vector3(float(c[0]),float(c[1]),float(c[2]))
		cam.look_at(Vector3(float(c[3]),float(c[4]),float(c[5])))
		cam.fov=float(c[6]) if c.size()>6 else 50.0
	var z: Node3D=preload("res://scripts/zombie.gd").new()
	z.died.connect(func(_a,_b,_c): fx.pool(z))
	if args.has("hp"): z.max_health=float(args["hp"]); z.health=z.max_health
	if args.has("kind"): z.kind=String(args["kind"])
	if args.has("yaw"): z.rotation.y=deg_to_rad(float(args["yaw"]))
	root.add_child(z)
	# --lie: leží jako mrtvola (--push=x,y,z = kam se skácí), --wake=T: v čase T vstane
	if args.has("lie"):
		z.lie_down()
		if args.has("push"):
			var pv:PackedStringArray=String(args["push"]).split(",")
			for b in z.bodies.values(): (b as PhysicalBone3D).linear_velocity=Vector3(float(pv[0]),float(pv[1]),float(pv[2]))
	if args.has("ai"):
		var goal:=Node3D.new()
		root.add_child(goal)
		goal.position=Vector3(0,0,float(args.get("goal","6")))
		z.position=Vector3(0,0,-2.5)
		z.target=goal
		z.tier=String(args.get("tier","walk"))
		z.alert(args.has("scream"))
	await create_timer(0.4).timeout
	var hits:PackedStringArray=String(args.get("hits","99")).split(",")
	var times:PackedStringArray=String(args.get("times","0,0.2,0.4,0.6,0.8,1.0,1.3,1.7,2.2,3.0")).split(",")
	var bone:int=z.skeleton.find_bone("mixamorig_"+String(args.get("bone","Spine2")))
	var dirn:=Vector3.FORWARD*float(args.get("dir","1"))
	if args.has("dirv"):
		var dv:PackedStringArray=String(args["dirv"]).split(",")
		dirn=Vector3(float(dv[0]),float(dv[1]),float(dv[2])).normalized()
	if args.has("nokd"): z.knockdowns=false
	if args.has("noda"): z.death_anims=false
	if args.has("feed"): z.feed()
	if args.has("atk"): z.force_attack=String(args["atk"])
	if args.has("death"): z.force_death=String(args["death"])
	var t:=0.0
	var next_hit:=0
	var next_shot:=0
	var steps:=0
	var last:=float(times[times.size()-1])
	var wake_at:=float(args.get("wake","-1"))
	while next_shot<times.size():
		if wake_at>=0.0 and t>=wake_at:
			wake_at=-1.0
			z.wake()
		while next_hit<hits.size() and t>=float(hits[next_hit])-0.0001:
			if args.has("bones"): bone=z.skeleton.find_bone("mixamorig_"+String(args["bones"]).split(",")[next_hit])
			var p:Vector3=z.skeleton.global_transform*z.bone_pose(bone).origin
			z.hit(bone,p-dirn*0.1,dirn,float(args.get("str","1.0")),float(args.get("dmg","50")))
			fx.blood(p,dirn,z.dead or z._death_pending)
			next_hit+=1
		if t>=float(times[next_shot])-0.0001:
			if args.has("follow"):
				# --follow=x,y,z: kamera v tomto odstupu od kořene zombie, míří na kořen
				var fo:PackedStringArray=String(args["follow"]).split(",")
				var at:Vector3=z.global_position+Vector3(0,0.45,0)
				cam.global_position=at+Vector3(float(fo[0]),float(fo[1]),float(fo[2]))
				cam.look_at(at)
			z.set_physics_process(false)
			PhysicsServer3D.set_active(false)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img:=root.get_texture().get_image()
			img.save_png("%s/%s_%02d_%.2f.png"%[out,args.get("name","x"),next_shot,t])
			PhysicsServer3D.set_active(true)
			z.set_physics_process(true)
			next_shot+=1
			continue
		await physics_frame
		t+=1.0/60.0
	quit()
