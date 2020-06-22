extends Node2D

var bullet_obj = preload("res://common/scene/bullet.tscn");
var max_fire_rate:float = 200;
var last_touch_time;

func _ready():
	pass 

func _physics_process(delta):
	if !owner.is_player:
		return;
	if Input.is_action_pressed("click"):
		if self.last_touch_time and  OS.get_ticks_msec()-self.last_touch_time < max_fire_rate:
			return;
		self.last_touch_time = OS.get_ticks_msec();
		var bullet = bullet_obj.instance();
		owner.world.get_node("effect").add_child(bullet);
		bullet.init($bullet_point.global_position, get_parent().rotation, 700.0, 1)
		pass
