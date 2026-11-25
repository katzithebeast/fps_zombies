extends RefCounted
## Křídlo sanatoria kolem karanténního pokoje: chodba, další tři pokoje, společné WC a umývárna,
## sesterna, společenská místnost a uzavřené schodiště. Staví se do uzlu lobby (L) jeho pomocníky.

var L: Node3D
const H:=3.2
const T:=0.25
const TILE_H:=1.45
const CZ0:=2.15            # chodba: vnitřní líc severní zdi
const CZ1:=4.35            #         vnitřní líc jižní zdi
const CX0:=-4.6            # konec chodby u schodiště (mříž)
const CX1:=13.75           # vstup do společenské místnosti
const SZ0:=4.6             # jižní pokoje: vnitřní z
const SZ1:=8.4
const HALL:=Rect2(14.25,-1.9,9.75,10.3)   # x, z, šířka, hloubka (vnitřek)

var doors:=[]
var _paint: Material
var _tiles: Material
var _cap: Material

func build(lobby: Node3D) -> void:
	L=lobby
	_paint=L.mat("gen/paint_green",1.7,Color(1.04,0.97,0.9))
	_tiles=L.mat("ceramic_tiles",0.8,Color(0.97,0.97,0.94))
	_cap=L.flat(Color(0.2,0.27,0.24),0.35)
	for f in ["_corridor","_stairwell","_rn8","_rn9","_rs10","_washroom","_nurse","_hall","_backdrops"]:
		var t0:=Time.get_ticks_msec()
		call(f)
		if OS.get_environment("LOBBY_PROFILE")=="1": print("  ",f," ",Time.get_ticks_msec()-t0," ms")

func _rn8() -> void: _room_north(5.5,"8","open")
func _rn9() -> void: _room_north(11.0,"9","locked")
func _rs10() -> void: _room_south(0.0,"10","ajar")

# ------------------------------------------------------------------ obecné stavební díly

## Zeď podél osy: "x" = běží v ose x na líci z=`line`, tloušťka do směru `dir` (±1).
## Otvory: [od, do, y0, y1] v ose zdi. Zbytek zdi se poskládá z kvádrů kolem otvorů.
func wall(axis: String, line: float, dir: float, a0: float, a1: float, holes: Array, top: float, t: float, m: Material, collide:=true, base:=0.0) -> void:
	var hs:=holes.duplicate()
	hs.sort_custom(func(p,q): return float(p[0])<float(q[0]))
	var cur:=a0
	for h in hs:
		var h0:=clampf(float(h[0]),a0,a1); var h1:=clampf(float(h[1]),a0,a1)
		if h0>cur: _seg(axis,line,dir,cur,h0,base,top,t,m,collide)
		if float(h[2])>base: _seg(axis,line,dir,h0,h1,base,minf(float(h[2]),top),t,m,collide)
		if float(h[3])<top: _seg(axis,line,dir,h0,h1,maxf(float(h[3]),base),top,t,m,collide)
		cur=maxf(cur,h1)
	if cur<a1: _seg(axis,line,dir,cur,a1,base,top,t,m,collide)

func _seg(axis: String, line: float, dir: float, p0: float, p1: float, y0: float, y1: float, t: float, m: Material, collide: bool) -> void:
	if p1-p0<0.002 or y1-y0<0.002: return
	var q0:=minf(line,line+dir*t); var q1:=maxf(line,line+dir*t)
	if axis=="x": L.slab(Vector3(p0,y0,q0),Vector3(p1,y1,q1),m,collide)
	else: L.slab(Vector3(q0,y0,p0),Vector3(q1,y1,p1),m,collide)

## Obklad (nebo sokl) na líci zdi do výšky TILE_H s lištou, s vynechanými otvory.
func clad(axis: String, line: float, inward: float, a0: float, a1: float, holes: Array, m: Material=null) -> void:
	var hs:=[]
	for h in holes:
		if float(h[2])<TILE_H: hs.append([h[0],h[1],0.0,TILE_H+0.1])
	wall(axis,line,inward,a0,a1,hs,TILE_H,0.016,m if m else _tiles,false)
	wall(axis,line,inward,a0,a1,hs,TILE_H+0.035,0.03,_cap,false,TILE_H)

## Místnost: podlaha, strop, čtyři zdi (vně vnitřního obdélníku), obklad uvnitř.
## open = {"n":[[x0,x1,y0,y1]], "s":…, "w":[[z0,z1,y0,y1]], "e":…} ve světových souřadnicích.
func room(r: Rect2, open: Dictionary, floor_m: Material, opts:={}) -> void:
	var x0:=r.position.x; var x1:=r.end.x; var z0:=r.position.y; var z1:=r.end.y
	var paint: Material=opts.get("paint",_paint)
	L.slab(Vector3(x0-T,-0.2,z0-T),Vector3(x1+T,0.0,z1+T),floor_m)
	L.slab(Vector3(x0-T,H,z0-T),Vector3(x1+T,H+0.2,z1+T),opts.get("ceiling",L.mat("gen/plaster",1.9)))
	if not opts.get("skip",[]).has("n"): wall("x",z0,-1,x0-T,x1+T,open.get("n",[]),H,T,paint)
	if not opts.get("skip",[]).has("s"): wall("x",z1,1,x0-T,x1+T,open.get("s",[]),H,T,paint)
	if not opts.get("skip",[]).has("w"): wall("z",x0,-1,z0,z1,open.get("w",[]),H,T,paint)
	if not opts.get("skip",[]).has("e"): wall("z",x1,1,z0,z1,open.get("e",[]),H,T,paint)
	if opts.get("tiles",true):
		var tm: Material=opts.get("tile_mat",_tiles)
		clad("x",z0,1,x0,x1,open.get("n",[]),tm)
		clad("x",z1,-1,x0,x1,open.get("s",[]),tm)
		clad("z",x0,1,z0,z1,open.get("w",[]),tm)
		clad("z",x1,-1,z0,z1,open.get("e",[]),tm)

