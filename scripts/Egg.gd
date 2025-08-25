# res://scripts/Egg.gd
extends Sprite2D

# ───────── Config general
@export var broken_texture: Texture2D          # Asigna egg_xeno_broken.png en el Inspector
@export var drag_scale: float = 1.15           # Escala mientras arrastras
@export var drag_shake_amp: float = 2.0        # Amplitud del “tembleque” al arrastrar
@export var screen_margin: float = 0.0         # Margen al clamp con el viewport

# ───────── Tiempos de eclosión (total ≈ 120 s por defecto)
@export var t_phase1_quiet: float   = 30.0
@export var t_phase2_build: float   = 30.0
@export var t_phase3_broken: float  = 30.0
@export var t_phase4_hectic: float  = 30.0

# ───────── Wobble vertical (px) y giro (grados) por fase — “anclado abajo”
@export var wobble_quiet_amp: float = 2.5
@export var wobble_build_amp: float = 6.5
@export var wobble_broken_amp: float = 1.6
@export var wobble_hectic_amp: float = 11.0

@export var rot_quiet_deg: float   = 2.0
@export var rot_build_deg: float   = 6.0
@export var rot_broken_deg: float  = 1.0
@export var rot_hectic_deg: float  = 10.0

# Velocidad relativa del temblor por fase
@export var speed_quiet: float   = 1.5
@export var speed_build: float   = 2.3
@export var speed_broken: float  = 1.8
@export var speed_hectic: float  = 3.2

# ───────── Integración Creature
@export var creature_path: NodePath            # (Opcional) arrastra Main/Creature
var creature_node: Sprite2D

# ───────── Internos
enum Stage { QUIET, BUILD, BROKEN, HECTIC, HATCHED }
var _stage: Stage = Stage.QUIET
var _timer: float = 0.0
var _dragging: bool = false
var _grab_offset: Vector2 = Vector2.ZERO
var _base_scale: Vector2
var _rng := RandomNumberGenerator.new()

# Posición de reposo para el “anclado abajo”
var _rest_pos: Vector2

func _ready() -> void:
	_rng.randomize()
	_base_scale = scale
	_rest_pos = global_position

	# Creature opcional
	if creature_path != NodePath():
		creature_node = get_node_or_null(creature_path)
	else:
		creature_node = get_tree().current_scene.get_node_or_null("Creature")
	if creature_node:
		creature_node.visible = false

	visible = true
	modulate.a = 1.0
	rotation = 0.0

func start_lifecycle(spawn_pos: Vector2) -> void:
	# Llamado por BitsManager al finalizar ritual.
	_rest_pos = spawn_pos
	global_position = _rest_pos
	visible = true
	_stage = Stage.QUIET
	_timer = 0.0
	scale = _base_scale
	rotation = 0.0
	# La textura “normal” ya la pones en el editor.

func _process(delta: float) -> void:
	_timer += delta

	match _stage:
		Stage.QUIET:
			_apply_wobble_anchored(wobble_quiet_amp, rot_quiet_deg, speed_quiet)
			if _timer >= t_phase1_quiet:
				_next_stage(Stage.BUILD)
		Stage.BUILD:
			_apply_wobble_anchored(wobble_build_amp, rot_build_deg, speed_build)
			if _timer >= t_phase1_quiet + t_phase2_build:
				_break_egg()
		Stage.BROKEN:
			_apply_wobble_anchored(wobble_broken_amp, rot_broken_deg, speed_broken)
			if _timer >= t_phase1_quiet + t_phase2_build + t_phase3_broken:
				_next_stage(Stage.HECTIC)
		Stage.HECTIC:
			_apply_wobble_anchored(wobble_hectic_amp, rot_hectic_deg, speed_hectic)
			if _timer >= t_phase1_quiet + t_phase2_build + t_phase3_broken + t_phase4_hectic:
				_hatch()
		Stage.HATCHED:
			pass

	# Arrastre con clamp a pantalla
	if _dragging:
		var vp: Vector2 = get_viewport_rect().size
		var target: Vector2 = (get_viewport().get_mouse_position() - _grab_offset)
		target.x = clamp(target.x, screen_margin, vp.x - screen_margin)
		target.y = clamp(target.y, screen_margin, vp.y - screen_margin)
		global_position = target + _drag_shake()

