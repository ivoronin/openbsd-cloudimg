#!/bin/ksh
# Runs after Packer logged in as openbsd - that login alone proves the image
# booted, cloud-init ran, and the IMDS-provided ssh key was injected (there is
# no other way into the cleaned image). Assert the rest.
set -e

# cloud-init must have applied the IMDS local-hostname.
if [ "$(hostname)" != "smoke-test" ]; then
	echo "hostname is '$(hostname)', expected 'smoke-test'" >&2
	exit 1
fi

echo "smoke checks passed"
