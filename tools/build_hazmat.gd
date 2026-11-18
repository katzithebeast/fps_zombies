extends SceneTree
## Spuštění: Godot --headless --path . --script res://tools/build_hazmat.gd
## Hazmat oblek (kostra UE5 Manny) převlékne na kostru scientisty (Mixamo, 41 kostí, stejné
## indexy i natočení kostí), klouby posune do pozic obleku. Díky tomu dál fungují všechny
## animace, IK paží se zbraní i vlastní pohled. Výstup: assets/hazmat/
const OUT := "res://assets/hazmat/"
const SCI := "res://assets/scientist/"
const CUT_ABOVE_SHOULDER := 0.04 # řez pro vlastní pohled: těsně nad rameny (kukla je široká, víčko pod hlavou by zakrylo výhled)
# UE kost → Mixamo kost (váhy)
const WEIGHT_MAP := {
	"pelvis":"Hips","spine_01":"Spine","spine_02":"Spine","spine_03":"Spine1","spine_04":"Spine2","spine_05":"Spine2",
	"neck_01":"Neck","neck_02":"Neck","head":"Head",
	"clavicle_X":"XShoulder","upperarm_X":"XArm","upperarm_twist_01_X":"XArm","upperarm_twist_02_X":"XArm",
	"lowerarm_X":"XForeArm","lowerarm_twist_01_X":"XForeArm","lowerarm_twist_02_X":"XForeArm","hand_X":"XHand",
	"thumb_01_X":"XHandThumb1","thumb_02_X":"XHandThumb2","thumb_03_X":"XHandThumb3",
	"index_metacarpal_X":"XHand","middle_metacarpal_X":"XHand","ring_metacarpal_X":"XHand","pinky_metacarpal_X":"XHand",
	"index_01_X":"XHandIndex1","index_02_X":"XHandIndex2","index_03_X":"XHandIndex3",
	"middle_01_X":"XHandIndex1","middle_02_X":"XHandIndex2","middle_03_X":"XHandIndex3",
	"ring_01_X":"XHandIndex1","ring_02_X":"XHandIndex2","ring_03_X":"XHandIndex3",
	"pinky_01_X":"XHandIndex1","pinky_02_X":"XHandIndex2","pinky_03_X":"XHandIndex3",
	"thigh_X":"XUpLeg","thigh_twist_01_X":"XUpLeg","thigh_twist_02_X":"XUpLeg",
	"calf_X":"XLeg","calf_twist_01_X":"XLeg","calf_twist_02_X":"XLeg","foot_X":"XFoot","ball_X":"XToeBase",
}
# Mixamo kloub → UE kloub (pozice)
const JOINT_MAP := {
	"Hips":"pelvis","Spine":"spine_01","Spine1":"spine_03","Spine2":"spine_04","Neck":"neck_01","Head":"head",
	"XShoulder":"clavicle_X","XArm":"upperarm_X","XForeArm":"lowerarm_X","XHand":"hand_X",
	"XHandThumb1":"thumb_01_X","XHandThumb2":"thumb_02_X","XHandThumb3":"thumb_03_X",
	"XHandIndex1":"index_01_X","XHandIndex2":"index_02_X","XHandIndex3":"index_03_X",
	"XUpLeg":"thigh_X","XLeg":"calf_X","XFoot":"foot_X","XToeBase":"ball_X",
}

var hz: Skeleton3D
var fix := Transform3D.IDENTITY   # UE prostor obleku → prostor kostry scientisty

func ue(name: String) -> Vector3:
	return fix * hz.get_bone_global_rest(hz.find_bone(name)).origin

func expand(table: Dictionary) -> Dictionary:
	var out := {}
	for k in table:
		var v: String = table[k]
		if "X" in k and (k.ends_with("_X") or k.begins_with("X")):
			for side in [["l","Left"],["r","Right"]]:
				out[k.replace("_X","_"+side[0]) if k.ends_with("_X") else side[1]+k.substr(1)] = v.replace("_X","_"+side[0]) if v.ends_with("_X") else (side[1]+v.substr(1) if v.begins_with("X") else v)
		else:
			out[k] = v
	return out

