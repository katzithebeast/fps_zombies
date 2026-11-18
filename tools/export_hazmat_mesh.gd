extends SceneTree
## Export sítě obleku v klidové póze pro tools/bake_hazmat_wear.py → /tmp/hz_mesh_0.bin
func _initialize() -> void:
	var m: Mesh=load("res://assets/hazmat/hazmat_body.res")
	var a:=m.surface_get_arrays(0)
	var v: PackedVector3Array=a[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array=a[Mesh.ARRAY_TEX_UV]
	var n: PackedVector3Array=a[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array=a[Mesh.ARRAY_INDEX]
	var fa:=FileAccess.open("/tmp/hz_mesh_0.bin",FileAccess.WRITE)
	fa.store_32(v.size()); fa.store_32(idx.size())
	for i in v.size():
		fa.store_float(v[i].x); fa.store_float(v[i].y); fa.store_float(v[i].z)
		fa.store_float(uv[i].x); fa.store_float(uv[i].y)
		fa.store_float(n[i].x); fa.store_float(n[i].y); fa.store_float(n[i].z)
	for i in idx: fa.store_32(i)
	print("hazmat: ",v.size()," vrcholů")
	quit()
