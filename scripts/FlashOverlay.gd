extends CanvasLayer

@onready var flash: ColorRect = $Flash

signal flash_finished

func play(color: Color, duration: float = 5.0) -> void:
	# Configurar el color y hacerlo visible
	flash.color = color
	flash.visible = true
	flash.modulate.a = 1.0  # opacidad total

	# Empezar animación de desvanecimiento
	var tween := create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, duration)
	tween.finished.connect(_on_tween_finished)

func _on_tween_finished() -> void:
	flash.visible = false
	emit_signal("flash_finished")
