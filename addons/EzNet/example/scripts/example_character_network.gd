
#example network object extention
extends NetworkObject

@onready var body : ExamplePlayerCharacterBody = get_node("CharacterBody3D")
@onready var hp_label : Label3D = get_node("CharacterBody3D/Label3D")
@onready var blue_area : Area3D = get_node("/root/Node3D/World/BlueArea")
@onready var red_area : Area3D = get_node("/root/Node3D/World/RedArea")

var drop_hp = false

# This is a sync var that tracks the players current hp. Updated every tick if changed
var sync_health : int = 1000

func _ready():
	super()
	# checks the spawn arguments of this network_object to see if it has a color
	if spawn_args.has("color"):
		if spawn_args["color"] == "red":
			blue_area.body_entered.connect(body_entered)
			blue_area.body_exited.connect(body_exited)
		else:
			red_area.body_entered.connect(body_entered)
			red_area.body_exited.connect(body_exited)

func _process(delta: float) -> void:
	if !network_manager.is_server:
		hp_label.text = "%s" % sync_health 
		return
	
	if !drop_hp: return
	
	# editing the sync var on the server so it can be passed to the clients
	sync_health -= 1
	hp_label.text = "%s" % sync_health 

func body_entered(entering_body : Node3D):
	if entering_body == body:
		drop_hp = true

func body_exited(exiting_body : Node3D):
	if exiting_body == body:
		drop_hp = false

func _input(event: InputEvent) -> void:
	# checking to see if this object is owned by this client
	if !_is_owner():
		return
	
	if event is InputEventMouseButton && event.is_pressed():
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		var mousePos = get_viewport().get_mouse_position()
		var camera = get_viewport().get_camera_3d()
		var ray_origin = camera.project_ray_origin(mousePos)
		var ray_end = ray_origin + camera.project_ray_normal(mousePos) * 5000
		
		_send_input_ray.rpc_id(1, ray_origin, ray_end)
		
		var space_state = body.get_world_3d().direct_space_state
		var intersection = space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(ray_origin, ray_end))
			
		if !intersection.is_empty():
			body.set_movement_target(intersection.position)
		

func _set_position(pos : Vector3):
	get_node("CharacterBody3D").position = pos

@rpc("any_peer", "call_local", "unreliable", 0)
func _send_input_ray(start : Vector3, end : Vector3):
	var sender_id = network_manager.multiplayer.get_remote_sender_id()
	
	# checking to see if the owner of this object sent the request
	if sender_id != owner_id: return
	
	var space_state = body.get_world_3d().direct_space_state
	var intersection = space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(start, end))
		
	
	if !intersection.is_empty():
		_set_movement_target.rpc(intersection.position)

@rpc("authority", "call_local", "unreliable", 0)
func _set_movement_target(target : Vector3):
	body.set_movement_target(target)
