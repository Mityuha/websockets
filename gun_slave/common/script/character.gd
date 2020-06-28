extends KinematicBody2D

class_name character

const MAX_STATE_BUFFER_SIZE = 600

var blood_obj = preload("res://common/scene/blood.tscn");

export var is_player: bool = false;
var use_animation: bool = true
export var MAX_HEALTH: int = 100;
var health: int = MAX_HEALTH;
export var speed:float = 200.0
export var velocity:Vector2 = Vector2.ZERO;

var no_input_counter: int = 0
var entity_id = null;
var pending_inputs: Array = [] # for me

# (input_number, position) tuples array
var server_state_buffer: Array = [] # for other client entities

# (timestamp, input_number, position) tuples array
var client_state_buffer: Array = []
var interpolation_input_from: int = 0
var interpolation_input_to: int = 0
var interpolation_percentage: float = 0.0

var input_sequence_number: int = 0
var world = null
var looking_at: Vector2 = Vector2.ZERO


func set_animation(enable: bool):
	use_animation = enable
	$weapon.use_animation = enable


func interpolate(render_time: float):
	if client_state_buffer.size() < 2:
		return
	var last_interpolate_index = 1
	
	while client_state_buffer[last_interpolate_index][0] <= render_time:
		last_interpolate_index += 1
		if last_interpolate_index == client_state_buffer.size():
			return
			
	var pos_from: Vector2 = client_state_buffer[last_interpolate_index-1][2]
	var pos_to: Vector2 = client_state_buffer[last_interpolate_index][2]
	var time_from: int = client_state_buffer[last_interpolate_index-1][0]
	var time_to: int = client_state_buffer[last_interpolate_index][0] + 1
	
	self.interpolation_input_from = client_state_buffer[last_interpolate_index-1][1]
	self.interpolation_input_to = client_state_buffer[last_interpolate_index][1]
	
	# just linear interpolate it
	self.interpolation_percentage = (render_time - time_from) / (time_to - time_from)
	self.position = pos_from + (pos_to - pos_from) * interpolation_percentage
	client_state_buffer = client_state_buffer.slice(
		last_interpolate_index-1, client_state_buffer.size()-1
	)
	#print(render_time)
	#print(interpolation_percentage)
	#print()


func _ready():
	$camera.current = self.is_player
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
	if Input.is_action_pressed("click"):
		var now = OS.get_ticks_msec()
		var can_trigger = (now-$weapon.last_touch_time) > $weapon.MAX_FIRE_INTERVAL
		if can_trigger:
			input.trigger = true
			var target_entity: character = $weapon.get_weapon_target()
			if target_entity:
				input.shot_entity_id = target_entity.entity_id
				input.shot_entity_interpolation_percentage = target_entity.interpolation_percentage
			$weapon.last_touch_time = now
		
	input.entity_id = self.entity_id
	input.input_sequence_number = self.input_sequence_number
	self.input_sequence_number += 1
	
	self.pending_inputs.append(input)
	
	return input
	
	
	
func apply_input(input: Types.EntityInput):
	if input.trigger and use_animation:
		$weapon.shoot(input.shot_entity_id != null)
		
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
	if is_player:
		return
	self.input_sequence_number = input.input_sequence_number
	server_state_buffer.append([self.input_sequence_number, self.position])
	if (server_state_buffer.size() - 128) > MAX_STATE_BUFFER_SIZE:
		server_state_buffer = server_state_buffer.slice(128, server_state_buffer.size()-1)


func apply_state(state: Types.EntityState, timestamp: int):
	input_sequence_number = state.last_processed_input
	self.look_at(state.look_at)
	
	if not is_player:				
		client_state_buffer.append(
			[timestamp, state.last_processed_input, state.position]
		)
	
	if state.health != health:
		if (state.health < health) and use_animation:
			blood_animation()
		health = state.health
		
	if not is_player and state.is_triggered:
		$weapon.shoot(false)
	
	
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
	

func hit_enemy(enemy: character):
	return enemy.hit($weapon.damage)

func hit(damage:int)->void:
	self.health -= damage;
	if health <= 0:
		self.position.x += 100
		self.health = MAX_HEALTH
	
	if not use_animation:
		return
		
	blood_animation()
		
func blood_animation():
	var blood = blood_obj.instance();
	blood.global_position = self.global_position+Vector2(randi()%20-10,randi()%20-10);
	world.get_node("effect").add_child(blood);

