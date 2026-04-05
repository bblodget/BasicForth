# BasicForth — x86-64 Build

AS      = as
LD      = ld
CC      = gcc

BIN     = basicforth
SRCS    = main.s core.s platform_linux.s
OBJS    = $(SRCS:.s=.o)

TEST_DIR = ../../../tests
TEST_BIN = test_basicforth

.PHONY: all test unit-test clean help

all: $(BIN)

%.o: %.s
	$(AS) -o $@ $<

$(BIN): $(OBJS)
	$(LD) -o $@ $(OBJS)

test: $(BIN)
	./$(BIN)

$(TEST_BIN): core.o $(TEST_DIR)/test_basicforth.c $(TEST_DIR)/test_helper_x86.s
	$(CC) -o $(TEST_BIN) $(TEST_DIR)/test_basicforth.c \
		$(TEST_DIR)/test_helper_x86.s core.o

unit-test: $(TEST_BIN)
	./$(TEST_BIN)

clean:
	rm -f $(OBJS) $(BIN) $(TEST_BIN)

help:
	@echo "BasicForth x86-64 Build"
	@echo ""
	@echo "  make              Build basicforth binary"
	@echo "  make test         Run basicforth interactively"
	@echo "  make unit-test    Run unit tests (C harness)"
	@echo "  make clean        Remove build artifacts"
	@echo "  make help         Show this help"
