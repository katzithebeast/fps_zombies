extends SceneTree
## Zápěstí a předloktí v první osobě: ohyb zápěstí (úhel předloktí–dlaň, rozdělený na
## ohnutí dlaní / hřbetem a vychýlení do strany), zbylé zkroucení v zápěstí a zkroucení předloktí.
## Pro každou zbraň a stav vypíše nejhorší hodnoty. Spouštění headless:
##   godot --headless --path . --script res://tools/t_wrist.gd      (GUNS=ak,izh54)
var player: Player
var rig: Node

func _initialize() -> void: call_deferred("run")

func tick(dt: float, inspect:=-1.0, sprint:=-1.0) -> void:
	player.weapon.update(dt)
	if inspect>=0.0: rig.inspect=inspect
	if sprint>=0.0: rig.sprint=sprint
	player.body.update_body(dt,Vector3.ZERO,0,Vector3.ZERO,false,false,true)

static func twist(q: Quaternion) -> float:
	var p:=Vector3(q.x,q.y,q.z).project(Vector3.UP)
	var t:=Quaternion(p.x,p.y,p.z,q.w)
	if t.length_squared()<1e-9: return 0.0
	t=t.normalized()
	var a:=2.0*atan2(Vector3(t.x,t.y,t.z).length(),t.w)
	if Vector3(t.x,t.y,t.z).dot(Vector3.UP)<0.0: a=-a
	return rad_to_deg(wrapf(a,-PI,PI))

## [ohyb celkem, ohnutí (+ dlaní / - hřbetem), vychýlení do strany, zkrut v zápěstí, zkrut předloktí, loket]
func measure(side: String) -> Array:
	var sk: Skeleton3D=rig.avatar.first_skeleton if OS.get_environment("TP")=="" else rig.avatar.skeleton
	var up:=sk.find_bone("mixamorig_%sArm"%side)
	var fa:=sk.find_bone("mixamorig_%sForeArm"%side)
	var ha:=sk.find_bone("mixamorig_%sHand"%side)
	var mid:=sk.find_bone("mixamorig_%sHandMiddle1"%side)
	var gu:=sk.get_bone_global_pose(up)
	var gf:=sk.get_bone_global_pose(fa)
	var gh:=sk.get_bone_global_pose(ha)
	var gm:=sk.get_bone_global_pose(mid)
	var F:=(gh.origin-gf.origin).normalized()
	var H:=(gm.origin-gh.origin).normalized()
	# normála dlaně: osa Z kosti ruky v klidové póze je kolmá na dlaň (u Mixama hřbet/dlaň)
	var N:=gh.basis.orthonormalized().z
	var hp:=H-F*H.dot(F)
	var S:=F.cross(N).normalized()
	var Np:=(N-F*N.dot(F)).normalized()
	var flex:=rad_to_deg(atan2(hp.dot(Np),H.dot(F)))
	var dev:=rad_to_deg(atan2(hp.dot(S),H.dot(F)))
	var wq:=sk.get_bone_rest(ha).basis.get_rotation_quaternion().inverse()*sk.get_bone_pose_rotation(ha)
	var fq:=sk.get_bone_rest(fa).basis.get_rotation_quaternion().inverse()*sk.get_bone_pose_rotation(fa)
	var elbow:=rad_to_deg((gf.origin-gu.origin).angle_to(gh.origin-gf.origin))
	return [rad_to_deg(F.angle_to(H)),flex,dev,twist(wq),twist(fq),elbow]

var worst:={}
func rec(state: String) -> void:
	for side in ["Right","Left"]:
		var m: Array=measure(side)
		var key: String=state+":"+side
		if not worst.has(key) or absf(m[0])>absf(worst[key][0]): worst[key]=m

func run() -> void:
	player=Player.new(); root.add_child(player); player.set_process(false); player.set_physics_process(false)
	rig=player.body.weapon
	var w: Node=player.weapon
	var guns:=OS.get_environment("GUNS").split(",") if OS.get_environment("GUNS")!="" else PackedStringArray(["ak","mp40","izh54","deagle"])
	for g in w.ORDER: w.give(g,false)
	for gun in guns:
		worst={}
		w.switch_to(gun,true)
		for i in 90: tick(1.0/60.0)
		rec("klid")
		w.test_aim=true
		for i in 60: tick(1.0/60.0)
		rec("míření")
		w.test_aim=false
		for i in 40: tick(1.0/60.0)
		for i in 40:
			tick(1.0/60.0,-1.0,1.0)
			if i>25: rec("sprint")
		for i in 40: tick(1.0/60.0,-1.0,0.0)
		w.ammo=0; w.reload()
		while float(w.reload_left)>0.0:
			tick(1.0/60.0)
			rec("přebíjení")
		for i in 40: tick(1.0/60.0)
		for i in 50:
			tick(1.0/60.0,1.0)
			if i>30: rec("kontrola")
		for i in 40: tick(1.0/60.0,0.0)
		w.test_examine=true
		for i in 420:
			tick(1.0/60.0)
			if i>60: rec("prohlídka")
		w.test_examine=false
		for i in 60: tick(1.0/60.0)
		var line:="%s:"%gun
		for st in ["klid","míření","sprint","přebíjení","kontrola","prohlídka"]:
			for side in ["Right","Left"]:
				var m: Array=worst.get(st+":"+side,[])
				if m.is_empty(): continue
				line+="\n  %-10s %s  ohyb %5.1f° (dlaň %+5.1f, stranou %+5.1f)  zkrut zápěstí %+6.1f°  předloktí %+6.1f°  loket %5.1f°" % [st,"P" if side=="Right" else "L",m[0],m[1],m[2],m[3],m[4],m[5]]
		print(line)
	quit()
