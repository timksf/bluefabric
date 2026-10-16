#for BSVTools
ifndef BLUEFABRIC_MK_INCLUDED
BLUEFABRIC_MK_INCLUDED := 1

BLUEFABRIC_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BLUEFABRIC_SRC := $(BLUEFABRIC_ROOT)/src

# Prefer the project's library, falling back to the bundled dependency.
BLUEFABRIC_BLUEAXI_MK := $(firstword $(wildcard $(CURDIR)/libraries/*/BlueAXI.mk $(BLUEFABRIC_ROOT)/dep/blueaxi/BlueAXI.mk))
ifneq ($(BLUEFABRIC_BLUEAXI_MK),)
include $(BLUEFABRIC_BLUEAXI_MK)
endif

EXTRA_BSV_LIBS += $(BLUEFABRIC_SRC)
EXTRA_BSV_LIBS += $(wildcard $(BLUEFABRIC_SRC)/ahb)
EXTRA_BSV_LIBS += $(wildcard $(BLUEFABRIC_SRC)/axi)
EXTRA_BSV_LIBS += $(wildcard $(BLUEFABRIC_SRC)/apb)
EXTRA_BSV_LIBS += $(wildcard $(BLUEFABRIC_SRC)/axis)
EXTRA_BSV_LIBS += $(wildcard $(BLUEFABRIC_SRC)/common)
EXTRA_BSV_LIBS += $(wildcard $(BLUEFABRIC_SRC)/soc)

$(info Adding BlueFabric from $(BLUEFABRIC_SRC))

endif
