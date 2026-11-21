extends Node
## Procedural sound, no audio files: a soft wind bed, rain when it rains, birds in
## the daytime, and short chimes when something happens. Synthesized into one
## generator stream so it runs the same on the desktop and in a browser.

const RATE: float = 11025.0

var player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var muted: bool = false
var weather: String = "Clear"
var daytime: bool = true
var _tones: Array = []          # [freq, samples_left, total, volume]
var _noise_lp: float = 0.0
var _rain_lp: float = 0.0
var _bird_t: float = 3.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	player = AudioStreamPlayer.new()
	var gen: AudioStreamGenerator = AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.25
	player.stream = gen
	# browsers default to sample playback; a generator has to stream
	player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	player.volume_db = -8.0
	add_child(player)
	player.play()
	playback = player.get_stream_playback()
	_rng.seed = 7


func chime(kind: String) -> void:
	if muted:
		return
	match kind:
		"good":
			_tone(660.0, 0.12, 0.18)
			_tone(880.0, 0.18, 0.15, 0.1)
		"bad":
			_tone(330.0, 0.25, 0.18)
			_tone(262.0, 0.3, 0.15, 0.15)
		"click":
			_tone(1200.0, 0.03, 0.08)
		_:
			_tone(523.0, 0.15, 0.15)


func _tone(freq: float, dur: float, vol: float, delay: float = 0.0) -> void:
	_tones.append([freq, int(dur * RATE), int(dur * RATE), vol, int(delay * RATE), 0.0])


func _process(delta: float) -> void:
	if playback == null:
		return
	_bird_t -= delta
	if _bird_t <= 0.0:
		_bird_t = _rng.randf_range(2.0, 7.0)
		if daytime and weather != "Rain" and weather != "Storm" and not muted:
			var f: float = _rng.randf_range(2400.0, 3600.0)
			for i in _rng.randi_range(2, 4):
				_tone(f + _rng.randf_range(-200.0, 300.0), 0.06, 0.04, float(i) * 0.09)
	var frames: int = playback.get_frames_available()
	var wind_vol: float = 0.0 if muted else (0.05 if weather == "Storm" else 0.018)
	var rain_vol: float = 0.0 if muted else (0.06 if weather == "Rain" or weather == "Storm" else 0.0)
	for i in frames:
		var white: float = _rng.randf_range(-1.0, 1.0)
		_noise_lp += (white - _noise_lp) * 0.02
		_rain_lp += (white - _rain_lp) * 0.5
		var v: float = _noise_lp * wind_vol * 6.0 + (white - _rain_lp) * rain_vol
		var k: int = 0
		while k < _tones.size():
			var t: Array = _tones[k]
			if int(t[4]) > 0:
				t[4] = int(t[4]) - 1
				k += 1
				continue
			var left: int = int(t[1])
			if left <= 0:
				_tones.remove_at(k)
				continue
			var ph: float = float(t[5]) + float(t[0]) / RATE
			ph -= floor(ph)
			t[5] = ph
			var env: float = float(left) / float(t[2])
			v += sin(ph * TAU) * float(t[3]) * env
			t[1] = left - 1
			k += 1
		v = clampf(v, -1.0, 1.0)
		playback.push_frame(Vector2(v, v))
