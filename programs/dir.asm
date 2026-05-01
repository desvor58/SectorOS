[BITS 16]
[ORG 0x0000]

start:
    mov bx, 0x0F
    mov si, 0x0800
    xor ax, ax
    mov ds, ax

scan:
    cmp byte [si], 0
    jz done

    push si
        mov ah, 0x0E
        mov cx, 11
    print_lp:
        lodsb
        test al, al
        jz .its_zero
        int 0x10
        loop print_lp
        jmp .done

    .its_zero:
        mov al, '.'
        int 0x10
        loop print_lp
    .done:
    pop si

    mov al, [si + 11]
    int 0x10

    mov al, '.'
    int 0x10
    int 0x10

    mov ax, [si + 14]
    call print_ax_dec

    mov al, 0x0A
    int 0x10
    mov al, 0x0D
    int 0x10
    add si, 0x10
    jmp scan
done:
	retf
    
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

print_ax_dec:
    mov bx, 10
    xor cx, cx
.gc:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .gc
.put:
    pop ax
    add al, '0'
    mov ah, 0x0E
    int 0x10
    loop .put
    ret
