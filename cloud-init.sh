#!/bin/ksh

METADATA_BASE_URL="http://169.254.169.254/latest"
SSH_KEY_USER=openbsd

SSH_KEY_USER_GID="$(getent passwd ${SSH_KEY_USER} | cut -d: -f4)"
SSH_KEY_USER_HOME="$(getent passwd ${SSH_KEY_USER} | cut -d: -f6)"

get_data() {
   ftp -Vo - "${METADATA_BASE_URL}/$1"
}

setup_ssh_keys() {
	mkdir -p -m 700 "${SSH_KEY_USER_HOME}/.ssh"
	chown "${SSH_KEY_USER}:${SSH_KEY_USER_GID}" "${SSH_KEY_USER_HOME}/.ssh"

	if [ ! -f "${SSH_AUTHORIZED_KEYS}" ]; then
		touch "${SSH_AUTHORIZED_KEYS}"
		chown "${SSH_KEY_USER}:${SSH_KEY_USER_GID}" "${SSH_AUTHORIZED_KEYS}"
	fi

	mv "${SSH_AUTHORIZED_KEYS}" "${SSH_AUTHORIZED_KEYS}.bak"
	awk '/^# cloud-init/{c=2} !(c&&c--)' > "${SSH_AUTHORIZED_KEYS}" < "${SSH_AUTHORIZED_KEYS}.bak"
	echo "# cloud-init\n${SSH_KEY}" >> "${SSH_AUTHORIZED_KEYS}"
	rm "${SSH_AUTHORIZED_KEYS}.bak"
}

setup_local_hostname() {
	echo "${LOCAL_HOSTNAME}" > /etc/myname
	hostname "${LOCAL_HOSTNAME}"
	LOCAL_SHORTNAME="$(echo ${LOCAL_HOSTNAME} | cut -d. -f1)"
	LOCAL_NAMES="localhost ${LOCAL_SHORTNAME}"
	if [ "${LOCAL_SHORTNAME}" != "${LOCAL_HOSTNAME}" ]; then
		LOCAL_NAMES="${LOCAL_NAMES} ${LOCAL_HOSTNAME}"
	fi
	sed -i -e "s/^127.0.0.1[[:space:]].*/127.0.0.1 ${LOCAL_NAMES}/" \
		-e "s/^::1[[:space:]].*/::1 ${LOCAL_NAMES}/" /etc/hosts
}

SSH_KEY="$(get_data meta-data/public-keys/0/openssh-key)"
if [[ $? -eq 0 && -n "${SSH_KEY}" ]]; then
	SSH_AUTHORIZED_KEYS="${SSH_KEY_USER_HOME}/.ssh/authorized_keys"

	grep -q "^${SSH_KEY}$" "${SSH_AUTHORIZED_KEYS}" 2> /dev/null
	if [ $? -ne 0 ]; then
		setup_ssh_keys
	fi
fi

LOCAL_HOSTNAME="$(get_data meta-data/local-hostname)"
if [[ $? -eq 0 && -n "${LOCAL_HOSTNAME}" ]]; then
	grep -q "^${LOCAL_HOSTNAME}$" /etc/myname
	if [ $? -ne 0 ]; then
		setup_local_hostname
	fi
fi
