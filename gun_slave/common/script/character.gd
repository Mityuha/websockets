extends KinematicBody2D

class_name character

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
const SERVER_STATE_BUFFER_MAX_SIZE: int = 2048

# (timestamp, input_number, position) tuples array
var client_state_buffer: Array = []
var client_state_buffer_mutex: Mutex = Mutex.new()
var interpolation_input_from: int = 0
var interpolation_input_to: int = 0
var interpolation_percentage: float = 0.0


var last_entity_state_mutex: Mutex = Mutex.new()
var last_entity_state: Types.EntityState

var input_sequence_number: int = 0
var world = null
var looking_at: Vector2 = Vector2.ZERO
var _triggered_times: int = 0

func reset_triggered_times():
	"""return triggered times"""
	var res = _triggered_times
	_triggered_times = 0
	return res


func set_animation(enable: bool):
	use_animation = enable
	$weapon.use_animation = enable

func calculate_position(input_from: int, input_to: int, input_interpolation_percentage: float):
	var index_from = input_from - server_state_buffer[0][0]
	var index_to = index_from + (input_to - input_from)
	
	if index_from >= 0:
		Utils._log("Entity %s index_from (%s) < 0. Is it cheat?" % [entity_id, index_from])
		return
		
	assert(index_from >= 0)
	assert((index_to - index_from) == (input_to - input_from))
	assert(input_from == server_state_buffer[index_from][0])
	assert(input_to == server_state_buffer[index_to][0])
	
	var pos_from = server_state_buffer[index_from][1]
	var pos_to = server_state_buffer[index_to][1]
	return pos_from + (pos_to - pos_from) * input_interpolation_percentage
	


#var times = [0]
#var deltas = []

func interpolate(render_time: float):
	"""
		Return true if could interpolate
		return false if took last entity position
	"""
	if client_state_buffer.size() < 2:
		return true
		
	if render_time < client_state_buffer[0][0]:
		return true
		
	var last_interpolate_index = 1
#	deltas.append(render_time-times.back())
#	if len(deltas) == 100:
#		print(deltas)
#		print(client_state_buffer.size())
#		times.clear()
#		deltas.clear()
#	times.append(render_time)
	
	while client_state_buffer[last_interpolate_index][0] <= render_time:
		last_interpolate_index += 1
		if last_interpolate_index == client_state_buffer.size():
			self.interpolation_input_from = client_state_buffer[last_interpolate_index-2][1]
			self.interpolation_input_to = client_state_buffer[last_interpolate_index-1][1]
			self.interpolation_percentage = 1.0
			self.position = client_state_buffer[last_interpolate_index-1][2]
			client_state_buffer = [client_state_buffer.back()]
			if render_time > client_state_buffer.back()[0]:
				print("render_time: %s, last: %s" % [
					render_time, 
					client_state_buffer.back()[0]]
				)
				return false
			return true
			
			
	#print(client_state_buffer.size(), " ", last_interpolate_index)
	var pos_from: Vector2 = client_state_buffer[last_interpolate_index-1][2]
	var pos_to: Vector2 = client_state_buffer[last_interpolate_index][2]
	var time_from: int = client_state_buffer[last_interpolate_index-1][0]
	var time_to: int = client_state_buffer[last_interpolate_index][0] + 1
	
	self.interpolation_input_from = client_state_buffer[last_interpolate_index-1][1]
	self.interpolation_input_to = client_state_buffer[last_interpolate_index][1]
	
	# just linear interpolate it
	self.interpolation_percentage = (render_time - time_from) / (time_to - time_from)
	assert(self.interpolation_percentage <= 1.0 and self.interpolation_percentage >= 0.0)
#		print(self.interpolation_percentage, " ", 
#			render_time, " ", time_from, " ", time_to, " ",
#			last_interpolate_index, " ", client_state_buffer[last_interpolate_index], " ", 
#			client_state_buffer[last_interpolate_index-1] )
#		print(client_state_buffer)
#		return
	
	self.position = pos_from + (pos_to - pos_from) * interpolation_percentage
	client_state_buffer = client_state_buffer.slice(
		last_interpolate_index-1, client_state_buffer.size()-1
	)
	return true
	

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
				input.shot_entity_input_from = target_entity.interpolation_input_from
				input.shot_entity_input_to = target_entity.interpolation_input_to
				input.shot_entity_interpolation_percentage = target_entity.interpolation_percentage
				input.shot_entity_position = target_entity.position
			$weapon.last_touch_time = now
		
	input.entity_id = self.entity_id
	input.input_sequence_number = self.input_sequence_number
	self.input_sequence_number += 1
	
	self.pending_inputs.append(input)
	
	return input
	
func apply_input(input: Types.EntityInput):
	
	if input.trigger and use_animation:
		$weapon.shoot(input.shot_entity_id != null)
		input.trigger = false
		
	if input.trigger and not is_player:
		_triggered_times += 1
		
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
	

	server_state_buffer.append([input.input_sequence_number, self.position])
	if (server_state_buffer.size() - 128) > SERVER_STATE_BUFFER_MAX_SIZE:
		server_state_buffer = server_state_buffer.slice(128, server_state_buffer.size()-1)
		
func apply_health(new_health: int):
	if new_health == health:
		return
	if (new_health < health) and use_animation:
		blood_animation()
	health = new_health
	
	
func set_state(state: Types.EntityState):
	last_entity_state_mutex.lock()	
	last_entity_state = state
	last_entity_state_mutex.unlock()
	
func append_state(state: Types.EntityState, timestamp: int):
	assert(not is_player)
	client_state_buffer.append(
		[timestamp, state.last_processed_input, state.position]
	)
	
	set_state(state)

func apply_last_state():
	assert(not is_player)
	if not last_entity_state:
		return
	var state = last_entity_state
	self.look_at(state.look_at)
	
	self.input_sequence_number = state.last_processed_input
	
	apply_health(state.health)
		
	if state.is_triggered:
		$weapon.shoot(false)
		
	set_state(null)
	
	
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
#	if health <= 0:
#		self.position.x += 100
#		self.health = MAX_HEALTH
#
	if not use_animation:
		return
		
	blood_animation()
#	if self.health <= 0:
#		self.hide()
		
func blood_animation():
	var blood = blood_obj.instance();
	blood.global_position = self.global_position+Vector2(randi()%20-10,randi()%20-10);
	world.get_node("effect").add_child(blood);

