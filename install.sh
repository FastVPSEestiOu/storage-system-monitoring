#!/bin/bash
#
# That is installation script for storage system monitoring by FASTVPS Eesti OU
# If you have any questions about that system, please contact us:
# - https://github.com/FastVPSEestiOu/storage-system-monitoring
# - https://bill2fast.com (via ticket system)

set -u

# Disable interactive mode when configuring packages
export DEBIAN_FRONTEND='noninteractive'

# Setting text colors
TXT_GRN='\e[0;32m'
TXT_RED='\e[0;31m'
TXT_YLW='\e[0;33m'
TXT_RST='\e[0m'

# Set variable for pid
PID=$$

# Path for binaries
BIN_PATH='/usr/local/bin'

# Path of our repo, used for downloads
REPO_PATH='https://raw.githubusercontent.com/FastVPSEestiOu/storage-system-monitoring/master'

# Name of our script
SCRIPT_NAME='storage_system_fastvps_monitoring.pl'

# Path of our cron task
CRON_FILE='/etc/cron.d/storage-system-monitoring-fastvps'

# Static header for our cron task 
CRON_HEADER='# FastVPS disk monitoring tool
# https://github.com/FastVPSEestiOu/storage-system-monitoring
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'

# Suffix we add to moved smartd.conf
SMARTD_SUFFIX="fastvps_backup.${PID}"

# Static header for our smartd.conf
SMARTD_HEADER="# smartd.conf by FastVPS
# backup version of distrib file saved to /etc/smartd.conf.$SMARTD_SUFFIX
# Discover disks and run short tests every day at 02:00 and long tests every sunday at 03:00"

# Stable smartctl version (SVN revision)
SMARTCTL_STABLE_VERSION='6.6'
SMARTCTL_STABLE_REVISION='4318'

# Smartd config path
declare -A SMARTD_CONF_FILE
SMARTD_CONF_FILE["deb"]='/etc/smartd.conf'
SMARTD_CONF_FILE["deb_old"]='/etc/smartd.conf'
SMARTD_CONF_FILE["rpm_old"]='/etc/smartd.conf'
SMARTD_CONF_FILE["rpm_new"]='/etc/smartmontools/smartd.conf'

OS=''
ARCH=''
OS_TYPE=''
CRON_MINUTES=''
RAID_TYPE=''

# Dependencies
declare -A PKG_DEPS
PKG_DEPS["deb"]='wget libstdc++5 smartmontools liblwp-useragent-determined-perl libnet-https-any-perl libcrypt-ssleay-perl libjson-perl'
PKG_DEPS["deb_old"]='wget libstdc++5 smartmontools liblwp-useragent-determined-perl libnet-https-any-perl libcrypt-ssleay-perl libjson-perl'
PKG_DEPS["rpm_old"]='wget libstdc++ smartmontools perl-Crypt-SSLeay perl-libwww-perl perl-JSON'
PKG_DEPS["rpm_new"]='wget libstdc++ smartmontools perl-Crypt-SSLeay perl-libwww-perl perl-JSON perl-LWP-Protocol-https'

declare -A PKG_INSTALL
PKG_INSTALL["deb"]='apt-get update -qq && apt-get install -qq'
PKG_INSTALL["deb_old"]='apt-get update -o Acquire::Check-Valid-Until=false -qq && apt-get install -qq --allow-unauthenticated'
PKG_INSTALL["rpm_old"]='yum install -q -y'
PKG_INSTALL["rpm_new"]='yum install -q -y'

# List of packages which we do NOT want to update, in form of regex
declare -A PKG_UNSAFE
PKG_UNSAFE["deb"]='Inst libc6|Inst apache2|Inst php'
PKG_UNSAFE["deb_old"]='Inst libc6|Inst apache2|Inst php'
PKG_UNSAFE["rpm_old"]='^ glibc|^ httpd|^ php'
PKG_UNSAFE["rpm_new"]='^ glibc|^ httpd|^ php'

# And command for it
declare -A PKG_INSTALL_TEST
PKG_INSTALL_TEST["deb"]='apt-get update && apt-get install -s'
PKG_INSTALL_TEST["deb_old"]='apt-get update -o Acquire::Check-Valid-Until=false -qq && apt-get install -s'
PKG_INSTALL_TEST["rpm_old"]='yum install --assumeno'
PKG_INSTALL_TEST["rpm_new"]='yum install --assumeno'


