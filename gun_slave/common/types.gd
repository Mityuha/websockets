extends Node

"""
About _init functions see https://github.com/godotengine/godot/issues/30572
"""

func _ready():
	pass

class EntityInput:
	var input_sequence_number: int
	var entity_id: int
	var right: bool = false
	var left: bool = false
	var up: bool = false
	var down: bool = false 
	var trigger: bool = false
	var press_time: float
	var look_at: Vector2
	var shot_entity_id = null
	var shot_entity_interpolation_percentage: float = 0.0
	
	
class InitialState:
	var room: int = 0
	var entity_id: int
	var position: Vector2;
	
		
class EntityState:
	var entity_id: int
	var last_processed_input: int
	var position: Vector2
	var look_at: Vector2
	var is_triggered: bool
	var health: int
	
		
class WorldState:
	var entity_states: Array;
	

func serialize_entity_input(input: EntityInput) -> Dictionary:
	return inst2dict(input)
	
func serialize_entity_input_custom(input: EntityInput)->PoolByteArray:
	var res: PoolByteArray = PoolByteArray()
	res.append_array(Utils.int_2_bytes(input.input_sequence_number))
	res.append(input.entity_id)
	var key_mask: int = 0
	key_mask = Utils.enable_bit_or_do_nothing(key_mask, 4, input.trigger)
	key_mask = Utils.enable_bit_or_do_nothing(key_mask, 3, input.right)
	key_mask = Utils.enable_bit_or_do_nothing(key_mask, 2, input.up)
	key_mask = Utils.enable_bit_or_do_nothing(key_mask, 1, input.left)
	key_mask = Utils.enable_bit_or_do_nothing(key_mask, 0, input.down)
	res.append(key_mask)
	res.append_array(var2bytes(input.look_at))
	return res

func deserialize_entity_input(dict: Dictionary) -> Object:
	return dict2inst(dict)
	
func serialize_world_state(world_state: WorldState)-> Dictionary:
	return inst2dict(world_state)

func deserialize_world_state(dict: Dictionary)-> Object:
	return dict2inst(dict)
	
func serialize_entity_state(entity_state: EntityState)-> Dictionary:
	return inst2dict(entity_state)
	
func deserialize_entity_state(dict: Dictionary)-> Object:
	return dict2inst(dict)
	
func serialize_initial_state(init_state: InitialState)-> Dictionary:
	return inst2dict(init_state)
	
func deserialize_initial_state(dict: Dictionary)-> Object:
	return dict2inst(dict)
