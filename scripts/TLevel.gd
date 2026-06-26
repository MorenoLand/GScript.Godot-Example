@tool
class_name TLevel
extends Node2D

const TILE_SIZE := 16
const LEVEL_SIZE := Vector2i(64, 64)
const TArraysScript = preload("res://scripts/TArrays.gd")
const BUSH_OBJECTS := [
	{"tiles": [2, 130, 3, 131], "replace": [1301, 1429, 1302, 1430]},
	{"tiles": [3332, 3460, 3333, 3461], "replace": [1301, 1429, 1302, 1430]}
]
const LIFT_OBJECTS := [
	{"type": "bush", "tiles": [2, 130, 3, 131], "replace": [1301, 1429, 1302, 1430]},
	{"type": "bush", "tiles": [3332, 3460, 3333, 3461], "replace": [1301, 1429, 1302, 1430]},
	{"type": "vase", "tiles": [1308, 1436, 1309, 1437], "replace": [1850, 1978, 1851, 1979]},
	{"type": "stone", "tiles": [258, 386, 259, 387], "replace": [2362, 2490, 2363, 2491]},
	{"type": "blackstone", "tiles": [3742, 3870, 3743, 3871], "replace": [2362, 2490, 2363, 2491]}
]
const LEAF_RECTS := [
	Rect2(Vector2(35, 8), Vector2(9, 8)),
	Rect2(Vector2(44, 0), Vector2(15, 16)),
	Rect2(Vector2(60, 0), Vector2(16, 16))
]
const LEAP_RECTS := {
	"bush": [
		Rect2(Vector2(35, 8), Vector2(9, 8)),
		Rect2(Vector2(44, 0), Vector2(15, 16)),
		Rect2(Vector2(60, 0), Vector2(16, 16))
	],
	"vase": [
		Rect2(Vector2(56, 82), Vector2(16, 14)),
		Rect2(Vector2(72, 82), Vector2(16, 14)),
		Rect2(Vector2(56, 96), Vector2(16, 14)),
		Rect2(Vector2(72, 96), Vector2(16, 14))
	],
	"stone": [
		Rect2(Vector2(24, 82), Vector2(16, 16)),
		Rect2(Vector2(40, 82), Vector2(16, 16)),
		Rect2(Vector2(24, 98), Vector2(16, 16)),
		Rect2(Vector2(40, 98), Vector2(16, 16))
	],
	"blackstone": [
		Rect2(Vector2(56, 82), Vector2(16, 14)),
		Rect2(Vector2(72, 82), Vector2(16, 14)),
		Rect2(Vector2(56, 96), Vector2(16, 14)),
		Rect2(Vector2(72, 96), Vector2(16, 14))
	]
}
const CARRY_BUSH_SPRITE_RECT := Rect2(Vector2(0, 338), Vector2(32, 32))
const FLOWER_TILE_FRAMES := {
	128: [453, 454, 455, 454],
	453: [453, 454, 455, 454],
	454: [454, 455, 454, 453],
	455: [455, 454, 453, 454]
}
const FLOWER_FRAME_TIME := 0.22
const THROW_FLY := [
	Vector3(0.0, -0.8, -1.0),
	Vector3(-1.0, 0.2, 0.0),
	Vector3(0.0, 1.2, 1.0),
	Vector3(1.0, 0.2, 0.0)
]
const THROW_DURATION := 0.5

@export_file("*.nw", "*.gmap") var level_path: String = "res://levels/onlinestartlocal.nw":
	set(value):
		level_path = value
		if is_inside_tree():
			load_level()

@export var tileset_path: String = "res://tilesets/pics1.png":
	set(value):
		tileset_path = value
		if is_inside_tree():
			load_level()

@export var tileset_dir: String = "res://tilesets"
@export var sound_dir: String = "res://assets/sounds"
@export var bush_land_sound: String = "crush.wav"
@export var bush_respawn_seconds: float = 12.0

var tileset: Texture2D
var tiles: Array = []
var level_size := LEVEL_SIZE
var level_names: Array = []
var tile_types = TArraysScript.new()
var b64_table: Dictionary = {}
var is_loading := false
var editor_loaded := false
var sprites_texture: Texture2D
var bush_leaps: Array = []
var thrown_bushes: Array = []
var bush_respawns: Array = []
var sound_cache: Dictionary = {}
var flower_time := 0.0
var flower_frame_time := 0.0
var flower_frame := 0