# Some fancy echoing
_echo_OK()
{
    echo -e " -> ${TXT_GRN}OK${TXT_RST}"
}

_echo_FAIL()
{
    echo -e " -> ${TXT_RED}FAIL${TXT_RST}"
}

_echo_tabbed()
{
    local message=$1
    
    echo -e " -> $message"
}

_echo_result()
{
    local result=$*
    if [[ "$result" -eq 0 ]]; then
        _echo_OK
    else
        _echo_FAIL
        exit 1
    fi
}

# Detect OS
_detect_os()
{
    local issue_file='/etc/issue'
    local os_release_file='/etc/os-release'
    local redhat_release_file='/etc/redhat-release'
    local os=''
    local name=''
    local version=''
    # First of all, trying os-relese file
    if [ -f $os_release_file ]; then
        name=$(grep '^NAME=' $os_release_file | awk -F'[" ]' '{print $2}')
        version=$(grep '^VERSION_ID=' $os_release_file | awk -F'[". ]' '{print $2}')
        os="${name}${version}"
    else
        # If not, trying redhat-release file (mainly because of bitrix-env)
        if [ -f $redhat_release_file ]; then
            os=$(head -1 /etc/redhat-release | sed -re 's/([A-Za-z]+)[^0-9]*([0-9]+).*$/\1\2/')
        else
            # Else, trying issue file
            if [ -f $issue_file ]; then
                os=$(head -1 $issue_file | sed -re 's/([A-Za-z]+)[^0-9]*([0-9]+).*$/\1\2/')
            else
                # If none of that files worked, exit
                echo -e "${TXT_RED}Cannot detect OS. Exiting now"'!'"${TXT_RST}"
                exit 1
            fi
        fi
    fi
    OS=$os
}

# Detect architecture
_detect_arch()
{
    local arch=''
    local uname=''

    uname=$(uname -m)
    if [[ $uname == 'x86_64' ]]; then
        arch=64
    else
        arch=32
    fi

    ARCH=$arch
}

# Select OS type based on OS
_select_os_type()
{
    local os=$1
    local os_type=''

    case $os in
        Debian[6-7] )
            os_type='deb_old'
        ;;
        Debian[8-9]|Debian10|Ubuntu* )
            os_type='deb'
        ;;
        CentOS6 )
            os_type='rpm_old'
        ;;
        CentOS7 )
            os_type='rpm_new'
        ;;
        * )
            echo "We can do nothing on $os. Exiting."
            _echo_FAIL
            exit 1
        ;;
    esac

    OS_TYPE=$os_type
}

