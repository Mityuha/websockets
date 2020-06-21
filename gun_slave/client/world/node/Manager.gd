extends Node


export var HOST: String = "ws://localhost:8080/"
const is_multiplayer: bool = true

var entities: Dictionary = {}
var state_buffer: Array = [] # for other client entities

func on_connected():
	self.set_physics_process(true)
	
func on_disconnected():
	self.set_physics_process(false)
	$NetManager.disconnect_from_host()
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
		var obj = dict2inst(data)
		if obj.get("room") != null:
			$character.entity_id = obj.entity_id
			$character.position = obj.position
		else:
			var state: Types.WorldState = obj
			var entity_state: Types.EntityState
			for entity_state in state.entities_state:
				var entity_id = entity_state.entity_id
				if entity_id == $character.entity_id:
					var last_processed_input = entity_state.last_processed_input
					$character.position = entity_state.position
					var start_number = $character.pending_inputs[0].input_sequence_number
					var from = last_processed_input - start_number
					$character.pending_inputs = $character.pending_inputs.slice(from, $character.pending_inputs.size()-1)
					print("applying ", len($character.pending_inputs), " pending inputs")
					for input in $character.pending_inputs:
						$character.apply_input(input)
			
				else:
					# TODO create entity
					# set its position
					# set state for interpolation (step 2, not implemented yet)
					continue
	$NetManager.receive_message_queue.clear()
			
	

func interpolate_entities():
	pass
	
func send_input_to_server(input: Types.EntityInput):
	var obj = Types.serialize_entity_input(input)
	$NetManager.send_data(obj)
	
	
func _physics_process(delta):
	
	process_server_messages()
	
	if is_multiplayer and $character.entity_id == null:
#		# not connected yet
		return	
		
	var input: Types.EntityInput = $character.process_inputs(delta);
	if not ($character.input_sequence_number % 1000):
		print(len($character.pending_inputs))
		
	if is_multiplayer:
		send_input_to_server(input);
		
	$character.apply_input(input)

	if is_multiplayer:		
		interpolate_entities()
		
		
		
