@tool
class_name TPlayer
extends Node2D

const TGaniScript = preload("res://scripts/TGani.gd")
const COLLISION_SHAPE_OFFSET := Vector2(-0.5, 12)
const COLLISION_SHAPE_SIZE := Vector2(31, 30)

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
var camera: Camera2D
var space_was_down := false
var grab_was_down := false
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

	if camera:
		camera.zoom = camera.zoom.lerp(camera_zoom, min(1.0, 8.0 * delta))
		_update_camera_limits()
	_update_movement(delta)
	_process_animation(delta)

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not camera_enabled:
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
	if frame_timer_ms < float(frame.get("duration", 50)):
		return

	frame_timer_ms = 0.0
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
				_set_animation_if_available(walk_animation if velocity.length_squared() > 1.0 else idle_animation)
			return
		else:
			current_frame = current_gani.get_frame_count() - 1
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
	apply_body_colors()
	animation_cache[ani_name] = {
		"gani": current_gani,
		"textures": texture_cache.duplicate(),
		"body_source_image": body_source_image,
		"body_source_key": body_source_key
	}
	_set_status("")
	queue_redraw()
	return true

func setani(ani_name: String) -> bool:
	return load_animation(ani_name)

func _update_movement(delta: float) -> void:
	var input := _get_move_input()
	_update_action_state(input)
	var speed_scale := 1.0
	var tile_type := _get_feet_tile_type()
	var surface_animation := ""
	if tile_type == 3:
		surface_animation = sit_animation
		speed_scale = 0.3
	elif tile_type == 8:
		speed_scale = 0.75
	elif tile_type == 11:
		surface_animation = swim_animation
		speed_scale = 0.6
	if active_action == "attack":
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
	velocity = input.normalized() * move_speed * speed_scale
	if velocity != Vector2.ZERO:
		_move_with_collision(velocity * delta)
	if input != Vector2.ZERO:
		_update_direction(input)
	var moving_now := input != Vector2.ZERO and active_action == ""
	var wanted_animation := surface_animation
	if wanted_animation.is_empty():
		wanted_animation = walk_animation if moving_now else idle_animation
	is_moving = moving_now
	if active_action == "":
		_set_animation_if_available(wanted_animation)

func _update_action_state(_input: Vector2) -> void:
	var space_down := Input.is_key_pressed(KEY_SPACE)
	var grab_down := Input.is_key_pressed(KEY_E)
	if active_action == "attack":
		space_was_down = space_down
		grab_was_down = grab_down
		return
	if active_action == "grab":
		if not grab_down:
			active_action = ""
			_set_animation_if_available(walk_animation if velocity.length_squared() > 1.0 else idle_animation)
		space_was_down = space_down
		grab_was_down = grab_down
		return
	if space_down and not space_was_down:
		_start_action("attack", attack_animation)
	elif grab_down and not grab_was_down:
		action_direction = direction
		_start_action("grab", grab_animation)
	space_was_down = space_down
	grab_was_down = grab_down

func _start_action(action: String, anim: String) -> void:
	active_action = action
	action_direction = direction
	is_moving = false
	velocity = Vector2.ZERO
	if _set_animation_if_available(anim):
		_play_frame_sounds(current_frame)

func _move_with_collision(motion: Vector2) -> void:
	if motion.x != 0.0:
		var next := position + Vector2(motion.x, 0.0)
		if _can_stand_at(next):
			position = next
		else:
			velocity.x = 0.0
	if motion.y != 0.0:
		var next := position + Vector2(0.0, motion.y)
		if _can_stand_at(next):
			position = next
		else:
			velocity.y = 0.0

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
		var image_name := str(current_gani.default_images[slot])
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

		var image_name := str(sprite.get("custom_image", ""))
		if image_name.is_empty():
			continue

		var img := _load_image(image_name)
		if img != null:
			texture_cache[str(sprite_id)] = ImageTexture.create_from_image(img)

func _load_image(image_name: String) -> Image:
	var path := _find_resource_path(image_dir, image_name)
	if path.is_empty():
		path = _find_resource_path(resource_dir, image_name)
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

	var dir := 0 if current_gani.is_single_dir else direction
	current_gani.draw(self, dir, current_frame, texture_cache, draw_offset)
	_draw_shallow_water_overlay()

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
		var stream := _get_sound_stream(str(sound.get("file", "")))
		if stream == null:
			continue
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.volume_db = -2.0
		add_child(player)
		player.play()
		player.finished.connect(func(): player.queue_free())

func _get_sound_stream(file_name: String) -> AudioStream:
	if file_name.is_empty():
		return null
	var sound_path := _find_resource_path(sound_dir, file_name)
	if sound_path.is_empty():
		sound_path = _find_resource_path(resource_dir, file_name)
	if sound_path.is_empty() and not file_name.get_basename().is_empty():
		for ext in [".wav", ".mp3", ".ogg"]:
			sound_path = _find_resource_path(sound_dir, file_name.get_basename() + ext)
			if not sound_path.is_empty():
				break
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
