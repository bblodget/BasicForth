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
    QEMU := qemu-aarch64-static
endif

BIN     = basicforth
SRCS    = main.s core.s platform_linux.s
OBJS    = $(SRCS:.s=.o)

TEST_DIR = ../../../tests
TEST_BIN = test_basicforth

.PHONY: all test run run-test clean help

# Default: build binary only
$(BIN): $(OBJS)
	$(LD) -N -o $@ $(OBJS)

%.o: %.s
	$(AS) -o $@ $<

all: $(BIN) $(TEST_BIN)

test: $(TEST_BIN)

$(TEST_BIN): core.o $(TEST_DIR)/test_basicforth.c $(TEST_DIR)/test_helper_arm64.s
	$(CC) -o $(TEST_BIN) $(TEST_DIR)/test_basicforth.c \
		$(TEST_DIR)/test_helper_arm64.s core.o -static

run: $(BIN)
	$(QEMU) ./$(BIN)

run-test: $(TEST_BIN)
	$(QEMU) ./$(TEST_BIN)

clean:
	rm -f $(OBJS) $(BIN) $(TEST_BIN)

help:
	@echo "BasicForth ARM64 Build"
	@echo ""
	@echo "  make                 Build basicforth binary"
	@echo "  make test            Build unit test (C harness)"
	@echo "  make all             Build basicforth and unit test"
	@echo "  make run             Run basicforth (native or via QEMU)"
	@echo "  make run-test        Run unit test (native or via QEMU)"
	@echo "  make clean           Remove build artifacts"
	@echo "  make help            Show this help"
	@echo ""
	@echo "See deploy_template.sh for deploying to a remote board."
