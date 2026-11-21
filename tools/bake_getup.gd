extends SceneTree
## Animace zombie pečené z klíčových póz (pánev, hrudník, hlava + IK rukou a nohou):
##   getup_front – leží na břiše: zapře se rukama, přitáhne kolena, klekne na jedno koleno, vstane
##   getup_back  – leží na zádech: posadí se, zapře se rukama za sebou, přitáhne nohy, zvedne se z dřepu
##   stagger_back / stagger_left / stagger_right – zásah ji odhodí: trup se zvrátí, ruce se rozhodí
##     a udělá dva vrávoravé kroky (dozadu / do strany). Chodidla stojí na zemi pevně: posun těla
##     je v metadatech klipu "root_motion" (po snímcích, FPS) a hra jím posouvá kořen zombie.
## Konec každé animace přechází do první pózy klipu „idle“, takže navazuje bez skoku.
## Souřadnice kostry (jednotky kostry, Y nahoru, postava ve stoje kouká do +Z, levá strana je +X).
## Na konci stojí chodidla kolem počátku. Výstup: res://assets/zombie/getup_anims.res
##   godot --headless --path . --script res://tools/bake_getup.gd
const FPS:=30.0
const OUT:="res://assets/zombie/getup_anims.res"
var sk: Skeleton3D
var R0:={}       # kost -> globální klidová báze
var P0:={}       # kost -> globální klidový počátek
var REST:={}     # kost -> [d0, f0] (směr kosti a referenční směr v klidu)
var idle: Animation
var idle_rot:={}  # kost -> lokální rotace v první pózce idle
var idle_hips:=Vector3.ZERO
var warn:=[]

func B(n: String) -> int: return sk.find_bone("mixamorig_"+n)

static func frame(y: Vector3, z_hint: Vector3) -> Basis:
	var Y:=y.normalized()
	var X:=Y.cross(z_hint)
	if X.length()<1e-4: X=Y.cross(Vector3.RIGHT if absf(Y.x)<0.9 else Vector3.FORWARD)
	X=X.normalized()
	return Basis(X,Y,X.cross(Y))

func _initialize() -> void:
	var m: Node3D=(load("res://assets/zombie/zombie.fbx") as PackedScene).instantiate()
	root.add_child(m)
	sk=m.get_node("Skeleton3D")
	for b in sk.get_bone_count():
		var g:=sk.get_bone_global_rest(b)
		R0[b]=g.basis.orthonormalized()
		P0[b]=g.origin
	var lib: AnimationLibrary=load("res://assets/zombie/zombie_anims.res")
	idle=lib.get_animation("idle")
	for t in idle.get_track_count():
		var bn:=String(idle.track_get_path(t)).get_slice(":",1)
		var b:=sk.find_bone(bn)
		if idle.track_get_type(t)==Animation.TYPE_ROTATION_3D: idle_rot[b]=idle.track_get_key_value(t,0)
		elif idle.track_get_type(t)==Animation.TYPE_POSITION_3D: idle_hips=idle.track_get_key_value(t,0)
	var dir:=func(a: String, c: String) -> Vector3: return (P0[B(c)]-P0[B(a)]).normalized()
	for n in [["Hips","Spine"],["Spine","Spine1"],["Spine1","Spine2"],["Spine2","Neck"],["Neck","Head"],["Head","HeadTop_End"]]:
		REST[B(n[0])]=[dir.call(n[0],n[1]),Vector3.BACK]
	for s in ["Left","Right"]:
		REST[B(s+"Arm")]=[dir.call(s+"Arm",s+"ForeArm"),Vector3.FORWARD]          # f = špička lokte (dozadu v T-póze)
		REST[B(s+"ForeArm")]=[dir.call(s+"ForeArm",s+"Hand"),Vector3.FORWARD]
		REST[B(s+"Hand")]=[dir.call(s+"Hand",s+"HandMiddle1"),Vector3.DOWN]        # f = normála dlaně
		REST[B(s+"UpLeg")]=[dir.call(s+"UpLeg",s+"Leg"),Vector3.BACK]             # f = špička kolena (dopředu)
		REST[B(s+"Leg")]=[dir.call(s+"Leg",s+"Foot"),Vector3.BACK]
		REST[B(s+"Foot")]=[dir.call(s+"Foot",s+"ToeBase"),Vector3.UP]              # f = nárt
	var lib_out:=AnimationLibrary.new()
	lib_out.add_animation("getup_front",bake(FRONT,2.85))
	lib_out.add_animation("getup_back",bake(BACK,2.95))
	lib_out.add_animation("stagger_back",bake(STAGGER_BACK,1.25))
	lib_out.add_animation("stagger_left",bake(stagger_side(1.0),1.2))
	lib_out.add_animation("stagger_right",bake(stagger_side(-1.0),1.2))
	# Zrcadlené varianty pro zombie se zrcadlovým postojem (idle_m): začínají i končí v jejím postoji.
	# Zrcadlo levého úkroku je pravý úkrok, proto se jména prohodí.
	var M:=preload("res://tools/anim_mirror.gd")
	for pair in [["getup_front","getup_front_m"],["getup_back","getup_back_m"],["stagger_back","stagger_back_m"],
			["stagger_left","stagger_right_m"],["stagger_right","stagger_left_m"]]:
		lib_out.add_animation(pair[1],M.mirror(lib_out.get_animation(pair[0]),sk))
	var err:=ResourceSaver.save(lib_out,OUT)
	print("uloženo ",OUT," -> ",err)
	for w in warn: print(w)
	quit()

