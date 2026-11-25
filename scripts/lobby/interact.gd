extends StaticBody3D
## Věc, se kterou jde v pokoji použít E (rádio, televize, skříňka, mříž…).
## `action` vyřizuje lobby.gd (_on_action); `message` se jen ukáže dole na obrazovce.
@export var prompt:="[E] Použít"
@export var action:=""
@export_multiline var message:=""

func _ready() -> void:
	set_meta("prompt",prompt)
	set_meta("use",use)

func use() -> void:
	if action!="": get_tree().call_group("lobby_main","_on_action",action,self)
	elif message!="": get_tree().call_group("lobby_main","say",message)
