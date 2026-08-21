# BasicForth — Top-level Build
# Copyright (C) 2026 Brandon Blodget
# SPDX-License-Identifier: GPL-2.0-only
#
# Dispatches to architecture-specific Makefiles.

ARCH_DIRS = src/arch/arm64 src/arch/x86

HOST_ARCH := $(shell uname -m)
ifeq ($(HOST_ARCH),aarch64)
    NATIVE := arm64
else
    NATIVE := x86
endif

# Install location. PREFIX is where it goes; DESTDIR is the staging root a
# package build prepends without changing the paths compiled into anything —
# nothing is compiled in here, but packagers expect the knob and it costs one
# variable. `make install PREFIX=~/.local` needs no root.
PREFIX  ?= /usr/local
DESTDIR ?=

bindir   = $(DESTDIR)$(PREFIX)/bin
sharedir = $(DESTDIR)$(PREFIX)/share/basicforth

.PHONY: all arm64 x86 test test-arm64 test-x86 \
        run run-x86 run-arm64 \
        run-test run-test-x86 run-test-arm64 \
        run-integration run-integration-x86 run-integration-arm64 \
        run-pty run-pty-x86 run-pty-arm64 \
        install uninstall \
        clean help

# Default: build native architecture
$(NATIVE):

all: arm64 x86

arm64:
	$(MAKE) -C src/arch/arm64

x86:
	$(MAKE) -C src/arch/x86

test-x86:
	$(MAKE) -C src/arch/x86 test

test-arm64:
	$(MAKE) -C src/arch/arm64 test

run-x86:
	$(MAKE) -C src/arch/x86 run

run-arm64:
	$(MAKE) -C src/arch/arm64 run

run-test-x86:
	$(MAKE) -C src/arch/x86 run-test

run-test-arm64:
	$(MAKE) -C src/arch/arm64 run-test

test:
	$(MAKE) -C src/arch/$(NATIVE) test

run:
	$(MAKE) -C src/arch/$(NATIVE) run

run-test:
	$(MAKE) -C src/arch/$(NATIVE) run-test

run-integration-x86:
	$(MAKE) -C src/arch/x86 run-integration

run-integration-arm64:
	$(MAKE) -C src/arch/arm64 run-integration

run-integration:
	$(MAKE) -C src/arch/$(NATIVE) run-integration

run-pty-x86:
	$(MAKE) -C src/arch/x86 run-pty

run-pty-arm64:
	$(MAKE) -C src/arch/arm64 run-pty

run-pty:
	$(MAKE) -C src/arch/$(NATIVE) run-pty

run-lessons-x86:
	$(MAKE) -C src/arch/x86 run-lessons

run-lessons-arm64:
	$(MAKE) -C src/arch/arm64 run-lessons

run-lessons:
	$(MAKE) -C src/arch/$(NATIVE) run-lessons

# The layout here is not free-form: the binary derives BASICFORTH_PATH and
# BASICFORTH_DOCS from its own location as <prefix>/share/basicforth/{forth,
# examples,docs/...} when the environment does not set them (see
# derive_install_paths in main.s). Change one and the other must follow — the
# install test in tests/test_integration.sh checks the pair, so a drift shows
# up as a failure rather than as a silent "(BASICFORTH_DOCS not set)".
# ARCH defaults to this machine's. The integration suite overrides it so the
# ARM64 run installs the ARM64 binary it is actually testing, rather than
# whatever the host happens to be — otherwise the cross-compiled suite would
# quietly verify the x86 build twice and the ARM64 derivation never at all.
ARCH ?= $(NATIVE)

install: $(ARCH)
	install -d $(bindir) $(sharedir)/forth $(sharedir)/examples \
	           $(sharedir)/docs/Language-Reference \
	           $(sharedir)/docs/Tutorials $(sharedir)/docs/Guides
	install -m 755 src/arch/$(ARCH)/basicforth   $(bindir)/basicforth
	install -m 644 src/forth/*.fs                $(sharedir)/forth/
	install -m 644 examples/*                    $(sharedir)/examples/
	install -m 644 docs/Language-Reference/*.md  $(sharedir)/docs/Language-Reference/
	install -m 644 docs/Tutorials/*.md           $(sharedir)/docs/Tutorials/
	install -m 644 docs/Guides/*.md              $(sharedir)/docs/Guides/
	@echo
	@echo "Installed to $(DESTDIR)$(PREFIX):"
	@echo "  $(bindir)/basicforth"
	@echo "  $(sharedir)/{forth,examples,docs}"
	@echo
	@# Only worth saying when it is actually true. ~/.local/bin is the common
	@# case for a no-root install and is often absent from PATH, which turns a
	@# correct install into "command not found" with nothing pointing at why.
	@case ":$$PATH:" in \
	  *":$(PREFIX)/bin:"*) echo "Run 'basicforth' to start." ;; \
	  *) echo "$(PREFIX)/bin is not on your PATH. To fix it for new shells:" ; \
	     echo "    echo 'export PATH=\"$(PREFIX)/bin:\$$PATH\"' >> ~/.bashrc" ; \
	     echo "  or run it by full path: $(PREFIX)/bin/basicforth" ;; \
	esac

uninstall:
	rm -f $(bindir)/basicforth
	rm -rf $(sharedir)
	@echo "Removed $(bindir)/basicforth and $(sharedir)"

clean:
	@for dir in $(ARCH_DIRS); do $(MAKE) -C $$dir clean; done

help:
	@echo "BasicForth Build System"
	@echo ""
	@echo "Native architecture: $(NATIVE)"
	@echo ""
	@echo "Build:"
	@echo "  make                 Build basicforth for native arch ($(NATIVE))"
	@echo "  make all             Build all architectures"
	@echo "  make x86             Build x86-64 binary"
	@echo "  make arm64           Build ARM64 binary (cross-compile or native)"
	@echo "  make test            Build unit test for native arch"
	@echo "  make test-x86        Build x86-64 unit test"
	@echo "  make test-arm64      Build ARM64 unit test"
	@echo ""
	@echo "Run:"
	@echo "  make run             Run basicforth for native arch"
	@echo "  make run-x86         Run x86-64 binary interactively"
	@echo "  make run-arm64       Run ARM64 binary interactively"
	@echo "  make run-test        Run unit test for native arch"
	@echo "  make run-test-x86    Run x86-64 unit test"
	@echo "  make run-test-arm64  Run ARM64 unit test"
	@echo "  make run-integration Run integration tests for native arch"
	@echo "  make run-pty         Run line-editor PTY tests (scrolling) for native arch"
	@echo "  make run-lessons     Replay the docs/Tutorials lessons and examples"
	@echo ""
	@echo "Install:"
	@echo "  make install         Install to $(PREFIX) (override: PREFIX=~/.local)"
	@echo "  make uninstall       Remove an installation from $(PREFIX)"
	@echo ""
	@echo "Other:"
	@echo "  make clean           Remove build artifacts for all architectures"
	@echo "  make help            Show this help"
