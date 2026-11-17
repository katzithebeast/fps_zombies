extends SceneTree
# Headless scénáře: každý zásah zvlášť na čerstvé zombie, výpis fáze/výšky/náklonu v čase.
const SCEN:={
	"hruď 1x": [["Spine2",0.0]],
	"hruď 2x": [["Spine2",0.0],["Spine2",0.35]],
	"hruď 3x (smrt)": [["Spine2",0.0],["Spine2",0.25],["Spine2",0.5]],
	"noha 1x": [["LeftLeg",0.0]],
	"noha 2x (smrt)": [["LeftLeg",0.0],["RightLeg",0.3]],
	"ruka 1x": [["RightForeArm",0.0]],
	"hlava (smrt)": [["Head",0.0]],
	"záda 3x": [["Spine2",0.0,-1],["Spine2",0.25,-1],["Spine2",0.5,-1]],
}
var floor_body: StaticBody3D
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	floor_body=StaticBody3D.new()
	var shape:=BoxShape3D.new()
	shape.size=Vector3(30,0.5,30)
	var cs:=CollisionShape3D.new()
	cs.shape=shape
	floor_body.add_child(cs)
	root.add_child(floor_body)
	floor_body.position.y=-0.25
	var failures:=0
	for name in SCEN:
		var z: Node3D=preload("res://scripts/zombie.gd").new()
		root.add_child(z)
		await create_timer(0.3).timeout
		var shots: Array=SCEN[name]
		var line:=""
		var t:=0.0
		var fired:=0
		var max_speed:=0.0
		var bad:=false
		var ph:=["IDLE","ACT","FALL","LIMP","REST"]
		var step_dt:=1.0/60.0
		var next_print:=0.0
		var hips_id:int=z.skeleton.find_bone("mixamorig_Hips")
		print("== ",name)
		while t<5.0:
			while fired<shots.size() and t>=float(shots[fired][1]):
				var bone:int=z.skeleton.find_bone("mixamorig_"+str(shots[fired][0]))
				var dirn:=Vector3.FORWARD*(float(shots[fired][2]) if shots[fired].size()>2 else 1.0)
				var p: Vector3=z.bodies[bone].global_position
				z.hit(bone,p-dirn*0.1,dirn,1.0)
				fired+=1
			await physics_frame
			t+=step_dt
			for b in z.bodies.values():
				var sp: float=b.linear_velocity.length()
				max_speed=maxf(max_speed,sp)
				if not b.global_position.is_finite() or b.global_position.y<-0.3 or b.global_position.y>4.0: bad=true
			if t>=next_print:
				next_print+=0.5
				var h:float=z.bodies[hips_id].global_position.y
				line+="  t=%.1f %s h=%.2f lean=%.2f bal=%.2f\n"%[t,ph[z.phase],h,z._lean,z._balance]
		print(line,"  maxspeed=%.1f dead=%s bad=%s"%[max_speed,z.dead,bad])
		if bad or max_speed>25.0: failures+=1
		z.queue_free()
		await process_frame
	print("SCEN FAILURES ",failures)
	quit(failures)
