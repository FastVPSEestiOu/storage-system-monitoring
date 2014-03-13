#!/bin/bash

#
# Это скрипт установщик для системы мониторинга дисковой подсистемы серверов компании FastVPS Eesti OU
# Если у Вас есть вопросы по работе данной системы, рекомендуем обратиться по адресам:
# - https://github.com/FastVPSEestiOu/storage-system-monitoring
# - https://bill2fast.com (через тикет систему)

# Данные пакеты обязательны к установке, так как используются скриптом мониторинга
DEBIAN_DEPS="wget libstdc++5 parted smartmontools liblwp-useragent-determined-perl libnet-https-any-perl libcrypt-ssleay-perl libfile-spec-perl"
CENTOS_DEPS="wget libstdc++ parted smartmontools perl-Crypt-SSLeay perl-libwww-perl"

# Diag utilities repo
DIAG_UTILITIES_REPO="https://github.com/FastVPSEestiOu/........"
# utilities have suffix of ARCH, i.e. arcconf32 or megacli64
ADAPTEC_UTILITY=arcconf
LSI_UTILITY=megacli

# Monitoring script URL
MONITORING_SCRIPT_URL="https://github.com/FastVPSEestiOu/........../monitoring.pl.tgz"

# Monitoring CRON file
CRON_FILE=/etc/cron.hourly/monitoringfastvps

# Installation path
INSTALL_TO=/usr/local/bin

# smartd config command to run repiodic tests (short/long)
SMARTD_COMMAND="# smartd.conf by FastVPS
\n# backup version of distrib file saved to /etc/smartd.conf.dist
\n
\n# Discover disks and run short tests every day at 02:00 and long tests every sunday at 03:00
\nDEVICESCAN -d removable -n standby -s (S/../.././02|L/../../7/03)"

ARCH=
DISTRIB=

# init.d script of smartd
SMARTD_INIT_DEBIAN=/etc/init.d/smartmontools
SMARTD_INIT_CENTOS=/etc/init.d/smartd

#
# Functions
#

check_n_install_debian_deps()
{
    echo "Installing Debian dependencies..."
    res=`apt-get update && apt-get install -y $DEBIAN_DEPS`
    if [ $? -ne 0 ]
    then
        echo "Something went wrong while installing dependencies. APT log:"
        echo $res
    fi
    echo "Finished installation of debian dependencies."
}

check_n_install_centos_deps()
{
    echo "Installing CentOS dependencies..."
    res=`yum install -y $CENTOS_DEPS`
    if [ $? -ne 0 ]
    then
        echo "Something went wrong while installing dependencies. YUM log:"
        echo $res
    fi
    echo "Finished installation of CentOS dependencies."  
}

# Проверяем наличие аппаратный RAID контроллеров и в случае наличия устанавливаем ПО для их мониторинга
check_n_install_diag_tools()
{
    lsi_raid=0
    adaptec_raid=0

    parted_diag=`parted -mls`

    echo "Checking hardware for LSI or Adaptec raids..."
    if [ -n "`echo $parted_diag | grep -i adaptec`" ]
    then
        echo "Found Adaptec raid"
        adaptec_raid=1
    fi
    if [ -n "`echo $parted_diag | grep -i lsi`" ]
    then
        echo "Found LSI raid"
        lsi_raid=1
    fi

    if [ $adaptec_raid -eq 0 -a $lsi_raid -eq 0 ]
    then
        echo "Hardware raid not found"
        return
    fi

    echo ""

    if [ $adaptec_raid -eq 1 ]
    then
        echo "Installing diag utilities for Adaptec raid..."
        install_diag_utils $ADAPTEC_UTILITY $ARCH
        echo "Finished installation of diag utilities for Apactec raid"
    fi

    echo ""

    if [ $lsi_raid -eq 1 ]
    then
        echo "Installing diag utilities for LSI MegaRaid..."
        install_diag_utils $LSI_UTILITY $ARCH
        echo "Finished installation of diag utilities for Apactec raid"
    fi
}

