@tool
class_name TPlayer
extends Node2D

const TGaniScript = preload("res://scripts/TGani.gd")
const COLLISION_SHAPE_OFFSET := Vector2(-0.5, 12)
const COLLISION_SHAPE_SIZE := Vector2(31, 30)
const CORNER_SLIDE_PROBE := 9.0
const CORNER_SLIDE_STEP := 1.0
const CORNER_SLIDE_CHECKS := [1.0, 2.0, 3.0]
const CARRY_ITEM_RECTS := {
	"bush": Rect2i(0, 338, 32, 32),
	"vase": Rect2i(64, 340, 32, 32),
	"stone": Rect2i(96, 338, 32, 32),
	"blackstone": Rect2i(96, 370, 32, 32),
	"sign": Rect2i(32, 340, 32, 32)
}
const CARRY_ITEM_SOURCES := {}
const HIDABLE_CARRY_TYPES := {"bush": true, "stone": true, "blackstone": true}
const HIDDEN_WALK_SHAKE := [Vector2(0, 0), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1)]
const HIDDEN_SPEED_SCALE := 0.55
const WALK_STEP_TIME := 0.26
const HIDDEN_STEP_TIME := 0.16
const HIDDEN_SHAKE_TIME := 150
const CARRY_D := [Vector2(0, -2), Vector2(-2, 0), Vector2(0, 2), Vector2(2, 0)]
const LIFT_DELTA := [0.0, 0.9, 1.5, 1.8, 2.0]
const JUMP_SCALE := 16.0
const JUMP_DELTA_Y_UP := [-0.2, 0.2, 0.5, 1.5, 2.8, 4.0, 5.4, 7.0]
const JUMP_DELTA_Y_SIDE := [-0.2, -0.5, 0.0, 0.5, 1.1, 1.7, 2.3, 3.0]
const JUMP_DELTA_X_SIDE := [1.0, 2.0, 3.0, 3.8, 4.5, 5.2, 5.8, 6.5]
const JUMP_DELTA_Y_DOWN := [1.5, 2.7, 3.8, 4.5, 5.0, 5.2, 5.2, 5.0]
const JUMP_LANDING_OFFSET := [Vector2(0.0, -5.0), Vector2(-6.5, 3.0), Vector2(0.0, 7.0), Vector2(6.5, 3.0)]
const CLIFF_JUMP_TRIGGER_TICKS := 48
const JUMP_FRAME_TIME := 0.055

@export var resource_dir: String = "res://assets/ganis":
	set(value):
		resource_dir = value
		if is_inside_tree():
			load_animation(animation_name)

@export var image_dir: String = "res://assets/images"
@export var sound_dir: String = "res://assets/sounds"

@export var animation_name: String = "idle":
	set(value):
		animation_name = value.strip_edges().trim_suffix(".gani")
		if is_inside_tree():
			load_animation(animation_name)

@export_group("Movement")
@export var move_speed: float = 200.0
@export var idle_animation: String = "idle"
@export var walk_animation: String = "walk"
@export var attack_animation: String = "attack"
@export var grab_animation: String = "grab"
@export var pull_animation: String = "pull"
@export var lift_animation: String = "lift"
@export var carry_animation: String = "carry"
@export var carry_still_animation: String = "carrystill"
@export var hidden_animation: String = "hidden"
@export var hidden_still_animation: String = "hiddenstill"
@export var sit_animation: String = "sit"
@export var swim_animation: String = "swim"

@export_group("Camera")
@export var camera_enabled: bool = true
@export var camera_zoom: Vector2 = Vector2.ONE

@export_range(0, 3, 1) var direction: int = 2:
	set(value):
		direction = clampi(value, 0, 3)
		queue_redraw()

@export var draw_offset: Vector2 = Vector2(-24, -20):
	set(value):
		draw_offset = value
		queue_redraw()

@export_group("Body Colors")
@export_range(-1, 19, 1) var skin_color: int = 2:
	set(value):
		skin_color = value
		_apply_exported_body_colors()

@export_range(-1, 19, 1) var coat_color: int = 0:
	set(value):
		coat_color = value
		_apply_exported_body_colors()

@export_range(-1, 19, 1) var sleeves_color: int = 10:
	set(value):
		sleeves_color = value
		_apply_exported_body_colors()

@export_range(-1, 19, 1) var shoes_color: int = 4:
	set(value):
		shoes_color = value
		_apply_exported_body_colors()

@export_range(-1, 19, 1) var belt_color: int = 18:
	set(value):
		belt_color = value
		_apply_exported_body_colors()

var current_gani = null
var current_animation_name := ""
var current_frame := 0
var frame_timer_ms := 0.0
var texture_cache: Dictionary = {}
var body_source_image: Image
var body_color_slots: Array[int] = [-1, -1, -1, -1, -1]
var body_source_key := ""
var body_recolored_cache: ImageTexture
var body_recolor_cache_key := ""
var status_text := ""
var is_moving := false
var editor_frame_timer := 0.0
var velocity := Vector2.ZERO
var active_action := ""
var animation_cache: Dictionary = {}
var sound_cache: Dictionary = {}
var sound_players: Dictionary = {}
var camera: Camera2D
var carry_item_texture: ImageTexture
var carry_item_textures: Dictionary = {}
var carry_item_type := "bush"
var space_was_down := false
var grab_was_down := false
var pickup_was_down := false
var sign_move_was_down := false
var sign_reopen_lock := false
var carrying_object := false
var hidden_object := false
var hidden_uses_gani := false
var hidden_step_timer := 0.0
var walk_step_timer := 0.0
var sign_touch_timer := 0.0
var link_touch_timer := 0.0
var jump_frames := 0
var jump_timer := 0.0
var jump_start := Vector2.ZERO
var jump_direction := 2
var cliff_push_ticks := 0
var cliff_push_direction := -1
var action_direction := 2

