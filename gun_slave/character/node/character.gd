extends KinematicBody2D

class_name character

var blood_obj = preload("res://effect/blood/node/blood.tscn");


export var is_player:bool = false;
export var max_health:int = 100;
var health:int = max_health;
export var speed:float = 200.0
export var velocity:Vector2 = Vector2.ZERO;

func _ready():
	if self.is_player:
		$camera.current = true;
	pass 

func get_input()->void:
	if !self.is_player:
		return;
	self.look_at(get_global_mouse_position())
	velocity = Vector2.ZERO
	if Input.is_action_pressed('ui_right'):
		velocity.x += 1
	if Input.is_action_pressed('ui_left'):
		velocity.x -= 1
	if Input.is_action_pressed('ui_down'):
		velocity.y += 1
	if Input.is_action_pressed('ui_up'):
		velocity.y -= 1
	
	if Input.is_action_just_released("scroll_down"):
		if $camera.zoom.x < 1.2:
			$camera.zoom.x += 0.1;
			$camera.zoom.y += 0.1;
	if Input.is_action_just_released("scroll_up"):
		if $camera.zoom.x > 0.2:
			$camera.zoom.x -= 0.1;
			$camera.zoom.y -= 0.1;
	self.velocity = self.velocity.normalized() * self.speed

func _physics_process(_delta):
	self.get_input();
	self.move_and_slide(self.velocity);

func hit(damage:int)->void:
	self.health -= damage;
	var blood = blood_obj.instance();
	blood.global_position = self.global_position+Vector2(randi()%20-10,randi()%20-10);
	get_parent().get_node("effect").add_child(blood);
	pass
