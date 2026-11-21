extends SceneTree
## Kontrola nábojů (držené R): levá ruka z pohledu hráče a zblízka → /tmp/ins_<zbraň>_<pohled>.png
var player: Player
var ins:=1.0
func _initialize() -> void: call_deferred("run")
func tick(dt: float) -> void:
	player.weapon.update(dt)
	player.body.weapon.inspect=ins
	player.body.update_body(dt,Vector3.ZERO,0,Vector3.ZERO,false,false,true)
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(name)
func run() -> void:
	root.size=Vector2i(960,540)
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
	player.pitch=float(OS.get_environment("PITCH")) if OS.get_environment("PITCH")!="" else -0.1
	var tag:=OS.get_environment("TAG")
	var guns:=OS.get_environment("GUNS").split(",") if OS.get_environment("GUNS")!="" else PackedStringArray(["ak","mp40","deagle","izh54"])
	var levels:=OS.get_environment("LV").split_floats(",") if OS.get_environment("LV")!="" else PackedFloat64Array([1.0])
	for gun in guns:
		player.weapon.give(gun,false); player.weapon.switch_to(gun,true)
		ins=0.0
		for i in 90: tick(1.0/60.0)
		for lv in levels:
			ins=lv
			for i in 40: tick(1.0/60.0)
			cam.cull_mask=0xFFFFF & ~4
			cam.fov=80
			cam.global_position=player.body.first_person_eye(player.yaw)
			cam.rotation=Vector3(player.pitch,player.yaw,0)
			await shot("/tmp/ins_%s%s_%d_fp.png"%[gun,tag,int(lv*100)])
			var fs: Skeleton3D=rig.avatar.first_skeleton
			var lw: Vector3=fs.global_transform*fs.get_bone_global_pose(fs.find_bone("mixamorig_LeftHand")).origin
			var le: Vector3=fs.global_transform*fs.get_bone_global_pose(fs.find_bone("mixamorig_LeftForeArm")).origin
			var mb: Basis=rig.avatar.model.global_transform.basis.orthonormalized()
			cam.fov=45
			var c0:=(lw+le)*0.5
			var views:=[["a",Vector3(0.45,0.15,0.35)],["b",Vector3(0.1,-0.45,0.3)],["c",Vector3(-0.3,0.2,0.4)]]
			if OS.get_environment("HANDVIEW")!="":
				views=[["L",Vector3(0.35,0.05,0.05)],["U",Vector3(0.05,-0.35,0.05)],["T",Vector3(0.02,0.35,0.08)],["R",Vector3(-0.35,0.05,0.05)]]
				c0=lw
			for v in views:
				var c:=c0
				cam.global_position=c+mb*(v[1] as Vector3)
				cam.look_at(c,Vector3.UP)
				await shot("/tmp/ins_%s%s_%d_%s.png"%[gun,tag,int(lv*100),v[0]])
	quit()
