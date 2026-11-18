extends RefCounted
## Úchop zbraně jako v AAA hrách:
##  - ruce na úchopových bodech zbraně (osa rukojeti, spoušť, předpažbí), poloha i natočení dlaně
##    spočítané z rozměrů ruky postavy (klouby prstů, střed dlaně),
##  - prsty se ovinou až na povrch zbraně (distanční pole, žádné procházení),
##  - ukazovák bříškem na spoušti; při přebíjení / sprintu natažený podél pouzdra,
##  - levá ruka se při animacích vytlačí ze zbraně.
## Souřadnice zbraně jsou v metrech (holder zbraně), kostra v jednotkách postavy (× 0.86 = metry).
const SdfLib:=preload("res://scripts/gun_sdf.gd")
const S:=0.86

# Úchopové body (souřadnice zbraně, metry). Každý úchop: osa (a0 → a1), kořen ukazováku míří
# k a0 (prsty seřazené podél osy), základní směr normály dlaně a cíl kořene ukazováku:
#  - knuckle: pevný bod, nebo
#  - knuckle_dir + at: bod na povrchu ve vzdálenosti `at` od a0 podél osy, ve směru knuckle_dir od osy.
# trigger = přední plocha jazýčku spouště (bříško ukazováku).
const SOCKETS:={
	"ak":{"trigger":Vector3(0,0.045,-0.041),
		"right":{"a0":Vector3(0,0.05,0.005),"a1":Vector3(0,-0.025,0.035),"n":Vector3.LEFT,"knuckle":Vector3(0.026,0.053,-0.006)},
		"left":{"a0":Vector3(0,0.09,-0.39),"a1":Vector3(0,0.09,-0.23),"n":Vector3.UP,"knuckle_dir":Vector3(0.55,-0.83,0),"at":0.075},
		# kontrola nábojů: levá ruka obejme vysunutý zásobník zleva, prsty kolem jeho přední hrany
		"mag":{"a0":Vector3(0,-0.02,-0.15),"a1":Vector3(0,-0.12,-0.2),"n":Vector3.RIGHT,"knuckle_dir":Vector3(-0.6,0,-0.8),"at":0.035,"part":"magazine"}},
	"mp40":{"trigger":Vector3(0,0.009,-0.06),
		"right":{"a0":Vector3(0,0.01,-0.008),"a1":Vector3(0,-0.06,0.03),"n":Vector3.LEFT,"knuckle":Vector3(0.025,0.019,-0.02)},
		"left":{"a0":Vector3(0,0.03,-0.317),"a1":Vector3(0,-0.13,-0.317),"n":Vector3.RIGHT,"knuckle_dir":Vector3(-0.6,0,-0.8),"at":0.04},
		"mag":{"a0":Vector3(0,-0.02,-0.317),"a1":Vector3(0,-0.17,-0.317),"n":Vector3.RIGHT,"knuckle_dir":Vector3(-0.6,0,-0.8),"at":0.05,"part":"magazine"}},
	"deagle":{"trigger":Vector3(0,0.036,-0.094),
		"right":{"a0":Vector3(0,0.04,-0.04),"a1":Vector3(0,-0.035,-0.031),"n":Vector3.LEFT,"knuckle":Vector3(0.026,0.042,-0.06)},
		"left":{"a0":Vector3(0,0.04,-0.04),"a1":Vector3(0,-0.035,-0.031),"n":Vector3.RIGHT,"knuckle":Vector3(-0.032,0.006,-0.09),"free":0.015}},
	"izh54":{"trigger":Vector3(0,0.024,-0.09),
		"right":{"a0":Vector3(0,0.035,0.01),"a1":Vector3(0,-0.03,0.065),"n":Vector3.LEFT,"knuckle":Vector3(0.026,0.036,-0.045)},
		"left":{"a0":Vector3(0,0.062,-0.43),"a1":Vector3(0,0.062,-0.24),"n":Vector3.UP,"knuckle_dir":Vector3(0.55,-0.83,0),"at":0.1,"part":"barrel"}},
}
const FINGERS:=["Thumb","Index","Middle","Ring","Pinky"]
# rozsah ohybu článků [min, max] (rad)
const CURL:={"Thumb":[[-0.3,0.9],[-0.2,0.9],[-0.2,0.9]],"Index":[[-0.25,1.45],[0.0,1.6],[0.0,1.25]],
	"Middle":[[-0.25,1.5],[0.0,1.65],[0.0,1.3]],"Ring":[[-0.25,1.5],[0.0,1.65],[0.0,1.3]],"Pinky":[[-0.25,1.55],[0.0,1.7],[0.0,1.35]]}

