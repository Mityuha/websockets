extends Node

export var PORT:int = 8080

const UPDATE_RATE = 10
const UPDATE_INTERVAL = 1.0 / UPDATE_RATE # ms
var already_passed: float = 0.0

var entity_obj = preload("res://common/scene/character.tscn");

var entities: Dictionary = {}


# Called when the node enters the scene tree for the first time.
func _ready():
	if $server.listen(PORT) == OK:
		Utils._log("Listing on port %s" % PORT)
	else:
		Utils._log("Error listening on port %s" % PORT)
		
func process_connected():
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
		
func process_disconnected():
	while $server.disconnected_clients_queue:
		var client_id = $server.disconnected_clients_queue.pop_back()
# warning-ignore:return_value_discarded
		var entity = entities[client_id]
		entities.erase(client_id)
		remove_child(entity)
		
func process_world():
	for data in $server.receive_message_queue:
		var input: Types.EntityInput = Types.deserialize_entity_input(data)
		entities[input.entity_id].apply_input(input)
		entities[input.entity_id].input_sequence_number = input.input_sequence_number
		
	$server.receive_message_queue.clear()
	
func get_world_state()->Dictionary:
	var world_state = Types.WorldState.new()
	for entity in entities.values():
		var entity_state = Types.EntityState.new()
		entity_state.entity_id = entity.entity_id
		entity_state.position = entity.position
		entity_state.last_processed_input = entity.input_sequence_number
		entity_state.look_at = entity.looking_at
		world_state.entity_states.append(Types.serialize_entity_state(entity_state))
	return Types.serialize_world_state(world_state)
	

func _physics_process(delta):
	$server.poll(delta)
	if not $server._clients:
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

