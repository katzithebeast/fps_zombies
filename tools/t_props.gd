extends SceneTree
# Test stanic: bedna, skříňka, munice, stůl, bonusy. --shots uloží snímky.
var main: Node3D
var mode: Node
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	main=load("res://main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.6).timeout
	mode=main.mode
	main._on_play()
	await create_timer(1.5).timeout
	var p: Player=main.player
	p.weapon.equip()
	mode.begin()
	mode.points=20000
	mode.health=100000.0
	var st=mode.stations
	print("stanic ",st.items.size())
	var shots:="--shots" in OS.get_cmdline_user_args()
	var only:=""
	for a in OS.get_cmdline_user_args(): if a.begins_with("--only="): only=a.substr(7)
	for item in st.items:
		if only!="" and item.kind!=only: continue
		var pos: Vector3=item.pos
		var yaw: float=item.node.rotation.y
		var front:=Basis(Vector3.UP,yaw)*Vector3(0,0,1.6 if item.kind in ["crate","ammo","bench"] else -1.6)
		if item.kind=="gate": front=Vector3(-1.6,0,0)
		p.teleport(pos+front+Vector3(0,0.1,0),atan2(front.x,front.z),-0.35)
		mode.health=100000.0
		await create_timer(0.5).timeout
		print(item.kind," popis='",st.prompt_text,"' mode=",mode.state)
		if shots:
			main.player.camera.get_parent()
			root.get_texture().get_image().save_png("/tmp/ws/st0_%s.png"%item.kind)
		var before_gun: String=p.weapon.current
		st._use(item)
		await create_timer(3.2).timeout
		if shots: root.get_texture().get_image().save_png("/tmp/ws/st_%s.png"%item.kind)
		if item.kind=="locker" and item.show: print("  cena lezi na y=",snappedf(item.show.global_position.y-item.pos.y,0.01))
		print("  stav=",item.state," gun=",item.gun," prize=",item.prize," popis='",st.prompt_text,"'")
		if item.state=="ready": st._use(item)
		await create_timer(0.3).timeout
		print("  po: zbran ",before_gun,"->",p.weapon.current," upgr=",p.weapon.upgraded," jmeno=",p.weapon.display_name()," body=",mode.points," zdravi=",mode.health)
	# bonusy
	for kind in ["insta","heal","kaboom","ammo"]:
		mode.health=40.0
		mode._drop(kind,p.global_position+Vector3(0.5,0,0))
		await create_timer(1.2).timeout
		print(kind," zbyva bonusu ",mode._powerups.size()," zdravi=",mode.health)
	quit()
