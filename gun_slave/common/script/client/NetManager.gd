extends Node

signal disconnected;
var is_multithread: bool = true



var _client = WebSocketClient.new()
var _use_multiplayer = true
var to_exit: bool = false

var LockGuard = Utils.LockGuard
		
var mutex = Mutex.new()

func set_multithread(enable: bool):
	self.is_multithread = enable


func _init():
	_client.verify_ssl = false
#	_client.connect("connection_established", self, "_client_connected")
#	_client.connect("connection_error", self, "_client_disconnected")
#	_client.connect("connection_closed", self, "_client_disconnected")
#	_client.connect("server_close_request", self, "_client_close_request")
	#_client.connect("data_received", self, "_client_received")

	#_client.connect("peer_packet", self, "_client_received")
	#_client.connect("peer_connected", self, "_peer_connected")
	#_client.connect("connection_succeeded", self, "_client_connected", ["multiplayer_protocol"])
	_client.connect("connection_failed", self, "_client_disconnected")

	
func get_network_unique_id():
	var _lg = LockGuard.new(mutex)
	if _client.get_connection_status() != WebSocketClient.CONNECTION_CONNECTED:
		return 0
	return _client.get_unique_id()


func _client_close_request(code, reason):
	Utils._log("Close code: %d, reason: %s" % [code, reason])

func _exit_tree():
	to_exit = true
	disconnect_from_host()

func _process(_delta):
	if _client.get_connection_status() == WebSocketClient.CONNECTION_DISCONNECTED:
		return

	_client.poll()
	
func poll2():
	if _client.get_connection_status() == WebSocketClient.CONNECTION_DISCONNECTED:
		return

	mutex.lock()
	_client.poll()
	mutex.unlock()

func poll(_delta):
	if not is_multithread:
		return
		
	while true:
		if to_exit:
			break
		if _client.get_connection_status() == WebSocketClient.CONNECTION_DISCONNECTED:
			continue
		mutex.lock()
		_client.poll()
		mutex.unlock()

func _client_disconnected(clean=true):
	Utils._log("Client just disconnected. Was clean: %s" % clean)
	emit_signal("disconnected")


func get_packet()->PoolByteArray:
	var _lg = Utils.LockGuard.new(mutex)
	return _client.get_packet()

func connect_to_url(host, protocols=null, multiplayer=true):
	if is_multithread:
		var _lg = LockGuard.new(mutex)
		
	if not protocols:
		protocols = PoolStringArray()
	_use_multiplayer = multiplayer
	
	if get_network_unique_id():
		assert(false)
		
	return _client.connect_to_url(host, protocols, multiplayer)

func disconnect_from_host():
	if is_multithread:
		var _lg = LockGuard.new(mutex)
		
	_client.disconnect_from_host(1000, "Bye")

func send_data(data, dest=WebSocketClient.TARGET_PEER_SERVER):
	if is_multithread:
		var _lg = LockGuard.new(mutex)
		
	if _client.get_connection_status() == WebSocketClient.CONNECTION_DISCONNECTED:
		emit_signal("disconnected")
		return
		
	_client.set_target_peer(dest)
	_client.put_packet(Utils.encode_data(data))




