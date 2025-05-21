class_name Networker extends Resource

## Must be overriden. Called on network manager when host is started
func host() -> MultiplayerPeer:
	return null

## Must be overriden. Called on network manager when attempting 
## to connect to a server as a client
func connect_client() -> MultiplayerPeer:
	return null
