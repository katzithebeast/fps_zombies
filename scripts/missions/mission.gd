extends Node
## Základ mise. Mise nezávisí na archetypu mapy: věci rozmisťuje přes rozhraní mapy
## (main.mission_points(), main.mission_theme(), main.extraction_point(), main.ground())
## a o interakce, nošení, vysílačku a odlet se stará režisér (mission_director.gd).

var director: Node
var main: Node3D
var title := ""
var brief := ""
var finished := false
var waves_mode := "ambient"      # ambient = pár zombie pořád kolem | rounds = vlny | off
var ambient_cap := 6
var max_rounds := 0
var wants_alpha := false
var tracker_hint := true          # zaměřovač vede k cílům mise

## Rozmístí věci do mapy. Volá se ještě v _ready mapy, před pečením navigace (kolize se započítají).
func place() -> void:
	pass

## Začátek mise (navigace je hotová, zombie můžou chodit).
func start() -> void:
	pass

func tick(_dt: float) -> void:
	pass

## Řádky úkolu do HUD.
func lines() -> Array:
	return []

## Body pro zaměřovač (pípá rychleji, čím blíž je nejbližší).
func targets() -> Array:
	return []

func complete() -> void:
	if finished: return
	finished = true
	director.mission_complete()