func _enter_tree() -> void:
	set_process(true)

func _ready() -> void:
	add_to_group("level")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_b64_table()
	sprites_texture = load("res://assets/images/sprites.png") as Texture2D
	load_level()
	set_process(true)

func _process(delta: float) -> void:
	if Engine.is_editor_hint() and not editor_loaded:
		editor_loaded = true
		_build_b64_table()
		load_level()
	flower_time += delta
	flower_frame_time += delta
	if flower_frame_time >= 0.05:
		flower_frame_time = 0.0
		flower_frame = (flower_frame + 1) % 4
		queue_redraw()
	if not bush_leaps.is_empty():
		for i in range(bush_leaps.size() - 1, -1, -1):
			var leap: Dictionary = bush_leaps[i]
			leap.age = float(leap.age) + delta
			leap.pos = Vector2(leap.pos) + Vector2(leap.vel) * delta
			leap.vel = Vector2(leap.vel) + Vector2(0, 360) * delta
			leap.rot = float(leap.rot) + float(leap.spin) * delta
			if float(leap.age) >= float(leap.life):
				bush_leaps.remove_at(i)
			else:
				bush_leaps[i] = leap
		queue_redraw()
	if not thrown_bushes.is_empty():
		for i in range(thrown_bushes.size() - 1, -1, -1):
			var thrown: Dictionary = thrown_bushes[i]
			thrown["age"] = float(thrown["age"]) + delta
			if float(thrown["age"]) >= THROW_DURATION:
				_land_thrown_bush(Vector2(thrown["end"]), str(thrown.get("type", "bush")))
				thrown_bushes.remove_at(i)
			else:
				thrown_bushes[i] = thrown
		queue_redraw()
	if not bush_respawns.is_empty():
		for i in range(bush_respawns.size() - 1, -1, -1):
			var respawn: Dictionary = bush_respawns[i]
			respawn["time"] = float(respawn["time"]) - delta
			if float(respawn["time"]) <= 0.0:
				_respawn_bush(respawn)
				bush_respawns.remove_at(i)
			else:
				bush_respawns[i] = respawn

func _exit_tree() -> void:
	if tile_types != null:
		tile_types.free()

func load_level() -> void:
	if is_loading:
		return
	is_loading = true
	level_size = LEVEL_SIZE
	_clear_tiles(level_size)
	tileset = load(tileset_path) as Texture2D
	if level_path.get_extension().to_lower() == "gmap":
		_load_gmap(level_path)
	elif not level_path.is_empty():
		_load_nw(level_path)
	is_loading = false
	queue_redraw()

func is_world_blocking(world_pos: Vector2) -> bool:
	var tile_type := get_world_tile_type(world_pos)
	return tile_type == 22 or tile_type == 20

func has_grab_target(world_pos: Vector2) -> bool:
	return is_world_blocking(world_pos) or not _find_lift_object_at_world(world_pos).is_empty()

func get_world_tile_type(world_pos: Vector2) -> int:
	var cell := Vector2i(floori(world_pos.x / TILE_SIZE), floori(world_pos.y / TILE_SIZE))
	if cell.x < 0 or cell.y < 0 or cell.x >= level_size.x or cell.y >= level_size.y:
		return 22
	var tile_index := int(tiles[cell.y][cell.x])
	if tile_index < 0:
		return 0
	var atlas := Vector2i(tile_index % 128, int(tile_index / 128))
	var tile_id := int(atlas.x / 16.0) * 512 + (atlas.x % 16) + (atlas.y * 16)
	return int(tile_types.TYPE0TILES.get(tile_id, 0))

func get_world_pixel_size() -> Vector2:
	return Vector2(level_size * TILE_SIZE)

