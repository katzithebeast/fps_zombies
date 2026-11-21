## Síla zásahů: špičková odchylka fyzikálního těla od animace (°) pro zbraň × část těla.
##   godot --headless --fixed-fps 60 --path . --script res://tools/t_hit_strength.gd
extends SceneTree
const Z:=preload("res://scripts/zombie.gd")
func _initialize() -> void: call_deferred("run")
func err(z, id) -> float:
	var G: Array=z._anim_globals()
	var body: PhysicalBone3D=z.bodies[id]
	var tgt: Basis=(z.skeleton.global_basis*(G[id] as Transform3D).basis*body.body_offset.basis).orthonormalized()
	return rad_to_deg((z._rotation_error(tgt,body.global_basis) as Vector3).length())
func run() -> void:
	var fb:=StaticBody3D.new(); var cs:=CollisionShape3D.new(); var bs:=BoxShape3D.new(); bs.size=Vector3(80,1,80); cs.shape=bs; cs.position.y=-0.5; fb.add_child(cs); root.add_child(fb)
	Z.knockdowns=false
	var x:=-30.0
	for w in [["mp40",38.0,1.0,1],["ak",50.0,1.0,1],["deagle",130.0,1.0,1],["izh54",40.0,0.45,9]]:
		for part in ["Spine2","Head","LeftArm","LeftForeArm","Spine"]:
			var z: Node3D=Z.new(); z.max_health=5000; z.health=5000; z.position=Vector3(x,0,0); x+=2.5; root.add_child(z)
			for i in 20: await physics_frame
			var b: int=z._ids[part]
			var yaw0: float=z.rotation.y
			var p0: Vector3=z.global_position
			for p in int(w[3]): z.hit(b,z.bodies[b].global_position+Vector3(randf_range(-0.04,0.04),randf_range(-0.04,0.04),0.05),Vector3.FORWARD,w[2],w[1])
			var peak:={}
			var stag: String=z._stagger_clip
			var yawmax:=0.0
			for i in 60:
				await physics_frame
				yawmax=maxf(yawmax,absf(rad_to_deg(wrapf(z.rotation.y-yaw0,-PI,PI))))
				if z._hitrag_on:
					for nm in ["Spine2","Head","LeftArm","LeftForeArm"]: peak[nm]=maxf(float(peak.get(nm,0.0)),err(z,z._ids[nm]))
			var line:="%-7s -> %-11s"%[w[0],part]
			for nm in ["Spine2","Head","LeftArm","LeftForeArm"]: line+=" %s %3d°"%[nm,int(peak.get(nm,0))]
			print(line,"  otočení %2d°  posun %.2f m  %s"%[int(yawmax),z.global_position.distance_to(p0),stag])
			z.queue_free()
	quit()
