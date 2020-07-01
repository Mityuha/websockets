extends Node


export var HOST: String = "ws://localhost:8080/"
var entity_id = null
var input_sequence_number: int = 0

func on_connected():
	self.set_physics_process(true)
	
func on_disconnected():
	entity_id = null
	input_sequence_number = 0
	self.set_physics_process(false)
	$NetManager.disconnect_from_host()
	$NetManager.connect_to_url(HOST)
	

# Called when the node enters the scene tree for the first time.
func _ready():
	self.set_physics_process(false)
	
# warning-ignore:return_value_discarded
	$NetManager.connect("connected", self, "on_connected")
# warning-ignore:return_value_discarded
	$NetManager.connect("disconnected", self, "on_disconnected")
	
	$NetManager.set_process(true)
	$NetManager.set_multithread(false)
	
	$NetManager.connect_to_url(HOST)
	
	
		
	
func send_input_to_server(input: Types.EntityInput):
	var obj = Types.serialize_entity_input(input)
	$NetManager.send_data(obj)
	
	
func process_inputs(delta):
	var input = Types.EntityInput.new();
	input.press_time = delta
		
	#input.look_at = get_global_mouse_position();
	if Input.is_action_pressed('ui_right'):
		input.right = true
	if Input.is_action_pressed('ui_left'):
		input.left = true
	if Input.is_action_pressed('ui_down'):
		input.down = true
	if Input.is_action_pressed('ui_up'):
		input.up = true
	if Input.is_action_pressed("click"):
		pass
		
	input.entity_id = entity_id
	input.input_sequence_number = input_sequence_number
	input_sequence_number += 1
	
	return input
	
func get_entity_id():
	for time_data_list in $NetManager.receive_message_queue:
		var _message_time = time_data_list[0]
		var data = time_data_list[1]
		
		var obj = dict2inst(data)
		if obj.get("room") != null:
			entity_id = obj.entity_id
			return
	
func _physics_process(delta):
	
	if not entity_id:
		get_entity_id()
		return
		
	var input: Types.EntityInput = process_inputs(delta);
	send_input_to_server(input);
		
