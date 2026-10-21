extends Node
## Preloaded effects and fixed voice pools keep combat free of audio allocations.

const EFFECTS := ["rifle", "pistol", "shotgun", "reload", "step", "hurt", "click", "hit", "success", "failure", "engine", "helicopter"]
var _streams: Dictionary = {}
var _ui: Array[AudioStreamPlayer] = []
var _world: Array[AudioStreamPlayer3D] = []
var _reload: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	for effect in EFFECTS:
		var stream := load("res://assets/audio/%s.wav" % effect) as AudioStreamWAV
		if effect in ["engine", "helicopter"]:
			# Imported WAVs can be compressed; loop endpoints count decoded samples.
			stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		_streams[effect] = stream
	_reload = AudioStreamPlayer.new()
	_reload.stream = _streams["reload"]
	_reload.volume_db = -19.0
	add_child(_reload)
	for i in 8:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_ui.append(voice)
	for i in 24:
		var voice := AudioStreamPlayer3D.new()
		voice.max_distance = 200.0
		voice.unit_size = 12.0
		voice.max_db = -8.0
		add_child(voice)
		voice.add_to_group("world_audio")
		_world.append(voice)
	EventBus.player_damaged.connect(func(_amount, _source): play_ui("hurt", -13.0))
	EventBus.hitmarker.connect(func(kind): play_ui("hit", -21.0, 1.25 if kind == "head" else 1.0))
	EventBus.player_revived.connect(func(): play_ui("success", -22.0))
	EventBus.player_downed.connect(func(): play_ui("failure", -19.0))
	EventBus.mission_completed.connect(func(_credits, _xp): play_ui("success", -16.0))
	EventBus.mission_failed.connect(func(_reason): play_ui("failure", -16.0))

func play_ui(effect: String, volume: float = -18.0, pitch: float = 1.0) -> void:
	for voice in _ui:
		if not voice.playing:
			voice.stream = _streams[effect]
			voice.volume_db = volume
			voice.pitch_scale = pitch
			voice.play()
			return

func play_at(effect: String, at: Vector3, volume: float = -12.0) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.global_position.distance_squared_to(at) > 200.0 * 200.0:
		return
	for voice in _world:
		if not voice.playing:
			voice.global_position = at
			voice.stream = _streams[effect]
			voice.volume_db = volume
			voice.pitch_scale = _rng.randf_range(0.95, 1.05)
			voice.play()
			return

func weapon_shot(weapon: String, at: Vector3, local: bool = false, suppressed: bool = false) -> void:
	var effect := "pistol" if weapon.contains("Pistol") else ("shotgun" if weapon.contains("Shotgun") else "rifle")
	if local:
		play_ui(effect, -22.0 if suppressed else -12.0, 0.88 if suppressed else _rng.randf_range(0.97, 1.03))
	else:
		play_at(effect, at)

func create_engine(parent: Node3D, helicopter: bool) -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.stream = _streams["helicopter" if helicopter else "engine"]
	voice.volume_db = -17.0
	voice.max_db = -13.0
	voice.unit_size = 16.0
	voice.max_distance = 240.0
	parent.add_child(voice)
	voice.add_to_group("world_audio")
	return voice

func stop_world() -> void:
	stop_reload()
	for voice in get_tree().get_nodes_in_group("world_audio"):
		voice.stop()

func play_reload() -> void:
	_reload.play()

func stop_reload() -> void:
	_reload.stop()
