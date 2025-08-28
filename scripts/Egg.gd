extends Sprite2D

@export var broken_texture: Texture2D
@export var drag_scale: float = 1.15
@export var drag_shake_amp: float = 2.0
@export var screen_margin: float = 0.0
@export var auto_start: bool = false

@export var t_phase1_quiet: float   = 30.0
@export var t_phase2_build: float   = 30.0
@export var t_phase3_broken: float  = 30.0
@export var t_phase4_hectic: float  = 30.0

@export var wobble_quiet_amp: float  = 4.0
@export var wobble_build_amp: float  = 15.0
@export var wobble_broken_amp: float = 4.0
@export var wobble_hectic_amp: float = 15.0

@export var creature_path: NodePath
var creature_node: Sprite2D

enum Stage { QUIET, BUILD, BROKEN, HECTIC, HATCHED }
var _stage: Stage = Stage.QUIET
var _timer: float = 0.0
var _dragging: bool = false
var _grab_offset: Vector2 = Vector2.ZERO
var _base_scale: Vector2 = Vector2.ONE
var _rng := RandomNumberGenerator.new()
var _active: bool = false
var _orig_texture: Texture2D

func _ready() -> void:
	_rng.randomize()
	_base_scale = scale
	_orig_texture = texture

	if creature_path != NodePath():
		creature_node = get_node_or_null(creature_path)
	else:
		creature_node = get_tree().current_scene.get_node_or_null("Creature")
	if creature_node:
		creature_node.visible = false

	_active = auto_start
	_timer = 0.0
	_stage = Stage.QUIET
	if not _active:
		visible = false
		if _orig_texture:
			texture = _orig_texture

func start_lifecycle(spawn_pos: Vector2) -> void:
	global_position = spawn_pos
	visible = true
	_active = true
	_stage = Stage.QUIET
	_timer = 0.0
	scale = _base_scale
	rotation = 0.0
	if _orig_texture:
		texture = _orig_texture

func _process(delta: float) -> void:
	if not _active:
		return

	_timer += delta

	match _stage:
		Stage.QUIET:
			_apply_anchor_wobble(wobble_quiet_amp, 1.3)
			if _timer >= t_phase1_quiet:
				_next_stage(Stage.BUILD)
		Stage.BUILD:
			_apply_anchor_wobble(wobble_build_amp, 2.0)
			if _timer >= t_phase1_quiet + t_phase2_build:
				_break_egg()
		Stage.BROKEN:
			_apply_anchor_wobble(wobble_broken_amp, 1.5)
			if _timer >= t_phase1_quiet + t_phase2_build + t_phase3_broken:
				_next_stage(Stage.HECTIC)
		Stage.HECTIC:
			_apply_anchor_wobble(wobble_hectic_amp, 3.0)
			if _timer >= t_phase1_quiet + t_phase2_build + t_phase3_broken + t_phase4_hectic:
				_hatch()
		Stage.HATCHED:
			pass

	if _dragging:
		var vp := get_viewport_rect().size
		var target := (get_viewport().get_mouse_position() - _grab_offset)
		target.x = clamp(target.x, screen_margin, vp.x - screen_margin)
		target.y = clamp(target.y, screen_margin, vp.y - screen_margin)
		global_position = target + _drag_shake()

func _apply_anchor_wobble(amp: float, speed: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var rot := sin(t * TAU * speed) * deg_to_rad(4.0) * (amp / 7.0)
	var sway := sin(t * TAU * (speed * 0.6)) * (amp * 0.35)
	rotation = rot
	position.x += sway * get_process_delta_time()

func _drag_shake() -> Vector2:
	return Vector2(
		_rng.randf_range(-drag_shake_amp, drag_shake_amp),
		_rng.randf_range(-drag_shake_amp, drag_shake_amp)
	)

func _break_egg() -> void:
	_next_stage(Stage.BROKEN)
	if broken_texture:
		texture = broken_texture

func _hatch() -> void:
	_next_stage(Stage.HATCHED)
	_active = false
	var spawn_pos := global_position
	visible = false
	rotation = 0.0
	if creature_node:
		creature_node.global_position = spawn_pos
		creature_node.visible = true
		if creature_node.has_method("start_post_birth"):
			creature_node.call("start_post_birth", spawn_pos)

func _next_stage(s: Stage) -> void:
	_stage = s

func _unhandled_input(event: InputEvent) -> void:
	# F1: fuerza eclosión SIEMPRE (útil para test rápido)
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		if not _active:
			start_lifecycle(get_viewport().get_mouse_position())
		_hatch()
		return

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

	# Táctil
	if event is InputEventScreenTouch:
		if event.pressed and _is_touch_over(event.position):
			_dragging = true
			_grab_offset = event.position - global_position
			_tween_scale(scale, _base_scale * drag_scale, 0.08)
		elif not event.pressed and _dragging:
			_dragging = false
			_tween_scale(scale, _base_scale, 0.12)

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

# --- Expuestos para el manager
func is_active() -> bool:
	return _active

func is_dragging() -> bool:
	return _dragging
