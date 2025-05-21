class_name NetworkManager extends Node

## This controls whether the network ticks are sent reliable, unreliable, or unreliable_ordered
## Since you can't export constants change this here
const TICK_TYPE : Tick_Type = Tick_Type.UNRELIABLE

## The network channel that handles the sync vars. Seperated from the Tick channel to support webRTC
const SYNC_VAR_CHANNEL = 2
## The network channel that handles all of the core tick logic e.g. network ticks
const TICK_CHANNEL : int = 3
## The network channel that handles the core network logic functionality e.g. spawning, object initialization
const MANAGEMENT_CHANNEL : int = 4

#region constants
const OWNER_ID_KEY : String = "owner_id"
const RESOURCE_PATH_KEY : String = "resource_path"
const OBJECT_ID_KEY : String = "object_id"
const TRANSFORMS_KEY : String = "transforms"
const SYNC_VARS_KEY : String = "sync_vars"

const TICK_TYPES : Dictionary = {
	Tick_Type.RELIABLE: "reliable",
	Tick_Type.UNRELIABLE: "unreliable",
	Tick_Type.UNRELIABLE_ORDERED: "unreliable_ordered"
}
#endregion

#region enums
enum Tick_Type {RELIABLE = 0, UNRELIABLE = 1, UNRELIABLE_ORDERED = 2}
#endregion

#region variables
## The networker for the chosen MultiplayerPeer
@export var networker : Networker
## the number of network ticks that occure per second
@export var ticks_per_second : int = 30

## Stores all the connected players IDs and owned objects
var connected_player_data : Array[ConnectedPlayerData] = []
## The network ID of this client/server
var network_id : int
## If true this is the server. This just simplifies getting that information
var is_server : bool = false
## If the network hasn't started this will be false and no networky things will happen
var network_started : bool = false
## The current tally of object IDs that have been assigned
var current_object_id_number = 0
## The servers timer that is used to determine the tick times
var tick_timer : Timer
## The numbers of ticks that have occured since the server has started
var tick_number : int = 0
## has the info for the current spawns that are batched for the next tick
var spawn_batch : Array[Dictionary] = []
#endregion

#region validators
## Called on server when a client requests to spawn an item.
## This is where you should validate the path so that no hacking happens.
## Should probably limit the network spawnable items to something like 
## res://Scenes/Objects/NetworkObjects
## @tutorial _validate_request_spawn(spawn_args : Dictionary)
var validate_request_spawn_callable : Callable

## Called on the client and the server when a object is trying to spawn
## Should just be used to ensure the validity of the spawn for each client 
## in case they are missing some resources
## @tutorial _validate_spawn(spawn_args : Dictionary)
var validate_spawn_callable : Callable

## Used to determine if a specific spawn should be batched to spawn on the next tick or not.
## If this is unassigned the spawn is automatically batched.
## @tutorial _spawn_batch_logic(spawn_args : Dictionary)
var spawn_batching_logic : Callable
#endregion

#region signals
## Emitted when the server has started or this client has connected to the server
signal on_server_started

## Emitted every network tick
signal on_tick(tick_number : int)

#endregion

#region public functions

## Call to host a server using the selected networker
func _create_server():
	multiplayer.multiplayer_peer = networker.host()
	
	if multiplayer.multiplayer_peer == null: return
	
	connected_player_data.append(_create_player_data(1))
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	network_started = true
	is_server = multiplayer.is_server()
	on_server_started.connect(_on_network_started)
	on_server_started.emit()
	network_id = multiplayer.get_unique_id()
	on_tick.connect(_on_tick)
	
	tick_timer = Timer.new()
	add_child(tick_timer)
	tick_timer.timeout.connect(_tick)
	tick_timer.start(1.0 / ticks_per_second)
	

## Call to connect a client to a server using the selected Networker
func _connect_client():
	multiplayer.multiplayer_peer = networker.connect_client()
	
	if multiplayer.multiplayer_peer == null: return
	
	multiplayer.connected_to_server.connect(_on_connected_to_server)

## Adds a network object to the owner players connected_player_data
## if the object is already owned by another player/server call 
## _switch_network_object_owner(new_owner : int, network_object : NetworkObject)
## instead
func register_network_object(network_object : NetworkObject) -> void:
	if !is_instance_valid(network_object):
		return
	
	if is_server:
		network_object.object_id = current_object_id_number
		current_object_id_number += 1
		network_object._initialize_network_object.rpc(network_object.object_id,
		 network_object.owner_id,
		 network_object._get_transforms(),
		 network_object.network_sync_vars
		)
	
	for player in connected_player_data:
		if player.network_id != network_object.owner_id:
			continue
		
		if player.players_objects.has(network_object):
			print("player already owns this object")
			return
		
		player.players_objects.append(network_object)
		
	print("added network object to %s" % network_object.owner_id)