const CRGB = [
	[255, 255, 255],
	[255, 255, 0],
	[255, 173, 107],
	[255, 192, 203],
	[255, 0, 0],
	[139, 0, 0],
	[144, 238, 144],
	[0, 128, 0],
	[0, 100, 0],
	[173, 216, 230],
	[0, 0, 255],
	[0, 0, 139],
	[139, 69, 19],
	[255, 215, 0],
	[128, 0, 128],
	[64, 0, 64],
	[211, 211, 211],
	[128, 128, 128],
	[0, 0, 0],
	[0, 0, 0],
]

# source RGB in body.png -> body color slot
# slots: 0 skin, 1 coat, 2 sleeves, 3 shoes, 4 belt
const BODY_PALETTE = [
	[255, 255, 255, 1],
	[255, 173, 107, 0],
	[255, 0, 0, 2],
	[206, 24, 41, 3],
	[0, 0, 255, 4],
	[0, 132, 0, -1],
	[0, 0, 0, -1],
]

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not Engine.is_editor_hint() and camera_enabled:
		camera = Camera2D.new()
		camera.name = "Camera2D"
		camera.zoom = camera_zoom
		camera.limit_left = 0
		camera.limit_top = 0
		camera.limit_right = 64 * 16
		camera.limit_bottom = 64 * 16
		camera.limit_smoothed = true
		add_child(camera)
		camera.make_current()
	_apply_exported_body_colors()
	load_animation(animation_name)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_process_preview(delta)
		return
	if sign_touch_timer > 0.0:
		sign_touch_timer -= delta

	if camera:
		camera.zoom = camera.zoom.lerp(camera_zoom, min(1.0, 8.0 * delta))
		_update_camera_limits()
	_update_movement(delta)
	_process_animation(delta)
	var level = _get_level()
	if level != null and "thrown_bushes" in level and not level.thrown_bushes.is_empty():
		queue_redraw()
	if hidden_object and is_moving:
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not camera_enabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var level = _get_level()
		if level != null and level.has_method("advance_sign") and level.has_method("is_sign_open") and level.is_sign_open():
			level.advance_sign()
			sign_reopen_lock = true
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo and event.alt_pressed:
		if event.keycode == KEY_8:
			_set_camera_zoom(max(0.5, camera_zoom.x - 0.25))
		elif event.keycode == KEY_9:
			_set_camera_zoom(min(5.0, camera_zoom.x + 0.25))

func _set_camera_zoom(value: float) -> void:
	camera_zoom = Vector2(value, value)

func _update_camera_limits() -> void:
	var levels := get_tree().get_nodes_in_group("level")
	if levels.is_empty():
		return
	var level = levels[0]
	if not level.has_method("get_world_pixel_size"):
		return
	var size: Vector2 = level.get_world_pixel_size()
	camera.limit_right = int(size.x)
	camera.limit_bottom = int(size.y)

func _process_preview(delta: float) -> void:
	if current_gani == null:
		load_animation(animation_name)
		return
	editor_frame_timer += delta
	if editor_frame_timer >= 0.25:
		editor_frame_timer = 0.0
		_process_animation(0.25)

func _process_animation(delta: float) -> void:

	if current_gani == null or current_gani.get_frame_count() == 0:
		return

	var frame = current_gani.get_frame(current_frame)
	if frame.is_empty():
		return

	frame_timer_ms += delta * 1000.0
	var frame_duration := float(frame.get("duration", 50))
	if frame_timer_ms < frame_duration:
		return

	frame_timer_ms -= frame_duration
	current_frame += 1
	if current_frame >= current_gani.get_frame_count():
		if current_gani.is_looped:
			current_frame = 0
		elif current_gani.next_ani != "":
			active_action = ""
			_set_animation_if_available(current_gani.next_ani)
			return
		elif active_action != "":
			current_frame = max(0, current_gani.get_frame_count() - 1)
			if active_action != "grab":
				active_action = ""
				_set_animation_if_available(_get_idle_animation())
			return
		else:
			current_frame = current_gani.get_frame_count() - 1
	if not hidden_object and current_animation_name != walk_animation:
		_play_frame_sounds(current_frame)
	queue_redraw()

