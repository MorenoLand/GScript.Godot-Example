@tool
class_name TLevel
extends Node2D

const TILE_SIZE := 16
const LEVEL_SIZE := Vector2i(64, 64)
const TArraysScript = preload("res://scripts/TArrays.gd")

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

var tileset: Texture2D
var tiles: Array = []
var level_size := LEVEL_SIZE
var level_names: Array = []
var tile_types = TArraysScript.new()
var b64_table: Dictionary = {}
var is_loading := false
var editor_loaded := false

func _ready() -> void:
	add_to_group("level")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_b64_table()
	load_level()
	set_process(true)

func _process(delta: float) -> void:
	if Engine.is_editor_hint() and not editor_loaded:
		editor_loaded = true
		_build_b64_table()
		load_level()

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
			var atlas := Vector2i(tile_index % 128, int(tile_index / 128))
			draw_texture_rect_region(tileset, Rect2(Vector2(x, y) * TILE_SIZE, Vector2(TILE_SIZE, TILE_SIZE)), Rect2(Vector2(atlas) * TILE_SIZE, Vector2(TILE_SIZE, TILE_SIZE)))

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
