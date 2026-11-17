extends SceneTree
# Dojde zombie z každého výchozího místa k hráči, ať stojí kdekoli?
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var main: Node3D=load("res://main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.6).timeout
	var mode: Node=main.mode
	main._on_play()
	await create_timer(1.5).timeout
	var p: Player=main.player
	mode.player=p
	Engine.time_scale=6.0
	var spots: Array=mode.WALK_SPAWNS.duplicate()
	spots.append_array([Vector3(0,0,-14),Vector3(4,0,-10),Vector3(-4,0,-18)])
	for ledge in mode.LEDGES: spots.append(ledge)
	var failures:=0
	for stand in [["vstupni mistnost",Vector3(0,0.5,8.0)],["satny",Vector3(10.0,0.5,7.0)],["technicka",Vector3(-20.5,-0.35,-15.0)],["hala vzadu",Vector3(0,-0.35,-23.5)],["v bazenu",Vector3(0,-1.38,-14.0)],["pruzel",Vector3(-28.0,-0.35,-21.0)]]:
		p.teleport(stand[1],0.0,0.0)
		p.control_enabled=false
		p.set_physics_process(false)
		p.global_position=stand[1]
		var zs:=[]
		for spot in spots:
			var z: Node3D=mode._make(1)
			z.tier="sprint"
			z.position=spot[0] if spot is Array else spot
			main.add_child(z)
			if spot is Array: z.drop(spot[1])
			elif spot.y==0.0: z.emerge()
			else: z.alert(false)
			z.attacked.disconnect(mode.hurt)
			zs.append({"z":z,"reached":-1.0,"from":spot})
		var t:=0.0
		while t<45.0:
			await physics_frame
			t+=1.0/60.0
			for item in zs:
				if item.reached<0.0 and item.z.global_position.distance_to(p.global_position)<1.9: item.reached=t
		var line:=""
		for item in zs:
			if item.reached<0.0:
				failures+=1
				line+="  NEDOSLA z %s -> skoncila %s (%.1f m od hrace, plave=%s, low=%s)\n" % [item.from,item.z.global_position,item.z.global_position.distance_to(p.global_position),item.z.swimming,item.z._low]
		var times:=zs.map(func(item): return snappedf(item.reached,0.1))
		print(stand[0],": casy dosazeni ",times)
		if line!="": print(line)
		mode._clear()
		await create_timer(0.5).timeout
	print("REACH FAILURES ",failures)
	Engine.time_scale=1.0
	quit()
