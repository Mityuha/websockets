extends Node


export var PORT:int = 8080


# Called when the node enters the scene tree for the first time.
func _ready():
	if $server.listen(PORT) == OK:
		Utils._log("Listing on port %s" % PORT)
#		if not $server._use_multiplayer:
#			Utils._log("Supported protocols: %s" % supported_protocols)
	else:
		Utils._log("Error listening on port %s" % PORT)


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
