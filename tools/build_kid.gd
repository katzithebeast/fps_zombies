extends SceneTree
## Postaví res://assets/zombie/types/kid.scn: model dítěte z kid_src.glb navázaný na zmenšenou
## mixamo kostru klasického zombie (stejné animace). Váhy podle vzdálenosti od kostí.
const DEFORM:=["Hips","Spine","Spine1","Spine2","Neck","Head","LeftShoulder","LeftArm","LeftForeArm","LeftHand","RightShoulder","RightArm","RightForeArm","RightHand",
	"LeftUpLeg","LeftLeg","LeftFoot","LeftToeBase","RightUpLeg","RightLeg","RightFoot","RightToeBase"]
func _initialize() -> void:
	call_deferred("run")
func gp(sk: Skeleton3D, b: int) -> Transform3D:
	return sk.get_bone_global_pose(b)
func run():
	var adult: Node3D=load("res://assets/zombie/zombie.fbx").instantiate(); root.add_child(adult)
	var ask: Skeleton3D=adult.get_node("Skeleton3D")
	var src: Node3D=load("res://assets/zombie/types/kid_src.glb").instantiate(); root.add_child(src)
	var smi: MeshInstance3D=null
	for m in src.find_children("*","MeshInstance3D",true,false):
		if (m.global_transform*m.get_aabb()).size.x<1.9: smi=m
	await process_frame
	var top:=ask.get_bone_global_rest(ask.find_bone("mixamorig_HeadTop_End")).origin
	const KID_H:=1.32
	var ms:=KID_H/1.54
	var k:=KID_H/top.y
	print("adult top ",top," k ",k, " skel xf ",ask.transform)
	# Kostra dítěte: kopie s posunutými klouby (rotace beze změny).
	var sk: Skeleton3D=ask.duplicate()
	var n:=sk.get_bone_count()
	var glob:=[]
	for b in n: glob.append(ask.get_bone_global_rest(b))
	for b in n:
		var p:=sk.get_bone_parent(b)
		var g: Transform3D=glob[b]
		g.origin*=k
		var local:Transform3D
		if p<0: local=g
		else:
			var pg: Transform3D=glob[p]; pg.origin*=k
			local=pg.affine_inverse()*g
		sk.set_bone_rest(b,local)
		sk.set_bone_pose(b,local)
	for c in sk.get_children(): c.free()
	var kid:=Node3D.new(); kid.name="Kid"
	root.add_child(kid)
	kid.add_child(sk); sk.owner=kid; sk.name="Skeleton3D"
	sk.transform=Transform3D.IDENTITY
	var ap:=AnimationPlayer.new(); ap.name="AnimationPlayer"; kid.add_child(ap); ap.owner=kid
	await process_frame
	# Vrcholy modelu ve prostoru kostry.
	var xf: Transform3D=Transform3D(Basis().scaled(Vector3.ONE*ms),Vector3.ZERO)*smi.global_transform
	var mesh: ArrayMesh=smi.mesh
	# Ruce: odhad úhlu A-pózy z modelu.
	var hand_y:=0.0; var hand_n:=0; var hand_x:=0.0
	var maxx:=0.0
	for s in mesh.get_surface_count():
		for v in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]: maxx=maxf(maxx,(xf*v).x)
	for s in mesh.get_surface_count():
		var arr=mesh.surface_get_arrays(s)
		for v in arr[Mesh.ARRAY_VERTEX]:
			var w: Vector3=xf*v
			if w.x>maxx*0.86: hand_y+=w.y; hand_x+=w.x; hand_n+=1
	hand_y/=maxf(hand_n,1); hand_x/=maxf(hand_n,1)
	for side in ["Left","Right"]:
		var arm:=sk.find_bone("mixamorig_%sArm"%side)
		var g:=sk.get_bone_global_pose(arm)
		var hand:=sk.get_bone_global_pose(sk.find_bone("mixamorig_%sHand"%side)).origin
		var sx:=signf(hand.x-g.origin.x)
		var target:=Vector3(sx*hand_x,hand_y,hand.z)
		var from_dir:=(hand-g.origin).normalized()
		var to_dir:=(target-g.origin).normalized()
		var q:=Quaternion(from_dir,to_dir)
		var newg:=Transform3D(Basis(q)*g.basis,g.origin)
		var pg:=sk.get_bone_global_pose(sk.get_bone_parent(arm))
		sk.set_bone_pose(arm,pg.affine_inverse()*newg)
		print(side," arm angle ",rad_to_deg(from_dir.angle_to(to_dir)))
	await process_frame
	var segs:=[]
	for nm in DEFORM:
		var b:=sk.find_bone("mixamorig_"+nm)
		if b<0: continue
		var a:=gp(sk,b).origin
		var kids:=sk.get_bone_children(b)
		var e:=a+gp(sk,b).basis.y.normalized()*0.08
		if nm=="Head": e=gp(sk,sk.find_bone("mixamorig_HeadTop_End")).origin
		elif nm=="Spine2": e=gp(sk,sk.find_bone("mixamorig_Neck")).origin
		elif nm in ["LeftShoulder","RightShoulder","Hips"]: e=a+(gp(sk,kids[0]).origin-a)*0.6 if kids.size()>0 else e
		elif kids.size()>0: e=gp(sk,kids[0]).origin
		if nm.ends_with("Hand"): e=a+(e-a).normalized()*0.09
		segs.append([b,a,e,nm])
	var out:=ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arr=mesh.surface_get_arrays(s)
		var verts: PackedVector3Array=arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array=arr[Mesh.ARRAY_NORMAL]
		var bones:=PackedInt32Array(); var weights:=PackedFloat32Array()
		for i in verts.size():
			var w: Vector3=xf*verts[i]
			verts[i]=w
			if norms.size()>i: norms[i]=(xf.basis*norms[i]).normalized()
			var best:=[]
			for sg in segs:
				var nm: String=sg[3]
				if nm.begins_with("Left") and w.x<-0.03: continue
				if nm.begins_with("Right") and w.x>0.03: continue
				var d:=Geometry3D.get_closest_point_to_segment(w,sg[1],sg[2]).distance_to(w)
				best.append([d,sg[0]])
			best.sort_custom(func(a,b): return a[0]<b[0])
			var tot:=0.0; var ws:=[]
			for j in 4:
				var wv:=1.0/pow(maxf(best[j][0],0.01),4.0) if j<best.size() else 0.0
				# jen kosti srovnatelně blízko té nejbližší
				if j>0 and best[j][0]>best[0][0]*1.8+0.02: wv=0.0
				ws.append(wv); tot+=wv
			for j in 4:
				bones.append(best[j][1] if j<best.size() else 0)
				weights.append(ws[j]/tot)
		var na:=[]; na.resize(Mesh.ARRAY_MAX)
		na[Mesh.ARRAY_VERTEX]=verts
		na[Mesh.ARRAY_NORMAL]=norms
		na[Mesh.ARRAY_TEX_UV]=arr[Mesh.ARRAY_TEX_UV]
		na[Mesh.ARRAY_INDEX]=arr[Mesh.ARRAY_INDEX]
		na[Mesh.ARRAY_BONES]=bones
		na[Mesh.ARRAY_WEIGHTS]=weights
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,na)
		out.surface_set_material(s,smi.get_active_material(s))
	var skin:=Skin.new()
	for b in sk.get_bone_count():
		skin.add_named_bind(sk.get_bone_name(b),gp(sk,b).affine_inverse())
	var mi:=MeshInstance3D.new(); mi.name="Body"; mi.mesh=out; mi.skin=skin
	sk.add_child(mi); mi.owner=kid
	mi.skeleton=NodePath("..")
	sk.reset_bone_poses()
	var ps:=PackedScene.new(); ps.pack(kid)
	print("save ",ResourceSaver.save(ps,"res://assets/zombie/types/kid.scn"))
	quit()
