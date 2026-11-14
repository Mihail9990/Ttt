"""Run inside the UE 5.6 Editor after compiling SkyIslandsEditor.

Creates the cookable starter map. Runtime SkyGameMode populates terrain and gameplay.
Idempotent: existing maps and unrelated user actors are preserved.
"""
import unreal

MAP_PATH = "/Game/Maps/SkyWorld"
GAME_MODE = "/Script/SkyIslands.SkyGameMode"


def create_world():
    if unreal.load_class(None, GAME_MODE) is None:
        raise RuntimeError("Compile SkyIslandsEditor before creating the map")
    levels = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    actors = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
    unreal.EditorAssetLibrary.make_directory("/Game/Maps")
    if unreal.EditorAssetLibrary.does_asset_exist(MAP_PATH):
        if not levels.load_level(MAP_PATH):
            raise RuntimeError("Could not load existing SkyWorld map")
    elif not levels.new_level(MAP_PATH, False):
        raise RuntimeError("Could not create SkyWorld map")
    known = {a.get_actor_label(): a for a in actors.get_all_level_actors()}

    def ensure(label, cls, location, rotation=None):
        actor = known.get(label)
        if actor is None:
            actor = actors.spawn_actor_from_class(cls, unreal.Vector(*location))
            if actor is None:
                raise RuntimeError("Could not spawn " + label)
            actor.set_actor_label(label)
        if rotation is not None:
            actor.set_actor_rotation(unreal.Rotator(*rotation), False)
        return actor

    ensure("Sky_PlayerStart", unreal.PlayerStart, (-800, 0, 500))
    sun = ensure("Sky_Sun", unreal.DirectionalLight, (0, 0, 12000), (-25, -35, 0))
    sun_component = sun.get_component_by_class(unreal.DirectionalLightComponent)
    sun_component.set_editor_property("mobility", unreal.ComponentMobility.MOVABLE)
    sun_component.set_editor_property("intensity", 50000.0)
    sun_component.set_editor_property("light_source_angle", 0.8)
    sun_component.set_editor_property("atmosphere_sun_light", True)

    sky = ensure("Sky_Ambient", unreal.SkyLight, (0, 0, 5000))
    sky_component = sky.get_component_by_class(unreal.SkyLightComponent)
    sky_component.set_editor_property("mobility", unreal.ComponentMobility.MOVABLE)
    sky_component.set_editor_property("intensity", 1.0)
    sky_component.set_editor_property("real_time_capture", True)
    ensure("Sky_Atmosphere", unreal.SkyAtmosphere, (0, 0, -10000))
    fog = ensure("Sky_CloudSeaFog", unreal.ExponentialHeightFog, (0, 0, -1800))
    fog_component = fog.get_component_by_class(unreal.ExponentialHeightFogComponent)
    fog_component.set_editor_property("fog_density", 0.012)
    fog_component.set_editor_property("fog_height_falloff", 0.2)
    fog_component.set_editor_property("volumetric_fog", True)

    volume = ensure("Sky_CinematicPost", unreal.PostProcessVolume, (0, 0, 0))
    volume.set_editor_property("unbound", True)
    settings = volume.get_editor_property("settings")
    settings.set_editor_property("override_bloom_intensity", True)
    settings.set_editor_property("bloom_intensity", 0.25)
    settings.set_editor_property("override_motion_blur_amount", True)
    settings.set_editor_property("motion_blur_amount", 0.0)
    volume.set_editor_property("settings", settings)
    if not levels.save_current_level():
        raise RuntimeError("Could not save SkyWorld map")
    unreal.log("SKY_WORLD_BOOTSTRAP_OK " + MAP_PATH)


if __name__ == "__main__":
    create_world()
