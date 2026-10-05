# Тестовая сборка без smali-патчей

В GitHub Actions откройте **Build HyperOS port → Run workflow** и включите
**test_mode**. Остальные параметры сборки выбираются как обычно.

Для локальной сборки установите `test_mode=true` в `bin/port_config`, затем
запустите `sudo bash port.sh <сток.zip> <донор.zip>`. По умолчанию режим выключен.

В тестовом режиме отключены:

- Вызовы `patch_smali`: SystemUI, `miui-services.jar`, PowerKeeper и MiSettings.
- Правки smali для проверки подписей и shared UID в `services.jar` через APKEditor.
- Правки методов MiLinkOS2CN, MIUIThemeManager и Settings через `patchmethod.py`.

Все остальные операции работают как в обычной сборке: патчи ресурсов APK,
подмена приложений и ресурсных оверлеев из стока, скачивание и установка новой
MiuiCamera, NFC-пакеты, полный оверлей устройства, удаление приложений (debloat),
слияние `mi_ext`, настройки XML и `build.prop`, fstab, AVB, ядро и упаковка разделов.

Проверка неизменности всех APK/JAR удалена: разрешённые ресурсные патчи и подмена
приложений могут менять эти файлы.

Оба формата выходного ZIP получают суффикс `_TEST`. Для включения smali-патчей
отключите **test_mode** в Actions или установите `test_mode=false` в конфиге.
