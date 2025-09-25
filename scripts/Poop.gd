extends Node2D

@export var taps_to_clean: int = 2
@export var fade_time: float = 0.15

var _taps: int = 0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _is_mouse_over():
			_taps += 1
			if _taps >= taps_to_clean:
				var tw := create_tween()
				tw.tween_property(self, "modulate:a", 0.0, fade_time)
				tw.finished.connect(queue_free)

func _is_mouse_over() -> bool:
	var local: Vector2 = to_local(get_viewport().get_mouse_position())
	# caja generosa 16×16 centrada para que sea fácil acertar
	var rect := Rect2(Vector2(-8, -8), Vector2(16, 16))
	return rect.has_point(local)
