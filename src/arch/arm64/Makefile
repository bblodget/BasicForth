# BasicForth — ARM64 Build
# Builds natively on ARM64 or cross-compiles from x86

ARCH := $(shell uname -m)
ifeq ($(ARCH),aarch64)
    CROSS :=
else
    CROSS := aarch64-linux-gnu-
endif

AS      = $(CROSS)as
LD      = $(CROSS)ld

BIN     = basicforth
SRCS    = main.s core.s platform_linux.s
OBJS    = $(SRCS:.s=.o)

QEMU    = qemu-aarch64-static
BOARD   = p510
BOARD_DIR = ~/Dev/BasicForth/src/arch/arm64

.PHONY: all test deploy clean

all: $(BIN)

%.o: %.s
	$(AS) -o $@ $<

$(BIN): $(OBJS)
	$(LD) -o $@ $(OBJS)

test: $(BIN)
	$(QEMU) $(BIN)

deploy: $(BIN)
	scp $(BIN) $(BOARD):$(BOARD_DIR)/

clean:
	rm -f $(OBJS) $(BIN)
