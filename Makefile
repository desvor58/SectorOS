PROGRAMS := hello

ifeq ($(OS),Windows_NT)
    CLEAN_CMD := del /q
else
    CLEAN_CMD := rm -rf
endif


all: sos $(PROGRAMS) disk

sos:
	nasm -f bin -o sos.bin sos.asm

$(PROGRAMS): programs/$(PROGRAMS).asm
	nasm -f bin -o $@.bin $<

disk:
	python3 mkfs.py disk_example.sfsd disk.img

run: all
	qemu-system-x86_64 -drive format=raw,file=disk.img

.PHONY: clear
clear:
	$(CLEAN_CMD) *.img
	$(CLEAN_CMD) *.bin
