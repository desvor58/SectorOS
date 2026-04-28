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
        mov cx, 5
    .set_ivt:
        lodsw
        stosw
        mov ax, cs
        stosw
        loop .set_ivt
    sti

    mov ax, 0x0600
    mov bh, 0x0F
    xor cx, cx
    mov dx, 0x184F
    int 0x10
    mov ah, 0x02
    xor bh, bh
    xor dx, dx
    int 0x10

    ; load FHT
    mov ah, 0x42
    mov dl, 0x80
    mov si, DAP_struct
    int 0x13
    jc err_de
    
    mov word [DAP_struct.sec_ptr], 1
    mov word [DAP_struct.buf_ptr], 0x0600

    ; load SFSDD
    mov ah, 0x42
    mov dl, 0x80
    mov si, DAP_struct
    int 0x13
    jc err_de


shell_loop:
    xor ax, ax
    mov es, ax

    ; read to cmd
    mov di, 0x500
    int 0x22
    mov ah, 0x0E
    mov al, 0x0A
    int 0x10
    mov al, 0x0D
    int 0x10

    xor ax, ax
    mov ds, ax
    mov es, ax
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
    stosb
    mov si, 0x580
    mov dx, 0x2000
    int 0x23

    cmp ah, 1
    jz err_fnf
    cmp ah, 2
    jz err_de
    cmp al, 'E'
    jnz err_wft

    mov ax, 0x2000
    mov ds, ax
    call 0x2000:0x0000
    xor ax, ax
    mov ds, ax

    jmp shell_loop

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
    int 0x21
    jmp shell_loop


; 0x21
int_print:
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
    iret

; 0x22
int_read:
    xor cx, cx

.read:
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
    jmp .read

.done:
    mov byte [es:di], 0
    iret

.backspace:
    test cx, cx
    jz .read
    mov ah, 0x0E
    int 0x10
    mov al, ' '
    int 0x10
    mov al, 0x08
    int 0x10
    dec di
    dec cx
    jmp .read

; int 0x23
; in:       es:si - name of file
;           dx - segment to writing
; out:      ah - err code
;                0 - ok
;                1 - fnf
;                2 - de
;           al - file type
; destruct: ds, ax, bx, si, di
int_get_file_text:
    int 0x25
    test ah, ah
    jnz .err

    mov bl, byte [di + 11]

    mov ax, [di + 12]
    mov [DAP_struct.sec_ptr], ax
    mov ax, [di + 14]
    add ax, 0x1FF
    shr ax, 0x09
    mov [DAP_struct.sec_num], ax

    mov word [DAP_struct.buf_ptr], 0
    mov word [DAP_struct.buf_ptr + 2], dx

    mov ah, 0x42
    mov dl, 0x80
    mov si, DAP_struct
    int 0x13
    jc .err_de

    mov al, bl
    xor ah, ah
    iret

.err_de:
    mov ah, 2
.err:
    iret

; int 0x24
; in:       es:si - name of file
;           dx - segment for writing
;           cx - size of text in bytes
; out:      ah - err code
;                0 - ok
;                1 - fnf
;                2 - de
;           al - file type
; destruct: ds, ax, bx, si, di
int_set_file_text:
    int 0x25
    test ah, ah
    jnz .err

    mov ax, cx
    add ax, 0x1FF
    shr ax, 9

    mov bx, [di + 14]
    add bx, 0x1FF
    shr bx, 9

    cmp ax, bx
    ja .need_alloc
    jmp .write

.need_alloc:
    push dx
    push bx
        mov cx, [0x600]
        mov [di + 12], cx
        add [0x600], bx

        mov ax, 0x0201
        mov cx, 0x0002
        mov dx, 0x0080
        mov bx, 0x0600
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
    
    mov ah, 0x43
    mov dl, 0x80
    mov si, DAP_struct
    int 0x13
    jc .err_de

    xor ah, ah
    iret

.err_de:
    mov ah, 2
.err:
    iret

; int 0x25
; in:       es:si - name of file
; out:      ah - err code
;                0 - ok
;                1 - fnf
;           0x0000:di - file type
; destruct: ds, ax, bx, si, di
int_get_file_header:
    xor ax, ax
    mov ds, ax
    mov di, 0x0800
    mov bx, 11

.search_loop:
    cmp byte [di], 0
    jz .err_fnf

    push si
    push di
        call strcmp
    pop di
    pop si
    jnc .search_done

    add di, 0x10
    jmp .search_loop

.search_done:
    xor ah, ah
    iret
    
.err_fnf:
    mov ah, 1
    iret

; es:si    - 1 str
; ds:di    - 2 str
; bx       - max size
; ret      - set cf if err
; destruct - cx, di, si, al
strcmp:
    xor cx, cx
.ccmp:
    cmp cx, bx
    jz .neq
    
    mov al, [es:si]
    
    cmp al, [di]
    jnz .neq
    
    test al, al
    jz .eq
    
    inc si
    inc di
    inc cx
    jmp .ccmp
    
.neq:
    stc
    ret
    
.eq:
    clc
    ret

err_fnf_text   db "F", 10, 13, 0
err_de_text    db "D", 10, 13, 0
err_wft_text   db "W", 10, 13, 0

align 4
DAP_struct:
    .DAP_size db 0x10
    .res      db 0x00
    .sec_num  dw 1
    .buf_ptr  dw 0x0800
              dw 0x0000
    .sec_ptr  dq 2
    
int_table dw int_print
          dw int_read
          dw int_get_file_text
          dw int_set_file_text
          dw int_get_file_header

times 510 - ($ - $$) db 0
dw 0xAA55
