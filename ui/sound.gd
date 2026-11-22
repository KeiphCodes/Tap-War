extends Node
## Procedural sound, no audio files. Synthesized into one generator stream so it
## runs the same on the desktop and in a browser.
##
## The town's own sound (wind, rain, birds, crickets, traffic, hammering, voices)
## is only heard at street level, the same zoom where Sims appear; `ambience`
## fades it in. Chimes for events are the mayor's desk, so they always play.

const RATE: float = 11025.0

var player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var muted: bool = false
var weather: String = "Clear"
var daytime: bool = true
var season: String = "Summer"
## 0 when zoomed out to plan, 1 at street level
var ambience: float = 0.0
## how busy the town is near the camera, each 0..1: traffic, building, crowd
var city: Dictionary = {}
var _amb: float = 0.0
var _swooshes: Array = []      # [samples_left, total, volume]
var _car_t: float = 2.0
var _hammer_t: float = 1.5
var _cricket_t: float = 1.0
var _crowd_lp: float = 0.0
var _crowd_lp2: float = 0.0
var _swoosh_lp: float = 0.0
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


func _ambient_events(delta: float) -> void:
	# each sound waits on its own timer and only starts at street level
	var on: bool = _amb > 0.05 and not muted
	var traffic: float = float(city.get("traffic", 0.0))
	var building: float = float(city.get("building", 0.0))
	_car_t -= delta
	if _car_t <= 0.0:
		_car_t = _rng.randf_range(1.5, 5.0) / maxf(0.25, traffic * 2.0)
		if on and traffic > 0.02:
			var dur: float = _rng.randf_range(1.2, 2.4)
			_swooshes.append([int(dur * RATE), int(dur * RATE), _rng.randf_range(0.05, 0.09)])
			_tone(_rng.randf_range(60.0, 95.0), dur * 0.8, 0.025, dur * 0.1)
	_hammer_t -= delta
	if _hammer_t <= 0.0:
		_hammer_t = _rng.randf_range(1.5, 5.0)
		if on and building > 0.02 and daytime:
			var f: float = _rng.randf_range(170.0, 260.0)
			for i in _rng.randi_range(2, 5):
				_tone(f, 0.05, 0.09 * building, float(i) * _rng.randf_range(0.3, 0.4))
				_tone(f * 3.1, 0.02, 0.03 * building, float(i) * 0.35)
	_cricket_t -= delta
	if _cricket_t <= 0.0:
		_cricket_t = _rng.randf_range(0.8, 2.5)
		if on and not daytime and season != "Winter" and weather != "Rain" and weather != "Storm" and weather != "Snow":
			var cf: float = _rng.randf_range(4200.0, 4700.0)
			for i in 3:
				_tone(cf, 0.035, 0.02, float(i) * 0.07)


func _process(delta: float) -> void:
	if playback == null:
		return
	_amb = lerpf(_amb, ambience, clampf(delta * 3.0, 0.0, 1.0))
	_ambient_events(delta)
	_bird_t -= delta
	if _bird_t <= 0.0:
		_bird_t = _rng.randf_range(2.0, 7.0)
		if daytime and weather != "Rain" and weather != "Storm" and season != "Winter" and not muted and _amb > 0.05:
			var f: float = _rng.randf_range(2400.0, 3600.0)
			for i in _rng.randi_range(2, 4):
				_tone(f + _rng.randf_range(-200.0, 300.0), 0.06, 0.04, float(i) * 0.09)
	var frames: int = playback.get_frames_available()
	var wind_vol: float = 0.0 if muted else (0.05 if weather == "Storm" else 0.018) * _amb
	var rain_vol: float = 0.0 if muted else (0.06 if weather == "Rain" or weather == "Storm" else 0.0) * _amb
	var crowd_vol: float = 0.0 if muted or not daytime else float(city.get("crowd", 0.0)) * 0.05 * _amb
	for i in frames:
		var white: float = _rng.randf_range(-1.0, 1.0)
		_noise_lp += (white - _noise_lp) * 0.02
		_rain_lp += (white - _rain_lp) * 0.5
		var v: float = _noise_lp * wind_vol * 6.0 + (white - _rain_lp) * rain_vol
		if crowd_vol > 0.0:
			# voices far off: noise in the speech band, swelling slowly
			_crowd_lp += (white - _crowd_lp) * 0.12
			_crowd_lp2 += (_crowd_lp - _crowd_lp2) * 0.03
			v += (_crowd_lp - _crowd_lp2) * crowd_vol * (0.7 + 0.3 * sin(float(Time.get_ticks_msec()) / 700.0))
		var sw: int = 0
		while sw < _swooshes.size():
			var e: Array = _swooshes[sw]
			var left2: int = int(e[0])
			if left2 <= 0:
				_swooshes.remove_at(sw)
				continue
			# a car going by: road noise that rises and falls
			_swoosh_lp += (white - _swoosh_lp) * 0.08
			var tt: float = 1.0 - float(left2) / float(e[1])
			v += _swoosh_lp * float(e[2]) * sin(tt * PI) * _amb * 3.0
			e[0] = left2 - 1
			sw += 1
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
