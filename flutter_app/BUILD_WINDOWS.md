# Сборка приложения для Windows

Цель — обычная программа с ярлыком, которая запускается двойным кликом,
без PowerShell и без `flutter run`. Как Streambert, только не Electron.

Кстати про названия: `.apk` — это формат установки **только для Android**.
На компьютере ему соответствует `.exe`, а установщик собирается отдельно
(последний раздел).

На Windows блокировка рекламы во встроенном плеере работает **полностью**,
в отличие от веб-версии: WebView здесь наш собственный, а не чужой iframe
внутри браузера.

## Быстро: одной командой

```powershell
cd E:\movie-app\flutter_app
.\build_windows.ps1 -Update
```

Или двойной клик по `build_windows.bat` в папке `flutter_app`.

Скрипт сам проверит Visual Studio, скачает NuGet, если его нет, прогонит
тесты, соберёт программу, положит её в `E:\movie-app\dist\Monkey App\`
и сделает ярлык «Monkey App» на рабочем столе.

| Ключ | Что делает |
|---|---|
| `-Update` | сначала забрать свежий код с GitHub (`git pull`) |
| `-Installer` | ещё и `dist\MonkeyApp-Setup-<версия>.exe` (нужен Inno Setup: `winget install JRSoftware.InnoSetup`) |
| `-SkipTests` | собрать без тестов |
| `-Run` | сразу запустить программу после сборки |
| `-NoShortcut` | не трогать ярлык на рабочем столе |

Если PowerShell пишет, что выполнение сценариев отключено, — запускай через
`build_windows.bat` или один раз выполни
`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

Ниже — что скрипт делает под капотом, если захочется руками.

---

## Разово: что должно стоять

### 1. Visual Studio с поддержкой C++

Flutter собирает нативную часть компилятором Microsoft. Нужен
**Visual Studio Community** (бесплатный) с рабочей нагрузкой
**«Разработка классических приложений на C++»**.

Одной Visual Studio Code недостаточно — это разные программы.

Проверка:

```powershell
flutter doctor
```

У строки **Visual Studio** должна быть галочка.

### 2. NuGet CLI в PATH

Нужен плагину встроенного плеера — он тянет через NuGet компонент WebView2.

1. Скачай `nuget.exe` с https://www.nuget.org/downloads
   (нужен «Windows x86 Commandline», один файл)
2. Положи, например, в `C:\nuget\`
3. Win → «Изменение переменных среды текущего пользователя» → `Path` →
   Создать → `C:\nuget` → ОК
4. Перезапусти PowerShell и проверь: `nuget help`

### 3. WebView2 Runtime

На Windows 11 и свежих Windows 10 уже стоит. Если плеер окажется пустым —
поставь с сайта Microsoft («Evergreen Standalone Installer»).

---

## Собрать

```powershell
cd E:\movie-app\flutter_app
flutter build windows --release
```

Первая сборка идёт несколько минут, дальше быстрее.

Результат:

```
build\windows\x64\runner\Release\
```

Внутри `movie_app.exe` — двойной клик, и приложение открывается.

**Важно:** копировать надо папку целиком. Рядом с `.exe` лежат `.dll`
и папка `data` — без них программа не запустится. Это нормально для
Windows-приложений; в один файл всё собирает установщик.

Ярлык: правой кнопкой по `.exe` → «Отправить» → «Рабочий стол».

---

## Установщик в один файл

Чтобы получилось как у Streambert — один `Setup.exe`, который сам всё
разложит и добавит в меню «Пуск».

### Inno Setup (проще всего, бесплатно)

1. Поставь https://jrsoftware.org/isdl.php
2. Запусти, выбери «Create a new script file using the Script Wizard»
3. В мастере укажи:
   - имя приложения: `Monkey App`
   - главный файл: `build\windows\x64\runner\Release\movie_app.exe`
   - **добавить остальные файлы и папки из той же папки** — это ключевой
     шаг, иначе установится один `.exe` без библиотек
4. Compile → получаешь `Setup.exe`, который можно кому угодно отдать

### MSIX (для Microsoft Store)

Пакет `msix` в `dev_dependencies` собирает `.msix` одной командой.
Нужен, только если планируешь публиковаться в Store.

---

## Название и иконка

Окно называется «Monkey App» и открывается размером 1440×900, чтобы сразу
включалась десктопная раскладка. Файл по-прежнему `movie_app.exe`, а в
`Runner.rc` остаются `CompanyName` и `ProductName` от старого имени: по ним
Windows выбирает папку с данными приложения (вход, кэш, очередь
синхронизации), и переименование «потеряло» бы их.

Иконка — `windows/runner/resources/app_icon.ico`, пока стандартная Flutter.

Установщик описан в `windows/installer.iss`; ставится в профиль
пользователя без прав администратора, новая версия ложится поверх старой.
