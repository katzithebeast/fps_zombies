extends "res://scripts/missions/mission.gd"
## Najdi předchozí četu: 4 těla na různých místech mapy, u každého diktafon se záznamem.
## U každého těla leží jeho baterka a pořád svítí (kužel je v mlze vidět zdálky).

const LOGS := [
	["„Záznam, třiadvacet deset. Jsme u té zrezivělé cedule. Pavel tvrdí, že něco slyšel ve vodě…“",
	"„…vysílačka chrčí, centrála neodpovídá. Pokračujeme dál od lávky.“"],
	["„Jirka je pryč. Stál tři metry ode mě. Otočil jsem se k baterce… a byl pryč.“",
	"„Na vodě jen kruhy. Žádný výkřik. Nic.“"],
	["„Hýbe se, jenom když se nedíváme. Musíte na něj pořád svítit. Pořád!“",
	"„Baterka mi slábne… slyším ho čvachtat za sebou…“"],
	["„Jestli tohle někdo najde… nechoďte k bunkru. Tam to začalo.“",
	"„Zelená voda uvnitř… to není voda… [šum]“"],
]

var bodies: Array = []
var got := 0

func _init() -> void:
	title = "Najdi předchozí četu"
	brief = "Četa 2 se před třemi dny přestala ozývat. Najděte všechny čtyři. Každý měl diktafon, vyzvedněte záznamy. Baterky jim prý pořád svítí."

func place() -> void:
	var th: Dictionary = main.mission_theme()
	var pts: Array = main.mission_points(4, {"where": "land", "min_spawn": 24.0, "sep": 24.0, "clear": 1.5})
	var poses := [Vector3(-PI * 0.5, 0, 0), Vector3(PI * 0.5, 0, 0), Vector3(0, 0, PI * 0.5)]
	for i in pts.size():
		var p: Vector3 = pts[i]
		var yaw: float = main.rng.randf() * TAU
		var kind := i % 3
		var body: Node3D = director.place_model(main, th.corpses[kind], 1.78, p + Vector3(0, -0.07, 0), yaw, poses[kind])
		# diktafon vedle ruky, baterka o kus dál (svítí do strany)
		var side := Vector3(cos(yaw), 0, -sin(yaw))
		var dp: Vector3 = p + side * 0.75 + Vector3(0, 0, 0)
		dp.y = main.ground(dp.x, dp.z) - 0.005
		var dic: Node3D = director.place_model(main, th.dictaphone, 0.11, dp, main.rng.randf() * TAU, Vector3(-PI * 0.5, 0, 0))
		var lp: Vector3 = p - side * 0.9
		lp.y = maxf(main.ground(lp.x, lp.z), main.WATER_Y)
		director.dropped_light(lp, main.rng.randf() * TAU)
		var b := {"pos": p, "body": body, "dic": dic, "done": false}
		b.act = director.add_action(dp, "Vzít diktafon", 1.4, _take.bind(b))
		bodies.append(b)

func _take(b: Dictionary) -> void:
	b.done = true
	if is_instance_valid(b.dic): b.dic.queue_free()
	got += 1
	director.play_log(LOGS[got - 1])
	if got == bodies.size(): complete()

func lines() -> Array:
	return ["Záznamy z diktafonů: %d/%d" % [got, bodies.size()]]

func targets() -> Array:
	var out := []
	for b in bodies:
		if not b.done: out.append(b.pos)
	return out
