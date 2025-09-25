extends Node

# ───────── Volúmenes y buses
@export var music_volume_db: float = -6.0
@export var sfx_volume_db: float = 0.0
@export var music_bus: StringName = &"Master"
@export var sfx_bus: StringName = &"Master"

# ───────── Internos música (crossfade A/B)
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _using_a: bool = true

# ───────── Reproductores SFX por nombre
var _sfx_players: Dictionary = {} # String -> AudioStreamPlayer

func _ready() -> void:
	_music_a = AudioStreamPlayer.new()
	_music_a.bus = music_bus
	add_child(_music_a)

	_music_b = AudioStreamPlayer.new()
	_music_b.bus = music_bus
	add_child(_music_b)

# ============================
#         MÚSICA
# ============================

func set_music_volume_db(db: float) -> void:
	music_volume_db = db
	_music_a.volume_db = db
	_music_b.volume_db = db

func play_music(stream: AudioStream, from_start: bool = true, fade: float = 0.30) -> void:
	if stream == null:
		return

	var cur: AudioStreamPlayer = (_music_a if _using_a else _music_b)
	var nxt: AudioStreamPlayer = (_music_b if _using_a else _music_a)
	_using_a = not _using_a

	# Posición de reproducción
	var start_pos := 0.0
	if (not from_start) and cur.stream == stream:
		start_pos = cur.get_playback_position()

	# Configurar y arrancar siguiente
	nxt.stream = stream
	nxt.bus = music_bus
	nxt.volume_db = -80.0
	nxt.play(start_pos)

	if fade > 0.0:
		var tw := create_tween()
		tw.tween_property(cur, "volume_db", -80.0, fade)
		tw.parallel().tween_property(nxt, "volume_db", music_volume_db, fade)
		tw.finished.connect(func():
			cur.stop()
			nxt.volume_db = music_volume_db
		)
	else:
		cur.stop()
		nxt.volume_db = music_volume_db

func stop_music(fade: float = 0.30) -> void:
	var cur: AudioStreamPlayer = (_music_a if _using_a else _music_b)
	if fade > 0.0 and cur.playing:
		var tw := create_tween()
		tw.tween_property(cur, "volume_db", -80.0, fade)
		tw.finished.connect(_stop_music_player.bind(cur))
	else:
		_stop_music_player(cur)

func _stop_music_player(p: AudioStreamPlayer) -> void:
	if p and p.playing:
		p.stop()
	p.volume_db = music_volume_db

# ============================
#          SFX
# ============================

# Firma flexible (acepta 4º y 5º parámetro como usas en BitsManager)
@warning_ignore("shadowed_variable_base_class")
func play_sfx(name: String, stream: AudioStream, loop: bool = false, volume_db: float = NAN, pitch_scale: float = 1.0) -> void:
	if stream == null:
		return

	var p: AudioStreamPlayer
	if _sfx_players.has(name):
		p = _sfx_players[name]
	else:
		p = AudioStreamPlayer.new()
		p.bus = sfx_bus
		add_child(p)
		_sfx_players[name] = p

	# En Godot 4 el loop está en el recurso de audio
	if "loop" in stream:
		stream.loop = loop

	p.stop()
	p.stream = stream
	p.pitch_scale = pitch_scale
	p.volume_db = (sfx_volume_db if is_nan(volume_db) else volume_db)
	p.play()

@warning_ignore("shadowed_variable_base_class")
func stop_sfx(name: String) -> void:
	if not _sfx_players.has(name):
		return
	var p: AudioStreamPlayer = _sfx_players[name]
	if p and p.playing:
		p.stop()
	p.volume_db = sfx_volume_db

@warning_ignore("shadowed_variable_base_class")
func fade_out_sfx(name: String, time: float = 0.25) -> void:
	if not _sfx_players.has(name):
		return
	var p: AudioStreamPlayer = _sfx_players[name]
	if not p or not p.playing:
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -80.0, time)
	tw.finished.connect(func():
		p.stop()
		p.volume_db = sfx_volume_db
	)

func is_sfx_playing(sfx_name: String) -> bool:
	if _sfx_players.has(sfx_name):
		var p: AudioStreamPlayer = _sfx_players[sfx_name]
		return p.playing
	return false

func set_sfx_volume_db(db: float) -> void:
	sfx_volume_db = db
	for p in _sfx_players.values():
		if is_instance_valid(p):
			p.volume_db = db

# ───────── Helper que te estaba fallando (.empty() -> .is_empty())
func play_random_from_list(sfx_name: String, list_streams: Array[AudioStream], loop: bool = false, volume_db: float = NAN, pitch_scale: float = 1.0) -> void:
	if list_streams.is_empty():
		return
	var idx := randi() % list_streams.size()
	play_sfx(sfx_name, list_streams[idx], loop, volume_db, pitch_scale)
