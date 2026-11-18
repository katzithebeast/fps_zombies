extends SceneTree
# Úchopy zbraní zblízka: 1. osoba (kamera jako ve hře) a detaily obou rukou ze tří stran.
# Spouštění: GUNS=ak,mp40 ... (výchozí všechny). Výstup /tmp/gv_<zbraň>_<pohled>.png
var player: Player
func _initialize() -> void: call_deferred("run")
func tick(dt: float) -> void:
	player.weapon.update(dt)
	player.body.update_body(dt,Vector3.ZERO,0,Vector3.ZERO,false,false,true)
func shot(cam: Camera3D, name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(name)
func run() -> void:
	root.size=Vector2i(800,600)
	var env:=Environment.new(); env.background_mode=Environment.BG_COLOR; env.background_color=Color(0.33,0.37,0.4)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color=Color(0.75,0.78,0.82); env.ambient_light_energy=0.75
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	var we:=WorldEnvironment.new(); we.environment=env; root.add_child(we)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-45,140,0); sun.light_energy=1.1; root.add_child(sun)
	var fill:=DirectionalLight3D.new(); fill.rotation_degrees=Vector3(-20,-60,0); fill.light_energy=0.5; root.add_child(fill)
	player=Player.new(); root.add_child(player); player.set_process(false); player.set_physics_process(false)
	var cam:=Camera3D.new(); root.add_child(cam); cam.current=true; cam.near=0.02
	player.body.reset(0)
	var w: Node=player.weapon
	var rig: Node=player.body.weapon
	var guns:=OS.get_environment("GUNS").split(",") if OS.get_environment("GUNS")!="" else PackedStringArray(["ak","mp40","deagle","izh54"])
	for gun in guns:
		w.give(gun,false); w.switch_to(gun,true)
		for i in 100: tick(1.0/60.0)
		for aim in ([0.0,1.0] if OS.get_environment("AIM")!="0" else [0.0]):
			rig.aim=aim
			for i in 40:
				rig.aim=aim
				tick(1.0/60.0)
			cam.cull_mask=0xFFFFF & ~4
			cam.fov=72
			cam.global_position=player.body.first_person_eye(player.yaw)
			cam.rotation=Vector3(player.pitch,player.yaw,0)
			await shot(cam,"/tmp/gv_%s_fp%d.png"%[gun,int(aim)])
		rig.aim=0.0
		for i in 40:
			rig.aim=0.0
			tick(1.0/60.0)
		# ruce z pohledu 1. osoby (bez trupu, který by zakrýval) – stejná kostra jako ve 3. osobě
		cam.cull_mask=0xFFFFF & ~4
		cam.fov=34
		# pohledy v souřadnicích zbraně: +X pravý bok, -X levý bok, -Y zespodu, -Z zepředu
		var gx: Transform3D=rig.first.global_transform
		var gb: Basis=gx.basis.orthonormalized()
		var sock: Dictionary=rig.grip_solver.SOCKETS[gun]
		var rc: Vector3=gx*(((sock.right.a0 as Vector3)+(sock.right.a1 as Vector3))*0.5)
		var lw: Transform3D=rig._left_support.get(gun,Transform3D())
		var hl: Dictionary=rig.grip_solver.hand("Left")
		var lc: Vector3=gx*(lw*(((hl.i1 as Vector3)*0.5+(hl.palm as Vector3)*0.5)*0.86))
		var views:={"R_right":[rc,Vector3(0.26,0.03,-0.2)],"R_left":[rc,Vector3(-0.26,0.03,-0.2)],"R_under":[rc,Vector3(0.08,-0.3,-0.12)],
			"L_right":[lc,Vector3(0.32,0.02,0.0)],"L_left":[lc,Vector3(-0.32,0.02,0.0)],"L_under":[lc,Vector3(-0.06,-0.3,-0.1)],
			"top":[(rc+lc)*0.5,Vector3(0.05,0.45,0.15)]}
		for v in views:
			var c: Vector3=views[v][0]
			cam.global_position=c+gb*(views[v][1] as Vector3)
			cam.look_at(c,gb.y if v!="top" else -gb.z)
			await shot(cam,"/tmp/gv_%s_%s.png"%[gun,v])
	quit()
