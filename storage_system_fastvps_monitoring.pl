#!/usr/bin/perl
=description

Authors:
Alexander Kaidalov <kaidalov@fastvps.ru>
Pavel Odintsov <odintsov@fastvps.ee>
License: GPLv2

=cut

# TODO
# Добавить выгрузку информации по Физическим Дискам: 
# megacli -PDList -Aall
# arcconf getconfig 1 pd
# Перенести исключение ploop на этап идентификации дисковых устройств
# Добавить явно User Agent как у мониторинга, чтобы в случае чего их не лочило
# В случае Adaptec номер контроллера зафикисрован как 1, поддерживается только один контроллер
# В случае Adaptec поддерживается только один логический раздел!!!
# Отказаться от прямого указания major, анализировать файл /proc/devices и извлекать номера из него, так как они вовсе не фиксированы

use strict;
use warnings;

use LWP::UserAgent;
use JSON;
use Data::Dumper;

# Конфигурация
my $VERSION = "1.1";

my $os_architecture = "";

# Detect Linux architecture
if (-e '/lib64') {
    $os_architecture = '64';
} else {
    $os_architecture = '32';
}

# diagnostic utilities
my $ADAPTEC_UTILITY = '/usr/local/bin/arcconf';


my $LSI_UTILITY = '';

if ($os_architecture eq '64') {
    $LSI_UTILITY = '/opt/MegaRAID/MegaCli/MegaCli64';
} else {
    $LSI_UTILITY = '/opt/MegaRAID/MegaCli/MegaCli';
}

# API
my $API_URL = 'https://fastcheck24.com/api/server-state/storage';

# Centos && Debian uses same path
my $parted = "LANG=POSIX /sbin/parted";
# Centos && Debian uses same path
my $mdadm = "/sbin/mdadm";
my $sysfs_block_path = '/sys/block';

# Список устройств, которые мы игнорируем из рассмотрения
my @major_blacklist = (
    1,   # это ram устройства
    7,   # это loop устройства
    43,  # nbd http://en.wikipedia.org/wiki/Network_block_device
    182, # это openvz ploop диск
    253, # device-mapper, но на Citrix XenServer это tapdev
    252, # device-mapper на Citrix XenServer
);

my $user_id = $<;
if ( $user_id != 0 ) {
    die "This program can only be run under root.\n";
}

# Обанаруживаем все устройства хранения
# Также у нас есть старая версия, работающая исключительно на базе parted: find_disks()
my @disks = find_disks_without_parted();

# Проверим, все ли у нас тулзы для диагностики установлены
check_disk_utilities(@disks);

# Получаем информацию обо всех дисках
@disks = diag_disks(@disks);

my $only_detect_drives = 0;

# Запуск из крона
my $cron_run = 0;

if (scalar @ARGV > 0 and $ARGV[0] eq '--detect') {
    $only_detect_drives = 1;
}

if (scalar @ARGV > 0 and $ARGV[0] eq '--cron') {
    $cron_run = 1;
}

my $adaptec_needed = 0;
my $lsi_needed = 0;
my $mdadm_needed = 0;

if ($only_detect_drives) {
    for my $storage (@disks) {
        # Для обычных дисков понятия статуса нету
        if ($storage->{'type'} eq 'hard_disk') {
            print "Device $storage->{device_name} with type: $storage->{type} model: $storage->{model} detected\n";
        } else {
            # а вот для RAID оно вполне определено
            print "Device $storage->{device_name} with type: $storage->{type} model: $storage->{model} in state: $storage->{status} detected\n";
        }

    }
   
    if (scalar @disks == 0) {
        print "I can't find any disk devices. I suppose bug on this platform :(";
    }
 
    exit (0);
}

if ($cron_run) {
    if(!send_disks_results(@disks)) {
        print "Failed to send storage monitoring data to FastVPS";
        exit(1);
    }   
}

if (!$only_detect_drives && !$cron_run) {
    print "This information was gathered and will be sent to FastVPS:\n";
    print "Disks found: " . (scalar @disks) . "\n\n";

    for my $storage (@disks) {
        print $storage->{device_name} . " is " . $storage->{'type'} . " Diagnostic data:\n";
        print $storage->{'diag'} . "\n\n";
    }       
}



