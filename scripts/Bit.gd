extends Node2D
class_name Bit

enum State { IDLE, APPROACH, SCATTER, SHINE, MERGE }

# ===== Tipos =====
# 23 tipos totales, 5 activos con patrón especial. El resto: patrón neutro.
const TYPES_ACTIVE := ["NORMAL", "AQUA", "FLORA", "IGNEO", "XENO"]
const TYPES_ALL := [
	"NORMAL","AQUA","IGNEO","TORMENTA","ETER","LITHOS","CRISTAL","STELIUM",
	"FLORA","ESPORA","FROST","ONIRIC","TOXICO","ARCANA","DRACO","INSECTOIDE",
	"ESPECTRO","SONIDO","ORDEN","CAOS","XENO","AURORA","UMBRA"
]

const TYPE_COLOR := {
	# Activos
	"NORMAL": Color8(221,221,221),
	"AQUA":   Color8(63,169,245),
	"FLORA":  Color8(60,179,113),
	"IGNEO":  Color8(255,69,0),
	"XENO":   Color8(192,128,160),
	# Resto (placeholders)
	"TORMENTA":    Color8(255,215,0),
	"ETER":        Color8(228,249,255),
	"LITHOS":      Color8(139,90,43),
	"CRISTAL":     Color8(135,206,235),
	"STELIUM":     Color8(192,192,192),
	"ESPORA":      Color8(34,139,34),
	"FROST":       Color8(173,216,230),
	"ONIRIC":      Color8(218,112,214),
	"TOXICO":      Color8(127,255,0),
	"ARCANA":      Color8(255,105,180),
	"DRACO":       Color8(255,215,0),
	"INSECTOIDE":  Color8(255,191,0),
	"ESPECTRO":    Color8(75,0,130),
	"SONIDO":      Color8(0,255,255),
	"ORDEN":       Color8(255,248,220),
	"CAOS":        Color8(139,0,0),
	"AURORA":      Color8(255,255,255),
	"UMBRA":       Color8(46,8,84)
}
const WHITE := Color8(255, 255, 255)

# ───── Visual
@export var pixel_scale: float = 1.0
@export var fade_in_time: float = 2.0
@export var halo_size_px: int = 24
@export var halo_alpha: float = 0.35
@export var use_halo: bool = false   # <<— por defecto NO halo

# ───── Ciclo / color
@export var idle_to_cycle_delay: float = 5.0
@export var revert_to_white_time: float = 25.0
@export var color_blend_time: float = 1.25
@export var type_cycle_seconds: float = 3.0

# ───── Bloqueo de color (consistencia visual↔conteo)
@export var lock_on_interaction: bool = true
@export var lock_duration_sec: float = 2.5
@export var lock_extend_on_retouch: bool = true
@export var hard_lock_during_merge: bool = true

# ───── Movimiento global
@export var base_speed: float = 90.0
@export var max_speed: float = 170.0
@export var bounce_damping: float = 1.0
@export var drift_speed: float = 70.0
@export var drift_turn_speed: float = 0.30

# ───── Interacción (acercamiento/orbita)
@export var attract_radius: float = 60.0
@export var stand_off_radius: float = 22.0
@export var approach_lerp: float = 14.0
@export var tangent_slide: float = 0.6
@export var spawn_grace_time: float = 0.4
@export var scatter_duration: float = 1.0

# ───── Órbita estable
@export var approach_ang_speed_min: float = 3.8
@export var approach_ang_speed_max: float = 6.8
@export var approach_radius_jitter: float = 0.18
@export var min_move_speed: float = 40.0
@export var center_follow: float = 0.60

# ───── Anti-bordes suave
@export var wall_margin: float = 36.0
@export var wall_repulsion: float = 220.0
@export var wall_tangent: float = 140.0
@export var wall_steer_blend: float = 0.55

# ───── (predator desactivado: dejamos las variables por compatibilidad)
@export var flee_radius: float = 110.0
@export var flee_boost: float = 220.0
var _predator: Node2D = null

# ───── Nodos/estado
var core: Sprite2D
var halo: Sprite2D = null
var state: State = State.IDLE

