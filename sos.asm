[BITS 16]
[ORG 0x7C00]

start:
	cli
		xor ax, ax
		mov ds, ax
		mov es, ax
		mov ax, 0x2000
		mov ss, ax
		mov sp, 0xFFFE

		mov word [0x20 * 4], int_clear
		mov word [0x20 * 4 + 2], cs
		mov word [0x21 * 4], int_print
		mov word [0x21 * 4 + 2], cs
		mov word [0x22 * 4], int_read
		mov word [0x22 * 4 + 2], cs
	sti

	int 0x20

	mov si, hello
	mov bx, 0x0F
	int 0x21

	mov ah, 0x42
	mov dl, 0x80
	mov si, DAP_struct
	int 0x13

shell_loop:
	mov di, cmd
    mov cx, 32
    xor al, al
    rep stosb
    
	mov di, cmd
	mov dl , 0x0D
	int 0x22
	call printNL
	
.search_program:
    mov bx, 0x7E00          ; Начало таблицы секторов
.next_entry:
    cmp byte [bx], 0        ; Проверка на пустую запись
    jz .cmp_err_fnf
    
    mov si, bx              ; SI -> имя в таблице (11 байт)
    mov di, cmd             ; DI -> введенная команда
    mov cx, 11              ; Сравниваем строго 11 байт
.compare:
    mov al, [si]
    mov dl, [di]
    cmp al, dl
    jne .not_equal          ; Если символы разные — к следующей записи
    
    inc si
    inc di
    loop .compare
    
    jmp .end_cmp            ; Если 11 символов совпали

.not_equal:
    add bx, 0x10            ; Переходим к следующей записи (16 байт)
    cmp bx, 0x8000          ; Ограничение (конец прочитанного сектора)
    jl .next_entry

.cmp_err_fnf:
	mov si, err_fnf
	mov bx, 0x0F
	int 0x21
    jmp shell_loop

.end_cmp:
	push si
	push bx
	push ax
		mov si, hello
		mov bx, 0x0F
		int 0x21
	pop ax
	pop bx
	pop si

	mov ax, [bx + 12]
	mov [DAP_struct.sec_ptr], ax
	mov ax, [bx + 14]
	add ax, 511
	shr ax, 9
	mov [DAP_struct.sec_num], ax
	mov word [DAP_struct.buf_ptr], 0
	mov word [DAP_struct.buf_ptr + 2], 0x1000

	mov ah, 0x42
	mov dl, 0x80
	mov si, DAP_struct
	int 0x13

	mov ax, 0x1000
	mov ds, ax
	mov es, ax
	call 0x1000:0x0000
	xor ax, ax
	mov ds, ax
	mov es, ax

	jmp shell_loop


;0x20
int_clear:
	mov ax, 0x0600
	mov bh, 0x0F
	xor cx, cx
	mov dx, 0x184F
	int 0x10
	mov ah, 0x02
	xor bh, bh
	xor dx, dx
	int 0x10
	iret

; 0x21
int_print:
	mov ah, 0x0E
.put:
	lodsb
	test al, al
	jz .done
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
	cmp al, dl
	jz .done
	cmp al, 0x08
	jz .backspace
	stosb
	mov ah, 0x0E
	int 0x10
	inc cx
	jmp .read

.done:
	mov [es:di], 0
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

printNL:
	mov ah, 0x0E
	mov al, 0x0A
	int 0x10
	mov al, 0x0D
	int 0x10
	ret

; es:si - 1 str
; ds:di - 2 str
; bx    - max size
; ret   - set cf if err
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

hello          db "Hello, from SectorOS",  10, 13, 0
err_fnf        db "ERROR: File not found", 10, 13, 0
cmd   times 32 db 0

DAP_struct:
	.DAP_size db 0x10
	.res      db 0x00
	.sec_num  dw 1
	.buf_ptr  dw 0x0200
			  dw 0x07C0
	.sec_ptr  dq 1

times 510 - ($ - $$) db 0
dw 0xAA55
