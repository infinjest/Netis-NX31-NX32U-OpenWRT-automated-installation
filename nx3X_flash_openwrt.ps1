#Requires -Version 5.1
<#
.SYNOPSIS
    Netis NX31 / NX32U → OpenWrt (24.10.1+) | Скрипт автоматической установки (Robust Edition)
#>

param(
    [string]$RouterIP    = "192.168.1.1",
    [string]$User        = "admin",
    [string]$FirmwareDir = "$PSScriptRoot\firmware",
    [string]$BackupDir   = "$PSScriptRoot\backup",
    [string]$PlinkPath   = "$PSScriptRoot\putty-64bit-0.84-plink-pscp\plink.exe",
    [string]$PscpPath    = "$PSScriptRoot\putty-64bit-0.84-plink-pscp\pscp.exe",
    [string]$Tftpd64Path = "$PSScriptRoot\tftpd64_portable_v4.74\tftpd64.exe",
	[string]$OwrtUser = "root",
    [string]$OwrtPassword = ""
)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Скрипт запущен БЕЗ прав администратора. Правило брандмауэра не будет создано."
    Write-Host "Рекомендуется перезапустить от имени администратора." -ForegroundColor Yellow
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─── Цвета и Логирование ──────────────────────────────────────────────────────
function Write-Step  { param($msg) Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-OK    { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "  [!]  $msg" -ForegroundColor Yellow }
function Write-Fail  { param($msg) Write-Host "  [X]  $msg" -ForegroundColor Red; exit 1 }

# ─── Проверка зависимостей и сети ─────────────────────────────────────────────
Write-Step "ПРОВЕРКА ЗАВИСИМОСТЕЙ И СЕТИ"

foreach ($tool in @($PlinkPath, $PscpPath, $Tftpd64Path)) {
    if (-not (Test-Path $tool)) { Write-Fail "Не найден: $tool" }
    Write-OK "Утилита найдена: $(Split-Path $tool -Leaf)"
}

if (-not (Test-Connection -ComputerName $RouterIP -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
    Write-Fail "Роутер $RouterIP недоступен. Проверьте кабель и настройки сети."
}
Write-OK "Роутер $RouterIP в сети"

# ─── Правило брандмауэра для tftpd64 ─────────────────────────────────────────
$fwRuleName = "tftpd64 - OpenWrt Flash"
if (-not (Get-NetFirewallRule -DisplayName $fwRuleName -ErrorAction SilentlyContinue)) {
    Write-Host "  Создаю правило брандмауэра для tftpd64 (UDP 69)..." -ForegroundColor Cyan
    New-NetFirewallRule -DisplayName $fwRuleName `
        -Direction Inbound `
        -Protocol UDP `
        -LocalPort 69 `
        -Program $Tftpd64Path `
        -Action Allow `
        -Profile Any | Out-Null
    Write-OK "Правило брандмауэра создано"
} else {
    Write-OK "Правило брандмауэра уже существует"
}

# ─── Проверка папки и файлов прошивки ────────────────────────────────────────
$resolved = Resolve-Path $FirmwareDir -ErrorAction SilentlyContinue
if (-not $resolved) { Write-Fail "Папка с прошивкой не найдена: $FirmwareDir" }
$FirmwareDir = $resolved.Path

function Find-Fw { param($pattern)
    $f = Get-ChildItem (Join-Path $FirmwareDir $pattern) -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $f) { Write-Fail "Файл не найден: $pattern в $FirmwareDir" }
    return $f
}

$FipFile       = Find-Fw "*bl31-uboot.fip"
$PreloaderFile = Find-Fw "*preloader.bin"
$RecoveryFile  = Find-Fw "*initramfs-recovery.itb"
$SysupgrFile   = Find-Fw "*squashfs-sysupgrade.itb"

# ─── Убираем номер версии из имён файлов (нужно для TFTP и единообразия) ──────
function Rename-FwFile { param($File)
    $newName = $File.Name -replace 'openwrt-[\d.]+-', 'openwrt-'
    if ($File.Name -ne $newName) {
        Rename-Item $File.FullName $newName
        Write-OK "Переименован: $($File.Name) → $newName"
        return Get-Item (Join-Path $FirmwareDir $newName)
    }
    return $File
}

$FipFile       = Rename-FwFile $FipFile
$PreloaderFile = Rename-FwFile $PreloaderFile
$RecoveryFile  = Rename-FwFile $RecoveryFile
$SysupgrFile   = Rename-FwFile $SysupgrFile

Write-OK "Файлы прошивки найдены"

# ─── Проверка по официальному файлу sha256sums (если он есть в папке) ─────────
$SumsFile = Get-ChildItem (Join-Path $FirmwareDir "sha256sums") -ErrorAction SilentlyContinue | Select-Object -First 1

if ($SumsFile) {
    Write-Host "`n  Найден файл sha256sums, проверяю оригинальность файлов..." -ForegroundColor Cyan

    $SumsData = (Get-Content $SumsFile.FullName | Out-String).ToLower()

    foreach ($fwFile in @($FipFile, $PreloaderFile, $RecoveryFile, $SysupgrFile)) {
        $actualHash = (Get-FileHash -Path $fwFile.FullName -Algorithm SHA256).Hash.ToLower()
        if ($SumsData -match $actualHash) {
            Write-OK "$($fwFile.Name) (оригинальность подтверждена)"
        } else {
            Write-Fail "БИТЫЙ ИЛИ НЕИЗВЕСТНЫЙ ФАЙЛ: $($fwFile.Name)`nЕго хэш ($actualHash) не найден в sha256sums!`nПерекачайте прошивку."
        }
    }
}

# ─── Учётные данные ───────────────────────────────────────────────────────────
Write-Host ""
$SecPwd   = Read-Host "Введите SSH-пароль роутера ($User@$RouterIP)" -AsSecureString
$Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecPwd))