# Tipos
var current_type: String = "NORMAL"   # tipo interno/ciclando
var locked_type: String = "NORMAL"    # tipo bloqueado (si aplica)

# Timers
var _type_t: float = 0.0
var _t: float = 0.0
var lock_timer: float = 0.0

# Movimiento
var vel: Vector2 = Vector2.ZERO
var drift_dir: Vector2 = Vector2.ZERO

# Input
var pointer_pressed: bool = false
var pointer_pos: Vector2 = Vector2.ZERO
var since_spawn: float = 0.0
var scatter_t: float = 0.0

# Merge
var merging: bool = false
var merge_target: Vector2 = Vector2.ZERO

# Color/ciclo
var time_since_interaction: float = 0.0
var white_mode: bool = true
var color_locked: bool = false
var from_color: Color = WHITE
var to_color: Color = WHITE
var blend_t: float = 0.0

# Parpadeo blanco
var flicker_speed: float = 1.2
var flicker_min_a: float = 0.35
var flicker_max_a: float = 0.75

# Órbita por individuo
var orbit_center: Vector2 = Vector2.ZERO
var approach_angle: float = 0.0
var approach_ang_speed: float = 3.4
var approach_radius: float = 26.0
var angle_noise_t: float = 0.0
var radius_noise_t: float = 0.0
var noise_rate: float = 0.7

