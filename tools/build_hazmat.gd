extends SceneTree
## Spuštění: Godot --headless --path . --script res://tools/build_hazmat.gd
## Hazmat oblek (kostra UE5 Manny) převlékne na kostru scientisty (Mixamo, 41 kostí, stejné
## indexy i natočení kostí), klouby posune do pozic obleku. Díky tomu dál fungují všechny
## animace, IK paží se zbraní i vlastní pohled. Výstup: assets/hazmat/
const OUT := "res://assets/hazmat/"
const SCI := "res://assets/scientist/"
const CUT_ABOVE_SHOULDER := 0.04 # řez pro vlastní pohled: těsně nad rameny (kukla je široká, víčko pod hlavou by zakrylo výhled)
# UE kost → Mixamo kost (váhy). Prostředníček, prsteníček a malíček mají vlastní kosti
# (přidané na konec kostry, indexy 41+), scientist má jen palec a ukazovák.
const WEIGHT_MAP := {
	"pelvis":"Hips","spine_01":"Spine","spine_02":"Spine","spine_03":"Spine1","spine_04":"Spine2","spine_05":"Spine2",
	"neck_01":"Neck","neck_02":"Neck","head":"Head",
	"clavicle_X":"XShoulder","upperarm_X":"XArm","upperarm_twist_01_X":"XArm","upperarm_twist_02_X":"XArm",
	"lowerarm_X":"XForeArm","lowerarm_twist_01_X":"XForeArm","lowerarm_twist_02_X":"XForeArm","hand_X":"XHand",
	"thumb_01_X":"XHandThumb1","thumb_02_X":"XHandThumb2","thumb_03_X":"XHandThumb3",
	"index_metacarpal_X":"XHand","middle_metacarpal_X":"XHand","ring_metacarpal_X":"XHand","pinky_metacarpal_X":"XHand",
	"index_01_X":"XHandIndex1","index_02_X":"XHandIndex2","index_03_X":"XHandIndex3",
	"middle_01_X":"XHandMiddle1","middle_02_X":"XHandMiddle2","middle_03_X":"XHandMiddle3",
	"ring_01_X":"XHandRing1","ring_02_X":"XHandRing2","ring_03_X":"XHandRing3",
	"pinky_01_X":"XHandPinky1","pinky_02_X":"XHandPinky2","pinky_03_X":"XHandPinky3",
	"thigh_X":"XUpLeg","thigh_twist_01_X":"XUpLeg","thigh_twist_02_X":"XUpLeg",
	"calf_X":"XLeg","calf_twist_01_X":"XLeg","calf_twist_02_X":"XLeg","foot_X":"XFoot","ball_X":"XToeBase",
}
# Mixamo kloub → UE kloub (pozice)
const JOINT_MAP := {
	"Hips":"pelvis","Spine":"spine_01","Spine1":"spine_03","Spine2":"spine_04","Neck":"neck_01","Head":"head",
	"XShoulder":"clavicle_X","XArm":"upperarm_X","XForeArm":"lowerarm_X","XHand":"hand_X",
	"XHandThumb1":"thumb_01_X","XHandThumb2":"thumb_02_X","XHandThumb3":"thumb_03_X",
	"XHandIndex1":"index_01_X","XHandIndex2":"index_02_X","XHandIndex3":"index_03_X",
	"XHandMiddle1":"middle_01_X","XHandMiddle2":"middle_02_X","XHandMiddle3":"middle_03_X",
	"XHandRing1":"ring_01_X","XHandRing2":"ring_02_X","XHandRing3":"ring_03_X",
	"XHandPinky1":"pinky_01_X","XHandPinky2":"pinky_02_X","XHandPinky3":"pinky_03_X",
	"XUpLeg":"thigh_X","XLeg":"calf_X","XFoot":"foot_X","XToeBase":"ball_X",
}
const EXTRA_FINGERS := ["Middle","Ring","Pinky"]
# Kosti, které se přepózují do směru scientisty: kost → kloub, ke kterému míří
const AIM := {"Spine":"Spine1","Spine1":"Spine2","Spine2":"Neck","Neck":"Head",
	"XShoulder":"XArm","XArm":"XForeArm","XForeArm":"XHand","XHand":"XHandIndex1",
	"XUpLeg":"XLeg","XLeg":"XFoot","XFoot":"XToeBase"}

var hz: Skeleton3D
var fix := Transform3D.IDENTITY   # UE prostor obleku → prostor kostry scientisty

