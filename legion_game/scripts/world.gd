extends Node3D
## 3D highway, environment, lighting, boss and pooled shot/impact visuals.
var road_marks: Array[Node3D] = []
var roadside: Array[Node3D] = []
var gates_root: Node3D
var camera: Camera3D
var boss_root: Node3D
var boss_animation: AnimationPlayer
var beam_batch: MultiMeshInstance3D
var spark_batch: MultiMeshInstance3D
var materials: Dictionary = {}
var clock := 0.0
var normal_camera_position := Vector3(0, 25.5, 24.0)
var shake := 0.0
var graphic_high := true

func build() -> void:
    _materials()
    _environment()
    _road()
    _decoration()
    _pools()
    gates_root = Node3D.new()
    add_child(gates_root)
    camera = Camera3D.new()
    camera.current = true
    camera.fov = 48.0
    camera.position = normal_camera_position
    add_child(camera)
    camera.look_at(Vector3(0, 0, -7), Vector3.UP)
    _boss()

func _material(color: Color, metallic: float = 0.0, rough: float = 0.8, glow: float = 0.0) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.metallic = metallic
    m.roughness = rough
    if glow > 0:
        m.emission_enabled = true
        m.emission = color
        m.emission_energy_multiplier = glow
    return m

func _pbr(dir: String, tint: Color, tile: float) -> StandardMaterial3D:
    var m := _material(tint)
    var base := "res://assets/textures/" + dir + "/"
    if ResourceLoader.exists(base + "Color.webp"):
        m.albedo_texture = load(base + "Color.webp")
        m.uv1_triplanar = true
        m.uv1_scale = Vector3.ONE * tile
        m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
        if ResourceLoader.exists(base + "NormalGL.webp"):
            m.normal_enabled = true
            m.normal_texture = load(base + "NormalGL.webp")
            m.normal_scale = 0.5
        if ResourceLoader.exists(base + "Roughness.webp"):
            m.roughness_texture = load(base + "Roughness.webp")
            m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
    return m

func _materials() -> void:
    materials["asphalt"] = _pbr("Asphalt031", Color("#606f72"), 0.23)
    materials["concrete"] = _pbr("Concrete034", Color("#7c8985"), 0.27)
    materials["metal"] = _pbr("Metal046B", Color("#9aa7a8"), 0.28)
    materials["dark"] = _material(Color("#1c2a2d"), 0.65, 0.55)
    materials["yellow"] = _material(Color("#f6ad39"), 0.12, 0.55, 1.3)
    materials["white"] = _material(Color("#cbd5d0"), 0.05, 0.9)
    materials["red"] = _material(Color("#f04e36"), 0.2, 0.5, 1.3)
    materials["cyan"] = _material(Color("#40d8db"), 0.2, 0.5, 1.5)
    materials["blueglass"] = _material(Color(0.04, 0.6, 0.8, 0.22), 0.1, 0.4, 0.9)
    materials["blueglass"].transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    materials["blueglass"].cull_mode = BaseMaterial3D.CULL_DISABLED
    materials["redglass"] = _material(Color(0.88, 0.11, 0.06, 0.22), 0.1, 0.4, 0.9)
    materials["redglass"].transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    materials["redglass"].cull_mode = BaseMaterial3D.CULL_DISABLED

func _environment() -> void:
    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    var procedural := ProceduralSkyMaterial.new()
    procedural.sky_top_color = Color("#263d55")
    procedural.sky_horizon_color = Color("#c69471")
    procedural.ground_bottom_color = Color("#303b3c")
    procedural.ground_horizon_color = Color("#8b8a7b")
    sky.sky_material = procedural
    if ResourceLoader.exists("res://assets/textures/sunset.hdr"):
        var pano := PanoramaSkyMaterial.new()
        pano.panorama = load("res://assets/textures/sunset.hdr")
        sky.sky_material = pano
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#ced6d2")
    env.ambient_light_energy = 0.55
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.tonemap_exposure = 0.88
    env.fog_enabled = true
    env.fog_density = 0.006
    env.fog_sky_affect = 0.15
    env.fog_light_color = Color("#9ca8a2")
    var we := WorldEnvironment.new()
    we.environment = env
    add_child(we)
    var sun := DirectionalLight3D.new()
    sun.name = "Sun"
    sun.rotation_degrees = Vector3(-48, -35, 0)
    sun.light_color = Color("#ffdfb0")
    sun.light_energy = 1.25
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 35.0
    add_child(sun)