## Okno v lokálním rámu: počátek na vnitřním líci zdi uprostřed okna, +Z míří do místnosti.
func window(origin: Vector3, yaw: float, w: float, y0: float, y1: float, frosted:=false, bars:=true, radiator:=true) -> void:
	var f:=Node3D.new()
	L.add_child(f)
	f.global_transform=Transform3D(Basis(Vector3.UP,yaw),origin)
	var frame=L.mat("painted_metal",0.5,Color(2.2,2.3,2.2),0.6)
	var hgt:=y1-y0; var zf:=-0.14; var e:=0.06
	L.box(Vector3(w,e,0.08),Vector3(0,y0+e*0.5,zf),frame,false,f)
	L.box(Vector3(w,e,0.08),Vector3(0,y1-e*0.5,zf),frame,false,f)
	L.box(Vector3(e,hgt,0.08),Vector3(-w*0.5+e*0.5,(y0+y1)*0.5,zf),frame,false,f)
	L.box(Vector3(e,hgt,0.08),Vector3(w*0.5-e*0.5,(y0+y1)*0.5,zf),frame,false,f)
	L.box(Vector3(0.05,hgt,0.07),Vector3(0,(y0+y1)*0.5,zf),frame,false,f)
	L.box(Vector3(w,0.05,0.07),Vector3(0,y0+hgt*0.68,zf),frame,false,f)
	var glass:=StandardMaterial3D.new()
	glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_texture=load(L.M+("gen/glass_wired.png" if frosted else "gen/glass_dirty.png"))
	glass.albedo_color=Color(1,1,1,1.0 if frosted else 0.9)
	glass.roughness=0.4 if frosted else 0.15
	glass.cull_mode=BaseMaterial3D.CULL_DISABLED
	for side in [-1,1]:
		var q:=MeshInstance3D.new()
		var qm:=QuadMesh.new()
		qm.size=Vector2(w*0.5-0.085,hgt-0.12)
		q.mesh=qm
		q.material_override=glass
		q.position=Vector3(side*(w*0.25),(y0+y1)*0.5,zf)
		q.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.add_child(q)
	L.box(Vector3(w+0.12,0.05,0.13),Vector3(0,y0-0.015,0.005),L.mat("terrazzo",0.8,Color(1.15,1.15,1.15)),true,f)
	if bars:
		var bm=L.mat("rusty_metal",0.4,Color(0.75,0.72,0.7))
		var n:=int(round(w/0.22))+1
		for i in n: L.cyl(0.011,hgt+0.06,Vector3(lerpf(-w*0.5+0.1,w*0.5-0.1,float(i)/float(n-1)),(y0+y1)*0.5,-0.03),bm,Vector3.ZERO,f)
		for yy in [y0+0.25,y1-0.25]: L.cyl(0.012,w+0.04,Vector3(0,yy,-0.03),bm,Vector3(0,0,PI/2),f)
	if radiator:
		var rad=L.mat("painted_metal",0.5,Color(2.0,2.05,1.95),0.8)
		var cnt:=int(w/0.065)
		for i in cnt: L.box(Vector3(0.045,0.58,0.16),Vector3(-cnt*0.026+i*0.052,0.47,0.12),rad,i==0,f)
		L.cyl(0.02,cnt*0.052+0.06,Vector3(0,0.2,0.12),rad,Vector3(0,0,PI/2),f)
		L.cyl(0.02,cnt*0.052+0.06,Vector3(0,0.74,0.12),rad,Vector3(0,0,PI/2),f)

## Zářivka pod stropem (scripts/lobby/lamp_fixture.gd). mode: ok, flicker, rare, dead.
func lamp(p: Vector3, energy:=1.1, shadow:=false, mode:="ok", along_z:=false, hum:=false) -> void:
	var n:=Node3D.new()
	n.name="Zarivka"
	n.set_script(load("res://scripts/lobby/lamp_fixture.gd"))
	n.position=p
	n.rotation.y=PI/2 if along_z else 0.0
	L.add_child(n)
	n.energy=energy
	n.shadow=shadow
	n.mode=mode
	n.hum=hum

# ------------------------------------------------------------------ dveře

## Dvoukřídlé plechové dveře (scripts/lobby/door_double.gd). facing = otočení (180 = líc na sever).
func double_door(cx: float, zc: float, facing: float, state: String, label: String, swing:=1.0) -> Node3D:
	var n:=Node3D.new()
	n.name="Dvere"
	n.set_script(load("res://scripts/lobby/door_double.gd"))
	n.position=Vector3(cx,0,zc)
	n.rotation.y=deg_to_rad(facing)
	n.label=label
	n.swing=swing
	L.add_child(n)
	n.state=state
	doors.append(n)
	return n

## Jednokřídlé dveře (scripts/lobby/door_single.gd): pant v `hinge`, křídlo míří podél `yaw`.
func single_door(hinge: Vector3, yaw: float, w: float, h: float, open: float, m: Variant, label: String, state:="closed", window:=false) -> Node3D:
	var n:=Node3D.new()
	n.name="DvereJednokridle"
	n.set_script(load("res://scripts/lobby/door_single.gd"))
	n.position=hinge
	n.rotation.y=yaw
	n.label=label
	n.state=state
	L.add_child(n)
	n.width=w
	n.height=h
	n.window=window
	n.open=open
	return n

# ------------------------------------------------------------------ drobný nábytek z kódu

func chair(pos: Vector3, yaw: float, tipped:=false) -> void:
	var n:=Node3D.new()
	L.add_child(n)
	var tube=L.flat(Color(0.45,0.47,0.45),0.35,0.85)
	var seat=L.mat("old_wood",0.6,Color(0.85,0.7,0.55))
	L.box(Vector3(0.42,0.035,0.4),Vector3(0,0.46,0),seat,false,n)
	L.box(Vector3(0.42,0.24,0.025),Vector3(0,0.74,-0.19),seat,false,n)
	for x in [-0.19,0.19]:
		for z in [-0.18,0.18]: L.cyl(0.012,0.46,Vector3(x,0.23,z),tube,Vector3.ZERO,n)
		L.cyl(0.012,0.42,Vector3(x,0.67,-0.2),tube,Vector3.ZERO,n)
	n.position=pos
	n.rotation=Vector3(0,yaw,0)
	if tipped:
		n.rotation=Vector3(-PI/2,yaw,0)
		n.position=pos+Vector3(0,0.2,0)

func bench(pos: Vector3, yaw: float, length:=1.4) -> void:
	var n:=Node3D.new()
	L.add_child(n)
	var wood=L.mat("old_wood",0.9,Color(0.95,0.8,0.62))
	var iron=L.flat(Color(0.18,0.19,0.18),0.5,0.6)
	for i in 3: L.box(Vector3(length,0.03,0.11),Vector3(0,0.45,-0.13+i*0.13),wood,i==1,n)
	for i in 2: L.box(Vector3(length,0.1,0.025),Vector3(0,0.62+i*0.14,-0.21),wood,false,n)
	for s in [-1,1]:
		L.box(Vector3(0.04,0.45,0.04),Vector3(s*(length*0.5-0.12),0.225,0.12),iron,false,n)
		L.box(Vector3(0.04,0.9,0.04),Vector3(s*(length*0.5-0.12),0.45,-0.2),iron,false,n)
		L.box(Vector3(0.04,0.04,0.4),Vector3(s*(length*0.5-0.12),0.42,-0.04),iron,false,n)
	n.position=pos
	n.rotation.y=yaw