## Switches the owner of a network object and moves it to the correct ConnectedPlayerData.
## If the object is unowned call 
## register_network_object(network_object : NetworkObject) instead
func _switch_network_object_owner(new_owner : int, network_object : NetworkObject):
	if !is_instance_valid(network_object):
		return
		
	for player in connected_player_data:
		if player.network_id == new_owner:
			player.players_objects.append(network_object)
			

## removes a network object from the owning players ConnectedPlayerData
func _remove_network_object(network_object : NetworkObject):
	for player in connected_player_data:
		if player.network_id == network_object.owner_id:
			if player.players_objects.has(network_object):
				player.players_objects.erase(network_object)
				return

## if set to true the network manager will refuse all new connections 
## even if below the max_clients. If set to false the network manager will allow
## new connections up to the max_clients number and then refuse once that is reached
func _refuse_new_connections(should_refuse : bool):
	multiplayer.multiplayer_peer.refuse_new_connections = should_refuse

## returns the current state of whether the network manager is accepting new 
## connections 
func _get_refuse_connections() -> bool:
	return multiplayer.multiplayer_peer.refuse_new_connections

## Call to disconnect from the server or shut down the server
func _disconnect():
	multiplayer.multiplayer_peer = null
	
	for player in connected_player_data:
		for network_object in player.players_objects:
			network_object.queue_free()
	
	connected_player_data = []
	network_id = 0
	current_object_id_number = 0
	is_server = false
	network_started = false

#endregion

#region private functions
## for the server tick functionality
## emits the on_tick signal on all the clients and server after network logic is completed
func _tick():
	tick_number += 1
	
	for player in connected_player_data:
		var sync_vars : Array = []
		
		for network_object in player.players_objects:
			var objects_sync_vars = network_object._get_dirty_sync_vars()

			if objects_sync_vars.is_empty(): continue
			
			sync_vars.append(network_object.object_id)
			sync_vars.append(objects_sync_vars)
		
		if !sync_vars.is_empty():
			_update_dirty_sync_vars.rpc(player.network_id, sync_vars)
		
		if !spawn_batch.is_empty() && player.network_id != 1:
			_network_spawn_object.rpc_id(player.network_id ,spawn_batch)
		_on_network_tick.rpc_id(player.network_id, tick_number)
	
	if !spawn_batch.is_empty():
		_network_spawn_object.rpc_id(1 ,spawn_batch)
	
	spawn_batch.clear()
	
	
#endregion

#region network signal callbacks

## Called on server when a new client connects to the server
func _on_peer_connected(peer_id):
	if !is_server: return
	var connected_players : Array[int] = []
	var spawns : Array[Dictionary] = []
	
	for player in connected_player_data:
		if !is_instance_valid(player):
			connected_player_data.erase(player)
			continue
		
		if player.network_id == peer_id:
			for network_object in player.players_objects:
				if !is_instance_valid(network_object):
					continue
				network_object._destroy_network_object.rpc()
			connected_player_data.erase(player)
			continue
		
		connected_players.append(player.network_id)
		
		var spawn : Dictionary = {}
		print(player.players_objects.size())
		for network_object in player.players_objects:
			if network_object.resource_path.is_empty():
				spawn[OBJECT_ID_KEY] = network_object.object_id
				spawn[OWNER_ID_KEY] = network_object.owner_id
				spawn[TRANSFORMS_KEY] = network_object._get_transforms()
				spawn[SYNC_VARS_KEY] = network_object.network_sync_vars
				spawn["node_path"] = network_object.get_path()
			else:
				spawn = network_object.spawn_args.duplicate(true)
				spawn[OBJECT_ID_KEY] = network_object.object_id
				spawn[OWNER_ID_KEY] = network_object.owner_id
				spawn[TRANSFORMS_KEY] = network_object._get_transforms()
				spawn[SYNC_VARS_KEY] = network_object.network_sync_vars
			
			spawns.append(spawn)
		
	
	_add_connected_player.rpc_id(peer_id, connected_players, spawns)
	
	connected_player_data.append(_create_player_data(peer_id))
	print("%s connected" % peer_id)
	

