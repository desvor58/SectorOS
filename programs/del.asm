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
    push ds
        mov si, file
        int 0x23
    pop ds
    cmp ah, 1
    jz err_fnf
    ja err_de

    mov cx, 0x10
    xor ax, ax
clear_file_header:
    stosb
    loop clear_file_header

shift_header:
    cmp byte [es:di], 0
    jz end

    mov cx, 0x10
.lp:
    mov al, [es:di]
    mov [es:di - 0x10], al
    inc di
    loop .lp
    jmp shift_header

end:
    sub di, 0x10
    mov cx, 0x10
    xor ax, ax
clear_last_file_header:
    stosb
    loop clear_last_file_header


    mov ax, 0x0301
    mov cx, 0x0003
    mov dx, 0x0080
    mov bx, 0x0800
    int 0x13
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
