# BasicForth — Top-level Build
# Dispatches to architecture-specific Makefiles

ARCH_DIRS = src/arch/arm64 src/arch/x86

.PHONY: all clean arm64 x86 test-arm64 test-x86 unit-test-arm64 unit-test-x86 deploy help

# Default: build all architectures
all: arm64 x86

help:
	@echo "BasicForth Build System"
	@echo ""
	@echo "Build:"
	@echo "  make              Build all architectures"
	@echo "  make x86          Build x86-64 binary"
	@echo "  make arm64        Build ARM64 binary (cross-compile or native)"
	@echo ""
	@echo "Run:"
	@echo "  make test-x86     Run x86-64 binary"
	@echo "  make test-arm64   Run ARM64 binary (via QEMU or native)"
	@echo ""
	@echo "Unit Tests:"
	@echo "  make unit-test-x86    Run x86-64 unit tests"
	@echo "  make unit-test-arm64  Run ARM64 unit tests (requires gcc-aarch64-linux-gnu)"
	@echo ""
	@echo "Deploy:"
	@echo "  make deploy       Deploy ARM64 binary to Pumpkin board via SSH"
	@echo ""
	@echo "Other:"
	@echo "  make clean        Remove build artifacts for all architectures"
	@echo "  make help         Show this help"

arm64:
	$(MAKE) -C src/arch/arm64

x86:
	$(MAKE) -C src/arch/x86

test-arm64:
	$(MAKE) -C src/arch/arm64 test

test-x86:
	$(MAKE) -C src/arch/x86 test

unit-test-x86:
	$(MAKE) -C src/arch/x86 unit-test

unit-test-arm64:
	$(MAKE) -C src/arch/arm64 unit-test

deploy:
	$(MAKE) -C src/arch/arm64 deploy

clean:
	@for dir in $(ARCH_DIRS); do $(MAKE) -C $$dir clean; done
