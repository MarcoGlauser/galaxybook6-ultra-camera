# ipu-bridge with an SSLC2000 entry, for whichever kernel DKMS builds for.
#
# ipu-bridge.c is not part of the kernel headers, so the copy matching the
# target kernel (tag vX.Y.Z, falling back to vX.Y) is fetched from kernel.org
# stable and the two-line SSLC2000 entry is added to it.

KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build
# Kernels built with clang (e.g. XanMod) need LLVM=1
CLANG := $(if $(shell grep -s '^CONFIG_CC_IS_CLANG=y' $(KDIR)/.config),LLVM=1)

KMM    := $(shell echo $(KVER) | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')
KPATCH := $(shell echo $(KVER) | sed -nE 's/^[0-9]+\.[0-9]+\.([1-9][0-9]*).*/\1/p')
TAGS   := $(if $(KPATCH),v$(KMM).$(KPATCH)) v$(KMM)
URL    := https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/media/pci/intel/ipu-bridge.c?h=
# Samsung/SmartSens SC200PC. No link frequencies listed, so the fwnode
# property is omitted and ISYS takes the rate from the sensor driver's
# V4L2_CID_LINK_FREQ control.
ENTRY  := \t/* Samsung/SmartSens SC200PC (link frequency from the sensor driver) */\n\tIPU_SENSOR_CONFIG("SSLC2000", 0),

all: ipu-bridge.c
	$(MAKE) -C $(KDIR) M=$(CURDIR) $(CLANG) modules

ipu-bridge.c:
	@set -e; src=; for tag in $(TAGS); do \
		if curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
			-o $@.tmp '$(URL)'$$tag; then src=$$tag; break; fi; \
	done; \
	[ -n "$$src" ] || { echo "cannot fetch ipu-bridge.c for $(KVER) (tried: $(TAGS))" >&2; exit 1; }; \
	if grep -q '"SSLC2000"' $@.tmp; then mv $@.tmp $@; \
	else sed 's|\(ipu_supported_sensors\[\] = {\)|\1\n$(ENTRY)|' $@.tmp > $@; \
	     rm -f $@.tmp; grep -q '"SSLC2000"' $@; fi; \
	echo "ipu-bridge.c from $$src"

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
	rm -f ipu-bridge.c ipu-bridge.c.tmp

.PHONY: all clean