func expand(table: Dictionary) -> Dictionary:
	var out := {}
	for k in table:
		var v: String = table[k]
		var side_key: bool = k.ends_with("_X") or k.begins_with("X")
		if not side_key:
			out[k] = v
			continue
		for side in [["l","Left"],["r","Right"]]:
			var kk: String = k.replace("_X","_"+side[0]) if k.ends_with("_X") else side[1]+k.substr(1)
			var vv: String = v.replace("_X","_"+side[0]) if v.ends_with("_X") else (side[1]+v.substr(1) if v.begins_with("X") else v)
			out[kk] = vv
	return out

func arc(from: Vector3, to: Vector3) -> Basis:
	var a := from.normalized()
	var b := to.normalized()
	var axis := a.cross(b)
	if axis.length_squared() < 1e-10: return Basis.IDENTITY
	return Basis(axis.normalized(), a.angle_to(b))

## Rotace, která převede dvojici směrů (hlavní přesně, vedlejší co nejblíž) z a na b.
func align2(a_main: Vector3, a_side: Vector3, b_main: Vector3, b_side: Vector3) -> Basis:
	var r1 := arc(a_main, b_main)
	var s1 := r1 * a_side
	var m := b_main.normalized()
	var sa := (s1 - m * s1.dot(m))
	var sb := (b_side - m * b_side.dot(m))
	if sa.length_squared() < 1e-8 or sb.length_squared() < 1e-8: return r1
	var ang := sa.signed_angle_to(sb, m)
	return Basis(m, ang) * r1

## Normála dlaně z vrcholů ruky (nejmenší rozptyl = kolmo na plochou dlaň), otočená k palci.
func palm_normal(points: Array, thumb_tip: Vector3) -> Vector3:
	var c := Vector3.ZERO
	for v in points: c += v
	c /= float(points.size())
	var thumb_dir := thumb_tip - c
	var cov := [[0.0,0.0,0.0],[0.0,0.0,0.0],[0.0,0.0,0.0]]
	for v in points:
		var d: Vector3 = v - c
		for i in 3:
			for j in 3: cov[i][j] += d[i] * d[j]
	# nejmenší vlastní vektor: mocninná metoda na (tr*I - C)
	var tr: float = cov[0][0] + cov[1][1] + cov[2][2]
	var x := Vector3(0.3, 0.5, 0.8)
	for it in 80:
		var y := Vector3.ZERO
		for i in 3:
			var acc := tr * x[i]
			for j in 3: acc -= cov[i][j] * x[j]
			y[i] = acc
		x = y.normalized()
	return x if x.dot(thumb_dir) >= 0.0 else -x

func sci_palms(ss: Skeleton3D, mesh_inst: MeshInstance3D) -> Dictionary:
	var data := mesh_inst.mesh.surface_get_arrays(0)
	var xf := ss.get_bone_global_rest(ss.find_bone(mesh_inst.skin.get_bind_name(0))) * mesh_inst.skin.get_bind_pose(0)
	var out := {}
	for side in ["Left","Right"]:
		var ids := {}
		for b in mesh_inst.skin.get_bind_count():
			var nm := String(mesh_inst.skin.get_bind_name(b))
			if nm == "mixamorig_%sHand" % side or nm.begins_with("mixamorig_%sHandIndex" % side): ids[b] = true
		var pts := []
		var vv: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
		var bb: PackedInt32Array = data[Mesh.ARRAY_BONES]
		var ww: PackedFloat32Array = data[Mesh.ARRAY_WEIGHTS]
		var per := bb.size() / vv.size()
		for i in vv.size():
			var w := 0.0
			for j in per:
				if ids.has(bb[i*per+j]): w += ww[i*per+j]
			if w > 0.6: pts.append(xf * vv[i])
		var tip := ss.get_bone_global_rest(ss.find_bone("mixamorig_%sHandThumb4" % side)).origin
		out[side] = palm_normal(pts, tip)
		var hand_pts := []
		var hb := -1
		for b in mesh_inst.skin.get_bind_count():
			if String(mesh_inst.skin.get_bind_name(b)) == "mixamorig_%sHand" % side: hb = b
		for i in vv.size():
			var w := 0.0
			for j in per:
				if bb[i*per+j] == hb: w += ww[i*per+j]
			if w > 0.6: hand_pts.append(xf * vv[i])
		var c := Vector3.ZERO
		for v in hand_pts: c += v
		c /= float(maxi(1, hand_pts.size()))
		out[side + "_center"] = ss.get_bone_global_rest(ss.find_bone("mixamorig_%sHand" % side)).affine_inverse() * c
		var hrest := ss.get_bone_global_rest(ss.find_bone("mixamorig_%sHand" % side))
		var ib := ss.get_bone_global_rest(ss.find_bone("mixamorig_%sHandIndex1" % side)).basis.orthonormalized()
		var palm_local := hrest.basis.orthonormalized().inverse() * ib.x.cross(ib.y).normalized()
		var ext := -1.0
		for v in hand_pts: ext = maxf(ext, (hrest.affine_inverse() * v).dot(palm_local))
		out[side + "_palm_local"] = palm_local
		out[side + "_palm_ext"] = ext
		var cloud := []
		var fam := {}
		for b in mesh_inst.skin.get_bind_count():
			var nm2 := String(mesh_inst.skin.get_bind_name(b))
			if nm2 == "mixamorig_%sHand" % side or nm2.begins_with("mixamorig_%sHandThumb" % side): fam[b] = true
		for i in vv.size():
			var w := 0.0
			for j in per:
				if fam.has(bb[i*per+j]): w += ww[i*per+j]
			if w > 0.6: cloud.append(hrest.affine_inverse() * (xf * vv[i]))
		out[side + "_cloud"] = cloud
		print(side, " dlaň scientist: ", pts.size(), " vrcholů, normála ", out[side])
	return out