var sk: Skeleton3D
var _hand:={}
var _chains:={}
var _wrist_cache:={}        # zbraň:strana → Transform3D (souřadnice zbraně)
var finger_r:=0.0095        # poloměr prstu (m)
var part_rest:={}           # zbraň → {díl: Transform3D} klidové polohy zásobníku / hlavní

func setup(skeleton: Skeleton3D) -> void:
	sk=skeleton
	finger_r=float(sk.get_meta("finger_radius",0.0095))
	_hand.clear()
	_chains.clear()
	_wrist_cache.clear()

## Podpis postavy: upečené úchopy platí jen pro stejnou kostru a rozměry ruky.
func signature() -> String:
	var h:=hand("Right")
	var l:=hand("Left")
	return "%d|%.4f|%s|%s|%s|%s" % [sk.get_bone_count(),finger_r,str(h.i1),str(h.palm),str(l.i1),str(l.palm)]

func has(gun: String) -> bool:
	return SOCKETS.has(gun) and SdfLib.of(gun).has_data()

func sdf(gun: String) -> RefCounted:
	return SdfLib.of(gun)

# --- rozměry ruky (souřadnice kosti ruky, jednotky kostry)
func hand(side: String) -> Dictionary:
	if _hand.has(side): return _hand[side]
	var h:=sk.find_bone("mixamorig_%sHand"%side)
	var bh:=sk.get_bone_global_rest(h)
	var inv:=bh.affine_inverse()
	var i1:=sk.find_bone("mixamorig_%sHandIndex1"%side)
	var p1:=sk.find_bone("mixamorig_%sHandPinky1"%side)
	var ip:=inv*sk.get_bone_global_rest(i1).origin
	var pp:=(inv*sk.get_bone_global_rest(p1).origin) if p1>=0 else ip+Vector3(0,0,0.05)
	var ib:=sk.get_bone_global_rest(i1).basis.orthonormalized()
	var n:=(bh.basis.orthonormalized().inverse()*ib.x.cross(ib.y)).normalized()
	var palm: Vector3=sk.get_meta("palm_point_"+side,ip*0.55+n*0.02)
	var kn:=[ip]
	for f in ["Middle","Ring","Pinky"]:
		var b:=sk.find_bone("mixamorig_%sHand%s1"%[side,f])
		if b>=0: kn.append(inv*sk.get_bone_global_rest(b).origin)
	var d:={"bone":h,"k":(pp-ip).normalized(),"n":n,"palm":palm,"i1":ip,"kn":kn}
	_hand[side]=d
	return d

static func frame(a: Vector3, b: Vector3) -> Basis:
	var x:=a.normalized()
	var y:=(b-x*b.dot(x)).normalized()
	return Basis(x,y,x.cross(y))

## Bod na povrchu: z bodu uvnitř jít směrem dir, dokud není venku (a opačně, když začne venku).
func surface(gun: String, from: Vector3, dir: Vector3, xf: Dictionary, extra: Array=[]) -> Vector3:
	var s=sdf(gun)
	var step:=0.003
	var inside:=dist(s,from,xf,extra)<0.0
	var sgn:=1.0 if inside else -1.0
	var prev:=0.0
	for i in range(1,45):
		var t:=step*i
		var now_in:=dist(s,from+dir*t*sgn,xf,extra)<0.0
		if now_in!=inside:
			var lo:=prev
			var hi:=t
			for it in 4:
				var m:=(lo+hi)*0.5
				if (dist(s,from+dir*m*sgn,xf,extra)<0.0)==inside: lo=m
				else: hi=m
			return from+dir*(hi*sgn if inside else lo*sgn)
		prev=t
	return from+dir*0.13 if inside else from

## Vzdálenost k zbrani (metry) včetně případných kapslí (prsty druhé ruky): [a, b, poloměr].
static func dist(s, p: Vector3, xf: Dictionary, extra: Array=[]) -> float:
	var d: float=s.distance(p,xf)
	for c in extra:
		var a: Vector3=c[0]
		var b: Vector3=c[1]
		var ab:=b-a
		var t:=clampf((p-a).dot(ab)/maxf(ab.length_squared(),1e-9),0.0,1.0)
		d=minf(d,p.distance_to(a+ab*t)-float(c[2]))
	return d

