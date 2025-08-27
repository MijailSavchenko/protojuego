# res://scripts/Egg.gd
extends Sprite2D
#
# NOTA rápida:
# - Por defecto NO hace nada hasta que BitsManager llame a start_lifecycle(pos).
# - Si quieres que arranque solo para pruebas, pon auto_start = true en el Inspector.

# ───────── Config general
@export var broken_texture: Texture2D          # Asigna egg_xeno_broken.png en el Inspector
@export var drag_scale: float = 1.15           # Escala mientras arrastras
@export var drag_shake_amp: float = 2.0        # Amplitud del “tembleque” al arrastrar
@export var screen_margin: float = 0.0         # Margen al clamp con el viewport
@export var auto_start: bool = false           # Si true, el ciclo arranca solo (útil pruebas)

# ───────── Tiempos de eclosión (total ≈ 120 s)
@export var t_phase1_quiet: float   = 30.0     # Tranquilo, pequeños latidos
@export var t_phase2_build: float   = 30.0     # Agitación clara (pre-rotura)
@export var t_phase3_broken: float  = 30.0     # Textura rota, “descanso”
@export var t_phase4_hectic: float  = 30.0     # Agitación fuerte (antes de eclosionar)

# ───────── Wobble (movimiento espontáneo)
@export var wobble_quiet_amp: float  = 4.0
@export var wobble_build_amp: float  = 15.0
@export var wobble_broken_amp: float = 4.0
@export var wobble_hectic_amp: float = 15.0

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
var _active: bool = false                      # ← clave: bloquea el ciclo si no se ha invocado
var _orig_texture: Texture2D                   # para restaurar al reiniciar ciclo

func _ready() -> void:
	_rng.randomize()
	_base_scale = scale
	_orig_texture = texture

	# Creature opcional
	if creature_path != NodePath():
		creature_node = get_node_or_null(creature_path)
	else:
		creature_node = get_tree().current_scene.get_node_or_null("Creature")
	if creature_node:
		creature_node.visible = false

	# Estado inicial
	_active = auto_start
	_timer = 0.0
	_stage = Stage.QUIET
	if not _active:
		visible = false
		# asegúrate de que el sprite vuelve a su textura original si venías de pruebas
		if _orig_texture:
			texture = _orig_texture

func start_lifecycle(spawn_pos: Vector2) -> void:
	# Llamado por BitsManager al finalizar ritual.
	global_position = spawn_pos
	visible = true
	_active = true
	_stage = Stage.QUIET
	_timer = 0.0
	scale = _base_scale
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

	# Si arrastramos, seguimos el ratón con clamp a pantalla
	if _dragging:
		var vp := get_viewport_rect().size
		var target := (get_viewport().get_mouse_position() - _grab_offset)
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

	# Táctil
	if event is InputEventScreenTouch:
		if event.pressed and _is_touch_over(event.position):
			_dragging = true
			_grab_offset = event.position - global_position
			_tween_scale(scale, _base_scale * drag_scale, 0.08)
		elif not event.pressed and _dragging:
			_dragging = false
			_tween_scale(scale, _base_scale, 0.12)

# ───────── Wobble “anclado abajo”
func _apply_anchor_wobble(amp: float, speed: float) -> void:
	# El “ancla” está en la parte inferior del sprite (punto de apoyo)
	# Oscilamos rotación y un pequeño offset horizontal como si “patalease” dentro.
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

func _next_stage(s: Stage) -> void:
	_stage = s

func _tween_scale(from_s: Vector2, to_s: Vector2, secs: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", to_s, secs).from(from_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _is_mouse_over() -> bool:
	var tex := texture
	if tex == null: return false
	var local := to_local(get_viewport().get_mouse_position())
	var rect := Rect2(Vector2.ZERO - tex.get_size() * 0.5, tex.get_size())
	return rect.has_point(local)

func _is_touch_over(pos: Vector2) -> bool:
	var tex := texture
	if tex == null: return false
	var local := to_local(pos)
	var rect := Rect2(Vector2.ZERO - tex.get_size() * 0.5, tex.get_size())
	return rect.has_point(local)
