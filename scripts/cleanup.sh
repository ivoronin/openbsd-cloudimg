#!/bin/ksh
# Strip every identity and build-time trace before the image is sealed, so each
# instance starts fresh and the build host leaks nothing. cloud-init re-injects
# the ssh key and hostname on first boot; OpenBSD itself regenerates the host
# keys, IPsec keys and the RNG seed when it finds them missing.

# Per-host secrets and identity. rm -f because some paths are absent on some
# builds (random.seed, dhcp6leased, ntpd.drift) and a missing file must not fail
# the provisioner.
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

# Shell and editor history from provisioning.
rm -fv /root/.history /root/.ksh_history /root/.viminfo

# Logs hold the build session: the ephemeral-key root login, Packer's IP, build
# timestamps. Truncate every regular file under /var/log (wtmp and lastlog
# included) so logging keeps working from a clean slate.
for log in /var/log/*; do
	[ -f "$log" ] && : > "$log"
done

# Scratch dirs.
rm -rf /tmp/* /var/tmp/*
