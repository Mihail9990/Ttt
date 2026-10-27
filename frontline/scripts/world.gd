extends Node3D
const Assets = preload("res://scripts/assets.gd")
## Two carefully laid-out battlefields made from PBR primitives and procedural textures.
## Optimized for Godot 4 GLES3 compatibility and entry-level Android GPUs.

var player_spawn := Vector3(0, 1.1, 25)
var extraction_position := Vector3(0, 1.2, -47)
var palette: Dictionary = {}
var rng := RandomNumberGenerator.new()
var battlefield := 0
var rotor: Node3D
var beacon: Node3D
var scene_clock := 0.0

func generate(index: int) -> void:
    battlefield = index
    rng.seed = 885410 + index * 173
    _materials()
    _environment(index)
    _ground(index)
    if index == 0:
        _mountain_base()
    else:
        _broken_city()
    _marker()
    _boundary()

func _process(dt: float) -> void:
    scene_clock += dt
    if is_instance_valid(rotor):
        rotor.rotate_y(dt * 13.0)
    if is_instance_valid(beacon):
        beacon.rotate_y(dt * 1.5)
        beacon.position.y = 1.7 + sin(scene_clock * 1.8) * 0.12

func _tex(base: Color, seed_offset: int, grime: float = 0.28) -> Texture2D:
    var noise := FastNoiseLite.new()
    noise.seed = 10033 + seed_offset
    noise.frequency = 0.105
    noise.fractal_type = FastNoiseLite.FRACTAL_FBM
    noise.fractal_octaves = 4
    var fine := FastNoiseLite.new()
    fine.seed = seed_offset + 45679
    fine.frequency = 0.37
    var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
    for y in range(128):
        for x in range(128):
            var n := noise.get_noise_2d(float(x), float(y))
            var f := fine.get_noise_2d(float(x), float(y))
            var value: float = clampf(0.88 + n * grime + f * 0.16, 0.35, 1.15)
            img.set_pixel(x, y, Color(
                clampf(base.r * value, 0.0, 1.0),
                clampf(base.g * value, 0.0, 1.0),
                clampf(base.b * value, 0.0, 1.0),
                1.0
            ))
    img.generate_mipmaps()
    return ImageTexture.create_from_image(img)

func _material(color: Color, metallic: float = 0.0, roughness: float = 0.8, emissive: float = 0.0, tx: int = -1) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.metallic = metallic
    mat.roughness = roughness
    if tx >= 0:
        mat.albedo_texture = _tex(Color.WHITE, tx)
        mat.uv1_triplanar = true
        mat.uv1_scale = Vector3(0.45, 0.45, 0.45)
    if emissive > 0:
        mat.emission_enabled = true
        mat.emission = color
        mat.emission_energy_multiplier = emissive
    return mat

func _pbr(folder: String, tint: Color, tile: float = 0.22, metal: float = 0.0) -> StandardMaterial3D:
    var mat := _material(tint, metal, 0.9)
    var prefix := "res://assets/textures/" + folder + "/"
    if ResourceLoader.exists(prefix + "Color.webp"):
        mat.albedo_texture = load(prefix + "Color.webp")
        mat.uv1_triplanar = true
        mat.uv1_scale = Vector3(tile, tile, tile)
        mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
        if ResourceLoader.exists(prefix + "NormalGL.webp"):
            mat.normal_enabled = true
            mat.normal_texture = load(prefix + "NormalGL.webp")
            mat.normal_scale = 0.75
        if ResourceLoader.exists(prefix + "Roughness.webp"):
            mat.roughness_texture = load(prefix + "Roughness.webp")
            mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
    return mat

