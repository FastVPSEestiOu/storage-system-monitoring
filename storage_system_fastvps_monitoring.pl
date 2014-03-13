#!/usr/bin/perl
=description

Authors:
Alexander Kaidalov <kaidalov@fastvps.ru>
Pavel Odintsov <odintsov@fastvps.ee>

=cut

use strict;
use warnings;

use LWP::UserAgent;
use HTTP::Request::Common qw(GET POST);
use File::Spec;

use Data::Dumper;

# Конфигурация

my $VERSION = "1.0";

# diagnostic utilities
my $ADAPTEC_UTILITY = '/usr/local/bin/arcconf';
my $LSI_UTILITY = '/opt/MegaRAID/MegaCli/MegaCli64';

# API
use constant API_URL => 'https://bill2fast.com/monitoring_control.php';


#
# Functions
#

# Find disks
sub find_disks
{
    # here we'll save disk => ( info, ... )
    my %disks = ();
    
    # tmp variable for storing disk data
    my $tmp_disk = {};
    
    # get parted -lms output
    open(PARTED, 'parted -lms|') or die "Can't get parted output. Not installed?!";
    
    my $first_pass = 1;
    my $new_disk = 1;
    LINE: while(<PARTED>)
    {
        # skip empty line
        next LINE if /^\s/;
    
        # new disk
        if(/^BYT;/)
        {
            # add previous disk to hash
            if(!$first_pass)
            {
                %{$disks{$tmp_disk->{"disk"}->{"device"}}} = %$tmp_disk;
            }
    
            $new_disk = 1;
            $first_pass = 0;
            next LINE;
        }
    
        # get fields
        my @fields = split(/:/);
    
        # device
        if($new_disk)
        {
            $tmp_disk = {};
    
            # model
            $fields[6] =~ s/;\n$//;
    
            # add to list
            $tmp_disk->{"disk"} = {
                "device" => $fields[0],
                "size" => $fields[1],
                "model" => $fields[6],
            };
            @{$tmp_disk->{"partitions"}} = ();
    
            #
            # detect type (raid or disk)
            #
            my $type = 'disk';
            
            # adaptec
            if($fields[6] =~ m/adaptec .*(\d+)/i)
            {
                $type = 'adaptec';
    
                # save array number
                $tmp_disk->{"disk"}{"array_num"} = $1 + 1;
            }
    
            # MD
            $type = 'md' if $fields[0] =~ m/\/md\d+/;
    
            # LSI (3ware)
            $type = 'lsi' if $fields[6] =~ m/lsi/i;
    
            # add type
            $tmp_disk->{"disk"}{"type"} = $type;
    
            $new_disk = 0;
            next LINE;
        }
    
        # partition
        if(!$new_disk)
        {
            push(@{$tmp_disk->{"partitions"}}, {
                "number" => $fields[0],
                "used" => $fields[1],
                "total" => $fields[2],
                "free" => $fields[3]
            });
        }
    }

    # add last disk (if defined)
    if(scalar(keys(%$tmp_disk)))
    {
        %{$disks{$tmp_disk->{"disk"}->{"device"}}} = %$tmp_disk;
    }

    close(PARTED);

    return %disks;
}

# Check diagnostic utilities availability
sub check_disk_utilities
{
    my (%disks) = @_;

    my $adaptec_needed = 0;
    my $lsi_needed = 0;

    while((my $key, my $value) = each(%disks))
    {
        # Adaptec
        if(!$adaptec_needed && $value->{"disk"}{type} eq "adaptec")
        {
            die "Adaptec utility not found. Please, install Adaptech raid management utility into " . $ADAPTEC_UTILITY . "\n" unless -e $ADAPTEC_UTILITY;
            $adaptec_needed = 1;
        }
    
        # LSI
        if(!$lsi_needed && $value->{"disk"}{type} eq "lsi")
        {
            die "not found. Please, install LSI MegaCli raid management utility into " . $LSI_UTILITY . " (symlink if needed)\n" unless -e $LSI_UTILITY;
            $lsi_needed = 1;
        }
    
    }

    return ($adaptec_needed, $lsi_needed);
}

# Run disgnostic utility for each disk
sub diag_disks
{
    my (%disks) = @_;

    while((my $key, my $value) = each(%disks))
    {
        my $type = $value->{"disk"}{"type"};
        my $res = '';
        my $cmd = '';
    
        # adaptec
        if($type eq "adaptec")
        {
            $cmd = $ADAPTEC_UTILITY . " getconfig " . $value->{"disk"}{"array_num"} . " ld";
        }

        # md
        if($type eq "md")
        {    
            $cmd = 'cat /proc/mdstat';
        }

        # lsi (3ware)
        # TODO:
        if($type eq "lsi")
        {
            # it may be run with -L<num> for specific logical drive
            $cmd = $LSI_UTILITY . " -LDInfo -Lall -Aall";
        }
    
        # disk
        if($type eq "disk")
        {
            $cmd = "smartctl --all $key";
        }

        $res = `$cmd` if $cmd;
        
        $disks{$key}{"diag"} = $res;
    }

    return %disks;
}

# Send disks diag results
sub send_disks_results
{
    my (%disks) = @_;

    foreach(keys(%disks))
    {
    	my $disk = $disks{$_};
        my $diag = $disk->{'diag'};
    
        # send results
        my $status = 'error';
        $status = 'success' if $diag ne '';
        
        my $req = POST(API_URL, [
            action => "save_data",
            status => $status,
            agent_name => 'disks',
            agent_data => $diag,
            agent_version => $VERSION,
        ]);

        # get result
        my $ua = LWP::UserAgent->new();
        my $res = $ua->request($req);
        
        # TODO: check $res? old data in monitoring system will be notices
        #       one way or the other...

        return $res->is_success;
    }
}


#
# Run checks
#

# find disks
my %disks = find_disks;

# check diag utilities
check_disk_utilities(%disks);

# get diag data
%disks = diag_disks(%disks);

# send or show results

if (scalar @ARGV > 0 and $ARGV[0] eq '--cron')
{
    if(!send_disks_results(%disks))
    {
        print "Failed to send storage monitoring data to FastVPS";
        exit(1);
    }
}
else
{
    print "This information was gathered and will be sent to FastVPS:\n";
    print "Disks found: " . (scalar keys %disks) . "\n\n";

    while((my $key, my $value) = each(%disks))
    {
        print $key . " is " . $value->{'disk'}->{'type'} . " with " . (scalar @{$value->{'partitions'}}) . " partitions. Diagnostic data:\n";
        print $value->{'diag'} . "\n\n";
    }
}

