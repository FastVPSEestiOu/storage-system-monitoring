storage-system-monitoring
==========================

Добро пожаловать, уважаемый клиент компании FastVPS Eesti OU! :) Вы пришли сюда потому что мы очень заботимся о Вас и сохранности Ваших Данных!

В данном репозитории размещен открытый код используемой нами системы диагностики дисковой подсистемы Ваших серверов. 

Как установить скрипт мониторинга?
```bash
wget --no-check-certificate https://raw.github.com/FastVPSEestiOu/storage-system-monitoring/master/install.sh -O /tmp/storage_install.sh && bash /tmp/storage_install.sh && rm /tmp/storage_install.sh
```

Насколько безопасен скрипт?
- Скрипт работает по шифрованному каналу (https, ssl)
- Скрипт не открывает портов на системе (что исключает вторжение извне)
- Скрипт не обновляется автоматически (что исключение добавление уязвимостей)
- Скрипт имеет полностью открытый код (что дает возможность ознакомиться с его содержимым)

Куда отправляются все данные? 
- Они отправляются по адресу https://fastcheck24.com по шифрованному соединению

Что мы делаем с данными?
- Мы их анализируем специализированным ПО использующим различные алгоритмы для предсказания возможного отказа дисковой подсистемы
- В случае обнаружения деструктивных проблем на дисковой подсистеме мы свяжемся с Вами по всем доступным способам

Какие виды аппаратных RAID поддерживает мониторинг?
- Adaptec
- LSI
- DELL PERC (LSI)

Что делает скрипт мониторинга?
- Ежечасно отправляет состояние Linux Soft Raid (только mdadm) либо аппаратного RAID массива
- Ежечасно отправяет выдачу smartctl по всем дискам в системе
- Активирует выполнение S.M.A.R.T. тестов (short+long) каждые выходные

Что скрипт НЕ делает?
- Скрипт не запускает никаких сторонних модулей
- Скрипт не обновляется в автоматическом режиме
- Скрипт не отправляет никакой информации кроме того, что перечислено выше

Какие ОС поддерживаются:
- Debian Linux 5 (только вручную), 6, 7 и старше
- Centos Linux 5 (только вручную), 6 и старше
- Parallels Cloud Server 6
- Ubuntu 12.04 и старше
- Citrix XenServer 6 (только вручную)

На каком языке написано ПО для мониторинга?
- Perl (модуль мониторинга)
- Bash (установщик)

Какие изменения в системе мы производим?
- Мы создаем cron скрипт: /etc/cron.d/storage-system-monitoring-fastvps
- Мы размещаем утилиты arcconf, megaraid, а также скрипт storage_system_fastvps_monitoring.pl в папке /usr/local/bin 
- Мы заменяем системный конфиг smartd /etc/smartd.conf (требуется для активации автозапуска S.M.A.R.T. short/long тестов)

Кто может использовать данное ПО?
- Любой клиент компании FastVPS Eesti OU

Какое ПО мы устанавливаем на сервер и для чего?
- parted - универсальный инструмент для получения информации о дисковых устройствах (используется только в инсталляторе)
- smartmontools - пакет утилит для получения S.M.A.R.T. информации из устройства
- Perl модули для работы с HTTP и HTTPS, для отправки данных на сервер для анализа
- arcconf/megacli - утилиты от производителей Adaptec и LSI

Откуда берется проприетарное ПО для LSI/Adaptec?
- http://download.adaptec.com/raid/storage_manager/arcconf_v1_5_20942.zip 1_5_20942
- http://www.lsi.com/downloads/Public/RAID%20Controllers/RAID%20Controllers%20Common%20Files/8.07.14_MegaCLI.zip 8.07.14 (.rpm)
- http://www.lsi.com/downloads/Public/Nytro/downloads/Nytro%20XD/MegaCli_Linux.zip 8.07.08-1 (.deb) 

Могу ли я использовать программу только локально, вручную проверяя состояние массивов?
- Да, разумеется, но при этом Вы лишаетсь возможностей нашей системы по анализу S.M.A.R.T. и прочих метрик, проверяется только состояние массива, также Вы не получаете никаких уведомлений в случае отказа дисков

Возможна ли поддержка XXX YYY?
- Разумеется, патчи приветствуются! 

Как установить скрипт на Gentoo?
- Для начала требуется установить все его зависимости, а после этого выполнить ручную установку:
```bash
emerge -atv sys-apps/smartmontools
emerge -atv dev-perl/JSON
emerge -atv dev-perl/libwww-perl
```

Как установить скрипт на Citrix XenServer?
- Нужно добавить Epel репозиторий соответствующей версии (требуется для perl-JSON)
- Устанавливаем зависимости:
```bash
yum install --enablerepo=base libstdc++ parted smartmontools perl-Crypt-SSLeay perl-libwww-perl perl-JSON
```

Как осуществляется установка на CentOS 5?
- До начала установки требуется подключить к системе репозиторий EPEL: https://fedoraproject.org/wiki/EPEL (требуется для perl-JSON)

Как осуществляется установка на CentOS 7?
- До начала установки требуется установить 
```bash
yum install --enablerepo=base perl-LWP-Protocol-https
```
- После окончания установки требуется запустить smartd
```bash
systemctl start smartd
```

Как осуществляется установка на Debian 5 Lenny?
- До начала установки установите следующие пакеты (а вообще, пора обновляться!):
```bash
apt-get install -y libwww-perl libjson-any-perl libcrypt-ssleay-perl
```

Как выглядит выдача скрипта?
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