func _materials() -> void:
    palette["soil"] = _material(Color("#685f52"), 0.0, 0.95, 0.0, 21)
    palette["road"] = _material(Color("#383d40"), 0.0, 0.96, 0.0, 33)
    palette["concrete"] = _material(Color("#979389"), 0.0, 0.88, 0.0, 43)
    palette["wall"] = _material(Color("#9c9585"), 0.0, 0.91, 0.0, 49)
    palette["sand"] = _material(Color("#95836b"), 0.0, 0.99, 0.0, 29)
    palette["rock"] = _material(Color("#5d605c"), 0.05, 0.92, 0.0, 15)
    palette["foliage"] = _material(Color("#334639"), 0.0, 0.96, 0.0, 65)
    palette["foliage2"] = _material(Color("#43574a"), 0.0, 0.96, 0.0, 66)
    palette["metal"] = _material(Color("#474b49"), 0.75, 0.48, 0.0, 9)
    palette["rust"] = _material(Color("#6b4835"), 0.45, 0.88, 0.0, 83)
    palette["dark"] = _material(Color("#1a2228"), 0.3, 0.37)
    palette["glass"] = _material(Color("#30434d"), 0.55, 0.18)
    palette["beacon"] = _material(Color("#70eaca"), 0.25, 0.28, 3.5)
    palette["lamp"] = _material(Color("#ffd49b"), 0.0, 0.38, 3.0)
    palette["yellow"] = _material(Color("#d3a857"), 0.25, 0.6)
    palette["smoke"] = _material(Color("#343a3b"))
    # Genuine CC0 ambientCG PBR surfaces; original procedural materials remain as fallback.
    palette["soil"] = _pbr("Ground110", Color("#b8b3a7"), 0.18)
    palette["sand"] = _pbr("Ground110", Color("#d5bda0"), 0.19)
    palette["road"] = _pbr("Asphalt031", Color("#a5a7aa"), 0.23)
    palette["concrete"] = _pbr("Concrete034", Color("#c8c1b3"), 0.27)
    palette["wall"] = _pbr("Bricks097", Color("#adacaa"), 0.24)
    palette["rock"] = _pbr("PavingStones138", Color("#777c77"), 0.22)
    palette["metal"] = _pbr("Metal046B", Color("#c0c1bd"), 0.31, 0.75)
    palette["facade"] = _pbr("Concrete034", Color("#e1ded6"), 0.24)


func _environment(index: int) -> void:
    var world_environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    var procedural := ProceduralSkyMaterial.new()
    if index == 0:
        procedural.sky_top_color = Color("#3e596e")
        procedural.sky_horizon_color = Color("#c9a88b")
        procedural.ground_bottom_color = Color("#343b39")
        procedural.ground_horizon_color = Color("#aaa294")
        env.ambient_light_color = Color("#c4d3dd")
    else:
        procedural.sky_top_color = Color("#566777")
        procedural.sky_horizon_color = Color("#d5ae83")
        procedural.ground_bottom_color = Color("#3f4044")
        procedural.ground_horizon_color = Color("#aca39a")
        env.ambient_light_color = Color("#c0c6cf")
    sky.sky_material = procedural
    var panorama_path := "res://assets/textures/sunset.hdr"
    if ResourceLoader.exists(panorama_path):
        var pano := PanoramaSkyMaterial.new()
        pano.panorama = load(panorama_path)
        sky.sky_material = pano
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_energy = 0.35
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.tonemap_exposure = 1.06
    env.fog_enabled = true
    env.fog_density = 0.005 if index == 0 else 0.006
    env.fog_sun_scatter = 0.33
    world_environment.environment = env
    add_child(world_environment)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-35, -55 if index == 0 else 34, 0)
    sun.light_color = Color("#ffe2bb")
    sun.light_energy = 1.6
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 70.0
    add_child(sun)

func _box(pos: Vector3, size: Vector3, mat: Material, solid: bool = false, parent: Node3D = null) -> MeshInstance3D:
    var owner_node: Node3D = parent if is_instance_valid(parent) else self
    var node := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    node.mesh = mesh
    node.material_override = mat
    node.position = pos
    owner_node.add_child(node)
    if solid:
        var obstacle := StaticBody3D.new()
        owner_node.add_child(obstacle)
        obstacle.position = pos
        var shape := CollisionShape3D.new()
        var body := BoxShape3D.new()
        body.size = size
        shape.shape = body
        obstacle.add_child(shape)
    return node

func _cylinder(pos: Vector3, top: float, bottom: float, height: float, mat: Material, parent: Node3D = null) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    var mesh := CylinderMesh.new()
    mesh.top_radius = top
    mesh.bottom_radius = bottom
    mesh.height = height
    mesh.radial_segments = 9
    node.mesh = mesh
    node.material_override = mat
    (parent if is_instance_valid(parent) else self).add_child(node)
    node.position = pos
    return node

