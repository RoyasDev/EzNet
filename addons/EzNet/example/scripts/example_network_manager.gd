


# example extending the network manager to get the custom network manager logic
extends NetworkManager

@export var red_spawn_point : Vector3
@export var blue_spawn_point : Vector3

@onready var color_select_menu : Control = get_node("/root/Node3D/Menus/ColorSelectMenu")
@onready var error_text : RichTextLabel = get_node("/root/Node3D/Menus/ColorSelectMenu/RichTextLabel")

var red_players : int = 0
var blue_players : int = 0

# Gets called when the network starts on the server and the client. Its just an auto connected
# function to the on_server_started() signal
func _on_network_started():
	validate_spawn_callable = _validate_spawn
	
	if !is_server: return
	validate_request_spawn_callable = _validate_spawn_request
	spawn_batching_logic 

# Gets called every network tick on the network manager. Its just an auto connected
# function to the on_tick(tick_number : int) signal
func _on_tick(tick_number : int):
	pass

# an overridden function to add custom spawn logic
func _spawn_object(spawn_args : Dictionary) -> Node:
	var owner_id : int = 1
	
	var object_id : int = -1
	
	if spawn_args.has(OBJECT_ID_KEY):
		object_id = spawn_args[OBJECT_ID_KEY]
		print("spawning object with object_id %s" % object_id)
	
	if spawn_args.has(OWNER_ID_KEY):
		owner_id = spawn_args[OWNER_ID_KEY]
	
	var resource_path : String = spawn_args[RESOURCE_PATH_KEY]
	
	if validate_spawn_callable:
		if !validate_spawn_callable.call(spawn_args): return null
	
	var obj = load(resource_path).instantiate()
	
	var new_obj_name = obj.name + str(owner_id);
	obj.name = new_obj_name
	
	if !is_instance_valid(obj):
		push_error("Failed to instantiate: %s" % resource_path)
		return null
	
	if spawn_args.has("color"):
		if owner_id == network_id: color_select_menu.hide()
		
		if spawn_args["color"] == "red":
			obj._set_position(red_spawn_point)
			red_players += 1
		else:
			obj._set_position(blue_spawn_point)
			blue_players += 1
	
	if obj is NetworkObject:
		obj.resource_path = resource_path
		obj.owner_id = owner_id
		obj.object_id = object_id
		obj.spawn_args = spawn_args
	
	get_tree().current_scene.add_child(obj)
	return obj

# Called before _spawn_object(spawn_args : Dictionary). Used to see if a player
# has permission to request this specific spawn. Such as if they have this item in their bank
# that they want to spawn
func _validate_spawn_request(spawn_args : Dictionary) -> bool:
	var resource_path : String = spawn_args[RESOURCE_PATH_KEY]
	
	var owner_id : int = 1
	
	if spawn_args.has(OWNER_ID_KEY):
		owner_id = spawn_args[OWNER_ID_KEY]
	
	if resource_path is not String:
		push_error("either resource_path(%s) is not a String" % resource_path)
		return false
	
	# making sure that the spawns only come from the approved spawn folder
	if !ResourceLoader.exists(resource_path) || !resource_path.begins_with("res://addons/EzNet/example/scenes/Spawnable/"):
		push_error("Invalid resource path %s" % resource_path)
		return false
	
	if !spawn_args.has("color"): return true
	
	if spawn_args["color"] == "red" && red_players > blue_players: 
		_update_error_text.rpc_id(owner_id, "There are too many red players. Pick blue")
		return false
	
	if spawn_args["color"] == "blue" && blue_players > red_players: 
		_update_error_text.rpc_id(owner_id, "There are too many blue players. Pick red")
		return false
	
	return true

# this can be used to determine if a specific spawn should happen on THIS client.
# shouldn't be used to hide things from the player if cheating is a concern. So I am just returning true
func _validate_spawn(spawn_args : Dictionary) -> bool:
	return true

# determines if the currently requested spawn is batched. If false the spawn isn't batched
# so we are batching the blue spawns and not batching the red ones
func _spawn_batching_logic(spawn_args : Dictionary) -> bool:
	if spawn_args.has("color") && spawn_args["color"] == "blue": return true
	
	return false


@rpc("authority", "call_local", "reliable")
func _update_error_text(error : String):
	error_text.clear()
	error_text.add_text(error)