func bookcase(pos: Vector3, yaw: float, w:=1.6, h:=2.0) -> void:
	var n:=Node3D.new()
	L.add_child(n)
	var wood=L.mat("old_wood",0.8,Color(0.75,0.55,0.4))
	var books:=StandardMaterial3D.new()
	books.albedo_texture=load(L.M+"gen/books.jpg")
	books.roughness=0.8
	L.box(Vector3(w,h,0.03),Vector3(0,h*0.5,-0.16),wood,true,n)
	for s in [-1,1]: L.box(Vector3(0.03,h,0.34),Vector3(s*w*0.5,h*0.5,0),wood,false,n)
	var shelves:=5
	for i in shelves+1:
		var y:=0.05+i*(h-0.08)/shelves
		L.box(Vector3(w,0.025,0.34),Vector3(0,y,0),wood,false,n)
		if i<shelves and randf()<0.85:
			var bw:=randf_range(0.5,0.95)*w
			var q:=MeshInstance3D.new()
			var qm:=QuadMesh.new()
			qm.size=Vector2(bw,(h-0.08)/shelves*0.82)
			q.mesh=qm
			q.material_override=books
			q.position=Vector3(randf_range(-w*0.5+bw*0.5,w*0.5-bw*0.5),y+qm.size.y*0.5+0.015,0.08)
			n.add_child(q)
			L.box(Vector3(bw,qm.size.y,0.22),Vector3(q.position.x,q.position.y,-0.035),L.flat(Color(0.25,0.2,0.17),0.8),false,n)
	n.position=pos
	n.rotation.y=yaw

func pingpong_table(pos: Vector3, yaw: float) -> void:
	var n:=Node3D.new()
	L.add_child(n)
	var top=L.flat(Color(0.08,0.24,0.16),0.55)
	var white=L.flat(Color(0.85,0.85,0.8),0.6)
	var iron=L.flat(Color(0.15,0.15,0.15),0.5,0.6)
	L.box(Vector3(2.74,0.03,1.525),Vector3(0,0.745,0),top,true,n)
	for s in [-1,1]: L.box(Vector3(2.74,0.032,0.02),Vector3(0,0.746,s*0.752),white,false,n)
	for s in [-1,1]: L.box(Vector3(0.02,0.032,1.525),Vector3(s*1.36,0.746,0),white,false,n)
	L.box(Vector3(0.006,0.032,1.525),Vector3(0,0.746,0),white,false,n)
	var net:=StandardMaterial3D.new()
	net.albedo_color=Color(0.9,0.9,0.88,0.55)
	net.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	L.box(Vector3(0.01,0.15,1.7),Vector3(0,0.84,0),net,false,n)
	for x in [-1.1,1.1]:
		for z in [-0.6,0.6]: L.box(Vector3(0.05,0.73,0.05),Vector3(x,0.365,z),iron,false,n)
	n.position=pos
	n.rotation.y=yaw
	# pálka a míček
	var bat=L.flat(Color(0.6,0.1,0.08),0.5)
	L.cyl(0.075,0.012,pos+Basis(Vector3.UP,yaw)*Vector3(0.7,0.77,0.3),bat,Vector3(0,0,0))
	var ball:=MeshInstance3D.new()
	var bs:=SphereMesh.new()
	bs.radius=0.02
	bs.height=0.04
	ball.mesh=bs
	ball.material_override=L.flat(Color(0.95,0.95,0.9),0.4)
	ball.position=pos+Basis(Vector3.UP,yaw)*Vector3(-0.5,0.78,-0.2)
	L.add_child(ball)

func cabinet_glass(pos: Vector3, yaw: float) -> void:
	# lékárnička / skříňka na léky: bílý plech, prosklená dvířka, lahvičky
	var n:=Node3D.new()
	L.add_child(n)
	var white=L.mat("painted_metal",0.5,Color(2.6,2.6,2.5),0.5)
	L.box(Vector3(0.8,1.8,0.4),Vector3(0,0.9,0),white,true,n)
	var gl:=StandardMaterial3D.new()
	gl.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	gl.albedo_color=Color(0.8,0.85,0.85,0.25)
	gl.roughness=0.1
	L.box(Vector3(0.72,1.0,0.01),Vector3(0,1.25,0.205),gl,false,n)
	var cols:=[Color(0.45,0.25,0.1),Color(0.85,0.85,0.8),Color(0.2,0.35,0.5)]
	for row in 3:
		for i in 7:
			if randf()<0.3: continue
			L.cyl(0.025,randf_range(0.08,0.16),Vector3(-0.3+i*0.1,0.85+row*0.33+0.06,0.05),L.flat(cols.pick_random(),0.2),Vector3.ZERO,n)
	n.position=pos
	n.rotation.y=yaw

# ------------------------------------------------------------------ chodba a schodiště

