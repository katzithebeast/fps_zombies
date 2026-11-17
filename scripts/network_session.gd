extends Node
## ENet listen server. Klient vlastní pohyb; server ověřuje a předává data ostatním.
## RPC přijímají jen primitivní Varianty, nikdy objekty nebo cesty ke zdrojům.
signal started(slot: int)
signal closed(message: String)
signal status_changed(message: String)
signal roster_changed
signal remote_joined(id: int, display_name: String)
signal remote_left(id: int)
signal state_received(id: int, state: Array)
signal action_received(id: int, kind: String, data: Array)
signal water_received(points: Array)
signal pickup_requested(id: int)
signal sample_changed(owner: int)

const PROTOCOL := "hladina-mp-zombie-3"
const DEFAULT_PORT := 24567
const MAX_PLAYERS := 4
const TICK := 1.0 / 20.0
const FLAG_CROUCH := 1
const FLAG_SWIM := 2
const FLAG_STRAFE := 4
const FLAG_ORBIT := 8
const FLAG_GROUNDED := 16
const FLAG_ARMED := 32
const FLAG_AIM := 64
var active := false
var connecting := false
var port := DEFAULT_PORT
var local_name := "Hráč"
var names := {}
var slots := {}
var states := {}
var sample_owner := 0
var status := ""
var external_address := ""
var mapping_status := ""
var _peer: ENetMultiplayerPeer
var _mapper: Node
var _timeout := 0.0
var _tick := 0.0
var _sequence := 0
var _own_id := 1
var _water_queue: Array = []
var _pending := {}
var _last_action := {}
var _last_water := {}
var _last_state := {}
var local_state: Callable

func _ready() -> void:
	name = "NetworkSession"
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func(): _fail("Připojení se nezdařilo. Zkontroluj adresu, UDP port a firewall."))
	multiplayer.server_disconnected.connect(func(): _fail("Host ukončil hru nebo se přerušilo spojení."))
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	_mapper = preload("res://scripts/port_mapper.gd").new()
	add_child(_mapper)
	_mapper.result.connect(_mapping_result)

func host_game(display_name: String, server_port: int, automatic_port: bool) -> Error:
	leave()
	port = clampi(server_port, 1024, 65535)
	local_name = clean_name(display_name)
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_server(port, MAX_PLAYERS - 1, 3)
	if error != OK:
		_peer = null
		_set_status("Server nejde spustit: port %d je obsazený nebo nedostupný." % port)
		return error
	multiplayer.multiplayer_peer = _peer
	active = true
	_own_id = 1
	names[1] = local_name
	slots[1] = 0
	_set_status("Hostuješ · 1/%d hráči · UDP %d" % [MAX_PLAYERS, port])
	started.emit(0)
	roster_changed.emit()
	if automatic_port:
		mapping_status = "Zkouším otevřít UDP port přes UPnP…"
		_mapper.start(port)
	return OK

func join_game(display_name: String, address: String, server_port: int) -> Error:
	leave()
	address = address.strip_edges()
	if address.is_empty() or address.length() > 253 or "/" in address or " " in address:
		_set_status("Zadej IP adresu nebo název počítače hostitele.")
		return ERR_INVALID_PARAMETER
	local_name = clean_name(display_name)
	port = clampi(server_port, 1024, 65535)
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_client(address, port, 3)
	if error != OK:
		_peer = null
		_set_status("Připojení nelze zahájit. Zkontroluj adresu a port.")
		return error
	multiplayer.multiplayer_peer = _peer
	connecting = true
	_timeout = 12.0
	_set_status("Připojuji se k %s · UDP %d…" % [address, port])
	return OK

