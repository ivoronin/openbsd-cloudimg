#!/bin/ksh

chmod 755 /usr/local/sbin/cloud-init
echo /usr/local/sbin/cloud-init >> /etc/rc.firsttime

rm -f /etc/hostname.vio0 # used in qemu
echo dhcp > /etc/hostname.xnf0
chmod 640 /etc/hostname.xnf0
