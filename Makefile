PROGRAMS := hello     \
			help      \
			dir       \
			memd      \
			cat       \
			shutdown  \
			reboot    

BINS := $(addsuffix .bin, $(PROGRAMS))

ifeq ($(OS),Windows_NT)
    CLEAN_CMD := del /q
else
    CLEAN_CMD := rm -f
endif

all: disk

sos.bin: sos.asm
	nasm -f bin -o sos.bin sos.asm

$(BINS): %.bin: programs/%.asm
	nasm -f bin -o $@ $<

disk: sos.bin $(BINS)
	python3 mkfs.py disk_example.sfsd disk.img

run: all
	qemu-system-x86_64 -drive format=raw,file=disk.img

.PHONY: clear
clear:
	$(CLEAN_CMD) *.img
	$(CLEAN_CMD) *.bin