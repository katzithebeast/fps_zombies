extends SceneTree
## Distanční pole zbraní z tools/gun_sdf.py (/tmp/guns/*.sdf) → res://assets/guns_sdf/<zbraň>_<díl>.res
## (Image RF: šířka = nx*ny, výška = nz; v metadatech počátek, buňka, rozměry).
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var src:=OS.get_environment("SRC") if OS.get_environment("SRC")!="" else "/tmp/guns"
	var dir:=DirAccess.open(src)
	for f in dir.get_files():
		if not f.ends_with(".sdf"): continue
		var b:=FileAccess.get_file_as_bytes(src+"/"+f)
		var o:=Vector3(b.decode_float(0),b.decode_float(4),b.decode_float(8))
		var cell:=b.decode_float(12)
		var n:=Vector3i(b.decode_s32(16),b.decode_s32(20),b.decode_s32(24))
		var data:=b.slice(28)
		var img:=Image.create_from_data(n.x*n.y,n.z,false,Image.FORMAT_RF,data)
		img.set_meta("origin",o)
		img.set_meta("cell",cell)
		img.set_meta("dims",n)
		var out:="res://assets/guns_sdf/"+f.replace(".sdf",".res")
		assert(ResourceSaver.save(img,out)==OK)
		print(out," ",n," ",data.size()/4," hodnot")
	quit()
