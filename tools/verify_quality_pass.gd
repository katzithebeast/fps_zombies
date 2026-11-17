extends SceneTree
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 print("PASS " if ok else "FAIL ",label)
 if not ok: failures+=1
func run() -> void:
 var world:=Node3D.new()
 root.add_child(world)
 var camera:=Camera3D.new()
 world.add_child(camera)
 camera.current=true
 var sound:=Sfx.new()
 world.add_child(sound)
 var last: AudioStream
 var repeats:=false
 for i in 100:
  var sample:=sound._pick("step_tile")
  if sample==last: repeats=true
  last=sample
 check(not repeats,"footstep recording never repeats immediately")
 var wall:=StaticBody3D.new()
 var collision:=CollisionShape3D.new()
 var box:=BoxShape3D.new()
 box.size=Vector3(4,4,0.3)
 collision.shape=box
 wall.add_child(collision)
 world.add_child(wall)
 wall.position.z=-2
 sound.play_at("zombie_groan",Vector3(0,0,-4),-5.0)
 var voice: AudioStreamPlayer3D=sound._pool3d[0]
 # Keep a real voice alive long enough to exercise the round-robin occlusion budget.
 voice.stream=AudioStreamGenerator.new()
 voice.play()
 await create_timer(1.5).timeout
 check(voice.volume_db<-10.0 and voice.attenuation_filter_cutoff_hz<2500,"wall muffles a spatial voice")
 wall.queue_free()
 await create_timer(1.5).timeout
 check(voice.volume_db>-6.0 and voice.attenuation_filter_cutoff_hz>8000,"voice clears when line of sight returns")
 var impulses: Array[Vector3]=[]
 for damage in [38.0,130.0]:
  var z=load("res://scripts/zombie.gd").new()
  world.add_child(z)
  z.health=1.0
  z.died.connect(func(_p: Vector3, impulse: Vector3, _b: int): impulses.append(impulse))
  var chest: int=z._ids.Spine2
  z.hit(chest,z.bodies[chest].global_position,Vector3.RIGHT,1.0,damage)
  await process_frame
  await process_frame
  z.queue_free()
 check(impulses.size()==2 and impulses[1].length()>impulses[0].length()*1.5,"Deagle transfers more momentum than MP40")
 check(impulses.size()==2 and impulses[0].normalized().dot(Vector3.RIGHT)>0.99,"fatal shot preserves impact direction")
 print("QUALITY CHECKS failures=",failures)
 quit(1 if failures else 0)