## Called on server when a client disconnects
## Used to clean up the players data
func _on_peer_disconnected(peer_id):
	var disconnected_player : ConnectedPlayerData
	for player in connected_player_data:
		if player.network_id == peer_id:
			disconnected_player = player
			break;
	
	if !is_instance_valid(disconnected_player):
		print("no disconnected player object")
		return 
		
	for network_object in disconnected_player.players_objects:
		if !network_object.set_server_to_owner_on_disconnect:
			network_object._destroy_network_object.rpc()
		else:
			network_object._change_owner(1)
	
	_destroy_connected_player_data.rpc(disconnected_player.network_id)
	connected_player_data.erase(disconnected_player)

## Called on clients when a connection to the server is established
func _on_connected_to_server():
	network_id = multiplayer.get_unique_id()
	connected_player_data.append(_create_player_data(network_id))
	print("connected to server with id %s" % network_id)
	network_started = true
	on_server_started.connect(_on_network_started)
	on_server_started.emit()
	on_tick.connect(_on_tick)

#endregion

#region helper functions
## created connected player data and then returns it
func _create_player_data(player_id : int) -> ConnectedPlayerData:
	var player_data : ConnectedPlayerData = ConnectedPlayerData.new()
	player_data.network_id = player_id
	return player_data

## Helps with creating a spawn request in the desired format. Not needed, but useful
## If its on the server runs the spawn batching logic and doesn't send the _request_spawn rpc
func _request_spawn_helper(
	resource_path : String,
	args : Dictionary = {},
	owner_id : int = 1,
	object_id : int = -1):
	
	if !resource_path.begins_with("res://"):
		push_error("Invalid resource path %s" % resource_path)
		return
	
	args[RESOURCE_PATH_KEY] = resource_path
	
	if _verify_spawn_path(resource_path):
		push_error("Invalid resource path %s" % resource_path)
		return
	
	if !is_server:
		_request_spawn_object.rpc_id(1, args)
	else:
		args[OWNER_ID_KEY] = owner_id
		args[OBJECT_ID_KEY] = object_id
		_handle_spawn_batching(args)

## Just does a VERY basic validation of the spawn path for a object. 
## More validation should be done with the 
## _validate_request_spawn_callable(spawn_args : Dictionary)
## in a production game. Fine as is for testing purposes
func _verify_spawn_path(resource_path : String) -> bool:
	return !ResourceLoader.exists(resource_path) || !resource_path.begins_with("res://")

## If there is spawn batching logic assigned to spawn_batching_logic then it will run that test
## to see if that specific spawn should be batched or not
func _handle_spawn_batching(spawn : Dictionary):
	if spawn_batching_logic:
		if spawn_batching_logic.call(spawn):
			spawn_batch.append(spawn)
			return
	
	_network_spawn_object.rpc([spawn])
#endregion

#region overridable functions
## Override this function to add custom spawn behaviour. 
## Such as adding a spawn arg "position" to choose the spawning position
func _spawn_object(spawn_args : Dictionary) -> Node:
	var owner_id : int = 1
	
	var object_id : int = -1
	
	if spawn_args.has(OBJECT_ID_KEY):
		object_id = spawn_args[OBJECT_ID_KEY]
	
	if spawn_args.has(OWNER_ID_KEY):
		owner_id = spawn_args[OWNER_ID_KEY]
	
	var resource_path : String = spawn_args[RESOURCE_PATH_KEY]

	if resource_path is not String:
		push_warning("either resource_path(%s) is not a String" % resource_path)
		return null
	
	if !ResourceLoader.exists(resource_path) || !resource_path.begins_with("res://"):
		push_error("Invalid resource path %s" % resource_path)
		return null
	
	if validate_spawn_callable:
		if !validate_spawn_callable.call(spawn_args): return null
	
	var obj = load(resource_path).instantiate()
	
	# This makes sure there are no clashing names for spawned objects across players
	# but if the same player spawns multiple of the same object this may cause name conflicts
	# change this based on the needs of your game
	var new_obj_name = obj.name + str(owner_id)
	obj.name = new_obj_name
	
	if !is_instance_valid(obj):
		push_error("Failed to instantiate: %s" % resource_path)
		return null
	
	if obj is NetworkObject:
		obj.resource_path = resource_path
		obj.owner_id = owner_id
		obj.object_id = object_id
		obj.spawn_args = spawn_args
	
	get_tree().current_scene.add_child(obj)
	return obj