func _draw() -> void:
	if tileset == null:
		return
	for y in range(level_size.y):
		for x in range(level_size.x):
			var tile_index := int(tiles[y][x])
			if tile_index < 0:
				continue
			tile_index = _get_draw_tile_index(tile_index, Vector2i(x, y))
			var atlas := Vector2i(tile_index % 128, int(tile_index / 128))
			draw_texture_rect_region(tileset, Rect2(Vector2(x, y) * TILE_SIZE, Vector2(TILE_SIZE, TILE_SIZE)), Rect2(Vector2(atlas) * TILE_SIZE, Vector2(TILE_SIZE, TILE_SIZE)))
	if sprites_texture != null:
		for leap in bush_leaps:
			var src: Rect2 = leap.src
			var xf := Transform2D(float(leap.rot), Vector2(leap.pos))
			draw_set_transform_matrix(xf)
			draw_texture_rect_region(sprites_texture, Rect2(src.size * -0.5, src.size), src)
		draw_set_transform_matrix(Transform2D())

func _get_draw_tile_index(tile_index: int, cell: Vector2i) -> int:
	if FLOWER_TILE_FRAMES.has(tile_index):
		var frames: Array = FLOWER_TILE_FRAMES[tile_index]
		var frame_time := FLOWER_FRAME_TIME + float(posmod(cell.x * 17 + cell.y * 31, 7)) * 0.018
		var frame_offset := float(posmod(cell.x * 43 + cell.y * 19, 23)) * 0.037
		return int(frames[int(floor((flower_time + frame_offset) / frame_time)) % frames.size()])
	return tile_index

func try_slay_bush(world_pos: Vector2) -> bool:
	var match_data := _find_bush_at_world(world_pos)
	if match_data.is_empty():
		return false
	_replace_bush(match_data)
	_spawn_leaps(Vector2(match_data["origin"]) * TILE_SIZE + Vector2(TILE_SIZE, TILE_SIZE), "bush")
	_play_sound(bush_land_sound, "steps2.wav")
	return true

func try_lift_bush(world_pos: Vector2) -> String:
	var match_data := _find_lift_object_at_world(world_pos)
	if match_data.is_empty():
		return ""
	_replace_bush(match_data)
	queue_redraw()
	return str(match_data.get("type", "bush"))

func throw_bush(world_pos: Vector2, direction: int, item_type: String = "bush") -> void:
	direction = clampi(direction, 0, 3)
	var fly: Vector3 = THROW_FLY[direction]
	var end := world_pos + Vector2(fly.x, fly.y) * TILE_SIZE * 9.0
	thrown_bushes.append({"start": world_pos, "end": end, "age": 0.0, "type": item_type})
	queue_redraw()

func _land_thrown_bush(world_pos: Vector2, item_type: String = "bush") -> void:
	if get_world_tile_type(world_pos) == 11:
		_play_sound("water.wav", "steps2.wav")
		return
	_spawn_leaps(world_pos, item_type)
	_play_sound(bush_land_sound, "steps2.wav")

func _find_bush_at_world(world_pos: Vector2) -> Dictionary:
	var match_data := _find_lift_object_at_world(world_pos)
	if str(match_data.get("type", "")) == "bush":
		return match_data
	return {}

func _find_lift_object_at_world(world_pos: Vector2) -> Dictionary:
	var cell := Vector2i(floori(world_pos.x / TILE_SIZE), floori(world_pos.y / TILE_SIZE))
	for ox in range(2):
		for oy in range(2):
			var origin := cell - Vector2i(ox, oy)
			var match_data := _find_lift_object_at_origin(origin)
			if not match_data.is_empty():
				return match_data
	return {}

func _find_bush_at_origin(origin: Vector2i) -> Dictionary:
	var match_data := _find_lift_object_at_origin(origin)
	if str(match_data.get("type", "")) == "bush":
		return match_data
	return {}

func _find_lift_object_at_origin(origin: Vector2i) -> Dictionary:
	if origin.x < 0 or origin.y < 0 or origin.x + 1 >= level_size.x or origin.y + 1 >= level_size.y:
		return {}
	var current := [int(tiles[origin.y][origin.x]), int(tiles[origin.y + 1][origin.x]), int(tiles[origin.y][origin.x + 1]), int(tiles[origin.y + 1][origin.x + 1])]
	for item in LIFT_OBJECTS:
		if current == item["tiles"]:
			return {"origin": origin, "type": item["type"], "tiles": item["tiles"], "replace": item["replace"]}
	return {}

