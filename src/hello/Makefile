# PumpkinForth — Lesson 1: Hello World
# Builds natively on ARM64 or cross-compiles from x86

# Detect host architecture and set tool prefix
ARCH := $(shell uname -m)
ifeq ($(ARCH),aarch64)
    CROSS :=
else
    CROSS := aarch64-linux-gnu-
endif

AS      = $(CROSS)as
LD      = $(CROSS)ld

BIN     = hello

QEMU    = qemu-aarch64-static
BOARD   = p510

.PHONY: all test deploy clean help

all: $(BIN)

hello.o: hello.s
	$(AS) -o $@ $<

$(BIN): hello.o
	$(LD) -o $@ $<

test: $(BIN)
	$(QEMU) $(BIN)

deploy: $(BIN)
	scp $(BIN) $(BOARD):~/

help:
	@echo "Targets:"
	@echo "  all      Build hello (default)"
	@echo "  test     Build and run with QEMU"
	@echo "  deploy   Build, copy to board, and run"
	@echo "  clean    Remove build artifacts"
	@echo "  help     Show this help"

clean:
	rm -f hello.o $(BIN)
