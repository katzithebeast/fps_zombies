extends SceneTree
## Uloží klidovou polohu každého vrcholu obleku do CUSTOM0 (float) — vzory na obleku
## (Customize) se pak počítají přesně, bez 8bit schodů a švů textury hazmat_pos.png.
func _initialize() -> void:
	for p in ["res://assets/hazmat/hazmat_body.res","res://assets/hazmat/hazmat_first_person.res"]:
		var m: ArrayMesh=load(p)
		var out:=ArrayMesh.new()
		for s in m.get_surface_count():
			var a:=m.surface_get_arrays(s)
			var fmt:=m.surface_get_format(s)
			var v: PackedVector3Array=a[Mesh.ARRAY_VERTEX]
			var c:=PackedFloat32Array(); c.resize(v.size()*4)
			for i in v.size():
				c[i*4]=v[i].x; c[i*4+1]=v[i].y; c[i*4+2]=v[i].z; c[i*4+3]=1.0
			a[Mesh.ARRAY_CUSTOM0]=c
			var flags:=(fmt & (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a,[],{},flags)
			out.surface_set_material(s,m.surface_get_material(s))
			out.surface_set_name(s,m.surface_get_name(s))
		out.resource_name=m.resource_name
		var err:=ResourceSaver.save(out,p)
		print(p," -> ",err," fmt=",out.surface_get_format(0))
	quit()