install_diag_utils()
{
    util=$1
    arch=$2

    if [ -z "$arch" ]
    then
        echo "Architecture is unknown - installing both and trying to determine the right one"
        wget -qN "$DIAG_UTILITIES_REPO""$util"32 -P $INSTALL_TO
        wget -qN "$DIAG_UTILITIES_REPO""$util"64 -P $INSTALL_TO

        wget -qN "$DIAG_UTILITIES_REPO""$util"32.sha1 -P $INSTALL_TO
        wget -qN "$DIAG_UTILITIES_REPO""$util"64.sha1 -P $INSTALL_TO

        chmod +x $INSTALL_TO/"$util"*

        res=`"$INSTALL_TO"/"$util"32 -v 2>&1`
        if [ $? -eq 0 ]
        then
            echo "We are on x86. Creating symlink..."
            ln -sf $INSTALL_TO/"$util"32 $INSTALL_TO/$util
        fi

        res=`"$INSTALL_TO"/"$util"64 -v 2>&1`
        if [ $? -eq 0 ]
        then
            echo "We are on x86_64. Creating symlink..."
            ln -sf $INSTALL_TO/"$util"64 $INSTALL_TO/$util
        fi
    else
        echo "Architecture is $arch - installing..."
        wget -qN "$DIAG_UTILITIES_REPO""$util"$arch -P $INSTALL_TO
        wget -qN "$DIAG_UTILITIES_REPO""$util"$arch.sha1 -P $INSTALL_TO
        
        chmod +x $INSTALL_TO/"$util"*
        ln -sf $INSTALL_TO/"$util"$ARCH $INSTALL_TO/$util
    fi

    cd $INSTALL_TO
    sha1sum --status -c *.sha1
        
    if [ $? -ne 0 ]
    then
        echo "Wrong SHA1 checksums! Removing installed utilities"
        rm -f $INSTALL_TO/$util*
        exit 1
    else
        echo "SHA1 checksums is OK"
        rm -f $INSTALL_TO/$util*.sha1
        echo "done."
    fi
}


install_monitoring_script()
{
    echo "Installing monitoring.pl into $INSTALL_TO..."
    wget -qN --no-check-certificate $MONITORING_SCRIPT_URL -P $INSTALL_TO
    wget -qN --no-check-certificate $MONITORING_SCRIPT_URL".sha1" -P $INSTALL_TO

    monitoring_script=`basename $MONITORING_SCRIPT_URL`

    cd $INSTALL_TO
    sha1sum --status -c $monitoring_script.sha1
        
    if [ $? -ne 0 ]
    then
        echo "Wrong SHA1 checksums! Removing monitoring script"
        rm -f $INSTALL_TO/$monitoring_script*
        exit 2
    else
        echo "SHA1 checksums is OK"
        rm -f $INSTALL_TO/$monitoring_script*.sha1
        echo "Extracting monitoring file"
        tar -C $INSTALL_TO -xzf $INSTALL_TO/$monitoring_script
        rm -f $INSTALL_TO/$monitoring_script
        monitoring_script=${monitoring_script%.tgz}
        echo -n "Installing CRON task... "
        echo "#!/bin/bash" > $CRON_FILE
        echo "perl $INSTALL_TO/$monitoring_script --cron" >> $CRON_FILE
        chmod +x $CRON_FILE
        echo "done."
    fi
}


start_smartd_tests()
{
    echo -n "Creating config for smartd... "

    # Backup /etc/smartd.conf
    if [ ! -e /etc/smartd.conf.dist ]
    then
        mv /etc/smartd.conf /etc/smartd.conf.dist
    fi

    echo $SMARTD_COMMAND > /etc/smartd.conf
    echo "done."

    # restart service
    case $DISTRIB in
        debian)
        $SMARTD_INIT_DEBIAN restart
        ;;

        centos)
        $SMARTD_INIT_CENTOS restart
        ;;
    esac

    if [ $? -ne 0 ]
    then
        echo "smartd failed to start. This may be caused by absence of disks SMART able to monitor."
        tail /var/log/daemon.log
    fi
}

#
# Start installation procedure
#

if [ -n "`echo \`uname -a\` | grep -e \"-686\|i686\"`" ]
then
    ARCH=32
fi
if [ -n "`echo \`uname -a\` | grep -e \"amd64\|x86_64\"`" ]
then
    ARCH=64
fi

if [ -n "`cat /etc/issue | grep -i \"Debian\"`" ]
then
    DISTRIB=debian
fi
if [ -n "`cat /etc/issue | grep -i \"CentOS\"`" ]
then
    DISTRIB=centos
fi

echo "We are on $DISTRIB $ARCH"


# Dependencies installation
case $DISTRIB in
    debian)
    check_n_install_debian_deps
    ;;

    centos)
    check_n_install_centos_deps
    ;;

    *)
    echo "Can't determine OS. Exiting..."
    exit 1
    ;;
esac

# Diagnostic tools installation
check_n_install_diag_tools

# Monitoring script installation
install_monitoring_script

# Periodic smartd tests
start_smartd_tests

