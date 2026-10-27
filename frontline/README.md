# FRONTLINE: CONFLICT (Android)

Two-mission **offline first-person shooter** prototype for Android. Fully separate from the original Kotlin APK Starter in this repository.

## Gameplay

- **Mission 1 — ПРОРЫВ:** assault the mountain communications outpost, defeat the 6 defenders, then reach the active radio beacon.
- **Mission 2 — ЭВАКУАЦИЯ:** fight through the ruined city, survive two waves of opponents (4 + 5), then reach the extraction beacon beneath the helicopter.
- 3D first-person movement, mouse/touch aiming, rapid-fire assault rifle, 30-round magazine and reload, recoil, sight zoom, damage, death, enemy AI, line-of-sight fire, HUD radar.
- Authored procedural environment: valley terrain, 150+ conifers, concrete base, radio towers, crates, roadblocks, armored vehicles, urban ruins and rooftop helicopter.
- Generated original shot, impact, reload and completion SFX. No third-party assets or server calls.
- Godot **4.5.2**, **GL Compatibility** for broader midrange Android support.

## Controls

**Android (landscape):**
- Left thumb: hold/drag at bottom left to move.
- Right half, outside action buttons: drag to look.
- Big **ОГОНЬ** button: hold to fire.
- **ПРИЦЕЛ** button: hold to zoom/aim.
- **R** upper right: reload.
- **БЕГ** upper left: hold to sprint while moving forward.
- On the menu, tap mission card to choose, then **НАЧАТЬ ОПЕРАЦИЮ**.
- On mission completed/defeat, tap to continue/retry.

**Keyboard/mouse:** WASD, Shift sprint, Space jump, mouse to aim, left mouse shooting, right mouse sight, R reload, Esc/P pause.

## Build an Android APK from your phone

1. Open [Build FRONTLINE Android](https://github.com/Mihail9990/Ttt/actions/workflows/build-frontline.yml).
2. Select the latest successful run (green check), or **Run workflow**.
3. Download artifact `Frontline-Conflict-Android-...`.
4. Unzip, tap `Frontline-Conflict-....apk`, and install.

This is a **separate Android app** (`com.mihail9990.frontlineconflict`) — it does not replace the Kotlin APK Starter.

APK uses the repository's existing fixed **test** key from `signing/test-debug.jks`, no GitHub Secrets. It is intentionally **not a secure publishing key**.

## Graphics expectations

The atmospheric poster is a **concept illustration**, not an in-engine render. This first playable vertical slice uses procedural meshes and materials, not photogrammetry, advanced global illumination or AAA character animation. The GLES3 renderer prioritizes compatibility with a Samsung A22-class phone. The actual device's FPS must be measured by testing the APK.

## Source tree

- `scripts/game.gd`: level lifecycle, mission progression and combat effects
- `scripts/world.gd`: two scenes, props, terrain, lights and material generation
- `scripts/player.gd`: first-person player and 3D weapon
- `scripts/soldier.gd`: enemy model, patrol/attack/damage behavior
- `scripts/hud.gd`: mobile touch controller and menu/pause logic
- `scripts/ui_surface.gd`: all 2D HUD rendering
- `scripts/sound.gd`: original generated PCM sound effects
- `tests/smoke_test.gd`: Godot headless level generator smoke test
- `export_presets.cfg`: Android export configuration

This prototype is not connected with, endorsed by, or derived from EA/DICE/Battlefield.
