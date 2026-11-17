extends SceneTree
var main: Node3D
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	main=load("res://main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.6).timeout
	main._on_play()
	await create_timer(1.5).timeout
	var mode=main.mode
	var p: Player=main.player
	p.teleport(Vector3(0,-0.35,-5),0.0,0.0)
	var ledge: Array=mode.LEDGES[0]
	var z=mode._make(1)
	z.position=ledge[0]
	main.add_child(z)
	z.target=p
	z.drop(ledge[1])
	for i in 16:
		await create_timer(0.4).timeout
		print("t=%.1f rag=%s rise=%s pos=%s infl=%.2f dead=%s" % [i*0.4,z._ragdolled,z._rag_rise,z.global_position.snapped(Vector3.ONE*0.01),z.simulator.influence,z.dead])
	quit()
