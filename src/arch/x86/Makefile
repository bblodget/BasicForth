# BasicForth — x86-64 Build

AS      = as
LD      = ld

BIN     = basicforth
SRCS    = main.s core.s platform_linux.s
OBJS    = $(SRCS:.s=.o)

.PHONY: all test clean

all: $(BIN)

%.o: %.s
	$(AS) -o $@ $<

$(BIN): $(OBJS)
	$(LD) -o $@ $(OBJS)

test: $(BIN)
	./$(BIN)

clean:
	rm -f $(OBJS) $(BIN)
