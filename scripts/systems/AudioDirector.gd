extends Node
## AudioDirector — 100% procedural cyberpunk audio. No asset files needed.
## 16-bit soft-synth: sine/triangle blips with exponential envelopes and
## lowpassed noise for SFX; warm lowpassed darksynth progression for music.
## (8-bit + raw squares were harsh — this method keeps headroom and rolls
## off highs instead.)

const RATE := 22050

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
	var s := PackedFloat32Array()
	match name:
		"shoot":
			_blip(s, 900.0, 450.0, 0.08, 0.42)
		"shoot_heavy":
			_blip(s, 170.0, 70.0, 0.18, 0.5)
			_whoosh(s, 0.15, 0.22, 0.3)
		"melee":
			_whoosh(s, 0.12, 0.38, 0.5)
		"hit":
			_blip(s, 220.0, 120.0, 0.06, 0.45)
			_whoosh(s, 0.05, 0.28, 0.4)
		"explode":
			_blip(s, 90.0, 35.0, 0.5, 0.55)
			_whoosh(s, 0.5, 0.45, 0.12)
		"pickup":
			_blip(s, 660.0, 1320.0, 0.12, 0.32)
		"credits":
			_blip(s, 1320.0, 1760.0, 0.09, 0.28)
		"levelup":
			_arp(s, [440.0, 554.0, 659.0], 0.12, 0.32)
		"dash":
			_whoosh(s, 0.18, 0.28, 0.4)
		"hurt":
			_blip(s, 130.0, 70.0, 0.18, 0.45)
		"boss":
			_blip(s, 70.0, 50.0, 0.8, 0.45)
			_whoosh(s, 0.8, 0.18, 0.08)
		"ui":
			_blip(s, 990.0, 990.0, 0.06, 0.22)
		"synergy":
			_arp(s, [523.0, 659.0, 784.0, 1046.0], 0.09, 0.28)
		"turret":
			_blip(s, 500.0, 300.0, 0.1, 0.32)
		_:
			_blip(s, 440.0, 440.0, 0.15, 0.3)
	return _pack(s)

func _blip(s: PackedFloat32Array, f0: float, f1: float, dur: float, gain: float) -> void:
	## Sine sweep with exponential decay — soft zap/body without harmonics.
	var n := int(RATE * dur)
	var ph := 0.0
	for i in n:
		var t := float(i) / float(maxi(n, 1))
		var f: float = lerpf(f0, f1, t)
		ph += TAU * f / RATE
		s.append(sin(ph) * gain * pow(1.0 - t, 2.0))

func _arp(s: PackedFloat32Array, notes: Array, note_dur: float, gain: float) -> void:
	for fi in notes.size():
		var f := float(notes[fi])
		var n := int(RATE * note_dur)
		var ph := 0.0
		for i in n:
			var t := float(i) / float(maxi(n, 1))
			ph += TAU * f / RATE
			s.append((sin(ph) * 0.8 + sin(ph * 2.0) * 0.2) * gain * pow(1.0 - t, 1.5))

func _whoosh(s: PackedFloat32Array, dur: float, gain: float, bright: float) -> void:
	## Lowpassed noise swell — airy whoosh/boom, no harsh edges.
	var n := int(RATE * dur)
	var y := 0.0
	for i in n:
		var t := float(i) / float(maxi(n, 1))
		y += bright * (randf_range(-1.0, 1.0) - y)
		s.append(y * gain * sin(PI * minf(t * 1.12, 1.0)))