func _ball(pos: Vector3, size: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    var mesh := SphereMesh.new()
    mesh.radius = 0.5
    mesh.height = 1.0
    mesh.radial_segments = 12
    mesh.rings = 6
    node.mesh = mesh
    node.material_override = mat
    node.position = pos
    node.scale = size
    (parent if is_instance_valid(parent) else self).add_child(node)
    return node

func _ground(index: int) -> void:
    _box(Vector3(0, -0.62, -12), Vector3(152, 1.2, 175), palette["soil"] if index == 0 else palette["sand"], true)
    _box(Vector3(0, -0.035, -11), Vector3(12.5 if index == 0 else 16.0, 0.08, 115), palette["road"], false)
    if index == 1:
        _box(Vector3(0, -0.025, -18), Vector3(110, 0.07, 14), palette["road"])
        _box(Vector3(0, -0.025, -42), Vector3(110, 0.07, 12), palette["road"])
        for z in range(-58, 38, 8):
            _box(Vector3(0, 0.012, float(z)), Vector3(0.22, 0.016, 3.1), palette["wall"])
    else:
        for z in range(-55, 38, 8):
            _box(Vector3(0, 0.005, float(z)), Vector3(0.13, 0.016, 2.2), palette["sand"])
    for z in range(-55, 40, 13):
        for x in [-7.2, 7.2]:
            _box(Vector3(x, 0.03, float(z)), Vector3(0.22, 0.12, 5.0), palette["concrete"])

func _tree_batch() -> void:
    var trunks := MultiMesh.new()
    var trunk_mesh := CylinderMesh.new()
    trunk_mesh.top_radius = 0.12
    trunk_mesh.bottom_radius = 0.24
    trunk_mesh.height = 3.4
    trunk_mesh.radial_segments = 5
    trunks.transform_format = MultiMesh.TRANSFORM_3D
    trunks.mesh = trunk_mesh
    var leaves := MultiMesh.new()
    var cone := CylinderMesh.new()
    cone.top_radius = 0.0
    cone.bottom_radius = 1.8
    cone.height = 6.2
    cone.radial_segments = 6
    leaves.transform_format = MultiMesh.TRANSFORM_3D
    leaves.mesh = cone
    var locations: Array[Vector3] = []
    for i in range(154):
        var x: float = rng.randf_range(10.0, 64.0) * (-1.0 if i % 2 == 0 else 1.0)
        var z: float = rng.randf_range(-70.0, 56.0)
        locations.append(Vector3(x, 0, z))
    trunks.instance_count = locations.size()
    leaves.instance_count = locations.size()
    for i in locations.size():
        var p: Vector3 = locations[i]
        var scale_var: float = rng.randf_range(0.68, 1.55)
        trunks.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(scale_var, scale_var, scale_var)), p + Vector3(0, 1.7 * scale_var, 0)))
        leaves.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(scale_var, scale_var, scale_var)), p + Vector3(0, 4.5 * scale_var, 0)))
    var wood_node := MultiMeshInstance3D.new()
    wood_node.multimesh = trunks
    wood_node.material_override = palette["rust"]
    add_child(wood_node)
    var tree_node := MultiMeshInstance3D.new()
    tree_node.multimesh = leaves
    tree_node.material_override = palette["foliage"]
    add_child(tree_node)

func _rock(pos: Vector3, sz: Vector3) -> void:
    var rock := _ball(pos, sz, palette["rock"])
    rock.rotation_degrees = Vector3(rng.randf_range(-12, 12), rng.randf_range(-180, 180), rng.randf_range(-10, 10))
    if sz.x > 5:
        _box(pos + Vector3(0, -1.1, 0), Vector3(sz.x * 0.75, sz.y * 0.6, sz.z * 0.72), palette["rock"], true).visible = false

func _crate(pos: Vector3, sz: float = 1.0) -> void:
    var crate_visual: Node3D = Assets.add_ground_model(
        self, "crate", pos - Vector3(0, sz * 0.5, 0), sz, rng.randf_range(-PI, PI))
    if crate_visual != null:
        _box(pos, Vector3(sz * 0.88, sz, sz * 0.88), palette["dark"], true).visible = false
        return
    _box(pos, Vector3(sz, sz, sz), palette["rust"], true)
    for y in [-0.32, 0.32]:
        _box(pos + Vector3(0, y * sz, sz * 0.51), Vector3(sz, 0.06, 0.045), palette["metal"])
    for x in [-0.35, 0.35]:
        _box(pos + Vector3(x * sz, 0, sz * 0.51), Vector3(0.05, sz, 0.045), palette["metal"])