## Override this function
## This gets called on the server and clients on each network tick after the core tick logic happens
func _on_tick(current_tick : int):
	pass

## Override this function
## This gets called when the network starts
func _on_network_started():
	pass
#endregion

#region rpc functions
## Sends a request to spawn an object from a client to the server. 
## Can add custom spawn_args such as "position"
## You will need to override the _spawn_object(owner_id : int, spawn_args : Dictionary)
## function to use them.
@rpc("any_peer", "call_local", "reliable", 2)
func _request_spawn_object(spawn_args : Dictionary):
	var requester_id = multiplayer.get_remote_sender_id()
	
	if !spawn_args.has(RESOURCE_PATH_KEY):
		push_warning("No resource path provided")
		return
	
	var resource_path = spawn_args[RESOURCE_PATH_KEY]
	spawn_args[OWNER_ID_KEY] = requester_id
	
	if _verify_spawn_path(resource_path):
		push_error("Invalid resource path %s" % resource_path)
		return
	
	if resource_path is not String:
		push_error("either resource_path(%s) is not a String" % resource_path)
		return
	
	if validate_request_spawn_callable:
		if validate_request_spawn_callable.call(spawn_args):
			_handle_spawn_batching(spawn_args)
	else:
		_handle_spawn_batching(spawn_args)
	

## Called by the server to spawn a object
@rpc("authority", "call_local", "reliable", 2)
func _network_spawn_object(spawns : Array):
	for spawn in spawns:
			_spawn_object(spawn)

## Updates the dirty sync vars for all network objects of a given player
@rpc("authority", "call_remote", "unreliable", SYNC_VAR_CHANNEL)
func _update_dirty_sync_vars(owner_id : int, variables : Array):
	var updated_player : ConnectedPlayerData
	
	for player in connected_player_data:
		if player.network_id == owner_id:
			updated_player = player
			break
	
	if !is_instance_valid(updated_player) || updated_player == null: return
	
	var length : int = variables.size() - 1
	
	for n in range(0, length, 2):
		var object_id : int = variables[n]
		var updated_vars : Array = variables[n+1]
		var updated_object : NetworkObject
		
		for network_object in updated_player.players_objects:
			if network_object.object_id != object_id: continue
			
			updated_object = network_object
			break
		
		if !is_instance_valid(updated_object): continue
		updated_object._update_dirty_sync_vars(updated_vars)

## Destroys the connected players data that matches the player id on the local machine
## could be because the player disconnected or the player switched rooms, moved too far away etc.
@rpc("authority", "call_remote", "reliable")
func _destroy_connected_player_data(player_id):
	var player_to_destroy : ConnectedPlayerData
	for player in connected_player_data:
		if player.network_id == player_id:
			player_to_destroy = player
			break
	
	for network_object in player_to_destroy.players_objects:
		network_object.queue_free()
		
	connected_player_data.erase(player_to_destroy)

## Adds all connected players and their network objects to newly connected clients
@rpc("authority", "call_remote", "reliable")
func _add_connected_player(player_id : Array[int], network_objects : Array[Dictionary]):
	for id in player_id:
		for player in connected_player_data:
			if player.network_id == id:
				break
		
		connected_player_data.append(_create_player_data(id))
		for network_object in network_objects:
			if network_object[OWNER_ID_KEY] == id:
				var transforms : Dictionary = {}
				var sync_vars : Dictionary = {}
				
				if network_object.has(TRANSFORMS_KEY):
					transforms = network_object[TRANSFORMS_KEY]
				
				if network_object.has(SYNC_VARS_KEY):
					sync_vars = network_object[SYNC_VARS_KEY]
				
				if !network_object.has(RESOURCE_PATH_KEY) && network_object.has("node_path"):
					# get the node path and initialize
					var node : NetworkObject = get_node(network_object["node_path"])
					node._initialize_network_object(
						network_object[OBJECT_ID_KEY],
						network_object[OWNER_ID_KEY],
						transforms,
						sync_vars)
					network_objects.erase(network_object)
					continue
				
				var spawned_object = _spawn_object(network_object)
				if spawned_object is NetworkObject:
					spawned_object._initialize_network_object(
						spawned_object.object_id,
						spawned_object.owner_id,
						transforms,
						sync_vars
					)
				
				network_objects.erase(network_object)

## emits the tick signal
@rpc("authority", "call_local", TICK_TYPES[TICK_TYPE], TICK_CHANNEL)
func _on_network_tick(current_tick : int):
	on_tick.emit(current_tick)
#endregion
