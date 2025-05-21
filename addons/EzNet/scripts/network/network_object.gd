class_name NetworkObject extends Node

#region variables
## The name of the autoloaded network manager node 
@export var network_manager_name = "Network_Manager"

## Sets the owner of this network object to the server on disconnect
@export var set_server_to_owner_on_disconnect : bool = false

## grabs the autoloaded network manager
@onready var network_manager : NetworkManager = get_node("/root/%s" % network_manager_name)

## The network id of the connection that owns this object
var owner_id : int = 1
## the id of this object. Increases in order 0 to N
var object_id : int = -1
## is true if this network object has started its initialization
var has_initialized : bool = false
## The resource path that this network object was loaded from
var resource_path : String
## The arguments that this network object used to spawn 
## e.g. position, rotation, color
var spawn_args : Dictionary
## DO NOT MODIFY
## This is for the server to track which transforms have changed from their original position
var cached_transforms : Dictionary
## DO NOT MODIFY
## This is to cache the sync vars so that we don't need to get them each network tick
var network_sync_vars : Dictionary = {}
#endregion

#region validators
## Gets called on the server when a player requests ownership of an object
##
## @tutorial validate_request_ownership(sender_id : int) -> bool:
var validate_ownership_change_callable : Callable
## Gets called on the server when a player requests to destroy an object
##
## @tutorial validate_request_destroy(sender_id : int) -> bool:
var validate_destroy_request_callable : Callable
#endregion

#region signals
## Gets emitted when the network object finishes initializing
signal on_network_ready()
## Gets emitted when the server changes the owner of an object
##
## @tutorial _on_ownership_change(old_owner_id : int, new_owner_id):
signal on_owner_changed(old_owner : int, new_owner : int)
## Gets emitted when the server destroys a network object
signal on_network_destroy()
#endregion

#region godot functions
## @tutorial override this and then call super() at the END of your ready function
func _ready() -> void:
	var props := get_property_list()
	
	for prop in props:
		# checking for synce vars and making sure they are network serializable types
		if prop.name.begins_with("sync_") && (prop.type != 16 && prop.type != 17):
			network_sync_vars[prop.name] = get(prop.name)
	
	if !is_instance_valid(network_manager):
		printerr("No network manager found. Maybe the name is incorrect or it wasn't auto loaded")
		return
	
	if !network_manager.network_started:
		network_manager.on_server_started.connect(_on_network_start)
	else:
		_on_network_start()
		
#endregion

#region public functions
## Returns true if this client owns this network object
func _is_owner() -> bool:
	if owner_id == network_manager.network_id:
		return true
	
	return false

## returns all children transforms of this network object as a dictionary
func _get_transforms() -> Dictionary:
	var dict : Dictionary = {}
	
	var children := _get_all_children_transforms(self)
	
	for child in children:
		var child_path : NodePath = child.get_path()
		if !cached_transforms.has(child_path):
			cached_transforms.set(child_path, [child.position, child.rotation, child.scale])
			dict.set(child_path, child.transform)
		elif !compare_transform_to_cached_transform(child, cached_transforms.get(child_path)):
			dict.set(child_path, child.transform)
	
	return dict

## returns all immediate child transforms of a node as an array
func _get_all_children_transforms(node : Node) -> Array[Node]:
	var nodes : Array[Node] = []

	for N in node.get_children():

		if N.get_child_count() > 0:
			if N is Node2D || N is Node3D:
				nodes.append(N)

			nodes.append_array(_get_all_children_transforms(N))
		elif N is Node2D || N is Node3D:
			nodes.append(N)

	return nodes

## returns all of the synce vars that have changed
func _get_dirty_sync_vars() -> Array:
	if network_sync_vars.is_empty(): return[]
	
	var dirty_vars : Array = []
	
	for key in network_sync_vars:
		var old_value = network_sync_vars[key]
		var new_value = get(key)
		
		if old_value != new_value:
			dirty_vars.append(key)
			dirty_vars.append(new_value)
			network_sync_vars[key] = new_value
	
	if dirty_vars.size() < 2: return []
	
	return dirty_vars

func _update_dirty_sync_vars(updated_var : Array):
	var length : int = updated_var.size() - 1
	
	for n in range(0, length, 2):
		set(updated_var[n], updated_var[n+1])

#endregion

#region helper functions