func _corridor() -> void:
	var lino=L.mat("linoleum",1.5)
	var x0:=CX0; var x1:=CX1
	L.slab(Vector3(x0,-0.2,CZ0),Vector3(x1,0.0,CZ1),lino)
	L.slab(Vector3(x0-2.65,H,CZ0),Vector3(x1,H+0.2,CZ1),L.mat("gen/plaster",1.9))
	# zdi chodby mezi pokoji jsou zdi pokojů; tady jen konec u schodiště (sever a jih)
	wall("x",CZ0,-1,-7.25,-2.75,[],H,T,_paint)
	wall("x",CZ1,1,-7.25,-2.75,[],H,T,_paint)
	# obklad na líci chodby (otvory dveří a okénka sesterny)
	var north_holes:=[[-2.2,-0.6,0,2.2],[3.3,4.9,0,2.2],[8.8,10.4,0,2.2]]
	var south_holes:=[[0.6,2.2,0,2.2],[3.3,4.3,0,2.1],[12.3,13.2,0,2.1],[9.9,11.7,1.0,2.0]]
	clad("x",CZ0,1,x0,x1,north_holes)
	clad("x",CZ1,-1,x0,x1,south_holes)
	# potrubí pod stropem a zářivky (jedna bliká, jedna nesvítí)
	var pipe=L.mat("painted_metal",0.6,Color(0.85,0.85,0.8))
	L.cyl(0.05,x1-x0+2.6,Vector3((x0+x1)*0.5-1.3,H-0.12,CZ0+0.15),pipe,Vector3(0,0,PI/2))
	L.cyl(0.03,x1-x0+2.6,Vector3((x0+x1)*0.5-1.3,H-0.12,CZ0+0.3),L.mat("rusty_metal",0.5,Color(0.8,0.8,0.8)),Vector3(0,0,PI/2))
	var cz:=(CZ0+CZ1)*0.5
	lamp(Vector3(-2.6,H,cz),1.0,true,"ok")
	lamp(Vector3(1.6,H,cz),1.0,false,"flicker")
	lamp(Vector3(5.7,H,cz),1.0,true,"ok")
	lamp(Vector3(9.6,H,cz),1.0,false,"dead")
	lamp(Vector3(12.8,H,cz),1.0,false,"ok")
	# dveře do pokojů a cedulky s čísly
	L._paper("plate_room_7.jpg",0.16,Vector3(-0.3,1.65,CZ0+0.006),Vector3(0,0,1))
	L._paper("plate_room_8.jpg",0.16,Vector3(5.2,1.65,CZ0+0.006),Vector3(0,0,1))
	L._paper("plate_room_9.jpg",0.16,Vector3(10.7,1.65,CZ0+0.006),Vector3(0,0,1))
	L._paper("plate_room_10.jpg",0.16,Vector3(0.3,1.65,CZ1-0.006),Vector3(0,0,-1))
	L._paper("sign_quarantine.jpg",0.42,Vector3(-1.78,1.55,CZ0+0.12),Vector3(0,0,1))
	L._paper("sign_wc.jpg",0.4,Vector3(3.8,2.4,CZ1-0.006),Vector3(0,0,-1))
	L._paper("sign_nurse.jpg",0.45,Vector3(12.75,2.35,CZ1-0.006),Vector3(0,0,-1))
	L._paper("sign_nosmoke.jpg",0.3,Vector3(6.6,1.75,CZ0+0.006),Vector3(0,0,1),0.03)
	# lavičky naproti sobě, hasicí přístroj, hydrant, nástěnka, hodiny, květina
	bench(Vector3(6.5,0,CZ0+0.24),PI,1.4)
	bench(Vector3(6.7,0,CZ1-0.24),0.0,1.4)
	var red=L.flat(Color(0.62,0.06,0.05),0.35,0.2)
	L.cyl(0.075,0.5,Vector3(-3.4,0.42,CZ0+0.1),red)
	L.cyl(0.03,0.08,Vector3(-3.4,0.71,CZ0+0.1),L.flat(Color(0.1,0.1,0.1),0.4,0.6))
	L.box(Vector3(0.6,0.75,0.2),Vector3(1.5,1.35,CZ0+0.1),red,true)
	L.box(Vector3(0.5,0.6,0.01),Vector3(1.5,1.35,CZ0+0.205),L.flat(Color(0.8,0.85,0.85),0.08,0.3),false)
	L.cyl(0.18,0.08,Vector3(1.5,1.35,CZ0+0.17),L.flat(Color(0.75,0.12,0.08),0.5),Vector3(PI/2,0,0))
	L.box(Vector3(1.2,0.8,0.025),Vector3(-1.4,1.7,CZ1-0.015),L.mat("cork",0.6),false)
	L._paper("paper_roster.jpg",0.32,Vector3(-1.7,1.7,CZ1-0.03),Vector3(0,0,-1),0.02)
	L._paper("paper_circular.jpg",0.3,Vector3(-1.15,1.72,CZ1-0.03),Vector3(0,0,-1),-0.04)
	L._paper("calendar_1993.jpg",0.2,Vector3(-0.85,1.75,CZ1-0.03),Vector3(0,0,-1),0.05)
	_clock(Vector3(6.6,2.55,CZ1-0.03),Vector3(0,0,-1))
	var plant:=Props.make("vase")
	L.add_child(plant)
	plant.position=Vector3(13.3,0,CZ0+0.35)
	# radiátor na chodbě
	window_radiator(Vector3(8.1,0,CZ1),PI,1.0)
	# špína
	for s in [[Vector3(4.0,2.2,CZ0),Vector3(0,0,1)],[Vector3(10.0,2.4,CZ0),Vector3(0,0,1)],[Vector3(2.0,2.3,CZ1),Vector3(0,0,-1)],[Vector3(8.5,2.2,CZ1),Vector3(0,0,-1)]]:
		L._decal_file("gen/grunge_wall.png",s[0],s[1],Vector2(3.4,2.0),randf()*6.0,0.8)
	L._decal_file("gen/dirt_floor_strip.png",Vector3(4.5,0.13,CZ0),Vector3(0,0,1),Vector2(18.0,0.3),0.0,0.9)
	L._decal_file("gen/dirt_floor_strip.png",Vector3(4.5,0.13,CZ1),Vector3(0,0,-1),Vector2(18.0,0.3),0.0,0.9)
	L._decal("decal_grime_3_dusty_abrasion",Vector3(5.0,0.002,3.25),Vector3(0,1,0),Vector2(6.0,1.6),0.0,0.6)
	L._decal("decal_water_2_damp_tide_mark",Vector3(9.4,H,3.2),Vector3(0,-1,0),Vector2(1.8,1.8),0.5,0.8)
	L._decal("decal_mold_4_mixed_mold_drips",Vector3(-4.0,2.7,CZ1),Vector3(0,0,-1),Vector2(1.2,1.0),0.0,0.8)
	# dveře pokojů a WC / sesterny
	double_door(5.5-1.4,CZ0-T*0.5,180.0,"open","pokoj 8")
	double_door(11.0-1.4,CZ0-T*0.5,180.0,"locked","pokoj 9")
	double_door(1.4,CZ1+T*0.5,0.0,"ajar","pokoj 10")
	var door_m=L.mat("painted_metal",0.6,Color(1.5,1.6,1.45),0.6)
	single_door(Vector3(3.3,0,CZ1+0.12),0.0,0.98,2.08,0.0,door_m,"WC a umývárna","closed",true)
	single_door(Vector3(12.3,0,CZ1+0.12),0.0,0.88,2.08,0.0,door_m,"sesterna","locked",true)
	for x in [3.3,4.28,12.3,13.18]:
		L.box(Vector3(0.06,2.16,0.3),Vector3(x+(0.03 if x in [3.3,12.3] else -0.03),1.08,CZ1+0.12),L.flat(Color(0.3,0.32,0.3),0.5,0.3),false)