func _replace_bush(match_data: Dictionary) -> void:
	var origin: Vector2i = match_data["origin"]
	var replacement: Array = match_data["replace"]
	tiles[origin.y][origin.x] = replacement[0]
	tiles[origin.y + 1][origin.x] = replacement[1]
	tiles[origin.y][origin.x + 1] = replacement[2]
	tiles[origin.y + 1][origin.x + 1] = replacement[3]
	_schedule_bush_respawn(origin, match_data["tiles"], replacement)
	queue_redraw()

func _schedule_bush_respawn(origin: Vector2i, source_tiles: Array, replacement: Array) -> void:
	for i in range(bush_respawns.size() - 1, -1, -1):
		if Vector2i(bush_respawns[i]["origin"]) == origin:
			bush_respawns.remove_at(i)
	bush_respawns.append({"origin": origin, "tiles": source_tiles.duplicate(), "replace": replacement.duplicate(), "time": bush_respawn_seconds})

func _respawn_bush(respawn: Dictionary) -> void:
	var origin: Vector2i = respawn["origin"]
	if origin.x < 0 or origin.y < 0 or origin.x + 1 >= level_size.x or origin.y + 1 >= level_size.y:
		return
	var replacement: Array = respawn["replace"]
	var current := [int(tiles[origin.y][origin.x]), int(tiles[origin.y + 1][origin.x]), int(tiles[origin.y][origin.x + 1]), int(tiles[origin.y + 1][origin.x + 1])]
	if current != replacement:
		return
	var source_tiles: Array = respawn["tiles"]
	tiles[origin.y][origin.x] = source_tiles[0]
	tiles[origin.y + 1][origin.x] = source_tiles[1]
	tiles[origin.y][origin.x + 1] = source_tiles[2]
	tiles[origin.y + 1][origin.x + 1] = source_tiles[3]
	queue_redraw()

func _spawn_leaps(center: Vector2, item_type: String = "bush") -> void:
	var rects: Array = LEAP_RECTS.get(item_type, LEAP_RECTS["bush"])
	if item_type != "bush":
		_spawn_break_leaps(center, rects)
		return
	for i in range(4):
		var angle := randf_range(-PI, PI)
		var speed := randf_range(55.0, 115.0)
		bush_leaps.append({
			"pos": center + Vector2(randf_range(-5.0, 5.0), randf_range(-4.0, 3.0)),
			"vel": Vector2(cos(angle), sin(angle)) * speed + Vector2(0, randf_range(-80.0, -30.0)),
			"src": rects.pick_random(),
			"age": 0.0,
			"life": randf_range(0.24, 0.36),
			"rot": randf_range(-PI, PI),
			"spin": randf_range(-6.0, 6.0)
		})

func _spawn_break_leaps(center: Vector2, rects: Array) -> void:
	var offsets := [Vector2(-4, -4), Vector2(4, -4), Vector2(-4, 4), Vector2(4, 4)]
	var velocities := [Vector2(-70, -105), Vector2(70, -105), Vector2(-70, -65), Vector2(70, -65)]
	for i in range(min(rects.size(), 4)):
		bush_leaps.append({
			"pos": center + offsets[i],
			"vel": velocities[i],
			"src": rects[i],
			"age": 0.0,
			"life": 0.42,
			"rot": 0.0,
			"spin": 0.0
		})

func _play_sound(primary_name: String, fallback_name: String = "") -> void:
	var stream := _get_sound_stream(primary_name)
	if stream == null and not fallback_name.is_empty():
		stream = _get_sound_stream(fallback_name)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = -2.0
	add_child(player)
	player.play()
	player.finished.connect(func(): player.queue_free())

func _get_sound_stream(file_name: String) -> AudioStream:
	if file_name.is_empty():
		return null
	var path := sound_dir.path_join(file_name.get_file())
	if not ResourceLoader.exists(path):
		return null
	if sound_cache.has(path):
		return sound_cache[path]
	var stream := load(path) as AudioStream
	if stream != null:
		sound_cache[path] = stream
	return stream

func _clear_tiles(size: Vector2i) -> void:
	tiles.clear()
	for y in range(size.y):
		var row: Array[int] = []
		for x in range(size.x):
			row.append(-1)
		tiles.append(row)

