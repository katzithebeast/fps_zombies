## Stupně reakce: jak často rána porazí / rozhoupe (vrávorání) zombii, zbraň × část těla.
##   godot --headless --fixed-fps 60 --path . --script res://tools/t_hit_tiers.gd
extends SceneTree
const Z:=preload("res://scripts/zombie.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var fb:=StaticBody3D.new(); var cs:=CollisionShape3D.new(); var bs:=BoxShape3D.new(); bs.size=Vector3(80,1,80); cs.shape=bs; cs.position.y=-0.5; fb.add_child(cs); root.add_child(fb)
	var res:={}
	for w in [["mp40",38.0,1.0,1],["ak",50.0,1.0,1],["deagle",130.0,1.0,1],["izh54",40.0,0.45,9]]:
		for part in ["Spine2","Head","LeftArm","Spine"]:
			var kd:=0; var st:=0
			for trial in 6:
				var z: Node3D=Z.new(); z.max_health=5000; z.health=5000; z.position=Vector3(randf_range(-30,30),0,randf_range(-30,30)); root.add_child(z)
				for i in 12: await physics_frame
				var b: int=z._ids[part]
				for p in int(w[3]): z.hit(b,z.bodies[b].global_position+Vector3(randf_range(-0.04,0.04),randf_range(-0.04,0.04),0.05),Vector3.FORWARD,w[2],w[1])
				var s: bool=z._stagger_clip!=""
				for i in 10: await physics_frame
				if z._ragdolled: kd+=1
				elif s: st+=1
				z.queue_free()
			print("%-7s %-7s  pád %d/6  vrávorání %d/6" % [w[0],part,kd,st])
	quit()