func load_animation(ani_name: String) -> bool:
	ani_name = ani_name.strip_edges().trim_suffix(".gani")
	if ani_name.is_empty():
		_set_status("set animation_name on the TPlayer node")
		return false

	var path := _find_resource_path(resource_dir, ani_name + ".gani")
	if animation_cache.has(ani_name):
		var cached: Dictionary = animation_cache[ani_name]
		current_gani = cached.gani
		current_frame = 0
		frame_timer_ms = 0.0
		texture_cache = cached.textures.duplicate()
		body_source_image = cached.body_source_image
		body_source_key = str(cached.body_source_key)
		current_animation_name = ani_name
		apply_body_colors()
		_apply_carry_item_texture()
		_set_status("")
		queue_redraw()
		return true

	var gani = TGaniScript.new()
	if not gani.load_from_file(path):
		_set_status("could not load " + path)
		current_gani = null
		texture_cache.clear()
		queue_redraw()
		return false

	current_gani = gani
	current_animation_name = ani_name
	current_frame = 0
	frame_timer_ms = 0.0
	texture_cache.clear()
	body_source_image = null
	body_source_key = ""

	_load_default_textures()
	_load_custom_textures()
	_apply_carry_item_texture()
	apply_body_colors()
	var cached_textures := texture_cache.duplicate()
	cached_textures.erase("ATTR3")
	animation_cache[ani_name] = {
		"gani": current_gani,
		"textures": cached_textures,
		"body_source_image": body_source_image,
		"body_source_key": body_source_key
	}
	_set_status("")
	queue_redraw()
	return true

func setani(ani_name: String) -> bool:
	return load_animation(ani_name)

func set_gani_param(index: int, value: String) -> void:
	_set_gani_value("PARAM" + str(index), value)

func set_gani_attr(index: int, value: String) -> void:
	_set_gani_value("ATTR" + str(index), value)

func _set_gani_value(key: String, value: String) -> void:
	key = key.to_upper()
	if current_gani == null:
		return
	current_gani.default_images[key] = value
	if _looks_like_image(value):
		var img := _load_image(value)
		if img != null:
			texture_cache[key] = ImageTexture.create_from_image(img)
	else:
		texture_cache.erase(key)
	queue_redraw()

func _looks_like_image(value: String) -> bool:
	var lower := value.strip_edges().to_lower()
	return lower.ends_with(".png") or lower.ends_with(".gif") or lower.ends_with(".jpg") or lower.ends_with(".jpeg") or lower.ends_with(".webp")

func _update_movement(delta: float) -> void:
	var input := _get_move_input()
	var level = _get_level()
	if link_touch_timer > 0.0:
		link_touch_timer = maxf(0.0, link_touch_timer - delta)
	if level != null and level.has_method("is_sign_open") and level.is_sign_open():
		var sign_action_down := input != Vector2.ZERO or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_E)
		if sign_action_down and not sign_move_was_down and level.has_method("advance_sign"):
			level.advance_sign()
			sign_reopen_lock = true
		sign_move_was_down = sign_action_down
		active_action = ""
		velocity = Vector2.ZERO
		is_moving = false
		space_was_down = Input.is_key_pressed(KEY_SPACE)
		grab_was_down = Input.is_key_pressed(KEY_E)
		pickup_was_down = Input.is_key_pressed(KEY_F)
		_set_animation_if_available(_get_idle_animation())
		return
	sign_move_was_down = false
	if input == Vector2.ZERO:
		sign_reopen_lock = false
	if active_action == "jump":
		_animate_jump(delta)
		_try_level_link(_direction_vector(jump_direction))
		_update_hidden_steps(delta)
		_update_walk_steps(delta)
		return
	_update_action_state(input)
	var speed_scale := 1.0
	var tile_type := _get_feet_tile_type()
	var surface_animation := ""
	if tile_type == 3:
		if carrying_object:
			_throw_carried_bush()
		if not hidden_object:
			surface_animation = sit_animation
		speed_scale = 0.3
	elif tile_type == 8:
		speed_scale = 0.75
	elif tile_type == 11:
		if carrying_object:
			_throw_carried_bush()
		surface_animation = swim_animation
		speed_scale = 0.6
	if active_action == "attack" or active_action == "lift":
		input = Vector2.ZERO
		speed_scale = 0.0
	elif active_action == "grab":
		var facing := _direction_vector(action_direction)
		if input != Vector2.ZERO and input.normalized().dot(facing) < -0.5:
			_set_animation_if_available(pull_animation)
		else:
			_set_animation_if_available(grab_animation)
		input = Vector2.ZERO
		speed_scale = 0.0
	if hidden_object:
		speed_scale *= HIDDEN_SPEED_SCALE
	velocity = input.normalized() * move_speed * speed_scale
	if input != Vector2.ZERO:
		_update_direction(input)
		if _update_cliff_jump(input):
			return
	else:
		_reset_cliff_push()
	if velocity != Vector2.ZERO:
		_move_with_collision(velocity * delta)
	_try_level_link(input)
	_try_touch_sign(input)
	var moving_now := input != Vector2.ZERO and active_action == ""
	var wanted_animation := surface_animation
	if wanted_animation.is_empty():
		if hidden_object:
			wanted_animation = hidden_animation if moving_now else hidden_still_animation
		elif carrying_object:
			wanted_animation = carry_animation if moving_now else carry_still_animation
		else:
			wanted_animation = walk_animation if moving_now else idle_animation
	is_moving = moving_now
	if active_action == "":
		_set_animation_if_available(wanted_animation)
	_update_hidden_steps(delta)
	_update_walk_steps(delta)