# --- umístění zápěstí (souřadnice zbraně, metry)
## Dlaň leží na povrchu zbraně, kořen ukazováku co nejblíž cíli (u pravé ruky za spouští, u levé
## na hraně předpažbí / přes prsty pravé ruky), zápěstí ani klouby nesmí do zbraně. Hledá se natočení
## ruky kolem osy úchopu a malé posunutí cíle kořene (socket "free", metry).
func wrist(gun: String, side: String, extra: Array=[], sock_name:="") -> Transform3D:
	var key:=gun+":"+side+sock_name
	if _wrist_cache.has(key) and extra.is_empty(): return _wrist_cache[key]
	var sock: Dictionary=SOCKETS[gun][sock_name if sock_name!="" else ("right" if side=="Right" else "left")]
	var h:=hand(side)
	var rest: Dictionary=part_rest.get(gun,{})
	var a0: Vector3=sock.a0
	var a: Vector3=(sock.a1-a0).normalized()
	var length: float=(sock.a1-a0).length()
	var K0: Vector3
	if sock.has("knuckle"): K0=sock.knuckle
	else:
		var kd: Vector3=sock.knuckle_dir
		K0=surface(gun,a0+a*float(sock.at),kd.normalized(),rest,extra)+kd.normalized()*0.012
	var free: float=sock.get("free",0.004 if side=="Right" else 0.02)
	var base_n: Vector3=sock.n
	base_n=(base_n-a*base_n.dot(a)).normalized()
	var sdf_s=sdf(gun)
	var hk: Vector3=h.k
	var hn: Vector3=h.n
	var i1: Vector3=(h.i1 as Vector3)*S
	var palm_l: Vector3=(h.palm as Vector3)*S
	var kn_l:=(h.kn as Array).map(func(v): return (v as Vector3)*S)
	var hand_frame:=frame(hk,hn).transposed()
	# pravá ruka: ukazovák musí dosáhnout na spoušť (odhad přes několik ohybů, bez kolizí)
	var ich:={}
	var trig: Vector3=SOCKETS[gun].trigger
	if side=="Right":
		for c in chains("Right"):
			if c.name=="Index": ich=c
	var reach_est:=func(R: Basis, w: Vector3) -> float:
		if ich.is_empty(): return 0.0
		var hx:=Transform3D(R*S,w)
		var bestd:=INF
		for sa in [-0.6,-0.3,0.0,0.3]:
			for c2 in [0.5,0.8,1.1,1.4]:
				for c1 in [-0.2,0.15,0.5]:
					var pts:=fk(hx,ich,[c1,c2,c2*0.7],sa)
					var g3: Transform3D=pts[2]
					var pad: Vector3=g3*((ich.tip as Vector3)*0.6+Vector3(0,0,finger_r/S))
					bestd=minf(bestd,pad.distance_to(trig))
		return bestd
	# cena polohy: [cena, Transform3D, složky]
	var place:=func(th: float, d: Vector3) -> Array:
		var nt:=Basis(a,th)*base_n
		var R:=frame(a,nt)*hand_frame
		var K:=K0+d
		var w: Vector3=K-R*i1
		var palm: Vector3=w+R*palm_l
		var pd:=dist(sdf_s,palm,rest,extra)
		var e:=absf(pd-0.002)
		var pen:=0.0
		var dw:=dist(sdf_s,w,rest,extra)
		if dw<0.022: pen+=0.022-dw
		for v in kn_l:
			var dk:=dist(sdf_s,w+R*(v as Vector3),rest,extra)
			if dk<0.011: pen+=0.011-dk
		e+=pen*3.0
		var to_axis: Vector3=(a0+a*clampf((palm-a0).dot(a),0.0,length))-palm
		var facing:=(R*hn).normalized().dot(to_axis.normalized()) if to_axis.length()>0.001 else 1.0
		e+=maxf(0.0,0.5-facing)*0.03
		e+=d.length()*(2.0 if side=="Right" else 0.4)
		var re: float=reach_est.call(R,w)
		e+=re*0.6
		return [e,Transform3D(R,w),[pd,dw,pen,facing,d.length(),re]]
	var best:=[INF,Transform3D.IDENTITY,[],0.0,Vector3.ZERO]
	var offs:=[Vector3.ZERO]
	if free>0.0:
		offs=[]
		for x in [-1,0,1]:
			for y in [-1,0,1]:
				for z in [-1,0,1]: offs.append(Vector3(x,y,z)*free)
	for i in 36:
		var th:=-PI+i*TAU/36.0
		for d in offs:
			var r: Array=place.call(th,d)
			if float(r[0])<float(best[0]): best=[r[0],r[1],r[2],th,d]
	# doladění: střídavě natočení a posunutí, krok se půlí
	var dth:=TAU/72.0
	var dd:=free*0.5
	for it in 7:
		var improved:=true
		var guard:=0
		while improved and guard<6:
			improved=false
			guard+=1
			var cands:=[[best[3]+dth,best[4]],[best[3]-dth,best[4]]]
			if free>0.0:
				for ax in [Vector3.RIGHT,Vector3.UP,Vector3.BACK]:
					for sg in [-1.0,1.0]:
						var nd: Vector3=best[4]+ax*sg*dd
						if nd.length()<=free*1.8: cands.append([best[3],nd])
			for c in cands:
				var r: Array=place.call(c[0],c[1])
				if float(r[0])<float(best[0])-1e-6:
					best=[r[0],r[1],r[2],c[0],c[1]]
					improved=true
		dth*=0.5
		dd*=0.5
	var result: Transform3D=best[1]
	if extra.is_empty(): _wrist_cache[key]=result
	if OS.get_environment("GRIP_DEBUG")!="":
		var p: Array=best[2]
		print("úchop %s %s%s: cena %.1f | dlaň %.1f mm, zápěstí %.1f mm, průnik %.1f mm, čelem %.2f, posun cíle %.1f mm, ukazovák ke spoušti %.1f mm, natočení %.0f°" % [gun,side," (+kapsle)" if not extra.is_empty() else "",float(best[0])*1000.0,float(p[0])*1000.0,float(p[1])*1000.0,float(p[2])*1000.0,float(p[3]),float(p[4])*1000.0,float(p[5])*1000.0,rad_to_deg(float(best[3]))])
	return result

