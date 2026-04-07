# BasicForth — ARM64 Build
# Builds natively on ARM64 or cross-compiles from x86
#
# Build modes:
#   make              Safe build (stack/dict guards enabled)
#   make FAST=1       Fast build (guards disabled)

ARCH := $(shell uname -m)
ifeq ($(ARCH),aarch64)
    CROSS :=
else
    CROSS := aarch64-linux-gnu-
endif

AS      = $(CROSS)as
LD      = $(CROSS)ld
CC      = $(CROSS)gcc

ifdef FAST
ASFLAGS = --defsym FAST=1
endif

BIN     = basicforth
SRCS    = main.s core.s platform_linux.s
OBJS    = $(SRCS:.s=.o)

QEMU    = qemu-aarch64-static
BOARD   = p510
BOARD_DIR = ~/Dev/BasicForth/src/arch/arm64

TEST_DIR = ../../../tests
TEST_BIN = test_basicforth

.PHONY: all test unit-test deploy deploy-test deploy-all clean help

all: $(BIN)

%.o: %.s
	$(AS) $(ASFLAGS) -o $@ $<

$(BIN): $(OBJS)
	$(LD) -N -o $@ $(OBJS)

test: $(BIN)
	$(QEMU) $(BIN)

unit-test: $(TEST_BIN)
	$(QEMU) ./$(TEST_BIN)

$(TEST_BIN): core.o $(TEST_DIR)/test_basicforth.c $(TEST_DIR)/test_helper_arm64.s
	$(CC) -o $(TEST_BIN) $(TEST_DIR)/test_basicforth.c \
		$(TEST_DIR)/test_helper_arm64.s core.o -static

deploy: $(BIN)
	scp $(BIN) $(BOARD):$(BOARD_DIR)/

deploy-test: $(TEST_BIN)
	scp $(TEST_BIN) $(BOARD):$(BOARD_DIR)/

deploy-all: $(BIN) $(TEST_BIN)
	scp $(BIN) $(TEST_BIN) $(BOARD):$(BOARD_DIR)/

clean:
	rm -f $(OBJS) $(BIN) $(TEST_BIN)

help:
	@echo "BasicForth ARM64 Build"
	@echo ""
	@echo "  make              Build basicforth (safe mode, guards enabled)"
	@echo "  make FAST=1       Build basicforth (fast mode, guards disabled)"
	@echo ""
	@echo "  make test         Run basicforth (via QEMU or native)"
	@echo "  make unit-test    Run unit tests (C harness)"
	@echo "  make deploy       Deploy basicforth to Pumpkin board via SSH"
	@echo "  make deploy-test  Deploy test binary to Pumpkin board via SSH"
	@echo "  make deploy-all   Deploy both binaries to Pumpkin board via SSH"
	@echo "  make clean        Remove build artifacts"
	@echo "  make help         Show this help"
