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

BIN     = basicforth
SRCS    = main.s core.s platform_linux.s
OBJS    = $(SRCS:.s=.o)

TEST_DIR = ../../../tests
TEST_BIN = test_basicforth

.PHONY: all tests run run-tests clean help

# Default: build binary only
$(BIN): $(OBJS)
	$(LD) -N -o $@ $(OBJS)

%.o: %.s
	$(AS) -o $@ $<

all: $(BIN) $(TEST_BIN)

tests: $(TEST_BIN)

$(TEST_BIN): core.o $(TEST_DIR)/test_basicforth.c $(TEST_DIR)/test_helper_arm64.s
	$(CC) -o $(TEST_BIN) $(TEST_DIR)/test_basicforth.c \
		$(TEST_DIR)/test_helper_arm64.s core.o -static

run: $(BIN)
	./$(BIN)

run-tests: $(TEST_BIN)
	./$(TEST_BIN)

clean:
	rm -f $(OBJS) $(BIN) $(TEST_BIN)

help:
	@echo "BasicForth ARM64 Build"
	@echo ""
	@echo "  make                  Build basicforth binary"
	@echo "  make tests            Build unit tests (C harness)"
	@echo "  make all              Build basicforth and unit tests"
	@echo "  make run              Run basicforth interactively"
	@echo "  make run-tests        Run unit tests (C harness)"
	@echo "  make clean            Remove build artifacts"
	@echo "  make help             Show this help"
	@echo ""
	@echo "See deploy_template.sh for deploying to a remote board."