# --- prsty
func chains(side: String) -> Array:
	if _chains.has(side): return _chains[side]
	var out:=[]
	for f in FINGERS:
		var b:=[]
		for k in [1,2,3]: b.append(sk.find_bone("mixamorig_%sHand%s%d"%[side,f,k]))
		if b.has(-1): continue
		var rest:=[]
		for bi in b: rest.append(sk.get_bone_rest(bi))
		var tip_bone:=sk.find_bone("mixamorig_%sHand%s4"%[side,f])
		var tip: Vector3=sk.get_bone_rest(tip_bone).origin if tip_bone>=0 else Vector3(0,(rest[2] as Transform3D).origin.length()*0.85,0)
		out.append({"name":f,"bones":b,"rest":rest,"tip":tip,"range":CURL[f]})
	_chains[side]=out
	return out

static func fk(hand_xf: Transform3D, ch: Dictionary, c: Array, side_angle: float=0.0) -> Array:
	var pts:=[]
	var g:=hand_xf
	for j in 3:
		var r: Transform3D=ch.rest[j]
		var q:=r.basis.get_rotation_quaternion()
		if j==0 and side_angle!=0.0: q=q*Quaternion(Vector3.BACK,side_angle)
		q=q*Quaternion(Vector3.RIGHT,float(c[j]))
		g=g*Transform3D(Basis(q),r.origin)
		pts.append(g)
	return pts

## Průnik prstu do zbraně: [nejbližší článek s dotykem (-1 žádný), součet průniků].
func _contact(s, to_gun: Transform3D, pts: Array, ch: Dictionary, xf: Dictionary, extra: Array, r: float) -> Array:
	var first:=-1
	var depth:=0.0
	for j in 3:
		var a: Vector3=(pts[j] as Transform3D).origin
		var b: Vector3=(pts[j+1] as Transform3D).origin if j<2 else (pts[2] as Transform3D)*(ch.tip as Vector3)
		for t in ([0.45,0.85,1.0] if j==2 else [0.5,1.0]):
			var p: Vector3=to_gun*a.lerp(b,t)
			var d:=dist(s,p,xf,extra)
			if d<r:
				depth+=r-d
				if first<0: first=j
	return [first,depth]

func _first_hit(s, to_gun: Transform3D, pts: Array, ch: Dictionary, xf: Dictionary, extra: Array, r: float) -> int:
	return int(_contact(s,to_gun,pts,ch,xf,extra,r)[0])

