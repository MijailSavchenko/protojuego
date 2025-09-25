extends Sprite2D

# ====== Especie seleccionada (se define desde BitsManager en ritual_end) ======
var _species: String = "NORMAL"

# ====== Sprites por especie (arrastrar en Inspector) ======
@export var tex_norm: Texture2D
@export var tex_norm_broken: Texture2D
@export var tex_aqua: Texture2D
@export var tex_aqua_broken: Texture2D
@export var tex_flora: Texture2D
@export var tex_flora_broken: Texture2D
@export var tex_igneo: Texture2D
@export var tex_igneo_broken: Texture2D
@export var tex_xeno: Texture2D
@export var tex_xeno_broken: Texture2D

# ====== SFX (arrastrar en Inspector) ======
@export var sfx_egg_appear: AudioStream
@export var sfx_egg_wobble1: AudioStream
@export var sfx_egg_wobble2: AudioStream
@export var sfx_egg_crack: AudioStream
@export var sfx_egg_hatch: AudioStream

const SFXNAME_EGG_APPEAR := "egg_appear"
const SFXNAME_EGG_WOBBLE := "egg_wobble"
const SFXNAME_EGG_CRACK := "egg_crack"
const SFXNAME_EGG_HATCH := "egg_hatch"

# ====== Parámetros de interacción/drag ======
@export var drag_scale: float = 1.15
@export var drag_shake_amp: float = 2.0
@export var screen_margin: float = 0.0
@export var auto_start: bool = false

# ====== Timings de fases ======
@export var t_phase1_quiet: float   = 30.0
@export var t_phase2_build: float   = 30.0
@export var t_phase3_broken: float  = 30.0
@export var t_phase4_hectic: float  = 30.0

# ====== Wobble visual ======
@export var wobble_quiet_amp: float  = 4.0
@export var wobble_build_amp: float  = 15.0
@export var wobble_broken_amp: float = 4.0
@export var wobble_hectic_amp: float = 15.0

# ====== Frecuencia SFX wobble ======
@export var wobble_quiet_min_sec: float = 2.0
@export var wobble_quiet_max_sec: float = 4.0
@export var wobble_broken_min_sec: float = 0.8
@export var wobble_broken_max_sec: float = 1.5

# ====== Creature hookup ======
@export var creature_path: NodePath
var creature_node: Node2D

# ====== Estado ======
enum Stage { QUIET, BUILD, BROKEN, HECTIC, HATCHED }
var _stage: Stage = Stage.QUIET
var _timer: float = 0.0
var _dragging: bool = false
var _grab_offset: Vector2 = Vector2.ZERO
var _base_scale: Vector2 = Vector2.ONE
var _rng := RandomNumberGenerator.new()
var _active: bool = false
var _orig_texture: Texture2D

# Timers internos para wobble SFX
var _wobble_time_left: float = 0.0

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
	_reset_wobble_timer_for_stage()
	if not _active:
		visible = false
		if _orig_texture:
			texture = _orig_texture

# === API llamada por BitsManager ===
func set_species(species_name: String) -> void:
	# Mapear legados por seguridad
	match species_name.to_upper():
		"AGUA":    _species = "AQUA"
		"FUEGO":   _species = "IGNEO"
		"ELECTRICO": _species = "TORMENTA" # no activo, pero lo aceptamos
		"PIEDRA":  _species = "LITHOS"     # no activo
		"AIRE":    _species = "ETER"       # no activo
		_:          _species = species_name.to_upper()
	# no cambiamos visible aquí; solo preparamos textura intacta si ya está activo
	_apply_species_intact_if_possible()

func start_lifecycle(spawn_pos: Vector2) -> void:
	global_position = spawn_pos
	visible = true
	_active = true
	_stage = Stage.QUIET
	_timer = 0.0
	scale = _base_scale
	rotation = 0.0
	_apply_species_intact_fallback_norm()
	_play_sfx_appear()
	_reset_wobble_timer_for_stage()

func _process(delta: float) -> void:
	if not _active:
		return

	_timer += delta
	
	match _stage:
		Stage.QUIET:
			_apply_anchor_wobble(wobble_quiet_amp, 1.3)
			_tick_wobble_sfx(delta, true)
			if _timer >= t_phase1_quiet:
				_next_stage(Stage.BUILD)
		Stage.BUILD:
			_apply_anchor_wobble(wobble_build_amp, 2.0)
			# (Roadmap: wobble sfx SOLO en quiet/broken)
			if _timer >= t_phase1_quiet + t_phase2_build:
				_break_egg()
		Stage.BROKEN:
			_apply_anchor_wobble(wobble_broken_amp, 1.5)
			_tick_wobble_sfx(delta, false)
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
		global_position = target + Vector2(
			_rng.randf_range(-drag_shake_amp, drag_shake_amp),
			_rng.randf_range(-drag_shake_amp, drag_shake_amp)
		)

