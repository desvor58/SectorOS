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

all: disk

sos.bin: sos.asm
	nasm -f bin -o sos.bin sos.asm

$(BINS): %.bin: programs/%.asm init
	nasm -f bin -o bin/$@ $<

disk: sos.bin $(BINS)
	python3 mkfs.py disk_example.sfsd disk.img

run: all
	qemu-system-i386 -drive format=raw,file=disk.img

dbg: all
	qemu-system-i386 -drive format=raw,file=disk.img -monitor stdio
	
clean:
	-$(CLEAN_CMD) *.img
	-cd bin
	-$(CLEAN_CMD) *.bin
	-cd ..

init:
	-mkdir bin