## Ovinutí prstu: všechny články se zavírají spolu; článek, který narazí, i ty před ním zůstanou,
## zbytek se zavírá dál (prst obepne tvar zbraně). Když prst začíná uvnitř zbraně, nejdřív se
## z ní vymotá. Vrací ohyby [c1, c2, c3] (palec navíc odtažení [.., boční úhel]).
func wrap(gun: String, hand_xf: Transform3D, to_gun: Transform3D, ch: Dictionary, xf: Dictionary, extra: Array=[], steps: int=14) -> Array:
	if ch.name=="Thumb": return thumb(gun,hand_xf,to_gun,ch,xf,extra)
	var c: Array=_wrap1(gun,hand_xf,to_gun,ch,xf,extra,steps,0.0)
	return [c[0],c[1],c[2]]

func _wrap1(gun: String, hand_xf: Transform3D, to_gun: Transform3D, ch: Dictionary, xf: Dictionary, extra: Array, steps: int, side_a: float) -> Array:
	var s=sdf(gun)
	var rg: Array=ch.range
	var r:=finger_r*(1.15 if ch.name=="Thumb" else 1.0)
	var cur:=[rg[0][0],rg[1][0],rg[2][0]]
	var frozen:=[false,false,false]
	var start: Array=_contact(s,to_gun,fk(hand_xf,ch,cur,side_a),ch,xf,extra,r)
	var touched:=false
	var free:=float(start[1])<=0.0
	var best_bad:=[cur.duplicate(),float(start[1])]
	for step in range(1,steps+1):
		var t:=float(step)/steps
		var prop:=cur.duplicate()
		for j in 3:
			if not frozen[j]: prop[j]=lerpf(rg[j][0],rg[j][1],t)
		var hit: Array=_contact(s,to_gun,fk(hand_xf,ch,prop,side_a),ch,xf,extra,r)
		if not free:
			# začátek uvnitř zbraně: zavírat dál, dokud se nevymotá (pamatovat nejmenší průnik)
			cur=prop
			if float(hit[1])<float(best_bad[1]): best_bad=[prop.duplicate(),float(hit[1])]
			if float(hit[1])<=0.0: free=true
			continue
		if int(hit[0])<0:
			cur=prop
			continue
		touched=true
		var lo:=0.0
		var hi:=1.0
		for it in 3:
			var m:=(lo+hi)*0.5
			var test:=cur.duplicate()
			for j in 3: test[j]=lerpf(cur[j],prop[j],m)
			if int(_contact(s,to_gun,fk(hand_xf,ch,test,side_a),ch,xf,extra,r)[0])<0: lo=m
			else: hi=m
		for j in 3: cur[j]=lerpf(cur[j],prop[j],lo)
		for j in range(0,int(hit[0])+1): frozen[j]=true
		if frozen[2]: break
	if not free: cur=best_bad[0]
	var pen: float=float(_contact(s,to_gun,fk(hand_xf,ch,cur,side_a),ch,xf,extra,r)[1])
	return [cur[0],cur[1],cur[2],pen,touched]

## Rychlé ovinutí za běhu (přebíjení): prst jako celek (t 0 = otevřený, 1 = sevřený), začíná
## z minulého snímku – když je ve zbrani/zásobníku, povolí, jinak přitlačí. Pár vzorků na snímek.
func wrap_live(gun: String, hand_xf: Transform3D, to_gun: Transform3D, ch: Dictionary, xf: Dictionary, t0: float) -> Array:
	var s=sdf(gun)
	var rg: Array=ch.range
	var r:=finger_r
	var curl_at:=func(t: float) -> Array:
		return [lerpf(rg[0][0],rg[0][1],t),lerpf(rg[1][0],rg[1][1],t),lerpf(rg[2][0],rg[2][1],t)]
	var pen_at:=func(t: float) -> float:
		return float(_contact(s,to_gun,fk(hand_xf,ch,curl_at.call(t)),ch,xf,[],r)[1])
	var t:=clampf(t0,0.0,1.0)
	var p0: float=pen_at.call(t)
	if p0>0.0:
		# v průniku: zkusit povolit i sevřít (natažený prst může trčet do zbraně), nejmenší průnik
		var best:=[p0,t]
		for k in range(1,5):
			for sg in [-1.0,1.0]:
				var tt:=clampf(t+sg*0.14*k,0.0,1.0)
				var pp: float=pen_at.call(tt)
				if pp<float(best[0]): best=[pp,tt]
			if float(best[0])<=0.0: break
		t=best[1]
	else:
		var t2:=minf(1.0,t+0.12)
		if t2>t:
			if pen_at.call(t2)<=0.0: t=t2
			else:
				var lo:=t
				var hi:=t2
				for i in 2:
					var m:=(lo+hi)*0.5
					if pen_at.call(m)<=0.0: lo=m
					else: hi=m
				t=lo
	var out: Array=curl_at.call(t)
	out.append(0.0)
	out.append(t)
	return out

