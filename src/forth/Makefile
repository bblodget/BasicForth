# PumpkinForth — Phase 2: Forth Core
# Builds natively on ARM64 or cross-compiles from x86

ARCH := $(shell uname -m)
ifeq ($(ARCH),aarch64)
    CROSS :=
else
    CROSS := aarch64-linux-gnu-
endif

AS      = $(CROSS)as
LD      = $(CROSS)ld

BIN     = pumpkinforth
SRCS    = main.s core.s platform_linux.s
OBJS    = $(SRCS:.s=.o)

QEMU    = qemu-aarch64-static
BOARD   = p510

.PHONY: all test deploy clean help

all: $(BIN)

%.o: %.s
	$(AS) -o $@ $<

$(BIN): $(OBJS)
	$(LD) -o $@ $(OBJS)

test: $(BIN)
	$(QEMU) $(BIN)

BOARD_DIR = /home/pk/Dev/PumpkinForth/src/forth

deploy: $(BIN)
	scp $(BIN) $(BOARD):$(BOARD_DIR)/

help:
	@echo "Targets:"
	@echo "  all      Build pumpkinforth (default)"
	@echo "  test     Build and run with QEMU"
	@echo "  deploy   Build and copy to board"
	@echo "  clean    Remove build artifacts"
	@echo "  help     Show this help"

clean:
	rm -f $(OBJS) $(BIN)
