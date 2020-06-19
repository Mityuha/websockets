extends Node


# Declare member variables here. Examples:
# var a = 2
# var b = "text"


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.
	
func process_server_messages():
	pass
	

func interpolate_entities():
	pass


func _physics_process(delta):
	
	process_server_messages()
	
	if $character.entity_id == null:
		# not connected yet
		return	
		
	$character.process_inputs(delta);
	if not ($character.input_sequence_number % 1000):
		print(len($character.pending_inputs))
		
	interpolate_entities()
		
		
		
