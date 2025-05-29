
# example connection menu
extends Control

@export var network_manager_path : NodePath = "/root/Node3D/ExampleNetworkManager"

@onready var ip_field : LineEdit = get_node("IP LineEdit")
@onready var port_field : LineEdit = get_node("Port LineEdit")
@onready var connect_btn : Button = get_node("ConnectButton")
@onready var host_btn : Button = get_node("HostButton")
@onready var network_manager : NetworkManager = get_node(network_manager_path)


func _ready() -> void:
	network_manager.on_server_started.connect(_on_connected_to_server)
	connect_btn.button_up.connect(_connect)
	host_btn.button_up.connect(_host)

func _on_connected_to_server():
	var status_text = "client"
	if network_manager.is_server:
		status_text = "server"
	
	hide()

func _host():
	network_manager.networker.port = port_field.text as int
	network_manager._create_server()

func _connect():
	network_manager.networker.ip = ip_field.text
	network_manager.networker.port = port_field.text as int
	
	network_manager._connect_client()
