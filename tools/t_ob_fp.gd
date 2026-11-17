extends SceneTree
var player: Player
func _initialize() -> void: call_deferred("run")
var OB:=0.0
func tick(dt: float) -> void:
	player.weapon.update(dt)
	player.body.weapon.obstruct=OB
	player.body.update_body(dt,Vector3.ZERO,0,Vector3.ZERO,false,false,true)
func run() -> void:
	root.size=Vector2i(1280,720)
	var env:=Environment.new(); env.background_mode=Environment.BG_COLOR; env.background_color=Color(0.35,0.42,0.45)
	env.ambient_light_color=Color(0.7,0.75,0.8); env.ambient_light_energy=0.7
	var we:=WorldEnvironment.new(); we.environment=env; root.add_child(we)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-50,150,0); sun.light_energy=1.2; root.add_child(sun)
	var floor:=MeshInstance3D.new(); var pm:=BoxMesh.new(); pm.size=Vector3(8,4,0.2); floor.mesh=pm; floor.position=Vector3(0,1.5,-4); root.add_child(floor)
	player=Player.new()
	root.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	var cam:=Camera3D.new()
	root.add_child(cam)
	cam.current=true
	cam.near=0.03
	cam.fov=75
	cam.cull_mask=0xFFFFF & ~4
	player.body.reset(0)
	var w: Node=player.weapon
	var rig: Node=player.body.weapon
	w.give("ak",false)
	w.switch_to("ak",true)
	for i in 30: tick(1.0/60.0)
	w.wall_react=false
	for i in 60: tick(1.0/60.0)
	player.pitch=float(OS.get_environment("PITCH")) if OS.get_environment("PITCH")!="" else 0.0
	var shots=[0.0,0.4,0.8,1.0,1.4,2.0]
	for k in shots.size():
		var p: float=shots[k]
		for i in 20:
			OB=p
			tick(1.0/60.0)
		cam.position=player.body.first_person_eye(0)
		cam.rotation=Vector3(player.pitch,0,0)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		print("ob ",p," err ",snapped(rig.right_error*100,0.1)," ",snapped(rig.left_error*100,0.1)," #",rig.avatar.model.global_transform.origin," rot ",rig.avatar.model.global_rotation," body ",player.body.global_position," eye ",player.body.first_person_eye(0))
		print("p ",p," R err ",snapped(rig.first_right_error*100,0.1)," L err ",snapped(rig.first_left_error*100,0.1))
		root.get_texture().get_image().save_png("/tmp/ob_%d.png"%k)
		cam.cull_mask=0xFFFFF & ~8
		cam.fov=40
		var eye: Vector3=player.body.first_person_eye(0)
		var mt: Transform3D=rig.avatar.model.global_transform
		var cx:=float(OS.get_environment('CX')) if OS.get_environment('CX')!='' else -0.8
		cam.global_position=mt*Vector3(cx,1.95,1.25)
		cam.look_at(mt*Vector3(0,1.6,0.25))
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/obtp_%d.png"%k)
		cam.cull_mask=0xFFFFF & ~4
		cam.fov=75
	quit()