func _update_hidden_steps(delta: float) -> void:
	if not hidden_object or not is_moving:
		hidden_step_timer = 0.0
		return
	hidden_step_timer += delta
	if hidden_step_timer >= HIDDEN_STEP_TIME:
		hidden_step_timer = 0.0
		_play_sound_file("steps2.wav")

func _update_walk_steps(delta: float) -> void:
	if hidden_object or carrying_object or not is_moving:
		walk_step_timer = 0.0
		return
	walk_step_timer += delta
	if walk_step_timer >= WALK_STEP_TIME:
		walk_step_timer = 0.0
		_play_sound_file("steps2.wav")

func _update_action_state(_input: Vector2) -> void:
	var space_down := Input.is_key_pressed(KEY_SPACE)
	var weapon_down := Input.is_key_pressed(KEY_E)
	var pickup_down := Input.is_key_pressed(KEY_F)
	if active_action == "attack":
		if space_down and not space_was_down and current_frame >= 2:
			_start_action("attack", attack_animation)
			_try_slay_bush_ahead()
		space_was_down = space_down
		grab_was_down = weapon_down
		pickup_was_down = pickup_down
		return
	if active_action == "lift":
		space_was_down = space_down
		grab_was_down = weapon_down
		pickup_was_down = pickup_down
		return
	if hidden_object:
		if weapon_down and not grab_was_down:
			_unhide_bush()
		space_was_down = space_down
		grab_was_down = weapon_down
		pickup_was_down = pickup_down
		return
	if active_action == "grab":
		if not pickup_down:
			active_action = ""
			_set_animation_if_available(_get_idle_animation())
		space_was_down = space_down
		grab_was_down = weapon_down
		pickup_was_down = pickup_down
		return
	if space_down and not space_was_down:
		if carrying_object:
			_throw_carried_bush()
		else:
			_start_action("attack", attack_animation)
			_try_slay_bush_ahead()
	elif weapon_down and not grab_was_down:
		if carrying_object and HIDABLE_CARRY_TYPES.has(carry_item_type):
			_hide_with_bush()
		elif _try_show_sign_ahead():
			pass
	elif pickup_down and not pickup_was_down:
		if carrying_object:
			_throw_carried_bush()
		elif _try_lift_item_ahead():
			carrying_object = true
			_start_action("lift", lift_animation)
		elif _can_grab_ahead():
			action_direction = direction
			_start_action("grab", grab_animation)
	space_was_down = space_down
	grab_was_down = weapon_down
	pickup_was_down = pickup_down

func _start_action(action: String, anim: String) -> void:
	active_action = action
	action_direction = direction
	is_moving = false
	velocity = Vector2.ZERO
	if _set_animation_if_available(anim):
		_play_frame_sounds(current_frame)

func _get_idle_animation() -> String:
	if hidden_object:
		return hidden_still_animation
	return carry_still_animation if carrying_object else idle_animation

func _reset_cliff_push() -> void:
	cliff_push_ticks = 0
	cliff_push_direction = -1

func _update_cliff_jump(input: Vector2) -> bool:
	if active_action != "":
		_reset_cliff_push()
		return false
	var facing := _direction_vector(direction)
	if input.normalized().dot(facing) < 0.75:
		_reset_cliff_push()
		return false
	if not _can_jump_from_cliff():
		_reset_cliff_push()
		return false
	if cliff_push_direction != direction:
		cliff_push_direction = direction
		cliff_push_ticks = 0
	cliff_push_ticks += 1
	if cliff_push_ticks < CLIFF_JUMP_TRIGGER_TICKS:
		return false
	_reset_cliff_push()
	return _try_start_cliff_jump()

func _can_jump_from_cliff() -> bool:
	var level = _get_level()
	if level == null or not level.has_method("get_world_tile_type") or not level.has_method("is_world_blocking"):
		return false
	var found_cliff := false
	for point in _get_facing_action_points():
		if int(level.get_world_tile_type(point)) == 21:
			found_cliff = true
			break
	if not found_cliff:
		return false
	var landing_offset: Vector2 = JUMP_LANDING_OFFSET[direction]
	return not level.is_world_blocking(position + landing_offset * JUMP_SCALE)

func _try_start_cliff_jump() -> bool:
	if not _can_jump_from_cliff():
		return false
	active_action = "jump"
	action_direction = direction
	jump_direction = direction
	jump_start = position
	jump_frames = 8
	jump_timer = 0.0
	is_moving = false
	velocity = Vector2.ZERO
	_play_sound_file("jump.wav")
	return true

func _animate_jump(delta: float) -> void:
	if jump_frames <= 0:
		active_action = ""
		_set_animation_if_available(_get_idle_animation())
		return
	jump_timer += delta
	if jump_timer < JUMP_FRAME_TIME:
		return
	jump_timer = 0.0
	var index := clampi(8 - jump_frames, 0, 7)
	var next_pos := jump_start
	if jump_direction == 3:
		next_pos.x += float(JUMP_DELTA_X_SIDE[index]) * JUMP_SCALE
		next_pos.y += float(JUMP_DELTA_Y_SIDE[index]) * JUMP_SCALE
	elif jump_direction == 2:
		next_pos.y += float(JUMP_DELTA_Y_UP[index]) * JUMP_SCALE
	elif jump_direction == 0:
		next_pos.y -= float(JUMP_DELTA_Y_DOWN[index]) * JUMP_SCALE
	elif jump_direction == 1:
		next_pos.x -= float(JUMP_DELTA_X_SIDE[index]) * JUMP_SCALE
		next_pos.y += float(JUMP_DELTA_Y_SIDE[index]) * JUMP_SCALE
	position = next_pos
	jump_frames -= 1
	if jump_frames <= 0:
		active_action = ""
		_set_animation_if_available(_get_idle_animation())

