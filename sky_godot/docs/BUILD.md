# Сборка Sky Islands на Godot

Проект использует **официальный Godot 4.6.3 stable**, стандартный GDScript и GL Compatibility. Скачивание и запуск Godot не требуют аккаунта Epic или Unity. Графику и производительность на телефоне нужно проверять на самом устройстве.

## Запуск на компьютере

Из корня репозитория:

```bash
python3 -m pip install Pillow==11.3.0
python3 sky_godot/tools/prepare_assets.py
godot --headless --path sky_godot --editor --import
godot --path sky_godot
```

Исходные модели и текстуры скачиваются по закреплённому манифесту SHA-256. Скопированные файлы в `sky_godot/assets/` воспроизводятся скриптом и не хранятся в Git. Карта создаётся из обычной `scenes/main.tscn` и GDScript во время запуска.

## Проверки

```bash
godot --headless --path sky_godot --script res://tests/test_simulation.gd -- --fresh
godot --headless --path sky_godot --script res://tests/test_terrain.gd -- --fresh
godot --headless --path sky_godot --script res://tests/test_game.gd -- --fresh
godot --headless --path sky_godot --script res://tests/test_state.gd -- --fresh
godot --headless --path sky_godot --script res://tests/test_network.gd -- --fresh
```

Скрипт сборки дополнительно проверяется на обработку ошибок:

```bash
python3 -m unittest discover -s sky_godot/tests -p 'test_build_android.py'
```

Сетевая проверка запускает отдельные server/client процессы Godot через Python и настоящий ENet; она требует доступных локальных сокетов и не является имитацией RPC.

Графический снимок можно получить через настоящий программный OpenGL-рендер:

```bash
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s '-screen 0 1280x720x24' godot --path sky_godot --rendering-method gl_compatibility --script res://tests/render_preview.gd
```

Снимок пишется в `sky_godot/Artifacts/Preview/gameplay.png`. В headless-режиме Godot использует dummy renderer, поэтому headless-проверка сама по себе не является графическим снимком.

## Android APK

Нужны:

- Godot 4.6.3 и соответствующие `android_debug.apk` / `android_release.apk` в каталоге `export_templates/4.6.3.stable`.
- Полный JDK17.
- Android SDK с `platform-tools`, `build-tools;35.0.1`, `platforms;android-35`.
- Тестовый ключ из `legion_game/signing/legion-test.jks` базового репозитория либо явный путь `--keystore`.

```bash
python3 sky_godot/tools/build_android.py --sdk /path/to/android-sdk --java /path/to/jdk17
```

Скрипт проверяет версию движка, подготавливает ассеты, импортирует проект, выполняет тесты, создаёт APK и проверяет подпись через `apksigner`. Ошибка импорта/GDScript или отсутствие настоящего APK останавливает сборку. Логи и отчёт находятся в `sky_godot/Artifacts/`.

Обычный экспорт Godot без Gradle не компилирует Android-шаблон из исходников, поэтому NDK и сборка самого движка для этой конфигурации не требуются.

В проверенном APK официальный шаблон Godot 4.6.3 задаёт `minSdkVersion=24` и `targetSdkVersion=36`; установленные Android platform 35 и build-tools 35.0.1 используются для экспорта и подписи. Поля переопределения Min/Target SDK в Godot доступны только при Gradle-сборке и в этом пресете не задаются.

Приложение: `com.mihail9990.skyislands.godot`. Версия для локального экспорта — `0.2.0`; GitHub Actions выставляет `0.2.<номер сборки>` и увеличивает Android version code. Это отдельное приложение от прежних игр репозитория.

Ключ предназначен только для личных тестов. Он уже присутствует в истории репозитория и не подходит для публичного магазинного релиза. Повторные тестовые сборки подписываются тем же ключом для установки обновления поверх предыдущей версии.

## GitHub Actions

Workflow **Sky Islands Godot Android** запускается при push в ветку `sky-islands-godot` и вручную через Actions. Он скачивает Godot из официального GitHub release и проверяет SHA-512, выполняет игровые тесты, собирает настоящий APK, проверяет сертификат и делает графический preview через Xvfb/Mesa. Артефакты содержат APK, PNG и логи.

## Официальные источники

- [Godot 4.6: экспорт для Android](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html)
- [Godot 4.6.3 stable release](https://github.com/godotengine/godot-builds/releases/tag/4.6.3-stable)
- [Godot command line](https://docs.godotengine.org/en/4.6/tutorials/editor/command_line_tutorial.html)
