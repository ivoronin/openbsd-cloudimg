BUILD_ARCH = amd64
BUILD_FIRMWARE = bios
OPENBSD_TAG = 79

SETS = *
DISK_SIZE = 40G

ISO_URL = https://cdn.openbsd.org/pub/OpenBSD/7.9/amd64/install79.iso
ISO_CHECKSUM = sha256:7a4a92e953618035097c796a90b54424a0f3ae775552e1e7d102cf8a5130449f
ISO_SETS_PATH = 7.9/amd64

BUNDLE_NAMES = 7.9-aws15-amd64.tgz
BUNDLE_URL.7.9-aws15-amd64.tgz = https://github.com/ivoronin/openbsd-kernel-aws/releases/download/7.9-aws15/7.9-aws15-amd64.tgz
BUNDLE_SHA256.7.9-aws15-amd64.tgz = 20a6e0892cc09a134312206e62a9b127b483e49244f33a318a4f3a63a515149f
