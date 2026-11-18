extends SceneTree
## Paže a zápěstí při držení: 1. osoba (jako ve hře) a 3. osoba zboku / zepředu.
## GUNS=ak,... → /tmp/arms_<zbraň>_<pohled>.png
var player: Player
func _initialize() -> void: call_deferred("run")
func tick(dt: float) -> void:
	player.weapon.update(dt)
	if OS.get_environment("INS")!="": player.body.weapon.inspect=float(OS.get_environment("INS"))
	player.body.update_body(dt,Vector3.ZERO,0,Vector3.ZERO,false,false,true)
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(name)
func run() -> void:
	root.size=Vector2i(800,450)
	var env:=Environment.new(); env.background_mode=Environment.BG_COLOR; env.background_color=Color(0.33,0.37,0.4)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color=Color(0.75,0.78,0.82); env.ambient_light_energy=0.75
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	var we:=WorldEnvironment.new(); we.environment=env; root.add_child(we)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-45,140,0); sun.light_energy=1.1; root.add_child(sun)
	var fill:=DirectionalLight3D.new(); fill.rotation_degrees=Vector3(-20,-60,0); fill.light_energy=0.5; root.add_child(fill)
	player=Player.new(); root.add_child(player); player.set_process(false); player.set_physics_process(false)
	var cam:=Camera3D.new(); root.add_child(cam); cam.current=true; cam.near=0.02
	player.body.reset(0)
	var rig: Node=player.body.weapon
	# ladění: CT/CF klíční kosti, EA automatický loket, FT podíl zkrutu v předloktí, PITCH pohled
	if OS.get_environment("CT")!="": rig.CLAV_R_TP=str_to_var(OS.get_environment("CT"))
	if OS.get_environment("CF")!="": rig.CLAV_R_FP=str_to_var(OS.get_environment("CF"))
	if OS.get_environment("EA")!="": rig.ELBOW_AUTO=float(OS.get_environment("EA"))
	if OS.get_environment("FT")!="": rig.FOREARM_TWIST=float(OS.get_environment("FT"))
	if OS.get_environment("UT")!="": rig.UPPER_TWIST=float(OS.get_environment("UT"))
	player.pitch=float(OS.get_environment("PITCH")) if OS.get_environment("PITCH")!="" else -0.3
	var tag:=OS.get_environment("TAG")
	var guns:=OS.get_environment("GUNS").split(",") if OS.get_environment("GUNS")!="" else PackedStringArray(["ak","mp40","deagle","izh54"])
	for gun in guns:
		player.weapon.give(gun,false); player.weapon.switch_to(gun,true)
		for i in 120: tick(1.0/60.0)
		cam.cull_mask=0xFFFFF & ~4
		cam.fov=75
		cam.global_position=player.body.first_person_eye(player.yaw)
		cam.rotation=Vector3(player.pitch,player.yaw,0)
		cam.rotation=Vector3(player.pitch,player.yaw,0)
		await shot("/tmp/arms_%s%s_fp.png"%[gun,tag])
		# detail obou zápěstí z místa oka (užší objektiv)
		var fs: Skeleton3D=rig.avatar.first_skeleton
		var rw: Vector3=fs.global_transform*fs.get_bone_global_pose(fs.find_bone("mixamorig_RightHand")).origin
		var lw: Vector3=fs.global_transform*fs.get_bone_global_pose(fs.find_bone("mixamorig_LeftHand")).origin
		var eye: Vector3=player.body.first_person_eye(player.yaw)
		var mb: Basis=rig.avatar.model.global_transform.basis.orthonormalized()
		cam.fov=40
		for hw in [["fpR",rw,Vector3(-0.12,0.1,0.02)],["fpL",lw,Vector3(0.1,0.12,-0.02)]]:
			var c: Vector3=hw[1]
			cam.global_position=c+(eye-c).normalized()*0.3+mb*(hw[2] as Vector3)
			cam.look_at(c,Vector3.UP)
			await shot("/tmp/arms_%s%s_%s.png"%[gun,tag,hw[0]])
		cam.cull_mask=0xFFFFF & ~8
		cam.fov=35
		var mt: Transform3D=rig.avatar.model.global_transform
		var sk: Skeleton3D=rig.avatar.skeleton
		var mb2: Basis=mt.basis.orthonormalized()
		var rwt: Vector3=sk.global_transform*sk.get_bone_global_pose(sk.find_bone("mixamorig_RightHand")).origin
		var lwt: Vector3=sk.global_transform*sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftHand")).origin
		cam.fov=30
		var lel: Vector3=sk.global_transform*sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftForeArm")).origin
		var rel_: Vector3=sk.global_transform*sk.get_bone_global_pose(sk.find_bone("mixamorig_RightForeArm")).origin
		for wv in [["wR1",rwt,Vector3(-0.32,0.1,0.06)],["wR2",rwt,Vector3(-0.2,-0.28,0.12)],["wL1",lwt,Vector3(0.32,0.08,0.0)],["wL2",lwt,Vector3(0.15,-0.3,0.05)],["eL",lel,Vector3(0.4,-0.05,0.1)],["eR",rel_,Vector3(-0.4,-0.05,0.1)]]:
			cam.global_position=(wv[1] as Vector3)+mb2*(wv[2] as Vector3)
			cam.look_at(wv[1],Vector3.UP)
			await shot("/tmp/arms_%s%s_%s.png"%[gun,tag,wv[0]])
		cam.fov=35
		for v in [["side",Vector3(-1.6,1.45,0.35)],["front",Vector3(-0.5,1.5,1.7)],["top",Vector3(-0.35,2.6,0.6)]]:
			cam.global_position=mt*(v[1] as Vector3)
			cam.look_at(mt*Vector3(-0.05,1.32,0.2),Vector3.UP if v[0]!="top" else (mt.basis*Vector3.BACK))
			await shot("/tmp/arms_%s%s_%s.png"%[gun,tag,v[0]])
	quit()
