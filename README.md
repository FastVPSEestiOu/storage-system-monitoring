storage-system-monitoring
==========================

*Go to [English version](README.en.md).*

Добро пожаловать, уважаемый клиент компании FastVPS Eesti OU! :) Вы пришли сюда потому что мы очень заботимся о Вас и сохранности Ваших Данных!

В данном репозитории размещен открытый код используемой нами системы диагностики дисковой подсистемы Ваших серверов. 

### Как установить скрипт мониторинга?
- В автоматическом режиме (рекомендованный способ):
```bash
wget --no-check-certificate https://raw.github.com/FastVPSEestiOu/storage-system-monitoring/master/install.sh -O /tmp/storage_install.sh && bash /tmp/storage_install.sh && rm --force /tmp/storage_install.sh
```

- [Вручную](#Ручная-установка).

### Какие ОС поддерживаются:
- Debian 6-9
- Centos 6-7
- Ubuntu 12.04, 14.04, 16.04

### Насколько безопасен скрипт?
- Скрипт работает по шифрованному каналу (https, ssl)
- Скрипт не открывает портов на системе (что исключает вторжение извне)
- Скрипт не обновляется автоматически (что исключение добавление уязвимостей)
- Скрипт имеет полностью открытый код (что дает возможность ознакомиться с его содержимым)

### Куда отправляются все данные? 
- Они отправляются по адресу https://fastcheck24.com по шифрованному соединению

### Что мы делаем с данными?
- Мы их анализируем специализированным ПО использующим различные алгоритмы для предсказания возможного отказа дисковой подсистемы
- В случае обнаружения деструктивных проблем на дисковой подсистеме мы свяжемся с Вами по всем доступным способам

### Какие виды аппаратных RAID поддерживает мониторинг?
- Adaptec
- LSI
- DELL PERC (LSI)

### Что делает скрипт мониторинга?
- Ежечасно отправляет состояние Linux Soft Raid (только mdadm) либо аппаратного RAID массива
- Ежечасно отправяет выдачу smartctl по всем дискам в системе
- Активирует выполнение S.M.A.R.T. тестов (short+long) каждые выходные

### Что скрипт НЕ делает?
- Скрипт не запускает никаких сторонних модулей
- Скрипт не обновляется в автоматическом режиме
- Скрипт не отправляет никакой информации кроме того, что перечислено выше

### На каком языке написано ПО для мониторинга?
- Perl (модуль мониторинга)
- Bash (установщик)

### Какие изменения в системе мы производим?
- Мы создаем cron скрипт: /etc/cron.d/storage-system-monitoring-fastvps
- Мы размещаем утилиты arcconf, megaraid, а также скрипт storage_system_fastvps_monitoring.pl в папке /usr/local/bin 
- Мы заменяем системный конфиг smartd /etc/smartd.conf (требуется для активации автозапуска S.M.A.R.T. short/long тестов)

### Кто может использовать данное ПО?
- Любой клиент компании FastVPS Eesti OU

### Какое ПО мы устанавливаем на сервер и для чего?
- smartmontools - пакет утилит для получения S.M.A.R.T. информации из устройства
- Perl модули для работы с HTTP и HTTPS, для отправки данных на сервер для анализа
- arcconf/megacli - утилиты от производителей Adaptec и LSI

### Откуда берется проприетарное ПО для LSI/Adaptec?
- https://storage.microsemi.com/en-us/speed/raid/storage_manager/arcconf_v2_01_22270_zip.php
- https://docs.broadcom.com/docs-and-downloads/sep/oracle/files/Linux_MegaCLI-8-07-07.zip

### Могу ли я использовать программу только локально, вручную проверяя состояние массивов?
- Да, разумеется, но при этом Вы лишаетсь возможностей нашей системы по анализу S.M.A.R.T. и прочих метрик, проверяется только состояние массива, также Вы не получаете никаких уведомлений в случае отказа дисков

### Возможна ли поддержка XXX YYY?
- Разумеется, патчи приветствуются! 

### Как выглядит выдача скрипта?
```bash
storage_system_fastvps_monitoring.pl --detect
Device /dev/sda with type: raid model: adaptec in state: optimal detected
Device /dev/sda with type: raid model: lsi in state: optimal detected
Device /dev/sda with type: hard_disk model: ATA SAMSUNG HD753LJ detected
Device /dev/sdb with type: hard_disk model: ATA SAMSUNG HD753LJ detected
Device /dev/sdc with type: hard_disk model: ATA ST31500341AS detected
Device /dev/sdd with type: hard_disk model: ATA ST31500341AS detected
Device /dev/md0 with type: raid model: md in state: clean detected
Device /dev/md1 with type: raid model: md in state: clean detected
Device /dev/md2 with type: raid model: md in state: clean detected
Device /dev/md3 with type: raid model: md in state: clean detected
```
------------------------------------

### Ручная установка

#### При наличии аппаратного контроллера необходимо установить ПО для работы с ним
- Для **Adaptec** нужно выбрать ПО, соответствующее модели контроллера. Обычно для контроллеров 6-ой серии и новее используется новая версия. Она есть только для 64-битных ОС. [Список поддерживаемых контроллеров](https://storage.microsemi.com/en-us/speed/raid/storage_manager/arcconf_v2_05_22932_zip.php).
```bash
wget --no-check-certificate https://raw.githubusercontent.com/FastVPSEestiOu/storage-system-monitoring/master/raid_monitoring_tools/arcconf_new --output-document=/usr/local/bin/arcconf
chmod +x /usr/local/bin/arcconf
```

- Для более старых контроллеров используется старая версия ПО, и необходимо выбрать соотествующую ОС разрядность. [Список поддерживаемых контроллеров](https://storage.microsemi.com/en-us/speed/raid/storage_manager/asm_linux_x64_v7_31_18856_tgz.php).
```bash
# 64-bit OS
wget --no-check-certificate https://raw.githubusercontent.com/FastVPSEestiOu/storage-system-monitoring/master/raid_monitoring_tools/arcconf64_old --output-document=/usr/local/bin/arcconf
chmod +x /usr/local/bin/arcconf

# 32-bit OS
wget --no-check-certificate https://raw.githubusercontent.com/FastVPSEestiOu/storage-system-monitoring/master/raid_monitoring_tools/arcconf32_old --output-document=/usr/local/bin/arcconf
chmod +x /usr/local/bin/arcconf
```
- Лучше свериться c поддерживаемым контроллером ПО [На сайте разработчика](https://storage.microsemi.com/en-us/downloads/).

- Для **LSI** необходимо выбрать версию, соответствующую разрядности ОС.
```bash
# 64-bit OS
wget --no-check-certificate https://raw.githubusercontent.com/FastVPSEestiOu/storage-system-monitoring/master/raid_monitoring_tools/megacli64 --output-document=/usr/local/bin/megacli
chmod +x /usr/local/bin/megacli

# 32-bit OS
wget --no-check-certificate https://raw.githubusercontent.com/FastVPSEestiOu/storage-system-monitoring/master/raid_monitoring_tools/megacli32 --output-document=/usr/local/bin/megacli
chmod +x /usr/local/bin/megacli
```

#### Также в процессе установки потребуется создать конфигурационный файл SMARTD в зависимости от используемого типа RAID

- Программный массив.

```bash
cp /etc/smartd.conf /etc/smartd.conf.$$
echo 'DEVICESCAN -d removable -n standby -s (S/../.././02|L/../../7/03)' > /etc/smartd.conf
```

- Adaptec. Определяем устройства /dev/sgX, отвечающие за физические диски и добавляем для каждого строчку вида:
```bash
/dev/sgX -n standby -s (S/../.././02|L/../../7/03)
```

```bash
cp /etc/smartd.conf /etc/smartd.conf.$$
echo '' > /etc/smartd.conf
for sgx in /dev/sg?; do
    if smartctl -q silent -i "$sgx"; then
        echo "${sgx} -n standby -s (S/../.././02|L/../../7/03)" >> /etc/smartd.conf
    fi
done
```

- LSI. Определяем устройства, отвечающие за физические диски при помощи megacli и добавляем для каждого строчку вида:
```bash
/dev/sda -d megaraid,2 -n standby -s (S/../.././02|L/../../7/03)
```

```bash
cp /etc/smartd.conf /etc/smartd.conf.$$
echo '' > /etc/smartd.conf
for drive in $(megacli -pdlist -a0| awk '/Device Id/ {print $NF}'); do
    echo "/dev/sda -d megaraid,${drive} -n standby -s (S/../.././02|L/../../7/03)" >> /etc/smartd.conf
done
```

#### Debian 8-9, Ubuntu 16.04
```bash
apt-get update -qq && apt-get install wget libstdc++5 smartmontools liblwp-useragent-determined-perl libnet-https-any-perl libcrypt-ssleay-perl libjson-perl

wget --no-check-certificate https://raw.githubusercontent.com/FastVPSEestiOu/storage-system-monitoring/master/storage_system_fastvps_monitoring.pl --output-document=/usr/local/bin/storage_system_fastvps_monitoring.pl
chmod +x /usr/local/bin/storage_system_fastvps_monitoring.pl

echo "# FastVPS disk monitoring tool
# https://github.com/FastVPSEestiOu/storage-system-monitoring
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
$(((RANDOM % 59))) * * * * root /usr/local/bin/storage_system_fastvps_monitoring.pl --cron >/dev/null 2>&1" > /etc/cron.d/storage-system-monitoring-fastvps
chmod 644 /etc/cron.d/storage-system-monitoring-fastvps

systemctl restart smartd.service
systemctl enable smartd.service
```

#### Debian 6-7, Ubuntu 12.04, Ubuntu 14.04
```bash
apt-get update -qq && apt-get install wget libstdc++5 smartmontools liblwp-useragent-determined-perl libnet-https-any-perl libcrypt-ssleay-perl libjson-perl

wget --no-check-certificate https://raw.githubusercontent.com/FastVPSEestiOu/storage-system-monitoring/master/storage_system_fastvps_monitoring.pl --output-document=/usr/local/bin/storage_system_fastvps_monitoring.pl
chmod +x /usr/local/bin/storage_system_fastvps_monitoring.pl

echo "# FastVPS disk monitoring tool
# https://github.com/FastVPSEestiOu/storage-system-monitoring
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
$(((RANDOM % 59))) * * * * root /usr/local/bin/storage_system_fastvps_monitoring.pl --cron >/dev/null 2>&1" > /etc/cron.d/storage-system-monitoring-fastvps
chmod 644 /etc/cron.d/storage-system-monitoring-fastvps

/etc/init.d/smartmontools restart
update-rc.d smartmontools defaults
```

#### CentOS 7
```bash
yum install -q -y wget libstdc++ smartmontools perl-Crypt-SSLeay perl-libwww-perl perl-JSON perl-LWP-Protocol-https

wget --no-check-certificate https://raw.githubusercontent.com/FastVPSEestiOu/storage-system-monitoring/master/storage_system_fastvps_monitoring.pl --output-document=/usr/local/bin/storage_system_fastvps_monitoring.pl
chmod +x /usr/local/bin/storage_system_fastvps_monitoring.pl

echo "# FastVPS disk monitoring tool
# https://github.com/FastVPSEestiOu/storage-system-monitoring
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
$(((RANDOM % 59))) * * * * root /usr/local/bin/storage_system_fastvps_monitoring.pl --cron >/dev/null 2>&1" > /etc/cron.d/storage-system-monitoring-fastvps
chmod 644 /etc/cron.d/storage-system-monitoring-fastvps

systemctl restart smartd.service
systemctl enable smartd.service
```

#### CentOS 6
```bash
yum install -q -y wget libstdc++ smartmontools perl-Crypt-SSLeay perl-libwww-perl perl-JSON

wget --no-check-certificate https://raw.githubusercontent.com/FastVPSEestiOu/storage-system-monitoring/master/storage_system_fastvps_monitoring.pl --output-document=/usr/local/bin/storage_system_fastvps_monitoring.pl
chmod +x /usr/local/bin/storage_system_fastvps_monitoring.pl

echo "# FastVPS disk monitoring tool
# https://github.com/FastVPSEestiOu/storage-system-monitoring
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
$(((RANDOM % 59))) * * * * root /usr/local/bin/storage_system_fastvps_monitoring.pl --cron >/dev/null 2>&1" > /etc/cron.d/storage-system-monitoring-fastvps
chmod 644 /etc/cron.d/storage-system-monitoring-fastvps

/etc/init.d/smartd restart
chkconfig smartd on
```

#### Выполняем локальную проверку и тестовую отправку данных на сервер.
```bash
/usr/local/bin/storage_system_fastvps_monitoring.pl --detect

/usr/local/bin/storage_system_fastvps_monitoring.pl --cron
```
Установка завершена.

