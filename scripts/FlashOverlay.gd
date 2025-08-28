extends CanvasLayer

@onready var flash: ColorRect = $Flash
signal flash_finished

func _ready() -> void:
	if flash:
		flash.visible = false
		flash.modulate.a = 0.0

func play(color: Color, duration: float = 5.0) -> void:
	if not flash: 
		emit_signal("flash_finished")
		return
	flash.color = color
	flash.visible = true
	flash.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, duration)
	tween.finished.connect(_on_tween_finished)

func _on_tween_finished() -> void:
	if flash:
		flash.visible = false
	emit_signal("flash_finished")