func window_radiator(origin: Vector3, yaw: float, w: float) -> void:
	var f:=Node3D.new()
	L.add_child(f)
	f.global_transform=Transform3D(Basis(Vector3.UP,yaw),origin)
	var rad=L.mat("painted_metal",0.5,Color(2.0,2.05,1.95),0.8)
	var cnt:=int(w/0.065)
	for i in cnt: L.box(Vector3(0.045,0.58,0.16),Vector3(-cnt*0.026+i*0.052,0.47,0.12),rad,i==0,f)
	L.cyl(0.02,cnt*0.052+0.06,Vector3(0,0.2,0.12),rad,Vector3(0,0,PI/2),f)
	L.cyl(0.02,cnt*0.052+0.06,Vector3(0,0.74,0.12),rad,Vector3(0,0,PI/2),f)

func _clock(p: Vector3, n: Vector3) -> void:
	var face:MeshInstance3D=L._paper("clock_face.jpg",0.32,p,n)
	var hm=L.flat(Color(0.08,0.08,0.08),0.5)
	# zastavené hodiny: 4:17
	for h in [[0.09,deg_to_rad(4*30+8)],[0.13,deg_to_rad(17*6)]]:
		var hand:=MeshInstance3D.new()
		var bm:=BoxMesh.new()
		bm.size=Vector3(0.008,float(h[0]),0.004)
		hand.mesh=bm
		hand.material_override=hm
		face.add_child(hand)
		hand.rotation.z=-float(h[1])
		hand.position=hand.transform.basis*Vector3(0,float(h[0])*0.5,0)+Vector3(0,0,0.004)
	L.cyl(0.165,0.04,p-n*0.02,L.flat(Color(0.12,0.12,0.12),0.4,0.6),Vector3(PI/2,0,0) if absf(n.z)>0.5 else Vector3(0,0,PI/2))

func _stairwell() -> void:
	# schodiště dolů za zamčenou mříží; dole tma a slabé světlo
	var conc=L.mat("terrazzo",1.0,Color(0.8,0.8,0.78))
	var paint:=_paint
	var xw:=-7.0
	wall("z",xw,-1,CZ0-T,CZ1+T,[],H,T,paint,true,-3.2)
	wall("x",CZ0,-1,xw,CX0,[],0.0,T,paint,true,-3.2)
	wall("x",CZ1,1,xw,CX0,[],0.0,T,paint,true,-3.2)
	var steps:=9
	for k in steps:
		var top:=-0.17*(k+1)
		var xa:=CX0-0.28*k; var xb:=CX0-0.28*(k+1)
		L.slab(Vector3(xb,-3.0,CZ0),Vector3(xa,top,CZ0+1.1),conc)
		L.box(Vector3(0.28,0.02,1.1),Vector3((xa+xb)*0.5,top+0.01,CZ0+0.55),L.flat(Color(0.15,0.15,0.14),0.6,0.4),false)
	L.slab(Vector3(xw,-3.0,CZ0+1.1),Vector3(CX0,-1.53,CZ1),conc)       # podesta dole
	L.slab(Vector3(xw,-3.0,CZ0),Vector3(CX0-0.28*steps,-1.53,CZ0+1.1),conc)
	# zábradlí
	var rail=L.flat(Color(0.15,0.25,0.2),0.4,0.5)
	L.cyl(0.02,2.7,Vector3(CX0-1.26,0.0,CZ0+1.12),rail,Vector3(0,0,PI/2-atan2(1.53,2.52)))
	for i in 5: L.cyl(0.012,0.95,Vector3(CX0-0.25-i*0.5,0.47-0.17*(i*1.8)-0.4,CZ0+1.12),rail)
	# mříž přes chodbu s vrátky, řetěz a zámek
	var bars=L.mat("rusty_metal",0.4,Color(0.7,0.68,0.66))
	var n:=int((CZ1-CZ0)/0.12)
	for i in n+1:
		L.cyl(0.012,H,Vector3(CX0,H*0.5,CZ0+i*(CZ1-CZ0)/n),bars)
	for y in [0.1,1.05,2.1,3.1]:
		L.cyl(0.018,CZ1-CZ0,Vector3(CX0,y,(CZ0+CZ1)*0.5),bars,Vector3(PI/2,0,0))
	var gate:=StaticBody3D.new()
	var cs:=CollisionShape3D.new()
	var sh:=BoxShape3D.new()
	sh.size=Vector3(0.1,H,CZ1-CZ0)
	cs.shape=sh
	gate.add_child(cs)
	gate.position=Vector3(CX0,H*0.5,(CZ0+CZ1)*0.5)
	L.add_child(gate)
	L.interact(gate,"[E] Mříž","","Mříž je zamčená na řetěz. Schodiště dolů je uzavřené.")
	var chain=L.flat(Color(0.5,0.48,0.44),0.35,0.9)
	for i in 8: L.box(Vector3(0.03,0.05,0.015),Vector3(CX0+0.03,1.1+sin(i)*0.02,3.0+i*0.04),chain,false)
	L.box(Vector3(0.05,0.08,0.06),Vector3(CX0+0.05,1.02,3.32),L.flat(Color(0.6,0.5,0.25),0.3,0.9),false)
	L._paper("sign_stairs.jpg",0.5,Vector3(CX0+0.03,1.5,3.6),Vector3(1,0,0),0.02)
	# zelená cedule únikového východu (svítí)
	var ex:MeshInstance3D=L._paper("sign_exit.jpg",0.5,Vector3(CX0+0.15,2.75,(CZ0+CZ1)*0.5),Vector3(1,0,0))
	var em:=ex.material_override as StandardMaterial3D
	em.emission_enabled=true
	em.emission_texture=em.albedo_texture
	em.emission_energy_multiplier=1.4
	var gl:=OmniLight3D.new()
	gl.position=Vector3(CX0+0.4,2.6,(CZ0+CZ1)*0.5)
	gl.light_color=Color(0.3,1.0,0.5)
	gl.light_energy=0.25
	gl.omni_range=2.5
	L.add_child(gl)
	var low:=OmniLight3D.new()
	low.position=Vector3(xw+0.5,-0.6,(CZ0+CZ1)*0.5+0.4)
	low.light_color=Color(1.0,0.7,0.45)
	low.light_energy=0.35
	low.omni_range=3.0
	L.add_child(low)
	L._decal("decal_mold_1_black_mildew",Vector3(xw,1.0,3.2),Vector3(1,0,0),Vector2(1.6,1.6),0.0,0.9)

