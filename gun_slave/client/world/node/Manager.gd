extends Node


export var HOST: String = "ws://localhost:8080/"
const is_multiplayer: bool = true
const is_multithread: bool = false
const INTERPOLATION_INTERVAL:float = 1.0 / 10; #ms

var entities: Dictionary = {}
var disconnected_ids: Array = []

var entity_obj = preload("res://common/scene/character.tscn");
onready var mutex = $NetManager.mutex
onready var receive_message_queue_mutex = $NetManager.receive_message_queue_mutex

func on_connected():
	self.set_physics_process(true)
	
func on_disconnected():
	if is_multithread:
		var _lg = $NetManager.LockGuard.new(mutex)
		
	if $character.entity_id:
		disconnected_ids.append($character.entity_id)
	self.set_physics_process(false)
	$NetManager.disconnect_from_host()
	$NetManager.connect_to_url(HOST)
	

# Called when the node enters the scene tree for the first time.
func _ready():
	#$character.set_animation(false)		
	#$character2.set_animation(false)
	if not is_multiplayer:
		$character.entity_id = 0
		return

	self.set_physics_process(false)
	
# warning-ignore:return_value_discarded
	$NetManager.connect("connected", self, "on_connected")
# warning-ignore:return_value_discarded
	$NetManager.connect("disconnected", self, "on_disconnected")
	$NetManager.connect_to_url(HOST)
	
	$NetManager.set_process(!is_multithread)
	$NetManager.set_multithread(is_multithread)
	
	if is_multithread:
		$NetManager.poll_start()
		
	
	
func remove_entity(entity_id):
	var entity = entities.get(entity_id)
	if entities.erase(entity_id):
		remove_child(entity)
	
func process_server_messages():
	if not is_multiplayer:
		return
	
	if is_multithread:
		receive_message_queue_mutex.lock()
	var message_queue_copy = $NetManager.receive_message_queue.duplicate()
	$NetManager.receive_message_queue.clear()
	if is_multithread:
		receive_message_queue_mutex.unlock()
	
	var processed_entities: Array = []
	
	for data in message_queue_copy:
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
					$character.apply_state(entity_state, 0)
				else:
					
					if disconnected_ids.has(entity_id):
						continue
						
					if entity_state.last_processed_input == -1:
						# disconnected
						remove_entity(entity_id)
						continue
						
					var timestamp = OS.get_ticks_msec()
					if not entities.has(entity_id):
						var entity = entity_obj.instance()
						entities[entity_id] = entity
						entities[entity_id].position = entity_state.position
						entity.entity_id = entity_id
						add_child(entity)
					
					entities[entity_id].apply_state(entity_state, timestamp)
					processed_entities.append(entity_id)
					entities[entity_id].no_input_counter = 0
					
	for entity_id in entities.duplicate():
		
		if not processed_entities.has(entity_id):
			entities[entity_id].no_input_counter += 1
			if entities[entity_id].no_input_counter > 100:
				remove_entity(entity_id)
				
	
	

func interpolate_entities():
	var render_time:float = OS.get_ticks_msec() - INTERPOLATION_INTERVAL
	for entity in entities.values():
		entity.interpolate(render_time)
	
	
func send_input_to_server(input: Types.EntityInput):
	if is_multithread:
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
	
	if is_multiplayer and input.trigger:
		pass
	
#	if not ($character.input_sequence_number % 1000):
#		print(len($character.pending_inputs))
#
	if is_multiplayer:
		send_input_to_server(input);
		
	apply_input(input)
		
func apply_input(input: Types.EntityInput):
	if not is_multiplayer and input.trigger:
		var entity_shot = $character.get_node("weapon").get_weapon_target()
		if entity_shot is character:
			$character.hit_enemy(entity_shot)
	$character.apply_input(input)
		
		