func _sandbags(center: Vector3, length: int = 6) -> void:
    for i in range(length):
        var px := center.x + (i - (length - 1) * 0.5) * 0.63
        for layer in range(2):
            _ball(Vector3(px + layer * 0.15, 0.24 + layer * 0.43, center.z), Vector3(1.3, 0.35, 0.7), palette["sand"])

func _building(center: Vector3, width: float, depth: float, height: float, ruined: bool = false) -> void:
    var mat: Material = palette["wall"] if ruined else palette["facade"]
    _box(center + Vector3(0, height * 0.5, 0), Vector3(width, height, depth), mat, true)
    _box(center + Vector3(0, height + 0.18, 0), Vector3(width + 0.36, 0.35, depth + 0.36), palette["rock"])
    var floors: int = int(floor(height / 3.2))
    for f in floors:
        var y: float = center.y + f * 3.1 + 2.05
        # Architectural relief: heavy floor bands, deep window sills and balcony edges.
        for side in [-1.0, 1.0]:
            _box(center + Vector3(0, y - center.y - 1.23, side * (depth * 0.5 + 0.18)),
                Vector3(width + 0.2, 0.16, 0.38), palette["concrete"])
        for side in [-1.0, 1.0]:
            _box(center + Vector3(side * (width * 0.5 + 0.13), y - center.y - 1.23, 0),
                Vector3(0.30, 0.14, depth + 0.2), palette["concrete"])

        for side in [-1.0, 1.0]:
            for j in range(maxi(1, int(width / 3.1))):
                var wx: float = -width * 0.5 + (j + 0.5) * width / maxi(1, int(width / 3.1))
                _box(center + Vector3(wx, y - center.y, side * (depth * 0.5 + 0.028)), Vector3(1.10, 1.25, 0.055), palette["glass"])
                _box(center + Vector3(wx, y - center.y + 0.72, side * (depth * 0.5 + 0.08)), Vector3(1.4, 0.08, 0.17), palette["rust"])
        for side in [-1.0, 1.0]:
            for j in range(maxi(1, int(depth / 3.5))):
                var wz: float = -depth * 0.5 + (j + 0.5) * depth / maxi(1, int(depth / 3.5))
                _box(center + Vector3(side * (width * 0.5 + 0.03), y - center.y, wz), Vector3(0.07, 1.3, 1.0), palette["dark"])
    if ruined:
        _rock(center + Vector3(width * 0.3, 0.6, depth * 0.42), Vector3(3.4, 1.6, 3.0))

func _watchtower(pos: Vector3) -> void:
    for x in [-1.8, 1.8]:
        for z in [-1.8, 1.8]:
            _box(pos + Vector3(x, 4.5, z), Vector3(0.35, 9, 0.35), palette["metal"])
    _box(pos + Vector3(0, 9, 0), Vector3(5.5, 0.35, 5.5), palette["rust"])
    _box(pos + Vector3(0, 11.3, 0), Vector3(6.2, 0.3, 6.2), palette["dark"])
    for x in [-2.6, 2.6]:
        _box(pos + Vector3(x, 10, 0), Vector3(0.15, 1.2, 5.4), palette["metal"])

func _vehicle(pos: Vector3, armored: bool = false) -> void:
    # A photographed wreck is far more convincing than a car made of boxes.
    if battlefield == 1:
        var wreck: Node3D = Assets.add_ground_model(
            self, "destroyed_car", pos, 1.84, rng.randf_range(-1.3, 1.3))
        if wreck != null:
            _box(pos + Vector3(0, 0.95, 0), Vector3(2.2, 1.85, 4.3), palette["metal"], true).visible = false
            return
    var body := _box(pos + Vector3(0, 0.98, 0), Vector3(2.65, 1.24, 5.0), palette["metal"], true)
    body.rotation_degrees.y = 1
    _box(pos + Vector3(0, 1.85, -0.20), Vector3(2.1, 0.8, 2.7), palette["rust"])
    _box(pos + Vector3(0, 1.94, -1.58), Vector3(1.8, 0.64, 0.12), palette["glass"])
    for xx in [-1.3, 1.3]:
        for zz in [-1.4, 1.55]:
            var tire := _cylinder(pos + Vector3(xx, 0.52, zz), 0.6, 0.6, 0.34, palette["dark"])
            tire.rotate_z(PI * 0.5)
    if armored:
        _box(pos + Vector3(0, 2.35, 0.6), Vector3(1.4, 0.5, 1.6), palette["metal"])
        _cylinder(pos + Vector3(0, 2.62, -0.65), 0.10, 0.14, 3.5, palette["dark"]).rotation.x = PI * 0.5

