extends Node3D
## Odložená AK ve vstupní místnosti. Sebrání se provede jen jednou.
var collected := false
var _material: StandardMaterial3D
var _label: Label3D

func _ready() -> void:
	var gun: Node3D = preload("res://assets/ak47/ak47.tscn").instantiate()
	gun.rotation = Vector3(0.0, -0.5, PI/2)
	add_child(gun)
	_label = Label3D.new()
	_label.text = "AK-47"
	_label.position.y = 0.38
	_label.font_size = 38
	_label.pixel_size = 0.003
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color(1.0,0.82,0.48)
	add_child(_label)

func part(size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh=box
	mesh.position=at
	mesh.material_override=material
	add_child(mesh)

func set_highlight(value: bool) -> void:
	if _material:
		_material.emission_energy_multiplier = 0.65 if value else 0.12

func collect() -> bool:
	if collected:
		return false
	collected=true
	visible=false
	return true

func reset() -> void:
	collected=false
	visible=true
