# Netis-NX31-NX32U-OpenWRT-automated-installation

Как пользоваться:

1. В папку firmware\ положить 4 переименованных файла OpenWrt. Например, для NX31 ссылки на файлы для OpenWRT 24.10.1:

[openwrt-mediatek-filogic-netis_nx31-bl31-uboot.fip](https://archive.openwrt.org/releases/24.10.1/targets/mediatek/filogic/openwrt-24.10.1-mediatek-filogic-netis_nx31-bl31-uboot.fip)

[openwrt-mediatek-filogic-netis_nx31-preloader.bin](https://archive.openwrt.org/releases/24.10.1/targets/mediatek/filogic/openwrt-24.10.1-mediatek-filogic-netis_nx31-initramfs-recovery.itb)

[openwrt-mediatek-filogic-netis_nx31-initramfs-recovery.itb](https://archive.openwrt.org/releases/24.10.1/targets/mediatek/filogic/openwrt-24.10.1-mediatek-filogic-netis_nx31-preloader.bin)

[openwrt-mediatek-filogic-netis_nx31-squashfs-sysupgrade.itb](https://archive.openwrt.org/releases/24.10.1/targets/mediatek/filogic/openwrt-24.10.1-mediatek-filogic-netis_nx31-squashfs-sysupgrade.itb)

2. Настроить IP сетевого адаптера: **192.168.1.254 / 255.255.255.0**
  
3. Разрешить запуск скрипта (один раз в PowerShell от администратора):
```PowerShell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

5. Запустить:
```PowerShell
.\nx3X_flash_openwrt.ps1
```
