[BITS 16]
[ORG 0x0000]

start:
	mov si, msg
	mov bx, 0x0F
	call print
	retf

msg db "Hello world, from program", 10, 13, 0

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
