extends Node
## AudioDirector — 100% procedural cyberpunk audio. No asset files needed.
## Synthesizes SFX into AudioStreamWAV at runtime (8-bit style zaps, booms,
## pickups) and runs a generative darksynth loop (bass pulse + hats + pad).

var players: Array[AudioStreamPlayer] = []
var music_player: AudioStreamPlayer
var music_bass: AudioStreamPlayer
var _sfx_cache := {}
var enabled := true

func _ready() -> void:
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		players.append(p)
	music_player = AudioStreamPlayer.new()
	music_player.volume_db = -16.0
	add_child(music_player)
	music_bass = AudioStreamPlayer.new()
	music_bass.volume_db = -14.0
	add_child(music_bass)
	_start_music()

func set_volumes(master: float, music: float, sfx: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(master, 0.01, 1.0)))
	music_player.volume_db = linear_to_db(clampf(music, 0.01, 1.0)) - 8.0
	music_bass.volume_db = linear_to_db(clampf(music, 0.01, 1.0)) - 6.0
	for p in players:
		p.volume_db = linear_to_db(clampf(sfx, 0.01, 1.0)) - 4.0

func play(name: String, pitch := 1.0) -> void:
	if not enabled:
		return
	if not _sfx_cache.has(name):
		_sfx_cache[name] = _synth(name)
	var stream: AudioStreamWAV = _sfx_cache[name]
	for p in players:
		if not p.playing:
			p.stream = stream
			p.pitch_scale = pitch * randf_range(0.96, 1.04)
			p.play()
			return

func _synth(name: String) -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.3
	var freq := 440.0
	var slide := 0.0
	var kind := "square"
	match name:
		"shoot": dur = 0.12; freq = 880.0; slide = -600.0; kind = "square"
		"shoot_heavy": dur = 0.3; freq = 160.0; slide = -80.0; kind = "saw"
		"melee": dur = 0.14; freq = 300.0; slide = 500.0; kind = "noise"
		"hit": dur = 0.1; freq = 220.0; slide = -100.0; kind = "noise"
		"explode": dur = 0.6; freq = 90.0; slide = -40.0; kind = "noise"
		"pickup": dur = 0.18; freq = 660.0; slide = 660.0; kind = "sine"
		"credits": dur = 0.12; freq = 1320.0; slide = 440.0; kind = "sine"
		"levelup": dur = 0.7; freq = 440.0; slide = 880.0; kind = "saw"
		"dash": dur = 0.2; freq = 200.0; slide = 800.0; kind = "sine"
		"hurt": dur = 0.25; freq = 140.0; slide = -60.0; kind = "saw"
		"boss": dur = 1.0; freq = 70.0; slide = 30.0; kind = "saw"
		"ui": dur = 0.08; freq = 990.0; slide = 100.0; kind = "sine"
		"synergy": dur = 0.5; freq = 520.0; slide = 1040.0; kind = "saw"
		"turret": dur = 0.15; freq = 500.0; slide = -200.0; kind = "square"
		_: dur = 0.15; freq = 440.0; kind = "sine"
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / rate
		var f: float = maxf(20.0, freq + slide * t)
		phase += TAU * f / rate
		var s := 0.0
		match kind:
			"sine": s = sin(phase)
			"square": s = 1.0 if sin(phase) > 0.0 else -1.0
			"saw": s = fmod(phase / TAU, 1.0) * 2.0 - 1.0
			"noise": s = randf_range(-1.0, 1.0)
		var env: float = 1.0 - float(i) / n
		data[i] = int(clampf(s * env, -1.0, 1.0) * 100.0 + 128.0)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav

func _start_music() -> void:
	## Generative darksynth, 64-step progression: Am – F – C – G roots,
	## soft sine/triangle bass, detuned pad chords, kick/hat/snare kit,
	## sparse pentatonic plucks, noise riser into the loop point.
	var rate := 22050
	var bpm := 100.0
	var steps := 64
	var step_dur: float = 60.0 / bpm / 2.0  # eighth notes
	var dur: float = steps * step_dur
	var n := int(rate * dur)
	var low := PackedByteArray()
	low.resize(n)
	var high := PackedByteArray()
	high.resize(n)
	# chord roots (semitones from A1) + minor/major third per 16-step block
	var roots := [0, -4, 3, -2]  # Am F C G
	var minors := [true, true, false, false]
	# fixed sparse pluck melody (step -> semitone offset)
	var pluck := {2: 12, 7: 15, 11: 19, 18: 12, 22: 10, 27: 15, 34: 19,
		39: 22, 43: 19, 50: 15, 55: 12, 59: 10}
	for i in n:
		var t := float(i) / rate
		var step := int(t / step_dur) % steps
		var block := step / 16
		var rf: float = 55.0 * pow(2.0, float(roots[block]) / 12.0)
		var third: float = rf * pow(2.0, 3.0 / 12.0 if minors[block] else 4.0 / 12.0)
		var fifth: float = rf * pow(2.0, 7.0 / 12.0)
		var in_step: float = fmod(t, step_dur)
		# --- low layer: soft bass + kick + pad root ---
		var gate: float = 1.0 if in_step < step_dur * 0.7 else 0.25
		var tri: float = sin(TAU * rf * t) * 0.65 + sin(TAU * rf * 2.0 * t) * 0.2 + sin(TAU * rf * 3.0 * t) * 0.08
		var kick := 0.0
		if step % 4 == 0 and in_step < 0.14:
			var kf: float = 120.0 - 600.0 * in_step
			kick = sin(TAU * maxf(kf, 38.0) * t) * (1.0 - in_step / 0.14) * 0.9
		var pad: float = (sin(TAU * rf * 2.0 * t) + sin(TAU * third * 2.0 * t + 0.4) + sin(TAU * fifth * 2.0 * t + 0.8)) * 0.09
		low[i] = int(clampf(tri * gate * 0.55 + kick + pad, -1.0, 1.0) * 100.0 + 128.0)
		# --- high layer: hats + snare + pluck + riser ---
		var hat := 0.0
		if step % 2 == 1 and in_step < 0.03:
			hat = randf_range(-1.0, 1.0) * (0.5 if step % 8 == 7 else 0.28)
		var snare := 0.0
		if (step % 16 == 4 or step % 16 == 12) and in_step < 0.12:
			snare = randf_range(-1.0, 1.0) * (1.0 - in_step / 0.12) * 0.4
		var pluck_s := 0.0
		if pluck.has(step):
			var pf: float = 220.0 * pow(2.0, float(pluck[step]) / 12.0)
			if in_step < 0.4:
				pluck_s = (sin(TAU * pf * t) * 0.6 + sin(TAU * pf * 2.0 * t) * 0.25) * (1.0 - in_step / 0.4) * 0.5
		var riser := 0.0
		if step >= 60:
			riser = randf_range(-1.0, 1.0) * float(step - 60) / 4.0 * 0.22
		high[i] = int(clampf(hat + snare + pluck_s + riser, -1.0, 1.0) * 90.0 + 128.0)
	var wb := AudioStreamWAV.new()
	wb.format = AudioStreamWAV.FORMAT_8_BITS
	wb.mix_rate = rate
	wb.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wb.loop_end = n
	wb.data = low
	var wl := AudioStreamWAV.new()
	wl.format = AudioStreamWAV.FORMAT_8_BITS
	wl.mix_rate = rate
	wl.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wl.loop_end = n
	wl.data = high
	music_bass.stream = wb
	music_player.stream = wl
	music_bass.play()
	music_player.play()
