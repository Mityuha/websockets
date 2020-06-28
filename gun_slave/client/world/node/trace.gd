extends Line2D

var normal:Vector2;
var crr_count_point:int = 0;
var target_point:Vector2;
var step_dist:float = 50.0;
var is_die:bool = false;

func _ready():
	pass

func init(point:Vector2, pos:Vector2)->void:
	self.global_position = pos;
	self.target_point = point;
	self.normal = (point - pos).normalized();
	self.add_point(Vector2(0,0))

func _physics_process(_delta):
	if self.is_die == true:
		return;
	if self.target_point.distance_to(to_global(self.points[self.crr_count_point])) > step_dist:
		self.add_point(self.points[self.crr_count_point]+normal*step_dist)
		self.crr_count_point+=1;
	else:
		self.add_point(to_local(self.target_point));
		self.die();

func die():
	self.is_die = true;
	self.queue_free();