# Check and install needed software
_install_deps()
{
    local os_type=$1
    local pkgs_to_install=()
    local unsafe_pkgs=()

    # Check if we have packages needed
    local pkg=''
    local result=''

    for pkg in ${PKG_DEPS[$os_type]}; do
        if ! _check_pkg "$os_type" "$pkg" ; then
            pkgs_to_install+=("$pkg")
        fi
    done

    if [[ ${#pkgs_to_install[@]} -eq 0 ]]; then
        _echo_tabbed "We have everything we need."
        return 0
    else
        _echo_tabbed "Installing: ${TXT_YLW}${pkgs_to_install[*]}${TXT_RST} ..."

        # Check if we are going to break something
	    mapfile -t < <( eval "${PKG_INSTALL_TEST[$os_type]}" "${pkgs_to_install[@]}" ) result
        for (( i=0; i<${#result[@]}; i++ )); do
            if [[ "${result[i]}" =~ ${PKG_UNSAFE[$os_type]} ]]; then
		        unsafe_pkgs+=("${result[i]}")
            fi
        done

        if [[ ${#unsafe_pkgs[@]} -gt 0 ]]; then
            echo "We are going to update something we do not want to:"
            for (( i=0; i<${#unsafe_pkgs[@]}; i++ )); do
                echo "${unsafe_pkgs[i]}";
            done
            echo -e "\nYou can check it yourself with command:\n${PKG_INSTALL_TEST[$os_type]}" "${pkgs_to_install[@]}"
            return 1
        fi

        # Catch error in variable
        if IFS=$'\n' result=( $(eval "${PKG_INSTALL[$os_type]}" "${pkgs_to_install[@]}" 2>&1) ); then
            return 0

        # And output it, if we had nonzero exit code
        else
            echo
            for (( i=0; i<${#result[@]}; i++ )); do
                echo "${result[i]}";
            done
            return 1
        fi
    fi
}

# Check package
_check_pkg()
{
    local os_type=$1
    local pkg=$2

    case $os_type in
        deb* )
            if dpkg-query -W -f='\${Status}' "$pkg" 2>&1 | grep -qE '^(\$install ok installed)+$'; then
                return 0
            else
                return 1
            fi
        ;;
        rpm* )
            if rpm --quiet -q "$pkg"; then
                return 0
            else
                return 1
            fi
        ;;
        * )
            _echo_tabbed "We can do nothing on $os_type. Exiting."
            exit 1
        ;;
    esac
}

# Function to download with check
_dl_and_check()
{
    local remote_path=$1
    local local_path=$2
    local os=$OS
    local result=()
    local wget_param=()

    # Adding --no-check-certificate on old OS
    case $os in
        Debian6 )
            wget_param=(--no-check-certificate --verbose)
        ;;
        * )
            wget_param=(--verbose)
        ;;
    esac

    # Clean target path before download
    if [[ -x "$local_path" ]]; then
        rm -f "$local_path";
    fi

    # Catch error in variable
    if IFS=$'\n' result=( $(wget "${wget_param[@]}" "$remote_path" --output-document="$local_path" 2>&1) ); then
        return 0

    # And output it, if we had nonzero exit code
    else
        echo
        for (( i=0; i<${#result[@]}; i++ )); do
            echo "${result[i]}";
        done
        return 1
    fi
}

# Install RAID tools if needed
_install_raid_tools()
{
    local bin_path=$1
    local repo_path=$2
    local arch=$3

    local util_path=''
    local dl_path=''
    local raid_type=''

    # Detect RAID
    local sys_block_check=''
    sys_block_check=$(cat /sys/block/*/device/vendor /sys/block/*/device/model 2>/dev/null | grep -oEm1 'Adaptec|LSI|PERC|ASR8405')

    # Select utility to install
    case $sys_block_check in
        # arcconf for Adaptec
        ASR8405 )
            raid_type='adaptec'
            util_path="${bin_path}/arcconf"

            _echo_tabbed "Found RAID: ${TXT_YLW}${sys_block_check}${TXT_RST}"

            dl_path="${repo_path}/raid_monitoring_tools/arcconf_new"
        ;;
        Adaptec )
            raid_type='adaptec'
            util_path="${bin_path}/arcconf"

            local adaptec_version=''
            adaptec_version=$(lspci -m | awk -F\"  '/Adaptec/ {print $(NF-1)}')

            _echo_tabbed "Found RAID: ${TXT_YLW}${sys_block_check} ${adaptec_version}${TXT_RST}"

            # Select arcconf version dpending on controller version
            case $adaptec_version in
                # Old Adaptec controller (2xxx-5xxx) - need to use old arcconf
                *[2-5][0-9][0-9][0-9] )
                    dl_path="${repo_path}/raid_monitoring_tools/arcconf${arch}_old"
                ;;
                # Newer Adaptec controller (6xxx-8xxx) - new version of arcconf
                *[6-8][0-9][0-9][0-9] )
                    dl_path="${repo_path}/raid_monitoring_tools/arcconf_new"
                ;;
                # Otherwise exit
                * )
                    echo "We don't know, what arcconf version is needed."
                    return 1
                ;;
            esac

        ;;

        # megacli for LSI (PERC is LSI controller on DELL)
        LSI|PERC )
            raid_type='lsi'
            _echo_tabbed "Found RAID: ${TXT_YLW}${sys_block_check}${TXT_RST}"
            util_path="${bin_path}/megacli"
            dl_path="${repo_path}/raid_monitoring_tools/megacli${arch}"
        ;;

        # Nothing if none RAID found
        '' )
            raid_type='soft'
            _echo_tabbed "No HW RAID."
        ;;

        # Fallback that should never be reached
        * )
            _echo_tabbed "Unknown RAID type: ${TXT_YLW}${sys_block_check}${TXT_RST}. Exiting."
            return 1
        ;;
    esac


    # Set raid type for smartd
    RAID_TYPE="$raid_type"

    # Download selected utility
    case $raid_type in
        soft )
            return 0
        ;;
        adaptec|lsi )
            if _dl_and_check "$dl_path" "$util_path"; then
                chmod +x "$util_path"
                _echo_tabbed "Installed ${TXT_YLW}${util_path}${TXT_RST}"
                RAID_TYPE="$raid_type"
                return 0
            else
                return 1
            fi
        ;;
        # Fallback that should never be reached
        * )
            _echo_tabbed "Unknown RAID type: ${TXT_YLW}${raid_type}${TXT_RST}. Exiting."
            return 1
        ;;
    esac
}

# Install new smartctl binary, if we have too old one
_install_smartctl()
{
    local bin_path=$1
    local repo_path=$2
    local arch=$3
    local smartctl_stable_version=$4
    local smartctl_stable_revision=$5

    local smartctl_current_version=''
    local smartctl_current_revision=''
    local version_comp_result=''

    local util_path="${bin_path}/smartctl"
    local dl_path="${repo_path}/raid_monitoring_tools/smartctl${arch}"

    smartctl_current_version=$(smartctl --version | awk '/^smartmontools release/ {print $3}')
    smartctl_current_revision=$(smartctl --version | awk '/^smartmontools SVN rev/ {print $4}')


    # If current version is lower then stable, download a new one

    # We'll get exit code 2 if current version is lower than stable version
    _version_copmare "$smartctl_current_version" "$smartctl_stable_version"
    version_comp_result=$?
    
    if [[ "$version_comp_result" -eq "2" ]] || [[ "$smartctl_current_revision" -lt "$smartctl_stable_revision" ]]; then
        if _dl_and_check "$dl_path" "$util_path"; then
            chmod +x "$util_path"
            _echo_tabbed "Installed ${TXT_YLW}${util_path}${TXT_RST}"
            return 0
        else
            return 1
        fi
    else
        _echo_tabbed "We have smartctl version ${TXT_YLW}${smartctl_current_version}${TXT_RST} (rev. ${TXT_YLW}${smartctl_current_revision}${TXT_RST}) here."
        return 0
    fi
}

# Function to compare dotted versions
_version_copmare()
{
    # Compares two versions
    # Returns:
    #   0 -> first = second
    #   1 -> first > second
    #   2 -> first < second

    local first_string=$1
    local second_string=$2

    local first_array=()
    local second_array=()

    # Split versions into arrays
    IFS='.' read -ra first_array <<< "$first_string"
    IFS='.' read -ra second_array <<< "$second_string"

    # Fill empty fields in first array with zeros
    for ((i=${#first_array[@]}; i<${#second_array[@]}; i++)); do
        first_array[$i]=0
    done

    for ((i=0; i<${#first_array[@]}; i++)); do
        # Fill empty fields in second array with zeros
        if [[ -z ${second_array[$i]} ]]; then
            second_array[$i]=0
        fi

        # "10#" forces decimal numbers interpretation
        if ((10#${first_array[$i]} > 10#${second_array[$i]})); then
            return 1
        fi
        if ((10#${first_array[$i]} < 10#${second_array[$i]})); then
            return 2
        fi
    done

    return 0
}

# Install monitoring script
_install_script()
{
    local bin_path=$1
    local repo_path=$2
    local script_name=$3
    local cron_file=$4
    local cron_minutes=$5
    local cron_header=$6

    local script_local="${bin_path}/${script_name}"
    local script_remote="${repo_path}/${script_name}"

    if _dl_and_check "$script_remote" "$script_local"; then
        chmod +x -- "$script_local"
        _echo_tabbed "Installed ${TXT_YLW}${script_local}${TXT_RST}"
    else
        return 1
    fi

    if _set_cron "$cron_file" "$script_local" "$cron_minutes" "$cron_header"; then
        _echo_tabbed "Installed ${TXT_YLW}${cron_file}${TXT_RST}"
        return 0
    else
        return 1
    fi
}


# Add cron task for script
_set_cron()
{
    local cron_file=$1
    local script_local=$2
    local cron_minutes=$3
    local cron_header=$4

    local cron_text=''

    local cron_line="$cron_minutes * * * * root $script_local --cron >/dev/null 2>&1"

    read -r -d '' cron_text <<EOF
$cron_header
$cron_line
EOF

    echo "$cron_text" > "$cron_file"
    chmod 644 -- "$cron_file"
}


# Configure SMARTD
_set_smartd()
{
    local raid_type=$1
    local smartd_header=$2
    local os_type=$3
    local smartd_suffix=$4

    local smartd_conf_file=${SMARTD_CONF_FILE[$os_type]}
    local smartd_conf_backup=${smartd_conf_file}.${smartd_suffix}

    local smartd_conf=''
    local drive=''
    local drives=()
    local lines=()

    # Select smartd.conf for our RAID type
    case $raid_type in
        soft )
            lines+=('DEVICESCAN -d removable -n standby -s (S/../.././02|L/../../7/03)')
        ;;
        adaptec )
            # Try to load sg module if it is not loaded for some reason
            if [[ ! -c /dev/sg0 ]]; then
                # Catch error in variable
                if IFS=$'\n' result=( $(modprobe sg 2>&1) ); then
                    _echo_tabbed "Loaded ${TXT_YLW}sg${TXT_RST} module."

                # And output it, if we had nonzero exit code
                else
                    echo
                    for (( i=0; i<${#result[@]}; i++ )); do
                        echo "${result[i]}";
                    done
                    _echo_tabbed "Failed to load ${TXT_YLW}sg${TXT_RST} module. We need it to work with Adaptec controller."
                    return 1
                fi
            fi

            # Get drives to check
            local sgx=''
            for sgx in /dev/sg?; do
                if smartctl -q silent -i "$sgx"; then
                    drives+=("$sgx")
                fi
            done

            if [[ ${#drives[@]} -eq 0 ]]; then
                _echo_tabbed "Failed to get ${TXT_YLW}/dev/sg?${TXT_RST} drives for Adaptec controller. We have tried ${TXT_YLW}modprobe sg${TXT_RST} but without success. Check it and proceed manually."
                return 1
            fi

            # Form smartd rules
            for drive in "${drives[@]}"; do
                lines+=("$drive -n standby -s (S/../.././02|L/../../7/03)")
            done
        ;;
        lsi )
            # Get drives to check
            mapfile -t < <( megacli -pdlist -a0| awk '/Device Id/ {print $NF}' ) drives

            if [[ ${#drives[@]} -eq 0 ]]; then
                _echo_tabbed "Failed to get drives for LSI controller. Try to call ${TXT_YLW}megacli -pdlist -a0${TXT_RST} and check the output."
                return 1
            fi

            # Form smartd rules
            for drive in "${drives[@]}"; do
                lines+=("/dev/sda -d megaraid,${drive} -n standby -s (S/../.././02|L/../../7/03)")
            done
        ;;
        * )
            _echo_tabbed "Unknown RAID type: ${TXT_YLW}${raid_type}${TXT_RST}. Exiting."
            return 1
        ;;
    esac

    IFS=$'\n' read -r -d '' smartd_conf <<EOF
$smartd_header
${lines[*]}
EOF

    if mv "$smartd_conf_file" "$smartd_conf_backup"; then 
        _echo_tabbed "Moved ${TXT_YLW}${smartd_conf_file}${TXT_RST} to ${TXT_YLW}${smartd_conf_backup}${TXT_RST}"
    else
        return 1
    fi
    
    if echo "$smartd_conf" > "$smartd_conf_file"; then
        _echo_tabbed "Filled ${TXT_YLW}${smartd_conf_file}${TXT_RST}"
        return 0
    else
        return 1
    fi
}


# Restart smartd to enable config
_restart_smartd()
{
    local os=$1
    local restart_cmd=''

    case $os in
        # systemctl on new OS
        Debian[8-9]|Debian10|CentOS7|Ubuntu1[678] )
            restart_cmd='systemctl restart smartd.service'
        ;;
        # /etc/init.d/ on sysv|upstart OS
        CentOS6 )
            restart_cmd='/etc/init.d/smartd restart'
        ## On Debian 7 we should always have /etc/init.d/smartmontools while /etc/init.d/smartd can be removed when using backports
        ;;
        Debian[6-7]|Ubuntu12|Ubuntu14 )
            # Hack for Debain 6-7
            sed -i -e 's/^#start_smartd/start_smartd/' /etc/default/smartmontools
            restart_cmd='/etc/init.d/smartmontools restart'
        ;;
        * )
            _echo_tabbed "Don't know how to restart smartd on that OS: ${TXT_YLW}${os}${TXT_RST}"
            return 1
        ;;
    esac

    # Catch error in variable
    if IFS=$'\n' result=( $(eval "$restart_cmd" 2>&1) ); then
        _echo_tabbed "Smartd started."
        return 0

    # And output it, if we had nonzero exit code
    else
        echo
        for (( i=0; i<${#result[@]}; i++ )); do
            echo "${result[i]}";
        done
        return 1
    fi

}

# Enable autostart of smartd
_enable_smartd_autostart()
{
    local os=$1
    local enable_cmd=''

    case $os in
        # systemctl on new OS
        Debian[8-9]|Debian10|CentOS7|Ubuntu1[678] )
            enable_cmd='systemctl enable smartd.service'
        ;;
        # chkconfig on CentOS 6
        CentOS6 )
            enable_cmd='chkconfig smartd on'
        ;;
        # update-rc.d on sysv/upstart deb-based OS
        Debian[6-7]|Ubuntu12|Ubuntu14 )
            enable_cmd='update-rc.d smartmontools defaults'
        ;;
        * )
            _echo_tabbed "Don't know how to enable smartd autostart on that OS: ${TXT_YLW}${os}${TXT_RST}"
            return 1
        ;;
    esac

    # Catch error in variable
    if IFS=$'\n' result=( $(eval "$enable_cmd" 2>&1) ); then
        _echo_tabbed "Smartd autostart enabled."
        return 0

    # And output it, if we had nonzero exit code
    else
        echo
        for (( i=0; i<${#result[@]}; i++ )); do
            echo "${result[i]}";
        done
        return 1
    fi
}

# Run monitoring script
_run_script()
{
    local bin_path=$1
    local script_name=$2
    local mode=$3

    if "${bin_path}/${script_name}" --"$mode"; then
        return 0
    else
        _echo_tabbed "Cannot run script in --$mode mode"
        return 1
    fi
}


# Actual installation

# Detect OS and arch
_detect_os
_detect_arch
echo -e "OS: ${TXT_YLW}${OS} x${ARCH}${TXT_RST}"

# Set OS type
_select_os_type "$OS"

# We should randomize run time to prevent ddos attacks to our gates
# Limit random numbers by 59 minutes
((CRON_MINUTES = RANDOM % 59))

echo -e "Checking dependencies..."
_install_deps "$OS_TYPE"
_echo_result $?

echo -e "Checking for hardware RAID..."
_install_raid_tools "$BIN_PATH" "$REPO_PATH" "$ARCH"
_echo_result $?

echo -e "Installing new smartctl if needed..."
_install_smartctl "$BIN_PATH" "$REPO_PATH" "$ARCH" "$SMARTCTL_STABLE_VERSION" "$SMARTCTL_STABLE_REVISION"
_echo_result $?

echo -e "Installing monitoring script..."
_install_script "$BIN_PATH" "$REPO_PATH" "$SCRIPT_NAME" "$CRON_FILE" "$CRON_MINUTES" "$CRON_HEADER"
_echo_result $?

echo -e "Setting smartd..."
_set_smartd "$RAID_TYPE" "$SMARTD_HEADER" "$OS_TYPE" "$SMARTD_SUFFIX"
_echo_result $?

echo -e "Starting smartd..."
_restart_smartd "$OS"
_echo_result $?

echo -e "Enabling smartd autostart..."
_enable_smartd_autostart "$OS"
_echo_result $?

echo -e "Sending data to FASTVPS monitoring server..."
_run_script "$BIN_PATH" "$SCRIPT_NAME" "cron"
_echo_result $?

echo -e "Current storage status:"
_run_script "$BIN_PATH" "$SCRIPT_NAME" "detect"
echo
