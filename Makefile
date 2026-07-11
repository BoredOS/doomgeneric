# Copyright (c) 2026 Christiaan (chris@boreddev.nl)
# BoredOS doomgeneric Makefile

CC = x86_64-elf-gcc
LD = x86_64-elf-ld

# Smart SDK Resolution Logic
ifneq ($(BOREDOS_SDK),)
  ifeq ($(wildcard $(BOREDOS_SDK)/lib/libc.a),)
    BOOTSTRAP_SDK = $(BOREDOS_SDK)
    SDK_PATH      = $(BOREDOS_SDK)
  else
    SDK_PATH      = $(BOREDOS_SDK)
  endif
endif

# If SDK is still unresolved, fall back to a local standalone build folder
ifeq ($(SDK_PATH),)
  SDK_PATH = $(abspath build/sdk)
  ifeq ($(wildcard $(SDK_PATH)/lib/libc.a),)
    BOOTSTRAP_SDK = $(SDK_PATH)
  endif
endif

DESTDIR ?= $(abspath build/dist)

GCC_INTERNAL_INCLUDE := $(shell $(CC) -print-file-name=include)

CFLAGS  = -Wall -Wextra -std=gnu11 -ffreestanding -O2 -fno-stack-protector \
          -fno-stack-check -fno-lto -fno-pie -m64 -march=x86-64 -mno-red-zone \
          -nostdinc -isystem $(GCC_INTERNAL_INCLUDE) -isystem $(SDK_PATH)/include -Isrc -DNORMALUNIX -D_DEFAULT_SOURCE

LDFLAGS = -m elf_x86_64 -nostdlib -static -no-pie -Ttext=0x40000000 \
          --no-dynamic-linker -z text -z max-page-size=0x1000 -e _start \
          -L$(SDK_PATH)/lib

# Core Doom source files + Platform port file
SOURCES = $(wildcard src/*.c)
OBJECTS = $(SOURCES:src/%.c=obj/%.o)
BINARY = doom.elf

all: bootstrap-sdk $(BINARY)

# Autonomic SDK Bootstrapper
.PHONY: bootstrap-sdk
bootstrap-sdk:
	@if [ ! -f "$(SDK_PATH)/include/novaproto.h" ]; then \
		if [ -d "../nova" ]; then \
			echo "Exporting Nova SDK components..."; \
			$(MAKE) -C ../nova BOREDOS_SDK=$(SDK_PATH) export-sdk; \
		fi \
	fi

# Compile C source files
obj/%.o: src/%.c | bootstrap-sdk
	@mkdir -p obj
	$(CC) $(CFLAGS) -c $< -o $@

# Link the userland executable
$(BINARY): $(OBJECTS)
	$(LD) $(LDFLAGS) $(SDK_PATH)/lib/crt0.o $(SDK_PATH)/lib/crti.o $(OBJECTS) -lnovaproto -lc $(SDK_PATH)/lib/crtn.o -o $@

install: all
	mkdir -p $(DESTDIR)/bin
	cp $(BINARY) $(DESTDIR)/bin/
	mkdir -p $(DESTDIR)/Library/AppData/org.boredos.doomgeneric
	@if [ -f freedoom1.wad ]; then \
		cp freedoom1.wad $(DESTDIR)/Library/AppData/org.boredos.doomgeneric/doom1.wad; \
	fi
	@if [ -f pack/assets/doom.png ]; then \
		cp pack/assets/doom.png $(DESTDIR)/Library/AppData/org.boredos.doomgeneric/doomgeneric.png; \
	fi
	@if [ -d pack/apps ]; then \
		cp -a pack/apps/*.desktop $(DESTDIR)/Library/AppData/org.boredos.doomgeneric/; \
	fi


.PHONY: bup
bup: all
	rm -rf build/package
	mkdir -p build/package/bin build/package/assets build/package/usr/share/applications
	cp $(BINARY) build/package/bin/
	@if [ -f freedoom1.wad ]; then cp freedoom1.wad build/package/assets/freedoom1.wad; fi
	# Include any packaged assets (icons) from pack/assets
	if [ -f pack/assets/doom.png ]; then \
		cp pack/assets/doom.png build/package/assets/doomgeneric.png; \
	fi
	# Include any application desktop entries from pack/apps (if present)
	if [ -d pack/apps ]; then \
		cp -a pack/apps/*.desktop build/package/usr/share/applications/; \
	fi
	# Use pack/MANIFEST.toml if provided, otherwise generate a minimal manifest
	if [ -f pack/MANIFEST.toml ]; then \
		cp pack/MANIFEST.toml build/package/MANIFEST.toml; \
	else \
		@echo 'name = "doomgeneric"' > build/package/MANIFEST.toml; \
		@echo 'version = "1.0.0"' >> build/package/MANIFEST.toml; \
		@echo '[install]' >> build/package/MANIFEST.toml; \
		@echo 'bin = "/bin"' >> build/package/MANIFEST.toml; \
		@echo 'assets = "/Library/AppData/org.boredos.doomgeneric"' >> build/package/MANIFEST.toml; \
	fi
	x86_64-elf-strip --strip-unneeded build/package/bin/*.elf 2>/dev/null || true
	tar -cf build/doomgeneric.tar -C build/package MANIFEST.toml bin assets usr
	lz4 -f build/doomgeneric.tar build/doomgeneric.bup
	rm -f build/doomgeneric.tar
	rm -rf build/package

clean:
	rm -rf obj $(BINARY) build
