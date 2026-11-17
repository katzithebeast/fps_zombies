extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func key(k, on):
	var e=InputEventKey.new(); e.physical_keycode=k; e.keycode=k; e.pressed=on; Input.parse_input_event(e)
func run() -> void:
	var main=load("res://main.tscn").instantiate()
	root.add_child(main)
	main.settings["intro"]=false
	await create_timer(0.6).timeout
	main._on_play()
	await create_timer(3.0).timeout
	main.quest._set_angel_level(-14.3)
	var p=main.player
	p.teleport(Vector3(26.7,-0.2,-8.6),0.0,0.0)
	await create_timer(0.5).timeout
	key(KEY_W,true)
	for i in 16:
		await create_timer(0.5).timeout
		if i%5==0: print("ramp1 ",p.global_position.snapped(Vector3.ONE*0.1))
	key(KEY_W,false)
	p.teleport(Vector3(28.1,-7.2,-25.3),PI,0.0)
	await create_timer(0.5).timeout
	key(KEY_W,true)
	for i in 14:
		await create_timer(0.5).timeout
		if i%5==0: print("ramp2 ",p.global_position.snapped(Vector3.ONE*0.1))
	key(KEY_W,false)
	# do tunelu
	p.teleport(Vector3(33.5,-14.2,-25.0),0.0,0.0)
	main.quest._gate.state="open"; (main.quest._gate.body.get_child(0) as CollisionShape3D).disabled=true
	main.quest._gate.node.global_position+=Vector3.UP*3
	await create_timer(0.3).timeout
	key(KEY_W,true)
	for i in 12:
		await create_timer(0.5).timeout
	print("tunnel ",p.global_position.snapped(Vector3.ONE*0.1))
	key(KEY_W,false)
	await create_timer(3.0).timeout
	var mp=main.get_world_3d().navigation_map
	var pit=NavigationServer3D.map_get_path(mp,Vector3(30,-0.35,-5),Vector3(33.0,-14.4,-15),true)
	print("pit path pts ",pit.size()," end ",pit[pit.size()-1].snapped(Vector3.ONE*0.1) if pit.size()>0 else "none")
	main.mode._bake_navigation()
	await create_timer(4.0).timeout
	var path=NavigationServer3D.map_get_path(mp,Vector3(30,-0.35,-5),Vector3(33.5,-14.4,-50),true)
	print("nav path pts ",path.size()," end ",path[path.size()-1].snapped(Vector3.ONE*0.1) if path.size()>0 else "none")
	quit()
