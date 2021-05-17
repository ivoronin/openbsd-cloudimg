#!/bin/ksh

METADATA_BASE_URL="http://169.254.169.254/latest"

get_data() {
   ftp -Vo - "${METADATA_BASE_URL}/$1"
}

SSH_KEY="$(get_data meta-data/public-keys/0/openssh-key)"
LOCAL_HOSTNAME="$(get_data meta-data/local-hostname)"

mkdir -p -m 700 /root/.ssh
echo "${SSH_KEY}" > /root/.ssh/authorized_keys
echo "${LOCAL_HOSTNAME}" > /etc/myname
hostname "${LOCAL_HOSTNAME}"
sed -i -e "s/^127.0.0.1[[:space:]].*/127.0.0.1 localhost $(hostname -s) $(hostname)/" /etc/hosts