func _try_slay_bush_ahead() -> bool:
	var level = _get_level()
	if level == null or not level.has_method("try_slay_bush"):
		return false
	for point in _get_facing_action_points():
		if level.try_slay_bush(point):
			return true
	return false

func _try_lift_item_ahead() -> bool:
	var level = _get_level()
	if level == null or not level.has_method("try_lift_bush"):
		return false
	for point in _get_facing_action_points():
		var item_type := str(level.try_lift_bush(point))
		if not item_type.is_empty():
			_set_carry_item_type(item_type)
			if item_type == "sign":
				_play_sound_file("sign.wav")
			return true
	return false

func _try_touch_sign(input: Vector2) -> bool:
	if direction != 0 or sign_touch_timer > 0.0 or sign_reopen_lock or input == Vector2.ZERO:
		return false
	var level = _get_level()
	if level == null or not level.has_method("show_sign_at_world"):
		return false
	var facing := _direction_vector(direction)
	if input.normalized().dot(facing) < 0.75:
		return false
	for point in _get_sign_touch_points():
		if level.show_sign_at_world(point):
			sign_touch_timer = 0.4
			sign_move_was_down = true
			sign_reopen_lock = true
			return true
	return false

func _try_level_link(input: Vector2) -> bool:
	if link_touch_timer > 0.0:
		return false
	var level = _get_level()
	if level == null or not level.has_method("try_level_link"):
		return false
	var result: Dictionary = level.try_level_link(position, input, direction)
	if result.is_empty():
		return false
	position = Vector2(result["position"])
	link_touch_timer = 0.35
	_update_camera_limits()
	return true

func _try_show_sign_ahead() -> bool:
	if direction != 0:
		return false
	var level = _get_level()
	if level == null or not level.has_method("show_sign_at_world"):
		return false
	for point in _get_sign_touch_points():
		if level.show_sign_at_world(point):
			sign_move_was_down = true
			sign_reopen_lock = true
			return true
	return false

func _throw_carried_bush() -> void:
	var thrown_type := carry_item_type
	var level = _get_level()
	if level != null and level.has_method("throw_bush"):
		level.throw_bush(position + Vector2(0, -9), direction, thrown_type)
	carrying_object = false
	hidden_object = false
	active_action = ""
	carry_item_type = "bush"
	_set_carry_item_type(carry_item_type)
	_set_animation_if_available(idle_animation)

func _hide_with_bush() -> void:
	carrying_object = false
	hidden_object = true
	active_action = ""
	hidden_uses_gani = _set_animation_if_available(hidden_still_animation)
	_put_hide_leaps()
	queue_redraw()

func _unhide_bush() -> void:
	hidden_object = false
	hidden_uses_gani = false
	carrying_object = true
	_set_carry_item_type(carry_item_type)
	active_action = ""
	_set_animation_if_available(carry_still_animation)
	_put_hide_leaps()
	queue_redraw()

func _put_hide_leaps() -> void:
	var level = _get_level()
	if level != null and level.has_method("_spawn_leaps") and level.has_method("_play_sound"):
		level._spawn_leaps(position + Vector2(5, 0), "bush")
		level._play_sound("crush.wav", "steps2.wav")
		return
	_play_sound_file("crush.wav")

func _can_grab_ahead() -> bool:
	var level = _get_level()
	if level == null or not level.has_method("has_grab_target"):
		return false
	for point in _get_facing_action_points():
		if level.has_grab_target(point):
			return true
	return false

func _get_facing_action_points() -> Array[Vector2]:
	var facing := _direction_vector(direction)
	var side := Vector2(-facing.y, facing.x)
	var base := position + Vector2(0, 10) + facing * 22.0
	return [base, base + side * 7.0, base - side * 7.0]

func _get_sign_touch_points() -> Array[Vector2]:
	var facing := _direction_vector(direction)
	var side := Vector2(-facing.y, facing.x)
	var base := position + Vector2(0, 12) + facing * 6.0
	return [base, base + side * 5.0, base - side * 5.0]

func _get_level():
	var levels := get_tree().get_nodes_in_group("level")
	return null if levels.is_empty() else levels[0]

func _move_with_collision(motion: Vector2) -> void:
	if motion.x != 0.0:
		var step := Vector2(motion.x, 0.0)
		var next := position + step
		if _can_stand_at(next):
			if _try_corner_slide(step, true, velocity):
				next = position + step
			position = next
		elif not _try_corner_slide(step, false, velocity):
			velocity.x = 0.0
	if motion.y != 0.0:
		var step := Vector2(0.0, motion.y)
		var next := position + step
		if _can_stand_at(next):
			if _try_corner_slide(step, true, velocity):
				next = position + step
			position = next
		elif not _try_corner_slide(step, false, velocity):
			velocity.y = 0.0

