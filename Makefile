VER          ?= 7.9
ARCH         ?= amd64
FLAVOR       ?= base
ACCEL        ?= kvm
ISO_CHECKSUM ?= $(shell jq -r '.[] | select(.version=="$(VER)" and .arch=="$(ARCH)") | .iso_checksum' images.json)

NAME  = openbsd-$(VER)-$(ARCH)-$(FLAVOR)
OUT   = output/$(FLAVOR)
RAW   = $(OUT)/$(NAME).raw
QCOW2 = $(OUT)/$(NAME).qcow2
RAWGZ = $(OUT)/$(NAME).raw.gz

SOURCES = openbsd.pkr.hcl install.conf.pkrtpl cloud-init.sh $(wildcard scripts/*)

.PHONY: build clean
.SUFFIXES:

build: $(QCOW2) $(RAWGZ)

$(RAW): $(SOURCES) images.json
	packer init openbsd.pkr.hcl
	packer build -force \
	  -var version=$(VER) \
	  -var arch=$(ARCH) \
	  -var flavor=$(FLAVOR) \
	  -var accelerator=$(ACCEL) \
	  -var iso_checksum=$(ISO_CHECKSUM) \
	  openbsd.pkr.hcl

$(QCOW2): $(RAW)
	qemu-img convert -c -f raw -O qcow2 $< $@

$(RAWGZ): $(RAW)
	gzip -9c < $< > $@

clean:
	rm -rf output