## Palec: má víc volnosti (ohyb tří článků + odtažení v kořeni), proto hledání s cenou:
## žádný průnik, poslední článek leží na povrchu zbraně (nebo prstech druhé ruky) a špička je
## v přirozené opozici proti prstům (obejme rukojeť / leží podél předpažbí).
func thumb(gun: String, hand_xf: Transform3D, to_gun: Transform3D, ch: Dictionary, xf: Dictionary, extra: Array=[], start: Array=[]) -> Array:
	var s=sdf(gun)
	var r:=finger_r*1.1
	var side:="Left" if "Left" in sk.get_bone_name(ch.bones[0]) else "Right"
	var h:=hand(side)
	var k: Vector3=h.k
	var n: Vector3=h.n
	var f:=k.cross(n).normalized()*(1.0 if side=="Right" else -1.0)
	n=f.cross(k).normalized()*(1.0 if side=="Right" else -1.0)
	# přirozená opozice (souřadnice ruky, jednotky kostry): u ukazováku, nad dlaní, vpředu
	var pref: Vector3=(k*-6.0+n*3.5+f*4.5)/86.0
	var inv:=hand_xf.affine_inverse()
	var cost:=func(c: Array, sa: float) -> float:
		var pts:=fk(hand_xf,ch,c,sa)
		var pen:=0.0
		var touch:=INF
		for j in 3:
			var a: Vector3=(pts[j] as Transform3D).origin
			var b: Vector3=(pts[j+1] as Transform3D).origin if j<2 else (pts[2] as Transform3D)*(ch.tip as Vector3)
			for t in [0.4,0.75,1.0]:
				var d:=dist(s,to_gun*a.lerp(b,t),xf,extra)
				if d<r: pen+=r-d
				if j==2: touch=minf(touch,d)
		var tip: Vector3=inv*((pts[2] as Transform3D)*(ch.tip as Vector3))
		return pen*30.0+absf(touch-r)*1.0+tip.distance_to(pref)*S*0.15+absf(sa)*0.004
	var best:=[INF,[0.0,0.0,0.0],0.0]
	var step:=0.12
	var iters:=4
	if start.size()>=4:
		# za běhu: jen doladit z minulé polohy (levná varianta pro přebíjení)
		best=[cost.call([start[0],start[1],start[2]],float(start[3])),[start[0],start[1],start[2]],float(start[3])]
		step=0.14
		iters=1
	else:
		for c1 in [-0.3,0.0,0.3,0.6,0.9]:
			for c2 in [-0.2,0.2,0.6,1.0]:
				for c3 in [-0.2,0.2,0.6,1.0]:
					for sa in [-0.8,-0.4,0.0,0.4,0.8]:
						var e: float=cost.call([c1,c2,c3],sa)
						if e<best[0]: best=[e,[c1,c2,c3],sa]
	for it in iters:
		var improved:=true
		var guard:=0
		while improved and guard<(2 if start.size()>=4 else 8):
			improved=false
			guard+=1
			for dim in 4:
				for sg in [-1.0,1.0]:
					var c: Array=(best[1] as Array).duplicate()
					var sa: float=best[2]
					if dim<3: c[dim]=clampf(float(c[dim])+sg*step,-0.35,1.25)
					else: sa=clampf(sa+sg*step,-1.0,1.0)
					var e: float=cost.call(c,sa)
					if e<float(best[0])-1e-7:
						best=[e,c,sa]
						improved=true
		step*=0.5
	var out: Array=(best[1] as Array).duplicate()
	out.append(best[2])
	return out