# === Wobble visual ===
func _apply_anchor_wobble(amp: float, speed: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var rot := sin(t * TAU * speed) * deg_to_rad(4.0) * (amp / 7.0)
	var sway := sin(t * TAU * (speed * 0.6)) * (amp * 0.35)
	rotation = rot
	position.x += sway * get_process_delta_time()

# === Wobble SFX ===
func _tick_wobble_sfx(delta: float, is_quiet: bool) -> void:
	_wobble_time_left -= delta
	if _wobble_time_left <= 0.0:
		_play_sfx_wobble()
		if is_quiet:
			_wobble_time_left = _rng.randf_range(min(wobble_quiet_min_sec, wobble_quiet_max_sec), max(wobble_quiet_min_sec, wobble_quiet_max_sec))
		else:
			_wobble_time_left = _rng.randf_range(min(wobble_broken_min_sec, wobble_broken_max_sec), max(wobble_broken_min_sec, wobble_broken_max_sec))

func _reset_wobble_timer_for_stage() -> void:
	match _stage:
		Stage.QUIET:
			_wobble_time_left = _rng.randf_range(min(wobble_quiet_min_sec, wobble_quiet_max_sec), max(wobble_quiet_min_sec, wobble_quiet_max_sec))
		Stage.BROKEN:
			_wobble_time_left = _rng.randf_range(min(wobble_broken_min_sec, wobble_broken_max_sec), max(wobble_broken_min_sec, wobble_broken_max_sec))
		_:
			_wobble_time_left = 9999.0

# === Secuencia ===
func _break_egg() -> void:
	_next_stage(Stage.BROKEN)
	_apply_species_broken_fallback_norm()
	_play_sfx_crack()

func _hatch() -> void:
	_next_stage(Stage.HATCHED)
	_active = false
	var spawn_pos := global_position
	visible = false
	rotation = 0.0
	_play_sfx_hatch()
	if creature_node:
		creature_node.global_position = spawn_pos
		creature_node.visible = true
		if creature_node.has_method("set_species"):
			creature_node.call("set_species", _species)
		if creature_node.has_method("start_post_birth"):
			creature_node.call("start_post_birth", spawn_pos)

func _next_stage(s: Stage) -> void:
	_stage = s
	_reset_wobble_timer_for_stage()

# === Input (drag) ===
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

# ====== Helpers de especie/texturas ======
func _apply_species_intact_if_possible() -> void:
	if not _active:
		return
	_apply_species_intact_fallback_norm()

func _apply_species_intact_fallback_norm() -> void:
	var tex := _get_intact_for(_species)
	if tex == null:
		if tex_norm != null:
			texture = tex_norm
		else:
			texture = _orig_texture
		push_warning("[Egg] Falta tex intacta para %s, usando NORMAL" % _species)
	else:
		texture = tex

func _apply_species_broken_fallback_norm() -> void:
	var texb := _get_broken_for(_species)
	if texb == null:
		if tex_norm_broken != null:
			texture = tex_norm_broken
		elif tex_norm != null:
			texture = tex_norm
		else:
			texture = _orig_texture
		push_warning("[Egg] Falta tex rota para %s, usando NORMAL" % _species)
	else:
		texture = texb

func _get_intact_for(s: String) -> Texture2D:
	match s:
		"NORMAL": return tex_norm
		"AQUA":   return tex_aqua
		"FLORA":  return tex_flora
		"IGNEO":  return tex_igneo
		"XENO":   return tex_xeno
		_:        return null

func _get_broken_for(s: String) -> Texture2D:
	match s:
		"NORMAL": return tex_norm_broken
		"AQUA":   return tex_aqua_broken
		"FLORA":  return tex_flora_broken
		"IGNEO":  return tex_igneo_broken
		"XENO":   return tex_xeno_broken
		_:        return null

# ====== SFX helpers (con fallback a AudioManager autoload) ======
func _play_sfx_appear() -> void:
	if sfx_egg_appear:
		AudioManager.play_sfx(SFXNAME_EGG_APPEAR, sfx_egg_appear, false, 0.0)
	elif AudioManager.get("sfx_egg_appear"):
		AudioManager.play_sfx(SFXNAME_EGG_APPEAR, AudioManager.get("sfx_egg_appear"), false, 0.0)

func _play_sfx_wobble() -> void:
	var local1: AudioStream = sfx_egg_wobble1
	var local2: AudioStream = sfx_egg_wobble2
	var am1: AudioStream = AudioManager.get("sfx_egg_wobble1") if AudioManager.get("sfx_egg_wobble1") else null
	var am2: AudioStream = AudioManager.get("sfx_egg_wobble2") if AudioManager.get("sfx_egg_wobble2") else null
	var pick: AudioStream = null
	if local1 and local2:
		pick = (local1 if randi() % 2 == 0 else local2)
	elif local1:
		pick = local1
	elif local2:
		pick = local2
	elif am1 and am2:
		pick = (am1 if randi() % 2 == 0 else am2)
	elif am1:
		pick = am1
	elif am2:
		pick = am2
	if pick:
		AudioManager.play_sfx(SFXNAME_EGG_WOBBLE, pick, false, -4.0)

func _play_sfx_crack() -> void:
	if sfx_egg_crack:
		AudioManager.play_sfx(SFXNAME_EGG_CRACK, sfx_egg_crack, false, 0.0)
	elif AudioManager.get("sfx_egg_crack"):
		AudioManager.play_sfx(SFXNAME_EGG_CRACK, AudioManager.get("sfx_egg_crack"), false, 0.0)

func _play_sfx_hatch() -> void:
	if sfx_egg_hatch:
		AudioManager.play_sfx(SFXNAME_EGG_HATCH, sfx_egg_hatch, false, 0.0)
	elif AudioManager.get("sfx_egg_hatch"):
		AudioManager.play_sfx(SFXNAME_EGG_HATCH, AudioManager.get("sfx_egg_hatch"), false, 0.0)