## Globální báze kosti, jejíž směr je d a referenční směr f.
func aim(b: int, d: Vector3, f: Vector3) -> Basis:
	var r: Array=REST[b]
	return frame(d,f)*frame(r[0],r[1]).transposed()*(R0[b] as Basis)

static func two_bone(s: Vector3, t: Vector3, a: float, b: float, pole: Vector3) -> Array:
	var d:=t-s
	var L:=clampf(d.length(),absf(a-b)+0.002,a+b-0.0005)
	var dn:=d.normalized()
	var x:=(a*a-b*b+L*L)/(2.0*L)
	var h:=sqrt(maxf(a*a-x*x,0.0))
	var pn:=(pole-dn*pole.dot(dn)).normalized()
	return [s+dn*x+pn*h, s+dn*L, pn, d.length()-L]

# ------------------------------------------------------------------ klíčové pózy
# hips = poloha pánve; pelvis/chest/head = [nahoru (směr páteře), dopředu (břicho / obličej)]
# lh, rh = zápěstí [poloha, směr prstů, normála dlaně, kam míří loket]
# lf, rf = kotník [poloha, směr kotník->bříško, nárt, kam míří koleno]
const FRONT:=[
	[0.0, {"hips":Vector3(0,0.15,-0.2),"pelvis":[Vector3(0,0.06,1),Vector3(0,-1,0.06)],"chest":[Vector3(0,0.08,1),Vector3(0,-1,0.08)],
		"head":[Vector3(0,0.12,1),Vector3(0.55,-0.83,0)],
		"lh":[Vector3(0.36,0.045,0.42),Vector3(0.25,0,1),Vector3(0,-1,0),Vector3(0.7,1,0)],
		"rh":[Vector3(-0.36,0.045,0.48),Vector3(-0.2,0,1),Vector3(0,-1,0),Vector3(-0.7,1,0)],
		"lf":[Vector3(0.16,0.13,-1.03),Vector3(0.05,-0.6,-0.8),Vector3(0,-0.8,0.6),Vector3(0,-1,0)],
		"rf":[Vector3(-0.15,0.13,-1.03),Vector3(-0.05,-0.6,-0.8),Vector3(0,-0.8,0.6),Vector3(0,-1,0)]}],
	[0.35, {}],
	[0.85, {"hips":Vector3(0,0.2,-0.26),"pelvis":[Vector3(0,0.25,1),Vector3(0,-1,0.25)],"chest":[Vector3(0,0.45,0.89),Vector3(0,-0.89,0.45)],
		"head":[Vector3(0,0.5,0.86),Vector3(0.1,-0.6,0.8)],
		"lh":[Vector3(0.33,0.045,0.3),Vector3(0.25,0,1),Vector3(0,-1,0),Vector3(0.6,0.3,-0.8)],
		"rh":[Vector3(-0.33,0.045,0.33),Vector3(-0.2,0,1),Vector3(0,-1,0),Vector3(-0.6,0.3,-0.8)]}],
	[1.35, {"hips":Vector3(0,0.45,-0.3),"pelvis":[Vector3(0,0.1,1),Vector3(0,-1,0.1)],"chest":[Vector3(0,-0.12,0.99),Vector3(0,-0.99,-0.12)],
		"head":[Vector3(0,0.3,0.95),Vector3(0,-0.6,0.8)],
		"lf":[Vector3(0.15,0.11,-0.72),Vector3(0,-0.25,-0.97),Vector3(0,-0.97,0.25),Vector3(0,-1,0.7)],
		"rf":[Vector3(-0.15,0.11,-0.72),Vector3(0,-0.25,-0.97),Vector3(0,-0.97,0.25),Vector3(0,-1,0.7)]}],
	[1.85, {"hips":Vector3(0,0.56,-0.24),"pelvis":[Vector3(0,0.55,0.84),Vector3(0,-0.84,0.55)],"chest":[Vector3(0,0.5,0.87),Vector3(0,-0.87,0.5)],
		"head":[Vector3(0,0.65,0.76),Vector3(0,-0.35,0.94)],
		"lh":[Vector3(0.27,0.44,0.3),Vector3(0.1,-0.85,0.5),Vector3(-1,0,0.2),Vector3(0.4,0,-1)],
		"rh":[Vector3(-0.2,0.47,0.12),Vector3(0,-0.3,1),Vector3(0,-1,-0.3),Vector3(-0.5,0,-1)],
		"rf":[Vector3(-0.16,0.13,0.1),Vector3(0,-0.74,0.68),Vector3(0,1,0),Vector3(0,0.4,1)]}],
	[2.35, {"hips":Vector3(0,0.82,-0.06),"pelvis":[Vector3(0,0.88,0.47),Vector3(0,-0.47,0.88)],"chest":[Vector3(0,0.82,0.57),Vector3(0,-0.57,0.82)],
		"head":[Vector3(0,0.9,0.43),Vector3(0,-0.3,0.95)],
		"lh":[Vector3(0.29,0.88,0.3),Vector3(0.1,-0.85,0.5),Vector3(-1,0,0.2),Vector3(0.3,0,-1)],
		"rh":[Vector3(-0.29,0.9,0.32),Vector3(-0.1,-0.85,0.5),Vector3(1,0,0.2),Vector3(-0.3,0,-1)],
		"lf":[Vector3(0.14,0.13,-0.06),Vector3(0.05,-0.74,0.68),Vector3(0,1,0),Vector3(0.1,0.2,1)]}],
]
const BACK:=[
	[0.0, {"hips":Vector3(0,0.14,-0.3),"pelvis":[Vector3(0,0.05,-1),Vector3(0,1,0.05)],"chest":[Vector3(0,0.08,-1),Vector3(0,1,0.08)],
		"head":[Vector3(0,0.12,-1),Vector3(0.4,0.92,0)],
		"lh":[Vector3(0.4,0.05,-0.42),Vector3(0.1,0,1),Vector3(0,-1,0),Vector3(1,0.4,0)],
		"rh":[Vector3(-0.4,0.05,-0.42),Vector3(-0.1,0,1),Vector3(0,-1,0),Vector3(-1,0.4,0)],
		"lf":[Vector3(0.19,0.1,0.56),Vector3(0.35,0.6,0.72),Vector3(0.2,-0.3,1),Vector3(0.3,1,0)],
		"rf":[Vector3(-0.19,0.1,0.56),Vector3(-0.35,0.6,0.72),Vector3(-0.2,-0.3,1),Vector3(-0.3,1,0)]}],
	[0.35, {}],
	[0.9, {"hips":Vector3(0,0.14,-0.28),"pelvis":[Vector3(0,0.6,-0.8),Vector3(0,0.8,0.6)],"chest":[Vector3(0,0.78,-0.62),Vector3(0,0.62,0.78)],
		"head":[Vector3(0,0.95,0.3),Vector3(0,-0.3,0.95)],
		"lh":[Vector3(0.3,0.045,-0.74),Vector3(0.5,0,-0.85),Vector3(0,-1,0),Vector3(0.2,0.3,-1)],
		"rh":[Vector3(-0.3,0.045,-0.74),Vector3(-0.5,0,-0.85),Vector3(0,-1,0),Vector3(-0.2,0.3,-1)],
		"lf":[Vector3(0.18,0.12,0.42),Vector3(0.1,-0.4,0.9),Vector3(0,0.9,0.4),Vector3(0.2,1,0.2)],
		"rf":[Vector3(-0.18,0.12,0.42),Vector3(-0.1,-0.4,0.9),Vector3(0,0.9,0.4),Vector3(-0.2,1,0.2)]}],
	[1.4, {"hips":Vector3(0,0.15,-0.25),"pelvis":[Vector3(0,0.88,0.47),Vector3(0,-0.47,0.88)],"chest":[Vector3(0,0.38,0.92),Vector3(0,-0.92,0.38)],
		"head":[Vector3(0,0.75,0.66),Vector3(0,-0.5,0.86)],
		"lh":[Vector3(0.34,0.045,0.16),Vector3(0.2,0,1),Vector3(0,-1,0),Vector3(0.6,0.3,-0.8)],
		"rh":[Vector3(-0.34,0.045,0.16),Vector3(-0.2,0,1),Vector3(0,-1,0),Vector3(-0.6,0.3,-0.8)],
		"lf":[Vector3(0.17,0.13,0.06),Vector3(0.05,-0.74,0.68),Vector3(0,1,0),Vector3(0.25,0.5,1)],
		"rf":[Vector3(-0.17,0.13,0.06),Vector3(-0.05,-0.74,0.68),Vector3(0,1,0),Vector3(-0.25,0.5,1)]}],
	[1.95, {"hips":Vector3(0,0.42,-0.15),"pelvis":[Vector3(0,0.5,0.87),Vector3(0,-0.87,0.5)],"chest":[Vector3(0,0.4,0.92),Vector3(0,-0.92,0.4)],
		"head":[Vector3(0,0.75,0.66),Vector3(0,-0.35,0.94)],
		"lh":[Vector3(0.2,0.47,0.17),Vector3(0,-0.3,1),Vector3(0,-1,-0.3),Vector3(0.5,0,-1)],
		"rh":[Vector3(-0.2,0.47,0.17),Vector3(0,-0.3,1),Vector3(0,-1,-0.3),Vector3(-0.5,0,-1)]}],
	[2.45, {"hips":Vector3(0,0.82,-0.06),"pelvis":[Vector3(0,0.88,0.47),Vector3(0,-0.47,0.88)],"chest":[Vector3(0,0.82,0.57),Vector3(0,-0.57,0.82)],
		"head":[Vector3(0,0.9,0.43),Vector3(0,-0.3,0.95)],
		"lh":[Vector3(0.29,0.88,0.3),Vector3(0.1,-0.85,0.5),Vector3(-1,0,0.2),Vector3(0.3,0,-1)],
		"rh":[Vector3(-0.29,0.9,0.32),Vector3(-0.1,-0.85,0.5),Vector3(1,0,0.2),Vector3(-0.3,0,-1)],
		"lf":[Vector3(0.14,0.13,0.0),Vector3(0.05,-0.74,0.68),Vector3(0,1,0),Vector3(0.1,0.2,1)],
		"rf":[Vector3(-0.15,0.13,0.04),Vector3(-0.05,-0.74,0.68),Vector3(0,1,0),Vector3(-0.1,0.2,1)]}],
]

