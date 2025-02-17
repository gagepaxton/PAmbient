@tool
@icon("res://addons/purely-ambience/PurelyIcon.svg")
extends Node3D

## ====================== EXPORTED VARIABLES ======================
@export_category(" WHO HEARS THIS ")
@export var player_node: CharacterBody3D

@export_category(" AUDIO STREAM ")
@export var audio_stream: AudioStream

@export_category(" VOLUME SETTINGS ")
@export_range(-80.0, 80.0, 0.1) var max_volume_db: float = 0.0
@export_range(-80.0, 80.0, 0.1) var min_volume_db: float = 0.0

@export_category(" DISTANCE SETTINGS ")
@export var max_distance_fallback: float = 60.0
@export var trigger_distance: float = 0.0
@export var fade_range: float = 15.0

@export_category(" SMOOTHING ")
@export var volume_lerp_speed: float = 5.0

@export_category(" LOGIC TOGGLES ")
@export var priority: bool = false
@export var mute_outersources: bool = false
@export var show_debug: bool = false

## ====================== CONSTANTS & INTERNALS ======================
const VOLUME_OFF_DB: float = -80.0
const DEBUG_SPHERE_NODE: String = "DebugSphere"

var audio_player_node: AudioStreamPlayer

## ====================== READY ======================
func _ready() -> void:
	add_to_group("AudioAmbienceNodes")

	if not Engine.is_editor_hint():
		audio_player_node = AudioStreamPlayer.new()
		audio_player_node.name = "StreamAmbient"
		add_child(audio_player_node)
		audio_player_node.stream = audio_stream
		audio_player_node.volume_db = VOLUME_OFF_DB
		audio_player_node.play()
	
	if Engine.is_editor_hint():
		_update_debug_sphere()

## ====================== PROCESS (EDITOR) ======================
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_update_debug_sphere()
		
## ====================== PHYSICS PROCESS (GAME) ======================
func _physics_process(delta: float) -> void:
	# Only run the logic at runtime (unless we set simulate_in_editor).
	if not Engine.is_editor_hint():
		_apply_ambience_logic(delta)

## ====================== AMBIENCE LOGIC ======================
func _apply_ambience_logic(delta: float) -> void:
	# Null checks.
	if player_node == null or audio_player_node == null:
		return

	var distance_to_player = player_node.global_position.distance_to(global_position)
	var target_volume_db = _calculate_volume(distance_to_player)

	# For non-priority streams, lower volume or mute if an active priority stream is nearby.
	if not priority:
		for node in get_tree().get_nodes_in_group("AudioAmbienceNodes"):
			if node == self:
				continue
			if node is Node3D and node.priority:
				if node.trigger_distance > 0.0:
					var dist_to_priority = player_node.global_position.distance_to(node.global_position)
					if dist_to_priority <= node.trigger_distance:
						if mute_outersources:
							target_volume_db = VOLUME_OFF_DB
						else:
							target_volume_db = max(VOLUME_OFF_DB, target_volume_db - 10.0)
						break

	audio_player_node.volume_db = lerp(audio_player_node.volume_db, target_volume_db, volume_lerp_speed * delta)

## ====================== VOLUME CALCULATION ======================
func _calculate_volume(distance: float) -> float:
	if trigger_distance > 0.0:
		if distance <= trigger_distance:
			return max_volume_db
		elif distance <= trigger_distance + fade_range:
			var fade_factor = 1.0 - ((distance - trigger_distance) / fade_range)
			return lerp(VOLUME_OFF_DB, max_volume_db, fade_factor)
		else:
			return VOLUME_OFF_DB
	else:
		var global_ratio = clamp(distance / max_distance_fallback, 0.0, 1.0)
		return lerp(min_volume_db, max_volume_db, global_ratio)

## ====================== DEBUG SPHERE (EDITOR ONLY) ======================
func _update_debug_sphere() -> void:
	if (trigger_distance <= 0.0 or not show_debug) and Engine.is_editor_hint():
		var old_sphere = get_node_or_null(DEBUG_SPHERE_NODE)
		if old_sphere:
			old_sphere.queue_free()
		return
	
	var debug_sphere = get_node_or_null(DEBUG_SPHERE_NODE) as MeshInstance3D
	if debug_sphere == null:
		debug_sphere = MeshInstance3D.new()
		debug_sphere.name = DEBUG_SPHERE_NODE
		add_child(debug_sphere)
		
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = 1.0
		sphere_mesh.resource_local_to_scene = true
		debug_sphere.mesh = sphere_mesh
		
		var mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.flags_unshaded = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.disable_fog = true
		debug_sphere.material_override = mat
	else:
		if debug_sphere.mesh is SphereMesh:
			var s_mesh = debug_sphere.mesh as SphereMesh
			if s_mesh.radius != 1.0:
				s_mesh.radius = 1.0
		else:
			var sphere_mesh = SphereMesh.new()
			sphere_mesh.radius = 1.0
			sphere_mesh.resource_local_to_scene = true
			debug_sphere.mesh = sphere_mesh

	# Update the material color based on priority.
	if debug_sphere.material_override is StandardMaterial3D:
		var mat_sphere = debug_sphere.material_override as StandardMaterial3D
		debug_sphere.material_override.resource_local_to_scene = true
		if priority:
			mat_sphere.albedo_color = Color(0, 1, 0, 0.3)
		else:
			mat_sphere.albedo_color = Color(1, 0, 0, 0.3)
	
	debug_sphere.visible = (trigger_distance > 0.0 and show_debug)
	
	# Ignore parent's scale for a perfect sphere:
	var parent_tf_no_scale = global_transform
	var parent_scale = parent_tf_no_scale.basis.get_scale()
	if parent_scale.x != 0 and parent_scale.y != 0 and parent_scale.z != 0:
		parent_tf_no_scale.basis = parent_tf_no_scale.basis.scaled(
			Vector3(1.0 / parent_scale.x, 1.0 / parent_scale.y, 1.0 / parent_scale.z)
		)
	debug_sphere.global_transform = parent_tf_no_scale
	debug_sphere.scale = Vector3.ONE * trigger_distance
