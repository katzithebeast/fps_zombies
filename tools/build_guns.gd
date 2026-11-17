extends SceneTree
## Spuštění: Godot --headless --path . --script res://tools/build_guns.gd
## Převede dodané modely zbraní do stejné podoby jako AK-47: hlaveň míří do -Z, počátek je v místě
## úchopu pravé ruky, měřítko jako u AK (skutečná délka × 1,1). Zásobník (a u brokovnice hlavně)
## jsou samostatné uzly, aby je šlo při přebíjení rozpohybovat.
const GUNS:={
	"deagle":{"source":"res://assets/deagle/source/deagle.glb","turn":PI,"scale":1.03,"grip":Vector3(0.0,0.005,-0.035),
		"mag":{"min":Vector3(-1,-1,-0.07),"max":Vector3(1,-0.035,0.0)}},
	"mp40":{"source":"res://assets/mp40/source/mp40.glb","turn":PI/2,"scale":1.07,"grip":Vector3(0.01,0.02,0.0),
		"mag":{"min":Vector3(0.245,-1,-1),"max":Vector3(0.36,-0.005,1)}},
	"izh54":{"source":"res://assets/izh54/source/izh54.fbx","turn":PI,"scale":1.05,"grip":Vector3(0.0,-0.02,-0.08),
		"barrel":["stvol_low","priklad_low","zashelka"],"hinge":Vector3(0.0,0.02,0.1),
		"material":{"albedo":"res://assets/izh54/textures/Double_barrel_Izh_54_albedo.jpeg","normal":"res://assets/izh54/textures/Double_barrel_Izh_54_normal.png",
			"rough":"res://assets/izh54/textures/Double_barrel_Izh_54_roughness.jpeg","metal":"res://assets/izh54/textures/Double_barrel_Izh_54_metallic.jpeg","ao":"res://assets/izh54/textures/Double_barrel_Izh_54_AO.jpeg"}},
}

func _initialize() -> void:
	call_deferred("build")

func _material(info: Dictionary) -> StandardMaterial3D:
	var m:=StandardMaterial3D.new()
	m.albedo_texture=load(info.albedo)
	m.normal_enabled=true
	m.normal_texture=load(info.normal)
	m.roughness_texture=load(info.rough)
	m.metallic=1.0
	m.metallic_texture=load(info.metal)
	m.ao_enabled=true
	m.ao_texture=load(info.ao)
	m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

func _inside(p: Vector3, box: Dictionary) -> bool:
	return p.x>=box.min.x and p.y>=box.min.y and p.z>=box.min.z and p.x<=box.max.x and p.y<=box.max.y and p.z<=box.max.z

func build() -> void:
	for name in GUNS:
		var info: Dictionary=GUNS[name]
		var source: Node3D=load(info.source).instantiate()
		root.add_child(source)
		await process_frame
		var result:=Node3D.new()
		result.name=name
		var magazine:=Node3D.new()
		magazine.name="Magazine"
		result.add_child(magazine)
		magazine.owner=result
		var barrel: Node3D=null
		var normalize:=Transform3D(Basis(Vector3.UP,info.turn)*float(info.scale),Vector3.ZERO)
		normalize.origin=-(normalize.basis*info.grip)
		if info.has("barrel"):
			barrel=Node3D.new()
			barrel.name="Barrel"
			barrel.position=normalize*info.hinge
			result.add_child(barrel)
			barrel.owner=result
		var override: Material=_material(info.material) if info.has("material") else null
		var parts:=0
		var mag_tris:=0
		for node in source.find_children("*","MeshInstance3D",true,false):
			var into: Node3D=result
			var shift:=Transform3D.IDENTITY
			if barrel and str(node.name) in info.barrel:
				into=barrel
				shift=Transform3D(Basis.IDENTITY,-barrel.position)
			for surface in node.mesh.get_surface_count():
				var material: Material=override if override else node.get_active_material(surface)
				var body:=SurfaceTool.new()
				body.begin(Mesh.PRIMITIVE_TRIANGLES)
				body.append_from(node.mesh,surface,shift*normalize*node.global_transform)
				var whole: ArrayMesh=body.commit()
				var groups:=[[whole,into]]
				if info.has("mag"):
					# Zásobník vyříznout podle polohy trojúhelníků (v souřadnicích původního modelu).
					var data:=MeshDataTool.new()
					data.create_from_surface(whole,0)
					var keep:=SurfaceTool.new()
					var mag:=SurfaceTool.new()
					keep.begin(Mesh.PRIMITIVE_TRIANGLES)
					mag.begin(Mesh.PRIMITIVE_TRIANGLES)
					var back: Transform3D=(shift*normalize).affine_inverse()
					var mag_count:=0
					for face in data.get_face_count():
						var c:=Vector3.ZERO
						for k in 3: c+=data.get_vertex(data.get_face_vertex(face,k))
						var target:=mag if _inside(back*(c/3.0),info.mag) else keep
						if target==mag: mag_count+=1
						for k in 3:
							var v:=data.get_face_vertex(face,k)
							target.set_normal(data.get_vertex_normal(v))
							target.set_uv(data.get_vertex_uv(v))
							if data.get_vertex_tangent(v)!=Plane(): target.set_tangent(data.get_vertex_tangent(v))
							target.add_vertex(data.get_vertex(v))
					groups=[[keep.commit(),into]]
					if mag_count>0:
						groups.append([mag.commit(),magazine])
						mag_tris+=mag_count
				for group in groups:
					var mesh:=MeshInstance3D.new()
					mesh.name="%s_%d_%d" % [node.name,surface,parts]
					mesh.mesh=group[0]
					mesh.material_override=material
					group[1].add_child(mesh)
					mesh.owner=result
					parts+=1
		var box:=AABB()
		var first:=true
		for mesh in result.find_children("*","MeshInstance3D",true,false):
			var b: AABB=(mesh.get_parent() as Node3D).transform*mesh.get_aabb() if mesh.get_parent()!=result else mesh.get_aabb()
			box=b if first else box.merge(b)
			first=false
		var scene:=PackedScene.new()
		scene.pack(result)
		var path:="res://assets/%s/%s.tscn" % [name,name]
		print(name," saved=",ResourceSaver.save(scene,path)," parts=",parts," mag_tris=",mag_tris," bounds=",box," muzzle_z=",box.position.z)
		source.free()
		result.free()
	quit()
