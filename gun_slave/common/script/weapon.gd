extends Node2D

var trace_obj = preload("res://common/scene/trace.tscn")
const MAX_FIRE_RATE: int = 5
const MAX_FIRE_INTERVAL: float = 1000.0 / MAX_FIRE_RATE;
var last_touch_time = 0;
const fire_distance: int = 1000;
const damage:int = 20;
var use_animation: bool = true

func _ready():
	$bullet_point/cast.cast_to = $bullet_point/cast.cast_to * fire_distance;
	
	
func get_weapon_target():
	"""return entity or null"""
	var target = $bullet_point/cast.get_collider()
	if target and (target is character):
		return target
	return null
	

func shoot(has_hit: bool)->void:
	
#	var body = $bullet_point/cast.get_collider();
#	if !body:
#		target_pos =  to_global($bullet_point/cast.cast_to);
#	else:
#		target_pos = $bullet_point/cast.get_collision_point();
#		if body is character:
#			body.hit(self.damage);
		
	if use_animation:
		var target_pos:Vector2 = $bullet_point/cast.get_collision_point() if has_hit \
							else to_global($bullet_point/cast.cast_to);
		var trace = trace_obj.instance();
		trace.init(target_pos, $bullet_point.global_position);
		owner.world.get_node("effect").add_child(trace);
		$weapon_sound.play();
