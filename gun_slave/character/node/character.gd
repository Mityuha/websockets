extends KinematicBody2D

class_name character

var blood_obj = preload("res://effect/blood/node/blood.tscn");

export var is_player:bool = false;
export var max_health:int = 100;
var health:int = max_health;
export var speed:float = 200.0
export var velocity:Vector2 = Vector2.ZERO;


var entities:Dictionary = {}
var entity_id: int = 0;
var pending_inputs: Array = [] # for me
var state_buffer: Array = [] # for other client entities
var input_sequence_number: int = 0
var last_ts: int = 0
var world = null

func send_input_to_server(input):
	pass

func _ready():
	$camera.current = self.is_player
	self.world = get_parent().get_parent()
		
class PInput:
	var _right: bool
	var _left: bool
	var _up: bool
	var _down: bool
	var _press_time;
	var _trigger: bool
	var _look_at: Vector2
	var _input_sequence_number: int
	var _entity_id: int
	func _init(): pass
	
func apply_input(input: PInput):
	self.velocity.x += int(input._right)
	self.velocity.x -= int(input._left)
	self.velocity.y += int(input._down)
	self.velocity.y -= int(input._up)
	self.velocity = self.velocity.normalized() * self.speed
	look_at(input._look_at)
	move_and_slide(self.velocity)

func process_inputs(delta)->void:
	if !self.is_player:
		return;
		
#	var now_ts = OS.get_ticks_msec()
#	self.last_ts = self.last_ts or now_ts
#	var delta_sec = (now_ts - last_ts) / 1000.0
#	self.last_ts = now_ts
	
	var input = PInput.new();
	input._press_time = delta
		
	input._look_at = get_global_mouse_position();
	velocity = Vector2.ZERO
	if Input.is_action_pressed('ui_right'):
		input._right = true
	if Input.is_action_pressed('ui_left'):
		input._left = true
	if Input.is_action_pressed('ui_down'):
		input._down = true
	if Input.is_action_pressed('ui_up'):
		input._up = true
		
	input._entity_id = self.entity_id
	input._input_sequence_number = self.input_sequence_number
	self.input_sequence_number += 1
	
	if Input.is_action_just_released("scroll_down"):
		if $camera.zoom.x < 1.2:
			$camera.zoom.x += 0.1;
			$camera.zoom.y += 0.1;
	if Input.is_action_just_released("scroll_up"):
		if $camera.zoom.x > 0.2:
			$camera.zoom.x -= 0.1;
			$camera.zoom.y -= 0.1;
	
	send_input_to_server(input);
	apply_input(input)
	
	# TODO: right after server messages handling
	#self.pending_inputs.append(input)
	

func hit(damage:int)->void:
	self.health -= damage;
	var blood = blood_obj.instance();
	blood.global_position = self.global_position+Vector2(randi()%20-10,randi()%20-10);
	self.world.get_node("effect").add_child(blood);

