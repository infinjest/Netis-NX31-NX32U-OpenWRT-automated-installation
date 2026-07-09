# Netis-NX31-NX32U-OpenWRT-automated-installation

Как пользоваться (на ПК под Windows):

0. Скачать архив (Code > Download ZIP). Создать пустую папку с отсутствием кириллицы в пути, скопировать в нее файлы и папки репозитория.

1. В папку firmware\ положить 4 файла OpenWrt требуемой версии для нужной модели роутера. Например, файлы OpenWRT 24.10.1 для NX31:

[openwrt-mediatek-filogic-netis_nx31-bl31-uboot.fip](https://archive.openwrt.org/releases/24.10.1/targets/mediatek/filogic/openwrt-24.10.1-mediatek-filogic-netis_nx31-bl31-uboot.fip)  
[openwrt-mediatek-filogic-netis_nx31-initramfs-recovery.itb](https://archive.openwrt.org/releases/24.10.1/targets/mediatek/filogic/openwrt-24.10.1-mediatek-filogic-netis_nx31-initramfs-recovery.itb)  
[openwrt-mediatek-filogic-netis_nx31-preloader.bin](https://archive.openwrt.org/releases/24.10.1/targets/mediatek/filogic/openwrt-24.10.1-mediatek-filogic-netis_nx31-preloader.bin)  
[openwrt-mediatek-filogic-netis_nx31-squashfs-sysupgrade.itb](https://archive.openwrt.org/releases/24.10.1/targets/mediatek/filogic/openwrt-24.10.1-mediatek-filogic-netis_nx31-squashfs-sysupgrade.itb)  

2. Файл firmware\sha256sums либо удалить для пропуска проверки хеш-сумм, либо заменить в нем все строки на хеш-суммы скачанных файлов из поля sha256sum таблицы.

3. Настроить IP сетевого адаптера: **192.168.1.254 / 255.255.255.0**. Подключить ПК кабелем к роутеру в любой LAN-порт роутера.
  
4. Открыть PowerShell с правами администратора и разрешить запуск скрипта:
```PowerShell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

5. Перейти в папку из п. 0 и запустить скрипт:
```PowerShell
cd <путь к папке>
.\nx3X_flash_openwrt.ps1
```