func leave(message := "") -> void:
	var own := _own_id
	active = false
	connecting = false
	_mapper_stop()
	if _peer:
		_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_peer = null
	for id in names:
		if id != own:
			remote_left.emit(id)
	names.clear()
	slots.clear()
	states.clear()
	_pending.clear()
	_last_action.clear()
	_last_water.clear()
	_last_state.clear()
	_water_queue.clear()
	sample_owner = 0
	external_address = ""
	mapping_status = ""
	_tick = 0.0
	_sequence = 0
	status = message
	roster_changed.emit()

func _mapper_stop() -> void:
	if _mapper:
		_mapper.stop()

func _fail(message: String) -> void:
	leave(message)
	status_changed.emit(message)
	closed.emit(message)

func _set_status(message: String) -> void:
	status = message
	status_changed.emit(message)

static func clean_name(value: String) -> String:
	value = value.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges().left(24)
	return "Hráč" if value.is_empty() else value

func _connected() -> void:
	if connecting:
		_own_id = multiplayer.get_unique_id()
		_hello.rpc_id(1, PROTOCOL, local_name)

func _peer_connected(id: int) -> void:
	if active and multiplayer.is_server():
		_pending[id] = Time.get_ticks_msec()

func _peer_disconnected(id: int) -> void:
	_pending.erase(id)
	states.erase(id)
	slots.erase(id)
	_last_action.erase(id)
	_last_water.erase(id)
	_last_state.erase(id)
	if names.has(id):
		names.erase(id)
		remote_left.emit(id)
		roster_changed.emit()
		if active and multiplayer.is_server():
			_roster.rpc(names)

@rpc("any_peer", "call_remote", "reliable", 0)
func _hello(protocol: String, display_name: String) -> void:
	if not active or not multiplayer.is_server(): return
	var id := multiplayer.get_remote_sender_id()
	if not _pending.has(id) or names.has(id): return
	if protocol != PROTOCOL or names.size() >= MAX_PLAYERS:
		_reject.rpc_id(id, "Máte rozdílnou verzi hry nebo je server plný. Pošlete si stejný ZIP.")
		return
	_pending.erase(id)
	var slot := 0
	while slot in slots.values(): slot += 1
	names[id] = clean_name(display_name)
	slots[id] = slot
	_welcome.rpc_id(id, names, states, sample_owner, slot)
	_roster.rpc(names)
	remote_joined.emit(id, names[id])
	roster_changed.emit()

@rpc("authority", "call_remote", "reliable", 0)
func _reject(message: String) -> void:
	if connecting: _fail(message)

@rpc("authority", "call_remote", "reliable", 0)
func _welcome(roster: Dictionary, initial_states: Dictionary, owner: int, slot: int) -> void:
	if not connecting: return
	connecting = false
	active = true
	started.emit(slot)
	_apply_roster(roster)
	for id in initial_states:
		if id != multiplayer.get_unique_id() and names.has(id) and valid_state(initial_states[id]):
			states[id] = initial_states[id]
			state_received.emit(id, states[id])
	sample_owner = owner
	if owner != 0: sample_changed.emit(owner)
	_set_status("Připojeno · %d/%d hráči" % [names.size(), MAX_PLAYERS])

@rpc("authority", "call_remote", "reliable", 0)
func _roster(roster: Dictionary) -> void:
	if active: _apply_roster(roster)

func _apply_roster(roster: Dictionary) -> void:
	var own := multiplayer.get_unique_id()
	for id in names:
		if id != own and not roster.has(id): remote_left.emit(id)
	for id in roster:
		if id != own and not names.has(id): remote_joined.emit(id, clean_name(str(roster[id])))
	names = roster.duplicate()
	roster_changed.emit()

