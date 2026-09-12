[BITS 16]
[ORG 0x0000]

start:
	mov ax, 0x0600
	mov bh, 0x0F
	xor cx, cx
	mov dx, 0x184F
	int 0x10
	mov ah, 0x02
	xor bh, bh
	xor dx, dx
	int 0x10

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
    mov di, sec_num
    xor cx, cx
sec_num_cpy:
    mov al, [es:si]
    test al, al
    jz sec_num_cpy_done
    cmp al, ' '
    jz sec_num_cpy_done
    mov [di], al
    inc di
    inc si
    jmp sec_num_cpy

sec_num_cpy_done:
    mov di, rdsz
    xor cx, cx
rdsz_cpy:
    mov al, [es:si]
    test al, al
    jz rdsz_cpy_done
    cmp al, ' '
    jz rdsz_cpy_done
    mov [di], al
    inc di
    inc si
    jmp rdsz_cpy

rdsz_cpy_done:
    pop ds
    mov si, sec_num
    call num_to_ax

    mov cl, al

    mov ax, ds
    mov es, ax
    mov bx, sector
    mov ah, 0x02
    mov al, 0x01
    mov ch, 0x00
    mov dh, 0x00
    mov dl, 0x80
    int 0x13
    jc err_de

    mov cx, 256
    mov si, bx

    xor bx, bx
print_loop:
    mov ax, [si]

    xchg al, ah
    call print_ax_hex

    mov ah, 0x0E
    mov al, ' '
    int 0x10

    add si, 2
    inc bx
    cmp bx, 16
    jz .put_nl
    loop print_loop

.put_nl
    ; mov ah, 0x0E
    ; mov al, 0x0A
    ; int 0x10
    ; mov al, 0x0D
    ; int 0x10
    xor bx, bx
    loop print_loop

    retf

err_de:
    mov si, err_de_text
    mov bx, 0x04
    call print
    retf
    

; ds:si - str
num_to_ax:
    xor ax, ax
    mov bx, 10

.next_digit:
    movzx cx, byte [si]
    inc si

    cmp cl, '0'
    jb  .done
    cmp cl, '9'
    ja  .done

    sub cl, '0'
    mul bx
    add ax, cx
    jmp .next_digit

.done:
    ret

sec_num times 6 db 0
rdsz times 6 db 0
err_fnf_text db "File not found", 10, 13, 0
err_de_text db "Disk error", 10, 13, 0

sector times 512 db 0

%include "./programs/inc/sstd.inc"
USE_PRINT
USE_PRINT_AX_HEX