# ------------------------------------------------------------------ pokoje

func _room_north(cx: float, num: String, state: String) -> void:
	var r:=Rect2(cx-2.5,-1.9,5.0,3.8)
	var win:=[cx-1.2,cx+0.1,1.5,2.8]
	var dr:=[cx-2.2,cx-0.6,0.0,2.2]
	room(r,{"n":[win],"s":[dr]},L.mat("terrazzo",1.3),{"skip":["s"] if false else []})
	window(Vector3(cx-0.55,0,-1.9),0.0,1.3,1.5,2.8)
	if num=="8":
		# opuštěný ve spěchu: postel bez deky, převržená židle, rozházené papíry, otevřená komoda
		L._place("bed",0.0095,-90.0,Vector3(cx,0,-0.8),{"x_min":cx-2.46})
		L._place("table",0.01,8.0,Vector3(cx+1.3,0,0),{"z_min":-1.85})
		chair(Vector3(cx+0.6,0,-0.6),2.4,true)
		L._place("drawers",0.21,180.0,Vector3(cx,0,0.2),{"x_max":cx+2.47})
		for i in 6:
			L._paper(["note_1.jpg","note_2.jpg","note_3.jpg","paper_circular.jpg","paper_roster.jpg","map_site.jpg"][i],0.22,Vector3(cx+randf_range(-0.8,1.2),0.004+i*0.001,randf_range(-0.6,1.2)),Vector3(0,1,0),randf()*6.0)
		L._decal("decal_mold_2_olive_green_colony",Vector3(cx+2.5,2.6,-1.2),Vector3(-1,0,0),Vector2(1.2,1.2),0.0,0.9)
	else:
		# zamčený pokoj 9: přes okénka ve dveřích je vidět ustlaná postel a stůl
		L._place("bed",0.0095,-90.0,Vector3(cx,0,-0.8),{"x_min":cx-2.46})
		L._place("table",0.01,0.0,Vector3(cx+1.3,0,0),{"z_min":-1.85})
		chair(Vector3(cx+1.2,0,-0.9),PI)
		L._place("drawers",0.21,180.0,Vector3(cx,0,-0.2),{"x_max":cx+2.47})
		L._decal("decal_water_1_runoff_streaks",Vector3(cx-0.55,0.9,-1.9),Vector3(0,0,1),Vector2(1.2,1.0),0.0,0.8)
	for g in [[Vector3(cx,2.3,-1.9),Vector3(0,0,1)],[Vector3(cx+2.5,2.2,0.0),Vector3(-1,0,0)],[Vector3(cx,H,0.0),Vector3(0,-1,0)]]:
		L._decal_file("gen/grunge_wall.png",g[0],g[1],Vector2(3.2,2.4),randf()*6.0,0.8)

func _room_south(cx: float, num: String, state: String) -> void:
	var r:=Rect2(cx-2.5,SZ0,5.0,SZ1-SZ0)
	var win:=[cx-0.1,cx+1.2,1.5,2.8]
	var dr:=[cx+0.6,cx+2.2,0.0,2.2]
	room(r,{"s":[win],"n":[dr]},L.mat("terrazzo",1.3))
	window(Vector3(cx+0.55,0,SZ1),PI,1.3,1.5,2.8)
	# vyrabovaný: postel převržená na bok, matrace na zemi, rozkopané papíry, hodně plísně
	var bed:Node3D=L._place("bed",0.0095,0.0,Vector3(cx-1.2,0,6.6),{},false)
	bed.rotation=Vector3(0,0.1,PI/2)
	var ba:AABB=L._aabb(bed)
	bed.position+=Vector3(cx-2.42-ba.position.x,-ba.position.y,0)
	L._body_for(bed)
	var mattress=L.mat("gen/mattress",0.9)
	var mt=L.box(Vector3(0.85,0.12,1.85),Vector3(cx-0.4,0.06,6.4),mattress,true)
	mt.rotation.y=0.35
	L._place("table",0.01,-20.0,Vector3(cx+1.4,0,5.3))
	chair(Vector3(cx+0.4,0,5.4),0.6,true)
	L._place("multimeter",1.0,40.0,Vector3(cx+0.6,0,7.2),{},false)
	for i in 7:
		L._paper(["note_1.jpg","note_2.jpg","note_3.jpg","paper_circular.jpg","paper_roster.jpg","map_site.jpg","calendar_1993.jpg"][i],0.24,Vector3(cx+randf_range(-1.2,1.8),0.004+i*0.001,randf_range(5.0,8.0)),Vector3(0,1,0),randf()*6.0)
	L._decal("decal_mold_4_mixed_mold_drips",Vector3(cx-2.5,2.6,7.4),Vector3(1,0,0),Vector2(1.6,1.4),0.0,1.0)
	L._decal("decal_mold_1_black_mildew",Vector3(cx-1.5,H,7.8),Vector3(0,-1,0),Vector2(1.8,1.8),0.0,1.0)
	L._decal("decal_cracks_4_impact_cracks",Vector3(cx+2.5,1.6,6.5),Vector3(-1,0,0),Vector2(0.8,0.8),0.0,0.9)
	for g in [[Vector3(cx,2.3,SZ1),Vector3(0,0,-1)],[Vector3(cx-2.5,2.0,6.5),Vector3(1,0,0)]]:
		L._decal_file("gen/grunge_wall.png",g[0],g[1],Vector2(3.2,2.4),randf()*6.0,0.9)

# ------------------------------------------------------------------ WC a umývárna

