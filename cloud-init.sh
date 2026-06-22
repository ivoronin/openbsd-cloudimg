#!/bin/ksh

export LC_ALL=C   # byte-literal handling of binary garbage in raw label reads

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

# Echo the disk whose ISO9660 volume label is exactly CIDATA, else return 1.
# Reads only fixed-offset bytes (no mount): the ISO9660 PVD is always at sector
# 16, the "CD001" signature at offset 1, the 32-byte volume id at offset 40.
# The mount in datasource_nocloud is the real structural validator.
nocloud_find() {
	for dev in $(sysctl -n hw.disknames | tr , ' ' | sed 's/:[^ ]*//g'); do
		sig=$(dd if="/dev/r${dev}c" bs=2048 skip=16 count=1 2>/dev/null | dd bs=1 skip=1 count=5 2>/dev/null)
		[ "$sig" = CD001 ] || continue
		label=$(dd if="/dev/r${dev}c" bs=2048 skip=16 count=1 2>/dev/null | dd bs=1 skip=40 count=32 2>/dev/null | tr -cd 'A-Za-z0-9_' | tr '[:lower:]' '[:upper:]')
		[ "$label" = CIDATA ] && { echo "$dev"; return 0; }
	done
	return 1
}

# meta-data parsers: best-effort YAML, no library, scoped to the right keys.
nocloud_hostname() {
	sed -n 's/^local-hostname:[[:space:]]*//p' "$1"
}
nocloud_keys() {
	# items of the top-level public-keys: block; kept only if ssh-key-shaped, so
	# ssh-looking text elsewhere in the file is never harvested.
	awk '
		/^[^[:space:]#]/ { inblock = ($1 == "public-keys:") }
		inblock && /^[[:space:]]+-[[:space:]]/ {
			sub(/^[[:space:]]*-[[:space:]]*/, ""); sub(/^"/, ""); sub(/"$/, "")
			if ($0 ~ /^(ssh-|ecdsa-sha2-|sk-ssh-|sk-ecdsa-)/) print
		}
	' "$1"
}

datasource_nocloud() {
	dev="$(nocloud_find)" || return 1
	mount -t cd9660 -r "/dev/${dev}c" /mnt 2>/dev/null || return 1
	if [ -s /mnt/meta-data ]; then
		SSH_KEY="$(nocloud_keys /mnt/meta-data)"
		LOCAL_HOSTNAME="$(nocloud_hostname /mnt/meta-data)"
	fi
	umount /mnt 2>/dev/null
	# value sanity: drop a hostname that is not hostname-shaped
	case "${LOCAL_HOSTNAME}" in
		""|*[!A-Za-z0-9.-]*) LOCAL_HOSTNAME= ;;
	esac
	[ -n "${SSH_KEY}" ] || [ -n "${LOCAL_HOSTNAME}" ]
}

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
	awk '/^# cloud-init$/,/^# cloud-init end$/{next} 1' > "${SSH_AUTHORIZED_KEYS}" < "${SSH_AUTHORIZED_KEYS}.bak"
	printf '# cloud-init\n%s\n# cloud-init end\n' "${SSH_KEY}" >> "${SSH_AUTHORIZED_KEYS}"
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

# NoCloud (disk) wins if present; otherwise IMDS. NoCloud-first means a local
# VM with no IMDS does not sit through the 15s ftp connect timeout.
datasource_nocloud || datasource_imds

# No idempotency grep: NoCloud may yield multiple keys (a grep pattern with
# embedded newlines does not match line-by-line), and setup_ssh_keys /
# setup_local_hostname are already idempotent (they replace the managed block /
# rewrite the files), so re-running each boot is a no-op on content.
[ -n "${SSH_KEY}" ] && setup_ssh_keys
[ -n "${LOCAL_HOSTNAME}" ] && setup_local_hostname
