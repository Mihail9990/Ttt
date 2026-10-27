# Android APK Builder — GitHub Actions

Рабочий стартовый Android-проект на Kotlin. APK собирается на GitHub — всё управление доступно с Android-телефона, без ПК и VPS.

## Готовые возможности

- Автоматическая сборка при изменениях в ветке `main`.
- Ручная сборка: [Actions → Build Android APK](https://github.com/Mihail9990/Ttt/actions/workflows/build-apk.yml) → **Run workflow**.
- `Android-Debug-v1.0.N` — APK для тестирования.
- `Android-Release-v1.0.N` — APK с постоянной подписью, появляется после настройки двух GitHub Secrets.
- `versionCode` и `versionName` увеличиваются с каждым новым запуском workflow.
- Проверка подписи `apksigner` перед загрузкой артефактов.
- Тестовый экран показывает текущую версию и содержит рабочую кнопку; добавлена иконка.

## Как скачать APK

1. Откройте [Actions](https://github.com/Mihail9990/Ttt/actions).
2. Нажмите **Build Android APK** и выберите успешный запуск (зелёная галочка).
3. В нижней части страницы откройте **Artifacts** и скачайте ZIP с APK.
4. Распакуйте архив в Downloads, откройте APK и подтвердите установку на Android.

При первой настройке без секретов будет доступен **только Debug APK**.

## Обновления без удаления

Для этого требуется один и тот же сертификат подписи при каждой сборке. Чтобы подготовить постоянный ключ на телефоне через Termux, откройте **[пошаговую инструкцию](docs/SIGNING_ON_ANDROID.md)**. В ней объяснено, как создать ключ локально и добавить только **два секрета** через веб-интерфейс GitHub.

**Важно:** ранее установленный первый пробный APK был подписан временным debug-ключом, поэтому для перехода к постоянному ключу его придётся удалить один раз. В дальнейшем Release APK будут обновляться поверх предыдущих версий, пока не меняются подпись и `applicationId`.

## Где менять приложение

- `app/src/main/java/com/example/apkstarter/MainActivity.kt` — код экрана.
- `app/src/main/res/values/strings.xml` — название приложения.
- `app/src/main/res/drawable/ic_launcher.xml` — иконка приложения.
- `app/src/main/AndroidManifest.xml` — конфигурация Android.
- `app/build.gradle.kts` — версия, пакет, SDK и подпись.
- `.github/workflows/build-apk.yml` — сборка и загрузка APK.

Не храните пароли, `.jks`, `.keystore` или их base64-представление в репозитории. Секреты должны находиться только в GitHub Actions Secrets.
