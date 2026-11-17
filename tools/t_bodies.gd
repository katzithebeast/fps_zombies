extends SceneTree
var main: Node3D
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	main=load("res://main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.6).timeout
	main._on_play()
	await create_timer(6.0).timeout
	var Z=load("res://scripts/zombie.gd")
	var dead:=0
	var sleeping:=0
	for z in main.get_children():
		if z.get_script()==Z:
			if z.dead: dead+=1
			elif z._sleeping: sleeping+=1
	print("mrtvol=",dead," spicich=",sleeping," krev=",main.find_children("*","Decal",true,false).size())
	var p: Player=main.player
	p.teleport(Vector3(-6.0,-0.35,-20.5),PI,0.0)
	await create_timer(4.0).timeout
	for z in main.get_children():
		if z.get_script()==Z and not z.dead and z.global_position.distance_to(Vector3(-6,-0.35,-23.8))<3.0:
			print("spici u haly: sleeping=",z._sleeping," ai=",z.ai," rag=",z._ragdolled," pos=",z.global_position.snapped(Vector3.ONE*0.1))
	quit()
