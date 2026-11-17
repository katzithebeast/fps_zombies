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
	await create_timer(2.0).timeout
	main.mode.begin()
	await create_timer(1.5).timeout
	var p=main.player
	# ze šaten východními dveřmi dovnitř (yaw -PI/2 = čelem k +x)
	var sp=main.get_world_3d().direct_space_state
	for y in [0.6,1.0,1.5,2.2]:
		var h=sp.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(10.0,y,5.0),Vector3(14.0,y,5.0)))
		print("ray y",y," ",h.position.snapped(Vector3.ONE*0.01) if h else "free"," ",h.collider.name if h else "", " ", h.collider.get_parent().name if h else "")
	var d=sp.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(11.3,3.0,5.0),Vector3(11.3,-1.0,5.0)))
	print("down ",d.position if d else "none"," ",d.collider.get_path() if d else "", " ", d.collider.get_parent().get_children().map(func(c): return c.name).slice(0,6) if d else "")
	print("ctrl ",p.control_enabled," susp ",p.input_suspended," lock ",p.interaction_locked)
	p.teleport(Vector3(10.6,0.6,6.8),-PI/2,0.0)
	key(KEY_W,true); await create_timer(0.1).timeout; key(KEY_W,false); await create_timer(0.2).timeout; p.teleport(Vector3(10.6,0.6,6.8),-PI/2,0.0)
	await create_timer(0.4).timeout
	key(KEY_W,true)
	for i in 8:
		await create_timer(0.5).timeout
		print("walk ",p.global_position.snapped(Vector3.ONE*0.1))
	key(KEY_W,false)
	p.teleport(Vector3(14.0,0.6,5.0),-PI/2,0.0)
	await create_timer(0.4).timeout
	key(KEY_W,true)
	for i in 6:
		await create_timer(0.5).timeout
		print("walk2 ",p.global_position.snapped(Vector3.ONE*0.1))
	key(KEY_W,false)
	var q=main.quest
	print("kid ",is_instance_valid(q._kid)," kind ",q._kid.kind if is_instance_valid(q._kid) else "", " pos ",q._kid.global_position.snapped(Vector3.ONE*0.1) if is_instance_valid(q._kid) else "")
	print("area ",main.areas.area_at(p.global_position))
	# probudit dítě: přijít ke kabince
	p.teleport(Vector3(17.2,0.6,7.2),-PI/2,0.0)
	await create_timer(4.0).timeout
	print("kid ai ",q._kid.ai," pos ",q._kid.global_position.snapped(Vector3.ONE*0.1))
	main.mode.spawn_debug()
	var kids=0
	for i in 30:
		var z=main.mode._make(3)
		if z.kind=="kid": kids+=1
		z.free()
	print("kid picks of 30: ",kids)
	var cases=0
	for it in q._pickups: if String(it.lbl.call()[0]).begins_with("Kufr"): cases+=1; print("  case ",it.lbl.call()," ",it.node.global_position.snapped(Vector3.ONE*0.1))
	print("cases ",cases)
	p.teleport(Vector3(0.0,0.6,4.4),PI/2,0.0)
	await create_timer(0.4).timeout
	key(KEY_W,true)
	for i in 8:
		await create_timer(0.5).timeout
	key(KEY_W,false)
	print("west ",p.global_position.snapped(Vector3.ONE*0.1)," area ",main.areas.area_at(p.global_position))
	for it in q._pickups:
		if String(it.lbl.call()[0]).begins_with("Kufr"):
			it.use.call(); print("took ",it.lbl.call()); break
	quit()
