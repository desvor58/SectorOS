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

    mov [0x602], dl

shell_loop:
    mov di, 0x500
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

    mov si, 0x500
    mov di, 0x580
.slice_loop:
    lodsb
    cmp al, ' '
    jbe .slice_done
    stosb
    jmp .slice_loop

.slice_done:
    xor al, al
    mov cx, 11
    rep stosb

    mov si, 0x580
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
    xor ax, ax
    mov ds, ax
    mov es, ax

    jmp shell_loop

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
    jmp shell_loop


; int 0x21
; in:       ds:si - name of file
;           dx - segment to writing
; out:      ah - err code
;                0 - ok
;        	       1 - fnf
;        	       2 - de
;           al - file type
;           bx - file size in bytes
; destruct: es=0, ds=0, si, di
int_get_file_text:
    int 0x23
    test ah, ah
    jnz .err

    xor ax, ax
    mov ds, ax

    mov ax, [di + 12]
    mov [DAP_struct.sec_ptr], ax
    mov ax, [di + 14]
    add ax, 0x1FF
    mov cl, 0x09
    shr ax, cl
    mov [DAP_struct.sec_num], ax

    mov word [DAP_struct.buf_ptr], 0
    mov word [DAP_struct.buf_ptr + 2], dx

    mov ah, 0x42
    mov dl, [0x602]
    mov si, DAP_struct
    int 0x13
    jc .err_de

    mov al, [di + 11]
    mov bx, [di + 14]
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
;           al - file type
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
        mov [di + 14], bx
        mov cx, [0x600]
        mov [di + 12], cx
        add [0x600], bx

        mov ax, 0x0301
        mov cx, 0x0002
        mov dx, 0x0080
        mov bx, 0x0600
        int 0x13

        mov ax, 0x0301
        mov cx, 0x0003
        mov dx, 0x0080
        mov bx, 0x0800
        int 0x13
    pop bx
    pop dx
    jc .err_de

.write:
    mov ax, [di + 12]
    mov [DAP_struct.sec_ptr], ax
    mov [DAP_struct.sec_num], bx

    mov word [DAP_struct.buf_ptr], 0
    mov word [DAP_struct.buf_ptr + 2], dx
    
    mov ax, 0x4300
    mov dl, [0x602]
    mov si, DAP_struct
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
;           es:di - file struct
; destruct: es, ax, bx, cx, si, di
int_get_file_header:
    xor ax, ax
    mov es, ax
    mov di, 0x0800

.search_loop:
    cmp byte [es:di], 0
    jz .err_fnf

    push si
    push di
        mov cx, 11
        repe cmpsb
    pop di
    pop si
    jz .search_done

    add di, 0x10
    jmp .search_loop

.search_done:
    xor ah, ah
    iret
    
.err_fnf:
    mov ah, 1
    iret


align 4
DAP_struct:
    .DAP_size db 0x10
    .res      db 0x00
    .sec_num  dw 1
    .buf_ptr  dw 0x0800
              dw 0x0000
    .sec_ptr  dq 2
    
int_table dw int_get_file_text
          dw int_set_file_text
          dw int_get_file_header

times 510 - ($ - $$) db 0
dw 0xAA55
