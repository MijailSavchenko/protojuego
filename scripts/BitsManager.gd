extends Node

@export var bit_scene: PackedScene = preload("res://scenes/Bit.tscn")
@export var food_bit_scene: PackedScene = preload("res://scenes/FoodBit.tscn")
@export var max_bits: int = 23
@export var flash_duration: float = 5.0
@export var ritual_hold_time: float = 3.0
@export var random_margin: int = 24
@export_range(0.5, 1.0, 0.05) var capture_ratio: float = 0.85

# ------------------- Audio-related exports -------------------
@export var sfx_orbit_loops: Array[AudioStream] = []
@export var sfx_merge_rise: Array[AudioStream] = []  # [0]=rise 1, [1]=rise 2, [2]=rise 3
@export var sfx_bit_spawn: Array[AudioStream] = []
@export var sfx_ritual_start: AudioStream = null
@export var sfx_ritual_end: AudioStream = null  # evento final

# Nombres de SFX
const SFXNAME_ORBIT := "orbit_loop"
const SFXNAME_MERGE := "merge_rise"
const SFXNAME_SPAWN := "bit_spawn"
const SFXNAME_RITUAL_START := "ritual_start"
const SFXNAME_RITUAL_END := "ritual_end"

# Si el stream no reporta duración, disparamos ritual_end tras este tiempo:
const RITUAL_END_FALLBACK_DELAY := 2.6

# ------------------- Tipos/colores -------------------
const ACTIVE_TYPES := ["NORMAL", "AQUA", "FLORA", "IGNEO", "XENO"]
const ACTIVE_COLOR := {
	"NORMAL": Color8(221,221,221),
	"AQUA":   Color8(63,169,245),
	"FLORA":  Color8(60,179,113),
	"IGNEO":  Color8(255,69,0),
	"XENO":   Color8(192,128,160)
}

# ------------------- Vars -------------------
var bits: Array = []        # para ritual
var fifo: Array = []
var food_bits: Array = []   # para comida
var fifo_food: Array = []

var pointer_pos: Vector2 = Vector2.ZERO
var pointer_pressed: bool = false
var prev_pressed: bool = false
var touch_down: bool = false

var spawning_locked: bool = false
var ritual_timer: float = 0.0
var ritual_active: bool = false
var ritual_completed: bool = false

var _feeding_mode: bool = false
var _predator: Node2D = null

var _prev_orbiting_count: int = 0  # para re-disparar rises al volver a cruzar umbrales

# ritual: snapshot seguro
var _ritual_center: Vector2 = Vector2.ZERO
var _ritual_end_scheduled: bool = false
var _cached_species_winner: String = "NORMAL"  # ganador cacheado al iniciar el ritual

@onready var flash_overlay: CanvasLayer = get_tree().current_scene.get_node_or_null("FlashOverlay")
@onready var egg: Node = get_tree().current_scene.get_node_or_null("Egg")

func _ready() -> void:
	print("BitsManager listo. Max bits = %d." % max_bits)

