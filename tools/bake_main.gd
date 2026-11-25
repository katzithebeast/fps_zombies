extends SceneTree
## Vygeneruje hlavní mapu (lázně) kódem a uloží ji jako normální scénu maps/main_map.tscn.
## POZOR: přepíše ruční úpravy v té scéně! Spouštět jen pro novou mapu od nuly.
##   godot --headless --path . --script res://tools/bake_main.gd
const OUT:="res://maps/main_map.tscn"
const MainScript:=preload("res://scripts/main.gd")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	MainScript.bake_mode=true
	var main: Node3D=Node3D.new()
	main.set_script(MainScript)
	root.add_child(main)
	for i in 3: await process_frame
	var map:=Node3D.new()
	map.name="MainMap"
	root.add_child(map)
	# materiály, které hra za běhu mění, dostanou značku (po načtení se vymění za živé)
	for k in ["tile_mat","water_mat","chrome_mat","dark_mat","void_mat"]:
		var m: Material=main.get(k)
		if m: m.set_meta("main_mat",k)
	# lampy: informace pro blikání a úkoly
	for L in main.lamps:
		var l: OmniLight3D=L.light
		l.set_meta("lamp",{"energy":L.energy,"flicker":L.flicker})
		l.set_meta("lamp_mat",L.mat)
	# kolize: krabice zdí přesně pod svým meshem se pověsí na ten mesh (v editoru se posouvají spolu)
	var wb: StaticBody3D=main.world_body
	var meshes:={}
	for c in main.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is BoxMesh:
			meshes[_key((c as Node3D).transform,((c as MeshInstance3D).mesh as BoxMesh).size)]=c
	var paired:=0
	for cs in wb.get_children():
		if not (cs is CollisionShape3D and (cs as CollisionShape3D).shape is BoxShape3D): continue
		var k:=_key((cs as Node3D).transform,((cs as CollisionShape3D).shape as BoxShape3D).size)
		if meshes.has(k):
			var mi: MeshInstance3D=meshes[k]
			var body:=StaticBody3D.new()
			body.name="Kolize"
			body.collision_layer=1
			body.set_meta("wall_collider",true)
			mi.add_child(body)
			cs.reparent(body,false)
			(cs as Node3D).transform=Transform3D()
			paired+=1
	print("kolize na zdech: ",paired,", zbylo samostatně: ",wb.get_child_count())
	# složky podle částí lázní (pořadí stavby)
	var marks: Array=main.bake_marks
	var folders:=[]
	for m in marks:
		var f:=Node3D.new()
		f.name=m[0]
		map.add_child(f)
		folders.append(f)
	var other:=Node3D.new()
	other.name="Ostatni"
	map.add_child(other)
	var kids:=main.get_children()
	var counts:={}
	for i in kids.size():
		var n: Node=kids[i]
		var fi:=-1
		for j in marks.size():
			if i<int(marks[j][1]): fi=j; break
		var dest: Node3D=folders[fi] if fi>=0 else other
		if n==wb: dest=map
		else: n.name=_nice_name(n,counts)
		n.reparent(dest,true)
	# data (voda, světlíky, podlahy)
	var data:=Node.new()
	data.name="DataMapy"
	data.set_script(load("res://scripts/level/map_data.gd"))
	map.add_child(data)
	data.water_rects.assign(main.water_rects)
	data.water_groups=main.water_groups
	var zones: Array[Dictionary]=[]
	for z in main.water_zones: zones.append({"rect":z.rect,"level":z.level})
	data.water_zones=zones
	data.skylights.assign(main.skylights)
	data.floor_tiles=main._floor_tiles.duplicate(true)
	data.solids.assign(main.solids)
	# náhled hladin vody jen pro editor (ve hře se voda staví podle DataMapy)
	var prev:=Node3D.new()
	prev.name="Voda_nahled"
	prev.set_meta("editor_only",true)
	map.add_child(prev)
	var wm:=StandardMaterial3D.new()
	wm.albedo_color=Color(0.2,0.55,0.7,0.45)
	wm.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.cull_mode=BaseMaterial3D.CULL_DISABLED
	for i in main.water_rects.size():
		var r: Rect2=main.water_rects[i]
		var q:=MeshInstance3D.new()
		var pm:=PlaneMesh.new()
		pm.size=r.size
		q.mesh=pm
		q.material_override=wm
		q.position=Vector3(r.get_center().x,main.water_level_at(Vector3(r.get_center().x,0,r.get_center().y)),r.get_center().y)
		q.name="Hladina_%d"%(i+1)
		prev.add_child(q)
	main.queue_free()
	_own(map,map)
	var ps:=PackedScene.new()
	var err:=ps.pack(map)
	if err!=OK: push_error("pack %d"%err)
	DirAccess.make_dir_recursive_absolute("res://maps")
	err=ResourceSaver.save(ps,OUT)
	print("uloženo ",OUT," (",err,"), uzlů: ",_count(map))
	load("res://scripts/player.gd").water_at=Callable()
	load("res://scripts/zombie.gd").water_at=Callable()
	MainScript.bake_mode=false
	quit()

func _key(t: Transform3D, size: Vector3) -> String:
	return "%s|%s|%s" % [t.origin.snapped(Vector3.ONE*0.001),t.basis.get_euler().snapped(Vector3.ONE*0.001),size.snapped(Vector3.ONE*0.001)]

func _nice_name(n: Node, counts: Dictionary) -> String:
	var base:=String(n.name)
	if base.contains("@"):
		if n is MeshInstance3D:
			var m: Mesh=(n as MeshInstance3D).mesh
			if m is BoxMesh:
				var sz: Vector3=(m as BoxMesh).size
				if sz.y<0.3 and maxf(sz.x,sz.z)>1.5: base="Podlaha_Strop"
				elif sz.y>0.9 and maxf(sz.x,sz.z)>0.9: base="Zed"
				else: base="Kvadr"
			elif m is QuadMesh or m is PlaneMesh: base="Plocha"
			elif m is CylinderMesh: base="Valec"
			elif m is SphereMesh: base="Koule"
			elif m is ArrayMesh: base="Tvar"
			else: base="Mesh"
		elif n is Decal: base="Decal"
		elif n is OmniLight3D or n is SpotLight3D: base="Svetlo_lampa" if n.has_meta("lamp") else "Svetlo"
		elif n is ReflectionProbe: base="Sonda_odrazu"
		elif n is OccluderInstance3D: base="Okluder"
		elif n is StaticBody3D: base="Pevny_objekt"
		elif n is AudioStreamPlayer3D: base="Zvuk"
		elif n is GPUParticles3D: base="Castice"
		elif n is FogVolume: base="Mlha"
		elif n is Area3D: base="Oblast"
		elif n.get_child_count()>0: base="Objekt"
		else: base="Uzel"
	counts[base]=int(counts.get(base,0))+1
	return "%s_%d"%[base,counts[base]] if counts[base]>1 else base

func _own(n: Node, owner_root: Node) -> void:
	for c in n.get_children():
		c.owner=owner_root
		if c.scene_file_path=="": _own(c,owner_root)

func _count(n: Node) -> int:
	var k:=1
	for c in n.get_children(): k+=_count(c)
	return k
