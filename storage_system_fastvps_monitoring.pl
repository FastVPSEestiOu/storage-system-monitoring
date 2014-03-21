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

use strict;
use warnings;

use LWP::UserAgent;
use HTTP::Request::Common qw(GET POST);
use File::Spec;
use JSON;
use Data::Dumper;

# Конфигурация
my $VERSION = "1.0";

# diagnostic utilities
my $ADAPTEC_UTILITY = '/usr/local/bin/arcconf';
my $LSI_UTILITY = '/opt/MegaRAID/MegaCli/MegaCli64';

# API
my $API_URL = 'https://bill2fast.com/api/server-state/storage';

# Centos && Debian uses same path
my $parted = "LANG=POSIX /sbin/parted";
# Centos && Debian uses same path
my $mdadm = "/sbin/mdadm";

# Обанаруживаем все устройства хранения
my @disks = find_disks();

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

if ($only_detect_drives) {
    for my $storage (@disks) {
        print "Device $storage->{device_name} with type: $storage->{type} model: $storage->{model} in state: $storage->{status} detected\n";
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

# Check diagnostic utilities availability
sub check_disk_utilities {
    my (@disks) = @_;

    my $adaptec_needed = 0;
    my $lsi_needed = 0;
    my $mdadm_needed = 0;

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
        if ($line =~ /^\s+Status of logical device\s+:\s+(.+)$/i) {
            $status = lc($1);
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
            $status = lc($1);
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
        if ($line =~ /^\s+State\s+:\s+(\w+)/) {
            $status = $1;
        }
    }

    return $status;
}

# Run disgnostic utility for each disk
sub diag_disks {
    my (@disks) = @_;
    my @result_disks = ();

    foreach my $storage (@disks) {
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
                $cmd = $ADAPTEC_UTILITY . " getconfig 1 ld";
                $res = `$cmd 2>&1`;

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
                # it may be run with -L<num> for specific logical drive
                $cmd = $LSI_UTILITY . " -LDInfo -Lall -Aall";
        
                $res = `$cmd 2>&1`;

                $storage_status = extract_lsi_status($res);
            }
        } elsif ($type eq 'hard_disk') {
            $cmd = "smartctl --all $device_name";
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

    my $req = POST($API_URL, Content => encode_json($request_data) );

    # get result
    my $ua = LWP::UserAgent->new();
    #$ua->agent("FastVPS disk monitoring version $VERSION");
    my $res = $ua->request($req);
    
    if ($res->is_success) {
        print "Data sent successfully\n";
    } else {
        warn "Can't sent data to collector: " . $res->status_line  .  "\n";
    }
}

