extends Sprite

var max_timelife:float=5;

func _ready():
	pass 

func _physics_process(delta):
	self.self_modulate.a8 -= 255/(max_timelife/delta)
	if self.self_modulate.a8 <0:
		self.queue_free();
