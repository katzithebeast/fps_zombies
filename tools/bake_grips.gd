extends SceneTree
## Upeče úchopy zbraní (poloha rukou, ohyby prstů) → res://assets/guns_sdf/grips.res
## Spouštění: GRIP_BAKE=1 godot --headless --path . --script res://tools/bake_grips.gd
## (po změně modelu postavy, zbraní nebo úchopových bodů v scripts/hand_grip.gd)
var player: Player
func _initialize() -> void: call_deferred("run")
func tick(dt: float) -> void:
	player.weapon.update(dt)
	player.body.update_body(dt,Vector3.ZERO,0,Vector3.ZERO,false,false,true)
func run() -> void:
	if OS.get_environment("GRIP_BAKE")=="":
		push_error("spusť s GRIP_BAKE=1 (jinak se načtou stará data)")
		quit(1)
		return
	player=Player.new(); root.add_child(player); player.set_process(false); player.set_physics_process(false)
	player.body.reset(0)
	var w: Node=player.weapon
	var rig: Node=player.body.weapon
	var out:={}
	for gun in ["ak","mp40","deagle","izh54"]:
		w.give(gun,false); w.switch_to(gun,true)
		var d:={}
		for i in 600:
			tick(1.0/60.0)
			d=rig.baked_grip(gun)
			if not d.is_empty(): break
		if d.is_empty():
			push_error("úchop %s se nepodařilo spočítat (chyba R %.1f L %.1f mm)" % [gun,rig.right_error*1000,rig.left_error*1000])
			quit(1)
			return
		out[gun]=d
		print("upečeno: ",gun)
	var r:=Resource.new()
	r.set_meta("sig",rig.grip_solver.signature())
	r.set_meta("guns",out)
	var err:=ResourceSaver.save(r,"res://assets/guns_sdf/grips.res")
	print("uloženo ",err)
	quit(0 if err==OK else 1)
