extends SceneTree
## Úchopy první osoby, přepínání během akcí a účtování munice při různých FPS.
var failures:=0
var player: Player
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func tick(dt: float) -> void:
	player.weapon.update(dt)
	player.body.update_body(dt,Vector3.ZERO,0,Vector3.ZERO,false,false,true)
func run() -> void:
	player=Player.new()
	root.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var w: Node=player.weapon
	var rig: Node=player.body.weapon
	for gun in w.ORDER: w.give(gun,false)
	for fps in [30,60,144]:
		var dt: float=1.0/fps
		for gun in w.ORDER:
			w.switch_to(gun,true)
			for pitch in [-1.3,0.0,1.3]:
				player.pitch=pitch
				for i in fps: tick(dt)
				check(maxf(rig.first_right_error,rig.first_left_error)<0.035,"%s %d FPS pitch %.1f FP grips R %.3f L %.3f"%[gun,fps,pitch,rig.first_right_error,rig.first_left_error])
			player.pitch=0.0
			w.infinite_reserve=false
			var initial_ammo:=mini(5,int(w.stats().mag)-1)
			var take:=mini(3,int(w.stats().mag)-initial_ammo)
			w.ammo=initial_ammo
			w.reserve=3
			w.reload()
			var tactical: float=w.reload_left
			for i in ceili(3.0/dt): tick(dt)
			check(w.ammo==initial_ammo+take and w.reserve==3-take,"%s tactical reload conserves limited ammo at %d FPS"%[gun,fps])
			check(rig.first_left_error<0.035 and rig._part(rig.first,"Magazine").visible,"%s returns support hand and magazine"%gun)
			w.ammo=0
			w.reserve=100
			w.reload()
			check(gun=="izh54" or w.reload_left>tactical,"%s empty reload includes charging"%gun)
			for i in ceili(3.0/dt): tick(dt)
			check(w.ammo==int(w.stats().mag) and w.reserve==100-int(w.stats().mag),"%s empty reload finishes once"%gun)
		w.switch_to("ak",true)
		w.ammo=11
		w.switch_to("mp40")
		for i in ceili(0.2/dt): tick(dt)
		check(w.current=="ak" and rig.holster>0.7,"old weapon lowers before replacement at %d FPS"%fps)
		var ammo_before: int=w.ammo
		w.shoot()
		check(w.ammo==ammo_before,"cannot fire during switch")
		var swaps:=0
		var previous: String=w.current
		var hidden_swap:=true
		for i in fps:
			tick(dt)
			if previous!=w.current:
				swaps+=1
				hidden_swap=hidden_swap and rig.holster>0.98
			previous=w.current
		check(swaps==1 and hidden_swap and w.current=="mp40" and rig.holster==0,"one hidden swap and complete draw")
		check(w.clips.ak[0]==11,"switch preserves each magazine")
		w.switch_to("ak")
		for i in ceili(0.4/dt): tick(dt)
		w.switch_to("izh54")
		for i in fps*2: tick(dt)
		check(w.current=="izh54" and w._switch_left==0,"late switch input is buffered through draw")
		# Zrušení přebití nesmí nechat starý zásobník neviditelný ani přidat náboje.
		w.switch_to("ak",true)
		w.ammo=7
		w.reserve=30
		w.reload()
		for i in ceili(0.55/dt): tick(dt)
		w.switch_to("deagle")
		for i in fps: tick(dt)
		w.switch_to("ak",true)
		check(w.ammo==7 and w.reserve==30 and rig._part(rig.first,"Magazine").visible,"reload interruption restores visible magazine without free ammo")
	player.free()
	print("FPS ACTIONS failures=",failures)
	quit(1 if failures else 0)
