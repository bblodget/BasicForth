# BasicForth — ARM64 Build
# Copyright (C) 2026 Brandon Blodget
# SPDX-License-Identifier: GPL-2.0-only
#
# Builds natively on ARM64 or cross-compiles from x86.

ARCH := $(shell uname -m)
ifeq ($(ARCH),aarch64)
    CROSS :=
else
    CROSS := aarch64-linux-gnu-
endif

AS      = $(CROSS)as
LD      = $(CROSS)ld
CC      = $(CROSS)gcc

ifeq ($(ARCH),aarch64)
    QEMU :=
else
    # -L: the dynamically-linked binary needs the aarch64 ld.so + libc
    QEMU := qemu-aarch64-static -L /usr/aarch64-linux-gnu
endif

VERSION := $(shell git -C $(CURDIR)/../../.. describe --tags --dirty 2>/dev/null || echo "unknown")

BIN     = basicforth
SRCS    = main.s core.s platform_linux.s
OBJS    = $(SRCS:.s=.o)

TEST_DIR = ../../../tests
TEST_BIN = test_basicforth

.PHONY: all test run run-test run-integration run-pty clean help FORCE

# Default: build binary only.
# Dynamically linked (gcc, not ld) so the FFI can dlopen C libraries (SDL3).
# -nostartfiles keeps our own _start; ld.so still runs libc's initializers
# before jumping to it, which is what makes dlopen/dlsym usable. The
# dictionary is made executable at startup by mprotect (STC compiles machine
# code into it) — the old `ld -N` single-RWX-segment trick doesn't survive
# dynamic linking.
$(BIN): $(OBJS)
	$(CC) -nostartfiles -no-pie -o $@ $(OBJS) -ldl

main.o: main.s version.inc

%.o: %.s
	$(AS) -o $@ $<

# Generate version include file (rebuilt every time, only updates if changed)
version.inc: FORCE
	@printf '.section .rodata\nversion_str: .ascii "*** BasicForth %s (Linux/ARM64) ***\\n"\n.equ version_len, . - version_str\n.text\n' "$(VERSION)" > $@.tmp
	@cmp -s $@.tmp $@ 2>/dev/null || mv $@.tmp $@
	@rm -f $@.tmp
FORCE:

all: $(BIN) $(TEST_BIN)

test: $(TEST_BIN)

$(TEST_BIN): core.o $(TEST_DIR)/test_basicforth.c $(TEST_DIR)/test_helper_arm64.s
	$(CC) -o $(TEST_BIN) $(TEST_DIR)/test_basicforth.c \
		$(TEST_DIR)/test_helper_arm64.s core.o -static

FORTH_DIR = ../../forth

run: $(BIN)
	cp $(FORTH_DIR)/core.fs . 2>/dev/null || true
	$(QEMU) ./$(BIN)

run-test: $(TEST_BIN)
	$(QEMU) ./$(TEST_BIN)

run-integration: $(BIN)
	cp $(FORTH_DIR)/core.fs . 2>/dev/null || true
	$(TEST_DIR)/test_integration.sh $(QEMU) ./$(BIN)

run-pty: $(BIN)
	cp $(FORTH_DIR)/core.fs . 2>/dev/null || true
	python3 $(TEST_DIR)/test_line_editor_pty.py $(QEMU) ./$(BIN)

clean:
	rm -f $(OBJS) $(BIN) $(TEST_BIN) version.inc core.fs

help:
	@echo "BasicForth ARM64 Build"
	@echo ""
	@echo "  make                 Build basicforth binary"
	@echo "  make test            Build unit test (C harness)"
	@echo "  make all             Build basicforth and unit test"
	@echo "  make run             Run basicforth (native or via QEMU)"
	@echo "  make run-test        Run unit test (native or via QEMU)"
	@echo "  make run-integration Run integration tests"
	@echo "  make clean           Remove build artifacts"
	@echo "  make help            Show this help"
	@echo ""
	@echo "See deploy_template.sh for deploying to a remote board."
