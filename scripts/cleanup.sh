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

# Network: drop the installer's build-NIC config and lay down a generic cloud
# set, so netstart brings up whichever NIC the target presents and silently
# skips the absent ones (ifcreate no-ops them). "inet autoconf" = DHCP.
rm -f /etc/hostname.*
for _if in vio0 ena0 xnf0 hvn0 vmx0; do
	echo 'inet autoconf' > /etc/hostname.$_if
done

echo "Zeroing free space:"
mount -t ffs | while read -r _dev _on mnt _rest; do
	echo "  $mnt"
	dd if=/dev/zero of="$mnt/.zerofill" bs=1m 2>/dev/null
	rm -f "$mnt/.zerofill"
done
sync
