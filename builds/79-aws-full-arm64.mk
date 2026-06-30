BUILD_ARCH = arm64
BUILD_FIRMWARE = uefi
OPENBSD_TAG = 79

SETS = *
DISK_SIZE = 40G

ISO_URL = https://cdn.openbsd.org/pub/OpenBSD/7.9/arm64/install79.iso
ISO_CHECKSUM = sha256:49786ab82868b6e508a0117c0c1567694a2f6b46caf8972c726868617b8c22fb
ISO_SETS_PATH = 7.9/arm64

BUNDLE_NAMES = 7.9-aws14-arm64.tgz
BUNDLE_URL.7.9-aws14-arm64.tgz = https://github.com/ivoronin/openbsd-kernel-aws/releases/download/7.9-aws14/7.9-aws14-arm64.tgz
BUNDLE_SHA256.7.9-aws14-arm64.tgz = 4f96a92f1216b132a2292f391bdd58f5966279c2c96a784def994d1b51790760
