extends SceneTree
var player: Player
func _initialize() -> void: call_deferred("run")
func tick(dt: float) -> void:
	player.weapon.update(dt)
	player.body.update_body(dt,Vector3.ZERO,0,Vector3.ZERO,false,false,true)
func run() -> void:
	root.size=Vector2i(1280,720)
	var env:=Environment.new(); env.background_mode=Environment.BG_COLOR; env.background_color=Color(0.02,0.025,0.03)
	env.ambient_light_color=Color(0.3,0.33,0.35); env.ambient_light_energy=0.35
	env.glow_enabled=true; env.glow_intensity=0.8; env.glow_bloom=0.1; env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	var we:=WorldEnvironment.new(); we.environment=env; root.add_child(we)
	var wall:=MeshInstance3D.new(); var bm:=BoxMesh.new(); bm.size=Vector3(10,6,0.2); wall.mesh=bm; wall.position=Vector3(0,1.5,-6); root.add_child(wall)
	var fl:=MeshInstance3D.new(); var pm:=PlaneMesh.new(); pm.size=Vector2(20,20); fl.mesh=pm; root.add_child(fl)
	player=Player.new(); root.add_child(player)
	player.set_process(false); player.set_physics_process(false)
	var cam:=Camera3D.new(); root.add_child(cam); cam.current=true; cam.near=0.005
	player.body.reset(0)
	var w: Node=player.weapon
	var rig: Node=player.body.weapon
	var gun: String=OS.get_environment("GUN") if OS.get_environment("GUN")!="" else "ak"
	w.give(gun,false); w.switch_to(gun,true)
	for i in 60: tick(1.0/60.0)
	var shots=[]
	for k in (0 if OS.get_environment('SMOKEONLY')!='' else 4):
		for i in 10: tick(1.0/60.0)
		rig.kick()
		tick(0.004)
		cam.cull_mask=0xFFFFF & ~4; cam.fov=75
		cam.position=player.body.first_person_eye(0); cam.rotation=Vector3(player.pitch,0,0)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/fl_fp_%d.png"%k)
		rig.kick()
		tick(0.004)
		cam.cull_mask=0xFFFFF & ~8; cam.fov=40
		var mz: Vector3=rig.full.global_transform*(rig._gi().muzzle as Vector3)
		cam.global_position=mz+Vector3(1.1,0.15,-0.35)
		cam.look_at(mz+Vector3(0,0,-0.2))
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/fl_tp_%d.png"%k)
	# dávka a kouř
	var gnode: Node=rig.full
	print("smoke nodes ",gnode.find_children("smoke*","GPUParticles3D",false,false).size())
	if OS.get_environment("BIGSMOKE")!="":
		for sm in gnode.find_children("smoke*","GPUParticles3D",false,false):
			sm.process_material=sm.process_material.duplicate()
			sm.process_material.color_ramp=null
			var q: QuadMesh=sm.draw_pass_1.duplicate(); q.size=Vector2(0.4,0.4); sm.draw_pass_1=q
	for s in 8:
		rig.kick()
		var sm0: GPUParticles3D=gnode.get_node("smoke%d"%((rig._smoke_next+5)%6))
		print("emit ",sm0.emitting," vis ",sm0.is_visible_in_tree()," layers ",sm0.layers," pos ",sm0.global_position)
		for i in 5:
			tick(1.0/60.0)
			await process_frame
	var key:=OmniLight3D.new(); key.light_energy=3.0; key.omni_range=6.0; root.add_child(key)
	key.global_position=rig.full.global_transform*(rig._gi().muzzle as Vector3)+Vector3(0.8,0.8,0.6)
	cam.cull_mask=0xFFFFF & ~8; cam.fov=45
	var mz2: Vector3=rig.full.global_transform*(rig._gi().muzzle as Vector3)
	cam.global_position=mz2+Vector3(1.4,0.2,0.0)
	cam.look_at(mz2+Vector3(0,0.1,-0.5))
	for k in 3:
		rig.kick()
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/fl_smoke.png")
	quit()
