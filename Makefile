BASE_DISK_PATH=output/base/openbsd-base.raw
FULL_DISK_PATH=output/full/openbsd-full.raw
SCRIPTS=$(wildcard scripts/*)

.SUFFIXES: .raw .qcow2 .raw.gz

all: output/base/openbsd-base.qcow2 output/full/openbsd-full.qcow2 \
	output/base/openbsd-base.raw.gz output/full/openbsd-full.raw.gz

${BASE_DISK_PATH}: openbsd.pkr.hcl install.conf.pkrtpl cloud-init.sh ${SCRIPTS}
	packer build -only=qemu.base -force openbsd.pkr.hcl

${FULL_DISK_PATH}: openbsd.pkr.hcl install.conf.pkrtpl cloud-init.sh ${SCRIPTS}
	packer build -only=qemu.full -force openbsd.pkr.hcl

.raw.qcow2:
	qemu-img convert -c -f raw -O qcow2 $< $@

.raw.raw.gz:
	gzip -9c < $< > $@
