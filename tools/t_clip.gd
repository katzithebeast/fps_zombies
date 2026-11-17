extends SceneTree
# Při míření a pohybu: jak blízko kamery (podél osy pohledu) se dostane model zbraně v první osobě.
func _initialize() -> void: call_deferred("run")
func key(k, on):
	var e=InputEventKey.new(); e.physical_keycode=k; e.keycode=k; e.pressed=on; Input.parse_input_event(e)
var pts:={}
var _maxerr:=0.0
func collect(rig):
	pts.clear()
	for g in ["ak","mp40","izh54","deagle"]:
		var arr:=PackedVector3Array()
		var model: Node3D=rig.first.get_node(g)
		for m in model.find_children("*","MeshInstance3D",true,false):
			var mi: MeshInstance3D=m
			for si in mi.mesh.get_surface_count():
				var a: Array=mi.mesh.surface_get_arrays(si)
				var v: PackedVector3Array=a[Mesh.ARRAY_VERTEX]
				var step:=maxi(1,v.size()/1500)
				for i in range(0,v.size(),step): arr.append(v[i])
			pts[g+"|"+str(mi.get_instance_id())]=[mi,arr.duplicate()]
			arr.clear()
func min_depth(main,gun):
	var cam: Camera3D=main.player.camera
	var inv:=cam.global_transform.affine_inverse()
	var best:=99.0
	for k in pts:
		if not k.begins_with(gun+"|"): continue
		var mi: MeshInstance3D=pts[k][0]
		if not mi.is_visible_in_tree(): continue
		var xf:=inv*mi.global_transform
		for p in pts[k][1]:
			var c: Vector3=xf*p
			var d: float=-c.z
			# jen body, které jsou v zorném poli (jinak ořez nevadí)
			if d>0.0 and absf(c.x)<d*1.6 and absf(c.y)<d*1.0:
				best=minf(best,d)
	return best
func run() -> void:
	var main=load("res://main.tscn").instantiate()
	root.add_child(main)
	main.settings["intro"]=false
	await create_timer(0.6).timeout
	main._on_play()
	await create_timer(2.0).timeout
	var w=main.player.weapon
	for g in ["ak","mp40","izh54","deagle"]: w.give(g,false)
	collect(main.player.body.weapon)
	print("near ",main.player.camera.near)
	for g in ["ak","mp40","izh54","deagle"]:
		w.switch_to(g,true)
		await create_timer(0.8).timeout
		w.test_aim=true
		await create_timer(0.6).timeout
		var res=[]
		for mv in [[KEY_W],[KEY_S],[KEY_A],[KEY_D],[KEY_W,KEY_SHIFT],[]]:
			for k in mv: key(k,true)
			var lo:=99.0
			for f in 90:
				await process_frame
				var d0=min_depth(main,g)
				var rg=main.player.body.weapon
				if false: print("  idle f ",f," d ",snapped(d0*100,0.1)," inert ",(rg._inertia_offset*100).snapped(Vector3.ONE*0.1)," sway ",(rg._sway*100).snapped(Vector2.ONE*0.1)," reach ",(rg._reach*100).snapped(Vector3.ONE*0.1)," headoff ",(rg.head_offset*100).snapped(Vector3.ONE*0.1)," push ",snapped(rg._move_push*100,0.1)," tilt ",snapped(rg._move_tilt,0.01)," gait ",snapped(rg._gait,0.01)," rk ",(rg._rk_p*100).snapped(Vector3.ONE*0.1)," pitch ",snapped(main.player.pitch,0.01), " vel ",snapped(main.player.velocity.length(),0.01))
				lo=minf(lo,d0)
				_maxerr=maxf(_maxerr,maxf(rg.right_error,rg.left_error))
			for k in mv: key(k,false)
			for f in 40:
				await process_frame
				var dd=min_depth(main,g)
				if false: print("  CLOSE mv ",mv," f ",f," d ",snapped(dd*100,0.1)," aim ",snapped(w.aim_amount,0.01)," sprint ",snapped(w.sprint_amount,0.01)," vel ",snapped(main.player.velocity.length(),0.01))
				lo=minf(lo,dd)
			res.append(snapped(lo*100,0.1))
		print(g," near now ",main.player.camera.near)
		w.test_aim=false
		print(g," min depth cm W/S/A/D/sprint/idle ",res," max grip err cm ",snapped(_maxerr*100,0.1))
		_maxerr=0.0
	quit()
