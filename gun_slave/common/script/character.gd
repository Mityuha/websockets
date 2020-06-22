extends KinematicBody2D

class_name character

var blood_obj = preload("res://common/scene/blood.tscn");

export var is_player: bool = false;
export var max_health: int = 100;
var health: int = max_health;
export var speed:float = 200.0
export var velocity:Vector2 = Vector2.ZERO;


var entity_id = null;
var pending_inputs: Array = [] # for me
var state_buffer: Array = [] # for other client entities
var input_sequence_number: int = 0
var world = null
var looking_at: Vector2 = Vector2.ZERO


func _ready():
	$camera.current = self.is_player
	if is_player:
		self.world = get_parent().get_parent()
	set_physics_process(self.is_player)
	
func process_inputs(delta)->Types.EntityInput:
	if !self.is_player:
		return null;
	
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
		
	input.entity_id = self.entity_id
	input.input_sequence_number = self.input_sequence_number
	self.input_sequence_number += 1
	
	self.pending_inputs.append(input)
	
	return input
	
	
	
func apply_input(input: Types.EntityInput):
	self.velocity = Vector2.ZERO
	self.velocity.x += int(input.right)
	self.velocity.x -= int(input.left)
	self.velocity.y += int(input.down)
	self.velocity.y -= int(input.up)
	self.velocity = self.velocity.normalized() * self.speed
	self.looking_at = input.look_at
	self.look_at(input.look_at)
# warning-ignore:return_value_discarded
	move_and_slide(self.velocity)
	
func _unhandled_input(_event):
	if not is_player:
		return
	if Input.is_action_just_released("scroll_down"):
		if $camera.zoom.x < 1.2:
			$camera.zoom.x += 0.1;
			$camera.zoom.y += 0.1;
	if Input.is_action_just_released("scroll_up"):
		if $camera.zoom.x > 0.2:
			$camera.zoom.x -= 0.1;
			$camera.zoom.y -= 0.1;
	

func hit(damage:int)->void:
	# TODO: To remove from it
	self.health -= damage;
	var blood = blood_obj.instance();
	blood.global_position = self.global_position+Vector2(randi()%20-10,randi()%20-10);
	if not self.world:
		# does not work on other entities
		return
	var effect = self.world.get_node("effect")
	if effect:
		effect.add_child(blood);

