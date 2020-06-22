extends Node

var _server = WebSocketServer.new()
var _clients = {}
var _write_mode = WebSocketPeer.WRITE_MODE_BINARY
var _use_multiplayer = true
var last_connected_client = 0

var connected_clients_queue: Array = []
var disconnected_clients_queue: Array = []
var receive_message_queue: Array = []



func _init():
	_server.connect("client_connected", self, "_client_connected")
	_server.connect("client_disconnected", self, "_client_disconnected")
	_server.connect("client_close_request", self, "_client_close_request")
	_server.connect("data_received", self, "_client_receive")

	_server.connect("peer_packet", self, "_client_receive")
	_server.connect("peer_connected", self, "_client_connected", ["multiplayer_protocol"])
	_server.connect("peer_disconnected", self, "_client_disconnected")

func _exit_tree():
	_clients.clear()
	_server.stop()
		
func poll(_delta):
	if _server.is_listening():
		_server.poll()
		
func _client_close_request(id, code, reason):
	Utils._log("Client %s close code: %d, reason: %s" % [id, code, reason])

func _client_connected(id, protocol):
	_clients[id] = _server.get_peer(id)
	_clients[id].set_write_mode(_write_mode)
	last_connected_client = id
	Utils._log("%s: Client connected with protocol %s" % [id, protocol])
	connected_clients_queue.append(id)
	return

func _client_disconnected(id, clean = true):
	Utils._log("Client %s disconnected. Was clean: %s" % [id, clean])
	if _clients.has(id):
		_clients.erase(id)
	disconnected_clients_queue.append(id)

func _client_receive(id):
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
	receive_message_queue.append(data)

func send_data(data, dest):
	if _use_multiplayer:
		_server.set_target_peer(dest)
		_server.put_packet(Utils.encode_data(data))
	else:
		for id in _clients:
			_server.get_peer(id).put_packet(Utils.encode_data(data))
			
func broadcast_data(data):
	return send_data(data, WebSocketServer.TARGET_PEER_BROADCAST)

func listen(port, supported_protocols=null, multiplayer=true):
	if not supported_protocols:
		supported_protocols = PoolStringArray()
	_use_multiplayer = multiplayer
	if _use_multiplayer:
		set_write_mode(WebSocketPeer.WRITE_MODE_BINARY)
	return _server.listen(port, supported_protocols, multiplayer)

func stop():
	_server.stop()

func set_write_mode(mode):
	_write_mode = mode
	for c in _clients:
		_clients[c].set_write_mode(_write_mode)
