
# example character/color select menu
extends Control

@onready var network_manager : NetworkManager = get_node("/root/Node3D/ExampleNetworkManager")

func _ready() -> void:
	network_manager.on_server_started.connect(_on_connected_to_server)
	
	%Blue.pressed.connect(func():
		network_manager._request_spawn_helper("res://addons/EzNet/example/scenes/Spawnable/blue.tscn", {"color": "blue"})
	)
	%Red.pressed.connect(func():
		network_manager._request_spawn_helper("res://addons/EzNet/example/scenes/Spawnable/red.tscn", {"color": "red"})
	)

func _on_connected_to_server():
	show()