#
# Functions
#

# Функция обнаружения всех дисковых устройств в системе
sub find_disks {
    # here we'll save disk => ( info, ... )
    my @disks = ();
    
    # get list of disk devices with parted 
    my @parted_output = `$parted -lms`;

    if ($? != 0) {
        die "Can't get parted output. Not installed?!";
    }
 
    for my $line (@parted_output) {
        chomp $line;
        # skip empty line
        next if $line =~ /^\s/;
        next unless $line =~ m#^/dev#;   

        # После очистки нам приходят лишь строки вида:
        # /dev/sda:3597GB:scsi:512:512:gpt:DELL PERC H710P;
        # /dev/sda:599GB:scsi:512:512:msdos:Adaptec Device 0;
        # /dev/md0:4302MB:md:512:512:loop:Linux Software RAID Array;
        # /dev/sdc:1500GB:scsi:512:512:msdos:ATA ST31500341AS;

        # Отрезаем точку с запятой в конце
        $line =~ s/;$//; 
            
        # get fields
        my @fields = split ':', $line;
        my $device_name = $fields[0];        
        my $device_size = $fields[1]; 
        my $model = $fields[6];

        # Это виртуальные устройства в OpenVZ, их не нужно анализировать
        if ($device_name =~ m#/dev/ploop\d+#) {
            next;
        }

        # detect type (raid or disk)
        my $type = 'disk';
        my $is_raid = '';                 
   
        # adaptec
        if($model =~ m/adaptec/i) {
            $model = 'adaptec';
            $is_raid = 1;
        }
            
        # Linux MD raid (Soft RAID)
        if ($device_name =~ m/\/md\d+/) {
            $model = 'md';
            $is_raid = 1;
        }

        # LSI (3ware) / DELL PERC (LSI chips also)
        if ($model =~ m/lsi/i or $model =~ m/PERC/i) {
            $model = 'lsi';
            $is_raid = 1;
        }
        
        # add to list
        my $tmp_disk = { 
            "device_name" => $device_name,
            "size"        => $device_size,
            "model"       => $model,
            "type"        => ($is_raid ? 'raid' : 'hard_disk'),
        };  

        push @disks, $tmp_disk;
    }

    return @disks;
}

# Убираем все пробельные символы в конце строки
sub rtrim {
    my $string = shift;

    $string =~ s/\s+$//g;

    return $string;
}

# Получаем путь до устройства по его имени
sub get_device_path {
    my $name = shift;

    return "/dev/$name";
}

# Получаем major идентификатор блочного устройства в Linux
sub get_major {
    my $device = shift;

    my $device_path = get_device_path($device);
    my $major = '';


    if (-e $device_path) {
        my $rdev = (stat $device_path)[6];

        # Это платформо зависимый код!
        # https://github.com/quattor/LC/blob/master/src/main/perl/Stat.pm
        $major = ($rdev >> 8) & 0xFF;
        
        return $major;
    } else {
        # Для dm устройств и /dev/t у нас нету псевдо-устройст в /dev, поэтому мы можем попробовать получить major из sysfs
        my $dev_info = file_get_contents("/sys/block/$device/dev");

        if ($dev_info =~ /(\d+):\d+/) { 
            $major = $1;
        
            return $major;
        } else {
            return '';
        }
    }
}

sub in_array {
    my ($elem, @array) = @_; 

    return scalar grep { $elem eq $_ } @array;  
}

sub file_get_contents {
    my $path = shift;

    open my $fl, "<", $path or die "Can't open file";
    my $data = join '', <$fl>;
    chomp $data;

    close $fl;
    return $data;
}

# Пробуем получить производителя устройства
sub get_device_vendor {
    my $device_name = shift;

    my $vendor_path = "$sysfs_block_path/$device_name/device/vendor";

    if (-e $vendor_path) {
        my $vendor_raw = file_get_contents($vendor_path);
        $vendor_raw = lc($vendor_raw);

        # remove trailing spaces
        $vendor_raw =~ s/\s+$//g;

        return $vendor_raw;
    } else {
        return "unknown";
    }
}