func _ready() -> void:
	randomize()
	_make_visuals()
	# Iniciar dentro del conjunto ACTIVO (5 tipos)
	current_type = TYPES_ACTIVE[randi() % TYPES_ACTIVE.size()]
	locked_type = current_type
	vel = _random_dir() * base_speed
	drift_dir = _random_dir()
	white_mode = true
	color_locked = false
	from_color = WHITE
	to_color = WHITE
	blend_t = 0.0
	time_since_interaction = 0.0
	since_spawn = 0.0

	var tw: Tween = create_tween()
	tw.tween_property(core, "modulate:a", 1.0, fade_in_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if use_halo and halo:
		var tw2: Tween = create_tween()
		tw2.tween_property(halo, "modulate:a", halo_alpha, fade_in_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _make_visuals() -> void:
	core = Sprite2D.new()
	core.name = "Core"
	add_child(core)
	var img: Image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(1,1,1,1))
	core.texture = ImageTexture.create_from_image(img)
	core.scale = Vector2(pixel_scale, pixel_scale)
	core.modulate = Color(1,1,1,0)
	core.z_index = 0

	if use_halo:
		halo = Sprite2D.new()
		halo.name = "Halo"
		add_child(halo)
		var size: int = max(8, halo_size_px)
		var img2: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
		for y in size:
			for x in size:
				var dx: float = float(x) - float(size) * 0.5 + 0.5
				var dy: float = float(y) - float(size) * 0.5 + 0.5
				var r: float = sqrt(dx*dx + dy*dy) / (float(size) * 0.5)
				var a: float = clamp(1.0 - r, 0.0, 1.0)
				img2.set_pixel(x, y, Color(1,1,1,a))
		halo.texture = ImageTexture.create_from_image(img2)
		halo.scale = Vector2(pixel_scale * 4.0, pixel_scale * 4.0)
		halo.modulate = Color(1,1,1,0.0)
		halo.z_index = -1

func set_pointer_state(pressed: bool, pos: Vector2) -> void:
	pointer_pressed = pressed
	orbit_center = orbit_center.lerp(pos, center_follow)
	pointer_pos = pos
	if global_position.distance_to(pointer_pos) <= attract_radius * 0.9:
		time_since_interaction = 0.0
		# ── Bloqueo por interacción (parametrizable)
		if lock_on_interaction:
			if not color_locked:
				color_locked = true
				locked_type = current_type
				white_mode = false
				_apply_color(TYPE_COLOR.get(locked_type, WHITE))
			if lock_extend_on_retouch:
				lock_timer = lock_duration_sec

func is_orbiting() -> bool:
	if state != State.APPROACH:
		return false
	var d_orb: float = (global_position - orbit_center).length()
	var in_ring: bool = d_orb >= stand_off_radius * 0.4 and d_orb <= stand_off_radius * 2.5
	var d_finger: float = global_position.distance_to(pointer_pos)
	var near_finger: bool = d_finger <= attract_radius * 0.8
	return in_ring or near_finger

func _process(delta: float) -> void:
	_t += delta
	since_spawn += delta
	time_since_interaction += delta
	_update_color_logic(delta)

	match state:
		State.IDLE:
			_update_idle(delta)
			if pointer_pressed and since_spawn >= spawn_grace_time and global_position.distance_to(pointer_pos) <= attract_radius:
				_start_approach()
		State.APPROACH:
			_update_approach(delta)
			if not pointer_pressed:
				_enter_scatter()
		State.SCATTER:
			_update_scatter(delta)
		State.SHINE:
			_rebound()
		State.MERGE:
			_update_merge(delta)

# ───────── Color
func _update_color_logic(delta: float) -> void:
	# 1) Si está bloqueado (o en merge con hard lock), pintar fijo y gestionar unlock
	if color_locked or (merging and hard_lock_during_merge):
		_apply_color(TYPE_COLOR.get(locked_type, WHITE))
		# El lock no expira durante MERGE
		if color_locked and not (merging and hard_lock_during_merge):
			lock_timer -= delta
			if lock_timer <= 0.0 and not pointer_pressed:
				color_locked = false
				# reanudar ciclo más adelante; mantenemos current_type en locked_type
				current_type = locked_type
		return

	# 2) Flicker blanco mientras está en modo blanco
	if white_mode:
		var a: float = lerp(flicker_min_a, flicker_max_a, 0.5 + 0.5 * sin(_t * TAU * flicker_speed))
		core.modulate = Color(1, 1, 1, a)
		if use_halo and halo:
			halo.modulate = Color(halo.modulate.r, halo.modulate.g, halo.modulate.b, a * 0.25)

	# 3) Reversión a blanco tras inactividad (si NO está bloqueado)
	if not pointer_pressed and not color_locked and time_since_interaction >= revert_to_white_time:
		white_mode = true
		from_color = WHITE
		to_color = WHITE
		blend_t = 1.0
		current_type = "NORMAL"
		core.modulate = WHITE
		if use_halo and halo:
			halo.modulate = Color(1,1,1,halo_alpha)

	# 4) Ciclo de color entre tipos ACTIVOS (si no está en blanco)
	if not white_mode and time_since_interaction >= idle_to_cycle_delay:
		_type_t += delta
		if _type_t >= type_cycle_seconds:
			_type_t = 0.0
			var list := TYPES_ACTIVE
			var idx: int = list.find(current_type)
			if idx == -1:
				idx = 0
				current_type = list[0]
			var next_idx: int = (idx + 1) % list.size()
			current_type = list[next_idx]
			from_color = _current_color_rgb()
			to_color = TYPE_COLOR.get(current_type, WHITE)
			blend_t = 0.0
		if blend_t < 1.0:
			blend_t = min(1.0, blend_t + delta / color_blend_time)
			var c: Color = from_color.lerp(to_color, blend_t)
			_apply_color(c)

	# 5) Salida de blanco → iniciar ciclo
	if white_mode and time_since_interaction >= idle_to_cycle_delay:
		white_mode = false
		from_color = _current_color_rgb()
		to_color = TYPE_COLOR.get(current_type, WHITE)
		blend_t = 0.0
		_apply_color(from_color.lerp(to_color, blend_t))

func _current_color_rgb() -> Color:
	return Color(core.modulate.r, core.modulate.g, core.modulate.b, 1.0)

func _apply_color(c: Color) -> void:
	core.modulate = Color(c.r, c.g, c.b, core.modulate.a)
	if use_halo and halo:
		halo.modulate = Color(c.r, c.g, c.b, halo_alpha)

# Latido visual para el ritual (usado por BitsManager)
func start_shine(intensity: float = 1.25, duration: float = 0.35) -> void:
	if core == null:
		return
	var s0: Vector2 = core.scale
	var tw1: Tween = create_tween()
	tw1.tween_property(core, "scale", s0 * intensity, duration * 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw1.tween_property(core, "scale", s0, duration * 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if use_halo and halo:
		var a0: float = halo.modulate.a
		var target_a: float = clamp(a0 + 0.25, 0.0, 1.0)
		var tw2: Tween = create_tween()
		tw2.tween_property(halo, "modulate:a", target_a, duration * 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw2.tween_property(halo, "modulate:a", a0, duration * 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

# ───────── Merge (llamado por el manager durante el ritual)
func start_merge(target: Vector2) -> void:
	merging = true
	merge_target = target
	state = State.MERGE
	if hard_lock_during_merge:
		color_locked = true
		locked_type = current_type
		white_mode = false
		_apply_color(TYPE_COLOR.get(locked_type, WHITE))
	if use_halo and halo:
		var a0: float = halo.modulate.a
		var tw := create_tween()
		tw.tween_property(halo, "modulate:a", clamp(a0 + 0.2, 0.0, 1.0), 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _update_merge(delta: float) -> void:
	var to_t: Vector2 = merge_target - global_position
	var dist: float = to_t.length()
	if dist < 6.0:
		merging = false
		queue_free()
		return
	global_position = global_position + to_t.normalized() * min(400.0 * delta, dist * 0.35)
	_rebound()

# ───────── Movimiento
func _update_idle(delta: float) -> void:
	var a_turn: float = drift_turn_speed * delta
	drift_dir = (drift_dir.rotated(a_turn)).normalized()
	var drift_vel: Vector2 = drift_dir * drift_speed

	var type_vel: Vector2 = Vector2.ZERO
	if not white_mode:
		match current_type:
			"AQUA":
				type_vel = Vector2(sin(_t * 2.6), cos(_t * 2.0)) * 50.0
			"IGNEO":
				type_vel = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 120.0
			"FLORA":
				var up: float = 40.0 * max(0.0, sin(_t * 2.2))
				type_vel = Vector2(sin(_t * 1.6) * 20.0, -up)
			"XENO":
				var a: float = sin(_t * 7.0) * 1.7 + cos(_t * 5.3) * 0.9
				type_vel = Vector2(cos(a), sin(a)) * (base_speed * 0.9)
			"NORMAL":
				type_vel = Vector2.ZERO
			_:
				type_vel = Vector2.ZERO

	var steer: Vector2 = _wall_steer()
	var target: Vector2 = (drift_vel + type_vel).lerp(steer, wall_steer_blend)

	vel = vel.move_toward(target, 75.0 * delta)
	_move_and_rebound(delta)

func _wall_steer() -> Vector2:
	var vp: Vector2 = get_viewport_rect().size
	var p: Vector2 = global_position
	var steer: Vector2 = Vector2.ZERO

	var near_left: bool = p.x <= wall_margin
	var near_right: bool = p.x >= vp.x - wall_margin
	var near_top: bool = p.y <= wall_margin
	var near_bottom: bool = p.y >= vp.y - wall_margin

	if near_left: steer.x += wall_repulsion
	if near_right: steer.x -= wall_repulsion
	if near_top: steer.y += wall_repulsion
	if near_bottom: steer.y -= wall_repulsion

	if near_left or near_right:
		var vy: float = 1.0 if vel.y == 0.0 else vel.y
		steer.y += sign(vy) * wall_tangent
	if near_top or near_bottom:
		var vx: float = 1.0 if vel.x == 0.0 else vel.x
		steer.x += sign(vx) * wall_tangent

	return steer

func _start_approach() -> void:
	state = State.APPROACH
	orbit_center = pointer_pos
	approach_angle = (global_position - orbit_center).angle()
	var speed: float = randf_range(approach_ang_speed_min, approach_ang_speed_max)
	var sign_dir: float = 1.0 if randf() > 0.5 else -1.0
	approach_ang_speed = speed * sign_dir
	var jitter: float = 1.0 + randf_range(-approach_radius_jitter, approach_radius_jitter)
	approach_radius = max(8.0, stand_off_radius * jitter)
	angle_noise_t = randf() * 10.0
	radius_noise_t = randf() * 10.0

	# Bloqueo al iniciar approach (si está activado)
	if lock_on_interaction:
		color_locked = true
		locked_type = current_type
		lock_timer = lock_duration_sec
		white_mode = false
		_apply_color(TYPE_COLOR.get(locked_type, WHITE))
	else:
		# Si no bloqueamos por interacción, al menos salimos de blanco para responder visualmente
		white_mode = false

func _update_approach(delta: float) -> void:
	orbit_center = orbit_center.lerp(pointer_pos, center_follow)
	angle_noise_t += delta * noise_rate
	radius_noise_t += delta * noise_rate
	var angle_noise: float = sin(angle_noise_t * TAU) * 0.12
	var radius_noise: float = sin(radius_noise_t * TAU) * (approach_radius * 0.06)

	approach_angle += approach_ang_speed * delta
	var r: float = max(8.0, approach_radius + radius_noise)
	var target_pos: Vector2 = orbit_center + Vector2(r, 0).rotated(approach_angle + angle_noise)

	var lerp_rate: float = min(1.0, approach_lerp * delta)
	global_position = global_position.lerp(target_pos, lerp_rate)

	var cur_speed: float = vel.length()
	if cur_speed < min_move_speed:
		var tangent: Vector2 = Vector2(-sin(approach_angle), cos(approach_angle)) * (min_move_speed - cur_speed)
		vel += tangent

	_rebound()

func _enter_scatter() -> void:
	state = State.SCATTER
	scatter_t = 0.0
	# NO desactivar el lock aquí; dejaremos que expire por timer.
	time_since_interaction = 0.0
	var tangent_dir: Vector2 = Vector2(-sin(approach_angle), cos(approach_angle))
	vel = (tangent_dir * (stand_off_radius * 2.0) + _random_dir() * 20.0).limit_length(max_speed)

func _update_scatter(delta: float) -> void:
	scatter_t += delta
	vel += Vector2(randf_range(-15, 15), randf_range(-15, 15)) * delta
	_move_and_rebound(delta)
	if scatter_t >= scatter_duration:
		state = State.IDLE

func _move_and_rebound(delta: float) -> void:
	vel = vel.limit_length(max_speed)
	global_position += vel * delta
	_rebound()

func _rebound() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var pos: Vector2 = global_position
	var bounced: bool = false
	if pos.x < 0.0: pos.x = 0.0; vel.x = -vel.x * bounce_damping; bounced = true
	elif pos.x > vp.x: pos.x = vp.x; vel.x = -vel.x * bounce_damping; bounced = true
	if pos.y < 0.0: pos.y = 0.0; vel.y = -vel.y * bounce_damping; bounced = true
	elif pos.y > vp.y: pos.y = vp.y; vel.y = -vel.y * bounce_damping; bounced = true
	if bounced:
		global_position = pos

func _random_dir() -> Vector2:
	var d: Vector2 = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	return Vector2.RIGHT if d == Vector2.ZERO else d.normalized()

# ───────── Integración con BitsManager (conteo por tipo)
func get_type_id() -> String:
	# Lo que cuenta el manager es lo que se ve (si está bloqueado/merge)
	if color_locked or (merging and hard_lock_during_merge):
		return locked_type
	return current_type

# ───────── Depredador (no usado)
func set_predator(p: Node2D) -> void:
	_predator = p
func clear_predator() -> void:
	_predator = null

# ───────── Soporte legado para forzar especie (nombres antiguos → nuevos)
func set_species(species_name: String) -> void:
	var s: String = species_name.to_upper()
	match s:
		"AGUA": s = "AQUA"
		"FUEGO": s = "IGNEO"
		"ELECTRICO": s = "TORMENTA"
		"PIEDRA": s = "LITHOS"
		"AIRE": s = "ETER"
		_: pass
	if TYPES_ALL.has(s):
		current_type = s
		# aplica color inmediatamente (y cancela blanco)
		from_color = _current_color_rgb()
		to_color = TYPE_COLOR.get(current_type, WHITE)
		blend_t = 0.0
		white_mode = false
		_apply_color(to_color)
