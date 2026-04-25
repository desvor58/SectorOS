[BITS 16]
[ORG 0x0000]

start:
    mov bx, 0x0F
    mov si, 0x7E00
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

    ; mov ah, 0x03
    ; mov bh, 0
    ; int 0x10

    ; mov dl, 13
    ; mov ah, 0x02
    ; int 0x10

    mov al, 0x0A
    int 0x10
    mov al, 0x0D
    int 0x10
    add si, 0x10
    jmp scan
done:
	retf
    
