extends Node
## Blokující UPnP běží mimo herní vlákno; mapování po odchodu zase odstraníme.
signal result(address: String, message: String)
var _thread: Thread
var _stop := Semaphore.new()
var _generation := 0

func start(port: int) -> void:
	stop()
	_generation += 1
	_thread = Thread.new()
	_thread.start(_work.bind(port, _generation))

func stop() -> void:
	_generation += 1
	if _thread:
		_stop.post()
		_thread.wait_to_finish()
		_thread = null

func _work(port: int, generation: int) -> void:
	var upnp := UPNP.new()
	var mapped := false
	var address := ""
	var message := "UPnP není dostupné. Použij LAN/VPN adresu nebo přesměruj UDP port ručně."
	if upnp.discover(1800, 2) == UPNP.UPNP_RESULT_SUCCESS:
		var gateway := upnp.get_gateway()
		if gateway and gateway.is_valid_gateway():
			address = upnp.query_external_address()
			mapped = upnp.add_port_mapping(port, port, "Hladina multiplayer", "UDP", 3600) == UPNP.UPNP_RESULT_SUCCESS
			if mapped:
				message = "UPnP: UDP port otevřen. Připojení z internetu závisí také na poskytovateli."
	_report.call_deferred(generation, address, message)
	if mapped:
		# Obnovit hodinový pronájem i při delší společné hře.
		var renew_at := Time.get_ticks_msec() + 1800000
		while not _stop.try_wait():
			if Time.get_ticks_msec() >= renew_at:
				var renewed := upnp.add_port_mapping(port, port, "Hladina multiplayer", "UDP", 3600) == UPNP.UPNP_RESULT_SUCCESS
				renew_at = Time.get_ticks_msec() + (1800000 if renewed else 60000)
				if not renewed:
					_report.call_deferred(generation, address, "UPnP se nepodařilo obnovit. Ověř router nebo použij ruční UDP přesměrování / VPN.")
			OS.delay_msec(100)
		upnp.delete_port_mapping(port, "UDP")
	else:
		_stop.wait()

func _report(generation: int, address: String, message: String) -> void:
	if generation == _generation:
		result.emit(address, message)

func _exit_tree() -> void:
	stop()
