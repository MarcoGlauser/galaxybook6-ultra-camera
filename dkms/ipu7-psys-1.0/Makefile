# Intel IPU7 PSYS (hardware ISP) module for kernels with the in-tree staging
# intel_ipu7 driver (6.17+) that do not ship PSYS themselves, e.g. XanMod or
# Ubuntu kernels other than the one linux-modules-ipu7-generic is built for.
#
# The PSYS sources are from intel/ipu7-drivers (via Ubuntu's intel-ipu7-dkms,
# git a88b1909). PSYS uses the core driver's structures, so it is built
# against the staging IPU7 headers of the exact target kernel, fetched from
# kernel.org stable (tag vX.Y.Z, falling back to vX.Y), not against the copies
# in ipu7-drivers, which differ.

KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build
CLANG := $(if $(shell grep -s '^CONFIG_CC_IS_CLANG=y' $(KDIR)/.config),LLVM=1)

KMM    := $(shell echo $(KVER) | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')
KPATCH := $(shell echo $(KVER) | sed -nE 's/^[0-9]+\.[0-9]+\.([1-9][0-9]*).*/\1/p')
TAGS   := $(if $(KPATCH),v$(KMM).$(KPATCH)) v$(KMM)
URL    := https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/staging/media/ipu7/
HDRS   := ipu7.h ipu7-bus.h ipu7-boot.h ipu7-buttress.h ipu7-buttress-regs.h \
	  ipu7-dma.h ipu7-mmu.h ipu7-syscom.h ipu7-cpd.h ipu7-platform-regs.h \
	  abi/ipu7_fw_boot_abi.h abi/ipu7_fw_common_abi.h abi/ipu7_fw_config_abi.h \
	  abi/ipu7_fw_msg_abi.h abi/ipu7_fw_psys_config_abi.h abi/ipu7_fw_syscom_abi.h

all: hdr/.fetched
	$(MAKE) -C $(KDIR) M=$(CURDIR) $(CLANG) modules

# A single target, so parallel make does not fetch twice.
hdr/.fetched:
	@set -e; src=; for tag in $(TAGS); do \
		rm -rf hdr.tmp; mkdir -p hdr.tmp/abi; ok=1; \
		for h in $(HDRS); do \
			curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
				-o hdr.tmp/$$h '$(URL)'$$h'?h='$$tag || { ok=; break; }; \
		done; \
		if [ -n "$$ok" ]; then src=$$tag; break; fi; \
	done; \
	[ -n "$$src" ] || { echo "cannot fetch IPU7 headers for $(KVER) (tried: $(TAGS))" >&2; exit 1; }; \
	rm -rf hdr; mv hdr.tmp hdr; touch $@; echo "IPU7 headers from $$src"

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
	rm -rf hdr hdr.tmp

.PHONY: all clean
