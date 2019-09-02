#!/usr/bin/perl
=description
Authors:
Alexander Kaidalov <kaidalov@fastvps.ru>
Pavel Odintsov <odintsov@fastvps.ee>
License: GPLv2
=cut

# List of modules.
use strict;
use warnings;

use POSIX qw(locale_h);

use LWP::UserAgent;
use JSON;
use Data::Dumper;
use Getopt::Long;

# Configuration.
my $VERSION = "1.2";
my $PATH = $ENV{'PATH'};
my $API_URL = 'https://fastcheck24.com/api/server-state/storage';

# Diagnostic utilities
my $smartctl;
my $mdadm;
my $megacli;
my $arcconf;

# List of possible raid controllers.
my $adaptec_needed = 0;
my $lsi_needed = 0;
my $mdadm_needed = 0;

# Centos && Debian uses same path
my $sysfs_block_path = '/sys/block';

# Options
my $only_detect_drives;
my $cron_run;
my $json;
my $help;

# Set locale
setlocale(LC_ALL, "en_US");

# List of device's major_id for ignore.
my @major_blacklist = (
    1,   # это ram устройства
    2,   # Floppy disks
    7,   # это loop устройства
    11,  # CD-ROM
    43,  # nbd http://en.wikipedia.org/wiki/Network_block_device
    182, # это openvz ploop диск
    230, # zvol
    253, # device-mapper, но на Citrix XenServer это tapdev
    252, # device-mapper на Citrix XenServer
);

my $options = "Use options: [ --detect ] [ --cron ] [ --help ]
\t-d|--detect - Print list of drives. The result will not be sent to API.
\t-j|--json - Print smart data for found drives in json. The result will not be sent to API.
\t-c|--cron - Print smart data for found drives. The result will be sent to API. Must be set in crontab task.
\t-h|--help - show this message.\n";

GetOptions (
    "d|detect"  => \$only_detect_drives,
    "j|json"   => \$json,
    "c|cron"  => \$cron_run,
    "h|help"  => \$help,
) or die "Error in command line arguments!\n$options\n";

if ( $help ) {
    print $options,"\n";
    exit 0;
}

my $user_id = $<;
if ( $user_id != 0 ) {
    die "This program can only be run under root.\n";
}

# Get list of devices.
my @disks = find_disks_without_parted();

# Сheck the availability of utilities.
check_disk_utilities(@disks);

# Get smart result for found devices.
@disks = diag_disks(@disks);

# If a "--detect" option is specified .
if ($only_detect_drives) {
    for my $storage (@disks) {
        # The "hard_disk" does not have a "$storage->{status}"
        if ($storage->{'type'} eq 'hard_disk') {
            print "Device $storage->{device_name} with type: $storage->{type} model: $storage->{model} detected\n";
        } else {
            print "Device $storage->{device_name} with type: $storage->{type} model: $storage->{model} in state: $storage->{status} detected\n";
        }
    }
    if (scalar @disks == 0) {
        print "I can't find any disk devices. I suppose bug on this platform :(";
    }
    exit (0);
}

# If a "--cron" option is specified .
if ($cron_run) {
    if(!send_disks_results(@disks)) {
        print "Failed to send storage monitoring data to FastVPS";
        exit(1);
    }
    exit 0;
}

if ($json) {
    print_disks_results(@disks);
    exit 0;
}

if (!$only_detect_drives && !$cron_run) {
    print "This information was gathered and will be sent to FastVPS:\n";
    print "Disks found: " . (scalar @disks) . "\n\n";

    for my $storage (@disks) {
        print $storage->{device_name} . " is " . $storage->{'type'} . " Diagnostic data:\n";
        print $storage->{'diag'} . "\n\n";
    }
}

# Functions

sub which {
    my $prog_name   = shift;
    my $path_string = shift;

    my @path_array  = split /:/, $PATH;

    for my $path (@path_array) {
        if ( -x "$path/$prog_name" ) {
            return "$path/$prog_name";
        }
    }
    return 0;
}

# Deleting space symbols.
sub rtrim {
    my $string = shift;
    
    $string =~ s/\s+$//g;
    return $string;
}

# Get full path to device.
sub get_device_path {
    my $name = shift;
    
    return "/dev/$name";
}

# Get major_id for block devices in Linux.
sub get_major {
    my $device = shift;
 
    my $device_path = get_device_path($device);
    my $major = '';

    if (-e $device_path) {
        my $rdev = (stat $device_path)[6];
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

# Get name to device vendor
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
        # Convert to bytes.
        my $size_in_bytes = $size_in_blocks << 9;
        my $size_in_gbytes = int($size_in_bytes/1024**3);

        return "${size_in_gbytes}GB";
    } else {
        return "unknown";
    }
}

