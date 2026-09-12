[BITS 16]
[ORG 0x0000]

sterm:
shell_loop:
    push ds
    push es

    xor ax, ax
    mov es, ax
    mov di, 0x500

    mov cx, 0x100
    push di
        rep stosb
    pop di

    xor cx, cx

.read_char:
    xor ah, ah
    int 0x16

    cmp al, 0x0D
    jz .done

    cmp al, 0x08
    jz .backspace

    stosb
    mov ah, 0x0E
    int 0x10

    inc cx
    jmp .read_char

.backspace:
    test cx, cx
    jz .read_char

    mov ah, 0x0E
    int 0x10

    mov al, ' '
    int 0x10

    mov al, 0x08
    int 0x10

    dec di
    dec cx
    jmp .read_char

.done:
    mov byte [di], 0
    
    mov ax, 0x0E0A
    int 0x10
    mov al, 0x0D
    int 0x10

    push ds
    pop es
    xor ax, ax
    mov ds, ax

    mov si, 0x500
    mov di, prog
    mov cx, 11
.get_prog_loop:
    jcxz .get_prog_done

    lodsb
    cmp al, ' '
    jbe .get_prog_done

    stosb
    dec cx
    jmp .get_prog_loop

.get_prog_done:
    xor ax, ax
    rep stosb

    push es
    pop ds

    mov si, prog
    mov dx, 0x3000
    int 0x21

    cmp ah, 1
    jz err_fnf
    cmp ah, 2
    jz err_de
    ja err_ind
    cmp al, 'E'
    jnz err_wft

    mov ax, 0x3000
    mov ds, ax
    mov es, ax
    call 0x3000:0x0000

    jmp goto_shell_loop

err_fnf:
    mov si, err_fnf_text
    jmp general_err

err_de:
    mov si, err_de_text
    jmp general_err

err_ind:
    mov si, err_ind_text
    jmp general_err

err_wft:
    mov si, err_wft_text

general_err:
    mov bx, 0x04
    call print

goto_shell_loop:
    pop es
    pop ds
    jmp shell_loop

prog resb 11

err_fnf_text db "File not found", 10, 13, 0
err_de_text db "Disk error", 10, 13, 0
err_wft_text db "Wrong file type", 10, 13, 0
err_ind_text db "Its not dir", 10, 13, 0

%include "./programs/inc/sstd.inc"
USE_PRINT
