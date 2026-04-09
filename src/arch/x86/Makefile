# BasicForth — x86-64 Build
# Copyright (C) 2026 Brandon Blodget
# SPDX-License-Identifier: GPL-2.0-only

AS      = as
LD      = ld
CC      = gcc

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

$(TEST_BIN): core.o $(TEST_DIR)/test_basicforth.c $(TEST_DIR)/test_helper_x86.s
	$(CC) -o $(TEST_BIN) $(TEST_DIR)/test_basicforth.c \
		$(TEST_DIR)/test_helper_x86.s core.o

run: $(BIN)
	./$(BIN)

run-test: $(TEST_BIN)
	./$(TEST_BIN)

clean:
	rm -f $(OBJS) $(BIN) $(TEST_BIN)

help:
	@echo "BasicForth x86-64 Build"
	@echo ""
	@echo "  make                  Build basicforth binary"
	@echo "  make test            Build unit test (C harness)"
	@echo "  make all              Build basicforth and unit test"
	@echo "  make run              Run basicforth interactively"
	@echo "  make run-test        Run unit test (C harness)"
	@echo "  make clean            Remove build artifacts"
	@echo "  make help             Show this help"
