echo "Removing files:"
rm -v \
  /root/.ssh/authorized_keys \
  /etc/ssh/ssh_host* \
  /etc/isakmpd/private/local.key \
  /etc/isakmpd/local.pub \
  /etc/iked/private/local.key \
  /etc/iked/local.pub \
  /etc/soii.key \
  /var/db/dhcpleased/*
