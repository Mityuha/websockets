extends Node


export var HOST: String = "ws://127.0.0.1:8080/ws"
const is_multiplayer: bool = true

func on_connected():
	self.set_physics_process(true)
	
func on_disconnected():
	self.set_physics_process(false)
	$NetManager.connect_to_url(HOST)

# Called when the node enters the scene tree for the first time.
func _ready():
	if not is_multiplayer:
		return
	self.set_physics_process(false)
# warning-ignore:return_value_discarded
	$NetManager.connect("connected", self, "on_connected")
# warning-ignore:return_value_discarded
	$NetManager.connect("disconnected", self, "on_disconnected")
	$NetManager.connect_to_url(HOST)
	
func process_server_messages():
	if not is_multiplayer:
		return
	
	for data in $NetManager.receive_message_queue:
		if data[0] == 0:
			# initial packet
			$character.entity_id = data[1]
			$character.position.x = $NetManager.bytes_2_int(data.subarray(2, 5))
			$character.position.y = $NetManager.bytes_2_int(data.subarray(6, 9))
			print("here", $character.position)
		elif data[0] == 1:
			# state
			assert(data[1] == $character.entity_id)
			var last_processed_input = $NetManager.bytes_2_int(data.subarray(2, 5))
			$character.position.x = $NetManager.bytes_2_int(data.subarray(6, 9))
			$character.position.y = $NetManager.bytes_2_int(data.subarray(10, 13))
			print("position received ", $character.position, " last processed input", last_processed_input)
			var start_number = $character.pending_inputs[0]._input_sequence_number
			var from = last_processed_input - start_number
			$character.pending_inputs = $character.pending_inputs.slice(from, $character.pending_inputs.size()-1)
			print("applying ", len($character.pending_inputs), " pending inputs")
			for input in $character.pending_inputs:
				$character.apply_input(input)
			print("position calculated ", $character.position)
	$NetManager.receive_message_queue.clear()
			
	

func interpolate_entities():
	pass
	
func send_input_to_server(input):
	var bytes = encode_input(input)
	$NetManager.send_data(bytes)
	
func encode_input(input):
	var res: PoolByteArray = PoolByteArray()
	res.append_array($NetManager.int_2_bytes(input._input_sequence_number))
	res.append(input._entity_id)
	var key_mask: int = 0
	key_mask = $NetManager.enable_bit_or_do_nothing(key_mask, 4, input._trigger)
	key_mask = $NetManager.enable_bit_or_do_nothing(key_mask, 3, input._right)
	key_mask = $NetManager.enable_bit_or_do_nothing(key_mask, 2, input._up)
	key_mask = $NetManager.enable_bit_or_do_nothing(key_mask, 1, input._left)
	key_mask = $NetManager.enable_bit_or_do_nothing(key_mask, 0, input._down)
	res.append(key_mask)
	res.append_array(var2bytes(input._look_at))
	return res
	


func _physics_process(delta):
	
	process_server_messages()
	
	if $character.entity_id == null:
		# not connected yet
		return	
		
	var input = $character.process_inputs(delta);
	if not ($character.input_sequence_number % 1000):
		print(len($character.pending_inputs))
		
	if is_multiplayer:
		send_input_to_server(input);
		
	$character.apply_input(input)

	if is_multiplayer:		
		interpolate_entities()
		
		
		
