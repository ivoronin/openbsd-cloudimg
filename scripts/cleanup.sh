#!/bin/ksh
echo "Removing files:"
rm -fv \
  /root/.ssh/authorized_keys \
  /root/.ssh/known_hosts \
  /etc/ssh/ssh_host* \
  /etc/isakmpd/private/local.key \
  /etc/isakmpd/local.pub \
  /etc/iked/private/local.key \
  /etc/iked/local.pub \
  /etc/soii.key \
  /etc/random.seed \
  /var/db/host.random \
  /var/db/dhcpleased/* \
  /var/db/dhcp6leased/* \
  /var/db/acpi/* \
  /var/db/ntpd.drift

rm -fv /root/.history /root/.ksh_history /root/.viminfo

rcctl stop syslogd pflogd
for log in /var/log/*; do
	[ -f "$log" ] && : > "$log"
done

[ -f "/var/mail/root" ] && : > "/var/mail/root"

rm -rf /tmp/* /var/tmp/*