func sub(a: Array, n: int) -> Array:
	if a.size() <= n: return a
	var out := []
	var step := float(a.size()) / float(n)
	for k in n: out.append(a[int(k * step)])
	return out

func centroid(a: Array) -> Vector3:
	var c := Vector3.ZERO
	for v in a: c += v
	return c / float(maxi(1, a.size()))

func _initialize() -> void:
	var sci_scene: Node3D = load(SCI + "ScientistRigged.fbx").instantiate()
	root.add_child(sci_scene)
	var ss: Skeleton3D = sci_scene.get_node("Skeleton3D")
	var hz_scene: Node3D = load(OUT + "SKM_HazmatSuit.fbx").instantiate()
	root.add_child(hz_scene)
	hz = hz_scene.get_node("Skeleton3D")
	var src: MeshInstance3D = hz.get_node("HazmatSuit")
	var sci_palm := sci_palms(ss, ss.get_node("ScientistBody"))
	var basis := Basis.IDENTITY
	var raw_fwd := hz.get_bone_global_rest(hz.find_bone("ball_l")).origin - hz.get_bone_global_rest(hz.find_bone("foot_l")).origin
	raw_fwd.y = 0.0
	if absf(raw_fwd.x) > absf(raw_fwd.z): basis = Basis(Vector3.UP, -signf(raw_fwd.x) * PI * 0.5)
	elif raw_fwd.z < 0.0: basis = Basis(Vector3.UP, PI)
	assert((basis * (hz.get_bone_global_rest(hz.find_bone("upperarm_l")).origin - hz.get_bone_global_rest(hz.find_bone("upperarm_r")).origin)).x > 0.0)
	var sci_head := ss.get_bone_global_rest(ss.find_bone("mixamorig_Head")).origin
	var s := sci_head.y / (basis * hz.get_bone_global_rest(hz.find_bone("head")).origin).y
	fix = Transform3D(basis.scaled(Vector3.ONE * s), Vector3.ZERO)
	var jm := expand(JOINT_MAP)
	var wm := expand(WEIGHT_MAP)
	var aim := expand(AIM)
	# --- seznam kostí: scientist (0..40) + další prsty
	var names: Array[String] = []
	var parents: Array[int] = []
	for i in ss.get_bone_count():
		names.append(ss.get_bone_name(i))
		parents.append(ss.get_bone_parent(i))
	for side in ["Left","Right"]:
		var hand := names.find("mixamorig_%sHand" % side)
		for f in EXTRA_FINGERS:
			for k in [1,2,3]:
				names.append("mixamorig_%sHand%s%d" % [side, f, k])
				parents.append(hand if k == 1 else names.size() - 2)
	var count := names.size()
	var idx := func(short: String) -> int: return names.find("mixamorig_" + short)
	# klouby obleku (prostor scientisty, před přepózováním)
	var p: Array[Vector3] = []
	p.resize(count)
	var have: Array[bool] = []
	have.resize(count)
	for i in count:
		var short := names[i].trim_prefix("mixamorig_")
		if jm.has(short):
			p[i] = fix * hz.get_bone_global_rest(hz.find_bone(jm[short])).origin
			have[i] = true
	# koncové kosti
	var bind_xf := hz.get_bone_global_rest(hz.find_bone(src.skin.get_bind_name(0))) * src.skin.get_bind_pose(0)
	var vdata := src.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = vdata[Mesh.ARRAY_VERTEX]
	var top := -100.0
	for v in verts: top = maxf(top, (fix * bind_xf * v).y)
	for i in count:
		if have[i]: continue
		var short := names[i].trim_prefix("mixamorig_")
		var par := parents[i]
		if short == "HeadTop_End": p[i] = Vector3(p[par].x, top, p[par].z)
		elif short.ends_with("Toe_End"):
			var sd := ss.get_bone_global_rest(i).origin - ss.get_bone_global_rest(par).origin
			p[i] = p[par] + sd
		else: p[i] = p[par] + (p[par] - p[parents[par]]) * 0.85
		have[i] = true
	# dlaň obleku (původní prostor): vrcholy ruky a prstů kromě palce
	var hz_palm_pts := {"Left": [], "Right": []}
	var hz_cloud := {"Left": [], "Right": []}
	var grip_fit := {}
	var hb_names: Array[String] = []
	for b in src.skin.get_bind_count(): hb_names.append(String(src.skin.get_bind_name(b)))
	var hb_bones: PackedInt32Array = vdata[Mesh.ARRAY_BONES]
	var hb_w: PackedFloat32Array = vdata[Mesh.ARRAY_WEIGHTS]
	var hper := hb_bones.size() / verts.size()
	for vi in verts.size():
		for side in [["l","Left"],["r","Right"]]:
			var w := 0.0
			for j in hper:
				var nm := hb_names[hb_bones[vi*hper+j]]
				if nm.ends_with("_" + side[0]) and (nm.begins_with("hand") or "metacarpal" in nm or nm.begins_with("index") or nm.begins_with("middle") or nm.begins_with("ring") or nm.begins_with("pinky")):
					w += hb_w[vi*hper+j]
			if w > 0.6: hz_palm_pts[side[1]].append(fix * bind_xf * verts[vi])
			var w2 := 0.0
			for j in hper:
				var nm := hb_names[hb_bones[vi*hper+j]]
				if nm.ends_with("_" + side[0]) and (nm.begins_with("hand") or "metacarpal" in nm or nm.begins_with("thumb")):
					w2 += hb_w[vi*hper+j]
			if w2 > 0.6: hz_cloud[side[1]].append(fix * bind_xf * verts[vi])
	# --- přepózování obleku do pózy scientisty (rotace v kloubech, FK)
	var R: Array[Basis] = []
	var q: Array[Vector3] = []
	R.resize(count)
	q.resize(count)
	var sci_pos := func(i: int) -> Vector3: return ss.get_bone_global_rest(i).origin
	for i in count:
		var par := parents[i]
		var Rp: Basis = R[par] if par >= 0 else Basis.IDENTITY
		q[i] = (q[par] + Rp * (p[i] - p[par])) if par >= 0 else p[i]
		R[i] = Rp
		var short := names[i].trim_prefix("mixamorig_")
		if not aim.has(short): continue
		var c: int = idx.call(aim[short])
		var d_now := Rp * (p[c] - p[i])
		var d_sci: Vector3 = sci_pos.call(c) - sci_pos.call(i)
		var A := arc(d_now, d_sci)
		if short.ends_with("Hand"):
			# ruka: natočení kolem osy ruky a posun, při kterých dlaň s palcem nejlépe překryje
			# dlaň s palcem scientisty (na jeho ruku jsou odladěné všechny úchopy zbraní)
			var side := "Left" if short.begins_with("Left") else "Right"
			var B := ss.get_bone_global_rest(i).basis.orthonormalized()
			var sci_cloud: Array = sub(sci_palm[side + "_cloud"], 160)
			var sc_c := centroid(sci_cloud)
			var hz_pts: Array = sub(hz_cloud[side], 160)
			var base_rot := arc(d_now, d_sci) * Rp
			var best := INF
			var best_A := arc(d_now, d_sci)
			var best_off := Vector3.ZERO
			for deg in range(-180, 180, 5):
				var Arot := Basis(d_sci.normalized(), deg_to_rad(deg)) * arc(d_now, d_sci)
				var Rh := Arot * Rp
				var L := []
				for v in hz_pts: L.append(B.inverse() * (Rh * (v - p[i])))
				var lc := centroid(L)
				var err := 0.0
				for v in L:
					var md := INF
					var vv: Vector3 = v - lc + sc_c
					for t in sci_cloud: md = minf(md, vv.distance_squared_to(t))
					err += md
				for t in sci_cloud:
					var md := INF
					for v in L: md = minf(md, (v - lc + sc_c).distance_squared_to(t))
					err += md
				if err < best:
					best = err
					best_A = Arot
					best_off = lc - sc_c
			A = best_A
			grip_fit[side] = best_off
			print(side, " ruka: nejlepší překryv ", sqrt(best / 320.0) * 100.0, " cm, posun ", best_off)
		R[i] = A * Rp
	# --- váhy UE → nové kosti a přepózované vrcholy
	var bind_names: Array[String] = []
	for b in src.skin.get_bind_count(): bind_names.append(String(src.skin.get_bind_name(b)))
	var norms: PackedVector3Array = vdata[Mesh.ARRAY_NORMAL]
	var tans: PackedFloat32Array = vdata[Mesh.ARRAY_TANGENT] if vdata[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var bones_in: PackedInt32Array = vdata[Mesh.ARRAY_BONES]
	var weights_in: PackedFloat32Array = vdata[Mesh.ARRAY_WEIGHTS]
	var per := bones_in.size() / verts.size()
	var nb := (fix * bind_xf).basis.orthonormalized()
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_t := PackedFloat32Array()
	var out_b := PackedInt32Array()
	var out_w := PackedFloat32Array()
	for vi in verts.size():
		var acc := {}
		for j in per:
			var w := weights_in[vi*per+j]
			if w <= 0.00001: continue
			var target: String = wm.get(bind_names[bones_in[vi*per+j]], "")
			if target == "": continue
			var bi: int = idx.call(target)
			acc[bi] = float(acc.get(bi, 0.0)) + w
		var keys: Array = acc.keys()
		keys.sort_custom(func(a, b): return acc[a] > acc[b])
		var total := 0.0
		for k in mini(8, keys.size()): total += acc[keys[k]]
		var v0 := fix * bind_xf * verts[vi]
		var n0 := (nb * norms[vi]).normalized()
		var t0 := Vector3.ZERO
		if tans.size() >= (vi + 1) * 4: t0 = (nb * Vector3(tans[vi*4], tans[vi*4+1], tans[vi*4+2])).normalized()
		var v1 := Vector3.ZERO
		var n1 := Vector3.ZERO
		var t1 := Vector3.ZERO
		for k in 8:
			if k < keys.size():
				var bi: int = keys[k]
				var w: float = acc[bi] / maxf(total, 0.00001)
				v1 += (R[bi] * (v0 - p[bi]) + q[bi]) * w
				n1 += (R[bi] * n0) * w
				t1 += (R[bi] * t0) * w
				out_b.append(bi)
				out_w.append(w)
			else:
				out_b.append(0)
				out_w.append(0.0)
		out_v.append(v1)
		out_n.append(n1.normalized())
		if tans.size() >= (vi + 1) * 4:
			var tt := t1.normalized()
			out_t.append_array(PackedFloat32Array([tt.x, tt.y, tt.z, tans[vi*4+3]]))
	# --- nová kostra: natočení scientisty, klouby přepózovaného obleku; prsty natočené podél sebe
	var globals: Array[Transform3D] = []
	globals.resize(count)
	for i in count:
		var short := names[i].trim_prefix("mixamorig_")
		var b: Basis
		if i < ss.get_bone_count(): b = ss.get_bone_global_rest(i).basis.orthonormalized()
		else:
			# další prst: natočení jako odpovídající článek ukazováku
			var lvl := short.right(1)
			var side := "Left" if short.begins_with("Left") else "Right"
			b = ss.get_bone_global_rest(idx.call(side + "HandIndex" + lvl)).basis.orthonormalized()
		var is_finger := ("HandThumb" in short or "HandIndex" in short or "HandMiddle" in short or "HandRing" in short or "HandPinky" in short)
		if is_finger:
			# osa Y podél prstu (ohyb kolem X jako u scientisty)
			var child := -1
			for j in count:
				if parents[j] == i: child = j; break
			var dir: Vector3 = (q[child] - q[i]) if child >= 0 else (q[i] - q[parents[i]])
			b = arc(b * Vector3.UP, dir) * b
		globals[i] = Transform3D(b, q[i])
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	# posun středu dlaně proti scientistovi (v souřadnicích ruky) → cíl zápěstí v IK
	for side in ["Left","Right"]:
		sk.set_meta("grip_offset_" + side, grip_fit[side])
	# střed povrchu dlaně (souřadnice kosti ruky) a tloušťka prstu: pro úchop zbraní (scripts/hand_grip.gd)
	for side in ["Left","Right"]:
		var hi: int = idx.call(side + "Hand")
		var G := globals[hi]
		var Gi := G.affine_inverse()
		var ib := globals[idx.call(side + "HandIndex1")].basis.orthonormalized()
		var n := (G.basis.orthonormalized().inverse() * ib.x.cross(ib.y)).normalized()
		var pts := []
		for vi in out_v.size():
			var w := 0.0
			for j in 8:
				if out_b[vi*8+j] == hi: w += out_w[vi*8+j]
			if w > 0.6: pts.append(Gi * out_v[vi])
		var c := centroid(pts)
		var dmax := 0.0
		for v in pts: dmax = maxf(dmax, (v - c).dot(n))
		var layer := []
		for v in pts:
			if (v - c).dot(n) > 0.6 * dmax: layer.append(v)
		var palm := centroid(layer)
		sk.set_meta("palm_point_" + side, palm)
		print(side, " povrch dlaně ", palm, " (", layer.size(), " vrcholů)")
	var m2: int = idx.call("RightHandMiddle2")
	var m3: int = idx.call("RightHandMiddle3")
	var dists := []
	for vi in out_v.size():
		var w := 0.0
		for j in 8:
			if out_b[vi*8+j] == m2: w += out_w[vi*8+j]
		if w > 0.7:
			var a2 := q[m2]
			var ab := q[m3] - a2
			var t := clampf((out_v[vi] - a2).dot(ab) / ab.length_squared(), 0.0, 1.0)
			dists.append(out_v[vi].distance_to(a2 + ab * t))
	dists.sort()
	var fr: float = float(dists[dists.size() / 2]) * 0.86 if dists.size() > 0 else 0.0095
	sk.set_meta("finger_radius", fr)
	print("poloměr prstu ", fr * 1000.0, " mm")
	var bend := func(a: Vector3, b: Vector3, c: Vector3) -> float: return (b - a).angle_to(c - b)
	var sci_bend: float = bend.call(ss.get_bone_global_rest(idx.call("RightHandIndex1")).origin, ss.get_bone_global_rest(idx.call("RightHandIndex2")).origin, ss.get_bone_global_rest(idx.call("RightHandIndex3")).origin)
	var hz_bend: float = bend.call(q[idx.call("RightHandIndex1")], q[idx.call("RightHandIndex2")], q[idx.call("RightHandIndex3")])
	sk.set_meta("finger_curl_boost", clampf(sci_bend - hz_bend, 0.0, 0.6))
	print("pokrčení prstů scientist ", rad_to_deg(sci_bend), "° oblek ", rad_to_deg(hz_bend), "°")
	for i in count:
		sk.add_bone(names[i])
		sk.set_bone_parent(i, parents[i])
	for i in count:
		var local := globals[i] if parents[i] < 0 else globals[parents[i]].affine_inverse() * globals[i]
		sk.set_bone_rest(i, local)
		sk.set_bone_pose(i, local)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out_v
	arrays[Mesh.ARRAY_NORMAL] = out_n
	if out_t.size() == out_v.size() * 4: arrays[Mesh.ARRAY_TANGENT] = out_t
	arrays[Mesh.ARRAY_TEX_UV] = vdata[Mesh.ARRAY_TEX_UV]
	arrays[Mesh.ARRAY_BONES] = out_b
	arrays[Mesh.ARRAY_WEIGHTS] = out_w
	arrays[Mesh.ARRAY_INDEX] = vdata[Mesh.ARRAY_INDEX]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/hazmat.gdshader")
	mat.set_shader_parameter("albedo_tex", load(OUT + "hazmat_albedo.png"))
	mat.set_shader_parameter("normal_tex", load(OUT + "hazmat_normal.png"))
	mat.set_shader_parameter("orm_tex", load(OUT + "hazmat_orm.png"))
	mat.set_shader_parameter("grime_tex", load(OUT + "hazmat_grime.png"))
	assert(ResourceSaver.save(mat, OUT + "hazmat_material.tres") == OK)
	mat = load(OUT + "hazmat_material.tres")
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	mesh.surface_set_material(0, mat)
	var skin := Skin.new()
	for i in count: skin.add_named_bind(names[i], globals[i].affine_inverse())
	assert(ResourceSaver.save(mesh, OUT + "hazmat_body.res") == OK)
	assert(ResourceSaver.save(skin, OUT + "hazmat_skin.res") == OK)
	var model := Node3D.new()
	model.name = "Hazmat"
	model.add_child(sk)
	sk.owner = model
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = load(OUT + "hazmat_body.res")
	mi.skin = load(OUT + "hazmat_skin.res")
	mi.skeleton = NodePath("..")
	sk.add_child(mi)
	mi.owner = model
	var packed := PackedScene.new()
	packed.pack(model)
	assert(ResourceSaver.save(packed, OUT + "hazmat_player.tscn") == OK)
	# --- animace: rotace beze změny (stejná natočení kostí), u prstů převod přes klidovou pózu;
	# posuny = délky kostí obleku, pánev úměrně výšce
	var lib: AnimationLibrary = (load(SCI + "locomotion.res") as AnimationLibrary).duplicate(true)
	var hips := ss.find_bone("mixamorig_Hips")
	var sci_hips := ss.get_bone_rest(hips).origin
	var new_hips := sk.get_bone_rest(hips).origin
	var k_h := new_hips.y / sci_hips.y
	for an in lib.get_animation_list():
		var a: Animation = lib.get_animation(an)
		for t in a.get_track_count():
			var bone_name := String(a.track_get_path(t)).get_slice(":", 1)
			var bi := sk.find_bone(bone_name)
			if bi < 0 or bi >= ss.get_bone_count(): continue
			if a.track_get_type(t) == Animation.TYPE_POSITION_3D:
				for key in a.track_get_key_count(t):
					var val: Vector3 = a.track_get_key_value(t, key)
					a.track_set_key_value(t, key, new_hips + (val - sci_hips) * k_h if bi == hips else sk.get_bone_rest(bi).origin)
			elif a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				var old_rest := ss.get_bone_rest(bi).basis.get_rotation_quaternion()
				var new_rest := sk.get_bone_rest(bi).basis.get_rotation_quaternion()
				if old_rest.is_equal_approx(new_rest): continue
				var conv := new_rest * old_rest.inverse()
				for key in a.track_get_key_count(t):
					a.track_set_key_value(t, key, (conv * (a.track_get_key_value(t, key) as Quaternion)).normalized())
	assert(ResourceSaver.save(lib, OUT + "locomotion.res") == OK)
	var shoulder_y := globals[ss.find_bone("mixamorig_LeftArm")].origin.y
	var cut := shoulder_y + CUT_ABOVE_SHOULDER
	print("kostí ", count, ", pánev ", new_hips, ", řez ", cut)
	build_first_person(out_v, out_n, out_t, vdata[Mesh.ARRAY_TEX_UV], out_b, out_w, vdata[Mesh.ARRAY_INDEX], cut, mat, skin)
	quit()

func build_first_person(v: PackedVector3Array, n: PackedVector3Array, t: PackedFloat32Array, uv: PackedVector2Array, b: PackedInt32Array, w: PackedFloat32Array, idx: PackedInt32Array, cut: float, mat: Material, skin: Skin) -> void:
	# Samostatné kousky (průzor, filtry), jejichž vršek je nad řezem, zmizí celé; jinak by
	# jejich spodek visel před objektivem. Hlavní oblek se jen ořízne rovinou.
	var parent: Array[int] = []
	for i in v.size(): parent.append(i)
	var weld := {}
	for i in v.size():
		var key := Vector3i((v[i] * 10000.0).round())
		if weld.has(key): parent[root_of(parent, i)] = root_of(parent, weld[key])
		else: weld[key] = i
	for tri in range(0, idx.size(), 3):
		parent[root_of(parent, idx[tri+1])] = root_of(parent, idx[tri])
		parent[root_of(parent, idx[tri+2])] = root_of(parent, idx[tri])
	var top := {}
	var count := {}
	for i in v.size():
		var r := root_of(parent, i)
		top[r] = maxf(float(top.get(r, -100.0)), v[i].y)
		count[r] = int(count.get(r, 0)) + 1
	var biggest := 0
	for r in count:
		if int(count[r]) > int(count.get(biggest, 0)): biggest = r
	var ov := []; var on := []; var ouv := []; var ob := []; var ow := []
	var segs := []
	var vert := func(i: int) -> Dictionary:
		var wd := {}
		for j in 8:
			if w[i*8+j] > 0.00001: wd[b[i*8+j]] = w[i*8+j]
		return {"p": v[i], "n": n[i], "uv": uv[i], "w": wd}
	for tri in range(0, idx.size(), 3):
		var r := root_of(parent, idx[tri])
		if r != biggest and float(top[r]) > cut - 0.01: continue
		var poly: Array = [vert.call(idx[tri]), vert.call(idx[tri+1]), vert.call(idx[tri+2])]
		var clipped := []
		var crossing := []
		for j in 3:
			var a: Dictionary = poly[j]
			var c: Dictionary = poly[(j+1) % 3]
			var ia: bool = a.p.y <= cut
			var ic: bool = c.p.y <= cut
			if ia: clipped.append(a)
			if ia != ic:
				var x := lerp_v(a, c, (cut - a.p.y) / (c.p.y - a.p.y))
				clipped.append(x)
				crossing.append(x)
		if crossing.size() == 2: segs.append(crossing)
		for j in range(1, clipped.size() - 1):
			for q in [clipped[0], clipped[j], clipped[j+1]]: emit(ov, on, ouv, ob, ow, q)
	var mesh := ArrayMesh.new()
	commit(mesh, ov, on, ouv, ob, ow)
	mesh.surface_set_material(0, mat)
	# víčko řezu (tmavé, z obou stran)
	ov = []; on = []; ouv = []; ob = []; ow = []
	if segs.size() > 0:
		var center := {"p": Vector3.ZERO, "n": Vector3.UP, "uv": Vector2.ZERO, "w": {}}
		for sgm in segs:
			for q in sgm:
				center.p += q.p
				for bi in q.w: center.w[bi] = float(center.w.get(bi, 0.0)) + q.w[bi]
		center.p /= float(segs.size() * 2)
		for sgm in segs:
			var a: Dictionary = sgm[0].duplicate(true)
			var c: Dictionary = sgm[1].duplicate(true)
			a.n = Vector3.UP
			c.n = Vector3.UP
			# Godot: přední strana po směru hodin (shora)
			if (a.p - center.p).cross(c.p - center.p).y > 0.0:
				var tmp := a
				a = c
				c = tmp
			emit(ov, on, ouv, ob, ow, center)
			emit(ov, on, ouv, ob, ow, a)
			emit(ov, on, ouv, ob, ow, c)
		commit(mesh, ov, on, ouv, ob, ow)
		# víčko v barvě obleku a osvětlené: při pohledu dolů vypadá jako horní hrana ramen
		var cap := StandardMaterial3D.new()
		cap.albedo_color = Color(0.2, 0.36, 0.62)
		cap.roughness = 0.75
		cap.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.surface_set_material(1, cap)
	assert(ResourceSaver.save(mesh, OUT + "hazmat_first_person.res") == OK)
	print("vlastní pohled: ", segs.size(), " hran řezu")

func lerp_v(a: Dictionary, c: Dictionary, t: float) -> Dictionary:
	var wd := {}
	for bi in a.w: wd[bi] = a.w[bi] * (1.0 - t)
	for bi in c.w: wd[bi] = float(wd.get(bi, 0.0)) + c.w[bi] * t
	return {"p": a.p.lerp(c.p, t), "n": a.n.lerp(c.n, t).normalized(), "uv": a.uv.lerp(c.uv, t), "w": wd}

func emit(ov: Array, on: Array, ouv: Array, ob: Array, ow: Array, q: Dictionary) -> void:
	var keys: Array = q.w.keys()
	keys.sort_custom(func(x, y): return q.w[x] > q.w[y])
	var total := 0.0
	for k in mini(8, keys.size()): total += q.w[keys[k]]
	for k in 8:
		ob.append(keys[k] if k < keys.size() else 0)
		ow.append(q.w[keys[k]] / maxf(total, 0.00001) if k < keys.size() else 0.0)
	ov.append(q.p)
	on.append(q.n)
	ouv.append(q.uv)

func commit(mesh: ArrayMesh, ov: Array, on: Array, ouv: Array, ob: Array, ow: Array) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(ov)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(on)
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(ouv)
	arrays[Mesh.ARRAY_BONES] = PackedInt32Array(ob)
	arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array(ow)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)

func root_of(parent: Array[int], i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i
