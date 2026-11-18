extends SceneTree
## Prohlídka zbraně (držené N): snímky z 1. osoby v průběhu (GUNS=ak,... TIMES=0.4,...)
## → /tmp/ex_<zbraň>_<k>.png, ve 3. osobě /tmp/ex_<zbraň>_tp<k>.png
var player: Player
var rig: Node
func _initialize() -> void: call_deferred("run")
func tick(dt: float) -> void:
	player.weapon.update(dt)
	player.body.update_body(dt,Vector3.ZERO,0,Vector3.ZERO,false,false,true)
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
	rig=player.body.weapon
	var w: Node=player.weapon
	var guns:=OS.get_environment("GUNS").split(",") if OS.get_environment("GUNS")!="" else PackedStringArray(["ak","deagle"])
	var times:=[0.35,0.75,1.4,2.0,2.55,3.3,3.85,4.45]
	if OS.get_environment("TIMES")!="":
		times=Array(OS.get_environment("TIMES").split(",")).map(func(v): return float(v))
	var tp:=OS.get_environment("TP")!=""
	for gun in guns:
		w.give(gun,false); w.switch_to(gun,true)
		for i in 100: tick(1.0/60.0)
		w.test_examine=true
		var t:=0.0
		var worst:=0.0
		for k in times.size():
			while t<float(times[k]):
				tick(1.0/60.0)
				t+=1.0/60.0
				worst=maxf(worst,maxf(rig.right_error,rig.left_error if rig._left_relax<0.5 else 0.0))
			cam.cull_mask=0xFFFFF & ~4
			cam.fov=72
			cam.global_position=player.body.first_person_eye(player.yaw)
			cam.rotation=Vector3(player.pitch,player.yaw,0)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/ex_%s_%d.png"%[gun,k])
			if tp:
				cam.cull_mask=0xFFFFF & ~8
				cam.fov=40
				var mt: Transform3D=rig.avatar.model.global_transform
				cam.global_position=mt*Vector3(-0.9,1.85,1.3)
				cam.look_at(mt*Vector3(0,1.45,0.2))
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("/tmp/ex_%s_tp%d.png"%[gun,k])
		w.test_examine=false
		for i in 60: tick(1.0/60.0)
		print("%s: největší chyba dosahu rukou při prohlídce %.1f mm; po puštění ex_w %.2f chyba R %.1f L %.1f mm" % [gun,worst*1000,rig._ex_w,rig.right_error*1000,rig.left_error*1000])
	quit()
