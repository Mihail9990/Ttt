class_name SkyArt
extends RefCounted
## Actual CC0 PBR assets and a modest real-time environment; no image backdrop.

const MODEL_PATHS: Dictionary = {
	"drill": "res://assets/models/Drill_01/Drill_01_1k.gltf",
	"hammer": "res://assets/models/wooden_hammer_01/wooden_hammer_01_1k.gltf",
	"tree": "res://assets/models/pine_sapling_small/pine_sapling_small_variant0.gltf",
	"rock": "res://assets/models/boulder_01/boulder_01_1k.gltf",
}
static var _materials: Dictionary = {}


static func _texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


static func material(kind: String) -> Material:
	var key: String = kind
	if kind in ["soil", "ground", "grass", "clay", "sand"]:
		key = "ground"
	elif kind in ["stone", "rock", "ore"]:
		key = "rock"
	elif kind in ["timber", "wood", "board", "beam"]:
		key = "wood"
	elif kind in ["nail", "screw", "metal"]:
		key = "metal"
	if _materials.has(key):
		return _materials[key] as Material
	var result := StandardMaterial3D.new()
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	result.roughness = 0.86
	result.albedo_color = Color("766d5b")
	if key in ["ground", "rock", "wood", "brick"]:
		var folder: String = "res://assets/materials/" + key + "/"
		result.albedo_texture = _texture(folder + "base_color.jpg")
		result.roughness_texture = _texture(folder + "roughness.jpg")
		result.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		result.normal_texture = _texture(folder + "normal_gl.png")
		result.normal_enabled = result.normal_texture != null
		result.normal_scale = 0.45 if key == "ground" else 0.65
		if result.albedo_texture != null:
			result.albedo_color = Color.WHITE
		if key == "ground":
			result.albedo_color = Color(0.79, 0.77, 0.70)
			result.roughness = 1.0
			result.metallic_specular = 0.2
		elif key == "rock":
			result.albedo_color = Color(0.84, 0.85, 0.84)
			result.roughness = 0.97
			result.metallic_specular = 0.28
		if key in ["ground", "rock"]:
			# Metre-based mapping avoids stretched textures on mined cave surfaces.
			result.uv1_triplanar = true
			result.uv1_world_triplanar = true
			result.uv1_scale = Vector3.ONE * (0.45 if key == "ground" else 0.3)
			result.uv1_triplanar_sharpness = 4.0
	elif key == "metal":
		result.albedo_color = Color("858d91")
		result.metallic = 0.86
		result.roughness = 0.29
	elif key == "leaf":
		result.albedo_color = Color("354d2d")
		result.roughness = 0.93
	elif key == "glass":
		result.albedo_color = Color(0.66, 0.81, 0.87, 0.28)
		result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		result.roughness = 0.12
	elif key == "preview":
		result.albedo_color = Color(0.18, 0.85, 0.78, 0.30)
		result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		result.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = result
	return result


static func model(kind: String) -> Node3D:
	var path: String = str(MODEL_PATHS.get(kind, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var instance := scene.instantiate() as Node3D
	if instance == null:
		return null
	# Imported glTF scene keeps its own bark/foliage/tool material slots and UVs.
	for child in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		mesh.visibility_range_end = 170.0
		mesh.visibility_range_end_margin = 18.0
		mesh.lod_bias = 0.65
	return instance


static func build_environment(parent: Node3D) -> void:
	var world := WorldEnvironment.new()
	world.name = "SkyEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("4b789a")
	sky_material.sky_horizon_color = Color("c5d1d4")
	sky_material.ground_bottom_color = Color("6c8495")
	sky_material.ground_horizon_color = Color("c4d1d7")
	sky_material.sky_curve = 0.17
	sky_material.ground_curve = 0.12
	sky_material.sun_angle_max = 1.2
	sky_material.sun_curve = 0.08
	var cloud_noise := FastNoiseLite.new()
	cloud_noise.seed = 441
	cloud_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cloud_noise.frequency = 0.012
	cloud_noise.fractal_octaves = 4
	var cloud_texture := NoiseTexture2D.new()
	cloud_texture.width = 512
	cloud_texture.height = 256
	cloud_texture.noise = cloud_noise
	cloud_texture.seamless = true
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.48, 0.62, 0.78, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.87, 0.9, 0.92, 0.0), Color(0.87, 0.9, 0.92, 0.0),
		Color(0.93, 0.94, 0.94, 0.22), Color(0.95, 0.96, 0.96, 0.76),
		Color(0.98, 0.98, 0.98, 0.94),
	])
	cloud_texture.color_ramp = gradient
	sky_material.sky_cover = cloud_texture
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.38
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.82
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_depth_begin = 85.0
	environment.fog_depth_end = 550.0
	environment.fog_depth_curve = 1.6
	environment.fog_light_color = Color("c0d0d9")
	environment.fog_light_energy = 0.6
	environment.fog_sky_affect = 0.18
	world.environment = environment
	parent.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "MorningSun"
	sun.rotation_degrees = Vector3(-31.0, -28.0, 0.0)
	sun.light_color = Color("ffe4bc")
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 95.0
	sun.directional_shadow_blend_splits = true
	parent.add_child(sun)
	_build_cloud_sea(parent)


static func _build_cloud_sea(parent: Node3D) -> void:
	# One procedural transparent cloud sheet plus depth fog. This is intentionally
	# a budget real-time approximation, not desktop-only volumetric cloud raymarching.
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float n(vec2 p) {
 vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(h(i),h(i+vec2(1.0,0.0)),f.x),mix(h(i+vec2(0.0,1.0)),h(i+vec2(1.0,1.0)),f.x),f.y);
}
void fragment() {
 vec2 p=UV*25.0+vec2(TIME*0.004,0.0);
 float c=n(p)*0.56+n(p*2.1)*0.28+n(p*4.3)*0.16;
 float a=smoothstep(0.26,0.72,c);
 ALBEDO=mix(vec3(0.58,0.68,0.76),vec3(0.91,0.94,0.96),c);
 ALPHA=a*0.93;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	var plane := PlaneMesh.new()
	plane.size = Vector2(1400.0, 1400.0)
	var clouds := MeshInstance3D.new()
	clouds.name = "CloudSea"
	clouds.mesh = plane
	clouds.material_override = material
	clouds.position.y = -33.0
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(clouds)
