extends Node
## Small original offline effects; audio is kept quiet enough for automatic fire.
const RATE := 22050
var players: Array[AudioStreamPlayer] = []
var sounds: Dictionary = {}
var cursor := 0
var enabled := true

func _ready() -> void:
    for i in range(8):
        var player := AudioStreamPlayer.new()
        player.bus = "Master"
        add_child(player)
        players.append(player)
    for kind in ["shot", "hit", "gate", "upgrade", "damage", "boss", "end"]:
        sounds[kind] = _make(kind)

func _make(kind: String) -> AudioStreamWAV:
    var duration := 0.10
    match kind:
        "shot": duration = 0.045
        "hit": duration = 0.07
        "gate": duration = 0.23
        "upgrade": duration = 0.35
        "damage": duration = 0.22
        "boss": duration = 0.45
        "end": duration = 0.5
    var count := int(float(RATE) * duration)
    var data := PackedByteArray()
    data.resize(count * 2)
    var rng := RandomNumberGenerator.new()
    rng.seed = 3409 + kind.length() * 137
    for i in range(count):
        var t := float(i) / float(RATE)
        var k := 1.0 - float(i) / float(count)
        var v := 0.0
        match kind:
            "shot": v = (rng.randf_range(-1, 1) * 0.52 + sin(TAU * 120.0 * t) * 0.48) * pow(k, 5)
            "hit": v = (rng.randf_range(-1, 1) * 0.28 + sin(TAU * 280.0 * t)) * pow(k, 4)
            "gate": v = sin(TAU * (440.0 + t * 1200.0) * t) * pow(k, 1.3) * 0.55
            "upgrade": v = (sin(TAU * 660.0 * t) + 0.5 * sin(TAU * 990.0 * t)) * pow(k, 1.1) * 0.4
            "damage": v = (rng.randf_range(-1, 1) * 0.25 + sin(TAU * (155.0 - t * 150.0) * t)) * pow(k, 1.8) * 0.5
            "boss": v = (sin(TAU * (75.0 + 20.0 * t) * t) + rng.randf_range(-0.1, 0.1)) * pow(k, 0.8) * 0.45
            "end": v = (sin(TAU * (300.0 - 260.0 * t) * t) + 0.35 * sin(TAU * 100.0 * t)) * pow(k, 0.8) * 0.45
        data.encode_s16(i * 2, int(clampf(v, -1, 1) * 26000.0))
    var clip := AudioStreamWAV.new()
    clip.format = AudioStreamWAV.FORMAT_16_BITS
    clip.mix_rate = RATE
    clip.stereo = false
    clip.data = data
    return clip

func play(kind: String, volume: float = -8.0) -> void:
    if not enabled or not sounds.has(kind) or players.is_empty():
        return
    var p: AudioStreamPlayer = players[cursor % players.size()]
    cursor += 1
    p.stream = sounds[kind]
    p.volume_db = volume
    p.play()
