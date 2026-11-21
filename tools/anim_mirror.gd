extends RefCounted
## Zrcadlení klipů zombie (tools/build_zombie.gd, tools/bake_getup.gd).
## Zrcadlení klipu přes svislou rovinu postavy (x -> -x): levá a pravá strana si vymění pohyb.
## Ve světových souřadnicích kostry: odchylku kosti od klidu zrcadlit a přenést na protějšek.
static func mirror(anim: Animation, sk: Skeleton3D) -> Animation:
	var M:=Basis(Vector3(-1,0,0),Vector3(0,1,0),Vector3(0,0,1))
	var n:=sk.get_bone_count()
	var rest_g:=[]
	for b in n: rest_g.append(sk.get_bone_global_rest(b).basis.orthonormalized())
	var partner:=[]
	for b in n:
		var nm:=sk.get_bone_name(b)
		var other:=nm.replace("Left","#").replace("Right","Left").replace("#","Right")
		var ob:=sk.find_bone(other)
		partner.append(ob if ob>=0 else b)
	var rot_track:={}
	var pos_track:=-1
	var times:={}
	for t in anim.get_track_count():
		var b:=sk.find_bone(String(anim.track_get_path(t)).get_slice(":",1))
		if anim.track_get_type(t)==Animation.TYPE_ROTATION_3D: rot_track[b]=t
		elif anim.track_get_type(t)==Animation.TYPE_POSITION_3D: pos_track=t
		for k in anim.track_get_key_count(t): times[snappedf(anim.track_get_key_time(t,k),0.0001)]=true
	var out:=Animation.new()
	out.length=anim.length
	out.loop_mode=anim.loop_mode
	for m in anim.get_meta_list(): out.set_meta(m,anim.get_meta(m))
	if anim.has_meta("root_motion"):
		# posun kořene taky zrcadlově
		var rm:=PackedVector3Array()
		for v in (anim.get_meta("root_motion") as PackedVector3Array): rm.append(Vector3(-v.x,v.y,v.z))
		out.set_meta("root_motion",rm)
	var new_tracks:={}
	var new_pos:=-1
	if pos_track>=0:
		new_pos=out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(new_pos,anim.track_get_path(pos_track))
	for b in rot_track:
		var tr:=out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(tr,NodePath("Skeleton3D:"+sk.get_bone_name(partner[b])))
		new_tracks[partner[b]]=tr
	var keys:=times.keys()
	keys.sort()
	for t in keys:
		# globální rotace z lokálních (kosti bez stopy drží klidovou rotaci)
		var g:=[]
		for b in n:
			var loc: Quaternion=anim.rotation_track_interpolate(rot_track[b],t) if rot_track.has(b) else sk.get_bone_rest(b).basis.get_rotation_quaternion()
			var p:=sk.get_bone_parent(b)
			g.append((g[p] as Basis)*Basis(loc) if p>=0 else Basis(loc))
		var gm:=[]
		gm.resize(n)
		for b in n:
			var src: int=partner[b]
			gm[b]=M*((g[src] as Basis)*(rest_g[src] as Basis).inverse())*M*(rest_g[b] as Basis)
		for b in new_tracks:
			var p:=sk.get_bone_parent(b)
			var lb: Basis=((gm[p] as Basis).inverse()*(gm[b] as Basis)) if p>=0 else gm[b]
			out.rotation_track_insert_key(new_tracks[b],t,lb.get_rotation_quaternion().normalized())
		if pos_track>=0:
			var v: Vector3=anim.position_track_interpolate(pos_track,t)
			out.position_track_insert_key(new_pos,t,Vector3(-v.x,v.y,v.z))
	return out
