# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2021 Motor-comm Corporation.
#
# Makefile for the Motorcomm(R) 6801 PCI-Express ethernet driver
#
moderation_en?=1
moderation_param?=200
FXGMAC_SMART_SPEED_DISABLE = OFF
FXGMAC_PHY_SLEEP_ENABLE = OFF
FXGMAC_ASPM_ENABLED = OFF
FXGMAC_NOT_USE_PAGE_MAPPING = OFF
FXGMAC_ZERO_COPY = OFF
FXGMAC_DEBUG = ON
FXGMAC_TX_DMA_MAP_SINGLE = OFF
FXGMAC_EPHY_LOOPBACK_DETECT_ENABLED = OFF
FXGMAC_USE_STATIC_ALLOC = ON

obj-m += yt6801.o
EXTRA_CFLAGS += -I$(PWD)
EXTRA_CFLAGS += -Wall -g -fstack-protector-all -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,now -Wl,--disable-new-dtags,--rpath

EXTRA_CFLAGS += -DFXGMAC_INT_MODERATION_ENABLED=$(moderation_en)
EXTRA_CFLAGS += -DINT_MOD_IN_US=$(moderation_param)

ifeq (,$(filter OFF off, $(FXGMAC_SMART_SPEED_DISABLE)))
	EXTRA_CFLAGS += -DFXGMAC_SMART_SPEED_DISABLE
endif

ifeq (,$(filter OFF off, $(FXGMAC_PHY_SLEEP_ENABLE)))
	EXTRA_CFLAGS += -DFXGMAC_PHY_SLEEP_ENABLE
endif

ifeq (,$(filter OFF off, $(FXGMAC_NOT_USE_PAGE_MAPPING)))
	EXTRA_CFLAGS += -DFXGMAC_NOT_USE_PAGE_MAPPING
	ifeq (,$(filter OFF off, $(FXGMAC_ZERO_COPY)))
		EXTRA_CFLAGS += -DFXGMAC_ZERO_COPY
	endif
endif

ifeq (,$(filter OFF off, $(FXGMAC_DEBUG)))
	EXTRA_CFLAGS += -DFXGMAC_DEBUG
endif

ifeq (,$(filter OFF off, $(FXGMAC_TX_DMA_MAP_SINGLE)))
	EXTRA_CFLAGS += -DFXGMAC_TX_DMA_MAP_SINGLE
endif

ifeq (,$(filter OFF off, $(FXGMAC_EPHY_LOOPBACK_DETECT_ENABLED)))
	EXTRA_CFLAGS += -DFXGMAC_EPHY_LOOPBACK_DETECT_ENABLED
endif

ifeq (,$(filter OFF off, $(FXGMAC_ASPM_ENABLED)))
	EXTRA_CFLAGS += -DFXGMAC_ASPM_ENABLED
endif

ifeq (,$(filter OFF off, $(FXGMAC_USE_STATIC_ALLOC)))
	EXTRA_CFLAGS += -DFXGMAC_USE_STATIC_ALLOC
endif

yt6801-objs :=  fuxi-gmac-common.o fuxi-gmac-desc.o fuxi-gmac-ethtool.o fuxi-gmac-hw.o fuxi-gmac-net.o fuxi-gmac-pci.o fuxi-gmac-phy.o fuxi-efuse.o  fuxi-gmac-ioctl.o

BASEDIR := /lib/modules/$(shell uname -r)
KERNELDIR ?= $(BASEDIR)/build
PWD :=$(shell pwd)
DRIVERDIR := $(BASEDIR)/kernel/drivers/net/ethernet/motorcomm/yt6801

YTDIR := $(subst $(BASEDIR)/,,$(DRIVERDIR))

KERNEL_GCC_VERSION := $(shell cat /proc/version | sed -n 's/.*gcc version \([[:digit:]]\.[[:digit:]]\.[[:digit:]]\).*/\1/p')
CCVERSION = $(shell $(CC) -dumpversion)

KVER = $(shell uname -r)
KMAJ = $(shell echo $(KVER) | \
sed -e 's/^\([0-9][0-9]*\)\.[0-9][0-9]*\.[0-9][0-9]*.*/\1/')
KMIN = $(shell echo $(KVER) | \
sed -e 's/^[0-9][0-9]*\.\([0-9][0-9]*\)\.[0-9][0-9]*.*/\1/')
KREV = $(shell echo $(KVER) | \
sed -e 's/^[0-9][0-9]*\.[0-9][0-9]*\.\([0-9][0-9]*\).*/\1/')

kver_ge = $(shell \
echo test | awk '{if($(KMAJ) < $(1)) {print 0} else { \
if($(KMAJ) > $(1)) {print 1} else { \
if($(KMIN) < $(2)) {print 0} else { \
if($(KMIN) > $(2)) {print 1} else { \
if($(KREV) < $(3)) {print 0} else { print 1 } \
}}}}}' \
)


OS_NAME := $(shell grep '^NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')
ifneq (, $(findstring Kylin, $(OS_NAME)))
	SYS_TYPE := kylin
endif

.PHONY: all
all: print_vars clean modules

print_vars:
	@echo
	@echo "CC: " $(CC)
	@echo "CCVERSION: " $(CCVERSION)
	@echo "KERNEL_GCC_VERSION: " $(KERNEL_GCC_VERSION)
	@echo "KVER: " $(KVER)
	@echo "KMAJ: " $(KMAJ)
	@echo "KMIN: " $(KMIN)
	@echo "KREV: " $(KREV)
	@echo "BASEDIR: " $(BASEDIR)
	@echo "DRIVERDIR: " $(DRIVERDIR)
	@echo "PWD: " $(PWD)
	@echo "YTDIR: " $(YTDIR)
	@echo

.PHONY:modules
modules:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) modules
ifeq ($(SYS_TYPE),kylin)
	install -D ./motorcomm /usr/share/initramfs-tools/hooks/motorcomm
endif

.PHONY:clean
clean:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) clean
	@rm -f *.o
.PHONY:install
install:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) INSTALL_MOD_DIR=$(YTDIR) modules_install
	depmod -a


.PHONY:uninstall
uninstall:
	@rm -rf $(DRIVERDIR)
	depmod -a
