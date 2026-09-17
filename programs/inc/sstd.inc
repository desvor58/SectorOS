%ifndef SSTD
%define SSTD

; %macro pusha 0
;     push ax
;     push cx
;     push dx
;     push bx
;     push sp
;     push bp
;     push si
;     push di
; %endmacro

; %macro popa 0
;     pop di
;     pop si
;     pop bp
;     pop bx  ; ignore the sp
;     pop bx
;     pop dx
;     pop cx
;     pop ax
; %endmacro

%macro USE_PRINT 0
    ; in: si - string
    print:
        push cx
        mov cx, 1
    .put:
        lodsb
        test al, al
        jz .done
        cmp al, 0x20
    .ctrlC:
        mov ah, 0x0E
        int 0x10
        jmp .put
    .done:
        pop cx
        ret
%endmacro


%macro USE_PRINT_AX_DEC 0
    print_ax_dec:
        push dx
        push si
        push bx
        push cx

        mov bx, 10
        xor cx, cx
    .gc:
        xor dx, dx
        div bx
        push dx
        inc cx
        test ax, ax
        jnz .gc
    .put:
        pop ax
        add al, '0'
        mov ah, 0x0E
        int 0x10
        loop .put
        
        pop cx
        pop bx
        pop si
        pop dx
        ret
%endmacro


%macro USE_PRINT_AX_HEX 0
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
%endmacro

%macro USE_PATH_TO_SFS_PATH 0
    ; ds:si- path
    ; es:di - buffer for sfs path
    path_to_sfs_path:
        pusha
        mov cx, 11

    .load_char:
        dec cx
        lodsb
        test al, al
        jz .done
        cmp al, '/'
        jz .next_dir
        stosb
        jmp .load_char

    .next_dir:
        xor al, al
        stosb
        loop .next_dir
        mov al, '/'
        stosb
        mov cx, 11
        jmp .load_char

    .done:
        xor al, al
        stosb
        loop .done
        stosb
        popa
        ret
%endmacro

%endif