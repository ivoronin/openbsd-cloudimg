VER          ?= 7.9
ARCH         ?= amd64
FLAVOR       ?= base
ACCEL        ?= kvm
ISO_CHECKSUM ?= $(shell jq -r '.[] | select(.version=="$(VER)" and .arch=="$(ARCH)") | .iso_checksum' images.json)

NAME  = openbsd-$(VER)-$(ARCH)-$(FLAVOR)
OUT   = output/$(FLAVOR)
IMG    = $(OUT)/$(NAME).img
IMGZST = $(OUT)/$(NAME).img.zst

SOURCES = openbsd.pkr.hcl install.conf.pkrtpl cloud-init.sh $(wildcard scripts/*)

.PHONY: build smoke compress clean
.SUFFIXES:

build: $(IMG)

compress: $(IMGZST)

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

$(IMGZST): $(IMG)
	zstd -T0 -19 --long=27 -f -o $@ $<

clean:
	rm -rf output
