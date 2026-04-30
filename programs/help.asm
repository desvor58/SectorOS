[BITS 16]
[ORG 0x0000]

start:
	mov si, help
	mov bx, 0x0F
	call print
	retf

help db "                                    SectorOS", 10, 13
     db "                                 Made by Desvor", 10, 13
     db "help - show this menu", 10, 13
     db "hello - gets hello from SectorOS", 10, 13
     db "dir - show files at current directory", 10, 13
     db 0

print:
    mov cx, 1
.put:
    lodsb
    test al, al
    jz .done
    cmp al, 0x20
    jl .ctrlC
    mov ah, 0x09
    int 0x10
.ctrlC:
    mov ah, 0x0E
    int 0x10
    jmp .put
.done:
    ret