# Godot: реалистичные исходные ассеты

Используется ранее проверенный набор Poly Haven, закреплённый в `../sky_islands/ArtSource/manifest.json`: **8 ассетов, 35 исходных файлов, 24 891 597 байт**. Все исходные файлы проверяются по размеру и SHA-256 до копирования. Набор открытый, CC0-1.0; он не требует входа Epic/Fab.

| Ассет | Авторы | Лицензия |
|---|---|---|
| [Drill_01](https://polyhaven.com/a/Drill_01) | Fernando Quinn | CC0-1.0 |
| [wooden_hammer_01](https://polyhaven.com/a/wooden_hammer_01) | James Ray Cock | CC0-1.0 |
| [wood_planks](https://polyhaven.com/a/wood_planks) | Amal Kumar | CC0-1.0 |
| [brown_mud_03](https://polyhaven.com/a/brown_mud_03) | Rob Tuytel | CC0-1.0 |
| [rock_boulder_cracked](https://polyhaven.com/a/rock_boulder_cracked) | Dario Barresi, Dimitrios Savva | CC0-1.0 |
| [brick_wall_001](https://polyhaven.com/a/brick_wall_001) | Dimitrios Savva, Rob Tuytel | CC0-1.0 |
| [boulder_01](https://polyhaven.com/a/boulder_01) | Rico Cilliers | CC0-1.0 |
| [pine_sapling_small](https://polyhaven.com/a/pine_sapling_small) | Rico Cilliers, Rob Tuytel | CC0-1.0 |

Источник условий: [Poly Haven License](https://polyhaven.com/license). Условия CC0 относятся к перечисленным исходным моделям и текстурам; код игры имеет собственный статус лицензирования.

## Подготовка

```bash
python -m pip install Pillow
python sky_godot/tools/prepare_assets.py
python sky_godot/tools/prepare_assets.py --verify-only
godot --headless --path sky_godot --editor --import
```

Скрипт переиспользует исходный downloader UE-проекта, после чего копирует проверенные файлы в `sky_godot/assets/`. Большие бинарные загрузки следует исключить из Git; команда полностью восстанавливает их. В `assets/receipt.json` записываются хеши подготовленных файлов и хеш исходного манифеста. `--verify-only` не загружает и не изменяет файлы.

Четыре DirectX normal map конвертируются в OpenGL normal map: **только зелёный канал инвертируется (`255-G`)**, остальные каналы сохраняются. Для моделей, где уже используются OpenGL normal map, исходные glTF и относительные ссылки сохраняются. Все выходные normal map имеют PNG-формат без потерь; JPEG исходника остаётся закреплённым в исходном манифесте. Это техническая адаптация текстур, а не новые художественные изображения.

## Runtime-интерфейс

`SkyArt.material(kind)` возвращает кэшированные PBR-материалы `ground/soil`, `rock/stone`, `wood/board/timber`, `brick`, `metal/nail/screw`. Для грунта и скал используется мировая трёхплоскостная развёртка, чтобы текстура сохранялась после копания. Текстуры 1K; все материалы совместимы с Compatibility renderer, без обязательного desktop-only GI.

`SkyArt.model(kind)` загружает настоящие glTF-сцены:

- `drill`: `res://assets/models/Drill_01/Drill_01_1k.gltf`
- `hammer`: `res://assets/models/wooden_hammer_01/wooden_hammer_01_1k.gltf`
- `rock`: `res://assets/models/boulder_01/boulder_01_1k.gltf`
- `tree`: `res://assets/models/pine_sapling_small/pine_sapling_small_variant0.gltf`

Материалы хвои, коры и инструментов сохраняются по слотам исходных моделей. Сосна — ранее воспроизводимо выделенный вариант0 (122 235 треугольников); Godot импортирует собственные LOD. Источник молодого дерева имеет высоту около1.05м, поэтому сцена задаёт масштаб осмысленно. Коллизии и действия инструментами создаёт игровой код, а не визуальная glTF-сцена. При отсутствии импорта `model()` возвращает null, чтобы игра могла показать явный отладочный заменитель.

`SkyArt.build_environment(parent)` создаёт процедурное небо, облачный покров, солнце, depth fog и тонирование. Нижний облачный слой — один процедурный прозрачный меш с шумом и туманом: это ограниченная по стоимости real-time аппроксимация, не дорогой объёмный raymarching. Сгенерированные концепт-картинки не используются как фон вместо 3D-мира.

## Проверка

Проверены все35 исходных SHA-256 и35 подготовленных файлов (**29 322 615 байт**, включая преобразованные normal map). `art.gd` загружен реальным Godot4.6.3 в headless-режиме: материалы и окружение создаются без ошибок (`ART_API_PASS`). Дополнительно выполнен настоящий импорт в изолированном Godot-проекте: все4 PBR-материала загрузили albedo/roughness/normal1024×1024, все4 glTF-сцены созданы с материалами на каждом surface (`ART_IMPORT_PASS`). Проверены исходные количества треугольников: дрель2926, молоток3617, сосна122235, скала66122. Это не доказывает итоговую частоту кадров или картинку на Samsung A22; реальный рендер сцены и устройство проверяются отдельно.