func _antenna(pos: Vector3) -> void:
    for i in range(4):
        _box(pos + Vector3(0, 1.25 + i * 2.5, 0), Vector3(0.28, 2.5, 0.28), palette["metal"])
    for y in [3.0, 5.0, 7.0, 9.0]:
        _box(pos + Vector3(0, y, 0), Vector3(4.0, 0.15, 0.18), palette["dark"])
        _box(pos + Vector3(0, y, 0), Vector3(0.18, 0.15, 4.0), palette["dark"])
    _ball(pos + Vector3(0, 10.5, 0), Vector3(0.55, 0.55, 0.55), palette["lamp"])

func _smoke(pos: Vector3) -> void:
    for i in range(6):
        var mat := StandardMaterial3D.new()
        mat.albedo_color = Color(0.29, 0.3, 0.32, 0.22)
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        var center := pos + Vector3(rng.randf_range(-1.0, 1.0), 1.0 + float(i) * 1.7, rng.randf_range(-1.0, 1.0))
        _ball(center, Vector3(2.4 + i * 0.6, 1.6 + i * 0.7, 2.4 + i * 0.6), mat)
    _ball(pos + Vector3(0, 0.7, 0), Vector3(1.5, 1.1, 1.5), palette["yellow"])

func _mountain_base() -> void:
    _tree_batch()
    for i in range(26):
        var side := -1.0 if i % 2 == 0 else 1.0
        var x := side * rng.randf_range(17.0, 60.0)
        var z := rng.randf_range(-82, 50)
        _rock(Vector3(x, rng.randf_range(-0.5, 3.0), z), Vector3(rng.randf_range(5, 15), rng.randf_range(5, 17), rng.randf_range(7, 19)))
    for i in range(50):
        var sx := rng.randf_range(8, 14) * (-1.0 if i % 2 == 0 else 1.0)
        _rock(Vector3(sx, 0.15, rng.randf_range(-63, 38)), Vector3(rng.randf_range(0.7, 2.2), rng.randf_range(0.4, 1.2), rng.randf_range(0.7, 2.4)))
    _watchtower(Vector3(-12.5, 0, -37))
    _watchtower(Vector3(12.5, 0, -37))
    _building(Vector3(-16, 0, -48), 12, 12, 6.7, false)
    _building(Vector3(16, 0, -50), 13, 11, 6.5, false)
    _sandbags(Vector3(0, 0, -14), 11)
    _sandbags(Vector3(0, 0, -35), 11)
    _sandbags(Vector3(-3, 0, 3), 5)
    _crate(Vector3(-6.5, 0.65, -7), 1.3)
    _crate(Vector3(8.5, 0.65, -30), 1.3)
    Assets.add_ground_model(self, "ammo_box", Vector3(-3, 0, -11), 0.4)
    _crate(Vector3(10, 0.5, -31), 1.0)
    _vehicle(Vector3(-7.5, 0, 12.5), true)
    _antenna(Vector3(0, 0, -49))
    _smoke(Vector3(13, 0, -66))
    player_spawn = Vector3(0, 1.1, 30)
    extraction_position = Vector3(0, 1.1, -48)