func _process(delta: float) -> void:
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	if mouse_pos != Vector2.ZERO:
		pointer_pos = mouse_pos

	var mouse_down: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	pointer_pressed = mouse_down or touch_down

	if mouse_down and not prev_pressed and not touch_down:
		_on_tap()

	# Propagar estado y depredador a TODOS
	for b in bits:
		if is_instance_valid(b):
			b.set_pointer_state(pointer_pressed, pointer_pos)
			if _feeding_mode and b.has_method("set_predator"):
				b.call("set_predator", _predator)
			elif (not _feeding_mode) and b.has_method("clear_predator"):
				b.call("clear_predator")
	for f in food_bits:
		if is_instance_valid(f):
			f.set_pointer_state(pointer_pressed, pointer_pos)
			if _feeding_mode and f.has_method("set_predator"):
				f.call("set_predator", _predator)
			elif (not _feeding_mode) and f.has_method("clear_predator"):
				f.call("clear_predator")

	prev_pressed = pointer_pressed

	# Ritual solo si NO estamos alimentando
	if _feeding_mode or ritual_completed or spawning_locked:
		_prev_orbiting_count = 0
		return

	# ---------- audio: control de órbita / loops ----------
	var orbiting_count := _count_orbiting()
	if orbiting_count > 0:
		if not AudioManager.is_sfx_playing(SFXNAME_ORBIT):
			if sfx_orbit_loops.size() > 0:
				AudioManager.play_random_from_list(SFXNAME_ORBIT, sfx_orbit_loops, true, -8.0)
			elif AudioManager.get("sfx_orbit_loops") and AudioManager.get("sfx_orbit_loops").size() > 0:
				AudioManager.play_random_from_list(SFXNAME_ORBIT, AudioManager.get("sfx_orbit_loops"), true, -8.0)
	else:
		if AudioManager.is_sfx_playing(SFXNAME_ORBIT):
			AudioManager.fade_out_sfx(SFXNAME_ORBIT, 0.25)

	# ---------- hit markers por cruce de umbral (re-disparables) ----------
	if _prev_orbiting_count < 9 and orbiting_count >= 9:
		_play_merge_step(0)  # rise 1 (índice 0)
	if _prev_orbiting_count < 16 and orbiting_count >= 16:
		_play_merge_step(1)  # rise 2 (índice 1)
	if _prev_orbiting_count < 23 and orbiting_count >= 23:
		_play_merge_step(2)  # rise 3 (índice 2)
	_prev_orbiting_count = orbiting_count

	# Ritual trigger
	if pointer_pressed and bits.size() == max_bits:
		var needed: int = int(ceil(max_bits * capture_ratio))
		var orbiting_count2: int = _count_orbiting()
		if orbiting_count2 >= needed:
			ritual_timer += delta
			if not ritual_active and ritual_timer >= 0.4:
				ritual_active = true
				for b in bits:
					if is_instance_valid(b) and b.has_method("start_shine"):
						b.start_shine(1.3, 0.40)
			if ritual_timer >= ritual_hold_time:
				_start_ritual_sequence()
		else:
			ritual_timer = 0.0
			ritual_active = false
	else:
		ritual_timer = 0.0
		ritual_active = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		pointer_pos = event.position
		touch_down = event.pressed
		if event.pressed:
			_on_tap()
		return
	if event is InputEventScreenDrag:
		pointer_pos = event.position
		return
	if event is InputEventMouseMotion:
		pointer_pos = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pointer_pos = event.position

func _on_tap() -> void:
	# En feeding solo spawneamos comida
	if _feeding_mode:
		_spawn_food_bit()
		return

	# Ritual: permitir invocar antes del huevo y mientras no esté bloqueado
	var egg_active := false
	if egg and egg.has_method("is_active"):
		egg_active = egg.call("is_active")
	if egg_active or ritual_completed or spawning_locked:
		return

	_spawn_ritual_bit()

# ---------- SPAWN ----------
func _spawn_ritual_bit() -> void:
	if bits.size() >= max_bits:
		var oldest = fifo.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
		bits.erase(oldest)
	var inst = bit_scene.instantiate()
	get_parent().add_child(inst)
	inst.global_position = _random_spawn_position()
	bits.append(inst)
	fifo.append(inst)

	if sfx_bit_spawn.size() > 0:
		AudioManager.play_random_from_list(SFXNAME_SPAWN, sfx_bit_spawn, false, -2.0)
	elif AudioManager.get("sfx_bit_spawn") and AudioManager.get("sfx_bit_spawn").size() > 0:
		AudioManager.play_random_from_list(SFXNAME_SPAWN, AudioManager.get("sfx_bit_spawn"), false, -2.0)

func _spawn_food_bit() -> void:
	if food_bits.size() >= max_bits:
		var oldest = fifo_food.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
		food_bits.erase(oldest)
	var inst = food_bit_scene.instantiate()
	get_parent().add_child(inst)
	inst.global_position = _random_spawn_position()
	# pasar depredador
	if is_instance_valid(inst) and inst.has_method("set_predator"):
		inst.call("set_predator", _predator)
	food_bits.append(inst)
	fifo_food.append(inst)

func _random_spawn_position() -> Vector2:
	var vp_rect := get_viewport().get_visible_rect()
	return Vector2(
		randf_range(random_margin, vp_rect.size.x - random_margin),
		randf_range(random_margin, vp_rect.size.y - random_margin)
	)

# ---------- RITUAL ----------
func _count_orbiting() -> int:
	var c: int = 0
	for b in bits:
		if is_instance_valid(b) and b.has_method("is_orbiting") and b.is_orbiting():
			c += 1
	return c

