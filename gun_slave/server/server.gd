extends Node

var _server = WebSocketServer.new()
var _clients = {}
var _write_mode = WebSocketPeer.WRITE_MODE_BINARY
var _use_multiplayer = true
var _is_multithread = true
var last_connected_client = 0

var connected_clients_queue: Array = []
var disconnected_clients_queue: Array = []
var receive_message_queue: Array = []

var poll_thread: Thread

var mutex = Mutex.new()
var message_queue_mutex = Mutex.new()
var connected_clients_mutex = Mutex.new()
var disconnected_clients_mutex = Mutex.new()

var LockGuard = Utils.LockGuard


func _init():
	_server.connect("client_connected", self, "_client_connected")
	_server.connect("client_disconnected", self, "_client_disconnected")
	_server.connect("client_close_request", self, "_client_close_request")
	_server.connect("data_received", self, "_client_receive")

	_server.connect("peer_packet", self, "_client_receive")
	_server.connect("peer_connected", self, "_client_connected", ["multiplayer_protocol"])
	_server.connect("peer_disconnected", self, "_client_disconnected")
	
	poll_thread = Thread.new()
	
	
func start_poll():
	poll_thread.start(self, "poll_in_thread")
	
func set_multithread(enable: bool):
	_is_multithread = enable

func _exit_tree():
	_clients.clear()
	_server.stop()
	poll_thread.wait_to_finish()
		
func poll_in_thread(_delta):
	while true:
		if not _server.is_listening():
			break
		mutex.lock()
		_server.poll()
		mutex.unlock()
		
func poll(_delta):
	if _server.is_listening():
		_server.poll()
		
func _client_close_request(id, code, reason):
	Utils._log("Client %s close code: %d, reason: %s" % [id, code, reason])

func _client_connected(id, protocol):
	if _is_multithread:
		var _lg = LockGuard.new(mutex)
		
	_clients[id] = _server.get_peer(id)
	_clients[id].set_write_mode(_write_mode)
	last_connected_client = id
	Utils._log("%s: Client connected with protocol %s" % [id, protocol])
	
	if _is_multithread:
		var _lg2 = LockGuard.new(connected_clients_mutex)
		
	connected_clients_queue.append(id)
	return

func _client_disconnected(id, clean = true):
	Utils._log("Client %s disconnected. Was clean: %s" % [id, clean])
	if _clients.has(id):
		_clients.erase(id)
		
	if _is_multithread:
		var _lg2 = LockGuard.new(disconnected_clients_mutex)
	disconnected_clients_queue.append(id)
	
func _disconnect_client(id, code=1000, reason="timeout"):
	if _is_multithread:
		var _lg = LockGuard.new(mutex)
		
	return _server.disconnect_peer(id, code, reason)

func _client_receive(id):
	if _is_multithread:
		var _lg = LockGuard.new(mutex)
		
	var data = null
	if _use_multiplayer:
		var peer_id = _server.get_packet_peer()
		var packet = _server.get_packet()
		data = Utils.decode_data(packet)
		#Utils._log("MPAPI: From %s data: %s" % [peer_id, data])
	else:
		var packet = _server.get_peer(id).get_packet()
		data = Utils.decode_data(packet)
		#Utils._log("Data from %s BINARY: %s" % [id, data])

	message_queue_mutex.lock()		
	receive_message_queue.append(data)
	message_queue_mutex.unlock()		

func send_data(data, dest):
	if _is_multithread:
		var _lg = LockGuard.new(mutex)
		
	if _use_multiplayer:
		_server.set_target_peer(dest)
		_server.put_packet(Utils.encode_data(data))
	else:
		for id in _clients:
			_server.get_peer(id).put_packet(Utils.encode_data(data))
			
func broadcast_data(data):
	return send_data(data, WebSocketServer.TARGET_PEER_BROADCAST)

func listen(port, supported_protocols=null, multiplayer=true):
	if _is_multithread:
		var _lg = LockGuard.new(mutex)
		
	if not supported_protocols:
		supported_protocols = PoolStringArray()
	_use_multiplayer = multiplayer
	if _use_multiplayer:
		set_write_mode(WebSocketPeer.WRITE_MODE_BINARY)
	return _server.listen(port, supported_protocols, multiplayer)

func stop():
	if _is_multithread:
		var _lg = LockGuard.new(mutex)
	_server.stop()

func set_write_mode(mode):
	_write_mode = mode
	for c in _clients:
		_clients[c].set_write_mode(_write_mode)
