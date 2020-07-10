extends Node

var _server = WebSocketServer.new()

var _is_multithread = true

var receive_message_queue: Array = []

# To test maybe
# var broadcast_queue: Array = []

var poll_thread: Thread

var mutex = Mutex.new()
var message_queue_mutex = Mutex.new()

var LockGuard = Utils.LockGuard


func _init():
	_server.connect("client_connected", self, "_client_connected")
	_server.connect("client_disconnected", self, "_client_disconnected")
	_server.connect("client_close_request", self, "_client_close_request")

	_server.connect("peer_packet", self, "_client_receive")
	
	poll_thread = Thread.new()
	
	
func start_poll():
# warning-ignore:return_value_discarded
	poll_thread.start(self, "poll_in_thread")
	
func set_multithread(enable: bool):
	_is_multithread = enable

func _exit_tree():
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
	
func _disconnect_client(id, code=1000, reason="timeout"):
	if _is_multithread:
		var _lg = LockGuard.new(mutex)
		
	return _server.disconnect_peer(id, code, reason)

func _client_receive(_peer_source):
	if _is_multithread:
		var _lg = LockGuard.new(mutex)
		
	var packet = _server.get_packet()
	var data = Utils.decode_data(packet)

	message_queue_mutex.lock()		
	receive_message_queue.append(data)
	message_queue_mutex.unlock()		

func send_data(data, dest):
	if _is_multithread:
		var _lg = LockGuard.new(mutex)
		
	_server.set_target_peer(dest)
	_server.put_packet(Utils.encode_data(data))
			
func broadcast_data(data):
	return send_data(data, WebSocketServer.TARGET_PEER_BROADCAST)

func listen(port, supported_protocols=null, multiplayer=true):
	if _is_multithread:
		var _lg = LockGuard.new(mutex)
		
	if not supported_protocols:
		supported_protocols = PoolStringArray()

	return _server.listen(port, supported_protocols, multiplayer)

func stop():
	if _is_multithread:
		var _lg = LockGuard.new(mutex)
	_server.stop()
