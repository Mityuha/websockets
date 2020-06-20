extends Node

signal connected;
signal disconnected;

var receive_message_queue: Array = []


func is_bit_enabled(mask, index):
	return mask & (1 << index) != 0

func enable_bit(mask, index):
	return mask | (1 << index)

func disable_bit(mask, index):
	return mask & ~(1 << index)
	
func enable_bit_or_do_nothing(mask, index, enable):
	if enable:
		return enable_bit(mask, index)
	return mask
		
func int_from_bytes(byte1:int, byte0:int)->int:
	var res = byte1 << 8 | byte0 ;
	return res
	
func int_from_bytes2_array(bytes:Array)->int:
	return int_from_bytes(bytes[0], bytes[1])
	
func int_2_bytes(num:int, bytes_num=4)->PoolByteArray:
	var res:PoolByteArray = PoolByteArray();
	for i in range(0, bytes_num):
		res.append((num >> (8*i)) & 0xff)
	return res
	
func bytes_2_int(bytes: PoolByteArray, bytes_num=4)->int:
	var res:int = 0
	for i in range(0, bytes_num):
		res |= bytes[i] << (8 * i);
	return res



var _client = WebSocketClient.new()
#var _write_mode = WebSocketPeer.WRITE_MODE_TEXT
var _write_mode = WebSocketPeer.WRITE_MODE_BINARY

func encode_data(data):
	return var2bytes(data)

func decode_data(data, is_string):
	return data.get_string_from_utf8() if is_string else bytes2var(data)

func _log(msg):
	print(msg)

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
	_log("Close code: %d, reason: %s" % [code, reason])

func _peer_connected(id):
	_log("%s: Client just connected" % id)

func _exit_tree():
	_client.disconnect_from_host()

func _process(_delta):
	if _client.get_connection_status() == WebSocketClient.CONNECTION_DISCONNECTED:
		return

	_client.poll()

func _client_connected(protocol=""):
	_client.get_peer(1).set_write_mode(_write_mode)
	emit_signal("connected")

func _client_disconnected(clean=true):
	_log("Client just disconnected. Was clean: %s" % clean)
	emit_signal("disconnected")

func _client_received():
	var packet = _client.get_peer(1).get_packet()
	var is_string = _client.get_peer(1).was_string_packet()
	# _log("Received data. BINARY: %s: %s" % [not is_string, decode_data(packet, is_string)])
	receive_message_queue.push_back(packet)

func connect_to_url(host):
	return _client.connect_to_url(host)

func disconnect_from_host():
	#_client.disconnect_from_host(1000, "Bye bye!")
	_client.disconnect_from_host()

func send_data(data):
	if(_client.get_connection_status() == 0):
		emit_signal("disconnected")
		return
	_client.get_peer(1).put_packet(data)
