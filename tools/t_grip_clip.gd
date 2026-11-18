extends SceneTree
## Kontrola průniků rukou do zbraní (distanční pole) v klidu, při přebíjení, kontrole zásobníku,
## sprintu a úderu. Vypíše největší průnik (mm) pro každou ruku a stav. Spouštění headless.
var player: Player
var rig: Node
func _initialize() -> void: call_deferred("run")
func tick(dt: float, inspect: float=-1.0, sprint: float=-1.0) -> void:
	player.weapon.update(dt)
	if inspect>=0.0: rig.inspect=inspect
	if sprint>=0.0: rig.sprint=sprint
	player.body.update_body(dt,Vector3.ZERO,0,Vector3.ZERO,false,false,true)
func probe(gun: String) -> Dictionary:
	var gs=rig.grip_solver
	var sk: Skeleton3D=gs.sk
	var to_gun: Transform3D=rig.full.transform.affine_inverse()
	var s=gs.sdf(gun)
	var xf:={}
	for part in ["Magazine","Barrel"]:
		var n: Node3D=rig._part(rig.full,part)
		if n and n.visible: xf[part.to_lower()]=n.transform
		elif n: xf[part.to_lower()]=Transform3D(Basis(),Vector3(0,-50,0))
	var out:={}
	for side in ["Right","Left"]:
		var worst:=[0.0,""]
		var h: Transform3D=sk.get_bone_global_pose(sk.find_bone("mixamorig_%sHand"%side))
		var hd: Dictionary=gs.hand(side)
		var pts:=[[h.origin,0.018,"zápěstí"],[h*(hd.palm as Vector3),0.0,"dlaň"]]
		for ch in gs.chains(side):
			for j in 3:
				var g:=sk.get_bone_global_pose(ch.bones[j])
				var b: Vector3=g*(ch.tip as Vector3) if j==2 else sk.get_bone_global_pose(ch.bones[j+1]).origin
				for t in [0.5,1.0]: pts.append([g.origin.lerp(b,t),gs.finger_r*0.75,"%s%d"%[ch.name,j+1]])
		for e in pts:
			var d: float=s.distance(to_gun*(e[0] as Vector3),xf)
			var pen: float=float(e[1])-d
			if pen>worst[0]: worst=[pen,e[2]]
		out[side]=worst
	return out
func run() -> void:
	player=Player.new(); root.add_child(player); player.set_process(false); player.set_physics_process(false)
	player.body.reset(0)
	rig=player.body.weapon
	var w: Node=player.weapon
	var bad:=0
	for gun in ["ak","mp40","deagle","izh54"]:
		w.give(gun,false); w.switch_to(gun,true)
		for i in 90: tick(1.0/60.0)
		var res:={}
		var cnt:={}
		var tot:={}
		var acc:=func(state: String) -> void:
			var p: Dictionary=probe(gun)
			for side in p:
				var key: String=state+":"+str(side)
				if not res.has(key) or float(p[side][0])>float(res[key][0]): res[key]=p[side]
				if float(p[side][0])>0.005: cnt[key]=int(cnt.get(key,0))+1
				tot[key]=int(tot.get(key,0))+1
		for i in 30:
			tick(1.0/60.0); acc.call("klid")
		w.ammo=0
		w.reload()
		var n:=int(rig.reload_time*60.0)+20
		for i in n:
			tick(1.0/60.0); acc.call("přebíjení")
			if OS.get_environment("TRACE")==gun:
				var p: Dictionary=probe(gun)
				var lh: Vector3=rig.full.transform.affine_inverse()*rig.bone_pose(10).origin
				print("  f%3d fáze %.2f blend %.2f L %.1f mm (%s) R %.1f mm (%s) levé zápěstí %s chyba L %.1f" % [i,1.0-rig.reload_left/rig.reload_time,rig._left_free,float(p.Left[0])*1000,p.Left[1],float(p.Right[0])*1000,p.Right[1],lh,rig.left_error*1000])
		for i in 50:
			tick(1.0/60.0,minf(1.0,i/20.0)); acc.call("kontrola")
		for i in 30: tick(1.0/60.0,0.0)
		for i in 50:
			tick(1.0/60.0,0.0,minf(1.0,i/15.0)); acc.call("sprint")
		for i in 30: tick(1.0/60.0,0.0,0.0)
		var line:="%s:" % gun
		for k in res:
			var v: Array=res[k]
			line+="  %s %.1f mm (%s, %d/%d snímků)" % [k,float(v[0])*1000.0,v[1],int(cnt.get(k,0)),int(tot.get(k,0))] if float(v[0])>0.0005 else "  %s ok" % k
			if float(v[0])>0.004: bad+=1
		print(line)
	print("průniky nad 4 mm: ",bad)
	quit()
