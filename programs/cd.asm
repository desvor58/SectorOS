[BITS 16]
[ORG 0x0000]

start:
    xor ax, ax
    mov ds, ax
    mov si, 0x500

skip_pn_loop:
    lodsb
    test al, al
    jz cd_root
    cmp al, ' '
    jz to_args_loop
    jmp skip_pn_loop

to_args_loop:
    lodsb
    cmp al, ' '
    jnz args_done
    jmp to_args_loop

args_done:
    mov di, dir
    dec si
arg_cpy:
    lodsb
    test al, al
    jz arg_cpy_done
    cmp al, ' '
    jz arg_cpy_done
    stosb
    jmp arg_cpy

arg_cpy_done:
    mov ax, es
    mov ds, ax
    mov si, dir
    int 0x23
    cmp al, 1
    jz err_fnf
    cmp al, 2
    jz err_de
    ja err_ind

    xor ax, ax
    mov es, ax
    mov di, 0x60D
    mov si, dir
    mov cx, 60
    rep movsb
    retf

err_fnf:
    mov si, err_fnf_text
    mov bx, 0x04
    call print
    retf

err_de:
    mov si, err_de_text
    mov bx, 0x04
    call print
    retf

err_ind:
    mov si, err_ind_text
    mov bx, 0x04
    call print
    retf

cd_root:
    xor ax, ax
    mov cx, 60
    mov es, ax
    mov di, 0x60D
    rep stosb
    retf

dir resb 60

err_fnf_text db "File not found", 10, 13, 0
err_de_text db "Disk error", 10, 13, 0
err_ind_text db "Header not a directory", 10, 13, 0

%include "./programs/inc/sstd.inc"
USE_PRINT
