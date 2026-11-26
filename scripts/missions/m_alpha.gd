extends "res://scripts/missions/mission.gd"
## Hon na alfu: zabij bažináka (hýbe se, jen když se nedíváš) a odeber z těla vzorek tkáně.

var dead := false
var sampled := false
var body_pos := Vector3.ZERO

func _init() -> void:
	title = "Hon na alfu"
	brief = "Pozorovatelé hlásí velký exemplář. Hýbe se jen, když se na něj nikdo nedívá, držte ho ve světle baterky. Zabijte ho a odeberte vzorek tkáně."
	wants_alpha = true
	ambient_cap = 4

func start() -> void:
	var a: Node = director.waves.alpha
	a.hunt()
	a.died.connect(_on_dead)

func _on_dead(pos: Vector3) -> void:
	dead = true
	body_pos = pos
	director.radio("Centrála: Potvrzujeme zásah. Odeberte vzorek, než se tělo potopí do bahna.", 6.0)
	director.add_action(pos + Vector3(0, 0.3, 0), "Odebrat vzorek tkáně", 3.0, _sample, true, 3.0)

func _sample() -> void:
	sampled = true
	director.snd("res://audio/syringe_inject.wav", -2.0, 0.8)
	complete()

func lines() -> Array:
	if dead: return ["Bažinák je mrtvý", "Odeber vzorek z těla"]
	var a: Node = director.waves.alpha
	var l := ["Zabij bažináka (zdraví %d %%)" % int(a.hp / a.MAX_HP * 100.0)]
	l.append("Přijde si pro vás sám. Sviťte na něj.")
	return l

## Zaměřovač ho nenajde (to by byla moc snadná hra) – vede až k mrtvému tělu.
func targets() -> Array:
	return [body_pos] if dead and not sampled else []
