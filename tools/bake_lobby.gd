extends SceneTree
## Vygeneruje mapu pokoje a křídla sanatoria kódem a uloží ji jako normální scénu maps/lobby_map.tscn.
## POZOR: přepíše ruční úpravy v té scéně! Spouštět jen pro novou mapu od nuly.
##   godot --headless --path . --script res://tools/bake_lobby.gd
const OUT:="res://maps/lobby_map.tscn"

# oblasti křídla (x0, x1, z0, z1) → složka ve scéně
const ZONES:=[
	["Pokoj_7",-2.76,2.76,-2.2,2.16],
	["Pokoj_8",2.74,8.26,-2.2,2.16],
	["Pokoj_9",8.24,13.76,-2.2,2.16],
	["Schodiste",-7.5,-4.55,1.8,4.7],
	["Chodba",-4.6,13.76,2.1,4.5],
	["Pokoj_10",-2.76,2.76,4.3,8.7],
	["WC_umyvarna",2.74,9.26,4.3,8.7],
	["Sesterna",9.24,13.76,4.3,8.7],
	["Spolecenska_mistnost",13.7,24.3,-2.2,8.7],
]

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var L:=load("res://scripts/lobby.gd")
	L.bake=true
	var lob:=Node3D.new()
	lob.set_script(L)
	root.add_child(lob)
	for i in 3: await process_frame
	var map:=Node3D.new()
	map.name="LobbyMap"
	root.add_child(map)
	var folders:={}
	for z in ZONES: folders[z[0]]=_folder(map,z[0])
	folders["Prostredi"]=_folder(map,"Prostredi")
	folders["Venku"]=_folder(map,"Venku")
	var counts:={}
	for c in lob.get_children():
		var n: Node=c
		var dest:=_zone_for(n)
		var f: Node3D=folders[dest]
		n.name=_nice_name(n,counts)
		n.reparent(f,true)
	lob.queue_free()
	_own(map,map)
	var ps:=PackedScene.new()
	var err:=ps.pack(map)
	if err!=OK: push_error("pack %d"%err)
	DirAccess.make_dir_recursive_absolute("res://maps")
	err=ResourceSaver.save(ps,OUT)
	print("uloženo ",OUT," (",err,"), uzlů: ",_count(map))
	quit()

func _folder(parent: Node3D, n: String) -> Node3D:
	var f:=Node3D.new()
	f.name=n
	parent.add_child(f)
	return f

func _pos(n: Node) -> Vector3:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi: MeshInstance3D=n
		return (mi.global_transform*mi.get_aabb()).get_center()
	if n is Node3D: return (n as Node3D).global_position
	return Vector3.ZERO

func _zone_for(n: Node) -> String:
	if n is WorldEnvironment or n is DirectionalLight3D or n is GPUParticles3D or n is Marker3D: return "Prostredi"
	if n is AudioStreamPlayer3D and (n as Node3D).position.distance_to(Vector3(0,1.5,0))<0.1: return "Prostredi"
	var p:=_pos(n)
	if absf(p.z)>12.0 or p.x>30.0: return "Venku"
	for z in ZONES:
		if p.x>=z[1] and p.x<=z[2] and p.z>=z[3] and p.z<=z[4]: return z[0]
	return "Prostredi"

func _nice_name(n: Node, counts: Dictionary) -> String:
	var base:=String(n.name)
	if base.begins_with("@") or base.contains("@"):
		if n is MeshInstance3D:
			var m: Mesh=(n as MeshInstance3D).mesh
			if m is QuadMesh: base="Papir"
			elif m is CylinderMesh: base="Trubka"
			elif m is SphereMesh: base="Koule"
			elif m is BoxMesh:
				var sz: Vector3=(m as BoxMesh).size
				base="Zed" if maxf(sz.x,sz.z)>0.9 and sz.y>0.9 else "Kvadr"
				if sz.y<0.25 and maxf(sz.x,sz.z)>1.5: base="Podlaha_Strop"
			else: base="Mesh"
		elif n is Decal: base="Spina"
		elif n is StaticBody3D: base="Interakce"
		elif n is OmniLight3D or n is SpotLight3D: base="Svetlo"
		elif n is AudioStreamPlayer3D: base="Zvuk"
		elif n is GPUParticles3D: base="Prach"
		elif n is WorldEnvironment: base="Prostredi_svetlo"
		elif n is DirectionalLight3D: base="Slunce"
		elif n.get_child_count()>0: base="Vybaveni"
		else: base="Uzel"
	counts[base]=int(counts.get(base,0))+1
	return "%s_%d"%[base,counts[base]] if counts[base]>1 else base

## Vlastník = kořen mapy (uloží se). Do instancí modelů (.glb) a do vnitřků komponent se nejde.
func _own(n: Node, owner_root: Node) -> void:
	for c in n.get_children():
		c.owner=owner_root
		if c.scene_file_path=="": _own(c,owner_root)

func _count(n: Node) -> int:
	var k:=1
	for c in n.get_children(): k+=_count(c)
	return k
