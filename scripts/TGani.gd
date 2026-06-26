class_name TGani
extends RefCounted
var sprites = {}
var frames = []
var is_looped = false
var is_continuous = false
var next_ani = ""
var is_single_dir = false
var default_images = {}
var zoom := 1.0
var actors = {}
var scripts = []
var script_code := ""
func _init() -> void: pass
func load_from_file(file_path: String) -> bool:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if !file: return false
	var lines = []
	while !file.eof_reached(): lines.append(file.get_line())
	var ok := parse_lines(lines)
	var code_path := file_path.get_basename() + ".code"
	if FileAccess.file_exists(code_path):
		var code_file = FileAccess.open(code_path, FileAccess.READ)
		if code_file:
			script_code = code_file.get_as_text()
	return ok
	
func parse_lines(lines: Array) -> bool:
	var in_ani_section = false
	var current_frame = {}
	var expecting_direction = 0
	for line_text in lines:
		line_text = line_text.strip_edges()
		if line_text.is_empty():
			if in_ani_section and !current_frame.is_empty():
				current_frame = {}
				expecting_direction = 0
			continue
		var parts = line_text.split(" ", false)
		if parts.size() == 0: continue
		var keyword = parts[0].to_upper()
		match keyword:
			"SPRITE":
				if parts.size() >= 7:
					var sprite_id = int(parts[1])
					var sprite_type = parts[2].to_upper()
					var left = int(parts[3])
					var top = int(parts[4])
					var width = int(parts[5])
					var height = int(parts[6])
					var comment = ""
					if parts.size() > 7: comment = line_text.substr(line_text.find(parts[7]))
					var resolved_type = sprite_type if is_default_type(sprite_type) else "CUSTOM"
					sprites[sprite_id] = {
						"type": resolved_type,
						"left": left, "top": top, "width": width, "height": height,
						"comment": comment,
						"custom_image": parts[2] if resolved_type == "CUSTOM" else "",
						"rotation": 0.0, "xscale": 1.0, "yscale": 1.0,
						"color_effect_enabled": false, "color_effect": Color.WHITE,
						"attachments": []
					}
			"ATTACHSPRITE", "ATTACHSPRITEM":
				if parts.size() >= 5:
					var target_id = int(parts[1])
					if sprites.has(target_id):
						sprites[target_id]["attachments"].append({"sprite_id": int(parts[2]), "x_offset": int(parts[3]), "y_offset": int(parts[4]), "mirror": keyword == "ATTACHSPRITEM"})
			"LOOP": is_looped = true
			"CONTINUOUS": is_continuous = true
			"SETBACKTO": if parts.size() >= 2: next_ani = parts[1]
			"SINGLEDIR", "SINGLEDIRECTION": is_single_dir = true
			"ZOOM": if parts.size() >= 2: zoom = float(parts[1])
			"ACTOR":
				if parts.size() >= 2:
					var actor_id = int(parts[1])
					if !actors.has(actor_id): actors[actor_id] = []
					actors[actor_id].append(parts.slice(2))
			"ROTATEEFFECT":
				if parts.size() >= 3:
					var sprite_id = int(parts[1])
					if sprites.has(sprite_id):
						sprites[sprite_id].rotation = rad_to_deg(float(parts[2]))
			"STRETCHXEFFECT":
				if parts.size() >= 3:
					var sprite_id = int(parts[1])
					if sprites.has(sprite_id):
						sprites[sprite_id].xscale = float(parts[2])
			"STRETCHYEFFECT":
				if parts.size() >= 3:
					var sprite_id = int(parts[1])
					if sprites.has(sprite_id):
						sprites[sprite_id].yscale = float(parts[2])
			"COLOREFFECT":
				if parts.size() >= 6:
					var sprite_id = int(parts[1])
					if sprites.has(sprite_id):
						sprites[sprite_id].color_effect_enabled = true
						sprites[sprite_id].color_effect = Color(
							float(parts[2]),
							float(parts[3]),
							float(parts[4]),
							float(parts[5])
						)
			"ANI": 
				if parts.size() > 1:
					current_frame = _ensure_frame(current_frame, expecting_direction)
					_parse_piece_line(line_text.substr(line_text.find(parts[1])), current_frame, expecting_direction)
					expecting_direction += 1
				else:
					in_ani_section = true
					expecting_direction = 0
			"FRAME":
				current_frame = {"pieces": [[],[],[],[]], "duration": 50, "sounds": [], "scripts": []}
				frames.append(current_frame)
				if parts.size() > 1:
					_parse_piece_line(line_text.substr(line_text.find(parts[1])), current_frame, 0)
				expecting_direction = 1
			"ANIEND": in_ani_section = false
			_:
				if keyword.begins_with("DEFAULT") and parts.size() >= 2:
					var type = keyword.substr(7)
					var value = parts[1]
					default_images[type] = value
				elif (keyword.begins_with("PARAM") or keyword.begins_with("ATTR")) and parts.size() >= 2:
					default_images[keyword] = parts[1]
				elif in_ani_section:
					if keyword.begins_with("WAIT") and !current_frame.is_empty():
						var wait_count = int(parts[1]) if parts.size() >= 2 else int(keyword.substr(4))
						current_frame.duration += wait_count * 50
					elif keyword == "PLAYSOUND" and parts.size() >= 4:
						var target_frame = current_frame
						if target_frame.is_empty() or expecting_direction >= 4:
							if frames.size() > 1:
								target_frame = frames[frames.size() - 2]
							elif frames.size() == 1:
								target_frame = frames[0]
						if !target_frame.is_empty():
							if !target_frame.has("sounds"): target_frame.sounds = []
							target_frame.sounds.append({
								"file": parts[1],
								"x": float(parts[2]) * 16,
								"y": float(parts[3]) * 16
							})
					elif keyword == "SCRIPT":
						var target_frame = current_frame
						if target_frame.is_empty() or expecting_direction >= 4:
							target_frame = frames[frames.size() - 1] if frames.size() > 0 else {}
						if !target_frame.is_empty():
							if !target_frame.has("scripts"): target_frame.scripts = []
							var script_text = line_text.substr(line_text.find(parts[1])) if parts.size() > 1 else ""
							target_frame.scripts.append(script_text)
							scripts.append(script_text)
					else:
						current_frame = _ensure_frame(current_frame, expecting_direction)
						if expecting_direction >= 4:
							current_frame = {"pieces": [[],[],[],[]], "duration": 50, "sounds": [], "scripts": []}
							frames.append(current_frame)
							expecting_direction = 0
						_parse_piece_line(line_text, current_frame, expecting_direction)
						expecting_direction += 1
						
						if is_single_dir:
							for i in range(1, 4):
								current_frame.pieces[i] = current_frame.pieces[0].duplicate(true)
							expecting_direction = 4
	
	ensure_default_images()
	
	if is_single_dir:
		for frame in frames:
			for i in range(1, 4):
				frame.pieces[i] = frame.pieces[0].duplicate(true)
	
	return true

