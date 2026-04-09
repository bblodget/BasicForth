# BasicForth — Top-level Build
# Copyright (C) 2026 Brandon Blodget
# SPDX-License-Identifier: GPL-2.0-only
#
# Dispatches to architecture-specific Makefiles.

ARCH_DIRS = src/arch/arm64 src/arch/x86

HOST_ARCH := $(shell uname -m)
ifeq ($(HOST_ARCH),aarch64)
    NATIVE := arm64
else
    NATIVE := x86
endif

.PHONY: all arm64 x86 test test-arm64 test-x86 \
        run run-x86 run-arm64 \
        run-test run-test-x86 run-test-arm64 \
        run-integration run-integration-x86 run-integration-arm64 \
        clean help

# Default: build native architecture
$(NATIVE):

all: arm64 x86

arm64:
	$(MAKE) -C src/arch/arm64

x86:
	$(MAKE) -C src/arch/x86

test-x86:
	$(MAKE) -C src/arch/x86 test

test-arm64:
	$(MAKE) -C src/arch/arm64 test

run-x86:
	$(MAKE) -C src/arch/x86 run

run-arm64:
	$(MAKE) -C src/arch/arm64 run

run-test-x86:
	$(MAKE) -C src/arch/x86 run-test

run-test-arm64:
	$(MAKE) -C src/arch/arm64 run-test

test:
	$(MAKE) -C src/arch/$(NATIVE) test

run:
	$(MAKE) -C src/arch/$(NATIVE) run

run-test:
	$(MAKE) -C src/arch/$(NATIVE) run-test

run-integration-x86:
	$(MAKE) -C src/arch/x86 run-integration

run-integration-arm64:
	$(MAKE) -C src/arch/arm64 run-integration

run-integration:
	$(MAKE) -C src/arch/$(NATIVE) run-integration

clean:
	@for dir in $(ARCH_DIRS); do $(MAKE) -C $$dir clean; done

help:
	@echo "BasicForth Build System"
	@echo ""
	@echo "Native architecture: $(NATIVE)"
	@echo ""
	@echo "Build:"
	@echo "  make                 Build basicforth for native arch ($(NATIVE))"
	@echo "  make all             Build all architectures"
	@echo "  make x86             Build x86-64 binary"
	@echo "  make arm64           Build ARM64 binary (cross-compile or native)"
	@echo "  make test            Build unit test for native arch"
	@echo "  make test-x86        Build x86-64 unit test"
	@echo "  make test-arm64      Build ARM64 unit test"
	@echo ""
	@echo "Run:"
	@echo "  make run             Run basicforth for native arch"
	@echo "  make run-x86         Run x86-64 binary interactively"
	@echo "  make run-arm64       Run ARM64 binary interactively"
	@echo "  make run-test        Run unit test for native arch"
	@echo "  make run-test-x86    Run x86-64 unit test"
	@echo "  make run-test-arm64  Run ARM64 unit test"
	@echo "  make run-integration Run integration tests for native arch"
	@echo ""
	@echo "Other:"
	@echo "  make clean           Remove build artifacts for all architectures"
	@echo "  make help            Show this help"