# Получаем модуль устройства
sub get_device_model {
    my $device_name = shift;

    my $model_path = "$sysfs_block_path/$device_name/device/model";

    if (-e $model_path) {
        my $model_raw = file_get_contents($model_path);
        $model_raw = lc($model_raw);

        # remove trailing spaces
        $model_raw =~ s/\s+$//g;

        return $model_raw;
    } else {
        return "unknown";
    }    
}

sub get_device_size {
    my $device_name = shift;
   
    my $size_path = "$sysfs_block_path/$device_name/size";

    if (-e $size_path) {
        my $size_in_blocks = file_get_contents($size_path);

        # Переводим в байты
        my $size_in_bytes = $size_in_blocks << 9;
        my $size_in_gbytes = int($size_in_bytes/1024**3);

        return "${size_in_gbytes}GB"; 
    } else {
        return "unknown";
    }
}

# Обнаруживаем дисковые устройства без использования внешнего parted
# Используются идеи из кода util-linux-2.24, lsblk
sub find_disks_without_parted {
    opendir my $block_devices, $sysfs_block_path or die "Can't open path $sysfs_block_path";

    my @disks = ();
    while (my $block_device = readdir($block_devices)) {
        # skip . and ..
        if ($block_device =~ m/^\.+$/) {
            next;
        }

        # эта проверка в общем-то уже не имеет смысла, так как DM устройства отсекаются по major, но как
        # показал опыт Citrix XenServer особо одаренные разработчики иногда меняют стандартные major номера
        # skip device mapper fake devices
        if ($block_device =~ m/^dm-\d+/) {
            next;
        }

        # Также исключаем из рассмотрения служебные не физические устройства по номеру major
        my $major = get_major($block_device);
    
        if (in_array($major, @major_blacklist)) {
            next;
        }

        my $vendor = get_device_vendor($block_device);
        my $model = get_device_model($block_device);

        # Код ниже ожидает вот в таком виде
        $model = "$vendor $model";
	
	# Исключаем из рассмотрения виртуальные устройства от idrac
	if ( $model =~ m/^idrac\s+virtual\s+\w+$/ ) {
		next;
	}
        
        my $device_size = get_device_size($block_device);

        my $device_name = get_device_path($block_device);

        # detect type (raid or disk)
        my $type = 'disk';
        my $is_raid = '';    
        my $raid_level = '';   

        # adaptec
        if($model =~ m/adaptec/i) {
            $model = 'adaptec';
            $is_raid = 1;
        }   
    
        # Linux MD raid (Soft RAID)
        if ($device_name =~ m/\/md\d+/) {
            $model = 'md';
            $is_raid = 1;

            $raid_level = file_get_contents("/sys/block/$block_device/md/level");
        }   

        # LSI (3ware) / DELL PERC (LSI chips also)
        if ($model =~ m/lsi/i or $model =~ m/PERC/i) {
            $model = 'lsi';
            $is_raid = 1;
        }   
    
        # add to list
        my $tmp_disk = { 
            "device_name" => $device_name,
            "size"        => $device_size,
            "model"       => $model,
            "type"        => ($is_raid ? 'raid' : 'hard_disk'),
        };  

        push @disks, $tmp_disk;
    }

    return @disks;
}

# Check diagnostic utilities availability
sub check_disk_utilities {
    my (@disks) = @_;

    #my $adaptec_needed = 0;
    #my $lsi_needed = 0;
    #my $mdadm_needed = 0;

    for my $storage (@disks) {
        # Adaptec
        if ($storage->{model} eq "adaptec") {
            $adaptec_needed = 1;
        }
            
        # LSI
        if ($storage->{model} eq "lsi") {
            $lsi_needed = 1;
        }

        if ($storage->{model} eq "md") {
            $mdadm_needed = 1;
        }
    }

    if ($adaptec_needed) {
        die "Adaptec utility not found. Please, install Adaptech raid management utility into " . $ADAPTEC_UTILITY . "\n" unless -e $ADAPTEC_UTILITY;
    }

    if ($lsi_needed) {
        die "Megacli not found. Please, install LSI MegaCli raid management utility into " . $LSI_UTILITY . " (symlink if needed)\n" unless -e $LSI_UTILITY
    }

    if ($mdadm_needed) {
        die "mdadm not found. Please, install mdadm" unless -e $mdadm;
    }
}

