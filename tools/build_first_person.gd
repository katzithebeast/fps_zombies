extends SceneTree
## Celé tělo pro vlastní pohled: trup, obě paže, nohy a výbava.
## Skrytá je jen hlava; řez u krku je uzavřený a všechny váhy kostí zůstávají.
const BASE := "res://assets/scientist/"
const HEIGHT := 1.70
var _segments: Array = []

func _initialize() -> void:
	var model: Node3D = load(BASE + "ScientistRigged.fbx").instantiate()
	var sk: Skeleton3D = model.get_node("Skeleton3D")
	var source: MeshInstance3D = sk.get_node("ScientistBody")
	var data := source.mesh.surface_get_arrays(0)
	var transform := sk.get_bone_global_rest(sk.find_bone(source.skin.get_bind_name(0))) * source.skin.get_bind_pose(0)
	var normal_basis := transform.basis.orthonormalized()
	var vertices: Array = []
	for i in data[Mesh.ARRAY_VERTEX].size():
		var weights := {}
		for j in 8:
			var weight: float = data[Mesh.ARRAY_WEIGHTS][i * 8 + j]
			if weight > 0.00001:
				var bind: int = data[Mesh.ARRAY_BONES][i * 8 + j]
				weights[bind] = weight
		vertices.append({"p": transform * data[Mesh.ARRAY_VERTEX][i], "n": (normal_basis * data[Mesh.ARRAY_NORMAL][i]).normalized(), "uv": data[Mesh.ARRAY_TEX_UV][i], "w": weights})
	var st := new_arrays()
	var indices: PackedInt32Array = data[Mesh.ARRAY_INDEX]
	for i in range(0, indices.size(), 3):
		var polygon: Array = [vertices[indices[i]], vertices[indices[i+1]], vertices[indices[i+2]]]
		var clipped: Array = []
		var cut: Array = []
		for j in 3:
			var a: Dictionary = polygon[j]
			var b: Dictionary = polygon[(j+1) % 3]
			var inside_a: bool = a.p.y <= HEIGHT
			var inside_b: bool = b.p.y <= HEIGHT
			if inside_a:
				clipped.append(a)
			if inside_a != inside_b:
				var intersection := interpolate(a, b, (HEIGHT-a.p.y)/(b.p.y-a.p.y))
				clipped.append(intersection)
				cut.append(intersection)
		if cut.size() == 2:
			_segments.append(cut)
		for j in range(1, clipped.size()-1):
			for v in [clipped[0], clipped[j], clipped[j+1]]:
				emit(st, v)
	var mesh := ArrayMesh.new()
	commit_surface(mesh, st)
	mesh.surface_set_material(0, source.get_active_material(0))
	# Každý okraj řezu se spojí se středem krku. Vrcholy víčka mají stejné váhy
	# jako jeho obvod, takže řez zůstane zavřený i při běhu a přikrčení.
	# Každý samostatný okraj má vlastní střed i váhy; krk a řezy ramen
	# nesmějí spojovat velké trojúhelníky, které se při IK vytahují do kamery.
	var edge_parents: Array[int] = []
	var endpoints := {}
	for i in _segments.size(): edge_parents.append(i)
	for i in _segments.size():
		for vertex in _segments[i]:
			var key := Vector3i((vertex.p * 100000.0).round())
			if endpoints.has(key): edge_parents[component_root(edge_parents,i)] = component_root(edge_parents,endpoints[key])
			else: endpoints[key]=i
	var loops := {}
	for i in _segments.size():
		var group := component_root(edge_parents,i)
		if not loops.has(group): loops[group]=[]
		loops[group].append(_segments[i])
	var cap := new_arrays()
	for segments in loops.values():
		var center := {"p": Vector3.ZERO, "n": Vector3.UP, "uv": Vector2.ZERO, "w": {}}
		for segment in segments:
			for v in segment:
				center.p += v.p
				for bind in v.w:
					center.w[bind] = center.w.get(bind, 0.0) + v.w[bind]
		center.p /= float(segments.size()*2)
		for segment in segments:
			var a: Dictionary = segment[0].duplicate(true)
			var b: Dictionary = segment[1].duplicate(true)
			a.n = Vector3.UP
			b.n = Vector3.UP
			# Godot používá po směru hodinových ručiček.
			if (a.p-center.p).cross(b.p-center.p).y > 0.0:
				var swap := a
				a = b
				b = swap
			for v in [center, a, b]:
				emit(cap, v)
	commit_surface(mesh, cap)
	var cap_material := StandardMaterial3D.new()
	cap_material.albedo_color = Color(0.02, 0.045, 0.07)
	cap_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cap_material.roughness = 0.9
	cap_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(1, cap_material)
	# Ponechat dolní výbavu; části propojené s hlavou vynechat jen pro vlastní pohled.
	var gear := new_arrays()
	var gear_data := source.mesh.surface_get_arrays(1)
	var gear_indices: PackedInt32Array = gear_data[Mesh.ARRAY_INDEX]
	# Výbava hlavy má i dlouhé hadice pod úrovní řezu. Skrýt celý propojený díl,
	# nikoli jen jeho horní konec, který pak zůstával otevřený před objektivem.
	var parents: Array[int] = []
	var positions: Array[Vector3] = []
	var welded := {}
	for i in gear_data[Mesh.ARRAY_VERTEX].size():
		parents.append(i)
		var point: Vector3 = transform * gear_data[Mesh.ARRAY_VERTEX][i]
		positions.append(point)
		var key := Vector3i((point * 100000.0).round())
		if welded.has(key): parents[component_root(parents, i)] = component_root(parents, welded[key])
		else: welded[key] = i
	for triangle in range(0, gear_indices.size(), 3):
		for corner in [1,2]:
			parents[component_root(parents, gear_indices[triangle+corner])] = component_root(parents, gear_indices[triangle])
	var top := {}
	for i in positions.size():
		var component := component_root(parents,i)
		top[component] = maxf(float(top.get(component,-100.0)),positions[i].y)
	var visible_indices: Array[int] = []
	for triangle in range(0,gear_indices.size(),3):
		if float(top[component_root(parents,gear_indices[triangle])]) >= HEIGHT-0.01: continue
		for corner in 3: visible_indices.append(gear_indices[triangle+corner])
	for i in visible_indices:
		var weights := {}
		for j in 8:
			var weight: float = gear_data[Mesh.ARRAY_WEIGHTS][i*8+j]
			if weight > 0.00001:
				weights[int(gear_data[Mesh.ARRAY_BONES][i*8+j])] = weight
		emit(gear, {"p": transform * gear_data[Mesh.ARRAY_VERTEX][i], "n": (normal_basis * gear_data[Mesh.ARRAY_NORMAL][i]).normalized(), "uv": gear_data[Mesh.ARRAY_TEX_UV][i], "w": weights})
	commit_surface(mesh, gear)
	mesh.surface_set_material(2, source.get_active_material(1))
	var skin := Skin.new()
	for i in source.skin.get_bind_count():
		var name := source.skin.get_bind_name(i)
		skin.add_named_bind(name, sk.get_bone_global_rest(sk.find_bone(name)).affine_inverse())
	var error := ResourceSaver.save(mesh, BASE + "closed_first_person_mesh.res")
	assert(error == OK)
	error = ResourceSaver.save(skin, BASE + "first_person_skin.res")
	assert(error == OK)
	print("Closed first-person mesh: ", mesh.get_surface_count(), " surfaces, ", _segments.size(), " capped boundary edges")
	model.free()
	quit()

