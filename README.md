# Netis-NX31-NX32U-OpenWRT-automated-installation

Как пользоваться (на ПК под Windows):

0. Скачать архив (Code > Download ZIP). Создать пустую папку с отсутствием кириллицы и пробелов в пути, скопировать в нее файлы и папки репозитория.

1. В папку firmware\ положить 4 файла OpenWrt требуемой версии для нужной модели роутера. Пример - ссылки на файлы OpenWRT 24.10.1 для NX31: [1](https://archive.openwrt.org/releases/24.10.1/targets/mediatek/filogic/openwrt-24.10.1-mediatek-filogic-netis_nx31-bl31-uboot.fip) [2](https://archive.openwrt.org/releases/24.10.1/targets/mediatek/filogic/openwrt-24.10.1-mediatek-filogic-netis_nx31-initramfs-recovery.itb) [3](https://archive.openwrt.org/releases/24.10.1/targets/mediatek/filogic/openwrt-24.10.1-mediatek-filogic-netis_nx31-preloader.bin) [4](https://archive.openwrt.org/releases/24.10.1/targets/mediatek/filogic/openwrt-24.10.1-mediatek-filogic-netis_nx31-squashfs-sysupgrade.itb)

2. Файл firmware\sha256sums либо удалить для пропуска проверки целостности файлов, либо заменить в нем все строки на хеш-суммы скачанных файлов из поля sha256sum таблицы.

3. Настроить сетевой адаптер ПК: статический IP 192.168.1.254, маска 255.255.255.0. Подключить ПК кабелем к роутеру в LAN-порт роутера.

4. Подключиться к веб-интерфейсу роутера и либо оставить пароль admin (если не выключен производителем), либо задать и запомнить свой.
  
5. На ПК открыть PowerShell с правами администратора и разрешить запуск скрипта, перейти в папку из п. 0 и запустить скрипт:
```PowerShell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
cd <путь к папке>
.\nx3X_flash_openwrt.ps1
```
В процессе работы скрипт попросит ввести текущий SSH-пароль от заводской прошивки роутера - он совпадает с паролем к веб-интерфейсу.
Данные для входа в интерфейс роутера со свежеустановленной OpenWRT - логин root, без пароля (рекомендуется установить).