func _load_nw(path: String, offset: Vector2i = Vector2i.ZERO, update_tileset: bool = true) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	while not file.eof_reached():
		var line := file.get_line()
		if line.begins_with("TILESET ") or line.begins_with("TILESETIMAGE "):
			var parts := line.split(" ", false)
			if update_tileset and parts.size() >= 2:
				tileset_path = _resolve_level_asset(parts[1])
				tileset = load(tileset_path) as Texture2D
		elif line.begins_with("BOARD "):
			_read_board_line(line, offset)

func _load_gmap(path: String) -> void:
	level_names.clear()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var reading_names := false
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line == "LEVELNAMESEND":
			reading_names = false
		elif reading_names:
			var row: Array[String] = []
			for name in line.split(",", false):
				row.append(str(name).strip_edges().trim_prefix("\"").trim_suffix("\""))
			level_names.append(row)
		elif line == "LEVELNAMES":
			reading_names = true
		elif line.begins_with("WIDTH "):
			level_size.x = max(1, int(line.split(" ", false)[1])) * LEVEL_SIZE.x
		elif line.begins_with("HEIGHT "):
			level_size.y = max(1, int(line.split(" ", false)[1])) * LEVEL_SIZE.y
		elif line.begins_with("TILESET ") or line.begins_with("TILESETIMAGE "):
			var parts := line.split(" ", false)
			if parts.size() >= 2:
				tileset_path = _resolve_level_asset(parts[1])
				tileset = load(tileset_path) as Texture2D
	if level_names.size() == 0:
		return
	var grid_width := 0
	for row in level_names:
		grid_width = max(grid_width, row.size())
	level_size = Vector2i(max(level_size.x, grid_width * LEVEL_SIZE.x), max(level_size.y, level_names.size() * LEVEL_SIZE.y))
	_clear_tiles(level_size)
	for cell_y in range(level_names.size()):
		var row: Array = level_names[cell_y]
		for cell_x in range(row.size()):
			var member_name := str(row[cell_x]).strip_edges()
			if member_name.is_empty():
				continue
			var member_path := _resolve_level_asset(member_name)
			_load_nw(member_path, Vector2i(cell_x * LEVEL_SIZE.x, cell_y * LEVEL_SIZE.y), false)

func _read_board_line(line: String, offset: Vector2i = Vector2i.ZERO) -> void:
	var parts := line.split(" ", false)
	if parts.size() < 6:
		return
	var start_x := int(parts[1])
	var y := int(parts[2])
	var width := int(parts[3])
	var layer := int(parts[4])
	var tiledata := parts[5]
	if layer != 0:
		return
	for i in range(width):
		var x := offset.x + start_x + i
		var world_y := offset.y + y
		if x < 0 or world_y < 0 or x >= level_size.x or world_y >= level_size.y or i * 2 + 2 > tiledata.length():
			continue
		var tile_index := _decode_nw_tile_index(tiledata.substr(i * 2, 2))
		if tile_index >= 0:
			tiles[world_y][x] = tile_index

func _decode_nw_tile_index(tile_code: String) -> int:
	if tile_code.length() < 2 or tile_code == "//":
		return -1
	var a := tile_code.substr(0, 1)
	var b := tile_code.substr(1, 1)
	if not b64_table.has(a) or not b64_table.has(b):
		return -1
	var g := int(b64_table[a]) * 64 + int(b64_table[b])
	var packed_y := int(g / 16)
	var tx := (g & 0xF) + 16 * int(packed_y / 32)
	var ty := packed_y % 32
	return ty * 128 + tx

func _build_b64_table() -> void:
	b64_table.clear()
	var chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i in range(chars.length()):
		b64_table[chars[i]] = i
		b64_table[chars.substr(i, 1)] = i

func _resolve_level_asset(file_name: String) -> String:
	if file_name.begins_with("res://") or file_name.is_absolute_path():
		return file_name
	var level_relative := level_path.get_base_dir().path_join(file_name.get_file())
	if FileAccess.file_exists(level_relative):
		return level_relative
	var tileset_relative := tileset_dir.path_join(file_name.get_file())
	if FileAccess.file_exists(tileset_relative):
		return tileset_relative
	return level_relative
