@tool
extends Node3D
## Skutečné zrcadlo: lícem ve směru +Z uzlu. Ve hře odražená kamera (SubViewport), v editoru jen šedá plocha.
@export var size:=Vector2(0.44,0.56):
	set(v): size=v; _rebuild()
@export var resolution:=1200.0

const LAYER:=1<<10
var _quad: MeshInstance3D
var _cam: Camera3D
var _vp: SubViewport
var _on:=true

func _ready() -> void: _rebuild()

func _rebuild() -> void:
	if not is_inside_tree(): return
	for c in get_children(true):
		if c.get_meta("mirror_part",false): c.queue_free()
	_quad=MeshInstance3D.new()
	var q:=QuadMesh.new()
	q.size=size
	_quad.mesh=q
	_quad.layers=LAYER
	_quad.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.set_meta("mirror_part",true)
	add_child(_quad,false,Node.INTERNAL_MODE_BACK)
	if Engine.is_editor_hint():
		var m:=StandardMaterial3D.new()
		m.albedo_color=Color(0.7,0.72,0.72)
		m.metallic=1.0
		m.roughness=0.05
		_quad.material_override=m
		return
	_vp=SubViewport.new()
	_vp.size=Vector2i(int(size.x*resolution),int(size.y*resolution))
	_vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d=Viewport.MSAA_2X
	_vp.set_meta("mirror_part",true)
	add_child(_vp,false,Node.INTERNAL_MODE_BACK)
	_cam=Camera3D.new()
	_cam.projection=Camera3D.PROJECTION_FRUSTUM
	_cam.cull_mask=0xFFFFF & ~8 & ~LAYER       # celé tělo hráče (vrstva 4) ano, kopie pro vlastní pohled (8) ne
	_vp.add_child(_cam)
	var sm:=ShaderMaterial.new()
	sm.shader=load("res://shaders/lobby_mirror.gdshader")
	sm.set_shader_parameter("reflection",_vp.get_texture())
	sm.set_shader_parameter("wear",load("res://assets/lobby/gen/mirror_albedo.jpg"))
	_quad.material_override=sm
	var vis:=VisibleOnScreenNotifier3D.new()
	vis.aabb=AABB(Vector3(-size.x*0.5,-size.y*0.5,-0.05),Vector3(size.x,size.y,0.1))
	_quad.add_child(vis)
	vis.screen_entered.connect(func(): _on=true; _vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS)
	vis.screen_exited.connect(func(): _on=false; _vp.render_target_update_mode=SubViewport.UPDATE_DISABLED)
	process_priority=100

func _process(_dt: float) -> void:
	if Engine.is_editor_hint() or _cam==null or not _on: return
	var view:=get_viewport().get_camera_3d()
	if view==null: return
	var n:=global_basis.z.normalized()
	var c:=global_position
	var e:=view.global_position
	var e2:=e-2.0*(e-c).dot(n)*n
	var z:=-n
	var x:=Vector3.UP.cross(z).normalized()
	var y:=z.cross(x)
	_cam.global_transform=Transform3D(Basis(x,y,z),e2)
	var local:=_cam.global_transform.affine_inverse()*c
	_cam.set_frustum(size.y,Vector2(local.x,local.y),maxf(-local.z,0.02),40.0)
