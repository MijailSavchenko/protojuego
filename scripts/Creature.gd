extends Sprite2D

# ─── Texturas de Xeno
@export var tex_front: Texture2D
@export var tex_back: Texture2D
@export var tex_front_diag: Texture2D

# ─── Movimiento y detección
@export var move_speed: float = 120.0
@export var wander_speed: float = 65.0
@export var sense_radius: float = 220.0
@export var eat_radius: float = 22.0
@export var screen_margin: float = 0.0

# ─── Drag
@export var drag_scale: float = 1.15
@export var drag_shake_amp: float = 2.0

# ─── Stats
@export var max_stamina: float = 100.0
@export var max_hunger: float = 100.0
@export var hunger_increase_per_sec: float = 2.0
@export var stamina_decay_drag_per_sec: float = 8.0
@export var stamina_recover_full_after_eat: float = 35.0
@export var hunger_decrease_per_bit: float = 20.0
@export var poop_every_n_bits: int = 3
@export var stamina_gain_per_bit: float = 6.0

# ─── Integraciones
@export var bits_manager_path: NodePath
@export var poop_scene: PackedScene
var bits_manager: Node2D

# ─── UI mínima
@export var bubble_offset: Vector2 = Vector2(0, -48)
@export var bubble_gap: float = 28.0
@export var bubble_scale: float = 0.9

# ─── Estados
enum S { IDLE, WANDER, FEEDING, DRAGGED }
var _state: S = S.IDLE
var _dragging: bool = false
var _grab_offset: Vector2 = Vector2.ZERO
var _base_scale: Vector2 = Vector2.ONE
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# stats
var stamina: float
var hunger: float
var eaten_count: int = 0

# doble tap
var _last_tap_time: float = 0.0
@export var double_tap_window: float = 0.28

# bubbles
var _bubble_root: Node2D
var _bubble_stats: Area2D
var _bubble_eat: Area2D

# panels + escudo
var _panel_stats: Control
var _panel_feed: Control
var _shield: Control
var _menu_open: bool = false

# dirección
var _last_dir: Vector2 = Vector2.ZERO

# pausas
@export var dwell_min: float = 1.2
@export var dwell_max: float = 2.5
var _dwell_t: float = 0.0

# idle “respirar”
@export var breathe_scale_amp: float = 0.035
@export var step_bob_amp: float = 3.0

func _ready() -> void:
	_rng.randomize()
	_base_scale = scale

	if bits_manager_path != NodePath():
		bits_manager = get_node_or_null(bits_manager_path)
	else:
		bits_manager = get_tree().current_scene.get_node_or_null("BitsManager")

	stamina = max_stamina * 0.6
	hunger = max_hunger * 0.35
	visible = false

func start_post_birth(spawn_pos: Vector2) -> void:
	global_position = spawn_pos
	visible = true
	_state = S.WANDER
	_dwell_t = _randf_range(dwell_min, dwell_max)

func _process(delta: float) -> void:
	hunger = clampf(hunger + hunger_increase_per_sec * delta, 0.0, max_hunger)

	if _menu_open && _state != S.DRAGGED:
		_process_idle(delta)
	else:
		match _state:
			S.DRAGGED:
				_process_drag(delta)
			S.FEEDING:
				_process_feeding(delta)
			S.WANDER:
				_process_wander(delta)
			S.IDLE:
				_process_idle(delta)

	_update_sprite_from_velocity_hint()
	_clamp_to_viewport()

	if _dragging:
		stamina = clampf(stamina - stamina_decay_drag_per_sec * delta, 0.0, max_stamina)