func _washroom() -> void:
	var r:=Rect2(3.0,SZ0,6.0,SZ1-SZ0)
	var dr:=[3.3,4.3,0.0,2.1]
	var win:=[4.0,5.5,1.9,2.6]
	var tiles_full=L.mat("ceramic_tiles",0.6,Color(0.92,0.95,0.94))
	var floor_t=L.mat("ceramic_tiles",0.45,Color(0.62,0.64,0.62))
	room(r,{"n":[dr],"s":[win]},floor_t,{"tile_mat":tiles_full})
	# obklad až do 2,1 m (umývárna)
	var hi=L.mat("ceramic_tiles",0.6,Color(0.92,0.95,0.94))
	for w in [["x",SZ0,1,3.0,9.0],["x",SZ1,-1,3.0,9.0],["z",3.0,1,SZ0,SZ1],["z",9.0,-1,SZ0,SZ1]]:
		var holes:=[]
		if w[1]==SZ0 and w[0]=="x": holes=[[3.3,4.3,0,2.1]]
		if w[1]==SZ1 and w[0]=="x": holes=[[4.0,5.5,1.9,2.6]]
		wall(w[0],w[1],w[2],w[3],w[4],holes,2.1,0.017,hi,false,TILE_H+0.035)
	window(Vector3(4.75,0,SZ1),PI,1.5,1.9,2.6,true,false,false)
	# tři kabinky u jižní zdi
	var panel=L.mat("painted_metal",0.6,Color(1.3,1.45,1.3),0.6)
	var zf:=SZ1-1.45
	for i in 4:
		var x:=6.0+i*1.0
		if i<3 or true:
			L.box(Vector3(0.03,1.9,1.45),Vector3(minf(x,8.985),1.05,SZ1-0.725),panel,true)
	L.box(Vector3(3.0,0.06,0.04),Vector3(7.5,2.0,zf),panel,false)
	var states:=[0.85,0.0,0.3]
	for i in 3:
		var x:=6.0+i*1.0
		single_door(Vector3(x+0.04,0.15,zf),0.0,0.9,1.75,states[i],panel,"kabinka")
		var t:Node3D=L._place("res://assets/toilets/toilet.glb",1.0,90.0,Vector3(x+0.5,0,0),{"z_max":SZ1-0.05})
		L.cyl(0.02,0.45,Vector3(x+0.5,1.8,SZ1-0.12),L.flat(Color(0.85,0.85,0.82),0.3,0.2))
		L.box(Vector3(0.38,0.2,0.16),Vector3(x+0.5,1.95,SZ1-0.1),L.flat(Color(0.85,0.85,0.82),0.4),false)
	# pisoáry na východní zdi
	for z in [4.95,5.65]:
		L._place("res://assets/toilets/urinal.glb",1.0,180.0,Vector3(0,0.3,z),{"x_max":8.98,"y":0.35})
	# umyvadla se zrcadly na západní zdi (jedno zrcadlo prasklé)
	for i in 3:
		var z:float=[5.15,6.0,6.85][i]
		var s:Node3D=L._place("res://assets/lobby/models/sink.glb",0.0085,0.0,Vector3(0,0,z),{"x_min":3.02})
		var sa:AABB=L._aabb(s)
		var mm=L.flat(Color(0.75,0.78,0.78),0.05 if i!=1 else 0.35,1.0)
		L.box(Vector3(0.02,0.55,0.45),Vector3(3.02,sa.end.y+0.45,z),mm,false)
		if i==1: L._decal("decal_cracks_4_impact_cracks",Vector3(3.03,sa.end.y+0.45,z),Vector3(1,0,0),Vector2(0.4,0.4),0.0,1.0)
	# odpad v podlaze, plíseň, zatečení
	L.cyl(0.07,0.01,Vector3(5.0,0.004,6.6),L.flat(Color(0.12,0.12,0.12),0.4,0.8))
	L._decal("decal_mold_3_gray_fungal_threads",Vector3(9.0,1.8,7.6),Vector3(-1,0,0),Vector2(1.2,1.2),0.0,0.9)
	L._decal("decal_water_4_dirty_water_splash",Vector3(5.2,0.003,6.4),Vector3(0,1,0),Vector2(1.4,1.4),0.0,0.8)
	L._decal("decal_water_3_narrow_leaks",Vector3(4.75,1.7,SZ1),Vector3(0,0,-1),Vector2(1.4,1.2),0.0,0.8)
	lamp(Vector3(5.2,H,6.0),0.9,true,"ok",true)
	lamp(Vector3(7.6,H,6.0),0.8,false,"flicker",true)
	L._snd("res://audio/amb_water.wav",Vector3(4.0,1.0,6.0),-26.0,true,2.0)

# ------------------------------------------------------------------ sesterna

func _nurse() -> void:
	var r:=Rect2(9.5,SZ0,4.0,SZ1-SZ0)
	var dr:=[12.3,13.2,0.0,2.1]
	var inner_win:=[9.9,11.7,1.0,2.0]
	room(r,{"n":[dr,inner_win]},L.mat("linoleum",1.5))
	# okénko do chodby se žaluzií
	var glass:=StandardMaterial3D.new()
	glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_texture=load(L.M+"gen/glass_dirty.png")
	glass.cull_mode=BaseMaterial3D.CULL_DISABLED
	L._quad(Vector2(1.8,1.0),Vector3(10.8,1.5,SZ0-0.12),Vector3(0,0,1),glass)
	var fr=L.mat("painted_metal",0.5,Color(2.2,2.3,2.2),0.6)
	L.box(Vector3(1.9,0.05,0.3),Vector3(10.8,1.0,SZ0-0.12),fr,true)
	L.box(Vector3(1.9,0.05,0.3),Vector3(10.8,2.0,SZ0-0.12),fr,false)
	var slat=L.flat(Color(0.82,0.8,0.72),0.5,0.2)
	for i in 12:
		var s=L.box(Vector3(1.76,0.004,0.05),Vector3(10.8,1.95-i*0.05,SZ0+0.03),slat,false)
		s.rotation.x=0.9 if i>5 else 0.25
	# vnitřek: stůl, rádio, lékárna, regály, skříňka
	L._place("table",0.01,0.0,Vector3(10.8,0,0),{"z_min":SZ0+0.05})
	L._place("radio",0.0021,170.0,Vector3(10.4,0,SZ0+0.35),{"y":0.75},false)
	chair(Vector3(10.9,0,5.6),PI)
	cabinet_glass(Vector3(13.0,0,SZ1-0.25),PI)
	var sh:=Props.make("shelves")
	L.add_child(sh)
	sh.rotation.y=PI/2
	sh.position=Vector3(9.8,0,7.2)
	var desk:=OmniLight3D.new()
	desk.position=Vector3(10.4,1.2,SZ0+0.4)
	desk.light_color=Color(1.0,0.72,0.42)
	desk.light_energy=0.6
	desk.omni_range=2.6
	desk.shadow_enabled=true
	L.add_child(desk)
	var shade=L.flat(Color(0.15,0.3,0.2),0.4,0.3)
	L.cyl(0.09,0.12,Vector3(10.4,1.05,SZ0+0.4),shade)
	L.cyl(0.01,0.3,Vector3(10.4,0.9,SZ0+0.4),shade)

# ------------------------------------------------------------------ společenská místnost