## Přechod ukazováku ze spouště na pouzdro a zpět: ohyby kloubů v čase t (0 = spoušť, 1 = pouzdro).
## Lineární přechod by prst protáhl lučíkem, proto několik průběhů; tools/bake_grips.gd vybere
## ten bez průniku.
static func index_blend(on: Array, off: Array, t: float, scheme: int) -> Array:
	var tc:=t       # ohyb
	var ts:=t       # odtažení
	var lift:=0.0
	match scheme:
		1:  # nejdřív narovnat konec prstu, pak zbytek
			tc=clampf(t*1.6,0.0,1.0)
			ts=clampf((t-0.35)/0.65,0.0,1.0)
		2:  # nejdřív odtáhnout do strany
			ts=clampf(t*1.8,0.0,1.0)
			tc=clampf((t-0.3)/0.7,0.0,1.0)
		3:  # zvednout prst z lučíku obloukem
			lift=-0.45*sin(PI*t)
	var c:=[]
	for j in 3:
		var k:=tc if j>0 else t
		c.append(lerpf(float(on[j]),float(off[j]),k)+(lift if j==0 else 0.0)+(lift*0.5 if j>0 else 0.0))
	c.append(lerpf(float(on[3]),float(off[3]),ts))
	return c

func index_path(gun: String, hand_xf: Transform3D, to_gun: Transform3D, ch: Dictionary, xf: Dictionary, on: Array, off: Array) -> int:
	var s=sdf(gun)
	var r:=finger_r*0.8
	var best:=[INF,0]
	for scheme in 4:
		var worst:=0.0
		for i in range(1,12):
			var c: Array=index_blend(on,off,i/12.0,scheme)
			var pts:=fk(hand_xf,ch,c,float(c[3]))
			for j in 3:
				var a: Vector3=(pts[j] as Transform3D).origin
				var b: Vector3=(pts[j+1] as Transform3D).origin if j<2 else (pts[2] as Transform3D)*(ch.tip as Vector3)
				for t in [0.5,1.0]:
					worst=maxf(worst,r-s.distance(to_gun*a.lerp(b,t),xf))
		if worst<float(best[0])-0.0005: best=[worst,scheme]
	if OS.get_environment("GRIP_DEBUG")!="": print("ukazovák %s: přechod %d, největší průnik %.1f mm" % [gun,best[1],maxf(0.0,float(best[0]))*1000.0])
	return best[1]

## Ukazovák mimo spoušť (přebíjení, sprint): natažený podél pouzdra nad lučíkem, bez průniku.
func along(gun: String, hand_xf: Transform3D, to_gun: Transform3D, ch: Dictionary, xf: Dictionary) -> Array:
	var s=sdf(gun)
	var r:=finger_r
	var cost:=func(c: Array, sa: float) -> float:
		var pts:=fk(hand_xf,ch,c,sa)
		var pen:=0.0
		var near:=INF
		for j in 3:
			var a: Vector3=(pts[j] as Transform3D).origin
			var b: Vector3=(pts[j+1] as Transform3D).origin if j<2 else (pts[2] as Transform3D)*(ch.tip as Vector3)
			for t in [0.35,0.7,1.0]:
				var d:=dist(s,to_gun*a.lerp(b,t),xf)
				if d<r*1.05: pen+=r*1.05-d
				if j>=1: near=minf(near,d)
		# položený na pouzdře (ne ve vzduchu), co nejrovnější
		return pen*40.0+absf(near-r*1.1)*0.6+(absf(float(c[0]))+float(c[1]))*0.004+absf(sa)*0.002
	var best:=[INF,[0.0,0.0,0.0],0.0]
	for c1 in [-0.35,-0.2,-0.05,0.1,0.25,0.4]:
		for c2 in [0.0,0.15,0.3,0.45,0.6]:
			for sa in [-0.6,-0.4,-0.2,0.0,0.2,0.4]:
				var c:=[c1,c2,c2*0.7]
				var e: float=cost.call(c,sa)
				if e<best[0]: best=[e,c,sa]
	var step:=0.06
	for it in 3:
		for d1 in [-1,0,1]:
			for d2 in [-1,0,1]:
				for ds in [-1,0,1]:
					var base: Array=best[1]
					var c:=[clampf(float(base[0])+d1*step,-0.4,1.0),clampf(float(base[1])+d2*step,0.0,1.4),0.0]
					c[2]=float(c[1])*0.7
					var sa: float=float(best[2])+ds*step
					var e: float=cost.call(c,sa)
					if e<best[0]: best=[e,c,sa]
		step*=0.5
	var out: Array=(best[1] as Array).duplicate()
	out.append(best[2])
	out.append(best[0])
	return out

