extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func key(k, on):
	var e=InputEventKey.new(); e.physical_keycode=k; e.keycode=k; e.pressed=on; Input.parse_input_event(e)
func rel(main):
	var cam=main.player.camera; var r=main.player.body.weapon
	var t=cam.global_transform.affine_inverse()*r.first.global_transform
	return [t.origin*100.0, t.basis.get_euler()*57.3]
func run() -> void:
	var main=load("res://main.tscn").instantiate()
	root.add_child(main)
	main.settings["intro"]=false
	await create_timer(0.6).timeout
	main._on_play()
	await create_timer(2.0).timeout
	var r=main.player.body.weapon
	print("equipped ",r.equipped," gun ",r.gun)
	if not r.equipped:
		main.player.weapon.equipped=true if main.player.weapon.get("equipped")!=null else false
	await create_timer(1.0).timeout
	var base=rel(main); print("idle ",base)
	var mn=Vector3.ONE*99; var mx=-mn; var rmn=Vector3.ONE*99; var rmx=-rmn
	for i in 30:
		await create_timer(0.1).timeout
		var q=rel(main); mn=mn.min(q[0]); mx=mx.max(q[0]); rmn=rmn.min(q[1]); rmx=rmx.max(q[1])
	print("idle range cm ",(mx-mn)," deg ",(rmx-rmn))
	key(KEY_W,true)
	await create_timer(1.0).timeout
	mn=Vector3.ONE*99; mx=-mn; rmn=Vector3.ONE*99; rmx=-rmn
	for i in 40:
		await create_timer(0.05).timeout
		var q=rel(main); mn=mn.min(q[0]); mx=mx.max(q[0]); rmn=rmn.min(q[1]); rmx=rmx.max(q[1])
	print("walk range cm ",(mx-mn)," deg ",(rmx-rmn), " speed ",Vector2(main.player.velocity.x,main.player.velocity.z).length())
	key(KEY_W,false)
	await create_timer(1.5).timeout
	for i in 20:
		main.player.yaw+=0.06
		await create_timer(0.016).timeout
	print("turning ",rel(main)[1]," sway ",r._sway," drift ",r._idle_drift)
	for i in 8:
		await create_timer(0.06).timeout
		print("  settle ",snapped(rel(main)[1],Vector3.ONE*0.1)," sway ",snapped(r._sway,Vector2.ONE*0.001))
	quit()