func _box(parent: Node3D, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
    var obj := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    obj.mesh = mesh
    obj.material_override = material
    obj.position = pos
    parent.add_child(obj)
    return obj

func _road() -> void:
    # A dark industrial ground keeps the road anchored in a real environment.
    _box(self, Vector3(0, -1.05, -10), Vector3(220, 0.4, 160), materials["dark"])
    _box(self, Vector3(0, -0.34, -7), Vector3(18, 0.65, 110), materials["asphalt"])
    for side in [-1.0, 1.0]:
        _box(self, Vector3(side * 7.85, 0.006, -7), Vector3(0.16, 0.018, 105), materials["white"])
    for x in [-8.5, 8.5]:
        _box(self, Vector3(x, 0.24, -8), Vector3(0.55, 0.5, 105), materials["concrete"])
        _box(self, Vector3(x, 0.83, -8), Vector3(0.18, 0.2, 105), materials["metal"])
        _box(self, Vector3(x + (-0.55 if x < 0 else 0.55), -0.2, -8), Vector3(1.2, 0.3, 105), materials["dark"])
    # Move lane markings toward the camera to make forward motion obvious.
    for z in range(-45, 35, 5):
        for x in [-2.7, 2.7]:
            var stripe := Node3D.new()
            stripe.position = Vector3(x, 0.012, float(z))
            add_child(stripe)
            _box(stripe, Vector3.ZERO, Vector3(0.12, 0.02, 2.3), materials["yellow"])
            road_marks.append(stripe)

func _model_bounds(n: Node, anchor: Node3D, state: Dictionary) -> void:
    if n is MeshInstance3D:
        var m := n as MeshInstance3D
        if m.mesh != null:
            var a: AABB = m.mesh.get_aabb()
            var trans: Transform3D = anchor.global_transform.affine_inverse() * m.global_transform
            for x in [0.0, 1.0]:
                for y in [0.0, 1.0]:
                    for z in [0.0, 1.0]:
                        var p: Vector3 = trans * (a.position + a.size * Vector3(x, y, z))
                        if not state["found"]:
                            state["found"] = true
                            state["lo"] = p
                            state["hi"] = p
                        else:
                            var lo: Vector3 = state["lo"]
                            var hi: Vector3 = state["hi"]
                            state["lo"] = Vector3(minf(lo.x,p.x),minf(lo.y,p.y),minf(lo.z,p.z))
                            state["hi"] = Vector3(maxf(hi.x,p.x),maxf(hi.y,p.y),maxf(hi.z,p.z))
    for child in n.get_children():
        _model_bounds(child, anchor, state)

func _prop(filename: String, pos: Vector3, target_height: float, yaw: float = 0.0) -> Node3D:
    var path := "res://assets/models/" + filename + ".glb"
    if not ResourceLoader.exists(path):
        return null
    var scene := load(path) as PackedScene
    if scene == null:
        return null
    var wrapper := Node3D.new()
    add_child(wrapper)
    var child := scene.instantiate() as Node3D
    wrapper.add_child(child)
    var s := {"found": false, "lo": Vector3.ZERO, "hi": Vector3.ZERO}
    _model_bounds(wrapper, wrapper, s)
    if s["found"]:
        var lo: Vector3 = s["lo"]
        var hi: Vector3 = s["hi"]
        var factor: float = target_height / maxf(0.05, hi.y - lo.y)
        child.scale = Vector3.ONE * factor
        child.position = Vector3(-(lo.x+hi.x)*0.5*factor, -lo.y*factor, -(lo.z+hi.z)*0.5*factor)
    wrapper.position = pos
    wrapper.rotation.y = yaw
    return wrapper

func _decoration() -> void:
    for side in [-1.0, 1.0]:
        for i in range(11):
            var z := -38.0 + float(i) * 7.0
            var post := Node3D.new()
            post.position = Vector3(side * 9.0, 0, z)
            add_child(post)
            _box(post, Vector3(0, 0.8, 0), Vector3(0.20, 1.6, 0.2), materials["metal"])
            _box(post, Vector3(0, 1.55, 0), Vector3(0.30, 0.14, 0.38), materials["yellow"] if i % 3 == 0 else materials["dark"])
            roadside.append(post)
    for i in range(5):
        var side := -1.0 if i % 2 == 0 else 1.0
        var z := -34.0 + i * 15.0
        var barrier := _prop("road_barrier", Vector3(side * 7.9, 0, z), 0.8, PI * 0.5)
        if barrier != null:
            roadside.append(barrier)
    for i in range(3):
        var side := -1.0 if i % 2 == 0 else 1.0
        var wreck := _prop("destroyed_car", Vector3(side * 7.2, 0, -35.0 + i * 25.0), 1.12, 0.15 + i * 0.25)
        if wreck != null:
            roadside.append(wreck)
    for side in [-1.0, 1.0]:
        var building := Node3D.new()
        building.position = Vector3(side * 12.0, 0, -27)
        add_child(building)
        _box(building, Vector3(0, 3, 0), Vector3(7, 6, 12), materials["concrete"])
        for z in [-4.0, 0.0, 4.0]:
            _box(building, Vector3(-side * 3.53, 3.7, z), Vector3(0.12, 1.0, 2.1), materials["dark"])
        roadside.append(building)

func _pools() -> void:
    var beam_mesh := BoxMesh.new()
    beam_mesh.size = Vector3(0.07, 0.07, 1.0)
    var beam_mat := _material(Color("#ffd77a"), 0.0, 0.3, 3.4)
    beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    beam_mesh.material = beam_mat
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.mesh = beam_mesh
    mm.instance_count = 160
    mm.visible_instance_count = 0
    beam_batch = MultiMeshInstance3D.new()
    beam_batch.multimesh = mm
    beam_batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(beam_batch)
    var spark_mesh := SphereMesh.new()
    spark_mesh.radius = 0.12
    spark_mesh.height = 0.24
    spark_mesh.radial_segments = 6
    spark_mesh.rings = 3
    var spark_mat := _material(Color("#ff894d"), 0.0, 0.3, 2.5)
    spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    spark_mesh.material = spark_mat
    var sm := MultiMesh.new()
    sm.transform_format = MultiMesh.TRANSFORM_3D
    sm.mesh = spark_mesh
    sm.instance_count = 96
    sm.visible_instance_count = 0
    spark_batch = MultiMeshInstance3D.new()
    spark_batch.multimesh = sm
    spark_batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(spark_batch)

func _boss() -> void:
    boss_root = Node3D.new()
    boss_root.visible = false
    add_child(boss_root)
    var path := "res://assets/models/tide/tide_hunter_monster.glb"
    if ResourceLoader.exists(path):
        var scene := load(path) as PackedScene
        if scene != null:
            var model := scene.instantiate() as Node3D
            model.scale = Vector3.ONE * 2.0
            model.rotation.y = PI
            boss_root.add_child(model)
            boss_animation = _find_animation(model)
            if boss_animation != null and boss_animation.has_animation("run"):
                boss_animation.play("run")
            return
    var fallback := _box(boss_root, Vector3(0, 2, 0), Vector3(2.6, 4, 1.6), materials["red"])
    fallback.name = "FallbackBoss"

func _find_animation(n: Node) -> AnimationPlayer:
    if n is AnimationPlayer:
        return n as AnimationPlayer
    for child in n.get_children():
        var result := _find_animation(child)
        if result != null:
            return result
    return null

func make_gate(x: float, z: float, caption: String, risky: bool) -> Node3D:
    var gate := Node3D.new()
    gate.position = Vector3(x, 0, z)
    gates_root.add_child(gate)
    var edge: Material = materials["red"] if risky else materials["cyan"]
    var glass: Material = materials["redglass"] if risky else materials["blueglass"]
    _box(gate, Vector3(0, 1.6, 0), Vector3(6.5, 3.2, 0.08), glass)
    for side in [-1.0, 1.0]:
        _box(gate, Vector3(side * 3.2, 1.6, 0), Vector3(0.14, 3.2, 0.16), edge)
    _box(gate, Vector3(0, 3.1, 0), Vector3(6.5, 0.18, 0.16), edge)
    _box(gate, Vector3(0, 0.08, 0), Vector3(6.5, 0.12, 0.16), edge)
    var label := Label3D.new()
    label.text = caption
    label.font_size = 80
    label.pixel_size = 0.009
    label.outline_size = 12
    label.outline_modulate = Color(0, 0, 0, 0.85)
    label.modulate = Color("#fff9dc")
    label.position = Vector3(0, 2.2, 0)
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    gate.add_child(label)
    return gate

func advance(delta: float, speed: float, velocity_shake: float = 0.0) -> void:
    clock += delta
    shake = maxf(shake - delta * 3, velocity_shake)
    if is_instance_valid(camera):
        camera.position = normal_camera_position + Vector3(sin(clock * 70) * shake * 0.09, cos(clock * 60) * shake * 0.06, 0)
        camera.look_at(Vector3(0, 0, -7), Vector3.UP)
    for mark in road_marks:
        mark.position.z += speed * delta
        if mark.position.z > 32:
            mark.position.z -= 80
    for prop in roadside:
        prop.position.z += speed * delta
        if prop.position.z > 34:
            prop.position.z -= 77

func draw_effects(shots: Array, sparks: Array) -> void:
    var count := mini(shots.size(), beam_batch.multimesh.instance_count)
    for i in range(count):
        var s: Dictionary = shots[i]
        var from: Vector3 = s["from"]
        var to: Vector3 = s["to"]
        var direction := (to - from).normalized()
        var progress: float = clampf(float(s["age"]) / float(s["life"]), 0.0, 1.0)
        var at := from.lerp(to, progress)
        var basis := Basis.looking_at(direction, Vector3.UP)
        basis = basis.scaled(Vector3(1, 1, 2.4))
        beam_batch.multimesh.set_instance_transform(i, Transform3D(basis, at))
    beam_batch.multimesh.visible_instance_count = count
    count = mini(sparks.size(), spark_batch.multimesh.instance_count)
    for i in range(count):
        var item: Dictionary = sparks[i]
        var t: float = 1.0 - clampf(float(item["age"]) / float(item["life"]), 0.0, 1.0)
        var scale := maxf(0.05, t * float(item["size"]))
        spark_batch.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * scale), item["pos"]))
    spark_batch.multimesh.visible_instance_count = count
