extends SceneTree
## Rozměry a náhledy modelů pokoje: --script res://tools/t_lobby_models.gd [-- --shots]
func _initialize() -> void: call_deferred("run")
func aabb_of(n: Node) -> AABB:
	var a:=AABB(); var first:=true
	for m in n.find_children("*","MeshInstance3D",true,false):
		var mi: MeshInstance3D=m
		var b: AABB=mi.global_transform*mi.get_aabb()
		if first: a=b; first=false
		else: a=a.merge(b)
	return a
func run() -> void:
	var shots:=OS.get_cmdline_user_args().has("--shots")
	var cam:=Camera3D.new(); root.add_child(cam)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-40,-30,0); root.add_child(sun)
	var env:=WorldEnvironment.new(); env.environment=Environment.new(); env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color(0.3,0.32,0.35); env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color=Color(0.6,0.6,0.6); root.add_child(env)
	for f in ["bed","crt_tv","door","drawers","multimeter","radio","sink","sofa","table"]:
		var s: PackedScene=load("res://assets/lobby/models/%s.glb"%f)
		var n: Node3D=s.instantiate(); root.add_child(n)
		await process_frame
		var a:=aabb_of(n)
		var mats:=[]
		for m in n.find_children("*","MeshInstance3D",true,false):
			var mi: MeshInstance3D=m
			for i in mi.mesh.get_surface_count():
				var mt:=mi.get_active_material(i)
				mats.append("%s:%s"%[mi.name,mt.resource_name if mt else "-"])
		print("%-10s pos %s size %s | %s"%[f,a.position.snapped(Vector3.ONE*0.01),a.size.snapped(Vector3.ONE*0.01),", ".join(mats).left(300)])
		if shots:
			var c:=a.get_center(); var r:=a.size.length()
			for k in 2:
				var dir:=Vector3(0,0.35,1).normalized() if k==0 else Vector3(1,0.35,0).normalized()
				cam.position=c+dir*r*1.25; cam.look_at(c)
				await RenderingServer.frame_post_draw; await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("/tmp/lm/%s_%d.png"%[f,k])
		n.queue_free()
		await process_frame
	quit()
