extends SceneTree
# Celá hra bez grafiky: kola, příchod zombie k hráči, zranění, smrt, restart a střílející bot.
var main: Node3D
var mode: Node
func _initialize() -> void:
	call_deferred("run")
func status(label: String) -> void:
	var p: Player=main.player
	var nearest:=999.0
	var alive:=0
	var swimming:=0
	for z in mode.ZombieScript.crowd:
		if is_instance_valid(z) and z.ai:
			alive+=1
			if z.swimming: swimming+=1
			nearest=minf(nearest,z.global_position.distance_to(p.global_position))
	print("%s t=%.0f stav=%s kolo=%d zivych=%d (plave %d) ceka=%d nejbliz=%.1f zdravi=%.0f body=%d zabiti=%d munice=%d/%d" % [label,Time.get_ticks_msec()/1000.0*Engine.time_scale,mode.state,mode.round_now,alive,swimming,mode._to_spawn,nearest,mode.health,mode.points,mode.kills,p.weapon.ammo,p.weapon.reserve])
func run() -> void:
	main=load("res://main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.6).timeout
	mode=main.mode
	main._on_play()
	await create_timer(1.5).timeout
	var p: Player=main.player
	print("hrac ",p.global_position," control ",p.control_enabled," maska ",p.collision_mask)
	p.weapon.equip()
	mode.begin()
	Engine.time_scale=5.0
	# --- A: hráč stojí ve vstupní místnosti a nebrání se
	for i in 60:
		await create_timer(5.0).timeout
		if i%2==0: status("A")
		if mode.state=="dead": break
	status("A konec")
	print("A: smrt=",mode.state=="dead")
	# --- B: restart, hráč v hale u bazénu, bot střílí na nejbližší zombie
	mode.restart()
	p.teleport(Vector3(0,-0.35,-4.5),PI,0.0)
	p.weapon.infinite_reserve=true
	var shots:=0
	var clock:=0.0
	var log_clock:=0.0
	var start:=Time.get_ticks_msec()
	while (Time.get_ticks_msec()-start)<70000 and mode.round_now<4 and mode.state!="dead":
		await physics_frame
		clock+=1.0/60.0
		log_clock+=1.0/60.0
		if log_clock>20.0:
			log_clock=0.0
			status("B")
		if clock<0.1: continue
		clock=0.0
		var eye: Vector3=p.camera.global_position
		var best: Node3D=null
		var best_d:=30.0
		for z in mode.ZombieScript.crowd:
			if not is_instance_valid(z) or not z.ai or z._emerge>0.0: continue
			var d: float=z.global_position.distance_to(p.global_position)
			if d<best_d:
				best_d=d
				best=z
		if best==null: continue
		var aim: Vector3=best.skeleton.global_transform*best.bone_pose(best._ids["Head" if shots%3==0 else "Spine2"]).origin+Vector3(0,0.05,0)
		main._weapon_fired(eye,aim)
		shots+=1
	status("B konec")
	print("B: vystrelu=",shots," kolo=",mode.round_now," headshoty=",mode.headshots)
	Engine.time_scale=1.0
	quit()
