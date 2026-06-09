[BITS 16]
[ORG 0x0000]

sterm:
shell_loop:
    push ds
    push es

    mov di, comm
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

    push es
        xor ax, ax
        mov es, ax
        mov di, 0x500
        mov si, comm
        mov cx, 128
        rep movsb
    pop es

    mov si, comm
    mov di, prog
    mov cx, 11
.get_prog_loop:
    lodsb

    cmp al, ' '
    jbe .get_prog_done

    stosb
    dec cx
    jmp .get_prog_loop

.get_prog_done:
    xor ax, ax
    rep stosb

    mov si, prog
    mov dx, 0x3000
    int 0x21

    cmp ah, 1
    jz err_fnf
    ja err_de
    cmp al, 'E'
    jnz err_wft

    mov ax, 0x3000
    mov ds, ax
    mov es, ax
    call 0x3000:0x0000

    jmp goto_shell_loop
    retf


err_fnf:
    mov si, err_fnf_text
    jmp general_err

err_de:
    mov si, err_de_text
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

comm resb 128
prog resb 11

err_fnf_text db "File not found", 10, 13, 0
err_de_text db "Disk error", 10, 13, 0
err_wft_text db "Wrong file type", 10, 13, 0