func _broken_city() -> void:
    for i in range(14):
        var x: float = (-1.0 if i % 2 == 0 else 1.0) * rng.randf_range(22.0, 34.0)
        var z: float = -58 + floor(float(i) / 2.0) * 13.4
        var height := rng.randf_range(9.0, 20.0)
        _building(Vector3(x, 0, z), rng.randf_range(9, 15), rng.randf_range(8, 13), height, i % 3 == 0)
    for i in range(42):
        var side: float = -1.0 if i % 2 == 0 else 1.0
        var x := side * rng.randf_range(9.5, 19.0)
        var z := rng.randf_range(-59, 38)
        _rock(Vector3(x, 0.1, z), Vector3(rng.randf_range(0.6, 3.2), rng.randf_range(0.25, 1.6), rng.randf_range(0.6, 3.4)))
    _vehicle(Vector3(5, 0, -12), true)
    _vehicle(Vector3(-5, 0, 16), false)
    _vehicle(Vector3(-11, 0, -39), true)
    _crate(Vector3(8.5, 0.75, -22), 1.5)
    _crate(Vector3(-8.3, 0.5, -29), 1.0)
    _sandbags(Vector3(0, 0, -34), 7)
    # Authored Poly Haven street furniture and cover models, CC0.
    for prop_location in [
        Vector3(-4, 0, -4), Vector3(7, 0, -24), Vector3(-8, 0, -36)
    ]:
        var cover: Node3D = Assets.add_ground_model(
            self, "road_barrier", prop_location, 1.12, rng.randf_range(-0.35, 0.35))
        if cover != null:
            _box(prop_location + Vector3(0, 0.55, 0), Vector3(2.55, 1.10, 0.55), palette["rock"], true).visible = false
    for barrel_location in [Vector3(9, 0, -3), Vector3(-10, 0, -23), Vector3(9.5, 0, -45)]:
        Assets.add_ground_model(self, "barrel", barrel_location, 1.0)
    for lamp_z in [-47.0, -15.0, 16.0, 33.0]:
        Assets.add_ground_model(self, "street_lamp", Vector3(-12.7, 0, lamp_z), 8.1, PI)
        Assets.add_ground_model(self, "street_lamp", Vector3(12.7, 0, lamp_z), 8.1)
    Assets.add_ground_model(self, "ammo_box", Vector3(-8.2, 0, -29), 0.36)
    Assets.add_ground_model(self, "generator", Vector3(13.2, 0, -40), 1.2)
    _smoke(Vector3(-15, 0, -15))
    _smoke(Vector3(17, 0, -45))
    _helicopter(Vector3(0, 7.4, -50))
    player_spawn = Vector3(0, 1.1, 31)
    extraction_position = Vector3(0, 1.2, -50)

func _helicopter(pos: Vector3) -> void:
    var imported: Node3D = Assets.add_ground_model(
        self, "helicopter", pos - Vector3(0, 1.4, 0), 3.2, -PI * 0.5)
    if imported != null:
        return
    var heli := Node3D.new()
    add_child(heli)
    heli.position = pos
    _ball(Vector3(0, 0, 0), Vector3(4.8, 2.1, 2.1), palette["metal"], heli)
    _box(Vector3(0, 0.15, 3.1), Vector3(0.35, 0.35, 5.8), palette["dark"], false, heli)
    _box(Vector3(0, 0.42, -1.3), Vector3(2.8, 1.1, 0.15), palette["glass"], false, heli)
    for side in [-1.0, 1.0]:
        _box(Vector3(side * 1.3, -1.25, 0), Vector3(0.18, 0.14, 3.0), palette["metal"], false, heli)
    rotor = Node3D.new()
    heli.add_child(rotor)
    rotor.position.y = 1.5
    _box(Vector3.ZERO, Vector3(11.0, 0.07, 0.23), palette["dark"], false, rotor)
    _box(Vector3.ZERO, Vector3(0.23, 0.07, 11.0), palette["dark"], false, rotor)

func _marker() -> void:
    beacon = Node3D.new()
    beacon.position = extraction_position + Vector3(0, 0.65, 0)
    add_child(beacon)
    _cylinder(Vector3.ZERO, 1.4, 1.4, 0.06, palette["beacon"], beacon)
    _cylinder(Vector3(0, 1.2, 0), 0.09, 0.09, 2.3, palette["beacon"], beacon)
    _ball(Vector3(0, 2.5, 0), Vector3(0.45, 0.45, 0.45), palette["beacon"], beacon)

func _boundary() -> void:
    # Invisible anti-fall walls around the compact mission sandbox.
    var wall_mat := StandardMaterial3D.new()
    wall_mat.albedo_color = Color(0, 0, 0, 0)
    for x in [-70.0, 70.0]:
        _box(Vector3(x, 4, -12), Vector3(2, 8, 170), wall_mat, true).visible = false
    for z in [-80.0, 60.0]:
        _box(Vector3(0, 4, z), Vector3(144, 8, 2), wall_mat, true).visible = false