# ─── Кэш SSH-ключей PuTTY ────────────────────────────────────────────────────
# Вызывается ровно дважды: после ввода пароля и в начале Фазы 5.
# Чистит устаревший ключ роутера и принимает новый без интерактивного диалога.
# plink и pscp используют один реестровый кэш, поэтому одного вызова достаточно
# для обоих инструментов.
function Accept-RouterKey {
    Write-Host "  Обновление SSH-ключа роутера в кэше PuTTY..." -ForegroundColor DarkGray
    $keyPath = "HKCU:\Software\SimonTatham\PuTTY\SshHostKeys"
    if (Test-Path $keyPath) {
        Get-ItemProperty $keyPath -ErrorAction SilentlyContinue |
            Get-Member -MemberType NoteProperty |
            Where-Object { $_.Name -like "*@22:$RouterIP" } |
            ForEach-Object { Remove-ItemProperty $keyPath -Name $_.Name -ErrorAction SilentlyContinue }
    }
    # Без -batch: нужен интерактивный режим, чтобы plink спросил и получил "y"
    "y" | & $PlinkPath -ssh -pw $Password "$User@$RouterIP" "exit" 2>&1 | Out-Null
}

Accept-RouterKey

# ─── Вспомогательные функции SSH/SCP ─────────────────────────────────────────
function Invoke-SSH {
    param([string]$Cmd, [switch]$IgnoreError, [switch]$Quiet)
    # -batch: запрет интерактивных вопросов; ключ уже в кэше после Accept-RouterKey
    $out      = & $PlinkPath -ssh -pw $Password -batch -no-antispoof "$User@$RouterIP" $Cmd 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0 -and -not $IgnoreError) {
        Write-Fail "SSH ошибка (код $exitCode) при выполнении: $Cmd`n       Вывод роутера: $out"
    }
    if ($Quiet) { return }
    return @{ Output = $out; ExitCode = $exitCode }
}

function Invoke-Download {
    param([string]$Remote, [string]$Local)
    $out = & $PscpPath -pw $Password -batch -scp "$User@${RouterIP}:$Remote" $Local 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Fail "SCP ошибка скачивания: $Remote`n       Вывод: $out" }
}

function Invoke-Upload {
    param([string]$Local, [string]$Remote)

    $out = & $PscpPath -pw $Password -batch -scp $Local "$User@${RouterIP}:$Remote" 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Fail "SCP ошибка загрузки: $Local`n       Вывод: $out" }

    $LocalHash = (Get-FileHash -Path $Local -Algorithm SHA256).Hash.ToLower()

    $sshResult = Invoke-SSH "sha256sum $Remote" -IgnoreError
    if ($sshResult.ExitCode -ne 0) {
        Write-Warn "Файл загружен, но на роутере нет утилиты sha256sum для проверки."
        return
    }

    # Ищем ровно 64 hex-символа — независимо от любого мусора в выводе роутера
    if ($sshResult.Output -match '([a-f0-9]{64})') {
        $RemoteHash = $matches[1]
    } else {
        Write-Fail "Не удалось извлечь хэш из ответа роутера.`nВывод: $($sshResult.Output)"
    }

    if ($LocalHash -ne $RemoteHash) {
        Write-Fail "Нарушена целостность при передаче ($Remote)!`nЛокальный: $LocalHash`nНа роутере: $RemoteHash"
    }
}

