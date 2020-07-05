extends Node


export var HOST: String = "ws://localhost:8080/"
const is_multiplayer: bool = true
var is_html5: bool = OS.get_name() == "HTML5"
const is_thread_interpolation: bool = false
const INTERPOLATION_INTERVAL_MSEC:float = 1000.0 / 10; #ms
const INTERPOLATION_INC_STEP_MSEC:float = 5.0 #ms
var INTERPOLATION_EXTRA_TIME_MSEC:float = 0.0 #ms

var entities: Dictionary = {}

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
		$character.input_sequence_number = 0
		$character.entity_id = null
		
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
	if not is_multiplayer:
		$character.entity_id = 0
		return
		
	if is_thread_interpolation:
		interpolation_thread = Thread.new()

	self.set_physics_process(false)
	
# warning-ignore:return_value_discarded
	$NetManager._client.connect("peer_packet", self, "message_received")
	$NetManager._client.connect("peer_connected", self, "on_peer_connected")
	$NetManager._client.connect("peer_disconnected", self, "on_peer_disconnected")
	$NetManager._client.connect("server_disconnected", self, "on_server_disconnected")
	$NetManager.connect("disconnected", self, "on_disconnected")
	
	$NetManager.set_process(!is_thread_interpolation)
	$NetManager.set_multithread(is_thread_interpolation)
	
	$NetManager.connect_to_url(HOST)
	
	if is_thread_interpolation:
# warning-ignore:return_value_discarded
		interpolation_thread.start(self, "interpolate_entities_in_thread")
		
		
func on_peer_connected(peer_id):
	if peer_id == 1:
		return on_connected()
	if entities.has(peer_id):
		return
	var entity = entity_obj.instance()
	entity.entity_id = peer_id
	entities[peer_id] = entity
	add_child(entity)
	Utils._log("%s: Client just connected" % peer_id)
		
		
func on_peer_disconnected(peer_id):
	if peer_id == 1:
		return on_disconnected()
	var entity = entities.get(peer_id)
	if entities.erase(peer_id):
		remove_child(entity)
		
func on_server_disconnected():
	for entity_id in entities:
		on_peer_disconnected(entity_id)
	return on_disconnected()
		
func message_received(_peer_id=1):
	
	if not $character.entity_id:
		return
	
	var data = Utils.decode_data($NetManager.get_packet())
	var obj = dict2inst(data)
	
	var timestamp = OS.get_ticks_msec()

	var world_state: Types.WorldState = obj
	for entity_state_obj in world_state.entity_states:
		var entity_state = Types.deserialize_entity_state(entity_state_obj)
		var entity_id = entity_state.entity_id
		
		if entities.has(entity_id):
			entities.get(entity_id).append_state(entity_state, timestamp)
			
		elif $character.entity_id == entity_id:
			$character.set_state(entity_state)

		
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
	
	if $character.last_entity_state:
		process_character_state()
		
	for entity in entities.values():
		entity.apply_last_state()
	
	
		
		
func _interpolate_entities():
	var render_time:float = OS.get_ticks_msec() - (
		INTERPOLATION_INTERVAL_MSEC + INTERPOLATION_EXTRA_TIME_MSEC)
		
	var is_smooth: bool = true
	for entity in entities.values():
		is_smooth = entity.interpolate(render_time) and is_smooth
		
	if not is_smooth:
		Utils._log("Interpolation extra time += %s" % INTERPOLATION_INC_STEP_MSEC)
		INTERPOLATION_EXTRA_TIME_MSEC += INTERPOLATION_INC_STEP_MSEC
	
	
func interpolate_entities_in_thread(_dummy=null):
	assert(false)
	while true:
		if is_interpolation_thread_stopped:
			break
		$NetManager.poll2()
		_interpolate_entities()


func interpolate_entities(_dummy=null):
	_interpolate_entities()
	
	
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
		
		
