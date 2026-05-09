[BITS 16]
[ORG 0x0000]

start:
	mov si, help
	mov bx, 0x0F
	call print
	retf

help db "shutdown - shuting down the pc", 10, 13
     db "reboot - rebooting the pc", 10, 13
     db "help - show this menu", 10, 13
     db "hello - gets hello from SectorOS", 10, 13
     db "dir - show files at current directory", 10, 13
     db "touch <file> [<type>] - creates file with <type> (E, F, or special)", 10, 13
     db "wrt <file> [<text>] - write <text> to file", 10, 13
     db "cat <file> - prints <file> text", 10, 13
     db "rdsd <sec> - prints disk <sec> data", 10, 13
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