[BITS 16]
[ORG 0x0000]

start:
    mov bx, 0x0F
    mov si, 0x0600
    xor ax, ax
    mov ds, ax

scan:
    cmp byte [si], 0
    jz done

    mov ah, 0x0E
    mov al, [si + 11]
    int 0x10

    mov al, 0x20
    int 0x10

    push si
        int 0x21
    pop si

    mov al, 0x0A
    int 0x10
    mov al, 0x0D
    int 0x10
    add si, 0x10
    jmp scan
done:
	retf
    
