extends Node

onready var _log_dest = get_parent().get_node("Panel/VBoxContainer/RichTextLabel")

var _client = WebSocketClient.new()
var _write_mode = WebSocketPeer.WRITE_MODE_TEXT

func encode_data(data, mode):
	return JSON.print(data).to_utf8() if mode == WebSocketPeer.WRITE_MODE_TEXT else var2bytes(data)

func decode_data(data, is_string):
	return data.get_string_from_utf8() if is_string else bytes2var(data)

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
	_client.get_peer(1).set_write_mode(_write_mode)

func _client_disconnected(clean=true):
	_log(_log_dest, "Client just disconnected. Was clean: %s" % clean)

func _client_received(p_id = 1):
	var packet = _client.get_peer(1).get_packet()
	var is_string = _client.get_peer(1).was_string_packet()
	_log(_log_dest, "Received data. BINARY: %s: %s" % [not is_string, decode_data(packet, is_string)])

func connect_to_url(host):
	return _client.connect_to_url(host)

func disconnect_from_host():
	#_client.disconnect_from_host(1000, "Bye bye!")
	_client.disconnect_from_host()

func send_data(data):
	_client.get_peer(1).put_packet(encode_data(data, _write_mode))
