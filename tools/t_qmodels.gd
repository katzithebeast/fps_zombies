extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func shot(w, cam, c: Vector3, dist: float, dir: Vector3, name: String) -> void:
	cam.look_at_from_position(c+dir.normalized()*dist,c,Vector3.UP)
	for i in 5: await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/ws/q_%s.png" % name)
func run() -> void:
	var w:=Node3D.new(); root.add_child(w)
	var env:=WorldEnvironment.new(); var e:=Environment.new(); e.background_mode=Environment.BG_COLOR; e.background_color=Color(0.25,0.27,0.3); e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color=Color(0.6,0.6,0.65); e.ambient_light_energy=0.8; env.environment=e; w.add_child(env)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-40,35,0); sun.light_energy=1.6; w.add_child(sun)
	var cam:=Camera3D.new(); w.add_child(cam); cam.current=true
	var q=load("res://scripts/quest.gd").new(); w.add_child(q)
	# ventily
	var row:=Node3D.new(); w.add_child(row)
	for i in 3:
		var v: Node3D=q._inst("valve",0.75,1); row.add_child(v); v.position.x=(i-1)*0.95
		var parts=q._valve_split(v)
		var pivot:=Node3D.new(); v.add_child(pivot); pivot.position=parts.center
		for m in parts.wheel: m.reparent(pivot,true)
		pivot.rotation.y=i*0.6
		pivot.visible=i!=2
	await shot(w,cam,Vector3(0,0.5,0),3.0,Vector3(0,0.5,1),"valves")
	row.queue_free()
	# hodiny 9:45
	var clock: Node3D=q._inst("clock",0.65,0); w.add_child(clock); clock.rotation.x=PI/2
	clock.find_child("hour empty",true,false).rotation.y=-TAU*(9.75/12.0)
	clock.find_child("minute empty",true,false).rotation.y=-TAU*0.75
	await shot(w,cam,Vector3(0,0,0),1.2,Vector3(0,0,1),"clock")
	clock.queue_free()
	# rozvaděč s pojistkami
	var cab: Node3D=q._inst("electrical_box",2.0,1); w.add_child(cab)
	for i in 3:
		var f: Node3D=q._inst("fuse",0.16,0); w.add_child(f); f.position=Vector3(-0.2+i*0.2,1.42,0.27)
	await shot(w,cam,Vector3(0,1.1,0),3.2,Vector3(0.3,0.1,1),"fusebox")
	for c in w.get_children(): if c is Node3D and not (c is Camera3D or c is DirectionalLight3D or c==q): c.queue_free()
	await process_frame
	# čerpadlo
	var pump: Node3D=q._inst("pump",2.6,1); w.add_child(pump)
	await shot(w,cam,Vector3(0,1.3,0),5.0,Vector3(0.4,0.2,1),"pump")
	pump.queue_free()
	# Anděl
	var b:=Node3D.new(); w.add_child(b)
	var m: Node3D=load("res://assets/quest/angel_boss.glb").instantiate(); b.add_child(m); m.scale=Vector3.ONE*200.0
	for mi in m.find_children("*","MeshInstance3D",true,false): mi.extra_cull_margin=8.0
	var ap: AnimationPlayer=m.find_children("*","AnimationPlayer",true,false)[0]; ap.play("anim"); ap.seek(5.0,true)
	await shot(w,cam,Vector3(0,3.2,0),9.0,Vector3(0,0.1,1),"boss")
	ap.seek(9.0,true)
	await shot(w,cam,Vector3(0,3.2,0),9.0,Vector3(0.7,0.1,0.7),"boss2")
	b.queue_free()
	var lab: Node3D=q._inst("autopsy_lab",3.1,-1); w.add_child(lab)
	await shot(w,cam,Vector3(0,0.9,0),4.0,Vector3(0.6,0.5,1),"lab")
	quit()
