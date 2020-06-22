extends Node

signal connected;
signal disconnected;

var receive_message_queue: Array = []


var _client = WebSocketClient.new()
var _write_mode = WebSocketPeer.WRITE_MODE_BINARY
var _use_multiplayer = true
var last_connected_client = 0

func _init():
	_client.verify_ssl = false
	_client.connect("connection_established", self, "_client_connected")
	_client.connect("connection_error", self, "_client_disconnected")
	_client.connect("connection_closed", self, "_client_disconnected")
	_client.connect("server_close_request", self, "_client_close_request")
	_client.connect("data_received", self, "_client_received")

	_client.connect("peer_packet", self, "_client_received")
	_client.connect("peer_connected", self, "_peer_connected")
	_client.connect("connection_succeeded", self, "_client_connected", ["multiplayer_protocol"])
	_client.connect("connection_failed", self, "_client_disconnected")


func _client_close_request(code, reason):
	Utils._log("Close code: %d, reason: %s" % [code, reason])

func _peer_connected(id):
	Utils._log("%s: Client just connected" % id)
	last_connected_client = id

func _exit_tree():
	_client.disconnect_from_host(1001, "Bye")

func _process(_delta):
	if _client.get_connection_status() == WebSocketClient.CONNECTION_DISCONNECTED:
		return

	_client.poll()

func _client_connected(protocol=""):
	_client.get_peer(1).set_write_mode(_write_mode)
	emit_signal("connected")

func _client_disconnected(clean=true):
	Utils._log("Client just disconnected. Was clean: %s" % clean)
	emit_signal("disconnected")


func _client_received(p_id = 1):
	var data = null;
	if _use_multiplayer:
		var peer_id = _client.get_packet_peer()
		var packet = _client.get_packet()
		data = Utils.decode_data(packet)
		#Utils._log("MPAPI: From %s Data: %s" % [str(peer_id), data])
	else:
		var packet = _client.get_peer(1).get_packet()
		data = Utils.decode_data(packet)
		#Utils._log("Received data. BINARY: %s" % [Utils.decode_data(packet)])
		
	receive_message_queue.push_back(data)	

func connect_to_url(host, protocols=null, multiplayer=true):
	if not protocols:
		protocols = PoolStringArray()
	_use_multiplayer = multiplayer
	if _use_multiplayer:
		_write_mode = WebSocketPeer.WRITE_MODE_BINARY
	return _client.connect_to_url(host, protocols, multiplayer)

func disconnect_from_host():
	_client.disconnect_from_host(1000, "Bye")

func send_data(data, dest=WebSocketClient.TARGET_PEER_SERVER):
	if _client.get_connection_status() == WebSocketClient.CONNECTION_DISCONNECTED:
		emit_signal("disconnected")
		return
	#_client.get_peer(1).set_write_mode(_write_mode)
	if _use_multiplayer:
		_client.set_target_peer(dest)
		_client.put_packet(Utils.encode_data(data))
	else:
		_client.get_peer(1).put_packet(Utils.encode_data(data))




