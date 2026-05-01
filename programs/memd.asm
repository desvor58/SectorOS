[BITS 16]
[ORG 0x0000]

start:
    mov ax, 0x3000
    mov es, ax

    mov si, 0x000
    mov cx, 0x100

.lp:
    mov ax, [es:si]
    mov bl, ah
    mov ah, al
    mov al, bl
    call print_ax_hex
    add si, 2
    loop .lp

	retf
    
; ax - num
print_ax_hex:
    push bp
    mov bp, sp
    pusha

    sub sp, 6
    mov di, sp

    mov cx, 4
    mov bx, ax
.loop:
    rol bx, 4
    mov al, bl
    and al, 0Fh
    add al, '0'
    cmp al, '9'
    jbe .store
    add al, 7
.store:
    mov [di], al
    inc di
    loop .loop

    mov byte [di], 0

    mov si, sp
    mov bx, 0x0F
    call print
    add sp, 6
    popa
    pop bp
    ret

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