[BITS 16]
[ORG 0x0000]

start:
    push ds
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
    mov al, [es:si]
    cmp al, ' '
    jnz type_cpy
    inc si
    jmp file_cpy_done

type_cpy:
    test al, al
    jz skip_type_cpy
    mov [type], al
skip_type_cpy:

    mov bx, 0x0F
    mov si, 0x0800
    xor ax, ax
    mov ds, ax

to_free_space_loop:
    cmp byte [si], 0
    jz to_free_space_done
    add si, 0x10
    jmp to_free_space_loop

to_free_space_done:
    pop ds
    mov ax, ds
    mov es, ax

    mov bx, FHT_sector
    mov ah, 0x02
    mov al, 0x01
    mov ch, 0x00
    mov dh, 0x00
    mov cl, 0x03
    mov dl, 0x80
    int 0x13
    jc err_de

    sub si, 0x800
    add si, FHT_sector

    mov di, file
    mov cx, 11
cpy_file_name:
    mov al, [di]
    mov [si], al
    inc si
    inc di
    loop cpy_file_name
    
    mov al, [type]
    mov [si], al

    push es
        mov ax, 0
        mov es, ax
        mov ax, [es:0x600]

        inc si
        mov [si], ax
        inc word [es:0x600]


        mov bx, 0x600
        mov ah, 0x03
        mov al, 0x01
        mov ch, 0x00
        mov dh, 0x00
        mov cl, 0x02
        mov dl, 0x80
        int 0x13
        jc err_de
    pop es

cpy_file_name_done:
    push ds
    push es
        mov si, FHT_sector
        mov ax, 0
        mov es, ax
        mov di, 0x800

        mov cx, 256
    cpy_new_FHT:
        lodsw
        stosw
        loop cpy_new_FHT
    pop es
    pop ds

    mov bx, FHT_sector
    mov ah, 0x03
    mov al, 0x01
    mov ch, 0x00
    mov dh, 0x00
    mov cl, 0x03
    mov dl, 0x80
    int 0x13
    jc err_de



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
type db 'F'
err_fnf_text db "File not found", 10, 13, 0
err_de_text db "Disk error", 10, 13, 0

FHT_sector times 512 db 0
