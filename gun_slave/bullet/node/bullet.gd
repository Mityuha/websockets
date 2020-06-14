extends KinematicBody2D

class_name bullet

var velocity:Vector2 = Vector2();
var speed:float = 700.0;
var damage:int = 10;

func _ready():
	pass # Replace with function body.

func init(pos:Vector2, 
			dir:float, 
			new_speed:float, 
			lifetime:float)->void:
	self.global_position = pos;
	self.speed = new_speed;
	self.rotation = dir;
	$lifetime.start(lifetime);
	self.start(pos, dir);
	pass

func start(pos:Vector2, dir:float):
	self.rotation = dir
	self.global_position = pos
	self.velocity = Vector2(speed, 0).rotated(self.rotation);

func _physics_process(delta):
	var collision = move_and_collide(velocity * delta)
	if collision:
		self.check_collision(collision);

func check_collision(collision)->void:
	if collision.collider.has_method("bullet_destroy"):
		self.velocity = velocity.bounce(collision.normal);
		$lifetime.wait_time = 0.1;
		return;
	if collision.collider is character:
		collision.collider.hit(self.damage);
		self.bullet_destroy();
		return;
	self.bullet_destroy();

func bullet_destroy():
	self.queue_free();

func _on_lifetime_timeout():
	self.bullet_destroy();
	pass