func _start_ritual_sequence() -> void:
	# por si quedó la meta del ciclo anterior
	if has_meta("_ritend_done"):
		remove_meta("_ritend_done")

	spawning_locked = true
	ritual_completed = true
	_ritual_center = pointer_pos  # snapshot centro
	_ritual_end_scheduled = false

	# --- SNAPSHOT: decidir ganador UNA VEZ y usarlo para TODO ---
	var snapshot := _snapshot_counts_active()
	_cached_species_winner = _decide_species_winner_snapshot()

	# DEBUG opcional
	print("SNAPSHOT:", snapshot, "  WINNER:", _cached_species_winner)

	# flash usa el MISMO ganador del ritual/huevo
	var flash_color: Color = ACTIVE_COLOR.get(_cached_species_winner, Color.WHITE)

	# merge hacia el centro del gesto
	for b in bits:
		if is_instance_valid(b) and b.has_method("start_merge"):
			b.start_merge(_ritual_center)

	# RITUAL START y programar RITUAL END al terminar start
	var start_stream: AudioStream = null
	if sfx_ritual_start:
		start_stream = sfx_ritual_start
		AudioManager.play_sfx(SFXNAME_RITUAL_START, sfx_ritual_start, false, 0.0)
	elif AudioManager.get("sfx_ritual_start"):
		start_stream = AudioManager.get("sfx_ritual_start")
		AudioManager.play_sfx(SFXNAME_RITUAL_START, start_stream, false, 0.0)

	_schedule_ritual_end_after_start(start_stream)

	# Apagar rápido el loop de órbita si estuviera activo
	if AudioManager.is_sfx_playing(SFXNAME_ORBIT):
		AudioManager.fade_out_sfx(SFXNAME_ORBIT, 0.2)

	# FLASH visual
	if flash_overlay and flash_overlay.has_method("play"):
		flash_overlay.call("play", flash_color, flash_duration)
		flash_overlay.connect("flash_finished", Callable(self, "_on_flash_finished"), CONNECT_ONE_SHOT)

func _on_flash_finished() -> void:
	# limpiar bits al terminar el flash
	for b in bits:
		if is_instance_valid(b):
			b.queue_free()
	bits.clear()
	fifo.clear()
	_ritual_end_scheduled = false
	# spawning_locked sigue true hasta que entremos/salgamos de feeding

# ---------- Selección de especie ----------
func _normalize_to_active(type_str: String) -> String:
	var t := type_str.to_upper()
	match t:
		"AGUA": t = "AQUA"
		"FUEGO": t = "IGNEO"
		"ELECTRICO": t = "TORMENTA"
		"PIEDRA": t = "LITHOS"
		"AIRE": t = "ETER"
		_: pass
	return t if t in ACTIVE_TYPES else ""

func _snapshot_counts_active() -> Dictionary:
	var counts: Dictionary = {"NORMAL":0, "AQUA":0, "FLORA":0, "IGNEO":0, "XENO":0}
	for b in bits:
		if not is_instance_valid(b) or not b.has_method("get_type_id"):
			continue
		var t: String = b.get_type_id()
		var norm: String = _normalize_to_active(t)
		if norm != "":
			counts[norm] = int(counts[norm]) + 1
	return counts

func _decide_species_winner_snapshot() -> String:
	var counts: Dictionary = _snapshot_counts_active()
	var maxc: int = 0
	for k in counts.keys():
		maxc = max(maxc, int(counts[k]))
	if maxc <= 0:
		return "NORMAL"

	var cands: Array = []
	for k in counts.keys():
		if int(counts[k]) == maxc:
			cands.append(k)

	# Regla Xeno: si empata con alguien, se descarta
	if cands.has("XENO") and cands.size() > 1:
		cands.erase("XENO")
		if cands.size() == 1:
			return cands[0]

	# Si sigue habiendo empate y aparece NORMAL → gana NORMAL
	if cands.has("NORMAL"):
		return "NORMAL"

	# Cadena direccional (AQUA>IGNEO>FLORA>AQUA)
	if cands.size() == 2:
		var a_has := cands.has("AQUA")
		var i_has := cands.has("IGNEO")
		var f_has := cands.has("FLORA")
		if a_has and i_has: return "AQUA"
		if i_has and f_has: return "IGNEO"
		if f_has and a_has: return "FLORA"

	return "NORMAL"

