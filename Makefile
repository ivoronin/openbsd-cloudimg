VER          ?= 7.9
# Build-host arch in the project's naming (amd64/arm64); drives ARCH and ACCEL defaults.
HOST_ARCH    := $(patsubst aarch64,arm64,$(patsubst x86_64,amd64,$(shell uname -m)))
ARCH         ?= $(HOST_ARCH)
FLAVOR       ?= base
# Build target: generic (stock kernel) or aws (patched kernel via the builder stage).
BUILD        ?= generic
# Boot firmware: uefi (GPT) or, on amd64 only, bios (MBR). Defaults uefi for aws/arm64.
FIRMWARE     ?= $(if $(filter aws,$(BUILD)),uefi,$(if $(filter arm64,$(ARCH)),uefi,bios))
# QEMU accelerator: native (kvm/hvf) when target arch matches the host, else tcg.
ACCEL        ?= $(if $(filter $(ARCH),$(HOST_ARCH)),$(if $(filter Darwin,$(shell uname -s)),hvf,kvm),tcg)
CLOUD_INIT_SOURCE  ?=
# Optional debug flags - set to 1 to drop a provisioning step from the build.
DISABLE_SYSPATCH   ?=
DISABLE_CLOUD_INIT ?=
DISABLE_CLEANUP    ?=
# UEFI firmware, auto-located across common qemu/distro dirs (override if not found).
EFI_CODE     ?= $(firstword $(wildcard $(if $(filter arm64,$(ARCH)),\
/opt/homebrew/share/qemu/edk2-aarch64-code.fd /usr/share/qemu/edk2-aarch64-code.fd /usr/share/AAVMF/AAVMF_CODE.fd,\
/opt/homebrew/share/qemu/edk2-x86_64-code.fd /usr/share/qemu/edk2-x86_64-code.fd /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd)))
EFI_VARS     ?= $(firstword $(wildcard $(if $(filter arm64,$(ARCH)),\
/opt/homebrew/share/qemu/edk2-arm-vars.fd /usr/share/qemu/edk2-arm-vars.fd /usr/share/AAVMF/AAVMF_VARS.fd,\
/opt/homebrew/share/qemu/edk2-i386-vars.fd /usr/share/qemu/edk2-i386-vars.fd /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd)))
ISO_CHECKSUM ?= $(shell jq -r '.[] | select(.version=="$(VER)" and .arch=="$(ARCH)") | .iso_checksum' images.json)

NAME  = openbsd-$(VER)-$(ARCH)-$(BUILD)-$(FLAVOR)-$(FIRMWARE)
OUT    = output/build/$(ARCH)/$(VER)/$(BUILD)/$(FLAVOR)/$(FIRMWARE)
IMG    = $(OUT)/$(NAME).img
IMGXZ  = $(OUT)/$(NAME).img.xz
# The site set the builder produces, ridden as cd1. Keyed by arch/ver/build, kept
# outside $(OUT) (which -force wipes).
TAG    = $(subst .,,$(VER))
SETDIR = output/sets/$(ARCH)/$(VER)/$(BUILD)
SITE   = $(SETDIR)/site$(TAG).tgz
# Only non-generic targets ship a site set.
SITE_IF = $(if $(filter-out generic,$(BUILD)),$(SITE))

SOURCES = image.pkr.hcl install.conf.pkrtpl cloud-init.pl $(wildcard scripts/*)

.PHONY: build site smoke compress clean
.SUFFIXES:

build: $(IMG)

site: $(SITE_IF)

compress: $(IMGXZ)

SMOKE_SOURCES = $(if $(CLOUD_INIT_SOURCE),$(CLOUD_INIT_SOURCE),imds cidata)

smoke: $(IMG)
	packer init smoke.pkr.hcl
	@for s in $(SMOKE_SOURCES); do \
	  echo "=== smoke: cloud_init_source=$$s ==="; \
	  packer build -force -var cloud_init_source=$$s -var image=$(IMG) -var version=$(VER) -var arch=$(ARCH) -var flavor=$(FLAVOR) -var firmware=$(FIRMWARE) -var accelerator=$(ACCEL) -var efi_code=$(EFI_CODE) -var efi_vars=$(EFI_VARS) smoke.pkr.hcl || exit 1; \
	done

# The builder VM compiles the kernel and packs the whole site set + SHA256.
$(SITE): build.pkr.hcl build.conf.pkrtpl build/$(BUILD)/build.sh build/$(BUILD)/install.site \
         $(wildcard build/$(BUILD)/$(VER)/patches/* build/$(BUILD)/$(VER)/files/*) images.json
	packer init build.pkr.hcl
	packer build -force \
	  -var version=$(VER) \
	  -var arch=$(ARCH) \
	  -var build=$(BUILD) \
	  -var accelerator=$(ACCEL) \
	  -var iso_checksum=$(ISO_CHECKSUM) \
	  -var efi_code=$(EFI_CODE) \
	  -var efi_vars=$(EFI_VARS) \
	  build.pkr.hcl

$(IMG): $(SOURCES) $(SITE_IF) images.json
	packer init image.pkr.hcl
	packer build -force \
	  -var version=$(VER) \
	  -var arch=$(ARCH) \
	  -var build=$(BUILD) \
	  -var flavor=$(FLAVOR) \
	  -var firmware=$(FIRMWARE) \
	  -var accelerator=$(ACCEL) \
	  -var iso_checksum=$(ISO_CHECKSUM) \
	  -var efi_code=$(EFI_CODE) \
	  -var efi_vars=$(EFI_VARS) \
	  -var set_dir=$(SETDIR) \
	  -var disable_syspatch=$(if $(DISABLE_SYSPATCH),true,false) \
	  -var disable_cloud_init=$(if $(DISABLE_CLOUD_INIT),true,false) \
	  -var disable_cleanup=$(if $(DISABLE_CLEANUP),true,false) \
	  image.pkr.hcl

$(IMGXZ): $(IMG)
	xz -T0 -c $< > $@

clean:
	rm -rf output
