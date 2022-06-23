#!/bin/ksh

useradd -G wheel -m openbsd
echo "permit keepenv nopass :wheel" > /etc/doas.conf
chmod 755 /usr/local/sbin/cloud-init
echo /usr/local/sbin/cloud-init >> /etc/rc.local
