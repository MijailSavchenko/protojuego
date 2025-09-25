extends "res://scripts/Bit.gd"
class_name FoodBit

# Radio a partir del cual el bit se considera “comido”
@export var auto_eat_radius: float = 30.0
@export var debug_auto_eat: bool = false

var _ate: bool = false

func _enter_tree() -> void:
	add_to_group("food_bit")

func _ready() -> void:
	# Mantiene el comportamiento visual/movimiento del Bit original
	super._ready()

# Usamos el _predator heredado del Bit; solo sobreescribimos para poder llamar al super.
func set_predator(p: Node2D) -> void:
	super.set_predator(p)

func clear_predator() -> void:
	super.clear_predator()

func _process(delta: float) -> void:
	super._process(delta)
	_try_auto_eat()

func _try_auto_eat() -> void:
	if _ate:
		return
	# _predator viene del Bit padre
	if _predator == null or not is_instance_valid(_predator):
		return

	var d := global_position.distance_to(_predator.global_position)
	if d <= auto_eat_radius:
		_ate = true
		if debug_auto_eat:
			print("[FoodBit] auto-eat a d=%.2f" % d)

		# 1) Notificar a la criatura para que suba stats y cuente caca
		if _predator.has_method("_on_ate_bit"):
			_predator.call("_on_ate_bit")

		# 2) Pedir al manager que nos quite de su lista
		var mgr := _find_bits_manager()
		if mgr and mgr.has_method("remove_food_bit"):
			mgr.call("remove_food_bit", self)
		elif is_instance_valid(self):
			queue_free()

func _find_bits_manager() -> Node:
	var root := get_tree().current_scene
	if root:
		return root.find_child("BitsManager", true, false)
	return null
