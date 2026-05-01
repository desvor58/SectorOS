[BITS 16]
[ORG 0x0000]

shutdown:
    mov ax, 0x5301
    xor bx, bx
    int 0x15
    jc .err

    mov ax, 0x530E
    xor bx, bx
    mov cx, 0x0102
    int 0x15

    mov ax, 0x5308
    mov bx, 0x0001
    mov cx, 0x0001
    int 0x15

    mov ax, 0x5307
    mov bx, 0x0001
    mov cx, 0x0003
    int 0x15

.err:
    ret                 