#!/bin/ksh

# Configure the machine (ssh key + hostname) from the first available data
# source. Sources are tried in priority order; the first present one wins.

IMDS_BASE_URL="http://169.254.169.254/latest"
SSH_KEY_USER=openbsd
SSH_KEY_USER_GID="$(getent passwd ${SSH_KEY_USER} | cut -d: -f4)"
SSH_KEY_USER_HOME="$(getent passwd ${SSH_KEY_USER} | cut -d: -f6)"
SSH_AUTHORIZED_KEYS="${SSH_KEY_USER_HOME}/.ssh/authorized_keys"

# Normalized config, populated by the selected data source.
SSH_KEY=
LOCAL_HOSTNAME=

# ---- data sources ------------------------------------------------------
# Each datasource_* populates SSH_KEY / LOCAL_HOSTNAME and returns 0 if its
# medium is present (it is the active source), non-zero otherwise.

# -w 15: give up if the IMDS does not connect within 15s, so an unavailable
# metadata endpoint cannot wedge boot.
imds_get() {
	ftp -w 15 -Vo - "${IMDS_BASE_URL}/$1"
}

datasource_imds() {
	SSH_KEY="$(imds_get meta-data/public-keys/0/openssh-key)"
	LOCAL_HOSTNAME="$(imds_get meta-data/local-hostname)"
	[ -n "${SSH_KEY}" ] || [ -n "${LOCAL_HOSTNAME}" ]
}

# ---- apply (source-agnostic) -------------------------------------------

setup_ssh_keys() {
	# shellcheck disable=SC2174
	mkdir -p -m 700 "${SSH_KEY_USER_HOME}/.ssh"
	chown "${SSH_KEY_USER}:${SSH_KEY_USER_GID}" "${SSH_KEY_USER_HOME}/.ssh"

	if [ ! -f "${SSH_AUTHORIZED_KEYS}" ]; then
		touch "${SSH_AUTHORIZED_KEYS}"
		chown "${SSH_KEY_USER}:${SSH_KEY_USER_GID}" "${SSH_AUTHORIZED_KEYS}"
	fi

	mv "${SSH_AUTHORIZED_KEYS}" "${SSH_AUTHORIZED_KEYS}.bak"
	awk '/^# cloud-init/{c=2} !(c&&c--)' > "${SSH_AUTHORIZED_KEYS}" < "${SSH_AUTHORIZED_KEYS}.bak"
	printf '# cloud-init\n%s\n' "${SSH_KEY}" >> "${SSH_AUTHORIZED_KEYS}"
	rm "${SSH_AUTHORIZED_KEYS}.bak"
}

setup_local_hostname() {
	echo "${LOCAL_HOSTNAME}" > /etc/myname
	hostname "${LOCAL_HOSTNAME}"
	LOCAL_SHORTNAME="${LOCAL_HOSTNAME%%.*}"
	LOCAL_NAMES="localhost ${LOCAL_SHORTNAME}"
	if [ "${LOCAL_SHORTNAME}" != "${LOCAL_HOSTNAME}" ]; then
		LOCAL_NAMES="${LOCAL_NAMES} ${LOCAL_HOSTNAME}"
	fi
	sed -i -e "s/^127.0.0.1[[:space:]].*/127.0.0.1 ${LOCAL_NAMES}/" \
		-e "s/^::1[[:space:]].*/::1 ${LOCAL_NAMES}/" /etc/hosts
}

# ---- main: first present source wins, then apply -----------------------

datasource_imds

if [ -n "${SSH_KEY}" ] && ! grep -q "^${SSH_KEY}$" "${SSH_AUTHORIZED_KEYS}" 2> /dev/null; then
	setup_ssh_keys
fi

if [ -n "${LOCAL_HOSTNAME}" ] && ! grep -q "^${LOCAL_HOSTNAME}$" /etc/myname; then
	setup_local_hostname
fi
