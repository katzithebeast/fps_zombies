@tool
extends Node3D
## Vymění materiál vybrané plochy uvnitř modelu (podle jména materiálu v modelu), např. deku na posteli.
@export var surface_name:="":
	set(v): surface_name=v; _apply()
@export var material: Material:
	set(v): material=v; _apply()

func _ready() -> void: _apply.call_deferred()

func _apply() -> void:
	if not is_inside_tree() or material==null or surface_name=="": return
	for m in find_children("*","MeshInstance3D",true,false):
		var mi: MeshInstance3D=m
		if mi.mesh==null: continue
		for i in mi.mesh.get_surface_count():
			var mt:=mi.mesh.surface_get_material(i)
			if mt and mt.resource_name==surface_name: mi.set_surface_override_material(i,material)