func _unhandled_input(event: InputEvent) -> void:
	# Ratón
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _is_mouse_over():
				_dragging = true
				_grab_offset = get_viewport().get_mouse_position() - global_position
				_tween_scale(scale, _base_scale * drag_scale, 0.08)
		else:
			if _dragging:
				_dragging = false
				_tween_scale(scale, _base_scale, 0.12)
				_rest_pos = global_position    # nueva “base” tras soltar
				rotation = 0.0                 # al soltar, recto

	# Táctil
	if event is InputEventScreenTouch:
		if event.pressed and _is_touch_over(event.position):
			_dragging = true
			_grab_offset = event.position - global_position
			_tween_scale(scale, _base_scale * drag_scale, 0.08)
		elif not event.pressed and _dragging:
			_dragging = false
			_tween_scale(scale, _base_scale, 0.12)
			_rest_pos = global_position
			rotation = 0.0

# ───────── Wobble “anclado abajo”
func _apply_wobble_anchored(amp_px: float, rot_deg: float, speed: float) -> void:
	if _dragging:
		return  # si estás arrastrando, no imponemos el “anclado”

	var tex := texture
	if tex == null:
		return

	var t: float = Time.get_ticks_msec() / 1000.0
	var angle_rad: float = sin(t * TAU * (speed * 0.8)) * deg_to_rad(rot_deg)
	var bob: float = abs(sin(t * TAU * (speed * 0.62))) * amp_px

	# Longitud de centro → borde inferior (en píxeles de pantalla)
	var half_h: float = (tex.get_size().y * 0.5) * abs(scale.y)

	# Corrección de ancla: v - R(θ)*v, con v = (0, half_h)
	var v: Vector2 = Vector2(0.0, half_h)
	var anchor_correction: Vector2 = v - v.rotated(angle_rad)

	# Posición final = base + corrección por ancla + empuje hacia arriba
	global_position = _rest_pos + anchor_correction + Vector2(0.0, -bob)
	rotation = angle_rad

func _drag_shake() -> Vector2:
	return Vector2(
		_rng.randf_range(-drag_shake_amp, drag_shake_amp),
		_rng.randf_range(-drag_shake_amp, drag_shake_amp)
	)

# ───────── Transiciones de estado
func _break_egg() -> void:
	_next_stage(Stage.BROKEN)
	if broken_texture:
		texture = broken_texture
	rotation = 0.0

func _hatch() -> void:
	_next_stage(Stage.HATCHED)
	# Usa el mismo espacio de canvas para evitar desajustes por capas
	var spawn_canvas_pos: Vector2 = get_global_transform_with_canvas().origin
	visible = false
	rotation = 0.0

	if creature_node:
		creature_node.global_position = spawn_canvas_pos
		creature_node.visible = true
		creature_node.modulate.a = 1.0
		creature_node.scale = Vector2.ONE

func _next_stage(s: Stage) -> void:
	_stage = s

# ───────── Utilidades
func _tween_scale(from_s: Vector2, to_s: Vector2, secs: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", to_s, secs).from(from_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _is_mouse_over() -> bool:
	var tex := texture
	if tex == null: return false
	var local: Vector2 = to_local(get_viewport().get_mouse_position())
	var rect := Rect2(Vector2.ZERO - tex.get_size() * 0.5, tex.get_size())
	return rect.has_point(local)

func _is_touch_over(pos: Vector2) -> bool:
	var tex := texture
	if tex == null: return false
	var local: Vector2 = to_local(pos)
	var rect := Rect2(Vector2.ZERO - tex.get_size() * 0.5, tex.get_size())
	return rect.has_point(local)
