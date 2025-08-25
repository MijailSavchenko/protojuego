extends Node2D

@onready var background: ColorRect = $Background
@onready var egg: Sprite2D = $Egg
@onready var creature: Sprite2D = $Creature
@onready var ui_min: CanvasLayer = get_node_or_null("UI_Min")
@onready var world_env: WorldEnvironment = get_node_or_null("WorldEnv")
@onready var flash_overlay: CanvasLayer = get_node_or_null("FlashOverlay")

func _ready() -> void:
	# 1) Forzar fondo NEGRO por código (si hay WorldEnvironment, lo sobreescribimos)
	if world_env and world_env.environment:
		world_env.environment.background_mode = Environment.BG_COLOR
		world_env.environment.background_color = Color.BLACK
	# 2) Asegurar ColorRect a pantalla completa y negro
	if background:
		background.color = Color.BLACK
		var vp := get_viewport_rect().size
		background.position = Vector2.ZERO
		background.size = vp
	# 3) Ocultar huevo y criatura al inicio
	if egg:
		egg.visible = false
	if creature:
		creature.visible = false
	# 4) Limpiar UI mín (si existe un Label hijo)
	if ui_min:
		var label := ui_min.get_node_or_null("Label")
		if label:
			label.text = ""
	# 5) Asegurar overlay de flash invisible
	if flash_overlay:
		var flash := flash_overlay.get_node_or_null("Flash")
		if flash:
			flash.visible = false

	# Opcional: log para confirmar inicio limpio
	print("Main ready: fondo negro forzado, Egg/Creature ocultos, UI limpia.")

# Si tu ventana cambia de tamaño (desktop/web), ajusta el ColorRect
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		if background:
			background.size = get_viewport_rect().size
