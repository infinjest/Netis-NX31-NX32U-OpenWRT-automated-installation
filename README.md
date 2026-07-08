# Netis-NX31-NX32U-OpenWRT-automated-installation

1) Что понадобится на ПК

- PuTTY (plink.exe + pscp.exe) — SSH/SCP с передачей пароля
- tftpd64 — TFTP-сервер, запускается из командной строки
- Папка firmware\ с четырьмя файлами OpenWrt. Например, для NX31 ссылки на файлы для OpenWRT 24.10.1:

https://archive.openwrt.org/releases/24.10.1/targets/mediatek/filogic/openwrt-24.10.1-mediatek-filogic-netis_nx31-bl31-uboot.fip
https://archive.openwrt.org/releases/24.10.1/targets/mediatek/filogic/openwrt-24.10.1-mediatek-filogic-netis_nx31-initramfs-recovery.itb
https://archive.openwrt.org/releases/24.10.1/targets/mediatek/filogic/openwrt-24.10.1-mediatek-filogic-netis_nx31-preloader.bin
https://archive.openwrt.org/releases/24.10.1/targets/mediatek/filogic/openwrt-24.10.1-mediatek-filogic-netis_nx31-squashfs-sysupgrade.itb


2) Как пользоваться

1. Подготовка папки (4 скачанных файла надо переименовать, убрав версию OpenWRT):

nx3X_flash_openwrt.ps1
firmware\
  openwrt-mediatek-filogic-netis_nx31-bl31-uboot.fip
  openwrt-mediatek-filogic-netis_nx31-preloader.bin
  openwrt-mediatek-filogic-netis_nx31-initramfs-recovery.itb
  openwrt-mediatek-filogic-netis_nx31-squashfs-sysupgrade.itb
  
3. Настроить IP сетевого адаптера: 192.168.1.254 / 255.255.255.0
  
5. Разрешить запуск скрипта (один раз в PowerShell от администратора):
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

7. Запустить:
.\nx3X_flash_openwrt.ps1
