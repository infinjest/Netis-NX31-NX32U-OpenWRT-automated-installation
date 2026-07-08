#Requires -Version 5.1
<#
.SYNOPSIS
    Netis NX31 / NX32U → OpenWrt (24.10.1+) | Скрипт автоматической установки

.DESCRIPTION
    Автоматизирует:
      - MTD-бэкап всех разделов (6 партиций)
      - Скачивание бэкапа на ПК
      - Загрузку файлов прошивки на роутер
      - Автоматическую прошивку загрузчика (FIP и BL2)
      - Запуск TFTP-сервера (tftpd64)
      - Стирание UBI-раздела и перезагрузку
      - Ожидание загрузки recovery-образа
      - Загрузку sysupgrade и финальную прошивку

.REQUIREMENTS
    - PuTTY (plink.exe, pscp.exe) — https://www.chiark.greenend.org.uk/~sgtatham/putty/
    - tftpd64 — https://pjo2.github.io/tftpd64/
    - Четыре файла OpenWrt в папке $FirmwareDir:
        *-bl31-uboot.fip
        *-preloader.bin
        *-initramfs-recovery.itb
        *-squashfs-sysupgrade.itb

.EXAMPLE
    .\nx3X_flash_openwrt.ps1
    .\nx3X_flash_openwrt.ps1 -RouterIP 192.168.1.1 -User admin -FirmwareDir .\fw
#>

param(
    [string]$RouterIP    = "192.168.1.1",
    [string]$User        = "admin",
    [string]$FirmwareDir = ".\firmware",
    [string]$BackupDir   = ".\backup",
    [string]$PlinkPath   = ".\putty-64bit-0.84-plink-pscp\plink.exe",
    [string]$PscpPath    = ".\putty-64bit-0.84-plink-pscp\pscp.exe",
    [string]$Tftpd64Path = ".\tftpd64_portable_v4.74\tftpd64.exe"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─── Цвета ────────────────────────────────────────────────────────────────────
function Write-Step  { param($msg) Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-OK    { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "  [!]  $msg" -ForegroundColor Yellow }
function Write-Fail  { param($msg) Write-Host "  [X]  $msg" -ForegroundColor Red; exit 1 }

# ─── Проверка зависимостей ────────────────────────────────────────────────────
Write-Step "ПРОВЕРКА ЗАВИСИМОСТЕЙ"
foreach ($tool in @($PlinkPath, $PscpPath, $Tftpd64Path)) {
    if (-not (Test-Path $tool)) {
        Write-Fail "Не найден: $tool`n     Укажите путь через параметр скрипта."
    }
    Write-OK $tool
}

# Проверка наличия файлов прошивки
$FirmwareDir = Resolve-Path $FirmwareDir -ErrorAction SilentlyContinue
if (-not $FirmwareDir) { Write-Fail "Папка с прошивкой не найдена: $FirmwareDir" }

function Find-Fw { param($pattern)
    $f = Get-ChildItem (Join-Path $FirmwareDir $pattern) -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $f) { Write-Fail "Файл не найден: $pattern в $FirmwareDir" }
    return $f
}
$FipFile       = Find-Fw "*bl31-uboot.fip"
$PreloaderFile = Find-Fw "*preloader.bin"
$RecoveryFile  = Find-Fw "*initramfs-recovery.itb"
$SysupgrFile   = Find-Fw "*squashfs-sysupgrade.itb"

Write-OK "bl31-uboot.fip      → $($FipFile.Name)"
Write-OK "preloader.bin       → $($PreloaderFile.Name)"
Write-OK "initramfs-recovery  → $($RecoveryFile.Name)"
Write-OK "sysupgrade          → $($SysupgrFile.Name)"

# ─── Учётные данные ───────────────────────────────────────────────────────────
Write-Host ""
$SecPwd  = Read-Host "Введите SSH-пароль роутера ($User@$RouterIP)" -AsSecureString
$Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
             [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecPwd))

# ─── Вспомогательные функции SSH/SCP ─────────────────────────────────────────
function Invoke-SSH {
    param([string]$Cmd, [switch]$IgnoreExit)
    $out = & $PlinkPath -ssh -pw $Password -batch -no-antispoof "$User@$RouterIP" $Cmd 2>&1
    if ($LASTEXITCODE -ne 0 -and -not $IgnoreExit) {
        Write-Warn "SSH вернул код $LASTEXITCODE для команды: $Cmd"
    }
    return $out
}

function Invoke-Download {
    param([string]$Remote, [string]$Local)
    & $PscpPath -pw $Password -batch -scp "$User@${RouterIP}:$Remote" $Local 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Fail "SCP download не удался: $Remote" }
}

function Invoke-Upload {
    param([string]$Local, [string]$Remote)
    & $PscpPath -pw $Password -batch -scp $Local "$User@${RouterIP}:$Remote" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Fail "SCP upload не удался: $Local" }
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
    Write-Host ""
    return $false
}

# ─── ФАЗА 1: MTD-БЭКАП ───────────────────────────────────────────────────────
Write-Step "ФАЗА 1 — MTD-БЭКАП"
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

$Partitions = @(
    @{ id = "mtd0"; name = "spi0.0"    },
    @{ id = "mtd1"; name = "BL2"       },
    @{ id = "mtd2"; name = "u-boot-env"},
    @{ id = "mtd3"; name = "Factory"   },
    @{ id = "mtd4"; name = "FIP"       },
    @{ id = "mtd5"; name = "ubi"       }
)

foreach ($p in $Partitions) {
    $gz = "$($p.id)_$($p.name).bin.gz"
    Write-Host "  Бэкап $($p.name) ($($p.id))..."
    Invoke-SSH "cat /dev/$($p.id) | gzip -1 -c > /tmp/$gz"
}
Write-OK "Все разделы сжаты в /tmp/ на роутере"