# Postoj v idle (první snímek): k němu se klipy zásahu vrací.
const ST_LF:=[Vector3(0.29,0.13,0.19),Vector3(0.05,-0.74,0.68),Vector3(0,1,0),Vector3(0.35,0.2,1)]
const ST_RF:=[Vector3(-0.31,0.13,-0.09),Vector3(-0.05,-0.74,0.68),Vector3(0,1,0),Vector3(-0.35,0.2,1)]
const ST_LH:=[Vector3(0.14,1.18,0.36),Vector3(0.15,-0.35,0.92),Vector3(-0.2,-0.9,0.1),Vector3(0.9,-0.3,-0.4)]
const ST_RH:=[Vector3(-0.31,1.24,0.25),Vector3(-0.15,-0.35,0.92),Vector3(0.2,-0.9,0.1),Vector3(-0.9,-0.3,-0.4)]
static func _sh(v: Array, d: Vector3) -> Array: return [(v[0] as Vector3)+d,v[1],v[2],v[3]]

# Zásah zepředu: trup se zvrátí dozadu, hlava cukne, ruce vyletí, dva kroky vzad (pravá, levá).
const ST_BACK_END:=Vector3(0,0,-0.55)
var STAGGER_BACK:=[
	[0.0, {"root":Vector3.ZERO,"hips":Vector3(0,0.93,-0.01),"pelvis":[Vector3(0,1,0.08),Vector3(0,-0.08,1)],"chest":[Vector3(0,0.93,0.36),Vector3(0,-0.36,0.93)],
		"head":[Vector3(0,0.9,0.43),Vector3(0,-0.4,0.92)],"lh":ST_LH,"rh":ST_RH,"lf":ST_LF,"rf":ST_RF}],
	[0.08, {"root":Vector3(0,0,-0.03),"hips":Vector3(0,0.93,-0.07),"pelvis":[Vector3(0,1,-0.06),Vector3(0,0.06,1)],"chest":[Vector3(0,0.94,-0.33),Vector3(0,0.33,0.94)],
		"head":[Vector3(0.08,0.82,-0.56),Vector3(0.05,0.56,0.82)],
		"lh":[Vector3(0.34,1.48,0.3),Vector3(0.35,0.5,0.8),Vector3(-0.3,-0.6,0.4),Vector3(0.9,-0.4,-0.3)],
		"rh":[Vector3(-0.36,1.42,0.24),Vector3(-0.35,0.45,0.82),Vector3(0.3,-0.6,0.4),Vector3(-0.9,-0.4,-0.3)]}],
	[0.22, {"root":Vector3(0,0,-0.14),"hips":Vector3(0,0.9,-0.18),"chest":[Vector3(0,0.97,-0.24),Vector3(0,0.24,0.97)],
		"head":[Vector3(-0.05,0.9,-0.4),Vector3(-0.03,0.4,0.9)],
		"lh":[Vector3(0.5,1.5,0.05),Vector3(0.6,0.7,0.2),Vector3(-0.6,0.2,0.7),Vector3(0.6,-0.6,-0.5)],
		"rh":[Vector3(-0.55,1.12,0.0),Vector3(-0.9,-0.3,0.2),Vector3(0.2,-0.9,0.3),Vector3(-0.3,-0.5,-0.8)],
		"rf":_sh(ST_RF,Vector3(0.02,0.1,-0.25))}],
	[0.36, {"root":Vector3(0,0,-0.29),"hips":Vector3(0,0.86,-0.32),"pelvis":[Vector3(0,1,0.02),Vector3(0,-0.02,1)],"chest":[Vector3(0,0.98,-0.1),Vector3(0,0.1,0.98)],
		"rf":_sh(ST_RF,ST_BACK_END)}],
	[0.5, {"root":Vector3(0,0,-0.41),"hips":Vector3(0,0.85,-0.43),"chest":[Vector3(0,0.97,0.12),Vector3(0,-0.12,0.97)],
		"head":[Vector3(0,0.98,0.1),Vector3(0,-0.1,0.98)],
		"lh":[Vector3(0.48,1.3,-0.15),Vector3(0.5,0.3,0.6),Vector3(-0.5,-0.5,0.4),Vector3(0.7,-0.6,-0.4)],
		"rh":[Vector3(-0.5,1.2,-0.25),Vector3(-0.6,0.1,0.75),Vector3(0.4,-0.7,0.3),Vector3(-0.7,-0.6,-0.4)],
		"lf":_sh(ST_LF,Vector3(0.0,0.1,-0.3))}],
	[0.64, {"root":Vector3(0,0,-0.5),"hips":Vector3(0,0.86,-0.53),"lf":_sh(ST_LF,ST_BACK_END)}],
	[0.82, {"root":ST_BACK_END,"hips":Vector3(0,0.9,-0.57),"pelvis":[Vector3(0,1,0.1),Vector3(0,-0.1,1)],"chest":[Vector3(0,0.88,0.47),Vector3(0,-0.47,0.88)],
		"head":[Vector3(0,0.86,0.5),Vector3(0,-0.45,0.89)],"lh":_sh(ST_LH,ST_BACK_END+Vector3(0.05,-0.06,0.05)),"rh":_sh(ST_RH,ST_BACK_END+Vector3(-0.03,-0.08,0.05))}],
	[1.02, {"hips":Vector3(0,0.93,-0.56),"chest":[Vector3(0,0.93,0.36),Vector3(0,-0.36,0.93)],"head":[Vector3(0,0.9,0.43),Vector3(0,-0.4,0.92)],
		"lh":_sh(ST_LH,ST_BACK_END),"rh":_sh(ST_RH,ST_BACK_END)}],
]

