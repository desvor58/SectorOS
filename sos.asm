[BITS 16]
[ORG 0x7C00]

start:
    cli
        xor ax, ax
        mov ds, ax
        mov es, ax
        mov ax, 0x1000
        mov ss, ax
        mov sp, 0xFFFE
        
        mov di, 0x21 * 4
        mov si, int_table
        mov cx, 3
    .set_ivt:
        lodsw
        stosw
        mov ax, cs
        stosw
        loop .set_ivt
    sti
    push dx

    mov ax, 0x0600
    mov bh, 0x0F
    xor cx, cx
    mov dx, 0x184F
    int 0x10
    mov ah, 0x02
    xor bh, bh
    xor dx, dx
    int 0x10

    pop dx

    ; load FHT
    mov ah, 0x42
    mov si, DAP_struct
    int 0x13
    jc err_de

    mov word [DAP_struct.sec_ptr], 1
    mov word [DAP_struct.buf_ptr], 0x0600

    ; load SFSDD
    mov ah, 0x42
    mov si, DAP_struct
    int 0x13
    jc err_de

    mov [0x6FE], dl

    mov si, 0x602
    mov dx, 0x2000
    int 0x21

    cmp ah, 1
    jz err_fnf
    ja err_de
    cmp al, 'E'
    jnz err_wft

    mov ax, 0x2000
    mov ds, ax
    mov es, ax
    call 0x2000:0x0000
    
    mov ax, 0x0945  ; 0x45 - E
    jmp general_err

err_fnf:
    mov ax, 0x0946  ; 0x46 - F
    jmp general_err

err_de:
    mov ax, 0x0944  ; 0x44 - D
    jmp general_err

err_wft:
    mov ax, 0x0957  ; 0x57 - W

general_err:
    mov cx, 1
    mov bx, 0x04
    int 0x10
    mov ah, 0x0E
    int 0x10
    mov al, 0x0A
    int 0x10
    mov al, 0x0D
    int 0x10
    
    jmp $


; int 0x21
; in:       ds:si - name of file
;           dx - segment to writing
; out:      ah - err code
;                0 - ok
;        	       1 - fnf
;        	       2 - de
;                  3 - ind
;           al - file type
;           bx - file size in bytes
; destruct: es=0, ds=0, si, di, dx
int_get_file_text:
    push dx
    int 0x23
    pop dx
    test ah, ah
    jnz .err

    xor ax, ax
    mov ds, ax

    mov si, DAP_struct
    mov ax, [es:di + 12]
    mov [si + 8], ax
    mov ax, [es:di + 14]
    add ax, 0x1FF
    mov cl, 0x09
    shr ax, cl
    mov [si + 2], ax

    mov word [si + 4], 0
    mov word [si + 6], dx

    mov ah, 0x42
    mov dl, [0x6FE]
    int 0x13
    jc .err_de

    mov al, [es:di + 11]
    mov bx, [es:di + 14]
    xor ah, ah
    iret

.err_de:
    mov ah, 2
.err:
    iret

; int 0x22
; in:       ds:si - name of file
;           dx - segment for writing
;           cx - size of text in bytes
; out:      ah - err code
;                0 - ok
;                1 - fnf
;                2 - de
; destruct: es=0, ds=0, ax, cx, bx, si, di
int_set_file_text:
    push cx
        int 0x23
    pop cx
    test ah, ah
    jnz .err

    xor ax, ax
    mov ds, ax

    mov bx, [di + 14]
    add bx, 0x1FF
    push cx
        mov cl, 9
        shr bx, cl
    pop cx

    test bx, bx
    jnz .bx_not_null
    inc bx
.bx_not_null:

    mov [di + 14], cx

    add cx, 0x1FF
    mov cl, 9
    shr cx, cl

    cmp cx, bx
    ja .need_alloc
    mov bx, cx
    jmp .write

.need_alloc:
    push dx
    push bx
        push cx
            mov cx, [0x6FE]
            mov [di + 12], cx
        pop cx
        add [0x6FE], cx

        mov ax, 0x0301
        mov cx, 0x0002
        mov dl, [0x6FE]
        mov bx, 0x0600
        int 0x13

        mov cx, 0x0003
        mov bx, 0x0800
        int 0x13
    pop bx
    pop dx
    jc .err_de

.write:
    mov si, DAP_struct
    mov ax, [di + 12]
    mov [si + 8], ax
    mov [si + 2], bx

    mov word [si + 4], 0
    mov word [si + 6], dx
    
    mov ax, 0x4300
    mov dl, [0x6FE]
    int 0x13
    jc .err_de

    xor ah, ah
    iret

.err_de:
    mov ah, 2
.err:
    iret

; int 0x23
; in:       ds:si - name of file
; out:      ah - err code
;                0 - ok
;                1 - fnf
;                2 - de
;                3 - ind
;           es:di - file struct
; destruct: es, ax, bx, cx, si, di, dx
int_get_file_header:
    xor ax, ax
    mov es, ax
    mov di, 0x0800

.search_loop:
    cmp byte [es:di], 0
    jz .err_fnf

    xor bx, bx
.name_cmp_loop:
    cmp bx, 11
    ja .check_slash

    mov al, [si + bx]
    test al, al
    jz .search_done
.check_slash:
    cmp al, '/'
    jz .to_subdir
    cmp al, [es:di + bx]
    jnz .next_header
    
    inc bx
    jmp .name_cmp_loop

.next_header:
    add di, 0x10
    jmp .search_loop

.search_done:
.ok_end:
    xor ah, ah
    iret

.to_subdir:
    cmp byte [es:di + 11], 'D'
    jnz .err_ind

    add si, bx

    push ds
    push si
        xor ax, ax
        mov ds, ax
        mov si, DAP_struct
        mov byte [si + 2], 1
        mov word [si + 4], 0x0800
        mov word [si + 6], 0x0000
        mov ax, [di + 12]
        mov [si + 8], ax
        mov ah, 0x42
        mov dl, [0x6FE]
        int 0x13
        jc .de_fail
    pop si
    pop ds

    inc si
    int 0x23

    iret

.de_fail:
    pop si
    pop ds
    jmp .err_de
    
.err_fnf:
    mov ah, 1
    iret

.err_de:
    mov ah, 2
    iret

.err_ind:
    mov ah, 3
    iret

align 4
DAP_struct:
    .DAP_size db 0x10
    .res      db 0x00
    .sec_num  dw 1       ; + 2
    .buf_ptr  dw 0x0800  ; + 4
              dw 0x0000  ; + 6
    .sec_ptr  dq 2       ; + 8
    
int_table dw int_get_file_text
          dw int_set_file_text
          dw int_get_file_header

times 510 - ($ - $$) db 0
dw 0xAA55