func compare_transform_to_cached_transform(n : Node, cached_transform : Array) -> bool:
	if n is Node2D:
		# These three checks can be removed for performance.
		# They are just here for your protection in case you decided to modify cached_transforms dict
		# outside of the _get_transforms function
		if cached_transform[0] is not Vector2: return false
		if cached_transform[1] is not float: return false
		if cached_transform[2] is not Vector2: return false
		
		# checking positions
		var pos : Vector2 = cached_transform[0]
		if !EzUtils.compare_approx_vector2(n.position, pos): return false
		
		# checking rotation
		var rot : float = cached_transform[1]
		if !EzUtils.compare_approx_float(n.rotation, rot): return false
		
		# checking scale
		var sca : Vector2 = cached_transform[2]
		if !EzUtils.compare_approx_vector2(n.scale, sca): return false
		
		return true
		
	elif n is Node3D:
		# These three checks can be removed for performance.
		# They are just here for your protection in case you decided to modify cached_transforms dict
		# outside of the _get_transforms function
		if cached_transform[0] is not Vector3: return false
		if cached_transform[1] is not Vector3: return false
		if cached_transform[2] is not Vector3: return false
		
		# checking position
		var pos : Vector3 = cached_transform[0]
		if !EzUtils.compare_approx_vector3(n.position, pos): return false
		
		# checking rotation
		var rot : Vector3 = cached_transform[1]
		if !EzUtils.compare_approx_vector3(n.rotation, rot): return false

		# checking scale
		var sca : Vector3 = cached_transform[2]
		if !EzUtils.compare_approx_vector3(n.scale, sca): return false
		
		return true
	
	return false

#endregion

#region signal callbacks
## Do not override. Used for internal logic
func _on_network_start():
	if has_initialized:
		return
	
	has_initialized = true
	network_manager.register_network_object(self)
	
	if network_manager.on_server_started.is_connected(_on_network_start):
		network_manager.on_server_started.disconnect(_on_network_start)
#endregion

#region rpc functions
## Requests ownership of this network object from the server. 
## 
## @tutorial _request_ownership.rpc_id(1)
@rpc("any_peer", "reliable", "call_local", NetworkManager.MANAGEMENT_CHANNEL)
func _request_ownership():
	var sender_id : int = network_manager.multiplayer.get_remote_sender_id()
	print("requested ownership change by %s" % sender_id)
	
	if !network_manager.is_server:
		return
	
	if owner_id == sender_id:
		return
	
	if validate_ownership_change_callable:
		if validate_ownership_change_callable.call(sender_id):
			_change_owner.rpc(sender_id)
	else:
		_change_owner.rpc(sender_id)

## Called from the server when it changes the ownership of this network object
@rpc("authority", "call_local", "reliable", NetworkManager.MANAGEMENT_CHANNEL)
func _change_owner(new_owner : int):
	network_manager._switch_network_object_owner(new_owner, self)
	on_owner_changed.emit(owner_id, new_owner)
	print("old owner: %s new owner: %s" % [owner_id, new_owner])
	owner_id = new_owner

## does the preliminary setup of an object such as syncing its position when
## spawned or connected to the network
@rpc("authority", "call_local", "reliable", NetworkManager.MANAGEMENT_CHANNEL)
func _initialize_network_object(objects_id : int, owners_id : int, transforms : Dictionary, sync_vars : Dictionary):
	if !network_manager.is_server:
		self.object_id = objects_id
		self.owner_id = owners_id
		
		var children_transforms := _get_all_children_transforms(self)
		
		for child in children_transforms:
			var child_path = child.get_path()
			if transforms.has(child_path):
				child.transform = transforms[child_path]
		
		for key in sync_vars.keys():
			set(key, sync_vars[key])
	
	on_network_ready.emit()

## Used to request the server to destroy this network object
@rpc("any_peer", "call_local", "reliable", NetworkManager.MANAGEMENT_CHANNEL)
func _request_destroy_network_object():
	var sender_id : int = network_manager.multiplayer.get_remote_sender_id()
	if validate_destroy_request_callable:
		if validate_destroy_request_callable.call(sender_id):
			_destroy_network_object.rpc()
	else:
		_destroy_network_object.rpc()

## Called by the server when it want's to destroy this network object
@rpc("authority", "call_local", "reliable", NetworkManager.MANAGEMENT_CHANNEL)
func _destroy_network_object():
	if _is_owner() || network_manager.is_server:
		network_manager._remove_network_object(self)
	
	on_network_destroy.emit()
	queue_free()
#endregion