func _ensure_frame(current_frame: Dictionary, expecting_direction: int) -> Dictionary:
	if current_frame.is_empty() or expecting_direction >= 4:
		current_frame = {"pieces": [[],[],[],[]], "duration": 50, "sounds": [], "scripts": []}
		frames.append(current_frame)
	return current_frame

func _parse_piece_line(line_text: String, frame: Dictionary, dir: int) -> void:
	if dir < 0 or dir >= 4:
		return
	var sprite_pieces = line_text.split(",", false)
	for piece_text in sprite_pieces:
		var piece_parts = piece_text.strip_edges().split(" ", false)
		if piece_parts.size() >= 3:
			frame.pieces[dir].append({
				"sprite_id": int(piece_parts[0]),
				"x_offset": int(piece_parts[1]),
				"y_offset": int(piece_parts[2]),
				"xscale": float(piece_parts[3]) if piece_parts.size() >= 4 else 1.0,
				"yscale": float(piece_parts[4]) if piece_parts.size() >= 5 else 1.0,
				"rotation": float(piece_parts[5]) if piece_parts.size() >= 6 else 0.0,
				"zoom": float(piece_parts[6]) if piece_parts.size() >= 7 else 1.0
			})
	
func ensure_default_images() -> void:
	var required_defaults = {
		"SPRITES": "sprites.png",
		"ATTR1": "",
		"HEAD": "head0.png",
		"BODY": "body.png",
		"SHIELD": "shield1.png",
		"SWORD": "sword1.png"
	}
	
	for type in required_defaults:
		if type == "ATTR1":
			# Engine rule: ATTR1 stays empty unless gameplay/script code sets it.
			default_images[type] = required_defaults[type]
		elif type == "HEAD":
			# Engine rule: default head is owned by the engine, not the GANI file.
			default_images[type] = required_defaults[type]
		elif !default_images.has(type):
			default_images[type] = required_defaults[type]
			
