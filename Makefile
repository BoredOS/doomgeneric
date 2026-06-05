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

CFLAGS  = -Wall -Wextra -std=gnu11 -ffreestanding -O2 -fno-stack-protector \
          -fno-stack-check -fno-lto -fno-pie -m64 -march=x86-64 -mno-red-zone \
          -isystem $(SDK_PATH)/include -Isrc -DNORMALUNIX -D_DEFAULT_SOURCE

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
ifdef BOOTSTRAP_SDK
	@if [ ! -f "$(BOOTSTRAP_SDK)/lib/libc.a" ]; then \
		if [ -d "../libc" ]; then \
			echo "[STANDALONE] Peer libc found at ../libc. Building standard SDK..."; \
			$(MAKE) -C ../libc SDK_DIR=$(BOOTSTRAP_SDK) install; \
		else \
			echo "[STANDALONE] SDK and peer libc not found. Fetching libc from GitHub..."; \
			mkdir -p build; \
			if [ ! -d "build/libc_src" ]; then \
				git clone https://github.com/boredos/libc.git build/libc_src; \
			fi; \
			$(MAKE) -C build/libc_src SDK_DIR=$(BOOTSTRAP_SDK) install; \
		fi \
	fi
endif
	@if [ ! -f "$(SDK_PATH)/include/novaproto.h" ]; then \
		if [ ! -d "../nova" ]; then \
			echo "Nova not found locally. Cloning from GitHub..."; \
			git clone https://github.com/boredos/nova.git ../nova; \
		fi; \
		echo "Exporting Nova SDK components..."; \
		$(MAKE) -C ../nova BOREDOS_SDK=$(SDK_PATH) export-sdk; \
	fi

# Compile C source files
obj/%.o: src/%.c | bootstrap-sdk
	@mkdir -p obj
	$(CC) $(CFLAGS) -c $< -o $@

# Link the userland executable
$(BINARY): $(OBJECTS)
	$(LD) $(LDFLAGS) $(SDK_PATH)/lib/crt0.o $(OBJECTS) -ltheme -lnovaproto -lui -lc -o $@

install: all
	mkdir -p $(DESTDIR)/bin
	cp $(BINARY) $(DESTDIR)/bin/
	@if [ -f freedoom1.wad ]; then \
		cp freedoom1.wad $(DESTDIR)/bin/doom1.wad; \
	fi

clean:
	rm -rf obj $(BINARY) build