## Ukazovák: bříško posledního článku na cílový bod (spoušť / pouzdro), bez zajíždění do zbraně.
func reach(gun: String, hand_xf: Transform3D, to_gun: Transform3D, ch: Dictionary, target_gun: Vector3, xf: Dictionary) -> Array:
	var s=sdf(gun)
	var r:=finger_r
	var cost:=func(c: Array, side_a: float, full: bool) -> float:
		var pts:=fk(hand_xf,ch,c,side_a)
		var g3: Transform3D=pts[2]
		var pad: Vector3=to_gun*(g3*((ch.tip as Vector3)*0.6+Vector3(0,0,r/S)))
		var e: float=pad.distance_to(target_gun)
		if full:
			for j in 3:
				var a: Vector3=(pts[j] as Transform3D).origin
				var b: Vector3=(pts[j+1] as Transform3D).origin if j<2 else g3*ch.tip
				for t in [0.5,1.0]:
					var p: Vector3=to_gun*a.lerp(b,t)
					if p.distance_to(target_gun)<0.012: continue
					var d: float=s.distance(p,xf)
					if d<r*0.85: e+=(r*0.85-d)*3.0
		return e+absf(float(c[2])-0.7*float(c[1]))*0.004
	var cands:=[]
	for i1 in range(-3,15):
		for i2 in range(0,17):
			for sa in [-0.6,-0.45,-0.3,-0.15,0.0,0.15,0.3,0.45,0.6]:
				var c:=[i1*0.1,i2*0.1,i2*0.07]
				cands.append([cost.call(c,sa,false),c,sa])
	cands.sort_custom(func(x,y): return x[0]<y[0])
	var best:=[INF,[0.0,0.0,0.0],0.0]
	for k in mini(30,cands.size()):
		var e: float=cost.call(cands[k][1],cands[k][2],true)
		if e<best[0]: best=[e,cands[k][1],cands[k][2]]
	# doladit
	var step:=0.04
	for it in 3:
		var base: Array=best[1]
		var sa0: float=best[2]
		for d1 in [-1,0,1]:
			for d2 in [-1,0,1]:
				for ds in [-1,0,1]:
					var c:=[base[0]+d1*step,base[1]+d2*step,(base[1]+d2*step)*0.7]
					var e: float=cost.call(c,sa0+ds*step,true)
					if e<best[0]: best=[e,c,sa0+ds*step]
		step*=0.5
	var out: Array=best[1].duplicate()
	out.append(best[2])
	out.append(best[0])
	return out

## Kapsle prstů ruky (souřadnice zbraně) – překážka pro druhou ruku.
func capsules(side: String, to_gun: Transform3D) -> Array:
	var out:=[]
	var r:=finger_r
	for ch in chains(side):
		var prev:=to_gun*sk.get_bone_global_pose((ch.bones[0] as int)).origin
		for j in 3:
			var bj: int=ch.bones[j]
			var g:=sk.get_bone_global_pose(bj)
			var p: Vector3=to_gun*(g*(ch.tip as Vector3)) if j==2 else to_gun*sk.get_bone_global_pose(ch.bones[j+1]).origin
			out.append([to_gun*g.origin,p,r])
	var h:=sk.get_bone_global_pose(sk.find_bone("mixamorig_%sHand"%side))
	var hd:=hand(side)
	out.append([to_gun*h.origin,to_gun*(h*hd.palm),0.025])
	return out

## O kolik a kam vytlačit ruku ze zbraně (souřadnice zbraně, metry).
func push_out(gun: String, side: String, to_gun: Transform3D, xf: Dictionary) -> Vector3:
	var s=sdf(gun)
	var h:=sk.get_bone_global_pose(sk.find_bone("mixamorig_%sHand"%side))
	var hd:=hand(side)
	var pts:=[[h.origin,0.02],[h*hd.palm,0.012]]
	for f in ["Index","Middle","Ring","Pinky","Thumb"]:
		var b:=sk.find_bone("mixamorig_%sHand%s1"%[side,f])
		if b<0: continue
		var g1:=sk.get_bone_global_pose(b)
		pts.append([g1.origin,0.011])
		# i první článek (patří k dlani, ohybem prstu se z věci nedostane)
		var b2:=sk.find_bone("mixamorig_%sHand%s2"%[side,f])
		if b2>=0: pts.append([g1.origin.lerp(sk.get_bone_global_pose(b2).origin,0.6),0.008])
	var push:=Vector3.ZERO
	for e in pts:
		var p: Vector3=to_gun*(e[0] as Vector3)
		var d: float=s.distance(p,xf)
		var need: float=float(e[1])-d
		if need>0.0:
			var g: Vector3=s.gradient(p,xf)
			var already:=push.dot(g)
			if need>already: push+=g*(need-already)
	return push
