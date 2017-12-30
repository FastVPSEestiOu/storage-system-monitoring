storage-system-monitoring
==========================

*Read this in: [Russian](README.md), [English](README.en.md).*

Welcome, dear FastVPS Eesti OU customer! :) You've got here because we really care about you and your data safety!

You may find an open code of our disk subsystem diagnose system for your server.

How to install the monitoring script?
```bash
wget --no-check-certificate https://raw.github.com/FastVPSEestiOu/storage-system-monitoring/master/install.sh -O /tmp/storage_install.sh && bash /tmp/storage_install.sh && rm --force /tmp/storage_install.sh
```

Is this script safe?
- The script works via an ecrypted channel (https, ssl)
- The script doesn't open any ports in the system (which excludes a chance of intrusion from outside)
- The script doesn't update itself automatically (which excludes adding vulnerabilities)
- The script has an open code (which gives you a chance to read its content)

Where does it send all data?
- The data is send to https://fastcheck24.com via an ecrypted channel

What do we do with the data?
- We analyze it with a special software that uses various alogorythms to predict a disk subsystem failure
- In the event of detecting a potentially destructive promlems with the disk subsystem we shall contact you in any available way

Which types of RAID are being suppored by the monitoring?
- Adaptec
- LSI
- DELL PERC (LSI)

What does the script do?
- Sends Linux Soft Raid (mdadm only) or hardware RAID array status hourly
- Sends smartctl output regarding all disks in the system
- Executes S.M.A.R.T. tests (short+long) every weekend

What the script does NOT do?
- The script does not run any additional modules
- The script does not update itself automatically
- The script does not send any information except what is listed above 

Which operating systems are supported:
- Debian 7 and up
- Centos 6 and up
- Ubuntu 14.04 and up

Which program language the script was written in?
- Perl (monitoring module)
- Bash (installer)

What changes do we do in your system?
- We create a cron script: /etc/cron.d/storage-system-monitoring-fastvps
- We place arcconf, megaraid and storage_system_fastvps_monitoring.pl script in /usr/local/bin directory
- We change smartd configuration /etc/smartd.conf (is required to autorun S.M.A.R.T. short/long tests)

Who may use the software?
- Any FastVPS Eesti OU customer

What kind of software do we install on the server and why?
- smartmontools - a package of utilities for obtaining S.M.A.R.T. information from the device
- Perl modules to send data via HTTP and HTTPS protocols to our server for analysis
- arcconf/megacli - Adaptec и LSI vendor utilities

Where do we get proprietary software for LSI/Adaptec?
- https://storage.microsemi.com/en-us/speed/raid/storage_manager/arcconf_v2_01_22270_zip.php
- https://docs.broadcom.com/docs-and-downloads/sep/oracle/files/Linux_MegaCLI-8-07-07.zip

May I use the program locally to check an array status?
- Sure, but you loose all the features of our S.M.A.R.T. analyze system and other metrics. Only array contidion can be checked. Moreover you will not get any notifications when a disk fails

Is XXX YYY support available?
- Of course, patches are welcome!

How does the script output looks like?
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