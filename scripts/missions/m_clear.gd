extends "res://scripts/missions/mission.gd"
## Vyčisti oblast: 4 vlny zombie, pak odlet.

const ROUNDS := 4

func _init() -> void:
	title = "Vyčisti oblast"
	brief = "Oblast je zamořená. Zlikvidujte všechno, co se pohne. Čtyři vlny, pak vás vyzvedneme."
	waves_mode = "rounds"
	max_rounds = ROUNDS

func start() -> void:
	director.waves.rounds_done.connect(complete)

func lines() -> Array:
	var w: Node = director.waves
	var alive: int = w._alive() + w._to_spawn
	if w.round_now == 0: return ["Vlna 1/%d začíná…" % ROUNDS]
	return ["Vlna %d/%d – zbývá %d" % [w.round_now, ROUNDS, alive]]

## Zaměřovač vede k posledním zombie (ať se nedá schovat ve tmě).
func targets() -> Array:
	var w: Node = director.waves
	if w._alive() + w._to_spawn > 3: return []
	var out := []
	for z in w.ZombieScript.crowd:
		if is_instance_valid(z) and not z.dead: out.append(z.global_position)
	return out
