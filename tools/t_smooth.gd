extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func key(k, on):
	var e=InputEventKey.new(); e.physical_keycode=k; e.keycode=k; e.pressed=on; Input.parse_input_event(e)
func cam_track(main):
	return main.player.camera.global_position
func rel(main):
	var cam=main.player.camera; var r=main.player.body.weapon
	return (cam.global_transform.affine_inverse()*r.first.global_transform).origin*100.0
func run() -> void:
	var main=load("res://main.tscn").instantiate()
	root.add_child(main)
	main.settings["intro"]=false
	await create_timer(0.6).timeout
	main._on_play()
	await create_timer(2.5).timeout
	key(KEY_W,true); await create_timer(0.1).timeout; key(KEY_W,false); await create_timer(1.0).timeout
	key(KEY_W,true)
	var pts=[]
	var rg=main.player.body.weapon
	for i in 90:
		await process_frame
		pts.append(rel(main))
		if i%10==0: print("err ",i," R ",snapped(rg.right_error*100,0.1)," L ",snapped(rg.left_error*100,0.1)," reach ",(rg._reach*100).snapped(Vector3.ONE*0.1)," gait ",snapped(rg._gait,0.01))
		if i<0: print("m",i," model ",(rg.avatar.model.global_position*100).snapped(Vector3.ONE*0.1)," mrot ",(rg.avatar.model.global_rotation*57.3).snapped(Vector3.ONE*0.1)," fullpos ",(rg.full.position*100).snapped(Vector3.ONE*0.1)," fullglob ",(rg.full.global_position*100).snapped(Vector3.ONE*0.1))
		if i<0: print("s",i," sprint ",snapped(rg.sprint,0.01)," psprint ",main.player._sprint," av ",(rg.avatar.global_position*100).snapped(Vector3.ONE*0.1)," avrot ",snapped(rg.avatar.rotation.x*57.3,0.1)," pitch ",snapped(rg.pitch,0.001))
		if i<0: print("g",i," cam ",(main.player.camera.global_position*100).snapped(Vector3.ONE*0.1)," gun ",(rg.first.global_position*100).snapped(Vector3.ONE*0.1)," full ",(rg.full.global_position*100).snapped(Vector3.ONE*0.1)," camrot ",(main.player.camera.global_rotation*57.3).snapped(Vector3.ONE*0.1))
		if i<0: print("w",i," rel ",pts[-1].snapped(Vector3.ONE*0.1)," head ",(rg._head_smooth*100).snapped(Vector3.ONE*0.1)," raw ",(rg.bone_pose(5).origin*100).snapped(Vector3.ONE*0.1)," eyeh ",snapped(main.player.camera_eye_height,0.001)," gait ",snapped(rg._gait,0.01)," inert ",(rg._inertia_offset*100).snapped(Vector3.ONE*0.1)," w ",snapped(rg.weight,0.01))
	key(KEY_W,false)
	var rig=main.player.body.weapon
	var cams=[]
	for i in 90:
		await process_frame
		pts.append(rel(main))
		cams.append(cam_track(main))
		if i<45 and i%3==0: print("f",i," y ",snapped(pts[-1].y,0.01)," z ",snapped(pts[-1].z,0.01)," gait ",snapped(rig._gait,0.01)," in ",(rig._inertia_offset*100).snapped(Vector3.ONE*0.01)," head ",(rig._head_smooth*100).snapped(Vector3.ONE*0.1), " spd ",snapped(Vector2(main.player.velocity.x,main.player.velocity.z).length(),0.01))
	var jerk_walk:=0.0; var jerk_stop:=0.0; var settle:=0
	for i in range(2,pts.size()):
		var j: float=(pts[i]-2*pts[i-1]+pts[i-2]).length()
		if i<90:
			if j>jerk_walk: print("walkjerk at ",i," ",snapped(j,0.01)," p ",pts[i].snapped(Vector3.ONE*0.01))
			jerk_walk=maxf(jerk_walk,j)
		else: jerk_stop=maxf(jerk_stop,j)
	for i in range(pts.size()-1,90,-1):
		if (pts[i]-pts[pts.size()-1]).length()>0.15: settle=i-90; break
	var cj:=0.0
	for i in range(2,cams.size()): cj=maxf(cj,(cams[i]-2*cams[i-1]+cams[i-2]).length()*100.0)
	print("CAMJERK stop ",snapped(cj,0.001))
	print("JERK walk ",snapped(jerk_walk,0.001)," stop ",snapped(jerk_stop,0.001)," settle frames ",settle)
	var line=""
	for i in range(84,130,3): line+=str(snapped(pts[i].y,0.01))+" "
	print("Y ",line)
	quit()