## Zásah z boku: s = +1 odhodí zombii na její levou stranu (+X), -1 na pravou. Napřed vykročí
## noha na té straně, druhá se dotáhne; trup se ohne od rány, hlava cukne, ruce se rozhodí.
func stagger_side(s: float) -> Array:
	var end:=Vector3(0.37*s,0,0)
	var lead_f:Array=ST_LF if s>0.0 else ST_RF        # noha na straně, kam letí
	var trail_f:Array=ST_RF if s>0.0 else ST_LF
	var lead_h:Array=ST_LH if s>0.0 else ST_RH
	var trail_h:Array=ST_RH if s>0.0 else ST_LH
	var lk:="lf" if s>0.0 else "rf"
	var tk:="rf" if s>0.0 else "lf"
	var lhk:="lh" if s>0.0 else "rh"
	var thk:="rh" if s>0.0 else "lh"
	return [
		[0.0, {"root":Vector3.ZERO,"hips":Vector3(0,0.93,-0.01),"pelvis":[Vector3(0,1,0.08),Vector3(0,-0.08,1)],"chest":[Vector3(0,0.93,0.36),Vector3(0,-0.36,0.93)],
			"head":[Vector3(0,0.9,0.43),Vector3(0,-0.4,0.92)],"lh":ST_LH,"rh":ST_RH,"lf":ST_LF,"rf":ST_RF}],
		[0.08, {"root":Vector3(0.04*s,0,0),"hips":Vector3(0.07*s,0.92,0.0),"pelvis":[Vector3(-0.12*s,1,0.05),Vector3(0,-0.05,1)],
			"chest":[Vector3(0.38*s,0.88,0.28),Vector3(-0.2*s,-0.28,0.94)],"head":[Vector3(0.55*s,0.8,0.25),Vector3(-0.35*s,-0.1,0.93)],
			lhk:[Vector3(0.6*s,1.28,0.12),Vector3(0.8*s,0.2,0.5),Vector3(0,-1,0),Vector3(0.6*s,-0.4,-0.7)],
			thk:[Vector3(-0.12*s,1.45,0.38),Vector3(0.3*s,0.6,0.7),Vector3(0.3*s,-0.6,0.5),Vector3(-0.9*s,-0.3,-0.3)]}],
		[0.24, {"root":Vector3(0.16*s,0,0),"hips":Vector3(0.2*s,0.88,0.0),"chest":[Vector3(0.3*s,0.92,0.25),Vector3(-0.3*s,-0.25,0.92)],
			lk:_sh(lead_f,Vector3(0.18*s,0.11,-0.03))}],
		[0.38, {"root":Vector3(0.27*s,0,0),"hips":Vector3(0.3*s,0.87,0.0),lk:_sh(lead_f,end),
			"head":[Vector3(0.2*s,0.93,0.3),Vector3(-0.1*s,-0.3,0.95)]}],
		[0.52, {"root":Vector3(0.33*s,0,0),"hips":Vector3(0.36*s,0.87,0.0),tk:_sh(trail_f,Vector3(0.2*s,0.1,0.0)),
			"chest":[Vector3(0.05*s,0.93,0.36),Vector3(0,-0.36,0.93)]}],
		[0.64, {"root":end,"hips":Vector3(0.37*s,0.89,-0.01),tk:_sh(trail_f,end)}],
		[0.82, {"hips":Vector3(0.37*s,0.92,-0.01),"pelvis":[Vector3(0,1,0.08),Vector3(0,-0.08,1)],"chest":[Vector3(0,0.93,0.36),Vector3(0,-0.36,0.93)],
			"head":[Vector3(0,0.9,0.43),Vector3(0,-0.4,0.92)],lhk:_sh(lead_h,end+Vector3(0.04*s,-0.05,0.0)),thk:_sh(trail_h,end+Vector3(0,-0.05,0.04))}],
		[1.0, {"hips":Vector3(0.37*s,0.93,-0.01),lhk:_sh(lead_h,end),thk:_sh(trail_h,end)}],
	]