# Find block devices. Pareted is not used.
sub find_disks_without_parted {
    opendir my $block_devices, $sysfs_block_path or die "Can't open path $sysfs_block_path";

    my @disks = ();
    while (my $block_device = readdir($block_devices)) {
        # skip . and ..
        if ($block_device =~ m/^\.+$/) {
            next;
        }
        # skip device mapper fake devices
        if ($block_device =~ m/^dm-\d+/) {
            next;
        }

        # Skip devices if they have major_id from @major_blacklist.
        my $major = get_major($block_device);
        if (in_array($major, @major_blacklist)) {
            next;
        }

        my $vendor = get_device_vendor($block_device);
        my $model = get_device_model($block_device);

        $model = "$vendor $model";

        # Skip idrac devices.
        if ( $model =~ m/^idrac\s+virtual\s+\w+$/ ) {
           	next;
        }
        
        # Skip ipmi devices.
        if ( $model =~ m/^ipmi\s+virtual\s+\w+$/ ) {
           	next;
        }
        
        # Skip qemu devices.
        if ( $model =~ m/.+qemu.+/ ) {
            next;
        }

        # Skip JetFlash devices
        if ( $model =~ m/^jetflash\s+transcend\s+\w+$/ ) {
            next;
        }

        my $device_size = get_device_size($block_device);
        my $device_name = get_device_path($block_device);

        # detect type (raid or disk)
        my $type = 'disk';
        my $is_raid = '';
        my $raid_level = '';

        # adaptec
        if($model =~ m/adaptec/i or $model =~ m/ASR8405/i) {
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

    for my $storage (@disks) {
        # Adaptec
        if ($storage->{model} eq "adaptec") {
            $adaptec_needed = 1;

            $arcconf = which("arcconf", $PATH);            
            unless ($arcconf) {
                die "Adaptec utility not found. Please, install Adaptech raid management utility.\n";
            }
        }
        # LSI
        if ($storage->{model} eq "lsi") {
            $lsi_needed = 1;

            $megacli= which("megacli", $PATH);   
            unless ($megacli) {
                die "Megacli not found. Please, install LSI MegaCli raid management utility into.\n";
            }
        }
        # Mdadm
        if ($storage->{model} eq "md") {
            $mdadm_needed = 1;

            $mdadm = which("mdadm", $PATH);
            unless ($mdadm) {
                die "mdadm not found. Please, install mdadm.\n";
            }
        }
    }

    $smartctl = which("smartctl", $PATH);
    unless ($smartctl) {
        die "smartctl not found. Please, install smartctl.\n"
    }
}

# Get status from adaptec logical devices.
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

# Get status from mdadm.
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
    my @hwraid_disk_smart;
    my $adapctec_device_quantity = 0;

    if ( $lsi_needed ) {
        my $lsi_ld_all_res = `$megacli  -LDInfo -Lall -Aall 2>&1`;
        $lsi_ld_all_res =~ s/^\n\n//;
        @lsi_ld_all = split /\n\n\n/, $lsi_ld_all_res;
    }

    if ( $adaptec_needed ) {
        my $adaptec_ld_all_res = `$arcconf getconfig 1 ld 2>&1`;
        @adaptec_ld_all = split /\n\n/, $adaptec_ld_all_res;
        $adapctec_device_quantity = @{[$adaptec_ld_all_res =~ /Logical device number/gi]};
    }

    foreach my $storage (sort { $a->{'device_name'} cmp $b->{'device_name'} } @disks) {
        my $device_name = $storage->{device_name};
        my $type = $storage->{type};
        my $model = $storage->{model};
        my $res = '';
        my $cmd = '';
        # Get the status of a raid array.
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
                # Get status from mdadm.
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
            if ($device_name =~ /nvme/i) {
                $cmd = "$smartctl -d nvme,0xffffffff --all $device_name";
            } else {
                $cmd = "$smartctl --all $device_name";
            }
            $res = `$cmd 2>&1`;
        } else {
            warn "Unexpected type";
            $cmd = '';
        }

        $storage->{'status'} = $storage_status;
        $storage->{'diag'} = $res;

        push @result_disks, $storage;
    }

 # Get smart data for drives from a hardware raid.
 # If raid model is adaptec, additionally specify quantity of virtual arrays.
    if ($lsi_needed) {
        @hwraid_disk_smart = get_smart_disk('lsi');
        push @result_disks, @hwraid_disk_smart;
        }
    if ($adaptec_needed) {
        @hwraid_disk_smart = get_smart_disk('adaptec', $adapctec_device_quantity);
        push @result_disks, @hwraid_disk_smart;
    }

    return @result_disks;
}