function Wait-Router {
    param([string]$IP = $RouterIP, [int]$Timeout = 180, [int]$Delay = 5)
    Write-Host "  Ожидаю роутер на $IP" -NoNewline
    $deadline = (Get-Date).AddSeconds($Timeout)
    while ((Get-Date) -lt $deadline) {
        if (Test-Connection -ComputerName $IP -Count 1 -Quiet -ErrorAction SilentlyContinue) {
            Write-Host " готов!"
            Start-Sleep -Seconds $Delay
            return $true
        }
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 3
    }
    Write-Host " время вышло!"
    return $false
}

# ─── Управление tftpd64 ───────────────────────────────────────────────────────
function Start-TftpServer {
    param(
        [string]$Root,
        [string]$BindIP = "192.168.1.254",
        [string]$TftpdPath
    )

    $TftpdDir = Split-Path $TftpdPath -Parent
    $TftpdIni = Join-Path $TftpdDir "tftpd64.ini"

    $script:IniPath   = $TftpdIni
    $script:IniBackup = if (Test-Path $TftpdIni) { Get-Content $TftpdIni -Raw } else { $null }

    # Патчим только два ключа — всё остальное оставляем как есть
    $ini = if ($script:IniBackup) { $script:IniBackup } else { "[TFTPD32]`r`n" }

    if ($ini -match '(?m)^BaseDirectory=') {
        $ini = $ini -replace '(?m)^BaseDirectory=.*$', "BaseDirectory=$Root"
    } else {
        $ini = $ini -replace '(?m)^\[TFTPD32\]', "[TFTPD32]`r`nBaseDirectory=$Root"
    }

    if ($ini -match '(?m)^LocalIP=') {
        $ini = $ini -replace '(?m)^LocalIP=.*$', "LocalIP=$BindIP"
    } else {
        $ini = $ini -replace '(?m)^\[TFTPD32\]', "[TFTPD32]`r`nLocalIP=$BindIP"
    }

    Set-Content -Path $TftpdIni -Value $ini -Encoding ASCII -NoNewline

    $proc = Start-Process -FilePath $TftpdPath -PassThru -WindowStyle Minimized
    return $proc
}

function Stop-TftpServer {
    param([System.Diagnostics.Process]$Process)

    if ($Process) {
        Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
    }

    if ($null -ne $script:IniBackup) {
        Set-Content -Path $script:IniPath -Value $script:IniBackup -Encoding ASCII -NoNewline
    } elseif (Test-Path $script:IniPath) {
        Remove-Item $script:IniPath -Force
    }
}

# ─── ФАЗА 1: MTD-БЭКАП ───────────────────────────────────────────────────────
Write-Step "ФАЗА 1 — MTD-БЭКАП"
if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null }

$Partitions = @("mtd0:spi0.0", "mtd1:BL2", "mtd2:u-boot-env", "mtd3:Factory", "mtd4:FIP", "mtd5:ubi")

foreach ($p in $Partitions) {
    $id = $p.Split(":")[0]; $name = $p.Split(":")[1]
    $gz = "${id}_${name}.bin.gz"
    Write-Host "  Сжатие $name ($id)..."
    Invoke-SSH "cat /dev/$id | gzip -1 -c > /tmp/$gz" -Quiet
}
Write-OK "Все разделы успешно сжаты в /tmp/"

# ─── ФАЗА 2: СКАЧИВАНИЕ БЭКАПА ───────────────────────────────────────────────
Write-Step "ФАЗА 2 — СКАЧИВАНИЕ БЭКАПА НА ПК"
foreach ($p in $Partitions) {
    $id = $p.Split(":")[0]; $name = $p.Split(":")[1]
    $gz = "${id}_${name}.bin.gz"
    Write-Host "  Скачиваю $gz..."
    Invoke-Download "/tmp/$gz" (Join-Path $BackupDir $gz)
}
Write-OK "Бэкапы сохранены локально: $BackupDir"

