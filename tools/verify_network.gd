extends SceneTree
## Lokální ENet integrace přes oddělená MultiplayerAPI. --headless --script res://tools/verify_network.gd
const Net := preload("res://scripts/network_session.gd")
var failures := 0
var nodes: Array = []
var snapshots := {}
var actions := {}
var waters := {}

func _initialize() -> void:
	call_deferred("verify")

func _process(_dt: float) -> bool:
	for net in nodes:
		if net._peer: net.multiplayer.poll()
	return false

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok: failures += 1

func make_peer(index: int) -> Node:
	var branch := Node.new()
	branch.name = "Branch%d" % index
	root.add_child(branch)
	var api := SceneMultiplayer.new()
	api.root_path = branch.get_path()
	set_multiplayer(api, branch.get_path())
	var net := Net.new()
	branch.add_child(net)
	net.local_state = func(seq: int) -> Array: return [seq, Vector3(index, 0.5, 7), Vector3.ZERO, 0.0, 0.0, Net.FLAG_GROUNDED, 0.0, Time.get_ticks_msec()]
	snapshots[index] = 0
	actions[index] = []
	waters[index] = 0
	net.state_received.connect(func(_id: int, _state: Array): snapshots[index] += 1)
	net.action_received.connect(func(id: int, kind: String, data: Array): actions[index].append([id, kind, data]))
	net.water_received.connect(func(points: Array): waters[index] += points.size())
	nodes.append(net)
	return net

func verify() -> void:
	var host := make_peer(0)
	var client := make_peer(1)
	check(host.host_game("Host", 24680, false) == OK, "ENet host starts")
	check(client.join_game("Kamarád", "127.0.0.1", 24680) == OK, "ENet client begins connection")
	await create_timer(1.0).timeout
	check(host.names.size() == 2 and client.names.size() == 2 and client.active, "handshake registers both peers")
	check(snapshots[0] > 5 and snapshots[1] > 5, "snapshots flow bidirectionally")
	client.send_action("jump", [3.7, 11.5])
	host.send_action("turn", [PI/2])
	await create_timer(0.15).timeout
	check(actions[0].any(func(a: Array) -> bool: return a[1]=="jump") and actions[1].any(func(a: Array) -> bool: return a[1]=="turn"), "jump and turn actions flow both directions")
	client.queue_water(Vector2(1,7),0.25,-0.5)
	host.queue_water(Vector2(0,7),0.25,-0.5)
	await create_timer(0.2).timeout
	check(waters[0]==1 and waters[1]==1, "wave impulses arrive once without echo")
	host.pickup_requested.connect(func(id: int): host.collect_sample(id))
	client.request_pickup()
	await create_timer(0.15).timeout
	check(host.sample_owner == client.multiplayer.get_unique_id() and client.sample_owner==host.sample_owner, "server owns shared pickup result")
	var late := make_peer(2)
	late.join_game("Pozdější hráč", "127.0.0.1", 24680)
	await create_timer(0.7).timeout
	check(late.active and late.names.size()==3 and late.sample_owner==host.sample_owner and late.states.size()>=2, "late join receives roster, snapshots and collected prop")
	var fourth := make_peer(3)
	fourth.join_game("Čtvrtý hráč", "127.0.0.1", 24680)
	await create_timer(0.5).timeout
	check(fourth.active and host.names.size()==4 and late.names.size()==4, "four-player roster is supported")
	client.send_action("pickup", [0.0])
	client.send_action("land", [])
	await create_timer(0.15).timeout
	check(actions[0].any(func(a: Array) -> bool: return a[1]=="pickup") and actions[2].any(func(a: Array) -> bool: return a[1]=="pickup"), "server relays client action to another client")
	check(actions[0].any(func(a: Array) -> bool: return a[1]=="land"), "multiple action events in one frame are preserved")
	check(not Net.valid_state([1,Vector3(NAN,0,0),Vector3.ZERO,0.0,0.0,0,0.0,0]), "non-finite snapshots rejected")
	check(not Net.valid_action("jump",[NAN,11.5]) and not Net.valid_action("unknown",[]), "invalid action payloads rejected")
	client.leave()
	await create_timer(0.3).timeout
	check(host.names.size()==3 and late.names.size()==3, "disconnect removes peer from remaining rosters")
	check(client.join_game("Znovu", "127.0.0.1", 24680)==OK, "client can reconnect")
	await create_timer(0.5).timeout
	check(client.active and host.names.size()==4, "reconnect completes without stale peer state")
	host.leave()
	await create_timer(0.3).timeout
	check(not client.active and not late.active, "host shutdown closes client sessions")
	for net in nodes: net.leave()
	print("NETWORK REGRESSION FINISHED failures=", failures)
	quit(1 if failures else 0)
