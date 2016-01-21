#!/bin/bash
#
# Это скрипт установщик для системы мониторинга дисковой подсистемы серверов компании FastVPS Eesti OU
# Если у Вас есть вопросы по работе данной системы, рекомендуем обратиться по адресам:
# - https://github.com/FastVPSEestiOu/storage-system-monitoring
# - https://bill2fast.com (через тикет систему)
#

# Данные пакеты обязательны к установке, так как используются скриптом мониторинга
DEBIAN_DEPS=(wget libstdc++5 parted smartmontools liblwp-useragent-determined-perl libnet-https-any-perl libcrypt-ssleay-perl libjson-perl)
CENTOS_DEPS=(wget libstdc++ parted smartmontools perl-Crypt-SSLeay perl-libwww-perl perl-JSON)
CENTOS7_DEPS=(wget libstdc++ parted smartmontools perl-Crypt-SSLeay perl-libwww-perl perl-JSON perl-LWP-Protocol-https)

# init.d script для smartd
SMARTD_REST_DEBIAN='/etc/init.d/smartmontools restart'
SMARTD_REST_CENTOS='/etc/init.d/smartd restart'
SMARTD_REST_CENTOS7='/bin/systemctl restart smartd.service'

GITHUB_FASTVPS_URL='https://raw.github.com/FastVPSEestiOu/storage-system-monitoring'

# Diag utilities repo
DIAG_UTILITIES_REPO='https://raw.github.com/FastVPSEestiOu/storage-system-monitoring/master/raid_monitoring_tools'

MONITORING_SCRIPT_NAME='storage_system_fastvps_monitoring.pl'

# Monitoring script URL
MONITORING_SCRIPT_URL="$GITHUB_FASTVPS_URL/master/$MONITORING_SCRIPT_NAME"

# Monitoring CRON file
CRON_FILE='/etc/cron.d/storage-system-monitoring-fastvps'

# Installation path
INSTALL_TO='/usr/local/bin'

# smartd config command to run repiodic tests (short/long)
SMARTD_COMMAND="# smartd.conf by FastVPS
# backup version of distrib file saved to /etc/smartd.conf.dist

# Discover disks and run short tests every day at 02:00 and long tests every sunday at 03:00
DEVICESCAN -d removable -n standby -s (S/../.././02|L/../../7/03)"

ARCH=
DISTRIB=

check_n_install_debian_deps() {
    echo "Installing Debian dependencies: ${DEBIAN_DEPS[*]} ..."
    apt-get update
    if ! apt-get install -y "${DEBIAN_DEPS[@]}"; then
        echo 'Something went wrong while installing dependencies!' >&2
    fi
    echo 'Finished installation of debian dependencies.'
}

check_n_install_centos_deps() {
    echo "Installing CentOS dependencies: ${CENTOS_DEPS[*]} ..."
    if ! yum install -y "${CENTOS_DEPS[@]}"; then
        echo 'Something went wrong while installing dependencies.' >&2
    fi
    echo 'Finished installation of CentOS dependencies.'
}

check_n_install_centos7_deps() {
    echo "Installing CentOS 7 dependencies: ${CENTOS_DEPS[*]} ..."
    if ! yum install -y "${CENTOS7_DEPS[@]}"; then
        echo 'Something went wrong while installing dependencies.' >&2
    fi
    echo 'Finished installation of CentOS 7 dependencies.'
}

# Проверяем наличие аппаратный RAID контроллеров и в случае наличия устанавливаем ПО для их мониторинга
check_n_install_diag_tools() {
    # utilities have suffix of ARCH, i.e. arcconf32 or megacli64
    ADAPTEC_UTILITY=arcconf
    # LSI_UTILITY=megacli

    lsi_raid=0
    adaptec_raid=0

    # флаг -m не используется, так как он не поддерживается в версии parted на CentOS 5
    parted_diag=$(parted -ls)

    echo 'Checking hardware for LSI or Adaptec RAID controllers...'
    if grep -i 'adaptec' <<< "$parted_diag"; then
        echo 'Found Adaptec raid'
        adaptec_raid=1
    fi
    if grep -Ei 'lsi|perc' <<< "$parted_diag"; then
        echo 'Found LSI raid'
        lsi_raid=1
    fi

    if (( adaptec_raid == 0 && lsi_raid == 0 )); then
        echo 'Hardware raid not found'
        return
    fi

    echo

    if (( adaptec_raid == 1 )); then
        echo 'Installing diag utilities for Adaptec raid...'
        wget --no-check-certificate "$DIAG_UTILITIES_REPO/arcconf$ARCH" -O "$INSTALL_TO/$ADAPTEC_UTILITY"
        chmod +x -- "$INSTALL_TO/$ADAPTEC_UTILITY"
        echo 'Finished installation of diag utilities for Apactec raid'
    fi

    echo

    if (( lsi_raid == 1 )); then
        echo 'Installing diag utilities for LSI MegaRaid...'

        # Dependencies installation
        case $DISTRIB in
            debian)
                wget --no-check-certificate "$DIAG_UTILITIES_REPO/megacli.deb" -O /tmp/megacli.deb
                dpkg -i /tmp/megacli.deb
                rm -f /tmp/megacli.deb
            ;;
            centos)
                yum install -y "$DIAG_UTILITIES_REPO/megacli.rpm"
            ;;
            *)
                echo 'Cannot install LSI tools for you distribution'
                exit 1
            ;;
        esac

        echo 'Finished installation of diag utilities for LSI raid'
    fi
}