func _play_ritual_end() -> void:
	if has_meta("_ritend_done"):
		return
	set_meta("_ritend_done", true)

	if sfx_ritual_end:
		AudioManager.play_sfx(SFXNAME_RITUAL_END, sfx_ritual_end, false, 0.0)
	elif AudioManager.get("sfx_ritual_end"):
		AudioManager.play_sfx(SFXNAME_RITUAL_END, AudioManager.get("sfx_ritual_end"), false, 0.0)

	var species_winner: String = _cached_species_winner if _cached_species_winner != "" else "NORMAL"

	if egg:
		if egg.has_method("set_species"):
			egg.call("set_species", species_winner)
		if egg.has_method("start_lifecycle"):
			egg.call("start_lifecycle", _ritual_center)
		else:
			if egg is Node2D:
				(egg as Node2D).global_position = _ritual_center
				(egg as Node2D).visible = true

# ---------- API para Creature ----------
func get_bits() -> Array: return bits
func get_food_bits() -> Array: return food_bits

func remove_bit(node: Node2D) -> void:
	if node in bits: bits.erase(node)
	if node in fifo: fifo.erase(node)
	if is_instance_valid(node): node.queue_free()

func remove_food_bit(node: Node2D) -> void:
	if node in food_bits: food_bits.erase(node)
	if node in fifo_food: fifo_food.erase(node)
	if is_instance_valid(node): node.queue_free()

func clear_all_bits() -> void:
	for b in bits:
		if is_instance_valid(b): b.queue_free()
	bits.clear(); fifo.clear()

func clear_all_food_bits() -> void:
	for f in food_bits:
		if is_instance_valid(f): f.queue_free()
	food_bits.clear(); fifo_food.clear()

func set_feeding_mode(active: bool, creature_ref: Node2D = null) -> void:
	_feeding_mode = active
	_predator = creature_ref
	if active:
		spawning_locked = true
		_prev_orbiting_count = 0
		_ritual_end_scheduled = false
	else:
		clear_all_food_bits()
		spawning_locked = false
		_ritual_end_scheduled = false

	# Propagar predator a todos
	for b in bits:
		if not is_instance_valid(b): continue
		if active and b.has_method("set_predator"):
			b.call("set_predator", creature_ref)
		elif (not active) and b.has_method("clear_predator"):
			b.call("clear_predator")
	for f in food_bits:
		if not is_instance_valid(f): continue
		if active and f.has_method("set_predator"):
			f.call("set_predator", creature_ref)
		elif (not active) and f.has_method("clear_predator"):
			f.call("clear_predator")

func stop_and_clear_feeding() -> void:
	_feeding_mode = false
	_predator = null
	clear_all_food_bits()
	spawning_locked = false
	_prev_orbiting_count = 0
	_ritual_end_scheduled = false

func is_feeding_mode() -> bool:
	return _feeding_mode

# ---------- (queda para compatibilidad, ya no se usa por el flash) ----------
func _calc_flash_color_snapshot() -> Color:
	var counts := _snapshot_counts_active()
	var best_type: String = "NORMAL"
	var best_count: int = -1
	for t in counts.keys():
		var c: int = counts[t]
		if c > best_count:
			best_count = c
			best_type = t
	return ACTIVE_COLOR.get(best_type, Color.WHITE)

# ---------- Audio helpers ----------
func _play_merge_step(index: int) -> void:
	if sfx_merge_rise.size() > index and sfx_merge_rise[index]:
		AudioManager.play_sfx(SFXNAME_MERGE, sfx_merge_rise[index], false, -2.0)
		return
	var am_list = AudioManager.get("sfx_merge_rise")
	if am_list and am_list.size() > index and am_list[index]:
		AudioManager.play_sfx(SFXNAME_MERGE, am_list[index], false, -2.0)
		return
	var stream: AudioStream = null
	if sfx_merge_rise.size() > 0: stream = sfx_merge_rise.back()
	elif am_list and am_list.size() > 0: stream = am_list.back()
	if stream: AudioManager.play_sfx(SFXNAME_MERGE, stream, false, -2.0)

func _get_stream_length(stream: AudioStream) -> float:
	if stream == null: return 0.0
	var length_sec: float = 0.0
	if stream.has_method("get_length"): length_sec = float(stream.call("get_length"))
	else: length_sec = float(stream.get_length())
	return max(length_sec, 0.0)

func _schedule_ritual_end_after_start(start_stream: AudioStream) -> void:
	if _ritual_end_scheduled: return
	_ritual_end_scheduled = true
	var delay := _get_stream_length(start_stream)
	if delay <= 0.0: delay = RITUAL_END_FALLBACK_DELAY
	await get_tree().create_timer(delay).timeout
	_play_ritual_end()
