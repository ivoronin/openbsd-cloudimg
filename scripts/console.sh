echo 'stty com0 115200' > /etc/boot.conf
echo 'set tty com0' >> /etc/boot.conf
sed -i -e 's/^tty00[[:space:]]\(.*\)[[:space:]]unknown off$/tty00   \1   vt220   on  secure/' /etc/ttys