func _try_corner_slide(step: Vector2, proactive: bool = false, wanted: Vector2 = Vector2.ZERO) -> bool:
	var side := Vector2(-sign(step.y), sign(step.x))
	if side == Vector2.ZERO:
		return false
	var step_dir: Vector2 = step.normalized()
	var probe: Vector2 = step_dir * CORNER_SLIDE_PROBE
	if proactive and _can_stand_at(position + probe):
		return false
	var side_dot: float = wanted.dot(side)
	var dirs: Array[float] = [-1.0, 1.0]
	if side_dot > 0.0:
		dirs = [1.0]
	elif side_dot < 0.0:
		dirs = [-1.0]
	for dir: float in dirs:
		for amount: float in CORNER_SLIDE_CHECKS:
			var test_offset: Vector2 = side * dir * amount
			var nudge: Vector2 = side * dir * CORNER_SLIDE_STEP
			var lookahead: Vector2 = step_dir * max(step.length(), 1.0)
			if _can_stand_at(position + test_offset) and _can_stand_at(position + test_offset + lookahead):
				position += nudge
				return true
	if proactive:
		return false
	return false

func _can_stand_at(pos: Vector2) -> bool:
	var levels := get_tree().get_nodes_in_group("level")
	if levels.is_empty():
		return true
	var level = levels[0]
	var collision_shape := get_node_or_null("CollisionShape2D")
	var collision_offset := COLLISION_SHAPE_OFFSET
	var collision_size := COLLISION_SHAPE_SIZE
	if collision_shape and collision_shape.shape is RectangleShape2D:
		collision_offset = collision_shape.position
		collision_size = collision_shape.shape.size
	var collision_pos := pos + collision_offset
	var half_size := collision_size / 2.0
	var grid_resolution := 4
	var step_x := collision_size.x / grid_resolution
	var step_y := collision_size.y / grid_resolution
	for x in range(grid_resolution + 1):
		for y in range(grid_resolution + 1):
			var point := collision_pos + Vector2(-half_size.x + x * step_x, -half_size.y + y * step_y)
			if level.has_method("is_world_blocking") and level.is_world_blocking(point):
				return false
	var num_edge_checks := 8
	for i in range(num_edge_checks):
		var t := i / float(num_edge_checks - 1)
		var edge_points := [
			collision_pos + Vector2(lerp(-half_size.x, half_size.x, t), -half_size.y),
			collision_pos + Vector2(lerp(-half_size.x, half_size.x, t), half_size.y),
			collision_pos + Vector2(-half_size.x, lerp(-half_size.y, half_size.y, t)),
			collision_pos + Vector2(half_size.x, lerp(-half_size.y, half_size.y, t))
		]
		for point in edge_points:
			if level.has_method("is_world_blocking") and level.is_world_blocking(point):
				return false
	return true

func _get_feet_tile_type() -> int:
	var levels := get_tree().get_nodes_in_group("level")
	if levels.is_empty():
		return 0
	var level = levels[0]
	if level.has_method("get_world_tile_type"):
		return int(level.get_world_tile_type(position + Vector2(0, 16)))
	return 0

func _set_animation_if_available(ani_name: String) -> bool:
	ani_name = ani_name.strip_edges().trim_suffix(".gani")
	if ani_name.is_empty() or current_animation_name == ani_name:
		return true
	var path := _find_resource_path(resource_dir, ani_name + ".gani")
	if not FileAccess.file_exists(path):
		return false
	return load_animation(ani_name)

func _get_move_input() -> Vector2:
	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input.y += 1.0
	return input

func _update_direction(input: Vector2) -> void:
	if abs(input.x) > abs(input.y):
		direction = 3 if input.x > 0.0 else 1
	elif input.y != 0.0:
		direction = 2 if input.y > 0.0 else 0

func _direction_vector(dir: int) -> Vector2:
	match dir:
		0: return Vector2.UP
		1: return Vector2.LEFT
		2: return Vector2.DOWN
		3: return Vector2.RIGHT
	return Vector2.DOWN

func set_body_colors(skin: int, coat: int, sleeves: int, shoes: int, belt: int) -> void:
	skin_color = skin
	coat_color = coat
	sleeves_color = sleeves
	shoes_color = shoes
	belt_color = belt
	_apply_exported_body_colors()

func _apply_exported_body_colors() -> void:
	body_color_slots = [skin_color, coat_color, sleeves_color, shoes_color, belt_color]
	body_recolored_cache = null
	body_recolor_cache_key = ""
	if is_inside_tree():
		apply_body_colors()

func _load_default_textures() -> void:
	if current_gani == null:
		return

	for slot in current_gani.default_images.keys():
		var image_name := str(current_gani.default_images[slot]).strip_edges()
		if image_name.is_empty():
			continue

		var img := _load_image(image_name)
		if img == null:
			continue

		if slot == "BODY":
			body_source_image = img.duplicate()
			body_source_key = image_name
		texture_cache[slot] = ImageTexture.create_from_image(img)

func _load_custom_textures() -> void:
	if current_gani == null:
		return

	for sprite_id in current_gani.sprites.keys():
		var sprite: Dictionary = current_gani.sprites[sprite_id]
		if str(sprite.get("type", "")) != "CUSTOM":
			continue

		var image_name := str(sprite.get("custom_image", "")).strip_edges()
		if image_name.is_empty():
			continue

		var img := _load_image(image_name)
		if img != null:
			texture_cache[str(sprite_id)] = ImageTexture.create_from_image(img)

