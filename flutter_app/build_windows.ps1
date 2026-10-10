<#
.SYNOPSIS
  Собирает Monkey App для Windows: проверки, тесты, сборка, папка dist, ярлык.

.EXAMPLE
  .\build_windows.ps1                 # обычная сборка + ярлык на рабочем столе
  .\build_windows.ps1 -Update         # сначала забрать свежий код с GitHub
  .\build_windows.ps1 -Installer      # ещё и установщик Setup.exe (Inno Setup)
  .\build_windows.ps1 -SkipTests      # без тестов, если торопишься

  Или просто дважды щёлкнуть build_windows.bat рядом с этим файлом.
#>
param(
  [switch]$Update,
  [switch]$Installer,
  [switch]$SkipTests,
  [switch]$NoShortcut,
  [switch]$Run
)

$ErrorActionPreference = 'Stop'
$AppName  = 'Monkey App'
$ExeName  = 'movie_app.exe'
$Project  = $PSScriptRoot                       # ...\movie-app\flutter_app
$RepoRoot = Split-Path $Project -Parent         # ...\movie-app
$Release  = Join-Path $Project 'build\windows\x64\runner\Release'
$Dist     = Join-Path $RepoRoot "dist\$AppName"

function Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }
function Ok($text)   { Write-Host "    $text" -ForegroundColor Green }
function Warn($text) { Write-Host "    $text" -ForegroundColor Yellow }
function Fail($text) { Write-Host "`n$text" -ForegroundColor Red; exit 1 }

# Нативные команды (flutter, git) не бросают исключений — проверяем код выхода.
function Invoke-Checked([string]$what, [scriptblock]$cmd) {
  & $cmd
  if ($LASTEXITCODE -ne 0) { Fail "Не получилось: $what (код $LASTEXITCODE). Смотри сообщения выше." }
}

Set-Location $Project
$started = Get-Date

# ─── 1. Что должно стоять ──────────────────────────────────────────────────
Step 'Проверяю окружение'

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Fail 'Flutter не найден в PATH. Открой новое окно PowerShell или добавь C:\src\flutter\bin в Path.'
}
Ok 'Flutter есть'

# Компилятор C++ из Visual Studio — без него Windows-версию не собрать.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vsPath = if (Test-Path $vswhere) {
  & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
}
if (-not $vsPath) {
  Fail @"
Не найдена Visual Studio с C++. Поставь (один раз, ~8 ГБ):
  winget install Microsoft.VisualStudio.2022.Community --override "--add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended --passive"
Или вручную: Visual Studio Community -> «Разработка классических приложений на C++».
"@
}
Ok "Visual Studio: $vsPath"

# NuGet нужен плагину встроенного плеера (WebView2). Нет — скачаем сами.
if (-not (Get-Command nuget -ErrorAction SilentlyContinue)) {
  $nugetDir = Join-Path $env:LOCALAPPDATA 'nuget-cli'
  $nugetExe = Join-Path $nugetDir 'nuget.exe'
  if (-not (Test-Path $nugetExe)) {
    Warn 'NuGet не найден — скачиваю nuget.exe'
    New-Item -ItemType Directory -Force $nugetDir | Out-Null
    Invoke-WebRequest 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' -OutFile $nugetExe
  }
  $env:Path = "$nugetDir;$env:Path"
  # И навсегда для пользователя, чтобы flutter run тоже его видел.
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ($userPath -notlike "*$nugetDir*") {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$nugetDir", 'User')
  }
}
Ok 'NuGet есть'

# Плагинам нужны символические ссылки — их разрешает режим разработчика.
$devMode = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' `
  -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue
if (-not $devMode -or $devMode.AllowDevelopmentWithoutDevLicense -ne 1) {
  # Не стоп: из окна администратора ссылки создаются и без него.
  Warn 'Режим разработчика Windows, похоже, выключен.'
  Warn 'Если flutter pub get ниже пожалуется на symlink — включи его: Параметры -> Для разработчиков.'
} else {
  Ok 'Режим разработчика включён'
}

# ─── 2. Свежий код ─────────────────────────────────────────────────────────
if ($Update) {
  Step 'Забираю свежий код с GitHub'
  Push-Location $RepoRoot
  Invoke-Checked 'git pull' { git pull --ff-only }
  Pop-Location
}

$version = (Select-String -Path (Join-Path $Project 'pubspec.yaml') -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value
Ok "Версия $version"

# ─── 3. Зависимости и тесты ────────────────────────────────────────────────
Step 'Загружаю зависимости'
Invoke-Checked 'flutter pub get' { flutter pub get }

if (-not $SkipTests) {
  Step 'Прогоняю тесты'
  Invoke-Checked 'тесты (запусти с -SkipTests, чтобы собрать без них)' { flutter test }
}

# ─── 4. Сборка ─────────────────────────────────────────────────────────────
# Запущенное приложение держит свои .dll — сборка и копирование упадут.
Get-Process -Name ($ExeName -replace '\.exe$', '') -ErrorAction SilentlyContinue | ForEach-Object {
  Warn 'Закрываю запущенный Monkey App'
  $_ | Stop-Process -Force
  Start-Sleep -Milliseconds 500
}

Step 'Собираю Windows-версию (первый раз — несколько минут)'
Invoke-Checked 'flutter build windows' { flutter build windows --release }

if (-not (Test-Path (Join-Path $Release $ExeName))) { Fail "Сборка прошла, но $ExeName не найден в $Release" }

# ─── 5. Папка с программой ─────────────────────────────────────────────────
# Копируем всю папку: рядом с .exe лежат .dll и data — без них не запустится.
Step "Кладу программу в $Dist"
New-Item -ItemType Directory -Force $Dist | Out-Null
robocopy $Release $Dist /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { Fail "Не удалось скопировать файлы в $Dist (robocopy $LASTEXITCODE)" }
$global:LASTEXITCODE = 0
$exe = Join-Path $Dist $ExeName
Ok $exe

# ─── 6. Ярлык ──────────────────────────────────────────────────────────────
if (-not $NoShortcut) {
  Step 'Создаю ярлык на рабочем столе'
  $desktop = [Environment]::GetFolderPath('Desktop')
  $shell = New-Object -ComObject WScript.Shell
  $lnk = $shell.CreateShortcut((Join-Path $desktop "$AppName.lnk"))
  $lnk.TargetPath = $exe
  $lnk.WorkingDirectory = $Dist
  $lnk.IconLocation = "$exe,0"
  $lnk.Description = $AppName
  $lnk.Save()
  Ok "Ярлык «$AppName» на рабочем столе"
}

# ─── 7. Установщик ─────────────────────────────────────────────────────────
if ($Installer) {
  Step 'Собираю установщик'
  $iscc = @(
    (Get-Command iscc -ErrorAction SilentlyContinue).Source,
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
  ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

  if (-not $iscc) {
    Warn 'Inno Setup не найден. Поставь одной командой и запусти снова:'
    Warn '  winget install JRSoftware.InnoSetup'
  } else {
    $outDir = Join-Path $RepoRoot 'dist'
    Invoke-Checked 'Inno Setup' {
      & $iscc /Q "/DAppVersion=$version" "/DSourceDir=$Dist" "/DOutputDir=$outDir" (Join-Path $Project 'windows\installer.iss')
    }
    Ok (Join-Path $outDir "MonkeyApp-Setup-$version.exe")
  }
}

$took = [int]((Get-Date) - $started).TotalSeconds
Write-Host "`nГотово за $took с. Программа: $exe" -ForegroundColor Green

if ($Run) { Start-Process $exe -WorkingDirectory $Dist } else { Invoke-Item $Dist }