func component_root(parents: Array[int], index: int) -> int:
	while parents[index] != index:
		parents[index] = parents[parents[index]]
		index = parents[index]
	return index

func interpolate(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var weights := {}
	for bind in a.w:
		weights[bind] = a.w[bind] * (1.0-t)
	for bind in b.w:
		weights[bind] = weights.get(bind, 0.0) + b.w[bind] * t
	return {"p": a.p.lerp(b.p, t), "n": a.n.lerp(b.n, t).normalized(), "uv": a.uv.lerp(b.uv, t), "w": weights}

func emit(st: Dictionary, v: Dictionary) -> void:
	var ordered: Array = v.w.keys()
	ordered.sort_custom(func(a: int, b: int) -> bool: return v.w[a] > v.w[b])
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var total := 0.0
	for i in mini(8, ordered.size()):
		bones.append(ordered[i])
		weights.append(v.w[ordered[i]])
		total += v.w[ordered[i]]
	for i in weights.size():
		weights[i] /= maxf(total, 0.00001)
	bones.resize(8)
	weights.resize(8)
	st.bones.append_array(Array(bones))
	st.weights.append_array(Array(weights))
	st.normals.append(v.n)
	st.uvs.append(v.uv)
	st.vertices.append(v.p)

func new_arrays() -> Dictionary:
	return {"vertices": [], "normals": [], "uvs": [], "bones": [], "weights": []}

func commit_surface(mesh: ArrayMesh, data: Dictionary) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(data.vertices)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(data.normals)
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(data.uvs)
	arrays[Mesh.ARRAY_BONES] = PackedInt32Array(data.bones)
	arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array(data.weights)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