func _process(dt: float) -> void:
	if connecting:
		_timeout -= dt
		if _timeout <= 0.0: _fail("Server neodpovídá. Ověř IP, UDP port %d a firewall; přes internet může být potřeba přesměrování portu nebo VPN." % port)
	if not active: return
	if multiplayer.is_server():
		for id in _pending.keys():
			if Time.get_ticks_msec() - int(_pending[id]) > 10000:
				_peer.disconnect_peer(id)
				_pending.erase(id)
	_tick += dt
	if _tick < TICK: return
	_tick = fmod(_tick, TICK)
	if local_state.is_valid():
		_sequence += 1
		var state: Array = local_state.call(_sequence)
		if valid_state(state):
			var own := multiplayer.get_unique_id()
			states[own] = state
			if multiplayer.is_server(): _state.rpc(own, state)
			else: _submit_state.rpc_id(1, state)
	if not _water_queue.is_empty():
		var points := _water_queue.duplicate()
		_water_queue.clear()
		if multiplayer.is_server(): _water.rpc(1, points)
		else: _submit_water.rpc_id(1, points)

static func valid_state(s: Variant) -> bool:
	if not s is Array or s.size() != 8: return false
	if not s[0] is int or s[0] < 0 or not s[1] is Vector3 or not s[2] is Vector3: return false
	if not s[1].is_finite() or not s[2].is_finite() or s[1].length() > 150.0 or s[2].length() > 30.0: return false
	for index in [3, 4, 6]:
		if typeof(s[index]) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(s[index])) or absf(float(s[index])) > 100000.0: return false
	return s[5] is int and s[5] >= 0 and s[5] < 128 and s[7] is int

@rpc("any_peer", "call_remote", "unreliable", 1)
func _submit_state(state: Array) -> void:
	if not active or not multiplayer.is_server(): return
	var id := multiplayer.get_remote_sender_id()
	if not names.has(id) or not valid_state(state): return
	if states.has(id) and state[0] <= states[id][0]: return
	if not _allow(_last_state, id, 20): return
	states[id] = state
	state_received.emit(id, state)
	_state.rpc(id, state)

@rpc("authority", "call_remote", "unreliable", 1)
func _state(id: int, state: Array) -> void:
	if not active or id == multiplayer.get_unique_id() or not names.has(id) or not valid_state(state): return
	if states.has(id) and state[0] <= states[id][0]: return
	states[id] = state
	state_received.emit(id, state)

func send_action(kind: String, data: Array) -> void:
	if not active or not valid_action(kind, data): return
	if multiplayer.is_server(): _action.rpc(1, kind, data)
	else: _submit_action.rpc_id(1, kind, data)

static func valid_action(kind: String, data: Array) -> bool:
	if kind == "reload": return data.is_empty()
	if kind == "shot": return data.size()==2 and data[0] is Vector3 and data[1] is Vector3 and data[0].is_finite() and data[1].is_finite() and data[0].length()<150.0 and data[0].distance_to(data[1])<101.0
	if kind == "land": return data.is_empty()
	if kind == "jump": return data.size() == 2 and finite_number(data[0], 0.1, 8.0) and finite_number(data[1], 1.0, 20.0)
	if kind == "turn": return data.size() == 1 and finite_number(data[0], -100000.0, 100000.0)
	if kind == "pickup": return data.size() == 1 and finite_number(data[0], -100000.0, 100000.0)
	if kind == "step": return data.size() == 2 and data[0] in ["tile", "water", "swim"] and finite_number(data[1], 0.0, 2.0)
	if kind == "splash": return data.size() == 1 and finite_number(data[0], 0.0, 2.0)
	return false

static func finite_number(value: Variant, low: float, high: float) -> bool:
	return typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value)) and float(value) >= low and float(value) <= high

@rpc("any_peer", "call_remote", "reliable", 0)
func _submit_action(kind: String, data: Array) -> void:
	if not active or not multiplayer.is_server(): return
	var id := multiplayer.get_remote_sender_id()
	if not names.has(id) or not valid_action(kind, data) or not _allow_action(id): return
	action_received.emit(id, kind, data)
	_action.rpc(id, kind, data)

@rpc("authority", "call_remote", "reliable", 0)
func _action(id: int, kind: String, data: Array) -> void:
	if active and id != multiplayer.get_unique_id() and names.has(id) and valid_action(kind, data):
		action_received.emit(id, kind, data)

