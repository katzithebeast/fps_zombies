extends SceneTree
# Render efektu zásahu do zdi (spouštět s --fixed-fps 60): snímky v čase po zásahu.
func _initialize() -> void: call_deferred("run")
func boxm(pos: Vector3, size: Vector3, col: Color) -> void:
	var b:=StaticBody3D.new(); var c:=CollisionShape3D.new(); var sh:=BoxShape3D.new(); sh.size=size; c.shape=sh; b.add_child(c)
	var mi:=MeshInstance3D.new(); var bm:=BoxMesh.new(); bm.size=size; mi.mesh=bm
	var m:=StandardMaterial3D.new(); m.albedo_color=col; m.roughness=0.25; mi.material_override=m; b.add_child(mi)
	b.position=pos; root.add_child(b)
func run() -> void:
	root.size=Vector2i(960,540)
	var we:=WorldEnvironment.new(); var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR; env.background_color=Color(0.05,0.06,0.07)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color=Color(0.35,0.4,0.42); env.ambient_light_energy=0.5
	env.glow_enabled=true; env.tonemap_mode=Environment.TONE_MAPPER_ACES
	we.environment=env; root.add_child(we)
	boxm(Vector3(0,-0.25,0),Vector3(8,0.5,8),Color(0.55,0.62,0.6))
	boxm(Vector3(0,1.5,-1.6),Vector3(8,3,0.3),Color(0.62,0.72,0.7))
	var l:=OmniLight3D.new(); l.position=Vector3(0.8,2.2,0.2); l.omni_range=6; l.light_energy=1.6; l.shadow_enabled=true; root.add_child(l)
	var cam:=Camera3D.new(); root.add_child(cam); cam.position=Vector3(0.55,1.25,-0.15); cam.look_at(Vector3(0,1.05,-1.45)); cam.current=true; cam.fov=60
	seed(5)
	var fx=load("res://scripts/combat_fx.gd").new(); root.add_child(fx); fx.water_y=-10.0
	await process_frame
	# pár starších děr
	for p in [Vector3(-0.35,1.3,-1.45),Vector3(0.3,0.75,-1.45),Vector3(-0.15,0.55,-1.45)]: fx.hole(p,Vector3(0,0,1))
	for k in 3: await process_frame
	var hit:=Vector3(0.0,1.05,-1.45)
	fx.shot(Vector3(2.0,1.4,3.0),hit,true,Vector3(0,0,1),"tile")
	fx.hole(hit,Vector3(0,0,1))
	var shots:={1:"a",4:"b",12:"c",30:"d",70:"e"}
	for f in 71:
		await RenderingServer.frame_post_draw
		if shots.has(f): root.get_texture().get_image().save_png("/tmp/imp_%s.png"%shots[f])
	quit()
