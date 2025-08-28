extends Node2D

@export var bit_scene: PackedScene = preload("res://scenes/Bit.tscn")
@export var max_bits: int = 23
@export var flash_duration: float = 5.0
@export var ritual_hold_time: float = 3.0
@export var random_margin: int = 24
@export_range(0.5, 1.0, 0.05) var capture_ratio: float = 0.85

var bits: Array = []
var fifo: Array = []

var pointer_pos: Vector2 = Vector2.ZERO
var pointer_pressed: bool = false
var prev_pressed: bool = false
var touch_down: bool = false

var spawning_locked: bool = false
var ritual_timer: float = 0.0
var ritual_active: bool = false
var ritual_completed: bool = false

# Feeding mode
var _feeding_mode: bool = false
var _predator: Node2D = null

@onready var flash_overlay: CanvasLayer = get_tree().current_scene.get_node_or_null("FlashOverlay")
@onready var egg: Sprite2D = get_tree().current_scene.get_node_or_null("Egg")

func _ready() -> void:
	print("BitsManager listo. Tap para crear bits (tope %d)." % max_bits)

func _process(_delta: float) -> void:
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	if mouse_pos != Vector2.ZERO:
		pointer_pos = mouse_pos

	var mouse_down: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	pointer_pressed = mouse_down or touch_down

	if mouse_down and not prev_pressed and not touch_down:
		_on_tap()

	for b in bits:
		if is_instance_valid(b):
			b.set_pointer_state(pointer_pressed, pointer_pos)
			if _feeding_mode and b.has_method("set_predator"):
				b.call("set_predator", _predator)
			elif not _feeding_mode and b.has_method("clear_predator"):
				b.call("clear_predator")

	prev_pressed = pointer_pressed

	if ritual_completed or spawning_locked or _feeding_mode:
		return

	if pointer_pressed and bits.size() == max_bits:
		var needed: int = int(ceil(max_bits * capture_ratio))
		var orbiting_count: int = _count_orbiting()

		if orbiting_count >= needed:
			ritual_timer += _delta
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
	# 1) Si NO estamos en feeding y el huevo está visible → NO spawnear bits.
	if (not _feeding_mode) and egg and egg.visible:
		return

	# 2) Spawnear bit (en feeding o libre)
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

	# 3) Si no feeding: no forzar ritual aquí; el resto de lógica va en _process()

func _random_spawn_position() -> Vector2:
	var vp: Vector2 = get_viewport_rect().size
	return Vector2(
		randf_range(random_margin, vp.x - random_margin),
		randf_range(random_margin, vp.y - random_margin)
	)

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
	spawning_locked = true

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

# ─────────── Helpers para Creature
func get_bits() -> Array:
	return bits

func remove_bit(node: Node2D) -> void:
	if node in bits:
		bits.erase(node)
	if node in fifo:
		fifo.erase(node)
	if is_instance_valid(node):
		node.queue_free()

func set_feeding_mode(active: bool, creature: Node2D = null) -> void:
	_feeding_mode = active
	_predator = creature
	for b in bits:
		if not is_instance_valid(b): continue
		if active and b.has_method("set_predator"):
			b.call("set_predator", creature)
		elif (not active) and b.has_method("clear_predator"):
			b.call("clear_predator")

func is_feeding_mode() -> bool:
	return _feeding_mode
