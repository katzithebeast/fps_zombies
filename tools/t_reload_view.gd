extends SceneTree
## Přebíjení zastavené ve zvolených fázích: pohled hráče a tři pohledy zblízka na levou ruku.
##   GUNS=izh54 PH=0.35,0.5 godot --rendering-driver vulkan --path . --script res://tools/t_reload_view.gd
## Výstup: /tmp/rv_<zbraň>_<fáze>_<pohled>.png
var player: Player

func _initialize() -> void: call_deferred("run")

func tick(dt: float) -> void:
	player.weapon.update(dt)
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
	var cam:=Camera3D.new(); root.add_child(cam); cam.current=true; cam.near=0.01
	player.body.reset(0)
	var rig: Node=player.body.weapon
	var w: Node=player.weapon
	player.pitch=-0.05
	var guns:=OS.get_environment("GUNS").split(",") if OS.get_environment("GUNS")!="" else PackedStringArray(["izh54"])
	var phases:=OS.get_environment("PH").split_floats(",") if OS.get_environment("PH")!="" else PackedFloat64Array([0.35,0.5])
	for gun in guns:
		for ph in phases:
			w.give(gun,false); w.switch_to(gun,true)
			for i in 90: tick(1.0/60.0)
			w.ammo=0
			w.reload()
			var total: float=float(rig.reload_time)
			while float(rig.reload_left)>total*(1.0-ph): tick(1.0/60.0)
			# zastavit čas přebíjení (jen dorovnat pružiny)
			var keep: float=float(rig.reload_left)
			for i in 3:
				rig.reload_left=keep
				w.reload_left=keep
				tick(1.0/60.0)
			cam.cull_mask=0xFFFFF & ~4
			cam.fov=75
			cam.global_position=player.body.first_person_eye(player.yaw)
			cam.rotation=Vector3(player.pitch,player.yaw,0)
			var ci: Transform3D=cam.global_transform.affine_inverse()
			var bn: Node3D=rig._part(rig.first,"Barrel")
			if bn:
				var ax: Vector3=(ci.basis*(bn.global_basis.orthonormalized()*Vector3.BACK)).normalized()
				var mo: Vector3=ci*(bn.global_transform*rig.SHOT_MOUTH_L)
				var fsk: Skeleton3D=rig.avatar.first_skeleton
				var hw: Vector3=ci*(rig.avatar.first_mesh.global_transform*fsk.get_bone_global_pose(fsk.find_bone("mixamorig_LeftHand")).origin)
				var fa: Vector3=ci*(rig.avatar.first_mesh.global_transform*fsk.get_bone_global_pose(fsk.find_bone("mixamorig_LeftForeArm")).origin)
				print("ph %.2f  osa komor (kamera) %s  ústí %s  zápěstí %s  loket %s" % [ph,ax.snapped(Vector3.ONE*0.01),mo.snapped(Vector3.ONE*0.01),hw.snapped(Vector3.ONE*0.01),fa.snapped(Vector3.ONE*0.01)])
			if OS.get_environment("NOIMG")!="": continue
			await shot("/tmp/rv_%s_%d_fp.png"%[gun,int(ph*100)])
			if OS.get_environment("FPONLY")!="":
				w.reload_left=0.0
				rig.cancel_reload()
				for i in 30: tick(1.0/60.0)
				continue
			var fs: Skeleton3D=rig.avatar.first_skeleton
			var lw: Vector3=fs.global_transform*fs.get_bone_global_pose(fs.find_bone("mixamorig_LeftHand")).origin
			var mb: Basis=rig.avatar.model.global_transform.basis.orthonormalized()
			cam.fov=45
			for v in [["L",Vector3(0.4,0.12,0.1)],["U",Vector3(0.05,-0.4,0.1)],["T",Vector3(0.05,0.4,0.15)]]:
				cam.global_position=lw+mb*(v[1] as Vector3)
				cam.look_at(lw,Vector3.UP if absf((v[1] as Vector3).normalized().y)<0.9 else Vector3.FORWARD)
				await shot("/tmp/rv_%s_%d_%s.png"%[gun,int(ph*100),v[0]])
			w.reload_left=0.0
			rig.cancel_reload()
			for i in 30: tick(1.0/60.0)
	quit()
