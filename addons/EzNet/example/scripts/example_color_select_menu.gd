
# example character/color select menu
extends Control

@onready var network_manager : NetworkManager = get_node("/root/Node3D/ExampleNetworkManager")

func _ready() -> void:
	%Blue.pressed.connect(func():
		network_manager._request_spawn_helper("res://addons/EzNet/example/scenes/Spawnable/blue.tscn", {"color": "blue"})
	)
	%Red.pressed.connect(func():
		network_manager._request_spawn_helper("res://addons/EzNet/example/scenes/Spawnable/red.tscn", {"color": "red"})
	)
