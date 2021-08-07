extends Node

onready var _log_dest = get_parent().get_node("Panel/VBoxContainer/RichTextLabel")

var _client = WebSocketClient.new()

const GameProto = preload("res://game_proto.gd")

func _log(node, msg):
	print(msg)
	node.add_text(str(msg) + "\n")

func _init():
	_client.verify_ssl = false
	_client.connect("connection_established", self, "_client_connected")
	_client.connect("connection_error", self, "_client_disconnected")
	_client.connect("connection_closed", self, "_client_disconnected")
	_client.connect("server_close_request", self, "_client_close_request")
	_client.connect("data_received", self, "_client_received")

	_client.connect("peer_packet", self, "_client_received")
	_client.connect("peer_connected", self, "_peer_connected")
	_client.connect("connection_succeeded", self, "_client_connected")
	_client.connect("connection_failed", self, "_client_disconnected")

func _client_close_request(code, reason):
	_log(_log_dest, "Close code: %d, reason: %s" % [code, reason])

func _peer_connected(id):
	_log(_log_dest, "%s: Client just connected" % id)

func _exit_tree():
	_client.disconnect_from_host()

func _process(delta):
	if _client.get_connection_status() == WebSocketClient.CONNECTION_DISCONNECTED:
		return

	_client.poll()

func _client_connected(protocol=""):
	_log(_log_dest, "Client just connected with protocol: %s" % protocol)
	_client.get_peer(1).set_write_mode(WebSocketPeer.WRITE_MODE_BINARY)

func _client_disconnected(clean=true):
	_log(_log_dest, "Client just disconnected. Was clean: %s" % clean)

func _client_received(p_id = 1):
	for _i in range(_client.get_peer(1).get_available_packet_count()):
		var data = _client.get_peer(1).get_packet()
		# print("package: ", data.hex_encode())
		var msg: GameProto.Message = GameProto.Message.new()
		var state = msg.from_bytes(data)
		
		if state < 0:
			_log(_log_dest, "Cannot parse message from bytes")
			return
			
		handle_message(msg)
	
func handle_message(msg: GameProto.Message):
	if msg.has_client_message():
		var message = msg.get_client_message()
		_log(_log_dest, "[%s]:> %s" % [message.get_username(), message.get_text()])
	elif msg.has_server_message():
		var message = msg.get_server_message()
		_log(_log_dest, "[server]: code: %s, message: %s" % [message.get_code(), message.get_reason()])


func connect_to_url(host):
	return _client.connect_to_url(host)

func disconnect_from_host():
	#_client.disconnect_from_host(1000, "Bye bye!")
	_client.disconnect_from_host()

func send_data(data):
	_client.get_peer(1).put_packet(data.to_bytes())