func is_default_type(type: String) -> bool:
	type = type.to_upper()
	return type in ["SPRITES", "PICS", "HEAD", "BODY", "SWORD", "SHIELD", "HORSE"] or type.begins_with("ATTR") or type.begins_with("PARAM")
func get_frame_count() -> int: return frames.size()
func get_frame(index: int) -> Dictionary: return frames[index] if index >= 0 and index < frames.size() else {}
func get_sprite(id: int) -> Dictionary: return sprites[id] if id in sprites else {}
func get_default_image(type: String) -> String: return default_images[type] if type in default_images else ""

func draw(node: CanvasItem, direction: int, frame_index: int, texture_cache: Dictionary, offset: Vector2 = Vector2.ZERO) -> void:
	var frame = get_frame(frame_index)
	if frame.is_empty(): return
	
	var dir = 0 if is_single_dir else direction
	if dir < 0 or dir >= 4 or dir >= frame.pieces.size(): return
		
	var pieces = frame.pieces[dir]
	
	for piece in pieces:
		_draw_piece(node, piece, texture_cache, offset, {})

func _draw_piece(node: CanvasItem, piece: Dictionary, texture_cache: Dictionary, offset: Vector2, visited: Dictionary) -> void:
	if !piece.has("sprite_id"): return
	var sprite_id = int(piece.sprite_id)
	if visited.has(sprite_id): return
	var sprite = get_sprite(sprite_id)
	if sprite.is_empty(): return
	visited[sprite_id] = true
	var texture = null
	var sprite_type = str(sprite.type)
	if sprite_type == "CUSTOM" and sprite.custom_image != "": texture = texture_cache.get(str(sprite_id))
	elif sprite_type in texture_cache: texture = texture_cache[sprite_type]
	if texture:
		var x_offset = float(piece.x_offset)
		var y_offset = float(piece.y_offset)
		var src_rect = Rect2(sprite.left, sprite.top, sprite.width, sprite.height)
		var pos = Vector2(x_offset, y_offset) + offset
		var xscale = float(sprite.xscale) * float(piece.get("xscale", 1.0)) * float(piece.get("zoom", 1.0)) * zoom
		var yscale = float(sprite.yscale) * float(piece.get("yscale", 1.0)) * float(piece.get("zoom", 1.0)) * zoom
		if bool(piece.get("mirror", false)): xscale *= -1.0
		var rotation = float(sprite.rotation) + float(piece.get("rotation", 0.0))
		_draw_sprite(node, texture, src_rect, pos, Vector2(sprite.width, sprite.height), xscale, yscale, rotation, sprite.color_effect if sprite.color_effect_enabled else Color.WHITE)
	for attachment in sprite.get("attachments", []):
		var attached = attachment.duplicate()
		attached["x_offset"] = float(piece.get("x_offset", 0.0)) + float(attachment.get("x_offset", 0.0))
		attached["y_offset"] = float(piece.get("y_offset", 0.0)) + float(attachment.get("y_offset", 0.0))
		_draw_piece(node, attached, texture_cache, offset, visited.duplicate())

func _draw_sprite(node: CanvasItem, texture, src_rect: Rect2, pos: Vector2, size: Vector2, xscale: float, yscale: float, rotation: float, color: Color) -> void:
	if rotation == 0 and xscale == 1 and yscale == 1:
		node.draw_texture_rect_region(texture, Rect2(pos, size), src_rect, color)
	else:
		var sprite_transform = Transform2D()
		sprite_transform = sprite_transform.translated(pos + size * 0.5)
		sprite_transform = sprite_transform.scaled(Vector2(xscale, yscale))
		sprite_transform = sprite_transform.rotated(rotation * PI/180)
		sprite_transform = sprite_transform.translated(-size * 0.5)
		node.draw_set_transform_matrix(sprite_transform)
		node.draw_texture_rect_region(texture, Rect2(Vector2.ZERO, size), src_rect, color)
		node.draw_set_transform_matrix(Transform2D())