func _hall() -> void:
	var r:=HALL
	var x0:=r.position.x; var x1:=r.end.x; var z0:=r.position.y; var z1:=r.end.y
	var doorway:=[CZ0,CZ1,0.0,2.6]
	var wins_n:=[[15.4,16.9,1.1,2.8],[18.4,19.9,1.1,2.8],[21.4,22.9,1.1,2.8]]
	var wins_e:=[[0.4,1.9,1.1,2.8],[4.6,6.1,1.1,2.8]]
	var cream=L.mat("gen/paint_cream",1.7)
	var parquet=L.mat("old_wood",1.0,Color(1.0,0.85,0.7))
	room(r,{"w":[doorway],"n":wins_n,"e":wins_e},parquet,{"paint":cream,"tile_mat":_paint,"skip":["w"]})
	# západní zeď (tlustší, vyplní mezeru k pokoji 9 a sesterně) s průchodem z chodby
	wall("z",x0,-1,z0-T,z1+T,[doorway],H,0.5,cream)
	clad("z",x0,1,z0,z1,[doorway],_paint)
	for w in wins_n: window(Vector3((w[0]+w[1])*0.5,0,z0),0.0,1.5,1.1,2.8,false,false)
	for w in wins_e: window(Vector3(x1,0,(w[0]+w[1])*0.5),-PI/2,1.5,1.1,2.8,false,false)
	# zárubeň průchodu a cedule nad ním (z chodby)
	var frame=L.mat("old_wood",0.8,Color(0.6,0.45,0.32))
	for z in [CZ0,CZ1]: L.box(Vector3(0.56,2.6,0.08),Vector3(x0-0.25,1.3,z+(0.04 if z==CZ0 else -0.04)),frame,false)
	L.box(Vector3(0.56,0.08,CZ1-CZ0+0.16),Vector3(x0-0.25,2.64,(CZ0+CZ1)*0.5),frame,false)
	L._paper("sign_hall.jpg",0.95,Vector3(x0-0.51,2.88,(CZ0+CZ1)*0.5),Vector3(-1,0,0))
	# vybavení: pingpong, televizní kout, stoly se židlemi, knihovna, automat, květiny
	pingpong_table(Vector3(18.6,0,1.6),0.0)
	var dr:Node3D=L._place("drawers",0.21,90.0,Vector3(20.8,0,0),{"z_max":z1-0.03})
	var da:AABB=L._aabb(dr)
	L._place("crt_tv",0.05,180.0,Vector3(da.get_center().x,0,da.get_center().z+0.03),{"y":da.end.y},false)
	L._place("sofa",0.72,180.0,Vector3(20.8,0,5.7))
	chair(Vector3(22.7,0,6.6),-2.3)
	chair(Vector3(19.0,0,6.8),2.2)
	for t in [Vector2(15.6,5.9),Vector2(15.6,3.9)]:
		L._place("table",0.01,90.0,Vector3(t.x,0,t.y))
		chair(Vector3(t.x-0.55,0,t.y),PI/2)
		chair(Vector3(t.x+0.55,0,t.y+0.1),-PI/2)
	bookcase(Vector3(x0+0.2,0,0.4),PI/2,1.6,2.0)
	bookcase(Vector3(x0+0.2,0,-1.2),PI/2,1.2,1.7)
	var vend:=Props.make("vending")
	L.add_child(vend)
	vend.rotation.y=-PI/2
	var va:AABB=L._aabb(vend)
	vend.position+=Vector3(x1-0.05-va.end.x,0,7.6-va.get_center().z)
	L._body_for(vend)
	for p in [Vector3(23.5,0,-1.4),Vector3(14.8,0,7.9)]:
		var pl:=Props.make("vase")
		L.add_child(pl)
		pl.position=p
	# nástěnka, plakát, hodiny
	L.box(Vector3(1.4,0.9,0.025),Vector3(17.2,1.75,z1-0.015),L.mat("cork",0.6),false)
	L._paper("paper_circular.jpg",0.32,Vector3(16.8,1.75,z1-0.03),Vector3(0,0,-1),0.03)
	L._paper("paper_roster.jpg",0.3,Vector3(17.5,1.72,z1-0.03),Vector3(0,0,-1),-0.02)
	L._paper("poster_civil_defense.jpg",0.55,Vector3(x0+0.006,1.95,6.9),Vector3(1,0,0))
	_clock(Vector3(x1-0.03,2.4,3.25),Vector3(-1,0,0))
	for l in [Vector3(16.5,H,1.5),Vector3(20.5,H,1.5),Vector3(16.5,H,5.8),Vector3(20.5,H,5.8)]:
		lamp(l,0.9,l.x>20.0 and l.z>5.0,"ok")
	for g in [[Vector3(18.0,2.4,z0),Vector3(0,0,1)],[Vector3(20.0,2.3,z1),Vector3(0,0,-1)],[Vector3(x1,2.5,3.2),Vector3(-1,0,0)],[Vector3(19.0,H,3.0),Vector3(0,-1,0)]]:
		L._decal_file("gen/grunge_wall.png",g[0],g[1],Vector2(4.0,2.6),randf()*6.0,0.7)
	L._decal("decal_water_2_damp_tide_mark",Vector3(22.5,H,-0.8),Vector3(0,-1,0),Vector2(2.0,2.0),0.3,0.8)
	L._decal("decal_grime_3_dusty_abrasion",Vector3(18.6,0.002,4.0),Vector3(0,1,0),Vector2(5.0,3.0),0.4,0.5)
	L._snd("res://audio/fridge_hum.wav",Vector3(x1-0.5,1.0,7.6),-22.0,true,2.0)

# ------------------------------------------------------------------ výhled ven ze všech oken

func _backdrops() -> void:
	var vm:=StandardMaterial3D.new()
	vm.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	vm.albedo_texture=load(L.M+"gen/window_view.jpg")
	vm.albedo_color=Color(1.15,1.1,1.05)
	vm.texture_repeat=true
	for b in [[Vector3(10.0,3.9,-18.0),Vector3(0,0,1),Vector2(60.0,12.0),2.5],[Vector3(10.0,3.9,26.0),Vector3(0,0,-1),Vector2(60.0,12.0),2.5],[Vector3(42.0,3.9,3.0),Vector3(-1,0,0),Vector2(40.0,12.0),1.7]]:
		var m:=vm.duplicate() as StandardMaterial3D
		m.uv1_scale=Vector3(float(b[3]),1,1)
		var q:MeshInstance3D=L._quad(b[2],b[0],b[1],m)
		q.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
