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
    mov cx, 11
    rep stosb

    mov si, file
    mov dx, 0x3000
    push ds
        int 0x21
    pop ds
    cmp ah, 1
    jz err_fnf
    ja err_de

    mov cx, bx

    mov ax, 0x3000
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

file times 32 db 0
err_fnf_text db "File not found", 10, 13, 0
err_de_text db "Disk error", 10, 13, 0
