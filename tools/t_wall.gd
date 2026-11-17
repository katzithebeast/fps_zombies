extends SceneTree
# Zbraň u zdi: o kolik ústí hlavně (v první osobě) vjede do stěny před hráčem.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var main=load("res://main.tscn").instantiate()
	root.add_child(main)
	main.settings["intro"]=false
	await create_timer(0.6).timeout
	main._on_play()
	await create_timer(2.0).timeout
	var p=main.player
	var w=p.weapon
	var rig=p.body.weapon
	for g in ["ak","mp40","izh54","deagle"]: w.give(g,false)
	var off: bool=OS.get_environment("NOWALL")!=""
	w.wall_react=not off
	# najít zeď: od startu na sever
	var space=p.get_world_3d().direct_space_state
	var start: Vector3=main.SPAWN+Vector3(0,1.6,0)
	var dirs=[Vector3(0,0,-1),Vector3(1,0,0),Vector3(-1,0,0),Vector3(0,0,1)]
	var wall_hit=null
	var fwd=Vector3.ZERO
	for d in dirs:
		var h=space.intersect_ray(PhysicsRayQueryParameters3D.create(start,start+d*30.0,1))
		if not h.is_empty() and absf(h.normal.dot(-d))>0.95:
			wall_hit=h.position; fwd=d; break
	print("wall at ",wall_hit," dir ",fwd)
	var yaw:=atan2(-fwd.x,-fwd.z)
	for g in ["ak","mp40","izh54","deagle"]:
		w.switch_to(g,true)
		await create_timer(0.7).timeout
		var res=[]
		for dist in [1.2,0.9,0.7,0.55,0.45,0.36]:
			var at: Vector3=wall_hit-fwd*dist
			p.teleport(Vector3(at.x,main.SPAWN.y,at.z),yaw,0.0)
			var worst:=-9.0
			for f in 50:
				await process_frame
			var cam: Camera3D=p.camera
			var cf: Vector3=-cam.global_basis.z
			var wall_d: float=(wall_hit-cam.global_position).dot(cf)
			var mz: Vector3=rig.first.global_transform*(rig._gi().muzzle as Vector3)
			var md: float=(mz-cam.global_position).dot(cf)
			res.append("%.2fm:%+.0fcm(ob %.2f)"%[dist,(md-wall_d)*100,rig._ob])
		print(g," ",res)
	quit()