## Doplní klíče: chybějící položka = drží hodnotu z předchozího klíče.
static func fill(keys: Array) -> Array:
	var out:=[]
	var cur:={}
	for k in keys:
		for n in (k[1] as Dictionary): cur[n]=k[1][n]
		out.append([float(k[0]),cur.duplicate(true)])
	return out

static func ease3(u: float) -> float: return u*u*(3.0-2.0*u)

## Plynulá křivka přes klíče (Hermite, tečny z okolních klíčů, na krajích nulové).
static func hermite(ts: Array, vs: Array, t: float) -> Variant:
	var n:=ts.size()
	if t<=ts[0]: return vs[0]
	if t>=ts[n-1]: return vs[n-1]
	var i:=0
	while i<n-2 and t>ts[i+1]: i+=1
	var t0: float=ts[i]
	var t1: float=ts[i+1]
	var h:=t1-t0
	var u:=(t-t0)/h
	var m0: Variant=(vs[i+1]-vs[i-1])/(t1-ts[i-1])*h if i>0 else vs[0]*0.0
	var m1: Variant=(vs[i+2]-vs[i])/(ts[i+2]-t0)*h if i<n-2 else vs[0]*0.0
	# drží-li se hodnota (opora na zemi), bez překmitu
	if (vs[i] as Variant)==vs[i+1]: return vs[i]
	var u2:=u*u
	var u3:=u2*u
	return vs[i]*(2*u3-3*u2+1)+m0*(u3-2*u2+u)+vs[i+1]*(-2*u3+3*u2)+m1*(u3-u2)

