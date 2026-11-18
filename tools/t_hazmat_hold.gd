extends SceneTree
# Hazmat se zbraní: chyba dosahu rukou (IK) a render 1. a 3. osoby (AK a Deagle, od boku a při míření).
var player: Player
func _initialize() -> void: call_deferred("run")
func tick(dt: float) -> void:
	player.weapon.update(dt)
	player.body.update_body(dt,Vector3.ZERO,0,Vector3.ZERO,false,false,true)
func run() -> void:
	root.size=Vector2i(960,540)
	var env:=Environment.new(); env.background_mode=Environment.BG_COLOR; env.background_color=Color(0.35,0.42,0.45)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color=Color(0.7,0.75,0.8); env.ambient_light_energy=0.7
	var we:=WorldEnvironment.new(); we.environment=env; root.add_child(we)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-50,150,0); sun.light_energy=1.2; root.add_child(sun)
	player=Player.new(); root.add_child(player); player.set_process(false); player.set_physics_process(false)
	var cam:=Camera3D.new(); root.add_child(cam); cam.current=true; cam.near=0.03; cam.fov=75
	player.body.reset(0)
	var w: Node=player.weapon
	var rig: Node=player.body.weapon
	var k:=0
	for gun in ["ak","deagle"]:
		w.give(gun,false); w.switch_to(gun,true)
		for aim in [0.0,1.0]:
			rig.aim=aim
			for i in 60:
				rig.aim=aim
				tick(1.0/60.0)
			cam.cull_mask=0xFFFFF & ~4
			cam.fov=75
			cam.position=player.body.first_person_eye(0); cam.rotation=Vector3(player.pitch,0,0)
			await RenderingServer.frame_post_draw; await RenderingServer.frame_post_draw
			print("%s aim %.0f: chyba R %.1f cm, L %.1f cm" % [gun,aim,rig.first_right_error*100,rig.first_left_error*100])
			root.get_texture().get_image().save_png("/tmp/hold_fp_%d.png"%k)
			cam.cull_mask=0xFFFFF & ~8
			cam.fov=40
			var mt: Transform3D=rig.avatar.model.global_transform
			cam.global_position=mt*Vector3(-1.3,1.9,1.6); cam.look_at(mt*Vector3(0,1.4,0.2))
			await RenderingServer.frame_post_draw; await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/hold_tp_%d.png"%k)
			# detail rukou
			var sk: Skeleton3D=rig.avatar.skeleton
			var rh: Vector3=sk.global_transform*sk.get_bone_global_pose(sk.find_bone("mixamorig_RightHand")).origin
			var lh: Vector3=sk.global_transform*sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftHand")).origin
			var mid:=(rh+lh)*0.5
			cam.fov=35
			cam.global_position=mid+mt.basis*Vector3(-0.55,0.25,0.45); cam.look_at(mid)
			await RenderingServer.frame_post_draw; await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/hold_hand_%d.png"%k)
			cam.global_position=mid+mt.basis*Vector3(0.6,0.1,0.35); cam.look_at(mid)
			await RenderingServer.frame_post_draw; await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/hold_hand2_%d.png"%k)
			k+=1
	quit()
