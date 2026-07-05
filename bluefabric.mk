#for BSVTools
MAKEPATH := $(dir $(lastword $(MAKEFILE_LIST)))
MODULENAME := BlueFabric
MODULEPATH := $(MAKEPATH)src
EXTRA_BSV_LIBS += $(MODULEPATH)

$(info Adding $(MODULENAME) from $(MODULEPATH))