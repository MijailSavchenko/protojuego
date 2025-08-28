extends Node2D

@onready var background: ColorRect = $Background
@onready var egg: Sprite2D = $Egg
@onready var creature: Sprite2D = $Creature
@onready var ui_min: CanvasLayer = get_node_or_null("UI_Min")
@onready var world_env: WorldEnvironment = get_node_or_null("WorldEnv")
@onready var flash_overlay: CanvasLayer = get_node_or_null("FlashOverlay")

func _ready() -> void:
	if world_env and world_env.environment:
		world_env.environment.background_mode = Environment.BG_COLOR
		world_env.environment.background_color = Color.BLACK
	if background:
		background.color = Color.BLACK
		background.call_deferred("set_size", get_viewport_rect().size)
	if egg: egg.visible = false
	if creature: creature.visible = false
	if ui_min:
		var label := ui_min.get_node_or_null("Label")
		if label: label.text = ""
	if flash_overlay:
		var flash := flash_overlay.get_node_or_null("Flash")
		if flash: flash.visible = false
	print("Main ready.")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		if background:
			background.call_deferred("set_size", get_viewport_rect().size)
