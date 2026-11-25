@tool
extends Node3D
## Jednokřídlé dveře (WC, sesterna, kabinky). Počátek uzlu = pant u podlahy, křídlo míří podél +X.
@export var width:=0.95:
	set(v): width=v; _rebuild()
@export var height:=2.08:
	set(v): height=v; _rebuild()
@export_range(0.0,1.0) var open:=0.0:
	set(v): open=v; if _pivot: _pivot.rotation.y=open*1.6
@export_enum("closed","locked") var state:="closed"
@export var label:="dveře"
@export var window:=false:
	set(v): window=v; _rebuild()
@export var color:=Color(1.5,1.6,1.45):
	set(v): color=v; _rebuild()

var _pivot: Node3D

func _ready() -> void: _rebuild()

func _rebuild() -> void:
	if not is_inside_tree(): return
	if _pivot: _pivot.queue_free()
	_pivot=Node3D.new()
	add_child(_pivot,false,Node.INTERNAL_MODE_BACK)
	var m:=StandardMaterial3D.new()
	m.albedo_texture=load("res://assets/lobby/mats/painted_metal_albedo.jpg")
	m.albedo_color=color
	m.normal_enabled=true
	m.normal_texture=load("res://assets/lobby/mats/painted_metal_normal.jpg")
	m.roughness_texture=load("res://assets/lobby/mats/painted_metal_rough.jpg")
	m.uv1_triplanar=true
	m.uv1_scale=Vector3.ONE/0.6
	var leaf:=MeshInstance3D.new()
	var bm:=BoxMesh.new()
	bm.size=Vector3(width,height,0.045)
	leaf.mesh=bm
	leaf.material_override=m
	leaf.position=Vector3(width*0.5,height*0.5,0)
	_pivot.add_child(leaf)
	var sb:=StaticBody3D.new()
	var cs:=CollisionShape3D.new()
	var sh:=BoxShape3D.new()
	sh.size=bm.size
	cs.shape=sh
	sb.add_child(cs)
	leaf.add_child(sb)
	sb.set_meta("prompt","[E] "+label.capitalize())
	sb.set_meta("use",toggle)
	var knob:=StandardMaterial3D.new()
	knob.albedo_color=Color(0.55,0.5,0.42)
	knob.metallic=0.8
	knob.roughness=0.35
	for s in [-1,1]:
		var k:=MeshInstance3D.new()
		var kb:=BoxMesh.new()
		kb.size=Vector3(0.12,0.025,0.025)
		k.mesh=kb
		k.material_override=knob
		k.position=Vector3(width-0.1,1.0,s*0.04)
		_pivot.add_child(k)
	if window:
		var gl:=StandardMaterial3D.new()
		gl.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		gl.albedo_texture=load("res://assets/lobby/gen/glass_wired.png")
		gl.cull_mode=BaseMaterial3D.CULL_DISABLED
		var q:=MeshInstance3D.new()
		var qm:=QuadMesh.new()
		qm.size=Vector2(width*0.5,0.45)
		q.mesh=qm
		q.material_override=gl
		q.position=Vector3(width*0.5,1.55,0.025)
		_pivot.add_child(q)
	_pivot.rotation.y=open*1.6

func toggle() -> void:
	if state=="locked":
		get_tree().call_group("lobby_main","say","Zamčeno. %s."%label.capitalize())
		return
	var target:=0.0 if open>0.5 else 1.0
	create_tween().tween_property(self,"open",target,0.7).set_trans(Tween.TRANS_SINE)
	var s:=AudioStreamPlayer3D.new()
	s.stream=load("res://audio/gate_open.wav")
	s.pitch_scale=1.2
	s.volume_db=-16.0
	s.position=Vector3(width*0.5,1.0,0)
	add_child(s,false,Node.INTERNAL_MODE_BACK)
	s.play()
	s.finished.connect(s.queue_free)