func _apply_carry_item_texture() -> void:
	if carry_item_texture == null:
		_set_carry_item_type(carry_item_type)
	if carry_item_texture != null:
		texture_cache["ATTR3"] = carry_item_texture

func _get_carry_item_texture(item_type: String) -> ImageTexture:
	var resolved_type := item_type if CARRY_ITEM_RECTS.has(item_type) else "bush"
	if carry_item_textures.has(resolved_type):
		return carry_item_textures[resolved_type]
	var source: String = str(CARRY_ITEM_SOURCES.get(resolved_type, "sprites.png"))
	var sprites: Image = _load_image_from_path(source) if source.begins_with("res://") else _load_image(source)
	if sprites == null:
		return null
	var src: Rect2i = CARRY_ITEM_RECTS[resolved_type]
	var img := Image.create(src.size.x, src.size.y, false, sprites.get_format())
	img.blit_rect(sprites, src, Vector2i.ZERO)
	carry_item_textures[resolved_type] = ImageTexture.create_from_image(img)
	return carry_item_textures[resolved_type]

func _set_carry_item_type(item_type: String) -> void:
	carry_item_type = item_type if CARRY_ITEM_RECTS.has(item_type) else "bush"
	carry_item_texture = _get_carry_item_texture(carry_item_type)
	if carry_item_texture != null:
		texture_cache["ATTR3"] = carry_item_texture
		return
	texture_cache.erase("ATTR3")

func _load_image(image_name: String) -> Image:
	image_name = image_name.strip_edges()
	if image_name.is_empty():
		return null
	var path := _find_resource_path(image_dir, image_name)
	if path.is_empty():
		path = _find_resource_path(resource_dir, image_name)
	if path.is_empty():
		push_warning("missing image: " + image_name)
		return null
	return _load_image_from_path(path)

func _load_image_from_path(path: String) -> Image:
	if path.is_empty():
		return null
	if path.begins_with("res://"):
		var texture := load(path)
		if texture is Texture2D:
			return texture.get_image()
		push_warning("missing image: " + path)
		return null

	var img := Image.new()
	if img.load(path) != OK:
		push_warning("missing image: " + path)
		return null
	return img

func apply_body_colors() -> void:
	if body_source_image == null:
		return
	var next_key := body_source_key + "|" + str(body_color_slots)
	if body_recolored_cache != null and body_recolor_cache_key == next_key:
		texture_cache["BODY"] = body_recolored_cache
		queue_redraw()
		return

	var img := body_source_image.duplicate()
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var px = img.get_pixel(x, y)
			if px.a < 0.04:
				continue

			var pr := int(px.r * 255.0)
			var pg := int(px.g * 255.0)
			var pb := int(px.b * 255.0)

			for entry in BODY_PALETTE:
				if abs(pr - entry[0]) + abs(pg - entry[1]) + abs(pb - entry[2]) >= 40:
					continue

				var slot := int(entry[3])
				if slot >= 0 and slot < body_color_slots.size():
					var color_index := int(body_color_slots[slot])
					if color_index >= 0 and color_index < CRGB.size():
						var c = CRGB[color_index]
						img.set_pixel(x, y, Color8(c[0], c[1], c[2], int(px.a * 255.0)))
				break

	body_recolored_cache = ImageTexture.create_from_image(img)
	body_recolor_cache_key = next_key
	texture_cache["BODY"] = body_recolored_cache
	queue_redraw()

func _draw() -> void:
	if current_gani == null:
		_draw_status()
		return
	if texture_cache.is_empty():
		_draw_status()
		return

	if hidden_object and not hidden_uses_gani:
		_draw_hidden_bush()
		return
	var dir := 0 if current_gani.is_single_dir else direction
	current_gani.draw(self, dir, current_frame, texture_cache, draw_offset + _get_hidden_walk_offset())
	if active_action == "lift":
		_draw_lift_item()
	_draw_shallow_water_overlay()
	_draw_thrown_bushes()

func _get_hidden_walk_offset() -> Vector2:
	if not hidden_object or not is_moving:
		return Vector2.ZERO
	return HIDDEN_WALK_SHAKE[int(Time.get_ticks_msec() / HIDDEN_SHAKE_TIME) % HIDDEN_WALK_SHAKE.size()]

func _draw_hidden_bush() -> void:
	if carry_item_texture == null:
		return
	draw_texture_rect(carry_item_texture, Rect2(Vector2(-16, -20) + _get_hidden_walk_offset(), Vector2(32, 32)), false)

func _draw_lift_item() -> void:
	if active_action != "lift" or not carrying_object or carry_item_texture == null:
		return
	var lift_frame := 4 - current_frame
	if lift_frame < 0:
		lift_frame = 0
	if lift_frame > 4:
		lift_frame = 4
	var dir := clampi(action_direction, 0, 3)
	var t := float(lift_frame) / 4.0
	var from_pos := Vector2(-16, -4)
	var to_pos := Vector2(-16, -30)
	if dir == 1:
		from_pos = Vector2(-31, -12)
		to_pos = Vector2(-17, -31)
	elif dir == 3:
		from_pos = Vector2(-1, -12)
		to_pos = Vector2(-15, -31)
	elif dir == 0:
		from_pos = Vector2(-16, -28)
		to_pos = Vector2(-16, -34)
	elif dir == 2:
		from_pos = Vector2(-16, 0)
		to_pos = Vector2(-16, -26)
	var pos := from_pos.lerp(to_pos, t)
	draw_texture_rect(carry_item_texture, Rect2(pos.round(), Vector2(32, 32)), false)