# ─── ФАЗА 2: СКАЧИВАНИЕ БЭКАПА ───────────────────────────────────────────────
Write-Step "ФАЗА 2 — СКАЧИВАНИЕ БЭКАПА НА ПК"
foreach ($p in $Partitions) {
    $gz = "$($p.id)_$($p.name).bin.gz"
    Write-Host "  Скачиваю $gz..."
    Invoke-Download "/tmp/$gz" (Join-Path $BackupDir $gz)
    Write-OK $gz
}
Write-OK "Бэкапы сохранены в: $BackupDir"

# ─── ФАЗА 3: ЗАГРУЗКА ФАЙЛОВ ЗАГРУЗЧИКА ──────────────────────────────────────
Write-Step "ФАЗА 3 — ЗАГРУЗКА ФАЙЛОВ ЗАГРУЗЧИКА НА РОУТЕР"
Write-Host "  Загружаю $($FipFile.Name)..."
Invoke-Upload $FipFile.FullName "/tmp/$($FipFile.Name)"
Write-OK $FipFile.Name

Write-Host "  Загружаю $($PreloaderFile.Name)..."
Invoke-Upload $PreloaderFile.FullName "/tmp/$($PreloaderFile.Name)"
Write-OK $PreloaderFile.Name

# ─── ФАЗА 3.5: АВТОМАТИЧЕСКАЯ ПРОШИВКА ЗАГРУЗЧИКА ────────────────────────────
Write-Step "ФАЗА 3.5 — ПРОШИВКА ЗАГРУЗЧИКА (FIP и BL2)"

Write-Host "  Запись $($FipFile.Name) в раздел FIP..."
Invoke-SSH "mtd write /tmp/$($FipFile.Name) FIP"
Write-OK "Раздел FIP обновлен"

Write-Host "  Запись $($PreloaderFile.Name) в раздел BL2..."
Invoke-SSH "mtd write /tmp/$($PreloaderFile.Name) BL2"
Write-OK "Раздел BL2 обновлен"

# ─── ФАЗА 4: TFTP + СТИРАНИЕ UBI + ПЕРЕЗАГРУЗКА ─────────────────────────────
Write-Step "ФАЗА 4 — ЗАПУСК TFTP, СТИРАНИЕ UBI, ПЕРЕЗАГРУЗКА"

# Скопировать recovery-файл в папку прошивок (tftpd64 раздаёт оттуда)
$TftpRoot = $FirmwareDir.Path
Copy-Item $RecoveryFile.FullName (Join-Path $TftpRoot $RecoveryFile.Name) -Force -ErrorAction SilentlyContinue

Write-Host "  Запускаю tftpd64 (IP сервера должен быть 192.168.1.254)..."
Write-Warn "Убедитесь, что сетевой адаптер настроен на IP 192.168.1.254/24"
$TftpdProc = Start-Process -FilePath $Tftpd64Path `
    -ArgumentList "--config", $TftpRoot `
    -PassThru -WindowStyle Minimized

Start-Sleep -Seconds 2
Write-OK "tftpd64 запущен (PID $($TftpdProc.Id))"

Write-Host "  Стираю UBI и перезагружаю роутер..."
Invoke-SSH "mtd erase ubi; reboot" -IgnoreExit
Write-OK "Роутер перезагружается, будет грузиться recovery по TFTP..."

Write-Host "  Ожидаю появления recovery-образа на 192.168.1.1 (~90 сек)..."
Start-Sleep -Seconds 40

if (-not (Wait-Router -IP $RouterIP -Timeout 150 -Delay 10)) {
    Stop-Process -Id $TftpdProc.Id -Force -ErrorAction SilentlyContinue
    Write-Fail "Recovery-образ не поднялся. Проверьте TFTP-сервер и подключение."
}

# Останавливаем TFTP — больше не нужен
Stop-Process -Id $TftpdProc.Id -Force -ErrorAction SilentlyContinue
Write-OK "tftpd64 остановлен"

# ─── ФАЗА 5: ЗАГРУЗКА И УСТАНОВКА SYSUPGRADE ─────────────────────────────────
Write-Step "ФАЗА 5 — ЗАГРУЗКА SYSUPGRADE И ФИНАЛЬНАЯ ПРОШИВКА"

Write-Host "  Загружаю $($SysupgrFile.Name) на recovery-образ..."
Invoke-Upload $SysupgrFile.FullName "/tmp/$($SysupgrFile.Name)"
Write-OK "Файл загружен"

Write-Host "  Запускаю sysupgrade (роутер перезагрузится в OpenWrt)..."
Invoke-SSH "sysupgrade -n /tmp/$($SysupgrFile.Name)" -IgnoreExit

Write-Host "  Ожидаю загрузки OpenWrt (~90 сек)..."
Start-Sleep -Seconds 60

if (Wait-Router -IP $RouterIP -Timeout 120 -Delay 5) {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║              ГОТОВО! OpenWrt установлен успешно                  ║" -ForegroundColor Green
    Write-Host "╠══════════════════════════════════════════════════════════════════╣" -ForegroundColor Green
    Write-Host "║  Web-интерфейс:  http://$RouterIP/                          ║" -ForegroundColor Green
    Write-Host "║  SSH:            ssh root@$RouterIP  (пароль пустой)       ║" -ForegroundColor Green
    Write-Host "║  Бэкапы хранятся: $BackupDir" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
} else {
    Write-Warn "Роутер не вышел на связь после sysupgrade."
    Write-Warn "Возможно, прошивка устанавливается дольше. Подождите и проверьте $RouterIP вручную."
}
