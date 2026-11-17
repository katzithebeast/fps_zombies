extends SceneTree
func _initialize() -> void:
	call_deferred("build")
func build() -> void:
	var source: Node3D=load("res://assets/ak47/source/AK_LP correct.fbx").instantiate()
	root.add_child(source)
	var result:=Node3D.new()
	result.name="AK47"
	var magazine:=Node3D.new()
	magazine.name="Magazine"
	result.add_child(magazine)
	magazine.owner=result
	var material:=StandardMaterial3D.new()
	material.albedo_texture=load("res://assets/ak47/textures/base_color.png")
	material.normal_enabled=true
	material.normal_texture=load("res://assets/ak47/textures/normal.png")
	material.metallic=1.0
	material.metallic_texture=load("res://assets/ak47/textures/metalic.png")
	material.roughness_texture=load("res://assets/ak47/textures/roughness.png")
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var normalize:=Transform3D(Basis(Vector3.UP,PI/2)*0.063, -Vector3(0,-0.09,0.12))
	for node in source.find_children("*","MeshInstance3D",true,false):
		var mesh:=MeshInstance3D.new()
		mesh.name=node.name
		var st:=SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(node.mesh,0,normalize*node.global_transform)
		mesh.mesh=st.commit()
		mesh.material_override=material
		if str(node.name) in ["Object_010_lp","Object_025_lp","Object_029_lp"]: magazine.add_child(mesh)
		else: result.add_child(mesh)
		mesh.owner=result
	var scene:=PackedScene.new()
	scene.pack(result)
	assert(ResourceSaver.save(scene,"res://assets/ak47/ak47.tscn")==OK)
	print("AK normalized: muzzle -Z, grip origin, length 0.97m")
	source.free()
	result.free()
	quit()
