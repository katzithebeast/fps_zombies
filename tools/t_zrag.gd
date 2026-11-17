extends SceneTree
const Z:=preload("res://scripts/zombie.gd")
func _initialize() -> void: call_deferred("run")
func body(pos: Vector3, size: Vector3) -> void:
	var b:=StaticBody3D.new(); var c:=CollisionShape3D.new(); var sh:=BoxShape3D.new(); sh.size=size; c.shape=sh; b.add_child(c); b.position=pos; root.add_child(b)
func hips(z) -> Vector3: return z.bodies[z._ids["Hips"]].global_position
func wait(t: float) -> void:
	var e:=0.0
	while e<t:
		await physics_frame
		e+=1.0/60.0
func run() -> void:
	body(Vector3(0,-0.25,0),Vector3(40,0.5,40))
	body(Vector3(1.4,1.5,0),Vector3(0.8,3,10))          # zeď líc x=1.0
	body(Vector3(30,-3.1,0),Vector3(6,0.2,6))          # hluboké dno y=-3.0 kolem x=30 (mimo podlahu)
	await physics_frame; await physics_frame
	# 1) smrt u zdi (sprinter tlačí do zdi), výstřel do zad směrem ke zdi
	var z=Z.new(); root.add_child(z)
	var tg:=Node3D.new(); root.add_child(tg); tg.global_position=Vector3(4,0,0.3)
	await physics_frame
	z.global_position=Vector3(-1.5,0,0); z.ai=true; z.tier="sprint"; z.target=tg
	await wait(1.5)
	z.hit(z._ids["Spine2"],hips(z)+Vector3.UP*0.3,Vector3(1,0,0),2.5,9999.0)
	var worst:=0.0
	var settled:=0.0
	var t0:=Time.get_ticks_msec()
	for k in 240:
		await physics_frame
		for id in z.bodies:
			if z.bodies[id].collision_layer==0: continue
			var pe: float=z.bodies[id].global_position.x+float(z.bodies[id].get_meta("radius"))-1.0
			worst=maxf(worst,pe)
			if k>60 and pe>settled:
				settled=pe; set_meta("sp","%s k=%d y=%.2f" % [z.bodies[id].get_meta("part_name"),k,z.bodies[id].global_position.y])
			if k==0 and pe>0.0: print("1 start ve zdi ",z.bodies[id].get_meta("part_name")," ",pe)
		if z._frozen: break
	print("1 po 1 s klidu max %.3f m %s" % [settled,get_meta("sp","")])
	print("1 smrt u zdi: max zajeti tela do zdi %.3f m, zapeceno=%s po %.1f s, mrtvol=%d" % [worst,str(z._frozen),(Time.get_ticks_msec()-t0)/1000.0,Z.corpses.size()])
	# 2) výstřel do zapečené mrtvoly
	var before:=hips(z)
	var head=z.bodies[z._ids["Head"]]
	var q:=PhysicsRayQueryParameters3D.create(head.global_position+Vector3(-2,0.5,0),head.global_position,32)
	var hitr:=root.get_world_3d().direct_space_state.intersect_ray(q)
	print("2 mrtvola jde trefit paprskem: ",not hitr.is_empty())
	z.hit(z._ids["Spine2"],hips(z),Vector3(0.3,0,1).normalized(),2.0,60.0)
	print("2 frozen po hit ",z._frozen," pending ",z._pending_impacts.size()," pm ",z.process_mode," phys ",z.is_physics_processing())
	await physics_frame
	await physics_frame
	var ch=z.bodies[z._ids["Spine2"]]
	print("2 hrudnik v ",ch.linear_velocity," sim ",ch.is_simulating_physics()," layer ",ch.collision_layer," mask ",ch.collision_mask)
	await wait(0.6)
	var after:=hips(z)
	print("2 po zásahu: rozmrazeno=%s posun panve %.3f m" % [str(not z._frozen or after.distance_to(before)>0.01),after.distance_to(before)])
	await wait(8.0)
	print("2 znovu zapeceno=",z._frozen)
	z.queue_free(); tg.queue_free()
	# 3) pád do vody (hladina 0, dno -0.4 a hluboká jáma)
	Z.water_level=0.0
	var w=Z.new(); root.add_child(w)
	await physics_frame
	w.global_position=Vector3(30,1.5,0)
	w.hit(w._ids["Spine2"],hips(w),Vector3(0,0,1),1.0,9999.0)
	var vmax:=0.0; var tt:=0.0; var landed:=-1.0
	while tt<8.0 and not w._frozen:
		await physics_frame; tt+=1.0/60.0
		var hv=w.bodies[w._ids["Hips"]].linear_velocity
		if hips(w).y<-1.0: vmax=maxf(vmax,-hv.y)
		if landed<0 and hips(w).y<-2.75: landed=tt
	print("3 voda: max rychlost pod hladinou %.2f m/s, panev u dna za %.2f s, zapeceno za %.2f s, panev y %.2f" % [vmax,landed,tt,hips(w).y])
	w.queue_free()
	Z.water_level=-1000.0
	# 4) výbuch dýně: 2 živé + 1 mrtvola
	var a=Z.new(); var b=Z.new(); var c=Z.new()
	for x in [a,b,c]: root.add_child(x)
	await physics_frame
	a.global_position=Vector3(-5,0,3); b.global_position=Vector3(-6.5,0,4); c.global_position=Vector3(-4,0,5)
	c.hit(c._ids["Spine2"],hips(c),Vector3(0,0,1),1.0,9999.0)
	await wait(1.0)
	await wait(0.1)
	var p0:=[hips(a),hips(b),hips(c)]
	var center:=Vector3(-5.2,0.2,4.2)
	for x in [a,b]: x.blast(center,7.0,7.5)
	for x in Z.corpses.duplicate(): if x==c: x.blast(center,7.0,6.0)
	await wait(1.2)
	print("4 výbuch: mrtvi %s %s, posun pánví %.2f %.2f %.2f m" % [a.dead,b.dead,hips(a).distance_to(p0[0]),hips(b).distance_to(p0[1]),hips(c).distance_to(p0[2])])
	quit()
