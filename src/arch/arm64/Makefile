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

.PHONY: all build test run run-test run-integration run-pty clean help FORCE

# The binary reads core.fs at startup, so a build is not usable without a
# current copy of it beside the binary — which is why the default goal is
# `build` rather than the binary alone. The two are separate targets because
# the binary does not DEPEND on core.fs: making it a prerequisite would relink
# on every edit to a .fs file, and claim a relationship that does not exist.
.DEFAULT_GOAL := build
build: $(BIN) core-copy

# Dynamically linked (gcc, not ld) so the FFI can dlopen C libraries (SDL3).
# -nostartfiles keeps our own _start; ld.so still runs libc's initializers
# before jumping to it, which is what makes dlopen/dlsym usable. The
# dictionary is made executable at startup by mprotect (STC compiles machine
# code into it) — the old `ld -N` single-RWX-segment trick doesn't survive
# dynamic linking.
$(BIN): $(OBJS)
	$(CC) -nostartfiles -no-pie -o $@ $(OBJS) -ldl

main.o: main.s version.inc ../../config.inc

# Shared tunables: a size change must force a rebuild, or the guard pages and
# the stack they fence would be assembled from different numbers.
core.o: core.s ../../config.inc

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

# The build directory's core.fs is a COPY of the real one in src/forth (it is
# gitignored, and `clean` removes it). It used to be `cp ... 2>/dev/null ||
# true` inside five separate run targets: a plain `make` refreshed nothing, a
# failed copy said nothing, and two targets running at once could copy over
# the file the other was reading.
#
# Compared by CONTENT, not by timestamp, and checked on every build. A
# timestamp rule misses an edit made in the same clock tick as the previous
# copy — the kernel's coarse clock hands both files the identical mtime, and
# make reads "not older" as "up to date". Measured: two of three back-to-back
# edits were skipped that way. Scripts write files back to back; people do
# not, which is what makes it the kind of staleness you would chase for an
# hour. Same idiom as version.inc above, and a cmp of 180 KB costs nothing.
.PHONY: core-copy
core-copy:
	@cmp -s $(FORTH_DIR)/core.fs core.fs || cp $(FORTH_DIR)/core.fs core.fs

run: $(BIN) core-copy
	$(QEMU) ./$(BIN)

run-test: $(TEST_BIN)
	$(QEMU) ./$(TEST_BIN)

run-integration: $(BIN) core-copy
	$(TEST_DIR)/test_integration.sh $(QEMU) ./$(BIN)

run-pty: $(BIN) core-copy
	python3 $(TEST_DIR)/test_line_editor_pty.py $(QEMU) ./$(BIN)

run-lessons: $(BIN) core-copy
	python3 $(TEST_DIR)/test_lessons.py $(QEMU) ./$(BIN)

clean:
	rm -f $(OBJS) $(BIN) $(TEST_BIN) version.inc core.fs

help:
	@echo "BasicForth ARM64 Build"
	@echo ""
	@echo "  make                 Build basicforth (binary + its core.fs)"
	@echo "  make test            Build unit test (C harness)"
	@echo "  make all             Build basicforth and unit test"
	@echo "  make run             Run basicforth (native or via QEMU)"
	@echo "  make run-test        Run unit test (native or via QEMU)"
	@echo "  make run-integration Run integration tests"
	@echo "  make run-pty         Run line-editor PTY tests (scrolling)"
	@echo "  make run-lessons     Replay the docs/Tutorials lessons and examples"
	@echo "  make clean           Remove build artifacts"
	@echo "  make help            Show this help"
	@echo ""
	@echo "See deploy_template.sh for deploying to a remote board."
