[BITS 16]
[ORG 0x0000]

start:
    mov si, header
    mov bx, 0x07
    call print

    xor ax, ax
    mov ds, ax
    mov si, 0x60D

    cmp byte [si], 0
    jz .root

    mov dx, 0x4000
    int 0x21
    test ah, ah
    jnz err_fnf
    cmp al, 'D'
    jnz err_ind

    mov ax, 0x4000
    mov ds, ax
    xor si, si
    jmp .list

.root:
    mov si, 0x0800
    xor ax, ax
    mov ds, ax

.list:
    mov bx, 0x0F

    xor dx, dx

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

    push dx
        mov ah, 0x03
        xor bx, bx
        int 0x10
        push dx

        mov ax, [si + 14]
        call print_ax_dec

        mov ah, 0x03
        xor bx, bx
        int 0x10
        pop bx

        sub dx, bx
        mov cx, 5
        sub cx, dx

        mov ah, 0x0E
        mov al, '.'
        xor bx, bx
    print_pts:
        int 0x10
        loop print_pts
    pop dx

    mov ax, [si + 12]
    call print_ax_dec

    mov al, 0x0A
    int 0x10
    mov al, 0x0D
    int 0x10
    add si, 0x10
    inc dx
    jmp scan

done:
    mov ax, dx
    call print_ax_dec
    mov ah, 0x0E
    mov al, '/'
    int 0x10
    mov ax, 32
    call print_ax_dec
    mov al, 0x0A
    int 0x10
    mov al, 0x0D
    int 0x10
	retf

err_fnf:
    mov si, err_fnf_text
    mov bx, 0x04
    call print
    retf

err_ind:
    mov si, err_ind_text
    mov bx, 0x04
    call print
    retf


header db "NAME.......T..SZ...SC", 13, 10, 0
err_fnf_text db "File not found", 10, 13, 0
err_ind_text db "Its not dir", 10, 13, 0

%include "./programs/inc/sstd.inc"
USE_PRINT
USE_PRINT_AX_DEC
