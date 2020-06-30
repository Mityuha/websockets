extends Node


export var HOST: String = "ws://vscale.sofaxes.xyz:8080/"
var entity_id: int
var input_sequence_number: int = 0

func on_connected():
	self.set_physics_process(true)
	
func on_disconnected():
	if is_multithread:
		var _lg = $NetManager.LockGuard.new(mutex)
		
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
	$NetManager.connect_to_url(HOST)
	
	$NetManager.set_process(true)
	$NetManager.set_multithread(false)
		
	
func send_input_to_server(input: Types.EntityInput):
	var obj = Types.serialize_entity_input(input)
	$NetManager.send_data(obj)
	
	
func process_inputs(delta):
	var input = Types.EntityInput.new();
	input.press_time = delta
		
	input.look_at = get_global_mouse_position();
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
	
func _physics_process(delta):
		
	var input: Types.EntityInput = process_inputs(delta);
	send_input_to_server(input);
		
