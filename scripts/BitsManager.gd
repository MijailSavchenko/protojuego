extends Node

@export var bit_scene: PackedScene = preload("res://scenes/Bit.tscn")
@export var food_bit_scene: PackedScene = preload("res://scenes/FoodBit.tscn")
@export var max_bits: int = 23
@export var flash_duration: float = 5.0
@export var ritual_hold_time: float = 3.0
@export var random_margin: int = 24
@export_range(0.5, 1.0, 0.05) var capture_ratio: float = 0.85

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

@onready var flash_overlay: CanvasLayer = get_tree().current_scene.get_node_or_null("FlashOverlay")
@onready var egg: Sprite2D = get_tree().current_scene.get_node_or_null("Egg")

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
		return

	if pointer_pressed and bits.size() == max_bits:
		var needed: int = int(ceil(max_bits * capture_ratio))
		var orbiting_count: int = _count_orbiting()
		if orbiting_count >= needed:
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

	# Ritual: permitimos invocar antes del huevo y mientras no esté bloqueado
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

func _spawn_food_bit() -> void:
	if food_bits.size() >= max_bits:
		var oldest = fifo_food.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
		food_bits.erase(oldest)
	var inst = food_bit_scene.instantiate()
	get_parent().add_child(inst)
	inst.global_position = _random_spawn_position()
	# pasar depredador para que pueda auto-comerse
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
	spawning_locked = true
	ritual_completed = true

	var flash_color: Color = _calc_majority_color()

	for b in bits:
		if is_instance_valid(b) and b.has_method("start_merge"):
			b.start_merge(pointer_pos)

	if egg:
		if egg.has_method("start_lifecycle"):
			egg.call("start_lifecycle", pointer_pos)
		else:
			egg.global_position = pointer_pos
			egg.visible = true

	if flash_overlay and flash_overlay.has_method("play"):
		flash_overlay.call("play", flash_color, flash_duration)
		flash_overlay.connect("flash_finished", Callable(self, "_on_flash_finished"), CONNECT_ONE_SHOT)
	else:
		_on_flash_finished()

func _on_flash_finished() -> void:
	for b in bits:
		if is_instance_valid(b):
			b.queue_free()
	bits.clear()
	fifo.clear()
	# spawning_locked sigue true hasta que entremos/salgamos de feeding

func _calc_majority_color() -> Color:
	var counts := {}
	for b in bits:
		if is_instance_valid(b) and b.has_method("get_type_id"):
			var t: String = b.get_type_id()
			counts[t] = int(counts.get(t, 0)) + 1
	var best_type: String = ""
	var best_count: int = -1
	for t in counts.keys():
		var c: int = counts[t]
		if c > best_count:
			best_count = c
			best_type = t
	var type_color := {
		"AGUA": Color8(63, 169, 245),
		"FUEGO": Color8(255, 69, 0),
		"ELECTRICO": Color8(255, 215, 0),
		"PIEDRA": Color8(156, 124, 56),
		"AIRE": Color8(228, 249, 255)
	}
	return type_color.get(best_type, Color.WHITE)

# ---------- API para Creature ----------
func get_bits() -> Array:
	return bits

func get_food_bits() -> Array:
	return food_bits

func remove_bit(node: Node2D) -> void:
	if node in bits:
		bits.erase(node)
	if node in fifo:
		fifo.erase(node)
	if is_instance_valid(node):
		node.queue_free()

func remove_food_bit(node: Node2D) -> void:
	if node in food_bits:
		food_bits.erase(node)
	if node in fifo_food:
		fifo_food.erase(node)
	if is_instance_valid(node):
		node.queue_free()

func clear_all_bits() -> void:
	for b in bits:
		if is_instance_valid(b):
			b.queue_free()
	bits.clear()
	fifo.clear()

func clear_all_food_bits() -> void:
	for f in food_bits:
		if is_instance_valid(f):
			f.queue_free()
	food_bits.clear()
	fifo_food.clear()

func set_feeding_mode(active: bool, creature_ref: Node2D = null) -> void:
	_feeding_mode = active
	_predator = creature_ref
	if active:
		spawning_locked = true
	else:
		clear_all_food_bits()
		spawning_locked = false

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

func is_feeding_mode() -> bool:
	return _feeding_mode