sub get_smart_disk{
    my $raid_control = shift;
    my $adapctec_device_quantity = shift;

    my %pd_type;
    my @disk_hwraid_type_number;
    my @disk_raid_list;
    my $smart_result;
    my $smart_all_result;
    my ($device_name, $device_size, $model, $diag);

# Получаем номера дисков в raid, и определяем SAS он или нет.
    if ($raid_control =~ /lsi/){
        my $res = `$megacli -LdpdInfo -a0 -NoLog|grep -E 'Device Id:|Inquiry Data:|PD Type:' `;
        $res =~ s/\nPD Type/ PD Type/g;
        $res =~ s/\nInquiry/ Inquiry/g;

        for(split(/\n/,$res)){
            if(/ SSD /){
                s/ SATA / SSD /;
            }
            chomp($_);
            /PD Type: ([A-Z]{3,4}) /;
            my $pd = $1;
            s/Device Id: //;
            s/ PD Type.*//;
            push @disk_hwraid_type_number,$_;
            $pd_type{$_} = $pd;
        }
    }elsif( $raid_control =~ /adaptec/){
        my $res=`$arcconf getconfig 1 pd  | grep -E "Device #|Transfer Speed|SSD" | sed 's/  //g'`;
        $res =~ s/\n Transfer/ Transfer/g;
        $res =~ s/\n SSD/ SSD/g;

        for(split(/\n/,$res)){

            if (/ Yes /){
                s/ SATA / SSD /;
            }
            chomp($_);
            if (/Device #(\d+) Transfer Speed : (\w+) / ) {
                push @disk_hwraid_type_number,$1;
                $pd_type{$1} = $2;
            } else {
                /Device #(\d+)\s+/;
                push @disk_hwraid_type_number,$1;
                $pd_type{$1} = "SAS";
            }
        }
    }else{
        warn("It is not LSI or Adaptec - we didnt know to do!\n");
    }
    # Пытаемся получить smart-ы для каждого найденного в raid-е диска.
    for my $disk_number (@disk_hwraid_type_number) {
        if ($pd_type{$disk_number} =~ /SAS/) {
            $smart_result = get_sas_smart_info($disk_number, $raid_control, $adapctec_device_quantity);
        } else {
            $smart_result = get_ssd_smart_info($disk_number, $raid_control, $adapctec_device_quantity);
        }
		unless ($smart_result) {
			next;
		}
        $device_name = $disk_number;
        $model = $raid_control;
        $diag = $smart_result;
    # Данный хэш нужен, чтобы данные о каждом диске, добавлялись в общий массив.
        my $tmp_disk = {
            "device_name" => $device_name,
            "size"        => 'undefined',
            "model"       => $model,
            "type"        => 'hard_disk',
            "status"      => 'undefined',
            "diag"        => $diag,
        };
        push @disk_raid_list, $tmp_disk;
    }
    return @disk_raid_list;
}

#Получаем и НЕ парсим инфу с SSD диска
sub get_ssd_smart_info{
    my $disk_number = shift;
    my $hw_raid = shift;

    my $smart_result;

    if ($hw_raid eq "lsi"){
       $smart_result = `$smartctl -a  -d sat+megaraid,$disk_number /dev/sda`;
    }else{
        my $adapctec_device_quantity = shift;
        my $sg_number=$disk_number+$adapctec_device_quantity;

		my $smart_info = `$smartctl -i /dev/sg$sg_number`;
        if ($smart_info =~ /Product:\s+LogicalDrv/) {
			return 0;
		} else {
        	$smart_result = `$smartctl -a -d sat  /dev/sg$sg_number`;
    		return "$smart_result\n";
		}
	}
}

#Получаем и НЕ парсим инфу с SAS диска
sub get_sas_smart_info{
    my $disk_number = shift;
    my $hw_raid = shift;

    my $smart_result;

    if ($hw_raid eq "lsi"){
        $smart_result=`$smartctl -a  -d megaraid,$disk_number /dev/sda`;
    }else{
        my $adapctec_device_quantity = shift;
        my $sg_number=$disk_number+$adapctec_device_quantity;
        $smart_result=`$smartctl -a  /dev/sg$sg_number`;
    }
    return "$smart_result\n";
}

# Send disks diag results
sub send_disks_results {
    my (@disks) = @_;
    
    my $request_data = {
        'storage_devices' => \@disks,
        'version'         => $VERSION,
    };
    # get result
    my $ua = LWP::UserAgent->new();
    #$ua->agent("FastVPS disk monitoring version $VER
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

sub print_disks_results {
    my (@disks) = @_;

    my $request_data = {
        'storage_devices' => \@disks,
        'version'         => $VERSION,
    };
    print encode_json($request_data), "\n";
}
