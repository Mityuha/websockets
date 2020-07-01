extends Node


export var HOST: String = "ws://localhost:8080/"
const is_multiplayer: bool = true
const is_multithread: bool = true
const is_thread_interpolation: bool = false
const INTERPOLATION_INTERVAL:float = 1.0 / 10; #ms

var entities: Dictionary = {}
var disconnected_ids: Array = []

var entity_obj = preload("res://common/scene/character.tscn");
onready var mutex = $NetManager.mutex
onready var receive_message_queue_mutex = $NetManager.receive_message_queue_mutex

var interpolation_thread: Thread;
var is_interpolation_thread_stopped: bool = false

func on_connected():
	self.set_physics_process(true)
	
	if is_thread_interpolation:
		is_interpolation_thread_stopped = false
# warning-ignore:return_value_discarded
		if interpolation_thread.is_active():
			interpolation_thread.wait_to_finish()
		interpolation_thread.start(self, "interpolate_entities_in_thread")
	
func on_disconnected():
	if is_multithread:
		var _lg = $NetManager.LockGuard.new(mutex)
		
	if $character.entity_id:
		disconnected_ids.append($character.entity_id)
		$character.input_sequence_number = 0
		
	self.set_physics_process(false)
	$NetManager.disconnect_from_host()
	$NetManager.connect_to_url(HOST)
	
	if is_thread_interpolation:
		is_interpolation_thread_stopped = true
		
func _exit_tree():
	if is_thread_interpolation:
		is_interpolation_thread_stopped = true
		interpolation_thread.wait_to_finish()
	

# Called when the node enters the scene tree for the first time.
func _ready():
	#$character.set_animation(false)		
	#$character2.set_animation(false)
	
	if not is_multiplayer:
		$character.entity_id = 0
		return
		
	if is_thread_interpolation:
		interpolation_thread = Thread.new()

	self.set_physics_process(false)
	
# warning-ignore:return_value_discarded
	$NetManager.connect("connected", self, "on_connected")
# warning-ignore:return_value_discarded
	$NetManager.connect("disconnected", self, "on_disconnected")
	
	$NetManager.set_process(!is_multithread)
	$NetManager.set_multithread(is_multithread)
	
	$NetManager.connect_to_url(HOST)
	
	if is_multithread:
		$NetManager.poll_start()
		
	$character.set_thread_interpolation(is_thread_interpolation)
		
	
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
	
	for time_data_list in message_queue_copy:
		var message_time = time_data_list[0]
		var data = time_data_list[1]
		
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
					$character.apply_health(entity_state.health)
				else:
					
					if disconnected_ids.has(entity_id):
						continue
						
					if entity_state.last_processed_input == -1:
						# disconnected
						remove_entity(entity_id)
						continue
					
					var entity: character = entities.get(entity_id)
					
					if not entity:
						entity = entity_obj.instance()
						entity.position = entity_state.position
						entity.entity_id = entity_id
						entities[entity_id] = entity
						add_child(entity)
					
					entity.apply_entity_state(entity_state, message_time)
					processed_entities.append(entity_id)
					entity.no_input_counter = 0
					
	# TODO: more elegant
#	for entity_id in entities.duplicate():
#
#		if not processed_entities.has(entity_id):
#			entities[entity_id].no_input_counter += 1
#			if entities[entity_id].no_input_counter > 100:
#				remove_entity(entity_id)
				
	
func interpolate_entities_in_thread(_dummy=null):
	while true:
		if is_interpolation_thread_stopped:
			break
		for entity in entities.values():
			var render_time:float = OS.get_ticks_msec() - INTERPOLATION_INTERVAL
			entity.interpolate(render_time)


func interpolate_entities(_dummy=null):
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
		
	if is_multiplayer and not is_thread_interpolation:		
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
		
		