func _pack(s: PackedFloat32Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = _pack_bytes(s)
	return wav

func _pack_bytes(s: PackedFloat32Array) -> PackedByteArray:
	## Explicit little-endian 16-bit packing (no API endianness ambiguity).
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		var v := int(clampf(s[i], -1.0, 1.0) * 32767.0)
		if v < 0:
			v += 65536
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	return data

func _start_music() -> void:
	## Composition notes (applied theory):
	## - Key A minor; chords Am7 – Fmaj7 – Cmaj7 – G7 (16 steps each).
	## - Hook: A-minor pentatonic motif, call (0–15) + response (16–31),
	##   B-section lift (32–63) with denser rhythm and octave peaks.
	##   Pentatonic stays consonant over every chord (9ths/13ths at worst).
	## - Bass: walking eighths (R R 5 R 8 R 5 b7) + sub drone.
	## - Groove: four-floor kick, backbeat snare, accented offbeat hats,
	##   open hat pickups, sidechain-ducked pad, crash into the B section.
	var bpm := 96.0
	var steps := 64
	var step_dur: float = 60.0 / bpm / 2.0  # eighth notes
	var dur: float = steps * step_dur
	var n := int(RATE * dur)
	var low := PackedFloat32Array()
	low.resize(n)
	var high := PackedFloat32Array()
	high.resize(n)
	var roots := [0, -4, 3, -2]  # Am F C G, semitones from A1
	var sevenths := [10, 11, 11, 10]  # Am7 Fmaj7 Cmaj7 G7
	var thirds := [3, 4, 4, 4]  # minor, major, major, major
	var bass_pat := [0, 0, 7, 0, 12, 0, 7, 10]
	var hook := {0: 12, 3: 10, 6: 7, 8: 10, 11: 12, 14: 15,
		16: 15, 19: 17, 22: 19, 24: 17, 27: 15, 30: 12,
		32: 12, 34: 12, 36: 15, 38: 17, 40: 19, 42: 19, 44: 22, 46: 19,
		48: 19, 50: 17, 52: 15, 54: 12, 56: 10, 58: 12, 60: 7, 62: 7}
	for i in n:
		var t := float(i) / RATE
		var step := int(t / step_dur) % steps
		var block := step / 16
		var rf: float = 55.0 * pow(2.0, float(roots[block]) / 12.0)
		var third: float = rf * pow(2.0, float(thirds[block]) / 12.0)
		var fifth: float = rf * pow(2.0, 7.0 / 12.0)
		var seventh: float = rf * pow(2.0, float(sevenths[block]) / 12.0)
		var in_step: float = fmod(t, step_dur)
		# --- low layer: walking bass + sub + gentle kick + ducked pad ---
		var bf: float = rf * pow(2.0, float(bass_pat[step % 8]) / 12.0)
		var bgate: float = 1.0 if in_step < step_dur * 0.55 else 0.2
		var bass: float = (sin(TAU * bf * t) * 0.6 + sin(TAU * bf * 2.0 * t) * 0.18) * bgate * 0.5
		var sub: float = sin(TAU * rf * t) * 0.15
		var kick := 0.0
		var kick_env := 0.0
		if step % 4 == 0 and in_step < 0.16:
			kick_env = 1.0 - in_step / 0.16
			var kf: float = 110.0 - 450.0 * in_step
			kick = sin(TAU * maxf(kf, 36.0) * t) * kick_env * 0.55
		var pad: float = (sin(TAU * rf * 2.0 * t) + sin(TAU * third * 2.0 * t + 0.4) + sin(TAU * fifth * 2.0 * t + 0.8) + sin(TAU * seventh * 2.0 * t + 1.2)) * 0.08
		pad *= 1.0 - 0.55 * kick_env  # sidechain pump
		low[i] = bass + sub + kick + pad
		# --- high layer: hats + snare + hook + fills ---
		var hat := 0.0
		if step % 2 == 1 and in_step < 0.03:
			var open := step % 16 == 14
			if open and in_step < 0.12:
				hat = randf_range(-1.0, 1.0) * 0.20
			else:
				hat = randf_range(-1.0, 1.0) * (0.20 if step % 4 == 3 else 0.11)
		var snare := 0.0
		if (step % 16 == 4 or step % 16 == 12) and in_step < 0.12:
			snare = randf_range(-1.0, 1.0) * (1.0 - in_step / 0.12) * 0.22
		var hook_s := 0.0
		if hook.has(step):
			var hf: float = 220.0 * pow(2.0, float(hook[step]) / 12.0)
			if in_step < 0.4:
				hook_s = (sin(TAU * hf * t) * 0.6 + sin(TAU * hf * 2.0 * t) * 0.25) * (1.0 - in_step / 0.4) * 0.42
		var crash := 0.0
		if step == 32 and in_step < 0.5:
			crash = randf_range(-1.0, 1.0) * (1.0 - in_step / 0.5) * 0.25
		var riser := 0.0
		if step >= 60:
			riser = randf_range(-1.0, 1.0) * float(step - 60) / 4.0 * 0.15
		high[i] = hat + snare + hook_s + crash + riser
	_lpf(low, 0.30)
	_lpf(high, 0.12)
	_normalize(low, 0.89)
	_normalize(high, 0.50)
	var wb := AudioStreamWAV.new()
	wb.format = AudioStreamWAV.FORMAT_16_BITS
	wb.mix_rate = RATE
	wb.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wb.loop_end = n
	wb.data = _pack_bytes(low)
	var wl := AudioStreamWAV.new()
	wl.format = AudioStreamWAV.FORMAT_16_BITS
	wl.mix_rate = RATE
	wl.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wl.loop_end = n
	wl.data = _pack_bytes(high)
	music_bass.stream = wb
	music_player.stream = wl
	music_bass.play()
	music_player.play()

func _lpf(s: PackedFloat32Array, a: float) -> void:
	## One-pole lowpass over the mix — rolls harsh highs off everything.
	var y := 0.0
	for i in s.size():
		y += a * (s[i] - y)
		s[i] = y

func _normalize(s: PackedFloat32Array, target: float) -> void:
	## Mastering: scale the whole loop so the peak hits target (no clips).
	var peak := 0.001
	for i in s.size():
		peak = maxf(peak, absf(s[i]))
	var g := target / peak
	if is_equal_approx(g, 1.0):
		return
	for i in s.size():
		s[i] = s[i] * g
