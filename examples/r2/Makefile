AHOLYC ?= ../../aholyc
PKG_CONFIG ?= pkg-config

R2_LIBEXT := $(shell r2 -H R2_LIBEXT)
PLUGIN := core_aholyc.$(R2_LIBEXT)
R2_VERSION := $(shell r2 -H R2_VERSION)
R2_INCLUDEDIR := $(shell $(PKG_CONFIG) --variable=includedir r_core)
R2_ABIVERSION := $(shell r2 -H R2_ABIVERSION)
R2_LIBS := $(shell $(PKG_CONFIG) --libs r_core)

all: $(PLUGIN)

$(PLUGIN): core_aholyc.HC r2.hc
	$(AHOLYC) -shared -fno-exceptions \
		-D R2_VERSION='"$(R2_VERSION)"' \
		-D R2_ABIVERSION=$(R2_ABIVERSION) \
		$< $(R2_LIBS) -o $@

clean:
	$(RM) $(PLUGIN)

.PHONY: all clean
