extends Node


export var HOST: String = "ws://localhost:8080/"
const is_multiplayer: bool = true
const INTERPOLATION_INTERVAL:float = 1.0 / 10; #ms

var entities: Dictionary = {}
var disconnected_ids: Array = []

var entity_obj = preload("res://common/scene/character.tscn");
onready var mutex = $NetManager.mutex

func on_connected():
	self.set_physics_process(true)
	
func on_disconnected():
	var _lg = $NetManager.LockGuard.new(mutex)
	if $character.entity_id:
		disconnected_ids.append($character.entity_id)
	self.set_physics_process(false)
	$NetManager.disconnect_from_host()
	$NetManager.connect_to_url(HOST)

# Called when the node enters the scene tree for the first time.
func _ready():
	if not is_multiplayer:
		$character.entity_id = 0
		return
	
	self.set_physics_process(false)
	
# warning-ignore:return_value_discarded
	$NetManager.connect("connected", self, "on_connected")
# warning-ignore:return_value_discarded
	$NetManager.connect("disconnected", self, "on_disconnected")
	$NetManager.connect_to_url(HOST)
	$NetManager.poll_start()
	
func process_server_messages():
	if not is_multiplayer:
		return
	
	var _lg = $NetManager.LockGuard.new(mutex)
	
	for data in $NetManager.receive_message_queue:
		var obj = dict2inst(data)
		if obj.get("room") != null:
			$character.entity_id = obj.entity_id
			$character.position = obj.position
		else:
			var state: Types.WorldState = obj
			for entity_state_obj in state.entity_states:
				var entity_state = Types.deserialize_entity_state(entity_state_obj)
				var entity_id = entity_state.entity_id
				if entity_id == $character.entity_id:
					$character.position = entity_state.position
					if $character.pending_inputs.empty():
						continue
					var start_number = $character.pending_inputs[0].input_sequence_number
					var from = entity_state.last_processed_input - start_number
					$character.pending_inputs = $character.pending_inputs.slice(from, $character.pending_inputs.size()-1)
					# print("applying ", len($character.pending_inputs), " pending inputs")
					for input in $character.pending_inputs:
						$character.apply_input(input)
				else:
					
					if disconnected_ids.has(entity_id):
						continue
						
					var timestamp = OS.get_ticks_msec()
					if not entities.has(entity_id):
						var entity = entity_obj.instance()
						entities[entity_id] = entity
						entities[entity_id].position = entity_state.position
						entity.entity_id = entity_id
						add_child(entity)
					
					entities[entity_id].input_sequence_number = entity_state.last_processed_input
					entities[entity_id].look_at(entity_state.look_at)
					
					entities[entity_id].client_state_buffer.append(
						[timestamp, entity_state.last_processed_input, entity_state.position]
					)
	$NetManager.receive_message_queue.clear()
	
	

func interpolate_entities():
	var render_time:float = OS.get_ticks_msec() - INTERPOLATION_INTERVAL
	for entity in entities.values():
		entity.interpolate(render_time)
	
	
func send_input_to_server(input: Types.EntityInput):
	var _lg = $NetManager.LockGuard.new(mutex)
	var obj = Types.serialize_entity_input(input)
	$NetManager.send_data(obj)
	
	
func _physics_process(delta):
	
	process_server_messages()
	
	if is_multiplayer and $character.entity_id == null:
#		# not connected yet
		return	
		
	if is_multiplayer:		
		interpolate_entities()
		
	var input: Types.EntityInput = $character.process_inputs(delta);
	
#	if not ($character.input_sequence_number % 1000):
#		print(len($character.pending_inputs))
#
	if is_multiplayer:
		send_input_to_server(input);
		
	$character.apply_input(input)
		
		
		
