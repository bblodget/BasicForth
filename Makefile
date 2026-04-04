# BasicForth — Top-level Build
# Dispatches to architecture-specific Makefiles

ARCH_DIRS = src/arch/arm64 src/arch/x86

.PHONY: all clean arm64 x86 test-arm64 test-x86 deploy

# Default: build all architectures
all: arm64 x86

arm64:
	$(MAKE) -C src/arch/arm64

x86:
	$(MAKE) -C src/arch/x86

test-arm64:
	$(MAKE) -C src/arch/arm64 test

test-x86:
	$(MAKE) -C src/arch/x86 test

deploy:
	$(MAKE) -C src/arch/arm64 deploy

clean:
	@for dir in $(ARCH_DIRS); do $(MAKE) -C $$dir clean; done
