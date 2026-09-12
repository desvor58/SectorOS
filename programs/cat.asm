[BITS 16]
[ORG 0x0000]

start:
    xor ax, ax
    mov es, ax
    mov si, 0x500

skip_pn_loop:
    mov al, [es:si]
    cmp al, ' '
    jz to_args_loop
    inc si
    jmp skip_pn_loop

to_args_loop:
    mov al, [es:si]
    cmp al, ' '
    jnz args_done
    inc si
    jmp to_args_loop

args_done:
    mov di, file
    xor cx, cx
file_cpy:
    mov al, [es:si]
    test al, al
    jz file_cpy_done
    cmp al, ' '
    jz file_cpy_done
    mov [di], al
    inc di
    inc si
    jmp file_cpy

file_cpy_done:
    mov ax, ds
    mov es, ax
    mov si, file

    mov dx, 0x4000
    push ds
        int 0x21
    pop ds
    cmp ah, 1
    jz err_fnf
    ja err_de

    mov cx, bx

    mov ax, 0x4000
    mov es, ax
    mov si, 0
    mov ah, 0x0E
    
print_loop:
    mov al, [es:si]
    int 0x10
    inc si
    loop print_loop

print_done:
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

err_de:
    mov si, err_de_text
    mov bx, 0x04
    call print
    retf

file times 32 db 0
full_path times 48 db 0
err_fnf_text db "File not found", 10, 13, 0
err_de_text db "Disk error", 10, 13, 0

%include "./programs/inc/sstd.inc"
USE_PRINT
USE_PATH_TO_SFS_PATH
