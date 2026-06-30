BUILD_ARCH = amd64
BUILD_FIRMWARE = bios
OPENBSD_TAG = 79

SETS = -man* -game* -x* -comp*
DISK_SIZE = 10G

ISO_URL = https://cdn.openbsd.org/pub/OpenBSD/7.9/amd64/install79.iso
ISO_CHECKSUM = sha256:7a4a92e953618035097c796a90b54424a0f3ae775552e1e7d102cf8a5130449f
ISO_SETS_PATH = 7.9/amd64

BUNDLE_NAMES = 7.9-aws14-amd64.tgz
BUNDLE_URL.7.9-aws14-amd64.tgz = https://github.com/ivoronin/openbsd-kernel-aws/releases/download/7.9-aws14/7.9-aws14-amd64.tgz
BUNDLE_SHA256.7.9-aws14-amd64.tgz = 0d03e9028195e75b4984ee3bf17355815a71a73ffeefa25af954b43eb1f825c5