# Извлекает из единого блока данных состояние логического устройства Adaptec
sub extract_adaptec_status {
    my $data = shift;

    my @data_as_array = split "\n", $data;
    my $status = 'unknown';

    for my $line (@data_as_array) {
        chomp $line;
        if ($line =~ /^\s+Status of logical device\s+:\s+(\w+)$/i) {
            $status = lc(rtrim($1));
        }
    }


    return $status;
}

sub extract_lsi_status {
    my $data = shift;

    my @data_as_array = split "\n", $data;
    my $status = 'unknown';

    for my $line (@data_as_array) {
        chomp $line;
        if ($line =~ /^State\s+:\s+(\w+)/i) {
            $status = lc(rtrim($1));
        }
    }

    return $status;
}

# Извлекат из единого блока выдачи состояние массива
sub extract_mdadm_raid_status {
    my $data = shift;

    my @data_as_array = split "\n", $data;
    my $status = 'unknown';

    for my $line (@data_as_array) {
        chomp $line;
        if ($line =~ /^\s+State\s+:\s+(.+)$/) {
            $status = lc(rtrim($1));
        }
    }

    return $status;
}

# Run disgnostic utility for each disk
sub diag_disks {
    my (@disks) = @_;
    my @result_disks = ();
    my @lsi_ld_all;
    my @adaptec_ld_all;

    if ( $lsi_needed ) {
        my $lsi_ld_all_res = `$LSI_UTILITY  -LDInfo -Lall -Aall 2>&1`; 
        $lsi_ld_all_res =~ s/^\n\n//;
        @lsi_ld_all = split /\n\n\n/, $lsi_ld_all_res;
    }

    if ( $adaptec_needed ) {
        my $adaptec_ld_all_res = `$ADAPTEC_UTILITY getconfig 1 ld 2>&1`;
        @adaptec_ld_all = split /\n\n/, $adaptec_ld_all_res;
    }   


    foreach my $storage (sort { $a->{'device_name'} cmp $b->{'device_name'} } @disks) {
        my $device_name = $storage->{device_name};
        my $type = $storage->{type};
        my $model = $storage->{model};

        my $res = '';
        my $cmd = '';
        # где можем, выцепляем состояние массива, актуально в первую очередь для RAID массивов
        my $storage_status = 'undefined';
 
        if ($type eq 'raid') {
            # adaptec
            if ($model eq "adaptec") {
                if (scalar @adaptec_ld_all > 0 ) {
                    $res = shift @adaptec_ld_all;
                }
                else {
                    $res = "";
                }

                $storage_status = extract_adaptec_status($res);
            }   

            # md
            if ($model eq "md") {    
                $cmd = "$mdadm --detail $device_name";

                $res = `$cmd 2>&1`;

                # попытаемся извлечь состояние массива 
                $storage_status = extract_mdadm_raid_status($res);
            }

            # lsi (3ware)
            if($model eq "lsi") {
                if (scalar @lsi_ld_all > 0) {
                    $res = shift @lsi_ld_all;
                }
                else {
                    $res = "";
                }
                $storage_status = extract_lsi_status($res);
            }
        } elsif ($type eq 'hard_disk') {
            $cmd = "/usr/sbin/smartctl --all $device_name";
            $res = `$cmd 2>&1`;
        } else {
            warn "Unexpected type";
            $cmd = '';
        }

        $storage->{'status'} = $storage_status;
        $storage->{'diag'} = $res;

        push @result_disks, $storage;
    }

    return @result_disks;
}

# Send disks diag results
sub send_disks_results {
    my (@disks) = @_;

    my $request_data = [
        'storage_devices' => \@disks,
        'version'         => $VERSION,
    ];


    # get result
    my $ua = LWP::UserAgent->new();
    #$ua->agent("FastVPS disk monitoring version $VERSION");
    
    # Allow redirects for POST requests
    push @{ $ua->requests_redirectable }, 'POST';    

    my $res = $ua->post($API_URL, Content => encode_json($request_data) );
    
    if ($res->is_success) {
        #print "Data sent successfully\n";
        exit 0;
    } else {
        warn "Can't sent data to collector: " . $res->status_line  .  "\n";
        exit 1;
    }
}

