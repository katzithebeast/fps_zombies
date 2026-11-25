@tool
extends Node3D
## Dvoukřídlé plechové dveře s drátosklem (assets/lobby/models/door.glb).
## Otvor 1,6 × 2,2 m, počátek uzlu = střed prahu. Křídla se otvírají klávesou E do směru +Z uzlu.
@export_enum("closed","open","ajar","locked") var state:="closed":
	set(v): state=v; if is_inside_tree(): _set_open({"open":1.0,"ajar":0.35}.get(state,0.0))
@export var label:="pokoj"
@export var swing:=1.0     ## 1 = křídla se otvírají na jednu stranu, -1 na druhou

const MODEL:="res://assets/lobby/models/door.glb"
var _pivots:=[]
var _open:=0.0
var _shape: CollisionShape3D
var _blocker: StaticBody3D

func _ready() -> void:
	var m: Node3D=load(MODEL).instantiate()
	m.scale=Vector3(1.72/375.7,2.3/356.66,0.0055)
	add_child(m,false,Node.INTERNAL_MODE_BACK)
	var a:=_local_aabb(m)
	m.position=Vector3(-a.get_center().x,-a.position.y,-a.get_center().z)
	_pivots=_split_leaves(m)
	_blocker=StaticBody3D.new()
	_shape=CollisionShape3D.new()
	var sh:=BoxShape3D.new()
	sh.size=Vector3(1.6,2.2,0.2)
	_shape.shape=sh
	_blocker.add_child(_shape)
	_blocker.position=Vector3(0,1.1,0)
	add_child(_blocker,false,Node.INTERNAL_MODE_BACK)
	_blocker.set_meta("prompt","[E] Dveře – "+label)
	_blocker.set_meta("use",toggle)
	_set_open({"open":1.0,"ajar":0.35}.get(state,0.0))

func _local_aabb(n: Node3D) -> AABB:
	var a:=AABB(); var first:=true
	var inv:=global_transform.affine_inverse() if is_inside_tree() else Transform3D()
	for c in n.find_children("*","MeshInstance3D",true,false):
		var mi: MeshInstance3D=c
		var b: AABB=(inv*mi.global_transform)*mi.get_aabb()
		if first: a=b; first=false
		else: a=a.merge(b)
	return a

func _set_open(v: float) -> void:
	_open=v
	if _pivots.size()==2:
		(_pivots[0] as Node3D).rotation.z=v*1.75*swing
		(_pivots[1] as Node3D).rotation.z=-v*1.75*swing
	if _shape: _shape.disabled=v>0.3

func toggle() -> void:
	if state=="locked":
		get_tree().call_group("lobby_main","say","Zamčeno. %s."%label.capitalize())
		_sound("res://audio/locker_open.wav",0.7,-10.0)
		return
	var target:=0.0 if _open>0.5 else 1.0
	create_tween().tween_method(_set_open,_open,target,0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sound("res://audio/gate_open.wav",0.9 if target>0.5 else 1.15,-14.0)

func _sound(f: String, pitch: float, db: float) -> void:
	var s:=AudioStreamPlayer3D.new()
	s.stream=load(f)
	s.pitch_scale=pitch
	s.volume_db=db
	s.position=Vector3(0,1.1,0)
	add_child(s,false,Node.INTERNAL_MODE_BACK)
	s.play()
	s.finished.connect(s.queue_free)

## Rozdělí síť modelu na rám a dvě křídla a pověsí křídla na panty (místní osa Z modelu = nahoru).
func _split_leaves(holder: Node3D) -> Array:
	var mis:=holder.find_children("*","MeshInstance3D",true,false)
	var host: MeshInstance3D=null
	for m in mis:
		if (m as MeshInstance3D).mesh.get_surface_count()>0 and (m as MeshInstance3D).mesh.surface_get_array_len(0)>500: host=m
	if host==null: return []
	var piv:=[]
	for side in [-1.0,1.0]:
		var p:=Node3D.new()
		p.position=Vector3(side*171.5,0,0)
		host.add_child(p)
		piv.append(p)
	var gl:=StandardMaterial3D.new()
	gl.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	gl.albedo_texture=load("res://assets/lobby/gen/glass_wired.png")
	gl.uv1_triplanar=true
	gl.uv1_world_triplanar=true
	gl.uv1_scale=Vector3.ONE/0.5
	gl.roughness=0.45
	for m in mis:
		var mi: MeshInstance3D=m
		var mesh: Mesh=mi.mesh
		var arr: Array=mesh.surface_get_arrays(0)
		var v: PackedVector3Array=arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array=arr[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			idx.resize(v.size())
			for i in v.size(): idx[i]=i
		var groups:=[[],[],[]]
		var is_glass: bool=mi!=host and mesh.surface_get_array_len(0)<50
		for t in range(0,idx.size(),3):
			var c:=(v[idx[t]]+v[idx[t+1]]+v[idx[t+2]])/3.0
			var g:=0
			if is_glass or (absf(c.x)<168.0 and c.z<342.0): g=1 if c.x<0.0 else 2
			(groups[g] as Array).append_array([idx[t],idx[t+1],idx[t+2]])
		var mat: Material=mi.get_active_material(0)
		var glass:=mat!=null and mat.resource_name.begins_with("glass")
		for g in 3:
			if (groups[g] as Array).is_empty(): continue
			var a2:=arr.duplicate()
			a2[Mesh.ARRAY_INDEX]=PackedInt32Array(groups[g])
			var am:=ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a2)
			am.surface_set_material(0,mat)
			if g==0:
				mi.mesh=am
			else:
				var leaf:=MeshInstance3D.new()
				leaf.mesh=am
				leaf.material_override=gl if glass else mat
				if glass: leaf.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var p: Node3D=piv[g-1]
				p.add_child(leaf)
				leaf.position=-p.position
		if (groups[0] as Array).is_empty() and mi!=host: mi.visible=false
	return piv
