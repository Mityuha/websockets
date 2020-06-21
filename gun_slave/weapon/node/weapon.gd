extends Node2D

var trace_obj = preload("res://effect/trace/trace.tscn");
var max_fire_rate:float = 200;
var last_touch_time;
var fire_distance:int = 1000;
var damage:int = 20;

func _ready():
	$bullet_point/cast.cast_to = $bullet_point/cast.cast_to*fire_distance;
	pass 

func _physics_process(_delta):
	if !get_parent().is_player:
		return;
	if Input.is_action_pressed("click"):
		if self.last_touch_time and  OS.get_ticks_msec()-self.last_touch_time < max_fire_rate:
			return;
		self.last_touch_time = OS.get_ticks_msec();
		self.shoot();
		pass

func shoot()->void:
	var target_pos:Vector2;
	var body = $bullet_point/cast.get_collider();
	if !body:
		target_pos =  to_global($bullet_point/cast.cast_to);
	else:
		target_pos = $bullet_point/cast.get_collision_point();
		if body is character:
			body.hit(self.damage);
		
	var trace = trace_obj.instance();
	trace.init(target_pos, $bullet_point.global_position);
	get_parent().get_parent().get_node("effect").add_child(trace);
	$weapon_sound.play();
	pass;
