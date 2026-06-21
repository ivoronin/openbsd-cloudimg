VER          ?= 7.9
ARCH         ?= amd64
FLAVOR       ?= base
ACCEL        ?= kvm
ISO_CHECKSUM ?= $(shell jq -r '.[] | select(.version=="$(VER)" and .arch=="$(ARCH)") | .iso_checksum' images.json)

NAME  = openbsd-$(VER)-$(ARCH)-$(FLAVOR)
OUT   = output/$(FLAVOR)
IMG   = $(OUT)/$(NAME).img
IMGXZ = $(OUT)/$(NAME).img.xz

SOURCES = openbsd.pkr.hcl install.conf.pkrtpl cloud-init.sh $(wildcard scripts/*)

.PHONY: build smoke clean
.SUFFIXES:

build: $(IMGXZ)

smoke: $(IMG)
	packer init test.pkr.hcl
	packer build -force -var image=$(IMG) -var accelerator=$(ACCEL) test.pkr.hcl

$(IMG): $(SOURCES) images.json
	packer init openbsd.pkr.hcl
	packer build -force \
	  -var version=$(VER) \
	  -var arch=$(ARCH) \
	  -var flavor=$(FLAVOR) \
	  -var accelerator=$(ACCEL) \
	  -var iso_checksum=$(ISO_CHECKSUM) \
	  openbsd.pkr.hcl

$(IMGXZ): $(IMG)
	xz -9 -T0 -c $< > $@

clean:
	rm -rf output