func _initialize() -> void:
	var sci_scene: Node3D = load(SCI + "ScientistRigged.fbx").instantiate()
	root.add_child(sci_scene)
	var ss: Skeleton3D = sci_scene.get_node("Skeleton3D")
	var hz_scene: Node3D = load(OUT + "SKM_HazmatSuit.fbx").instantiate()
	root.add_child(hz_scene)
	hz = hz_scene.get_node("Skeleton3D")
	var src: MeshInstance3D = hz.get_node("HazmatSuit")
	# Natočení: postava kouká k +Z, levá strana na +X (jako Mixamo).
	var raw_fwd := hz.get_bone_global_rest(hz.find_bone("ball_l")).origin - hz.get_bone_global_rest(hz.find_bone("foot_l")).origin
	var raw_left := hz.get_bone_global_rest(hz.find_bone("upperarm_l")).origin - hz.get_bone_global_rest(hz.find_bone("upperarm_r")).origin
	raw_fwd.y = 0.0
	var basis := Basis.IDENTITY
	if absf(raw_fwd.x) > absf(raw_fwd.z): basis = Basis(Vector3.UP, -signf(raw_fwd.x) * PI * 0.5)
	elif raw_fwd.z < 0.0: basis = Basis(Vector3.UP, PI)
	var left_after := basis * raw_left
	print("fwd ", raw_fwd, " left ", raw_left, " → left po otočení ", left_after)
	assert(left_after.x > 0.0)
	# Měřítko: kloub hlavy ve stejné výšce jako u scientisty (kamera, IK i míření sedí).
	var sci_head := ss.get_bone_global_rest(ss.find_bone("mixamorig_Head")).origin
	var hz_head := basis * hz.get_bone_global_rest(hz.find_bone("head")).origin
	var s := sci_head.y / hz_head.y
	fix = Transform3D(basis.scaled(Vector3.ONE * s), Vector3.ZERO)
	print("měřítko ", s)
	var jm := expand(JOINT_MAP)
	var wm := expand(WEIGHT_MAP)
	# --- nová kostra: kosti, rodiče a natočení scientisty, klouby obleku
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	var globals: Array[Transform3D] = []
	var mesh_aabb_top := 0.0
	for i in ss.get_bone_count():
		var name := ss.get_bone_name(i)
		sk.add_bone(name)
		sk.set_bone_parent(i, ss.get_bone_parent(i))
		var short := name.trim_prefix("mixamorig_")
		var g := ss.get_bone_global_rest(i)
		var b := g.basis.orthonormalized()
		var p := g.origin
		if jm.has(short): p = ue(jm[short])
		globals.append(Transform3D(b, p))
	# koncové kosti (bez protějšku): prodloužit z rodiče
	var vdata := src.mesh.surface_get_arrays(0)
	var to_skel := src.global_transform
	var bind_xf := hz.get_bone_global_rest(hz.find_bone(src.skin.get_bind_name(0))) * src.skin.get_bind_pose(0)
	for v in (vdata[Mesh.ARRAY_VERTEX] as PackedVector3Array): mesh_aabb_top = maxf(mesh_aabb_top, (fix * bind_xf * v).y)
	for i in ss.get_bone_count():
		var short := ss.get_bone_name(i).trim_prefix("mixamorig_")
		if jm.has(short) or ss.get_bone_parent(i) < 0: continue
		var parent := ss.get_bone_parent(i)
		var gp := ss.get_bone_global_rest(parent).origin
		var gpp := ss.get_bone_global_rest(ss.get_bone_parent(parent)).origin if ss.get_bone_parent(parent) >= 0 else gp
		var p: Vector3
		if short == "HeadTop_End": p = Vector3(globals[parent].origin.x, mesh_aabb_top, globals[parent].origin.z)
		elif short.ends_with("Toe_End"):
			var fwd := globals[parent].origin - globals[ss.get_bone_parent(parent)].origin
			fwd.y = 0.0
			p = globals[parent].origin + fwd.normalized() * 0.08
		else:
			# špička prstu: pokračovat směrem posledního článku
			var d := globals[parent].origin - globals[ss.get_bone_parent(parent)].origin
			p = globals[parent].origin + d * 0.85
		globals[i] = Transform3D(globals[i].basis, p)
	for i in ss.get_bone_count():
		var parent := ss.get_bone_parent(i)
		var local := globals[i] if parent < 0 else globals[parent].affine_inverse() * globals[i]
		sk.set_bone_rest(i, local)
		sk.set_bone_pose(i, local)
	# --- síť: vrcholy do prostoru kostry, váhy UE → Mixamo
	var bind_names: Array[String] = []
	for b in src.skin.get_bind_count(): bind_names.append(String(src.skin.get_bind_name(b)))
	var verts: PackedVector3Array = vdata[Mesh.ARRAY_VERTEX]
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
	var unmapped := {}
	for i in verts.size():
		out_v.append(fix * bind_xf * verts[i])
		out_n.append((nb * norms[i]).normalized())
		if tans.size() >= (i + 1) * 4:
			var t := (nb * Vector3(tans[i*4], tans[i*4+1], tans[i*4+2])).normalized()
			out_t.append_array(PackedFloat32Array([t.x, t.y, t.z, tans[i*4+3]]))
		var acc := {}
		for j in per:
			var w := weights_in[i*per+j]
			if w <= 0.00001: continue
			var ue_name := bind_names[bones_in[i*per+j]]
			var target: String = wm.get(ue_name, "")
			if target == "":
				unmapped[ue_name] = true
				continue
			var idx := ss.find_bone("mixamorig_" + target)
			acc[idx] = float(acc.get(idx, 0.0)) + w
		var keys: Array = acc.keys()
		keys.sort_custom(func(a, b): return acc[a] > acc[b])
		var total := 0.0
		for k in mini(8, keys.size()): total += acc[keys[k]]
		for k in 8:
			if k < keys.size():
				out_b.append(keys[k])
				out_w.append(acc[keys[k]] / maxf(total, 0.00001))
			else:
				out_b.append(0)
				out_w.append(0.0)
	print("nemapované kosti s vahou: ", unmapped.keys())
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
	if arrays[Mesh.ARRAY_TANGENT] == null: mesh.regen_normal_maps()
	var skin := Skin.new()
	for i in sk.get_bone_count(): skin.add_named_bind(sk.get_bone_name(i), globals[i].affine_inverse())
	assert(ResourceSaver.save(mesh, OUT + "hazmat_body.res") == OK)
	assert(ResourceSaver.save(skin, OUT + "hazmat_skin.res") == OK)
	# scéna postavy (stejná struktura jako ScientistRigged: Skeleton3D + síť)
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
	# --- animace: stejné rotace, délky kostí obleku, pánev úměrně výšce
	var lib: AnimationLibrary = (load(SCI + "locomotion.res") as AnimationLibrary).duplicate(true)
	var hips := ss.find_bone("mixamorig_Hips")
	var sci_hips := ss.get_bone_rest(hips).origin
	var new_hips := sk.get_bone_rest(hips).origin
	var k := new_hips.y / sci_hips.y
	for an in lib.get_animation_list():
		var a: Animation = lib.get_animation(an)
		for t in a.get_track_count():
			if a.track_get_type(t) != Animation.TYPE_POSITION_3D: continue
			var bone_name := String(a.track_get_path(t)).get_slice(":", 1)
			var bi := sk.find_bone(bone_name)
			if bi < 0: continue
			for key in a.track_get_key_count(t):
				var val: Vector3 = a.track_get_key_value(t, key)
				if bi == hips: a.track_set_key_value(t, key, new_hips + (val - sci_hips) * k)
				else: a.track_set_key_value(t, key, sk.get_bone_rest(bi).origin)
	assert(ResourceSaver.save(lib, OUT + "locomotion.res") == OK)
	print("pánev scientist ", sci_hips, " → oblek ", new_hips, " (k=", k, ")")
	# --- vlastní pohled: bez hlavy, řez uzavřený víčkem
	var head_y := globals[ss.find_bone("mixamorig_Head")].origin.y
	var neck_y := globals[ss.find_bone("mixamorig_Neck")].origin.y
	var shoulder_y := globals[ss.find_bone("mixamorig_LeftArm")].origin.y
	var cut := shoulder_y + CUT_ABOVE_SHOULDER
	print("krk ", neck_y, " hlava ", head_y, " řez ", cut, " vršek ", mesh_aabb_top)
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
