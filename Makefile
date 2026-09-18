PROGRAMS := hello     \
			help      \
			dir       \
			memd      \
			rdsd      \
			cat       \
			shutdown  \
			reboot    \
			touch	  \
			wrt	      \
			del 	  \
			cd        \
			sterm	  

BINS := $(addsuffix .bin, $(PROGRAMS))

ifeq ($(OS),Windows_NT)
    CLEAN_CMD := del /q
else
    CLEAN_CMD := rm -f
endif

.PHONY: clear init

FUSE_PKG := fuse3
FUSE_CFLAGS := $(shell pkg-config --cflags $(FUSE_PKG) 2>/dev/null)
FUSE_LIBS := $(shell pkg-config --libs $(FUSE_PKG) 2>/dev/null)
FUSE_DEV := /tmp/opencode/fuse3dev
ifneq ($(strip $(FUSE_CFLAGS)),)
FUSE_CFLAGS := $(FUSE_CFLAGS) -pthread
FUSE_LIBS := $(FUSE_LIBS) -lpthread
else ifeq ($(wildcard $(FUSE_DEV)/usr/include/fuse3/fuse.h),$(FUSE_DEV)/usr/include/fuse3/fuse.h)
FUSE_CFLAGS := -I$(FUSE_DEV)/usr/include -pthread
FUSE_LIBS := -L$(FUSE_DEV)/usr/lib64 -lfuse3 -lpthread
endif

all: disk

sfsmount: sfsmount.c
	gcc -Wall -Wextra -O2 -o sfsmount sfsmount.c $(FUSE_CFLAGS) $(FUSE_LIBS)
ifeq ($(strip $(FUSE_CFLAGS)),)
	@echo 'error: fuse3 develop files not found (install fuse3-devel or extract headers to $(FUSE_DEV))'
endif

sos.bin: sos.asm
	nasm -f bin -o sos.bin sos.asm

$(BINS): %.bin: programs/%.asm init
	nasm -f bin -o bin/$@ $<

disk: sos.bin $(BINS)
	python3 mkfs.py disk_example.sfsd disk.img

run: all
	qemu-system-i386 -drive format=raw,file=disk.img

dbg: all
	qemu-system-i386 -drive format=raw,file=disk.img -s -S

gdb:
	gdb --ex "set architecture i8086" --ex "target remote localhost:1234"
	
clean:
	-$(CLEAN_CMD) *.img
	-cd bin
	-$(CLEAN_CMD) *.bin
	-cd ..

init:
	-mkdir bin
