extends Node
## Self-generated original PCM combat audio. No network/files required.
const RATE := 22050
var channels: Array[AudioStreamPlayer] = []
var clips: Dictionary = {}
var cursor := 0

func _ready() -> void:
    for _i in range(7):
        var p := AudioStreamPlayer.new()
        p.volume_db = -8
        add_child(p)
        channels.append(p)
    clips["shot"] = _synthesize("shot", 0.17)
    clips["enemy"] = _synthesize("enemy", 0.16)
    clips["hit"] = _synthesize("hit", 0.11)
    clips["impact"] = _synthesize("impact", 0.18)
    clips["reload"] = _synthesize("reload", 0.27)
    clips["kill"] = _synthesize("kill", 0.19)
    clips["death"] = _synthesize("death", 0.42)
    clips["success"] = _synthesize("success", 0.6)

func _synthesize(kind: String, duration: float) -> AudioStreamWAV:
    var samples := int(float(RATE) * duration)
    var raw := PackedByteArray()
    raw.resize(samples * 2)
    var rng := RandomNumberGenerator.new()
    rng.seed = 71299 + hash(kind)
    for i in range(samples):
        var t: float = float(i) / RATE
        var r: float = rng.randf_range(-1.0, 1.0)
        var v := 0.0
        match kind:
            "shot":
                v = (0.70 * r + 0.30 * sin(TAU * 92.0 * t)) * exp(-t * 27.0)
            "enemy":
                v = (0.67 * r + 0.33 * sin(TAU * 113.0 * t)) * exp(-t * 36.0)
            "hit":
                v = (0.22 * r + 0.60 * sin(TAU * 770 * t)) * exp(-t * 21.0)
            "impact":
                v = (0.62 * r + 0.22 * sin(TAU * 80 * t)) * exp(-t * 18)
            "reload":
                v = (0.38 * r + 0.30 * sin(TAU * 540 * t)) * (exp(-pow((t - 0.025) * 58.0, 2)) + exp(-pow((t - 0.19) * 46.0, 2)))
            "kill":
                v = sin(TAU * (950 - 500 * t) * t) * exp(-t * 14) * 0.35
            "death":
                v = (0.3 * r + 0.25 * sin(TAU * (220 - t * 320) * t)) * exp(-t * 4)
            "success":
                var freq: float = 392 if t < 0.20 else (494 if t < 0.40 else 587)
                v = sin(TAU * freq * t) * 0.24 * sin(PI * (fmod(t, 0.2) / 0.2))
        var value: int = clampi(int(v * 23000), -32767, 32767)
        if value < 0:
            value += 65536
        raw[i * 2] = value & 255
        raw[i * 2 + 1] = (value >> 8) & 255
    var stream := AudioStreamWAV.new()
    stream.format = AudioStreamWAV.FORMAT_16_BITS
    stream.mix_rate = RATE
    stream.stereo = false
    stream.data = raw
    return stream

func _play(which: String, volume: float = -5.0) -> void:
    var channel: AudioStreamPlayer = channels[cursor % channels.size()]
    cursor += 1
    channel.stop()
    channel.stream = clips[which]
    channel.volume_db = volume
    channel.play()

func play_shot() -> void:
    _play("shot", -2)

func play_enemy_shot() -> void:
    _play("enemy", -17)

func play_hit() -> void:
    _play("hit", -6)

func play_impact() -> void:
    _play("impact", -7)

func play_reload() -> void:
    _play("reload", -6)

func play_kill() -> void:
    _play("kill", -8)

func play_death() -> void:
    _play("death", -6)

func play_success() -> void:
    _play("success", -4)
