extends Node
## Data hlavní mapy, která nejsou vidět jako uzly: voda (obdélníky hladin a jejich výšky), světlíky
## (měsíční světlo a prach), podlahy s dlaždicemi (barva stop) a pevné kvádry (maska vln u zdí).
## Když v editoru posuneš bazén nebo světlík, uprav tady i jeho obdélník (x, z, šířka, hloubka).
@export var water_rects: Array[Rect2] = []
@export var water_groups: PackedInt32Array = []        ## > 0 = samostatná hladina (vypouštění bazénu)
@export var water_zones: Array[Dictionary] = []         ## {rect: Rect2, level: výška hladiny}
@export var skylights: Array[Dictionary] = []           ## {rect, top, bottom, floor}
@export var floor_tiles: Array = []                     ## [Rect2, barva, měřítko dlaždic]
@export var solids: Array[AABB] = []