install_monitoring_script() {
    # Remove old monitoring run script
    rm -f '/etc/cron.hourly/storage-system-monitoring-fastvps'

    echo "Installing monitoring.pl into $INSTALL_TO..."
    wget --no-check-certificate "$MONITORING_SCRIPT_URL" -O "$INSTALL_TO/$MONITORING_SCRIPT_NAME"
    chmod +x -- "$INSTALL_TO/$MONITORING_SCRIPT_NAME"

    echo "Installing CRON task to $CRON_FILE"
    echo '# FastVPS disk monitoring tool' > "$CRON_FILE"
    echo '# https://github.com/FastVPSEestiOu/storage-system-monitoring' >> "$CRON_FILE"

    # We should randomize run time to prevent ddos attacks to our gates
    # Limit random numbers by 59 minutes
    ((CRON_START_TIME = RANDOM % 59))

    echo "We tune cron task to run on $CRON_START_TIME minutes of every hour"
    echo "$CRON_START_TIME * * * * root $INSTALL_TO/$MONITORING_SCRIPT_NAME --cron >/dev/null 2>&1" >> "$CRON_FILE"
    chmod 644 -- "$CRON_FILE"
}

# We should enable smartd startup explicitly because it is switched off by default
enable_smartd_start_debian() {
    if ! grep -E '^start_smartd=yes' '/etc/default/smartmontools' > /dev/null; then
        echo 'start_smartd=yes' >> '/etc/default/smartmontools'
    fi
}

start_smartd_tests() {
    echo -n 'Creating config for smartd... '

    # creating config and restart service
    case $DISTRIB in
        debian)
        if [[ ! -e /etc/smartd.conf.dist ]]; then # TODO why?
            mv /etc/smartd.conf /etc/smartd.conf.dist
        fi
        echo "$SMARTD_COMMAND" > /etc/smartd.conf
        enable_smartd_start_debian
        $SMARTD_REST_DEBIAN
        ;;

        centos)
        if [[ ! -e /etc/smartd.conf.dist ]]; then # TODO why?
            mv /etc/smartd.conf /etc/smartd.conf.dist
        fi
        /sbin/chkconfig smartd on
        echo "$SMARTD_COMMAND" > /etc/smartd.conf
        $SMARTD_REST_CENTOS
        ;;

        centos7)
        if [[ ! -e /etc/smartmontools/smartd.conf.dist ]]; then # TODO why?
            mv /etc/smartmontools/smartd.conf /etc/smartmontools/smartd.conf.dist
        fi
        echo "$SMARTD_COMMAND" > /etc/smartmontools/smartd.conf
        $SMARTD_REST_CENTOS7
        ;;
    esac

    echo 'done.'

    if (( $? != 0 )); then
        echo 'smartd failed to start. This may be caused by absence of disks SMART able to monitor.' >&2
        tail /var/log/messages
    fi
}

#
# Start installation procedure
#

ARCH=32
if uname -a | grep -E 'amd64|x86_64' > /dev/null; then # XXX perhaps 'uname -m' is better?
    ARCH=64
fi

if grep -Ei 'Debian|Ubuntu|Proxmox' < /etc/issue > /dev/null; then
    DISTRIB=debian
elif grep -Ei 'CentOS|Fedora|Parallels|Citrix XenServer' < /etc/issue > /dev/null; then
    DISTRIB=centos
elif [ -f /etc/centos-release ] && grep -Ei 'CentOS\ Linux\ release\ 7' < /etc/centos-release > /dev/null; then
    DISTRIB=centos7
fi

echo "We are working on $DISTRIB $ARCH"

# Dependencies installation
case $DISTRIB in
    debian)
    check_n_install_debian_deps
    ;;

    centos)
    check_n_install_centos_deps
    ;;

    centos7)
    check_n_install_centos7_deps
    ;;

    *)
    echo 'Cannot determine OS. Exiting...'
    exit 1
    ;;
esac

# Diagnostic tools installation
check_n_install_diag_tools

# Monitoring script installation
install_monitoring_script

# Periodic smartd tests
start_smartd_tests

echo 'Send data to FastVPS...'
if "$INSTALL_TO/$MONITORING_SCRIPT_NAME" --cron; then
    echo 'Data sent successfully'
else
    echo 'Cannot run script in --cron mode'
fi

echo 'Checking disk system...'
"$INSTALL_TO/$MONITORING_SCRIPT_NAME" --detect