func _draw_thrown_bushes() -> void:
	var level = _get_level()
	if level == null or not "thrown_bushes" in level:
		return
	for thrown in level.thrown_bushes:
		var item_texture := _get_carry_item_texture(str(thrown.get("type", "bush")))
		if item_texture == null:
			continue
		var progress := clampf(float(thrown["age"]) / float(thrown.get("duration", level.THROW_DURATION)), 0.0, 1.0)
		var world_pos := Vector2(thrown["start"]).lerp(Vector2(thrown["end"]), progress)
		var local_pos := to_local(level.to_global(world_pos)).round()
		var height := sin(progress * PI) * 28.0
		var sprites = texture_cache.get("SPRITES")
		if sprites != null:
			draw_texture_rect_region(sprites, Rect2(local_pos + Vector2(-12, 3), Vector2(24, 12)), Rect2(Vector2.ZERO, Vector2(24, 12)))
		draw_texture_rect(item_texture, Rect2(local_pos + Vector2(-16, -16 - height), Vector2(32, 32)), false)

func _draw_shallow_water_overlay() -> void:
	if _get_feet_tile_type() != 8:
		return
	var sprites = texture_cache.get("SPRITES")
	if sprites == null:
		return
	var frame := int(Time.get_ticks_msec() / 110) % 2
	var src := Rect2(Vector2(4, 307), Vector2(24, 13)) if frame == 0 else Rect2(Vector2(2, 324), Vector2(28, 14))
	var dst := Rect2(Vector2(-src.size.x / 2.0, 13), src.size)
	draw_texture_rect_region(sprites, dst, src)

func _draw_status() -> void:
	var text := status_text
	if text.is_empty():
		text = "drop .gani files in res://assets/ganis, then set animation_name"
	draw_string(ThemeDB.fallback_font, Vector2(-260, 0), text, HORIZONTAL_ALIGNMENT_LEFT, 520, 16, Color.WHITE)

func _set_status(value: String) -> void:
	status_text = value
	queue_redraw()

func _play_frame_sounds(frame_index: int) -> void:
	if current_gani == null:
		return
	var frame = current_gani.get_frame(frame_index)
	if not frame.has("sounds"):
		return
	for sound in frame.sounds:
		_play_sound_file(_resolve_gani_value(str(sound.get("file", ""))))

func _resolve_gani_value(value: String) -> String:
	value = value.strip_edges()
	var key := value.to_upper()
	if current_gani != null and (key.begins_with("PARAM") or key.begins_with("ATTR")) and current_gani.default_images.has(key):
		return str(current_gani.default_images[key])
	return value

func _play_sound_file(file_name: String, volume_db: float = -2.0) -> void:
	var sound_path := _get_sound_path(file_name)
	if sound_path.is_empty():
		return
	var stream := _get_sound_stream(sound_path)
	if stream == null:
		return
	var player = sound_players.get(sound_path)
	if player == null or not is_instance_valid(player):
		player = AudioStreamPlayer.new()
		add_child(player)
		sound_players[sound_path] = player
	player.stop()
	player.stream = stream
	player.volume_db = volume_db
	player.play()

func _get_sound_path(file_name: String) -> String:
	if file_name.is_empty():
		return ""
	var sound_path := _find_resource_path(sound_dir, file_name)
	if sound_path.is_empty():
		sound_path = _find_resource_path(resource_dir, file_name)
	if sound_path.is_empty() and not file_name.get_basename().is_empty():
		for ext in [".wav", ".mp3", ".ogg"]:
			sound_path = _find_resource_path(sound_dir, file_name.get_basename() + ext)
			if not sound_path.is_empty():
				break
	return sound_path

func _get_sound_stream(sound_path: String) -> AudioStream:
	if sound_path.is_empty():
		return null
	if sound_cache.has(sound_path):
		return sound_cache[sound_path]
	var stream := _load_audio_stream(sound_path)
	if stream != null:
		sound_cache[sound_path] = stream
	return stream

func _load_audio_stream(path: String) -> AudioStream:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var magic := file.get_buffer(4)
	file.seek(0)
	var magic_text := magic.get_string_from_ascii()
	if magic_text.begins_with("ID3") or (magic.size() >= 2 and magic[0] == 0xFF):
		var mp3 := AudioStreamMP3.new()
		mp3.data = file.get_buffer(file.get_length())
		file.close()
		return mp3
	file.close()
	return load(path) as AudioStream

func _find_resource_path(base: String, file_name: String) -> String:
	var path := file_name if file_name.begins_with("res://") or file_name.is_absolute_path() else _join_path(base, file_name)
	if FileAccess.file_exists(path):
		return path
	return ""

func _join_path(base: String, file_name: String) -> String:
	if base.ends_with("/") or base.ends_with("\\"):
		return base + file_name
	return base + "/" + file_name