# ─── ФАЗА 3: ЗАГРУЗКА И ПРОШИВКА ЗАГРУЗЧИКА ──────────────────────────────────
Write-Step "ФАЗА 3 — ЗАГРУЗКА И ПРОШИВКА ЗАГРУЗЧИКА (FIP и BL2)"

Write-Host "  Загружаю $($FipFile.Name)..."
Invoke-Upload $FipFile.FullName "/tmp/$($FipFile.Name)"

Write-Host "  Загружаю $($PreloaderFile.Name)..."
Invoke-Upload $PreloaderFile.FullName "/tmp/$($PreloaderFile.Name)"

Write-Host "  Запись $($FipFile.Name) в раздел FIP..."
Invoke-SSH "mtd write /tmp/$($FipFile.Name) FIP" -Quiet
Write-OK "Раздел FIP успешно обновлён"

Write-Host "  Запись $($PreloaderFile.Name) в раздел BL2..."
$bl2Result = Invoke-SSH "mtd write /tmp/$($PreloaderFile.Name) BL2" -IgnoreError

if ($bl2Result.ExitCode -ne 0) {
    Write-Warn "Раздел BL2 защищён от записи в заводской прошивке (ошибка mtd)."
    Write-Warn "Это штатная ситуация для данной модели. Скрипт продолжает работу."
    Write-Warn "Обновлённого раздела FIP достаточно для загрузки Recovery образа."
} else {
    Write-OK "Раздел BL2 успешно обновлён"
}

# ─── ФАЗА 4: TFTP + СТИРАНИЕ UBI + ПЕРЕЗАГРУЗКА ─────────────────────────────
Write-Step "ФАЗА 4 — ЗАПУСК TFTP, СТИРАНИЕ UBI, ПЕРЕЗАГРУЗКА"

Write-Host "  Запускаю tftpd64 (интерфейс 192.168.1.254, папка: $FirmwareDir)..."
$TftpdProc = Start-TftpServer -Root $FirmwareDir -BindIP "192.168.1.254" -TftpdPath $Tftpd64Path
Start-Sleep -Seconds 2
Write-OK "tftpd64 запущен"

try {
    Write-Host "  Стираю UBI и отправляю роутер в перезагрузку..."
    Invoke-SSH "mtd erase ubi; reboot" -IgnoreError -Quiet
    Write-OK "Команда выполнена. Ожидание Recovery по TFTP..."

    Start-Sleep -Seconds 40
    if (-not (Wait-Router -IP $RouterIP -Timeout 150 -Delay 10)) {
		Stop-TftpServer -Process $TftpdProc
        Write-Fail "Recovery-образ не поднялся. Проверьте настройки сетевой карты (192.168.1.254)."
    }
} finally {
    # Выполняется всегда: при штатном завершении, ошибке или Ctrl+C
    Stop-TftpServer -Process $TftpdProc
    Write-OK "tftpd64 остановлен, конфигурация восстановлена"
}

# ─── ФАЗА 5: ЗАГРУЗКА И УСТАНОВКА SYSUPGRADE ─────────────────────────────────
Write-Step "ФАЗА 5 — ЗАГРУЗКА И УСТАНОВКА SYSUPGRADE"

# OpenWrt recovery: root без пароля
Write-Host "  Переключение учетных данных на OpenWrt (root)..." -ForegroundColor DarkGray
$User     = $OwrtUser
$Password = $OwrtPassword

# После перезагрузки в Recovery у роутера новый SSH-ключ — обновляем кэш
Accept-RouterKey

Write-Host "  Загружаю $($SysupgrFile.Name)..."
Invoke-Upload $SysupgrFile.FullName "/tmp/$($SysupgrFile.Name)"

Write-Host "  Запускаю установку sysupgrade..."
Write-Host "  Роутер начнёт перезагрузку через пару секунд..."
Invoke-SSH "sysupgrade -n /tmp/$($SysupgrFile.Name)" -IgnoreError -Quiet

Start-Sleep -Seconds 60
if (Wait-Router -IP $RouterIP -Timeout 120 -Delay 5) {
    Write-Host "`n╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║              ГОТОВО! OpenWrt установлен успешно                  ║" -ForegroundColor Green
    Write-Host "╠══════════════════════════════════════════════════════════════════╣" -ForegroundColor Green
    Write-Host "║  Управление: http://$RouterIP/                                  ║" -ForegroundColor Green
    Write-Host "║  SSH:        ssh root@$RouterIP                                 ║" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green
} else {
    Write-Warn "Роутер не ответил после sysupgrade. Проверьте подключение вручную."
}
