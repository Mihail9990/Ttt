# Sky Islands — Unreal Engine 5.6

Первая исходная реализация «Небесных островов»: общего мира с добычей ресурсов, детальным строительством, производством и торговлей. Художественный ориентир — кинематографический реализм с естественным рельефом и подробными материалами.

**Текущий результат — UE5 C++-проект в разработке. Готового APK и подтверждённой компиляции Unreal пока нет:** в среде разработки не установлен Unreal Editor. Переносимые тесты не заменяют запуск игры на движке и телефоне.

- [Реализованные части и ограничения](sky_islands/Docs/STATUS.md)
- [Подготовка Editor, карты и APK](sky_islands/Docs/BUILD.md)
- [Ассеты, лицензии и источники](sky_islands/Docs/ASSETS.md)
- [Проект Unreal](sky_islands/SkyIslands.uproject)

## Начало работы

На компьютере с установленным UE 5.6 и поддерживаемой C++-средой:

```powershell
cd sky_islands
python Tools/build.py --engine "C:\Program Files\Epic Games\UE_5.6" --target editor
```

Команда компилирует модуль, создаёт настоящую карту `SkyWorld`, получает проверенные исходные ассеты и импортирует их. После успешного выполнения откройте `SkyIslands.uproject` и нажмите Play. Запуск `--target android` дополнительно требует Android SDK/NDK и выполняет настоящее пакетирование через UAT.

Полный порядок действий описан в BUILD.md. Карта `.umap` создаётся внутри Unreal, поэтому первой должна выполняться подготовка проекта.

## Проверки исходников

```bash
python sky_islands/Tools/validate_project.py
bash sky_islands/Tests/run_core_tests.sh
bash sky_islands/Tests/run_terrain_tests.sh
python -m unittest discover -s sky_islands/Tests -p 'test_build*.py'
```

GitHub-hosted workflow запускает переносимые проверки. Unreal workflow запускается вручную на подготовленном self-hosted runner с установленным движком.

Ранее в репозитории находился Godot-проект `legion_game` с собственной сборкой. Это исторический отдельный проект; его workflow не собирает новую игру на Unreal.
