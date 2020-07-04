extends Node


export var HOST: String = "ws://localhost:8080/"
const is_multiplayer: bool = true
const is_thread_interpolation: bool = false
const INTERPOLATION_INTERVAL_MSEC:float = 1000.0 / 10; #ms

var entities: Dictionary = {}
var disconnected_ids: Array = []
var new_entities_messages: Array = []
var disconnected_entities_messages: Array = []

var entity_obj = preload("res://common/scene/character.tscn");
onready var mutex = $NetManager.mutex

var messages_mutex = Mutex.new()

var interpolation_thread: Thread;
var is_interpolation_thread_stopped: bool = false

func on_connected():
	self.set_physics_process(true)
	
	if is_thread_interpolation:
		is_interpolation_thread_stopped = false
# warning-ignore:return_value_discarded
		if not interpolation_thread.is_active():
			interpolation_thread.start(self, "interpolate_entities_in_thread")
		
	$character.entity_id = $NetManager.get_network_unique_id()
	
func on_disconnected():
	if is_thread_interpolation:
		var _lg = $NetManager.LockGuard.new(mutex)
		
	if $character.entity_id:
		disconnected_ids.append($character.entity_id)
		$character.input_sequence_number = 0
		$character.entity_id = null
		
	self.set_physics_process(false)
	$NetManager.disconnect_from_host()
	$NetManager.connect_to_url(HOST)
	
	if is_thread_interpolation:
		is_interpolation_thread_stopped = true
		interpolation_thread.wait_to_finish()
		
func _exit_tree():
	if is_thread_interpolation:
		is_interpolation_thread_stopped = true
		interpolation_thread.wait_to_finish()
		#interpolation_thread = Thread.new()
	

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
# warning-ignore:return_value_discarded
	$NetManager._client.connect("peer_packet", self, "message_received")
	
	$NetManager.set_process(!is_thread_interpolation)
	$NetManager.set_multithread(is_thread_interpolation)
	
	$NetManager.connect_to_url(HOST)
		
	$character.set_thread_interpolation(is_thread_interpolation)
	
	if is_thread_interpolation:
		interpolation_thread.start(self, "interpolate_entities_in_thread")
		
		
		
#var times: Array = [0]
#var deltas: Array = []
#
func message_received(_peer_id=1):
	
	if not $character.entity_id:
		return
	
#	var t = OS.get_ticks_msec()
#	deltas.append(t-times.back())
#	if len(deltas) == 100:
#		print(deltas)
#		times.clear()
#		deltas.clear()
#	times.append(t)
	
	var data = Utils.decode_data($NetManager.get_packet())
	var obj = dict2inst(data)

	var world_state: Types.WorldState = obj
	for entity_state_obj in world_state.entity_states:
		var entity_state = Types.deserialize_entity_state(entity_state_obj)
		var entity_id = entity_state.entity_id
		
		if disconnected_ids.has(entity_id):
			continue
				
		if entity_state.last_processed_input == -1:
			# disconnected
			messages_mutex.lock()
			disconnected_entities_messages.append(entity_state)
			messages_mutex.unlock()
			continue
			
		if not (entities.has(entity_id) or $character.entity_id == entity_id):
			messages_mutex.lock()
			new_entities_messages.append(entity_state)
			messages_mutex.unlock()
			continue
		
		if entities.has(entity_id):
			var timestamp = OS.get_ticks_msec()
			entities.get(entity_id).append_state(entity_state, timestamp)
		else:
			$character.set_state(entity_state)
		
	
func remove_entity(entity_id):
	var entity = entities.get(entity_id)
	if entities.erase(entity_id):
		remove_child(entity)
		
		
func process_character_state():
	var entity_state = $character.last_entity_state
	$character.position = entity_state.position
	if $character.pending_inputs.empty():
		return
		
	var start_number = $character.pending_inputs[0].input_sequence_number
	var from = entity_state.last_processed_input - start_number
	
	$character.pending_inputs = $character.pending_inputs.slice(
		from, $character.pending_inputs.size()-1 )
		
	for input in $character.pending_inputs:
		$character.apply_input(input)
	$character.apply_health(entity_state.health)
	
	if is_thread_interpolation:
		$character.set_state(null)
	else:
		$character.last_entity_state = null
	
func process_server_messages():
	if not is_multiplayer:
		return
	#var processed_entities: Array = []
	
	if $character.last_entity_state:
		process_character_state()
			
	messages_mutex.lock()
	var new_entity_messages_copy = new_entities_messages.duplicate()
	var disconnected_entity_messages_copy = disconnected_entities_messages.duplicate()
	new_entities_messages.clear()
	disconnected_entities_messages.clear()
	messages_mutex.unlock()
	
	for message in new_entity_messages_copy:
		var entity_id = message.entity_id
		var entity = entity_obj.instance()
		entity.position = message.position
		entity.entity_id = entity_id
		entities[entity_id] = entity
		add_child(entity)
		
	for message in disconnected_entity_messages_copy:
		remove_entity(message.entity_id)
		
	for entity in entities.values():
		entity.apply_last_state()
				
	
func interpolate_entities_in_thread(_dummy=null):
	while true:
		if is_interpolation_thread_stopped:
			break
		$NetManager.poll2()
		for entity in entities.values():
			var render_time:float = OS.get_ticks_msec() - INTERPOLATION_INTERVAL_MSEC
			entity.interpolate(render_time)


func interpolate_entities(_dummy=null):
	var render_time:float = OS.get_ticks_msec() - INTERPOLATION_INTERVAL_MSEC
	for entity in entities.values():
		entity.interpolate(render_time)
	
	
func send_input_to_server(input: Types.EntityInput):
	if is_thread_interpolation:
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
	
	if is_multiplayer:
		send_input_to_server(input);
		
	apply_input(input)
		
func apply_input(input: Types.EntityInput):
	if not is_multiplayer and input.trigger:
		var entity_shot = $character.get_node("weapon").get_weapon_target()
		if entity_shot is character:
			$character.hit_enemy(entity_shot)
	$character.apply_input(input)
		
		
