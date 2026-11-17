extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var main=load("res://main.tscn").instantiate()
	root.add_child(main)
	main.settings["intro"]=false
	await create_timer(0.6).timeout
	main._on_play()
	await create_timer(2.0).timeout
	main.mode.begin()
	main.mode.set_meta("t",1)
	await create_timer(1.5).timeout
	var q=main.quest
	var keep=func(): main.mode.health=100.0
	main.get_tree().process_frame.connect(keep)
	var lock37=false
	for it in q.st.items: if it.get("lock37",false): lock37=true
	var nq=0
	for it in q.st.items: if it.kind=="quest": nq+=1
	print("quest items ",nq," pickups ",q._pickups.size()," lock37 ",lock37," fusebox ",not q._fuse_box.is_empty()," valves ",q._valves.size()," taps ",q._taps.size()," clock ",q._clock_hands.size()," uv ",q._uv_labels.size()," body ",is_instance_valid(q._body)," chlor ",q._chlor_items.size(), " angel_water ",q._angel_water!=null, " gate ",not q._gate.is_empty())
	print("code ",q.valve_code," clock target ",q.clock_target," now ",q.clock_now)
	for v in q._valves: print("  valve at ",v.item.node.global_position.snapped(Vector3.ONE*0.1))
	print("  fusebox at ",q._fuse_box.node.global_position.snapped(Vector3.ONE*0.1))
	print("  clock at ",q._clock_hands[0].global_position.snapped(Vector3.ONE*0.1))
	for p in q._pickups: print("  pickup ",p.lbl.call()[0]," ",p.node.global_position.snapped(Vector3.ONE*0.1))
	for l in q._uv_labels: print("  uv '",l.text.replace("\n"," "),"' ",l.global_position.snapped(Vector3.ONE*0.1))
	# zkratka celé linky
	q.fuses=3
	for i in 3: q._fuse_box.use.call()
	q._fuse_box.use.call()
	print("power ",q.power)
	for t in q._taps: t.item.use.call()
	await create_timer(0.5).timeout
	print("mirror ",q.mirror_seen," text ",q._mirror_text.text)
	while q.clock_now!=q.clock_target: q.clock_now=(q.clock_now+15)%720
	q.clock_now=(q.clock_target+705)%720
	var clock_item=null
	for it in q.st.items:
		if it.kind=="quest" and it.lbl.call().size()>0 and String(it.lbl.call()[0]).begins_with("Hodiny"): clock_item=it
	clock_item.use.call()
	await create_timer(6.0).timeout
	print("clock_done ",q.clock_done," pickups ",q._pickups.size())
	for p in q._pickups.duplicate():
		if p.lbl.call()[0]=="Ventilové kolo": p.use.call()
	print("wheel ",q.has_wheel)
	q._valves[2].item.use.call()
	for v in q._valves:
		for k in q.valve_code[v.index]: v.item.use.call()
	print("valves ",q.valves_done)
	for p in q._pickups.duplicate():
		if p.lbl.call()[0]=="Klíč od čerpadel": p.use.call()
	print("key ",q.has_key)
	q._pump.use.call()
	print("drain stage ",q.drain_stage)
	for i in 6:
		if q.drained: break
		q._pump_jam=false; q._jam_at=-1.0; q._stage_t=39.95
		await create_timer(0.2).timeout
		print(" stage ",q.drain_stage," lvl ",snapped(q._angel_zone.level,0.1))
	print(" drained ",q.drained," lvl ",snapped(q._angel_zone.level,0.1))
	await create_timer(6.5).timeout
	print("gate ",q._gate.state," locked ",q._gate.locked)
	print("water at pit ",main.water_level_at(Vector3(33,0,-18))," cistern ",main.water_level_at(Vector3(34,0,-50)))
	main.player.teleport(Vector3(30.0,-14.2,-14.0),0.0,0.0)
	await create_timer(1.5).timeout
	print("player pit pos ",main.player.global_position.snapped(Vector3.ONE*0.1)," swim ",main.player.swimming)
	main.player.teleport(Vector3(33.5,-14.2,-46.0),0.0,0.0)
	await create_timer(1.5).timeout
	main.mode.health=100.0
	print("mode ",main.mode.active," ",main.mode.state," hp ",main.mode.health)
	print("player cistern ",main.player.global_position.snapped(Vector3.ONE*0.1)," boss ",q.boss_state)
	await create_timer(7.0).timeout
	print("boss ",q.boss_state," weak ",q._weak.size())
	for w in q._weak:
		while w.hp>0: q.shot(w.body,w.body.global_position,Vector3.FORWARD)
	print("boss ",q.boss_state)
	await create_timer(1.0).timeout
	var note=null
	for p in q._pickups: if p.lbl.call()[0]=="Lístek": note=p
	print("note ",note!=null)
	note.use.call(); await create_timer(0.3).timeout; main.notes.close()
	await create_timer(12.0).timeout
	print("ended ",q.ended)
	quit()