func queue_water(point: Vector2, radius: float, strength: float) -> void:
	if active and _water_queue.size() < 24:
		_water_queue.append(Vector4(point.x, point.y, radius, strength))

func _valid_water(points: Array, id: int) -> bool:
	if points.size() > 24 or not states.has(id): return false
	var position: Vector3 = states[id][1]
	for point in points:
		if not point is Vector4 or not point.is_finite(): return false
		if point.z < 0.02 or point.z > 1.0 or absf(point.w) > 2.0: return false
		if Vector2(point.x - position.x, point.y - position.z).length() > 3.0: return false
	return true

@rpc("any_peer", "call_remote", "unreliable", 2)
func _submit_water(points: Array) -> void:
	if not active or not multiplayer.is_server(): return
	var id := multiplayer.get_remote_sender_id()
	if not names.has(id) or not _valid_water(points, id) or not _allow(_last_water, id, 20): return
	water_received.emit(points)
	_water.rpc(id, points)

@rpc("authority", "call_remote", "unreliable", 2)
func _water(id: int, points: Array) -> void:
	if not active or id == multiplayer.get_unique_id() or points.size() > 24: return
	# Zprávy jsou pouze od serveru; konečná data přesto ověřit před GPU simulací.
	for point in points:
		if not point is Vector4 or not point.is_finite() or point.z <= 0.0 or point.z > 1.0 or absf(point.w) > 2.0: return
	water_received.emit(points)

func request_pickup() -> void:
	if not active: return
	if multiplayer.is_server(): pickup_requested.emit(1)
	else: _pickup_request.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable", 0)
func _pickup_request() -> void:
	var id := multiplayer.get_remote_sender_id()
	if active and multiplayer.is_server() and names.has(id): pickup_requested.emit(id)

func collect_sample(id: int) -> void:
	if not active or not multiplayer.is_server() or sample_owner != 0: return
	sample_owner = id
	sample_changed.emit(id)
	_sample.rpc(id)

@rpc("authority", "call_remote", "reliable", 0)
func _sample(owner: int) -> void:
	if active:
		sample_owner = owner
		sample_changed.emit(owner)

func _allow(times: Dictionary, id: int, interval_ms: int) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(times.get(id, -100000)) < interval_ms: return false
	times[id] = now
	return true

func _allow_action(id: int) -> bool:
	# Odraz/dopad/krok mohou přijít ve stejném snímku. Povolit krátké shluky,
	# ale omezit dlouhodobé zahlcení zprávami od jednoho klienta.
	var now := Time.get_ticks_msec()
	var bucket: Array = _last_action.get(id, [now, 0])
	if now - int(bucket[0]) >= 1000: bucket = [now, 0]
	if int(bucket[1]) >= 30: return false
	bucket[1] += 1
	_last_action[id] = bucket
	return true

func _mapping_result(address: String, message: String) -> void:
	if not active or not multiplayer.is_server(): return
	external_address = address
	mapping_status = message
	status_changed.emit(status)

func addresses() -> String:
	var values: Array[String] = []
	for address in IP.get_local_addresses():
		if ":" not in address and not address.begins_with("127.") and not address.begins_with("169.254."):
			values.append(address)
	return ", ".join(values)

func connection_text() -> String:
	if connecting: return status
	if not active: return status
	if multiplayer.is_server():
		var text := "Host · %d/%d hráči · UDP %d\nLAN / VPN: %s" % [names.size(), MAX_PLAYERS, port, addresses()]
		if not external_address.is_empty(): text += "\nAdresa routeru: " + external_address
		if not mapping_status.is_empty(): text += "\n" + mapping_status
		return text
	return "Připojeno · %d/%d hráči · UDP %d" % [names.size(), MAX_PLAYERS, port]

func _exit_tree() -> void:
	_mapper_stop()
	if _peer: _peer.close()
