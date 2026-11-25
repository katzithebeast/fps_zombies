@tool
extends Node3D
## Stropní zářivka. Počátek uzlu = bod na stropě. mode: ok, flicker (jiskří a bliká), rare (občas cvakne), dead.
@export var energy:=1.1:
	set(v): energy=v; _rebuild()
@export var shadow:=false:
	set(v): shadow=v; _rebuild()
@export_enum("ok","flicker","rare","dead") var mode:="ok":
	set(v): mode=v; _rebuild()
@export var hum:=false

var _root: Node3D
var _light: SpotLight3D
var _fill: OmniLight3D
var _tube_mat: StandardMaterial3D
var _t:=3.0
var _f:=0.0

func _ready() -> void:
	_rebuild()
	if hum and not Engine.is_editor_hint():
		var a:=AudioStreamPlayer3D.new()
		var s: AudioStreamWAV=(load("res://audio/lamp_hum.wav") as AudioStreamWAV).duplicate()
		s.loop_mode=AudioStreamWAV.LOOP_FORWARD
		s.loop_end=int(s.get_length()*s.mix_rate)
		a.stream=s
		a.volume_db=-22.0
		a.unit_size=2.0
		a.position=Vector3(0,-0.45,0)
		add_child(a,false,Node.INTERNAL_MODE_BACK)
		a.play()

func _rebuild() -> void:
	if not is_inside_tree(): return
	if _root: _root.queue_free()
	_root=Node3D.new()
	add_child(_root,false,Node.INTERNAL_MODE_BACK)
	var housing:=StandardMaterial3D.new()
	housing.albedo_texture=load("res://assets/lobby/mats/painted_metal_albedo.jpg")
	housing.albedo_color=Color(1.9,1.95,1.9)
	housing.uv1_triplanar=true
	housing.uv1_scale=Vector3.ONE/0.5
	_box(Vector3(1.25,0.07,0.16),Vector3(0,-0.42,0),housing)
	var rod:=StandardMaterial3D.new()
	rod.albedo_color=Color(0.3,0.3,0.3)
	rod.metallic=0.8
	for s in [-0.45,0.45]: _cyl(0.006,0.38,Vector3(s,-0.19,0),rod,Vector3.ZERO)
	_tube_mat=StandardMaterial3D.new()
	_tube_mat.albedo_color=Color(0.9,0.93,0.95) if mode!="dead" else Color(0.55,0.55,0.52)
	_tube_mat.emission_enabled=mode!="dead"
	_tube_mat.emission=Color(0.85,0.95,1.0)
	_tube_mat.emission_energy_multiplier=5.0
	var tube:=_cyl(0.016,1.15,Vector3(0,-0.47,0),_tube_mat,Vector3(0,0,PI/2))
	tube.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light=null
	_fill=null
	if mode=="dead": return
	_light=SpotLight3D.new()
	_light.position=Vector3(0,-0.5,0)
	_light.rotation.x=-PI/2
	_light.spot_angle=80.0
	_light.spot_range=5.5
	_light.spot_attenuation=0.7
	_light.light_color=Color(0.86,0.94,1.0)
	_light.light_energy=energy
	_light.light_volumetric_fog_energy=0.2
	_light.shadow_enabled=shadow
	_root.add_child(_light)
	_fill=OmniLight3D.new()
	_fill.position=Vector3(0,-0.55,0)
	_fill.omni_range=4.0
	_fill.light_color=Color(0.86,0.94,1.0)
	_fill.light_energy=energy*0.22
	_fill.light_volumetric_fog_energy=0.0
	_root.add_child(_fill)

func _box(size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi:=MeshInstance3D.new()
	var b:=BoxMesh.new()
	b.size=size
	mi.mesh=b
	mi.material_override=m
	mi.position=pos
	_root.add_child(mi)
	return mi

func _cyl(r: float, h: float, pos: Vector3, m: Material, rot: Vector3) -> MeshInstance3D:
	var mi:=MeshInstance3D.new()
	var c:=CylinderMesh.new()
	c.top_radius=r
	c.bottom_radius=r
	c.height=h
	c.radial_segments=12
	mi.mesh=c
	mi.material_override=m
	mi.position=pos
	mi.rotation=rot
	_root.add_child(mi)
	return mi

func _process(dt: float) -> void:
	if Engine.is_editor_hint() or _light==null or not (mode in ["flicker","rare"]): return
	_t-=dt
	if _t<=0.0:
		_t=randf_range(1.5,6.0) if mode=="flicker" else randf_range(6.0,18.0)
		_f=randf_range(0.2,1.2) if mode=="flicker" else randf_range(0.25,0.6)
		var c:=AudioStreamPlayer3D.new()
		c.stream=load("res://audio/lamp_spark_%d.wav"%randi_range(1,2) if mode=="flicker" else "res://audio/lamp_click.wav")
		c.volume_db=-16.0
		c.unit_size=2.0
		c.position=Vector3(0,-0.45,0)
		add_child(c,false,Node.INTERNAL_MODE_BACK)
		c.play()
		c.finished.connect(c.queue_free)
	var k:=1.0
	if _f>0.0:
		_f-=dt
		var ms:=Time.get_ticks_msec()*0.001
		k=(0.05 if mode=="flicker" else 0.25) if fmod(ms*17.0+sin(ms*3.7)*3.0,1.0)<0.5 else 1.0
	_light.light_energy=energy*k
	_fill.light_energy=energy*0.22*k
	_tube_mat.emission_energy_multiplier=5.0*k