func _process_idle(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var s := 1.0 + sin(t * TAU * 0.4) * breathe_scale_amp
	scale = _base_scale * s

	_dwell_t -= delta
	if _dwell_t <= 0.0 && not _menu_open:
		_state = S.WANDER

func _process_wander(delta: float) -> void:
	if _dwell_t > 0.0:
		_state = S.IDLE
		return

	var target: Node2D = _nearest_bit()
	if target:
		var speed := move_speed
		var dir := (target.global_position - global_position).normalized()
		if dir.y < -0.3:
			speed *= 0.85
		_move_towards(target.global_position, speed, delta)
	else:
		var dir2: Vector2 = Vector2(
			sin(Time.get_ticks_msec()/777.0),
			cos(Time.get_ticks_msec()/913.0)
		).normalized()
		_move_towards(global_position + dir2 * 30.0, wander_speed, delta)

	var v := _last_dir.length()
	if v > 0.01:
		position.y += sin(Time.get_ticks_msec()/90.0) * (step_bob_amp * delta)

	if _rng.randf() < 0.003:
		_dwell_t = _randf_range(dwell_min, dwell_max)
		_state = S.IDLE

func _process_feeding(delta: float) -> void:
	if not (bits_manager and bits_manager.has_method("is_feeding_mode") and bits_manager.call("is_feeding_mode")):
		return

	var target: Node2D = _nearest_bit()
	if target:
		var speed := move_speed
		var dir := (target.global_position - global_position).normalized()
		if dir.y < -0.3:
			speed *= 0.85
		_move_towards(target.global_position, speed, delta)

		if global_position.distance_to(target.global_position) <= eat_radius:
			if bits_manager and bits_manager.has_method("remove_bit"):
				bits_manager.call("remove_bit", target)
			elif is_instance_valid(target):
				target.queue_free()
			_on_ate_bit()
	else:
		_process_wander(delta)
		if hunger <= 0.05 * max_hunger:
			_stop_feeding(true)

func _process_drag(_delta: float) -> void:
	var vp: Vector2 = get_viewport_rect().size
	var target: Vector2 = get_viewport().get_mouse_position() - _grab_offset
	target.x = clamp(target.x, screen_margin, vp.x - screen_margin)
	target.y = clamp(target.y, screen_margin, vp.y - screen_margin)
	var jitter: Vector2 = Vector2(
		_rng.randf_range(-drag_shake_amp, drag_shake_amp),
		_rng.randf_range(-drag_shake_amp, drag_shake_amp)
	)
	global_position = target + jitter

func _move_towards(to: Vector2, speed: float, delta: float) -> void:
	var dir: Vector2 = (to - global_position)
	if dir.length() > 0.001:
		var step: Vector2 = dir.normalized() * speed * delta
		global_position += step
		_last_dir = dir

func _clamp_to_viewport() -> void:
	var vp: Vector2 = get_viewport_rect().size
	global_position.x = clamp(global_position.x, screen_margin, vp.x - screen_margin)
	global_position.y = clamp(global_position.y, screen_margin, vp.y - screen_margin)

func _nearest_bit() -> Node2D:
	if bits_manager == null or not bits_manager.has_method("get_bits"):
		return null
	var arr: Array = (bits_manager.call("get_bits") as Array)
	var best: Node2D = null
	var best_d: float = 1e9
	for item in arr:
		if not is_instance_valid(item):
			continue
		if item is Node2D:
			var b: Node2D = item
			if not is_instance_valid(b):
				continue
			var d: float = global_position.distance_to(b.global_position)
			if d < best_d and d <= sense_radius:
				best_d = d
				best = b
	return best

# ─── Sprites según dirección
func _update_sprite_from_velocity_hint() -> void:
	var dir: Vector2 = _last_dir
	if _state == S.DRAGGED:
		dir = get_viewport().get_mouse_position() - global_position

	var dir_n: Vector2 = dir.normalized()
	if dir_n.length() < 0.2:
		texture = tex_front
		flip_h = false
		return

	if dir_n.y < -0.3:
		texture = tex_back
		flip_h = false
	elif dir_n.y >= -0.3 and dir_n.y <= 0.2:
		texture = tex_front_diag
		flip_h = (dir_n.x > 0.0)
	else:
		texture = tex_front
		flip_h = (dir_n.x > 0.5)

# ─── Comer / Poop
func _on_ate_bit() -> void:
	hunger = clampf(hunger - hunger_decrease_per_bit, 0.0, max_hunger)
	stamina = clampf(stamina + stamina_gain_per_bit, 0.0, max_stamina)
	eaten_count += 1
	if hunger <= 0.05 * max_hunger:
		stamina = min(max_stamina, stamina + stamina_recover_full_after_eat)
	if eaten_count % poop_every_n_bits == 0:
		_spawn_poop()

func _spawn_poop() -> void:
	var poop: Node2D = null
	if poop_scene:
		poop = poop_scene.instantiate()
	else:
		poop = Node2D.new()
		var s: Sprite2D = Sprite2D.new()
		poop.add_child(s)
		var img: Image = Image.create(10, 10, false, Image.FORMAT_RGBA8)
		for y in 10:
			for x in 10:
				var dx: float = float(x - 5)
				var dy: float = float(y - 7)
				var r: float = sqrt(dx*dx + dy*dy)
				var a: float = clamp(1.2 - (r*0.45), 0.0, 1.0)
				img.set_pixel(x, y, Color(0.45, 0.35, 0.25, a))
		s.texture = ImageTexture.create_from_image(img)
		s.centered = true
	get_parent().add_child(poop)
	poop.global_position = global_position
	var pgd: Script = preload("res://scripts/Poop.gd")
	poop.set_script(pgd)

# ─── UI: burbujas SOLO con doble-tap (sin escudo en esta fase)
func _toggle_bubbles() -> void:
	# cerrar si ya están
	if _bubble_root and is_instance_valid(_bubble_root):
		_bubble_root.queue_free()
		_bubble_root = null
		_menu_open = false
		_destroy_shield() # por si acaso quedó alguno
		return

	_menu_open = true
	_state = S.IDLE
	_dwell_t = max(_dwell_t, 1.2)

	# OJO: NO creamos escudo aquí para que el toque llegue a las burbujas
	_bubble_root = Node2D.new()
	add_child(_bubble_root)
	_bubble_root.position = bubble_offset

	_bubble_stats = _make_bubble(Color8(120,200,255), -bubble_gap, "_on_bubble_stats_event")
	_bubble_eat   = _make_bubble(Color8(255,170,90), +bubble_gap, "_on_bubble_eat_event")

func _make_bubble(col: Color, xoff: float, handler: String) -> Area2D:
	var root: Node2D = Node2D.new()
	_bubble_root.add_child(root)
	root.position = Vector2(xoff, 0)
	root.scale = Vector2.ONE * bubble_scale

	var spr: Sprite2D = Sprite2D.new()
	root.add_child(spr)
	var img: Image = Image.create(14, 14, false, Image.FORMAT_RGBA8)
	for y in 14:
		for x in 14:
			var dx: float = float(x - 7)
			var dy: float = float(y - 7)
			var r: float = sqrt(dx*dx + dy*dy)
			var a: float = clamp(1.0 - (r/7.0), 0.0, 1.0)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	spr.texture = ImageTexture.create_from_image(img)
	spr.centered = true

	var ar: Area2D = Area2D.new()
	var cs: CollisionShape2D = CollisionShape2D.new()
	var circ: CircleShape2D = CircleShape2D.new()
	circ.radius = 8.0
	cs.shape = circ
	ar.add_child(cs)
	root.add_child(ar)
	ar.input_pickable = true
	ar.connect("input_event", Callable(self, handler))
	return ar

func _on_bubble_stats_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_show_stats_panel()
		if _bubble_root and is_instance_valid(_bubble_root):
			_bubble_root.queue_free()
			_bubble_root = null

func _on_bubble_eat_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_show_feed_panel("¿Atraer bits?")
		if _bubble_root and is_instance_valid(_bubble_root):
			_bubble_root.queue_free()
			_bubble_root = null

# ─── Panel de stats (con escudo para cerrar al tocar fuera)
func _show_stats_panel() -> void:
	_close_panels()
	_create_shield()

	_panel_stats = Control.new()
	add_child(_panel_stats)
	_panel_stats.position = Vector2(-64, -84)
	_panel_stats.size = Vector2(128, 72)
	_panel_stats.mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = Color(0,0,0,0.55)
	bg.size = _panel_stats.size
	_panel_stats.add_child(bg)

	var barW := 96.0
	var barH := 10.0

	var hunger_bar := ColorRect.new()
	hunger_bar.color = Color(1,0.35,0.35,0.9)
	hunger_bar.position = Vector2(16, 16)
	hunger_bar.size = Vector2(barW * (hunger / max_hunger), barH)
	_panel_stats.add_child(hunger_bar)

	var stamina_bar := ColorRect.new()
	stamina_bar.color = Color(0.35,0.8,1.0,0.9)
	stamina_bar.position = Vector2(16, 40)
	stamina_bar.size = Vector2(barW * (stamina / max_stamina), barH)
	_panel_stats.add_child(stamina_bar)

	var lh := Label.new()
	lh.text = "H"
	lh.position = Vector2(4, 12)
	_panel_stats.add_child(lh)

	var ls := Label.new()
	ls.text = "S"
	ls.position = Vector2(4, 36)
	_panel_stats.add_child(ls)

	_panel_stats.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			var now := Time.get_ticks_msec()/1000.0
			if now - _last_tap_time <= double_tap_window:
				_close_panels()
				_menu_open = false
			_last_tap_time = now
	)

	_state = S.IDLE
	_dwell_t = max(_dwell_t, 2.0)
	_menu_open = true