## Končetina mezi klíči: ease bez překmitu, oblouk nahoru, když se přesouvá po zemi.
static func limb(ts: Array, vs: Array, t: float, lift: float) -> Array:
	var n:=ts.size()
	if t<=ts[0]: return vs[0]
	if t>=ts[n-1]: return vs[n-1]
	var i:=0
	while i<n-2 and t>ts[i+1]: i+=1
	var u:=ease3((t-ts[i])/(ts[i+1]-ts[i]))
	var a: Array=vs[i]
	var b: Array=vs[i+1]
	var p: Vector3=(a[0] as Vector3).lerp(b[0],u)
	var dist:=(a[0] as Vector3).distance_to(b[0])
	if dist>0.05: p.y+=sin(u*PI)*lift*clampf(dist/0.3,0.3,1.0)
	var out:=[p]
	for j in range(1,4): out.append(((a[j] as Vector3).normalized().lerp((b[j] as Vector3).normalized(),u)).normalized())
	return out

func bake(keys_in: Array, length: float) -> Animation:
	var keys:=fill(keys_in)
	var ts:=[]
	for k in keys: ts.append(k[0])
	var series:=func(name: String) -> Array:
		var vs:=[]
		for k in keys: vs.append(k[1][name])
		return vs
	var anim:=Animation.new()
	anim.length=length
	var root_samples:=PackedVector3Array()
	# stejné stopy jako ostatní klipy zombie (pánev: poloha + rotace, ostatní rotace)
	var tracks:={}
	var hips_pos:=anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(hips_pos,"Skeleton3D:mixamorig_Hips")
	for t in idle.get_track_count():
		if idle.track_get_type(t)!=Animation.TYPE_ROTATION_3D: continue
		var bn:=String(idle.track_get_path(t)).get_slice(":",1)
		var tr:=anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(tr,"Skeleton3D:"+bn)
		tracks[sk.find_bone(bn)]=tr
	var last_key: float=ts[ts.size()-1]
	var nf:=int(ceil(length*FPS))
	for fi in nf+1:
		var t:=minf(fi/FPS,length)
		var G:={}
		var O:={}
		# posun kořene (krokování): pozice ve světě -> v souřadnicích kořene, který hra posouvá
		var rt: Vector3=hermite(ts,series.call("root"),t) if (keys[0][1] as Dictionary).has("root") else Vector3.ZERO
		root_samples.append(rt)
		var hp: Vector3=(hermite(ts,series.call("hips"),t) as Vector3)-rt
		var pel: Array=[(hermite(ts,_col(series.call("pelvis"),0),t) as Vector3).normalized(),(hermite(ts,_col(series.call("pelvis"),1),t) as Vector3).normalized()]
		var che: Array=[(hermite(ts,_col(series.call("chest"),0),t) as Vector3).normalized(),(hermite(ts,_col(series.call("chest"),1),t) as Vector3).normalized()]
		var hed: Array=[(hermite(ts,_col(series.call("head"),0),t) as Vector3).normalized(),(hermite(ts,_col(series.call("head"),1),t) as Vector3).normalized()]
		var hips:=B("Hips")
		G[hips]=aim(hips,pel[0],pel[1])
		O[hips]=hp
		# páteř: pánev -> hrudník rozložit do tří obratlů
		var spine:=[B("Spine"),B("Spine1"),B("Spine2")]
		for j in 3:
			var w:=(j+1)/3.0
			var up: Vector3=(pel[0] as Vector3).slerp(che[0],w)
			var fw: Vector3=(pel[1] as Vector3).slerp(che[1],w)
			G[spine[j]]=aim(spine[j],up,fw)
		var neck:=B("Neck")
		G[neck]=aim(neck,(che[0] as Vector3).slerp(hed[0],0.5),(che[1] as Vector3).slerp(hed[1],0.5))
		G[B("Head")]=aim(B("Head"),hed[0],hed[1])
		# počátky kostí od kořene dolů
		var order:=[hips]+spine+[neck,B("Head")]
		for b in order:
			if b==hips: continue
			var p:=sk.get_bone_parent(b)
			O[b]=O[p]+(G[p] as Basis)*(sk.get_bone_rest(b).origin)
		var q_chest: Basis=(G[B("Spine2")] as Basis)*(R0[B("Spine2")] as Basis).inverse()
		for s in ["Left","Right"]:
			var sh:=B(s+"Shoulder")
			G[sh]=q_chest*(R0[sh] as Basis)
			O[sh]=O[B("Spine2")]+(G[B("Spine2")] as Basis)*sk.get_bone_rest(sh).origin
			var arm:=B(s+"Arm")
			O[arm]=O[sh]+(G[sh] as Basis)*sk.get_bone_rest(arm).origin
			var fa:=B(s+"ForeArm")
			var ha:=B(s+"Hand")
			var h: Array=(limb(ts,series.call("lh" if s=="Left" else "rh"),t,0.1) as Array).duplicate()
			h[0]=(h[0] as Vector3)-rt
			var ik:=two_bone(O[arm],h[0],sk.get_bone_rest(fa).origin.length(),sk.get_bone_rest(ha).origin.length(),h[3])
			if float(ik[3])>0.03: warn.append("t=%.2f %s ruka nedosáhne o %.0f mm (rameno %s cíl %s)"%[t,s,float(ik[3])*1000,(O[arm] as Vector3).snapped(Vector3.ONE*0.01),(h[0] as Vector3).snapped(Vector3.ONE*0.01)])
			G[arm]=aim(arm,(ik[0] as Vector3)-(O[arm] as Vector3),ik[2])
			G[fa]=aim(fa,(ik[1] as Vector3)-(ik[0] as Vector3),ik[2])
			G[ha]=aim(ha,h[1],h[2])
			var ul:=B(s+"UpLeg")
			O[ul]=O[hips]+(G[hips] as Basis)*sk.get_bone_rest(ul).origin
			var lg:=B(s+"Leg")
			var ft:=B(s+"Foot")
			var f: Array=(limb(ts,series.call("lf" if s=="Left" else "rf"),t,0.14) as Array).duplicate()
			f[0]=(f[0] as Vector3)-rt
			var ik2:=two_bone(O[ul],f[0],sk.get_bone_rest(lg).origin.length(),sk.get_bone_rest(ft).origin.length(),f[3])
			if float(ik2[3])>0.03: warn.append("t=%.2f %s noha nedosáhne o %.0f mm"%[t,s,float(ik2[3])*1000])
			G[ul]=aim(ul,(ik2[0] as Vector3)-(O[ul] as Vector3),ik2[2])
			G[lg]=aim(lg,(ik2[1] as Vector3)-(ik2[0] as Vector3),ik2[2])
			G[ft]=aim(ft,f[1],f[2])
			var toe:=B(s+"ToeBase")
			G[toe]=(G[ft] as Basis)*(R0[ft] as Basis).inverse()*(R0[toe] as Basis)
		# na konci plynule do první pózy idle
		var blend:=ease3(clampf((t-last_key)/(length-last_key),0.0,1.0))
		var hips_out:=hp.lerp(idle_hips,blend)
		anim.position_track_insert_key(hips_pos,t,hips_out)
		for b in tracks:
			var q: Quaternion
			if G.has(b):
				var p:=sk.get_bone_parent(b)
				var pg: Basis=G[p] if p>=0 else Basis()
				q=(pg.inverse()*(G[b] as Basis)).get_rotation_quaternion()
			else:
				q=idle_rot.get(b,sk.get_bone_rest(b).basis.get_rotation_quaternion())
			if idle_rot.has(b): q=q.slerp(idle_rot[b],blend)
			anim.rotation_track_insert_key(tracks[b],t,q.normalized())
	if (keys[0][1] as Dictionary).has("root"):
		anim.set_meta("root_motion",root_samples)
		anim.set_meta("root_fps",FPS)
	return anim

static func _col(arr: Array, i: int) -> Array:
	var out:=[]
	for a in arr: out.append(a[i])
	return out
