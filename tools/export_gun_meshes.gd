extends SceneTree
## Geometrie zbraní (v souřadnicích zbraně, metry) pro výpočet distančního pole: tools/gun_sdf.py
## Díly: body (vše pevné), magazine (zásobník), barrel (sklopné hlavně dvojky).
const GUNS:={"ak":"res://assets/ak47/ak47.tscn","mp40":"res://assets/mp40/mp40.tscn","deagle":"res://assets/deagle/deagle.tscn","izh54":"res://assets/izh54/izh54.tscn"}
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var out_dir:=OS.get_environment("OUT") if OS.get_environment("OUT")!="" else "/tmp/guns"
	for key in GUNS:
		var m: Node3D=load(GUNS[key]).instantiate()
		root.add_child(m)
		var parts:={"body":[],"magazine":[],"barrel":[]}
		for mi in m.find_children("*","MeshInstance3D",true,false):
			var path:=String(m.get_path_to(mi))
			var part:="magazine" if path.begins_with("Magazine/") else ("barrel" if path.begins_with("Barrel/") else "body")
			var xf:=Props._xf(mi,m)
			# zásobník a hlaveň v souřadnicích svého uzlu (za běhu se posouvají / otáčejí)
			if part!="body": xf=Props._xf(m.get_node(path.get_slice("/",0)),m).affine_inverse()*xf
			var faces:=(mi as MeshInstance3D).mesh.get_faces()
			for v in faces: (parts[part] as Array).append([v.x,v.y,v.z] if true else null)
			for i in faces.size(): (parts[part] as Array)[(parts[part] as Array).size()-faces.size()+i]=[ (xf*faces[i]).x,(xf*faces[i]).y,(xf*faces[i]).z ]
		for part in parts:
			if (parts[part] as Array).is_empty(): continue
			var f:=FileAccess.open("%s/%s_%s.json"%[out_dir,key,part],FileAccess.WRITE)
			f.store_string(JSON.stringify(parts[part]))
			f.close()
			print(key," ",part," trojúhelníků ",(parts[part] as Array).size()/3)
		m.free()
	quit()