# ─── Panel de “Atraer bits” (con escudo)
func _show_feed_panel(msg: String) -> void:
	_close_panels()
	_create_shield()

	_panel_feed = Control.new()
	add_child(_panel_feed)
	_panel_feed.position = Vector2(-68, -88)
	_panel_feed.size = Vector2(136, 86)
	_panel_feed.mouse_filter = Control.MOUSE_FILTER_STOP

	var bg_panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0,0,0,0.55)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	bg_panel.add_theme_stylebox_override("panel", sb)
	bg_panel.size = _panel_feed.size
	_panel_feed.add_child(bg_panel)

	var lb := Label.new()
	lb.text = msg
	lb.position = Vector2(12, 10)
	_panel_feed.add_child(lb)

	var yes := _make_round_button(Color(0.3,0.9,0.3,0.95), "Sí")
	yes.position = Vector2(36, 48)
	_panel_feed.add_child(yes)

	var no := _make_round_button(Color(0.9,0.3,0.3,0.95), "No")
	no.position = Vector2(82, 48)
	_panel_feed.add_child(no)

	yes.pressed.connect(func():
		_start_feeding()
		_close_panels()
		_menu_open = false
	)
	no.pressed.connect(func():
		_close_panels()
		_menu_open = false
	)

	_state = S.IDLE
	_dwell_t = max(_dwell_t, 1.2)
	_menu_open = true

