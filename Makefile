# BasicForth — Top-level Build
# Copyright (C) 2026 Brandon Blodget
# SPDX-License-Identifier: GPL-2.0-only
#
# Dispatches to architecture-specific Makefiles.

ARCH_DIRS = src/arch/arm64 src/arch/x86

.PHONY: all arm64 x86 tests-arm64 tests-x86 run-x86 run-arm64 \
        run-tests-x86 run-tests-arm64 clean help

# Default: build both architectures
all: arm64 x86

arm64:
	$(MAKE) -C src/arch/arm64

x86:
	$(MAKE) -C src/arch/x86

tests-x86:
	$(MAKE) -C src/arch/x86 tests

tests-arm64:
	$(MAKE) -C src/arch/arm64 tests

run-x86:
	$(MAKE) -C src/arch/x86 run

run-arm64:
	$(MAKE) -C src/arch/arm64 run

run-tests-x86:
	$(MAKE) -C src/arch/x86 run-tests

run-tests-arm64:
	$(MAKE) -C src/arch/arm64 run-tests

clean:
	@for dir in $(ARCH_DIRS); do $(MAKE) -C $$dir clean; done

help:
	@echo "BasicForth Build System"
	@echo ""
	@echo "Build:"
	@echo "  make                  Build all architectures"
	@echo "  make x86              Build x86-64 binary"
	@echo "  make arm64            Build ARM64 binary (cross-compile or native)"
	@echo "  make tests-x86        Build x86-64 unit tests"
	@echo "  make tests-arm64      Build ARM64 unit tests"
	@echo ""
	@echo "Run:"
	@echo "  make run-x86          Run x86-64 binary interactively"
	@echo "  make run-arm64        Run ARM64 binary interactively"
	@echo "  make run-tests-x86    Run x86-64 unit tests"
	@echo "  make run-tests-arm64  Run ARM64 unit tests"
	@echo ""
	@echo "Other:"
	@echo "  make clean            Remove build artifacts for all architectures"
	@echo "  make help             Show this help"
