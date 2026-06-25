class_name TGani
extends RefCounted
var sprites = {}
var frames = []
var is_looped = false
var is_continuous = false
var next_ani = ""
var is_single_dir = false
var default_images = {}
func _init() -> void: pass
func load_from_file(file_path: String) -> bool:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if !file: return false
	var lines = []
	while !file.eof_reached(): lines.append(file.get_line())
	return parse_lines(lines)
	
func parse_lines(lines: Array) -> bool:
	var in_ani_section = false
	var current_frame = {}
	var expecting_direction = 0
	for line_text in lines:
		line_text = line_text.strip_edges()
		if line_text.is_empty(): continue
		var parts = line_text.split(" ", false)
		if parts.size() == 0: continue
		var keyword = parts[0]
		match keyword:
			"SPRITE":
				if parts.size() >= 7:
					var sprite_id = int(parts[1])
					var sprite_type = parts[2]
					var left = int(parts[3])
					var top = int(parts[4])
					var width = int(parts[5])
					var height = int(parts[6])
					var comment = ""
					if parts.size() > 7: comment = line_text.substr(line_text.find(parts[7]))
					sprites[sprite_id] = {
						"type": sprite_type if is_default_type(sprite_type) else "CUSTOM",
						"left": left, "top": top, "width": width, "height": height,
						"comment": comment,
						"custom_image": sprite_type if !is_default_type(sprite_type) else "",
						"rotation": 0.0, "xscale": 1.0, "yscale": 1.0,
						"color_effect_enabled": false, "color_effect": Color.WHITE
					}
			"LOOP": is_looped = true
			"CONTINUOUS": is_continuous = true
			"SETBACKTO": if parts.size() >= 2: next_ani = parts[1]
			"SINGLEDIR", "SINGLEDIRECTION": is_single_dir = true
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
				in_ani_section = true
				expecting_direction = 0
			"ANIEND": in_ani_section = false
			_:
				if keyword.begins_with("DEFAULT") and parts.size() >= 2:
					var type = keyword.substr(7)
					var value = parts[1]
					default_images[type] = value
				elif in_ani_section:
					if line_text == "":
						if !current_frame.is_empty():
							current_frame = {}
							expecting_direction = 0
					elif keyword == "WAIT" and !current_frame.is_empty() and parts.size() >= 2:
						current_frame.duration += int(parts[1]) * 50
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
					else:
						if current_frame.is_empty():
							current_frame = {"pieces": [[],[],[],[]], "duration": 50, "sounds": []}
							frames.append(current_frame)
							expecting_direction = 0
						
						if expecting_direction >= 4:
							current_frame = {"pieces": [[],[],[],[]], "duration": 50, "sounds": []}
							frames.append(current_frame)
							expecting_direction = 0
						
						var sprite_pieces = line_text.split(",", false)
						for piece_text in sprite_pieces:
							var piece_parts = piece_text.strip_edges().split(" ", false)
							if piece_parts.size() >= 3:
								var sprite_id = int(piece_parts[0])
								var x_offset = int(piece_parts[1])
								var y_offset = int(piece_parts[2])
								
								current_frame.pieces[expecting_direction].append({
									"sprite_id": sprite_id,
									"x_offset": x_offset,
									"y_offset": y_offset,
									"xscale": float(piece_parts[3]) if piece_parts.size() >= 4 else 1.0,
									"yscale": float(piece_parts[4]) if piece_parts.size() >= 5 else 1.0,
									"rotation": float(piece_parts[5]) if piece_parts.size() >= 6 else 0.0,
									"zoom": float(piece_parts[6]) if piece_parts.size() >= 7 else 1.0
								})
						
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
			
func is_default_type(type: String) -> bool: return type in ["SPRITES", "PICS", "HEAD", "BODY", "SWORD", "SHIELD", "HORSE", "ATTR1", "ATTR2", "ATTR3", "ATTR4", "ATTR5", "ATTR6", "ATTR7", "ATTR8", "ATTR9", "ATTR10"]
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
		if !piece.has("sprite_id"): continue
		
		var sprite_id = piece.sprite_id
		var sprite = get_sprite(sprite_id)
		if sprite.is_empty(): continue
		var texture = null
		var sprite_type = sprite.type

		if sprite_type == "CUSTOM" and sprite.custom_image != "": texture = texture_cache.get(str(sprite_id))
		elif sprite_type in texture_cache: texture = texture_cache[sprite_type]
		
		if !texture: continue
		
		var x_offset = piece.x_offset
		var y_offset = piece.y_offset
		var src_rect = Rect2(sprite.left, sprite.top, sprite.width, sprite.height)
		var pos = Vector2(x_offset, y_offset) + offset
		
		var xscale = float(sprite.xscale) * float(piece.get("xscale", 1.0)) * float(piece.get("zoom", 1.0))
		var yscale = float(sprite.yscale) * float(piece.get("yscale", 1.0)) * float(piece.get("zoom", 1.0))
		var rotation = float(sprite.rotation) + float(piece.get("rotation", 0.0))
		if rotation == 0 and xscale == 1 and yscale == 1:
			node.draw_texture_rect_region(
				texture, 
				Rect2(pos, Vector2(sprite.width, sprite.height)), 
				src_rect, 
				sprite.color_effect if sprite.color_effect_enabled else Color.WHITE
			)
		else:
			var sprite_transform = Transform2D()
			
			sprite_transform = sprite_transform.translated(pos + Vector2(sprite.width/2, sprite.height/2))
			sprite_transform = sprite_transform.scaled(Vector2(xscale, yscale))
			sprite_transform = sprite_transform.rotated(rotation * PI/180)
			sprite_transform = sprite_transform.translated(Vector2(-sprite.width/2, -sprite.height/2))
			
			node.draw_set_transform_matrix(sprite_transform)
			node.draw_texture_rect_region(
				texture, 
				Rect2(Vector2.ZERO, Vector2(sprite.width, sprite.height)), 
				src_rect, 
				sprite.color_effect if sprite.color_effect_enabled else Color.WHITE
			)
			node.draw_set_transform_matrix(Transform2D())