# Botón redondo estilizado
func _make_round_button(col: Color, txt: String) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(28, 28)

	var normal := StyleBoxFlat.new()
	normal.bg_color = col
	normal.corner_radius_top_left = 14
	normal.corner_radius_top_right = 14
	normal.corner_radius_bottom_left = 14
	normal.corner_radius_bottom_right = 14
	normal.corner_detail = 6

	var hover := normal.duplicate()
	hover.bg_color = col.lightened(0.08)

	var pressed := normal.duplicate()
	pressed.bg_color = col.darkened(0.10)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	return btn

# Escudo: cierra paneles al tocar fuera (solo para paneles)
func _create_shield() -> void:
	_destroy_shield()
	_shield = Control.new()
	_shield.mouse_filter = Control.MOUSE_FILTER_STOP
	_shield.size = get_viewport_rect().size
	_shield.position = Vector2(-global_position.x, -global_position.y)
	add_child(_shield)
	_shield.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			_close_panels()
			_menu_open = false
	)

func _destroy_shield() -> void:
	if _shield and is_instance_valid(_shield):
		_shield.queue_free()
		_shield = null

func _close_panels() -> void:
	if _panel_stats and is_instance_valid(_panel_stats):
		_panel_stats.queue_free()
	_panel_stats = null
	if _panel_feed and is_instance_valid(_panel_feed):
		_panel_feed.queue_free()
	_panel_feed = null
	if _bubble_root and is_instance_valid(_bubble_root):
		_bubble_root.queue_free()
	_bubble_root = null
	_destroy_shield()

# ─── Alimentación on/off
func _start_feeding() -> void:
	_state = S.FEEDING
	if bits_manager and bits_manager.has_method("set_feeding_mode"):
		bits_manager.call("set_feeding_mode", true, self)

func _stop_feeding(success: bool) -> void:
	_state = S.WANDER
	if bits_manager and bits_manager.has_method("set_feeding_mode"):
		bits_manager.call("set_feeding_mode", false, null)
	if success:
		var tw: Tween = create_tween()
		tw.tween_property(self, "scale", _base_scale * 1.06, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "scale", _base_scale, 0.20).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

# ─── Input (doble-tap y drag)
func _unhandled_input(event: InputEvent) -> void:
	# doble tap para abrir/cerrar burbujas
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var now: float = Time.get_ticks_msec() / 1000.0
		if now - _last_tap_time <= double_tap_window:
			if _is_mouse_over():
				_toggle_bubbles()
				_state = S.IDLE
				_dwell_t = max(_dwell_t, 1.5)
		_last_tap_time = now

	# drag ratón
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _is_mouse_over():
			_dragging = true
			_state = S.DRAGGED
			_grab_offset = get_viewport().get_mouse_position() - global_position
			var tw: Tween = create_tween()
			tw.tween_property(self, "scale", _base_scale * drag_scale, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		elif not event.pressed and _dragging:
			_dragging = false
			_state = S.IDLE
			_dwell_t = _randf_range(dwell_min, dwell_max)
			var tw2: Tween = create_tween()
			tw2.tween_property(self, "scale", _base_scale, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	# táctil
	if event is InputEventScreenTouch:
		if event.pressed and _is_touch_over(event.position):
			_dragging = true
			_state = S.DRAGGED
			_grab_offset = event.position - global_position
			var tw3: Tween = create_tween()
			tw3.tween_property(self, "scale", _base_scale * drag_scale, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		elif not event.pressed and _dragging:
			_dragging = false
			_state = S.IDLE
			_dwell_t = _randf_range(dwell_min, dwell_max)
			var tw4: Tween = create_tween()
			tw4.tween_property(self, "scale", _base_scale, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _is_mouse_over() -> bool:
	if texture == null: return false
	var local: Vector2 = to_local(get_viewport().get_mouse_position())
	var rect := Rect2(-texture.get_size()*0.5, texture.get_size())
	return rect.has_point(local)

func _is_touch_over(pos: Vector2) -> bool:
	if texture == null: return false
	var local: Vector2 = to_local(pos)
	var rect := Rect2(-texture.get_size()*0.5, texture.get_size())
	return rect.has_point(local)

func _randf_range(a: float, b: float) -> float:
	return a + _rng.randf() * (b - a)
