extends Node

export var PORT:int = 8080

const MAX_NO_INPUT_COUNT = 50
const UPDATE_RATE = 10
const UPDATE_INTERVAL = 1.0 / UPDATE_RATE # ms
var already_passed: float = 0.0

var entity_obj = preload("res://common/scene/character.tscn");

var entities: Dictionary = {}
var entities_2_last_processed_input: Dictionary = {}

onready var mutex = $server.mutex
onready var connected_clients_mutex = $server.connected_clients_mutex
onready var disconnected_clients_mutex = $server.disconnected_clients_mutex
onready var message_queue_mutex = $server.message_queue_mutex
var LockGuard = Utils.LockGuard

var is_multithread: bool = false


# Called when the node enters the scene tree for the first time.
func _ready():
	if $server.listen(PORT) == OK:
		Utils._log("Listening on port %s, multithread: %s" % [PORT, is_multithread])
	else:
		Utils._log("Error listening on port %s" % PORT)
		
	$server.set_multithread(is_multithread)
	
	if is_multithread:
		$server.start_poll()
		
func process_connected():
	if is_multithread:
		var _lg = LockGuard.new(connected_clients_mutex)
		
	while $server.connected_clients_queue:
		var client_id = $server.connected_clients_queue.pop_back()
		var pos = Vector2(rand_range(200, 500), rand_range(200, 500))
		
		var entity = entity_obj.instance()
		add_child(entity)
		entity.position = pos
		entity.entity_id = client_id
		entities[client_id] = entity
		
		var init_state = Types.InitialState.new()
		init_state.position = pos
		init_state.entity_id = client_id
		var obj = Types.serialize_initial_state(init_state)
		$server.send_data(obj, client_id)
		
func disconnect_client(client_id):
	var entity = entities[client_id]
# warning-ignore:return_value_discarded
	entities_2_last_processed_input.erase(client_id)
	remove_child(entity)
# warning-ignore:return_value_discarded
	entities.erase(client_id)
		
func process_disconnected():
	if is_multithread:
		var _lg = LockGuard.new(disconnected_clients_mutex)
		
	while $server.disconnected_clients_queue:
		var client_id = $server.disconnected_clients_queue.pop_back()
# warning-ignore:return_value_discarded
		disconnect_client(client_id)
		
func process_world():
	if is_multithread:
		message_queue_mutex.lock()
		
	var queue_copy = $server.receive_message_queue.duplicate()
	$server.receive_message_queue.clear()
	
	if is_multithread:
		message_queue_mutex.unlock()
		
	for data in queue_copy:
		var input: Types.EntityInput = Types.deserialize_entity_input(data)
		if not entities.has(input.entity_id):
			continue
		entities[input.entity_id].apply_input(input)
		
	
func get_world_state()->Dictionary:
	var world_state = Types.WorldState.new()
	for entity in entities.values():
		var entity_state = Types.EntityState.new()
		entity_state.entity_id = entity.entity_id
		entity_state.position = entity.position
		entity_state.last_processed_input = entity.input_sequence_number
		entity_state.look_at = entity.looking_at
		world_state.entity_states.append(Types.serialize_entity_state(entity_state))
		
		var e_last_input = entities_2_last_processed_input.get(entity.entity_id)
		if not e_last_input or e_last_input != entity_state.last_processed_input:
			entities_2_last_processed_input[entity.entity_id] = entity_state.last_processed_input
			entity.no_input_counter = 0
		else:
			entity.no_input_counter += 1
			if entity.no_input_counter > MAX_NO_INPUT_COUNT:
				$server._disconnect_client(entity.entity_id)
			
	return Types.serialize_world_state(world_state)
	

func _physics_process(delta):
	if not is_multithread:
		$server.poll(delta)
		
	if not $server._clients:
		if entities.size():
			process_disconnected()
			for entity_id in entities:
				disconnect_client(entity_id)
			entities.clear()
		return
		
	already_passed += delta
	if already_passed < UPDATE_INTERVAL:
		return
	already_passed = 0.0
	
	process_connected()
	
	process_world()
	
	var state_pkg = get_world_state()
	$server.broadcast_data(state_pkg)
	
	process_disconnected()

