extends Networker

@export var ip : String = "127.0.0.1"
@export var port : int = 9999
@export var max_clients : int = 4
@export var transport_channels : int = 5;

func host() -> MultiplayerPeer:
	var enet = ENetMultiplayerPeer.new()
	var err : Error = enet.create_server(port, max_clients, transport_channels)
	
	if err != OK:
		printerr(err)
		return null
	
	print("returning enet multiplayer peer")
	return enet

func connect_client() -> MultiplayerPeer:
	var enet = ENetMultiplayerPeer.new()
	var err : Error = enet.create_client(ip, port)
	
	if err != OK:
		printerr(err)
		return null
		
	return enet
