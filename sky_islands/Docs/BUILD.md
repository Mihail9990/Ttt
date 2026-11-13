# Сборка Sky Islands

Проект закреплён на **Unreal Engine 5.6**. Это исходники развиваемого игрового прототипа. В среде, где создан этот коммит, Unreal Editor отсутствовал: C++-модуль Unreal, Python-импорт внутри Editor, карта и APK ещё требуют настоящей сборки. Прошедшие portable checks проверяют только переносимое ядро и целостность исходников.

## Что требуется

- Установленный легальным способом Unreal Engine 5.6 с компонентами Android, если нужен APK.
- Для Windows — поддерживаемый UE 5.6 Visual Studio 2022 с workload «Game development with C++» и Windows SDK.
- Python 3.11+ для команд подготовки; сам Unreal Python использует встроенный интерпретатор Editor.
- Для Android — SDK/NDK/JDK, соответствующие именно UE 5.6. Историческая таблица Epic указывает SDK 34 и NDK r27c. Их нужно настроить через Unreal Turnkey/SDK Management или инструкцию Epic. Не следует подставлять NDK из старой Godot-сборки.

Эта конфигурация предназначена для личного **Development APK**, устанавливаемого на устройство для испытаний. Это не подтверждение готовности к публикации в Google Play. Версия API и подпись для магазина подготавливаются отдельно под актуальные требования.

Движок не включён в репозиторий. Обычный GitHub-hosted runner не содержит UE, а публичная установка движка без подходящего доступа не выполняется автоматически.

## Первая сборка на Windows

Откройте PowerShell в папке `sky_islands`:

```powershell
python Tools/build.py --engine "C:\Program Files\Epic Games\UE_5.6" --target editor
```

Команда последовательно:

1. Проверит версию установленного движка.
2. Скомпилирует `SkyIslandsEditor` через UnrealBuildTool.
3. Запустит `Tools/create_world.py` внутри Editor и сохранит настоящую карту `Content/Maps/SkyWorld.umap`.
4. Получит закреплённые в manifest исходные ассеты и проверит SHA-256.
5. Импортирует их внутри Unreal и сохранит `.uasset`, материалы и текстуры.

После успешного выполнения откройте `SkyIslands.uproject` в UE 5.6 и нажмите Play. Default GameMode — `/Script/SkyIslands.SkyGameMode`. Острова и игровые объекты появляются из C++ во время запуска мира. Bootstrap-карта содержит PlayerStart, солнце, SkyAtmosphere, SkyLight и высотный туман.

Вариант `--skip-assets` полезен для диагностики игрового кода до импорта: он оставляет процедурные материалы разработки. Он **не** проверяет фотореалистичные ассеты.

Если проект открыт до bootstrap и Editor сообщает о недостающей карте, используйте приведённую команду. Скрипт запускает движок через `/Engine/Maps/Entry`, затем создаёт и сохраняет карту. Не создавайте пустой файл с расширением `.umap` вручную.

## Android APK

После настройки Android SDK в UE:

```powershell
python Tools/build.py --engine "C:\Program Files\Epic Games\UE_5.6" --target android
```

Сборка использует ARM64, Landscape, ASTC, Min SDK 26 и Target SDK 34. UAT выполняет настоящие Build/Cook/Stage/Package/Archive. Результат помещается в `Artifacts/android`. Скрипт завершится ошибкой, если UAT не создал непустой `.apk`.

Для Samsung A22 нужно отдельно проверить установку, совместимость GPU/драйвера, FPS, температуру, память и сенсорное управление. Кинематографические концепты являются художественным ориентиром. Они не служат измерением графики мобильной сборки.

`Config/DefaultDeviceProfiles.ini` применяет более экономный Android-профиль: без Lumen и объёмного тумана, с ограничением теней и дальности. Desktop использует Lumen и более детальные настройки. Присутствие настроек само по себе не подтверждает производительность — необходим запуск на устройстве.

## Windows build и сервер

```powershell
python Tools/build.py --engine "C:\Program Files\Epic Games\UE_5.6" --target windows
```

Архив — `Artifacts/windows`. Для локальной проверки listen-server запускайте игровой build с `/Game/Maps/SkyWorld?listen`; второй клиент подключается через консоль `open 127.0.0.1`. Это локальная проверка репликации, а не готовая инфраструктура публичного MMO-мира.

```powershell
python Tools/build.py --engine "D:\UnrealEngine-5.6" --target server
```

Dedicated Server target требует **сборку Unreal Engine из исходников**, поддерживающую server targets. Launcher binary install обычно не содержит необходимого server build pipeline. Исходники игры не предоставляют авторизацию аккаунтов, хостинг, NAT traversal или защиту промышленного backend сами по себе.

## GitHub Actions

- **Sky Islands source checks** запускается на GitHub-hosted Ubuntu: переносимое C++-ядро, Python syntax, конфигурации и обработка ошибок build orchestration. Это не компиляция Unreal.
- **Sky Islands Unreal build (installed UE 5.6)** запускается вручную через Actions → Run workflow. Требуется настроенный владельцем self-hosted Windows runner с метками `self-hosted`, `Windows`, `X64`, `ue5-6` и переменная репозитория `UE56_ROOT` с каталогом движка.
- Self-hosted workflow не имеет события `pull_request`; запускайте его только для доверенной версии исходников.
- При ошибке сохраняются логи, а готовым результатом считается только успешный UAT и реально появившийся архив.

Каждая попытка настоящей сборки записывает `Artifacts/BuildLogs/BuildReport.json` с результатами этапов. В репозитории нет выдуманного отчёта успешной engine-сборки.

## Проверки без Unreal

Из корня репозитория:

```bash
python sky_islands/Tools/validate_project.py
bash sky_islands/Tests/run_core_tests.sh
bash sky_islands/Tests/run_terrain_tests.sh
python -m unittest discover -s sky_islands/Tests -p 'test_build*.py'
```

Тесты build orchestration используют маленький **симулированный движок** только для проверки того, что ошибка компилятора, пропавший success marker и отсутствие сохранённой карты не выдаются за успешную сборку. Они не тестируют Unreal API.

## Официальные источники

- [Android Development Requirements — Epic, UE 5.6](https://dev.epicgames.com/documentation/en-us/unreal-engine/android-development-requirements-for-unreal-engine?application_version=5.6)
- [Scripting the Unreal Editor using Python — Epic](https://dev.epicgames.com/documentation/en-us/unreal-engine/scripting-the-unreal-editor-using-python)
- [LevelEditorSubsystem Python API — Epic, UE 5.6](https://dev.epicgames.com/documentation/en-us/unreal-engine/python-api/class/LevelEditorSubsystem?application_version=5.6)
- [Packaging your project — Epic](https://dev.epicgames.com/documentation/en-us/unreal-engine/packaging-your-project)
- [Setting up dedicated servers — Epic](https://dev.epicgames.com/documentation/en-us/unreal-engine/setting-up-dedicated-servers-in-unreal-engine)
