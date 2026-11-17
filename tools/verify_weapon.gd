extends SceneTree
var failures:=0
func _initialize() -> void:
	call_deferred("verify")
func check(ok: bool,message: String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok: failures+=1
func verify() -> void:
	var player:=Player.new()
	root.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	var body: Node3D=player.body
	for config in [[false,0.0,2.2],[false,1.0,2.2],[false,0.0,4.0],[true,0.0,1.05],[true,1.0,1.05]]:
		var crouched: bool=config[0]
		for pitch in [-1.3,-0.7,0.0,0.7,1.3]:
			body.reset(0)
			body.weapon.equipped=true
			body.weapon.pitch=pitch
			body.weapon.aim=config[1]
			var error:=0.0
			for frame in 120:
				body.update_body(1.0/60,Vector3.ZERO,0,Vector3(0,0,-float(config[2])),crouched,false,true)
				if frame>60: error=maxf(error,maxf(body.weapon.right_error,body.weapon.left_error))
			check(error<0.06,"armed pose pitch %.1f crouch %s stays attached (%.3f m; R %.3f L %.3f)" % [pitch,str(crouched),error,body.weapon.right_error,body.weapon.left_error])
			check(maxf(body.weapon.first_right_error,body.weapon.first_left_error)<0.06,"first-person grips stay attached (R %.3f L %.3f)" % [body.weapon.first_right_error,body.weapon.first_left_error])
	body.weapon.equipped=false
	for frame in 60: body.update_body(1.0/60,Vector3.ZERO,0,Vector3.ZERO,false,true,true)
	check(not body.weapon.full.visible and not body.weapon.first.visible,"swimming stows gun and restores swim animation")
	var remote: Node3D=preload("res://scripts/remote_player.gd").new()
	root.add_child(remote)
	remote.set_process(false)
	remote.push_state([1,Vector3.ZERO,Vector3.ZERO,0.0,0.2,16|32|64,0.0,0])
	for frame in 60: remote._process(1.0/60)
	check(remote.body.weapon.full.visible and remote.body.weapon.full.get_child(1).layers==16,"remote armed snapshot renders full weapon on multiplayer layer")
	remote.play_action("shot",[Vector3.ZERO,Vector3.FORWARD])
	check(remote.body.weapon.recoil>0,"remote shot drives recoil")
	remote.play_action("reload",[])
	check(remote.body.weapon.reload_left>2,"remote reload drives hand and magazine animation")
	remote.free()
	player.free()
	print("WEAPON POSE FINISHED failures=",failures)
	quit(1 if failures else 0)
